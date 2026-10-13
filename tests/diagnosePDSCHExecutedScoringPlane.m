function [trials,symbols,pilots] = diagnosePDSCHExecutedScoringPlane(capturePaths,trialCSV,outputRoot)
% Post-decode decomposition on actual captured DL IQ, never a receiver input.
% Bounded rank-one CFO/timing-only diagnostic, not statistical qualification.
arguments
    capturePaths (:,1) string
    trialCSV (1,1) string
    outputRoot (1,1) string
end
assert(isfolder(outputRoot),'Use an existing diagnostic output directory.');
source = sixgr.util.csvReadTable(trialCSV,'TextType','string');
trials = table(); symbols = table(); pilots = table();
for file = capturePaths.'
    saved = load(file,'ReceiverReplay'); c = saved.ReceiverReplay;
    rx = c.ReceiverResult;
    assert(c.Direction=="DL" && c.Contract=="exact_receiver_replay/v1" && ...
        ~c.CaptureUsedByReceiver && c.AdditionalChannelExecutions==0 && ...
        c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
    assert(isfield(c.Context,'ScoringOnlyDesiredWaveform') && ...
        ~c.Context.ScoringReferenceReceiverInput && c.Context.ScoringReferenceAdditionalChannelExecutions==0, ...
        'Retain the same executed desired waveform; do not regenerate a missing historical reference.');
    row = source(source.Slot==c.Context.Slot & ...
        source.ConfiguredSNR_dB==c.Context.ConfiguredSNR_dB,:);
    assert(height(row)==1 && row.Layers==1 && rx.PDSCH.NumLayers==1);
    % Do not interpret an unmodeled nonlinear RF residual as thermal noise.
    for field = ["IQImbalanceApplied","PhaseNoiseApplied","PAEnabled", ...
            "AGCApplied","ADCQuantizationApplied"]
        assert(ismember(field,string(row.Properties.VariableNames)) && row.(field)==0, ...
            'This decomposition requires recorded %s=false.',field);
    end
    assert(isequal(size(c.Waveform),size(c.Context.ScoringOnlyDesiredWaveform)));
    desired = c.Context.ScoringOnlyDesiredWaveform;
    % Algebraic replay of the recorded receive clock only, after decoding.
    % No second channel/RF execution; no fit to the decoded symbols.
    if logical(row.TimingOffsetApplied)
        desired = sixgr.util.applyFractionalSampleDelay(desired,row.InjectedTimingOffset_samples);
    end
    fs = double(rx.ReceiverChannelOperator.SampleRateHz);
    if logical(row.CFOApplied)
        desired = desired .* exp(2i*pi*row.InjectedCFO_Hz/fs*(0:size(desired,1)-1).');
    end
    actualGrid = localExecutedFFT(c.Waveform,rx);
    cleanGrid = localExecutedFFT(desired,rx);
    assert(isequal(size(actualGrid),size(rx.OFDMGrid)) && ...
        norm(actualGrid(:)-rx.OFDMGrid(:))/max(norm(rx.OFDMGrid(:)),eps)<1e-11, ...
        'Recorded receiver operations must reproduce the actual FFT grid.');
    actual = nrExtractResources(rx.PDSCHIndices,actualGrid);
    clean = nrExtractResources(rx.PDSCHIndices,cleanGrid);
    equalizer = rx.EqualizationInfo.EqualizerResult;
    W = reshape(equalizer.W,size(actual,1),size(actual,2));
    actualEqualized = sum(W.*actual,2);
    cleanEqualized = sum(W.*clean,2);
    reference = c.Context.ScoringOnlyTransmittedLayerSymbols;
    assert(isequal(size(reference),size(actualEqualized)) && ...
        isequal(c.Context.ScoringOnlyTransmittedLayerIndices,rx.PDSCHIndices) && ...
        norm(actualEqualized-rx.LayerSymbols)/max(norm(rx.LayerSymbols),eps)<1e-11, ...
        'Use the executed layer indices and equalizer, not a new or ideal receiver.');
    errorDesired = cleanEqualized-reference;
    % The difference includes added noise and any un-replayed RX operation.
    % Its name must not assert a pure-thermal-noise plane without that proof.
    errorRemainder = actualEqualized-cleanEqualized;
    % A second SCORING-ONLY pilot estimate isolates pilot observation noise.
    % It is not the executed receiver estimate, is never decoded, and is not
    % an exact channel operator (interpolation/aging/ICI can still be present).
    [pilotReference,~] = nrChannelEstimate(rx.Carrier,cleanGrid,rx.DMRSIndices, ...
        rx.DMRSSymbols,'CDMLengths',rx.ChannelEstimationInfo.CDMLengths, ...
        'AveragingWindow',rx.ReceiverConfig.ChannelEstimationAveragingWindow);
    pilotData = nrExtractResources(rx.PDSCHIndices,pilotReference);
    pilotWeight = conj(pilotData)./sum(abs(pilotData).^2,2);
    pilotOnlyScoring = sum(pilotWeight.*clean,2);
    % Counterfactual SCORING ONLY: remove the recorded injected CFO at the
    % capture origin while preserving the executed timing and spatial
    % operator. This isolates CFO-estimation error, not Doppler or channel
    % aging. No corrected samples/estimate enter a receiver or CRC decoder.
    knownCFORx = rx;
    knownCFORx.ReceiverChannelOperator.CaptureOriginCFOCorrection_Hz = ...
        double(row.InjectedCFO_Hz)*double(logical(row.CFOApplied));
    knownCFORx.ReceiverChannelOperator.AlignedOriginCFOCorrection_Hz = 0;
    knownCFOGrid = localExecutedFFT(desired,knownCFORx);
    [knownCFOPilot,~] = nrChannelEstimate(rx.Carrier,knownCFOGrid, ...
        rx.DMRSIndices,rx.DMRSSymbols, ...
        'CDMLengths',rx.ChannelEstimationInfo.CDMLengths, ...
        'AveragingWindow',rx.ReceiverConfig.ChannelEstimationAveragingWindow);
    knownCFOData = nrExtractResources(rx.PDSCHIndices,knownCFOGrid);
    knownCFOH = nrExtractResources(rx.PDSCHIndices,knownCFOPilot);
    knownCFOWeight = conj(knownCFOH)./sum(abs(knownCFOH).^2,2);
    knownCFOPilotScoring = sum(knownCFOWeight.*knownCFOData,2);
    K = size(actualGrid,1);
    symbol0 = mod(floor((double(rx.PDSCHIndices(:,1))-1)/K),rx.Carrier.SymbolsPerSlot);
    for symbol = [-1,unique(symbol0).']
        selected = true(size(symbol0));
        if symbol>=0, selected = symbol0==symbol; end
        d = errorDesired(selected); n = errorRemainder(selected); ref = reference(selected);
        total = mean(abs(d+n).^2); desiredPower = mean(abs(d).^2);
        noisePower = mean(abs(n).^2); cross = 2*real(mean(d.*conj(n)));
        assert(abs(total-desiredPower-noisePower-cross)<1e-11*max(total,eps), ...
            'The independently accumulated component powers must close including the cross term.');
        refPower = mean(abs(ref).^2);
        item = table(file,c.Context.Slot,c.Context.ConfiguredSNR_dB,symbol,nnz(selected), ...
            logical(rx.TBCRCPass),sqrt(total/refPower),sqrt(desiredPower/refPower), ...
            sqrt(noisePower/refPower),total,desiredPower,noisePower,cross, ...
            mean(rx.EqualizationInfo.PostEqualizationNoiseVariancePerResourceLayer(selected)), ...
            row.InjectedCFO_Hz,rx.CFOCorrectionApplied_Hz,false,false, ...
            'VariableNames',{'CaptureMAT','Slot','ConfiguredSNR_dB','Symbol0','DataRE', ...
            'CRCPass','TotalEVM_rms','DesiredOnlyErrorEVM_rms','WaveformRemainderEVM_rms', ...
            'TotalErrorPower','DesiredOnlyErrorPower','WaveformRemainderErrorPower','CrossTermPower', ...
            'DemapperVarianceMean','RecordedInjectedCFO_Hz','AppliedReceiverCFO_Hz', ...
            'ReferenceUsedByReceiver','StatisticallyQualified'});
        if symbol<0, trials=[trials;item]; else, symbols=[symbols;item]; end %#ok<AGROW>
        perfectPilotError = mean(abs(pilotOnlyScoring(selected)-ref).^2);
        knownCFOPilotError = mean(abs(knownCFOPilotScoring(selected)-ref).^2);
        pilotItem = table(file,c.Context.Slot,symbol,nnz(selected), ...
            sqrt(desiredPower/refPower),sqrt(perfectPilotError/refPower), ...
            sqrt(knownCFOPilotError/refPower), ...
            "scoring_only_noiseless_pilot_interpolation_not_true_channel",false,false, ...
            'VariableNames',{'CaptureMAT','Slot','Symbol0','DataRE', ...
            'ExecutedNoisyPilotDesiredOnlyEVM_rms','NoiselessPilotDesiredOnlyEVM_rms', ...
            'NoiselessPilotKnownCFOScoringEVM_rms', ...
            'ReferenceScope','ReferenceUsedByReceiver','CRCEvaluatedWithReference'});
        pilots=[pilots;pilotItem]; %#ok<AGROW>
    end
    % DesiredOnlyError includes the NOISY executed channel estimate and
    % frozen receiver corrections. It is not pure RF EVM or perfect-CSI NMSE.
    sixgr.util.csvWriteTable(fullfile(outputRoot,'dl_executed_error_decomposition.csv'), ...
        trials,'PreserveSchema',true,'RoundTripNumericText',true);
    sixgr.util.csvWriteTable(fullfile(outputRoot,'dl_executed_symbol_error_decomposition.csv'), ...
        symbols,'PreserveSchema',true,'RoundTripNumericText',true);
    sixgr.util.csvWriteTable(fullfile(outputRoot,'dl_noiseless_pilot_scoring_only.csv'), ...
        pilots,'PreserveSchema',true,'RoundTripNumericText',true);
end
end

function grid = localExecutedFFT(wave,rx)
op = rx.ReceiverChannelOperator; fs = double(op.SampleRateHz);
wave = wave.*exp(-2i*pi*double(op.CaptureOriginCFOCorrection_Hz)/fs*(0:size(wave,1)-1).');
wave = wave*conj(op.ReceiveCombiningMatrix);
assert(startsWith(string(op.TimingApplicationPolicy),"signed_waveform_shift") || ...
    any(string(op.TimingApplicationPolicy)==["timing_estimation_bypassed_no_runtime_correction", ...
    "timing_estimate_unavailable_no_runtime_correction"]), ...
    'This isolated diagnostic does not reconstruct a shared capture boundary.');
wave = sixgr.util.applyFractionalSampleDelay(wave,-double(op.AppliedTimingCorrection_samples));
wave = wave.*exp(-2i*pi*double(op.AlignedOriginCFOCorrection_Hz)/fs*(0:size(wave,1)-1).');
grid = sixgr.phy.waveform.ofdmDemodulate(rx.Carrier,wave, ...
    'Nfft',rx.OFDMInfo.Nfft,'SampleRate',rx.OFDMInfo.SampleRate, ...
    'CyclicPrefixFraction',rx.OFDMInfo.CyclicPrefixFraction);
end
