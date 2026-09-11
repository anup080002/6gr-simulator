function snapshot = buildPHYSignalDiagnosticSnapshot(cfg, direction, tx, rxWave, rx, constellationT, context, existingSnapshot)
%BUILDPHYSIGNALDIAGNOSTICSNAPSHOT Capture one bounded, same-trial PHY diagnostic.
%
% The snapshot is intentionally built while the actual TX waveform, channel
% output, receiver channel estimate, received data REs, and aligned
% constellation evidence are all available.  It never reconstructs missing
% evidence from configured SNR, trial aggregates, or downsampled previews.

if nargin < 7 || ~isstruct(context)
    context = struct();
end
direction = upper(strtrim(string(direction)));
if nargin >= 8 && isstruct(existingSnapshot) && ...
        logical(sixgr.util.structGet(existingSnapshot,"Available",false))
    snapshot=localAugmentExecutedChannelEvidence(existingSnapshot,direction,context);
    return;
end
snapshot = localEmptySnapshot(direction);

if ~logical(sixgr.util.structGet(cfg, "outputs.phySignalDiagnosticEnabled", false))
    snapshot.Reason = string(sixgr.util.structGet(cfg, ...
        "outputs.phySignalDiagnosticUnavailableReason", "capture_disabled_by_config"));
    if strlength(strtrim(snapshot.Reason)) == 0
        snapshot.Reason = "capture_disabled_by_config";
    end
    return;
end
if ~any(direction == ["DL","UL"])
    snapshot.Reason = "unsupported_direction";
    return;
end

txWave = localFirstWaveformColumn(sixgr.util.structGet(tx, "Waveform", []));
rxWave = localFirstWaveformColumn(rxWave);
nAvailable = min(numel(txWave), numel(rxWave));
minWaveformSamples = 64;
if nAvailable < minWaveformSamples
    snapshot.Reason = "contiguous_tx_rx_waveform_unavailable";
    return;
end

sampleRateHz = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "SampleRate_Hz", NaN), ...
    sixgr.util.structGet(tx, "OFDMInfo.SampleRate", NaN), ...
    sixgr.util.structGet(tx, "OFDM.SampleRate", NaN));
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    snapshot.Reason = "waveform_sample_rate_unavailable";
    return;
end

hest = sixgr.util.structGet(rx, "ChannelEstimate", []);
channelSource = string(sixgr.util.structGet(rx, "ChannelEstimateSource", ""));
channelMethod = string(sixgr.util.structGet(rx, "ChannelEstimateMethod", ""));
channelModel = localChannelModel(cfg);
delayProfile = localDelayProfile(cfg, channelModel);
if strlength(strtrim(channelModel)) == 0
    snapshot.Reason = "channel_model_provenance_unavailable";
    return;
end
if isempty(hest)
    snapshot.Reason = "receiver_channel_estimate_unavailable";
    return;
end
if strlength(strtrim(channelSource)) == 0 || strlength(strtrim(channelMethod)) == 0
    snapshot.Reason = "receiver_channel_estimator_provenance_incomplete";
    return;
end
if localHasForbiddenEvidenceToken(channelSource + "|" + channelMethod)
    snapshot.Reason = "receiver_channel_estimate_has_forbidden_provenance";
    return;
end
if localIsFadingChannel(channelModel, delayProfile)
    if numel(hest) <= 1 || size(hest, 1) <= 1
        snapshot.Reason = "fading_channel_requires_grid_shaped_hest";
        return;
    end
    lowerSource = lower(channelSource + "|" + channelMethod);
    if contains(lowerSource, "awgn") || contains(lowerSource, "unit_channel") || contains(lowerSource, "flat_validation")
        snapshot.Reason = "fading_channel_hest_uses_awgn_shortcut";
        return;
    end
end

[hSlice, hSubcarrier, hSymbolIndex] = localSelectChannelEstimateSlice(hest, cfg);
finiteH = isfinite(real(hSlice)) & isfinite(imag(hSlice));
hSlice = hSlice(finiteH);
hSubcarrier = hSubcarrier(finiteH);
if isempty(hSlice)
    snapshot.Reason = "receiver_channel_estimate_has_no_finite_grid_samples";
    return;
end

if direction == "DL"
    preEq = sixgr.util.structGet(rx, "PDSCHRxSymbolsForEvidence", []);
else
    preEq = sixgr.util.structGet(rx, "PUSCHRxSymbolsForEvidence", []);
end
preEq = localFirstWaveformColumn(preEq);
preMask = isfinite(real(preEq)) & isfinite(imag(preEq));
preEq = preEq(preMask);
if isempty(preEq)
    snapshot.Reason = "pre_equalization_data_re_evidence_unavailable";
    return;
end

[constellationUse, constellationReason] = localSelectConstellationEvidence(constellationT);
if isempty(constellationUse)
    snapshot.Reason = constellationReason;
    return;
end

maxWaveformSamples = localBoundedInteger(cfg, "outputs.phySignalDiagnosticWaveformSamples", 1024, 64, 4096);
maxFFTLength = localBoundedInteger(cfg, "outputs.phySignalDiagnosticFFTLength", 1024, 64, 4096);
maxChannelPoints = localBoundedInteger(cfg, "outputs.phySignalDiagnosticChannelPoints", 1024, 8, 4096);
maxConstellationPoints = localBoundedInteger(cfg, "outputs.phySignalDiagnosticConstellationPoints", 512, 16, 2048);

nTime = min(nAvailable, maxWaveformSamples);
timeIndex = (1:nTime).';
time_s = (double(timeIndex) - 1) ./ sampleRateHz;
txTime = txWave(timeIndex);
rxTime = rxWave(timeIndex);

nFFTAvailable = min(nAvailable, maxFFTLength);
nFFT = 2 ^ floor(log2(double(nFFTAvailable)));
if nFFT < minWaveformSamples
    snapshot.Reason = "contiguous_waveform_window_too_short_for_fft";
    return;
end
[frequencyOffsetHz, txSpectrum_dB, rxSpectrum_dB] = localRelativeSpectrum( ...
    txWave(1:nFFT), rxWave(1:nFFT), sampleRateHz);

if numel(hSlice) > maxChannelPoints
    hKeep = unique(round(linspace(1, numel(hSlice), maxChannelPoints))).';
    hSlice = hSlice(hKeep);
    hSubcarrier = hSubcarrier(hKeep);
end
if numel(preEq) > maxConstellationPoints
    preEq = preEq(1:maxConstellationPoints);
end
if height(constellationUse) > maxConstellationPoints
    constellationUse = constellationUse(1:maxConstellationPoints, :);
end

meta = localMetadata(cfg, direction, tx, rx, context, constellationUse, ...
    sampleRateHz, nFFT, channelModel, delayProfile, channelSource, channelMethod, hSymbolIndex);
sourceT = localEmptySourceTable();

% Retain the exact sample ownership implied by the OFDM modulator metadata.
% These rows identify CP and useful-symbol samples in the same contiguous
% TX waveform captured below; they do not recreate an OFDM waveform from
% configuration.
ofdmRows = localOFDMSymbolSampleRows(meta, tx, txWave, nTime);
sourceT = [sourceT; ofdmRows]; %#ok<AGROW>

rows = localBaseRows(meta, "time_domain", "tx", numel(timeIndex));
rows.PointIndex = double(timeIndex);
rows.SampleIndex = double(timeIndex);
rows.XValue = time_s;
rows.YValue = abs(txTime);
rows.XUnit(:) = "s";
rows.YUnit(:) = "complex_baseband_amplitude";
rows.IValue = real(txTime);
rows.QValue = imag(txTime);
sourceT = [sourceT; rows]; %#ok<AGROW>

rows = localBaseRows(meta, "time_domain", "rx", numel(timeIndex));
rows.PointIndex = double(timeIndex);
rows.SampleIndex = double(timeIndex);
rows.XValue = time_s;
rows.YValue = abs(rxTime);
rows.XUnit(:) = "s";
rows.YUnit(:) = "complex_baseband_amplitude";
rows.IValue = real(rxTime);
rows.QValue = imag(rxTime);
sourceT = [sourceT; rows]; %#ok<AGROW>

postChannelWave = localFirstWaveformColumn(sixgr.util.structGet( ...
    context, "PostChannelWaveform", []));
if ~isempty(postChannelWave)
    nPostChannel = min(numel(postChannelWave), maxWaveformSamples);
    postChannelIndex = (1:nPostChannel).';
    postChannelTime_s = (double(postChannelIndex) - 1) ./ sampleRateHz;
    postChannelUse = postChannelWave(postChannelIndex);
    rows = localBaseRows(meta, "time_domain", "post_channel", nPostChannel);
    rows.PointIndex = double(postChannelIndex);
    rows.SampleIndex = double(postChannelIndex);
    rows.XValue = postChannelTime_s;
    rows.YValue = abs(postChannelUse);
    rows.XUnit(:) = "s";
    rows.YUnit(:) = "complex_baseband_amplitude_before_receiver_impairments";
    rows.IValue = real(postChannelUse);
    rows.QValue = imag(postChannelUse);
    rows.GridKind(:) = "exact_runtime_channel_output_waveform";
    rows.GridSHA256(:) = string(sixgr.util.structGet(context, ...
        "PostChannelWaveformSHA256", localComplexTensorHash(postChannelWave)));
    sourceT = [sourceT; rows]; %#ok<AGROW>
end

rows = localBaseRows(meta, "spectrum", "tx", numel(frequencyOffsetHz));
rows.PointIndex = (1:numel(frequencyOffsetHz)).';
rows.XValue = frequencyOffsetHz;
rows.YValue = txSpectrum_dB;
rows.XUnit(:) = "Hz_offset";
rows.YUnit(:) = "relative_magnitude_dB_common_reference";
sourceT = [sourceT; rows]; %#ok<AGROW>

% The inverse transform below is an explicitly bandwidth-limited impulse
% response of the receiver's own DM-RS channel estimate.  It is labelled
% Hhat(tau), never true H(tau), and does not consume channel-oracle state.
nHhat = numel(hSlice);
if nHhat >= 2 && isfinite(meta.SCS_kHz) && meta.SCS_kHz > 0
    hhatTau = ifft(ifftshift(hSlice(:)), nHhat);
    hhatDelay_s = (0:nHhat-1).' ./ (double(nHhat) .* double(meta.SCS_kHz) .* 1e3);
    rows = localBaseRows(meta, "estimated_channel_impulse_response", ...
        "receiver_hhat_tau_rx1_tx1", nHhat);
    rows.PointIndex = (1:nHhat).';
    rows.XValue = hhatDelay_s;
    rows.YValue = abs(hhatTau);
    rows.XUnit(:) = "s_excess_delay_bandlimited";
    rows.YUnit(:) = "estimated_channel_magnitude_linear";
    rows.IValue = real(hhatTau);
    rows.QValue = imag(hhatTau);
    rows.MagnitudeLinear = abs(hhatTau);
    rows.Magnitude_dB = 20 .* log10(max(rows.MagnitudeLinear, realmin));
    rows.PowerLinear = abs(hhatTau).^2;
    rows.Power_dB = 10 .* log10(max(rows.PowerLinear, realmin));
    rows.Phase_deg = rad2deg(angle(hhatTau));
    rows.WrappedPhase_rad = angle(hhatTau);
    rows.GridKind(:) = "receiver_estimated_bandlimited_impulse_response";
    rows.GridSHA256(:) = localComplexTensorHash(hhatTau);
    sourceT = [sourceT; rows]; %#ok<AGROW>
end

[truePathGain, truePathDelay_s, truePathStatus] = ...
    localSelectExecutedPathGain(context);
if truePathStatus == "available"
    nPath = numel(truePathGain);
    rows = localBaseRows(meta, "true_channel_impulse_response", ...
        "executed_path_gain_rx1_tx1", nPath);
    rows.PointIndex = (1:nPath).';
    rows.XValue = truePathDelay_s;
    rows.YValue = abs(truePathGain);
    rows.XUnit(:) = "s_excess_delay";
    rows.YUnit(:) = "executed_complex_path_gain_magnitude";
    rows.IValue = real(truePathGain);
    rows.QValue = imag(truePathGain);
    rows.MagnitudeLinear = abs(truePathGain);
    rows.Magnitude_dB = 20 .* log10(max(rows.MagnitudeLinear, realmin));
    rows.PowerLinear = abs(truePathGain).^2;
    rows.Power_dB = 10 .* log10(max(rows.PowerLinear, realmin));
    rows.Phase_deg = rad2deg(angle(truePathGain));
    rows.WrappedPhase_rad = angle(truePathGain);
    rows.GridKind(:) = "executed_runtime_channel_path_gain_tensor_slice";
    rows.GridSHA256(:) = string(sixgr.util.structGet(context, ...
        "RuntimeChannelPathGainsSHA256", localComplexTensorHash(truePathGain)));
    sourceT = [sourceT; rows]; %#ok<AGROW>

    if isfinite(meta.SCS_kHz) && meta.SCS_kHz > 0
        nFrequency = max(2, numel(hSlice));
        frequencyOffset_Hz = ((0:nFrequency-1).' - (nFrequency-1)./2) .* ...
            double(meta.SCS_kHz) .* 1e3;
        trueHf = exp(-1i .* 2 .* pi .* frequencyOffset_Hz .* ...
            reshape(truePathDelay_s, 1, [])) * reshape(truePathGain, [], 1);
        rows = localBaseRows(meta, "true_channel_frequency_response", ...
            "executed_h_f_rx1_tx1", nFrequency);
        rows.PointIndex = (1:nFrequency).';
        rows.XValue = frequencyOffset_Hz;
        rows.YValue = 20 .* log10(max(abs(trueHf), realmin));
        rows.XUnit(:) = "Hz_offset";
        rows.YUnit(:) = "executed_channel_magnitude_dB";
        rows.FrequencyOffset_Hz = frequencyOffset_Hz;
        if isfinite(meta.CarrierFrequency_Hz)
            rows.AbsoluteFrequency_Hz = meta.CarrierFrequency_Hz + frequencyOffset_Hz;
        end
        rows.IValue = real(trueHf);
        rows.QValue = imag(trueHf);
        rows.MagnitudeLinear = abs(trueHf);
        rows.Magnitude_dB = 20 .* log10(max(rows.MagnitudeLinear, realmin));
        rows.PowerLinear = abs(trueHf).^2;
        rows.Power_dB = 10 .* log10(max(rows.PowerLinear, realmin));
        rows.Phase_deg = rad2deg(unwrap(angle(trueHf)));
        rows.WrappedPhase_rad = angle(trueHf);
        rows.UnwrappedPhaseFrequency_rad = unwrap(angle(trueHf));
        rows.GridKind(:) = "frequency_response_from_executed_path_gains_and_delays";
        rows.GridSHA256(:) = localComplexTensorHash(trueHf);
        sourceT = [sourceT; rows]; %#ok<AGROW>
    end
end

angleRows = localExecutedRuntimeAngleRows(meta, context);
sourceT = [sourceT; angleRows]; %#ok<AGROW>

% Preserve the bounded executed path-gain tensor across time.  This is the
% actual tensor returned by the runtime fading object while filtering this
% waveform, never a configured PDP reconstruction or a receiver oracle.
[timeVaryingRows, dopplerRows] = ...
    localExecutedTimeVaryingChannelRows(meta, context);
sourceT = [sourceT; timeVaryingRows; dopplerRows]; %#ok<AGROW>

rows = localBaseRows(meta, "spectrum", "rx", numel(frequencyOffsetHz));
rows.PointIndex = (1:numel(frequencyOffsetHz)).';
rows.XValue = frequencyOffsetHz;
rows.YValue = rxSpectrum_dB;
rows.XUnit(:) = "Hz_offset";
rows.YUnit(:) = "relative_magnitude_dB_common_reference";
sourceT = [sourceT; rows]; %#ok<AGROW>

[hMagnitude_dB,hWrapped,hUnwrapped] = localMeasuredChannelPolar(hSlice);
hPhase_deg = hUnwrapped .* 180 ./ pi;
rows = localBaseRows(meta, "channel_estimate", "hest", numel(hSlice));
rows.PointIndex = (1:numel(hSlice)).';
rows.SubcarrierIndex = double(hSubcarrier);
rows.OFDMSymbolIndex(:) = double(hSymbolIndex);
rows.MatlabSubcarrierIndex = double(hSubcarrier) + 1;
rows.MatlabOFDMSymbolIndex(:) = double(hSymbolIndex) + 1;
startGrid = double(meta.NStartGrid);
if ~isfinite(startGrid)
    startGrid = 0;
end
rows.ResourceBlockIndex = startGrid + floor(double(hSubcarrier) ./ 12);
rows.SubcarrierInResourceBlock = mod(double(hSubcarrier), 12);
rows.XValue = double(hSubcarrier);
rows.YValue = hMagnitude_dB;
rows.XUnit(:) = "subcarrier_index";
rows.YUnit(:) = "channel_magnitude_dB";
rows.IValue = real(hSlice);
rows.QValue = imag(hSlice);
rows.MagnitudeLinear = abs(hSlice);
rows.Magnitude_dB = hMagnitude_dB;
rows.PowerLinear = abs(hSlice).^2;
rows.Power_dB = hMagnitude_dB;
rows.Phase_deg = hPhase_deg;
rows.WrappedPhase_rad = hWrapped;
rows.UnwrappedPhaseFrequency_rad = hUnwrapped;
rows.MagnitudeValueStatus(:) = "exact_receiver_estimate_log_magnitude";
rows.PhaseValueStatus(:) = "defined_nonzero_receiver_estimate";
zeroH = abs(hSlice)==0;
rows.MagnitudeValueStatus(zeroH) = "negative_infinity_exact_zero_receiver_estimate";
rows.PhaseValueStatus(zeroH) = "undefined_zero_receiver_estimate";
rows.GridKind(:) = "receiver_channel_estimate_frequency_slice";
rows.GridSHA256(:) = localComplexTensorHash(hSlice);
sourceT = [sourceT; rows]; %#ok<AGROW>

if logical(sixgr.util.structGet(cfg, ...
        "outputs.phySignalDiagnosticFullChannelGrid", false))
    fullGridRows = localFullChannelGridRows(meta, hest);
    sourceT = [sourceT; fullGridRows]; %#ok<AGROW>

    % Spatial correlation is calculated from that same measured Hest
    % tensor.  No configured correlation matrix is substituted.
    spatialRows = localMeasuredSpatialCorrelationRows(meta, hest);
    sourceT = [sourceT; spatialRows]; %#ok<AGROW>
end

equalizerRows = localEqualizerRows(meta, rx, maxChannelPoints);
sourceT = [sourceT; equalizerRows]; %#ok<AGROW>

rows = localBaseRows(meta, "pre_equalization_re_cloud", "rx_antenna_1", numel(preEq));
rows.PointIndex = (1:numel(preEq)).';
rows.XValue = real(preEq);
rows.YValue = imag(preEq);
rows.XUnit(:) = "received_data_re_I";
rows.YUnit(:) = "received_data_re_Q";
rows.IValue = real(preEq);
rows.QValue = imag(preEq);
sourceT = [sourceT; rows]; %#ok<AGROW>

eq = complex(double(constellationUse.EqualizedReal), double(constellationUse.EqualizedImag));
ref = complex(double(constellationUse.ReferenceSymbolReal), double(constellationUse.ReferenceSymbolImag));
hard = complex(nan(height(constellationUse), 1));
if all(ismember(["HardDecisionReal","HardDecisionImag"], string(constellationUse.Properties.VariableNames)))
    hard = complex(double(constellationUse.HardDecisionReal), double(constellationUse.HardDecisionImag));
elseif all(ismember(["DecisionReal","DecisionImag"], string(constellationUse.Properties.VariableNames)))
    hard = complex(double(constellationUse.DecisionReal), double(constellationUse.DecisionImag));
end
rows = localBaseRows(meta, "post_equalization_constellation", "layer_1", numel(eq));
rows.PointIndex = (1:numel(eq)).';
rows.XValue = real(eq);
rows.YValue = imag(eq);
rows.XUnit(:) = "normalized_equalized_I";
rows.YUnit(:) = "normalized_equalized_Q";
rows.IValue = real(eq);
rows.QValue = imag(eq);
rows.ReferenceI = real(ref);
rows.ReferenceQ = imag(ref);
rows.EqualizedI = real(eq);
rows.EqualizedQ = imag(eq);
rows.HardDecisionI = real(hard);
rows.HardDecisionQ = imag(hard);
sourceT = [sourceT; rows]; %#ok<AGROW>

decoderRows = localDecoderBERRows(meta, tx, rx);
sourceT = [sourceT; decoderRows]; %#ok<AGROW>

kpiRows = localKPIRows(meta);
sourceT = [sourceT; kpiRows]; %#ok<AGROW>

snapshot.Available = true;
snapshot.Reason = "";
snapshot.Direction = direction;
snapshot.SnapshotID = meta.SnapshotID;
snapshot.Metadata = meta;
snapshot.SourceTable = sourceT;
end

function snapshot=localAugmentExecutedChannelEvidence(snapshot,direction,context)
% Add channel-oracle arrays only after the practical receiver is complete.
% This mode cannot construct a receiver estimate and cannot influence CRC,
% CQI, PMI, equalization, or decoding.
assert(string(sixgr.util.structGet(snapshot,"Direction",""))==direction && ...
    isstruct(sixgr.util.structGet(snapshot,"Metadata",struct())) && ...
    istable(sixgr.util.structGet(snapshot,"SourceTable",table())), ...
    'sixgr:link:PHYDiagnosticAugmentIdentity', ...
    'Post-decode channel evidence must augment the same-direction actual PHY snapshot.');
meta=snapshot.Metadata;
sourceT=snapshot.SourceTable;
replacePanels=["true_channel_impulse_response","true_channel_frequency_response", ...
    "runtime_channel_angles","time_varying_channel_impulse_response","doppler_spectrum"];
sourceT=sourceT(~ismember(string(sourceT.Panel),replacePanels),:);
sourceT=sourceT(~(string(sourceT.Panel)=="time_domain" & ...
    string(sourceT.Series)=="post_channel"),:);
postChannelWave=localFirstWaveformColumn(sixgr.util.structGet( ...
    context,"PostChannelWaveform",[]));
if ~isempty(postChannelWave)
    txRows=sourceT(string(sourceT.Panel)=="time_domain" & string(sourceT.Series)=="tx",:);
    nPostChannel=min(numel(postChannelWave),height(txRows));
    assert(nPostChannel>0 && isfinite(meta.SampleRate_Hz) && meta.SampleRate_Hz>0, ...
        'sixgr:link:PostChannelDiagnosticClockUnavailable', ...
        'Post-channel augmentation requires the same bounded waveform clock as the actual trial snapshot.');
    postChannelIndex=(1:nPostChannel).';
    postChannelUse=postChannelWave(postChannelIndex);
    rows=localBaseRows(meta,"time_domain","post_channel",nPostChannel);
    rows.PointIndex=double(postChannelIndex);
    rows.SampleIndex=double(postChannelIndex);
    rows.XValue=(double(postChannelIndex)-1)./double(meta.SampleRate_Hz);
    rows.YValue=abs(postChannelUse);
    rows.XUnit(:)="s";
    rows.YUnit(:)="complex_baseband_amplitude_before_receiver_impairments";
    rows.IValue=real(postChannelUse);
    rows.QValue=imag(postChannelUse);
    rows.GridKind(:)="exact_runtime_channel_output_waveform";
    rows.GridSHA256(:)=string(sixgr.util.structGet(context, ...
        "PostChannelWaveformSHA256",localComplexTensorHash(postChannelWave)));
    sourceT=[sourceT;rows]; %#ok<AGROW>
end
[truePathGain,truePathDelay_s,truePathStatus]=localSelectExecutedPathGain(context);
assert(truePathStatus=="available", ...
    'sixgr:link:PHYDiagnosticExecutedChannelUnavailable', ...
    'A shared fading capture must provide actual path gains and delays after decoding.');
nPath=numel(truePathGain);
rows=localBaseRows(meta,"true_channel_impulse_response", ...
    "executed_path_gain_rx1_tx1",nPath);
rows.PointIndex=(1:nPath).';
rows.XValue=truePathDelay_s;
rows.YValue=abs(truePathGain);
rows.XUnit(:)="s_excess_delay";
rows.YUnit(:)="executed_complex_path_gain_magnitude";
rows.IValue=real(truePathGain);
rows.QValue=imag(truePathGain);
rows.MagnitudeLinear=abs(truePathGain);
rows.Magnitude_dB=20.*log10(max(rows.MagnitudeLinear,realmin));
rows.PowerLinear=abs(truePathGain).^2;
rows.Power_dB=10.*log10(max(rows.PowerLinear,realmin));
rows.Phase_deg=rad2deg(angle(truePathGain));
rows.WrappedPhase_rad=angle(truePathGain);
rows.GridKind(:)="executed_runtime_channel_path_gain_tensor_slice";
rows.GridSHA256(:)=string(sixgr.util.structGet(context, ...
    "RuntimeChannelPathGainsSHA256",localComplexTensorHash(truePathGain)));
sourceT=[sourceT;rows]; %#ok<AGROW>

if isfinite(meta.SCS_kHz) && meta.SCS_kHz>0
    channelRows=sourceT(string(sourceT.Panel)=="channel_estimate",:);
    nFrequency=max(2,height(channelRows));
    frequencyOffset_Hz=((0:nFrequency-1).'-(nFrequency-1)./2).*double(meta.SCS_kHz).*1e3;
    trueHf=exp(-1i.*2.*pi.*frequencyOffset_Hz.*reshape(truePathDelay_s,1,[]))* ...
        reshape(truePathGain,[],1);
    rows=localBaseRows(meta,"true_channel_frequency_response", ...
        "executed_h_f_rx1_tx1",nFrequency);
    rows.PointIndex=(1:nFrequency).';
    rows.XValue=frequencyOffset_Hz;
    rows.YValue=20.*log10(max(abs(trueHf),realmin));
    rows.XUnit(:)="Hz_offset";
    rows.YUnit(:)="executed_channel_magnitude_dB";
    rows.FrequencyOffset_Hz=frequencyOffset_Hz;
    if isfinite(meta.CarrierFrequency_Hz)
        rows.AbsoluteFrequency_Hz=meta.CarrierFrequency_Hz+frequencyOffset_Hz;
    end
    rows.IValue=real(trueHf);
    rows.QValue=imag(trueHf);
    rows.MagnitudeLinear=abs(trueHf);
    rows.Magnitude_dB=20.*log10(max(rows.MagnitudeLinear,realmin));
    rows.PowerLinear=abs(trueHf).^2;
    rows.Power_dB=10.*log10(max(rows.PowerLinear,realmin));
    rows.Phase_deg=rad2deg(unwrap(angle(trueHf)));
    rows.WrappedPhase_rad=angle(trueHf);
    rows.UnwrappedPhaseFrequency_rad=unwrap(angle(trueHf));
    rows.GridKind(:)="frequency_response_from_executed_path_gains_and_delays";
    rows.GridSHA256(:)=localComplexTensorHash(trueHf);
    sourceT=[sourceT;rows]; %#ok<AGROW>
end
sourceT=[sourceT;localExecutedRuntimeAngleRows(meta,context)]; %#ok<AGROW>
[timeRows,dopplerRows]=localExecutedTimeVaryingChannelRows(meta,context);
sourceT=[sourceT;timeRows;dopplerRows]; %#ok<AGROW>
sourceT=localBindExecutedChannelProvenance(sourceT,context,direction);
snapshot.SourceTable=sourceT;
end

function T=localBindExecutedChannelProvenance(T,context,direction)
% Flatten the exact post-decode channel identity onto every row from this
% one trial.  These values originate in exportSharedChannelObservation's
% captured processor segment; no configured channel values are used.
if isempty(T)
    return;
end
linkKey=strtrim(string(sixgr.util.structGet(context,"RuntimeChannelLinkKey","")));
stateKey=strtrim(string(sixgr.util.structGet(context,"RuntimeChannelStateKey","")));
assert(strlength(linkKey)>0 && strlength(stateKey)>0, ...
    'sixgr:link:PHYDiagnosticChannelIdentityUnavailable', ...
    'Post-decode PHY diagnostics require the exact executed link and channel-state keys.');

angleAvailable=logical(sixgr.util.structGet(context, ...
    "RuntimeChannelAngleEvidenceAvailable",false));
angleFrame=strtrim(string(sixgr.util.structGet(context, ...
    "RuntimeChannelAngleCoordinateFrame","")));
angleSource=strtrim(string(sixgr.util.structGet(context, ...
    "RuntimeChannelAngleEvidenceSource","")));
if angleAvailable
    assert(strlength(angleFrame)>0 && strlength(angleSource)>0, ...
        'sixgr:link:PHYDiagnosticAngleProvenanceUnavailable', ...
        'Executed channel angles require their runtime coordinate frame and evidence source.');
end

reciprocityExact=logical(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocityExact",false));
reciprocityDirection=strtrim(string(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocityDirection","")));
reciprocitySource=strtrim(string(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocitySource","")));
reciprocityMode=strtrim(string(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocityApproximationMode","")));
if reciprocityExact
    assert(reciprocityDirection==direction && strlength(reciprocitySource)>0 && ...
        strlength(reciprocityMode)>0, ...
        'sixgr:link:PHYDiagnosticReciprocityProvenanceUnavailable', ...
        'Exact runtime reciprocity requires matching direction, source, and approximation-mode evidence.');
end

T.RuntimeChannelLinkKey(:)=linkKey;
T.RuntimeChannelStateKey(:)=stateKey;
T.AngleCoordinateFrame(:)=angleFrame;
T.AngleEvidenceSource(:)=angleSource;
T.RuntimeChannelReciprocityExact(:)=reciprocityExact;
T.RuntimeChannelReciprocityDirection(:)=reciprocityDirection;
T.RuntimeChannelReciprocitySource(:)=reciprocitySource;
T.RuntimeChannelReciprocityApproximationMode(:)=reciprocityMode;
end

function snapshot = localEmptySnapshot(direction)
snapshot = struct( ...
    "Available", false, ...
    "Reason", "capture_not_attempted", ...
    "Direction", string(direction), ...
    "SnapshotID", "", ...
    "Metadata", struct(), ...
    "SourceTable", localEmptySourceTable());
end

function x = localFirstWaveformColumn(x)
if isempty(x)
    x = complex([]);
    return;
end
if iscell(x)
    try
        x = x{1};
    catch
        x = [];
    end
end
if isempty(x)
    x = complex([]);
    return;
end
if ismatrix(x) && size(x, 2) > 1
    x = x(:, 1);
end
x = x(:);
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    candidate = varargin{i};
    try
        candidate = double(candidate);
    catch
        continue;
    end
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function value = localBoundedInteger(cfg, path, fallback, lowerBound, upperBound)
value = double(sixgr.util.structGet(cfg, path, fallback));
if ~(isscalar(value) && isfinite(value))
    value = fallback;
end
value = min(upperBound, max(lowerBound, round(value)));
end

function model = localChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ...
    sixgr.util.structGet(cfg, "channels.model", ...
    sixgr.util.structGet(cfg, "channel.profile", ""))))));
end

function profile = localDelayProfile(cfg, channelModel)
model = upper(strtrim(string(channelModel)));
if startsWith(model, "TDL")
    profile = string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ...
        sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", "")))));
elseif startsWith(model, "CDL")
    profile = string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ...
        sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", "")))));
else
    profile = string(sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", channelModel)));
end
profile = upper(strtrim(profile));
end

function tf = localIsFadingChannel(model, profile)
token = upper(string(model) + "|" + string(profile));
tf = contains(token, "TDL") || contains(token, "CDL") || contains(token, "FADING");
end

function tf = localHasForbiddenEvidenceToken(text)
text = lower(strtrim(string(text)));
tf = any(contains(text, [ ...
    "fallback","synthetic","proxy","logistic","lut","oracle", ...
    "perfect","ideal","genie"]));
end

function [slice, subcarrier, symbolIndex] = localSelectChannelEstimateSlice(hest, cfg)
slice = complex([]);
subcarrier = [];
symbolIndex = NaN;
if isempty(hest)
    return;
end
hest = complex(double(hest));
if isvector(hest)
    hest = hest(:);
    k = numel(hest);
    l = 1;
    h3 = reshape(hest, k, l, 1);
else
    sz = size(hest);
    k = sz(1);
    l = sz(2);
    h3 = reshape(hest, k, l, []);
end
counts = zeros(l, 1);
for li = 1:l
    candidate = h3(:, li, 1);
    counts(li) = sum(isfinite(real(candidate)) & isfinite(imag(candidate)));
end
[~, matlabSymbolIndex] = max(counts);
if isempty(matlabSymbolIndex) || counts(matlabSymbolIndex) < 1
    slice = complex([]);
    subcarrier = [];
    symbolIndex = NaN;
    return;
end
slice = h3(:, matlabSymbolIndex, 1);
subcarrier = (0:k-1).';
symbolIndex = double(matlabSymbolIndex - 1);

% Preserve the receiver grid indexing convention. SCS is resolved by the
% exporter from metadata; no synthetic interpolation is performed here.
if localIsFadingChannel(localChannelModel(cfg), localDelayProfile(cfg, localChannelModel(cfg))) && k <= 1
    slice = complex([]);
    subcarrier = [];
end
end

function [frequencyOffsetHz, txDB, rxDB] = localRelativeSpectrum(tx, rx, sampleRateHz)
n = min(numel(tx), numel(rx));
tx = tx(1:n);
rx = rx(1:n);
if n == 1
    window = 1;
else
    window = 0.5 - 0.5 .* cos(2 .* pi .* (0:n-1).' ./ (n-1));
end
txFFT = fftshift(fft(tx .* window, n));
rxFFT = fftshift(fft(rx .* window, n));
commonReference = max([abs(txFFT(:)); abs(rxFFT(:))], [], "omitnan");
commonReference = max(commonReference, realmin);
txDB = 20 .* log10(max(abs(txFFT), realmin) ./ commonReference);
rxDB = 20 .* log10(max(abs(rxFFT), realmin) ./ commonReference);
frequencyOffsetHz = ((0:n-1).' - floor(n/2)) .* (sampleRateHz ./ n);
end

function [T, reason] = localSelectConstellationEvidence(T)
reason = "post_equalization_constellation_evidence_unavailable";
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
required = ["ReferenceSymbolReal","ReferenceSymbolImag","EqualizedReal","EqualizedImag"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    T = table();
    reason = "post_equalization_constellation_schema_incomplete";
    return;
end
if ismember("truth_status", string(T.Properties.VariableNames))
    truth = lower(strtrim(string(T.truth_status)));
elseif ismember("TruthStatus", string(T.Properties.VariableNames))
    truth = lower(strtrim(string(T.TruthStatus)));
else
    T = table();
    reason = "post_equalization_constellation_provenance_missing";
    return;
end
if any(truth ~= "real_lls_evidence")
    T = table();
    reason = "post_equalization_constellation_truth_status_invalid";
    return;
end
for provenanceField = ["Source","ExecutionBackend","ApproximationMode","Notes"]
    field = char(provenanceField);
    if ismember(provenanceField, string(T.Properties.VariableNames)) && ...
            any(localHasForbiddenEvidenceToken(string(T.(field))))
        T = table();
        reason = "post_equalization_constellation_provenance_conflict:" + provenanceField;
        return;
    end
end
mask = isfinite(double(T.ReferenceSymbolReal)) & isfinite(double(T.ReferenceSymbolImag)) & ...
    isfinite(double(T.EqualizedReal)) & isfinite(double(T.EqualizedImag));
if ismember("LayerIndex", string(T.Properties.VariableNames))
    layer = double(T.LayerIndex);
    finiteLayer = layer(isfinite(layer));
    if ~isempty(finiteLayer)
        mask = mask & layer == finiteLayer(1);
    end
end
T = T(mask, :);
if isempty(T)
    reason = "post_equalization_constellation_has_no_finite_symbol_pairs";
end
end

function meta = localMetadata(cfg, direction, tx, rx, context, constellationT, sampleRateHz, nFFT, channelModel, delayProfile, channelSource, channelMethod, hSymbolIndex)
meta = struct();
meta.Direction = string(direction);
userContext = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
meta.UEIndex = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "UEIndex", NaN), ...
    sixgr.util.structGet(userContext, "RuntimeUEIndex", ...
    sixgr.util.structGet(userContext, "UEIndex", NaN)));
meta.UEIdentitySource = string(sixgr.util.structGet(context, "UEIdentitySource", ""));
if strlength(strtrim(meta.UEIdentitySource)) == 0
    if isfinite(localFirstFiniteScalar(sixgr.util.structGet(context, "UEIndex", NaN)))
        meta.UEIdentitySource = "trial_context";
    elseif isfinite(localFirstFiniteScalar(sixgr.util.structGet(userContext, "RuntimeUEIndex", NaN)))
        meta.UEIdentitySource = "runtime_user_context";
    elseif isfinite(localFirstFiniteScalar(sixgr.util.structGet(userContext, "UEIndex", NaN)))
        meta.UEIdentitySource = "configured_user_context";
    end
end
if ~isfinite(meta.UEIndex)
    multiUserEnabled = logical(sixgr.util.structGet(cfg, "lls6g.users.enabled", false));
    numUsers = localFirstFiniteScalar(sixgr.util.structGet(cfg, "lls6g.users.n_users", 1));
    if ~multiUserEnabled || ~(isfinite(numUsers) && numUsers > 1)
        meta.UEIndex = 1;
        meta.UEIdentitySource = "standalone_single_user_default";
    end
end
meta.RNTI = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "RNTI", NaN), ...
    sixgr.util.structGet(userContext, "RNTI", NaN), ...
    sixgr.util.structGet(cfg, "phy.rnti", NaN));
meta.Frame = localFirstFiniteScalar(sixgr.util.structGet(context, "Frame", NaN));
meta.Slot = localFirstFiniteScalar(sixgr.util.structGet(context, "Slot", NaN));
meta.SFN = localFirstFiniteScalar(sixgr.util.structGet(context, "SFN", meta.Frame));
meta.CellID = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "CellID", NaN), ...
    sixgr.util.structGet(tx, "Carrier.NCellID", NaN), ...
    sixgr.util.structGet(cfg, "phy.nCellId", NaN), ...
    sixgr.util.structGet(cfg, "carrier.nCellId", NaN));
meta.SCS_kHz = localFirstFiniteScalar( ...
    sixgr.util.structGet(tx, "Carrier.SubcarrierSpacing", NaN), ...
    sixgr.util.structGet(tx, "Carrier.SubcarrierSpacing_kHz", NaN), ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", NaN), ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", NaN), ...
    sixgr.util.structGet(cfg, "channel.subcarrierSpacing_kHz", NaN), ...
    sixgr.util.structGet(cfg, "frame.scs_khz", NaN), ...
    sixgr.util.structGet(cfg, "frame.scs_kHz", NaN), ...
    sixgr.util.structGet(cfg, "carrier.scs_kHz", NaN));
meta.NStartGrid = localFirstFiniteScalar( ...
    sixgr.util.structGet(tx, "Carrier.NStartGrid", NaN), ...
    sixgr.util.structGet(cfg, "carrier.nStartGrid", 0));
meta.CarrierFrequency_Hz = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "CarrierFrequency_Hz", NaN), ...
    sixgr.util.structGet(cfg, "phy.fc_Hz", NaN), ...
    sixgr.util.structGet(cfg, "channel.fc_Hz", NaN), ...
    sixgr.util.structGet(cfg, "channel.carrierFrequencyHz", NaN), ...
    sixgr.util.structGet(cfg, "frequency.centerFrequencyHz", NaN), ...
    sixgr.util.structGet(cfg, "frequency.center_frequency_hz", NaN), ...
    sixgr.util.structGet(cfg, "global_radio_scope.carrier_frequency_hz", NaN), ...
    sixgr.util.structGet(cfg, "carrier.frequencyHz", NaN), ...
    1e9 .* sixgr.util.structGet(cfg, "frame.carrierFrequencyGHz", NaN));
if isfinite(meta.SCS_kHz) && meta.SCS_kHz > 0
    numerology = round(log2(meta.SCS_kHz ./ 15));
    meta.SlotsPerFrame = 10 .* (2 .^ numerology);
else
    meta.SlotsPerFrame = NaN;
end
if isfinite(meta.SFN) && isfinite(meta.Slot) && isfinite(meta.SlotsPerFrame)
    meta.AbsoluteSlot = meta.SFN .* meta.SlotsPerFrame + meta.Slot;
else
    meta.AbsoluteSlot = NaN;
end
meta.TBId = string(sixgr.util.structGet(context, "TBId", ""));
meta.LayerIndex = localFirstFiniteScalar(sixgr.util.structGet(context, "LayerIndex", 1));
meta.Layers = localFirstFiniteScalar(sixgr.util.structGet(context, "Layers", 1));
meta.RxAntennaIndex = 1;
meta.TxPortIndex = 1;
meta.ChannelModel = string(channelModel);
meta.DelayProfile = string(delayProfile);
meta.ChannelEstimateSource = string(channelSource);
meta.ChannelEstimateMethod = string(channelMethod);
meta.ChannelEstimateEngine = string(sixgr.util.structGet(rx, "ChannelEstimateEngine", ""));
meta.ChannelEstimateInterpolationMethod = string(sixgr.util.structGet(rx, "ChannelEstimateInterpolationMethod", ""));
meta.ChannelEstimateOFDMSymbolIndex = double(hSymbolIndex);
meta.Modulation = string(sixgr.util.structGet(context, "Modulation", ""));
if strlength(strtrim(meta.Modulation)) == 0 && ismember("Modulation", string(constellationT.Properties.VariableNames))
    meta.Modulation = string(constellationT.Modulation(1));
end
meta.MCSIndex = localFirstFiniteScalar(sixgr.util.structGet(context, "MCSIndex", NaN));
meta.ConfiguredSNR_dB = localFirstFiniteScalar(sixgr.util.structGet(context, "ConfiguredSNR_dB", NaN));
meta.ConfiguredSNRSource = string(sixgr.util.structGet(context, "ConfiguredSNRSource", "runner_configured_stimulus"));
meta.PostEqSINR_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "PostEqSINR_dB", NaN), ...
    sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
meta.PostEqSINRSource = string(sixgr.util.structGet(context, "PostEqSINRSource", ...
    sixgr.util.structGet(rx, "PostEqSINRSource", "")));
meta.PostEqSINRValueRole = string(sixgr.util.structGet(context, "PostEqSINRValueRole", ...
    sixgr.util.structGet(rx, "PostEqSINRValueRole", "")));
meta.EVM_rms_pct = 100 .* localFirstFiniteScalar(sixgr.util.structGet(context, "EVM_rms", NaN));
meta.CRCPass = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "CRCPass", NaN), ...
    sixgr.util.structGet(rx, "CRCPass", NaN));
meta.SampleRate_Hz = double(sampleRateHz);
meta.FFTLength = double(nFFT);
meta.CurveConstruction = "runtime_same_trial_phy_signal_snapshot";
meta.TruthStatus = "real_lls_evidence";
meta.SourceArtifact = "runtime_phy_arrays_same_trial";
meta.Status = "available";
meta.NAReason = "";
meta.SnapshotID = localSnapshotID(meta, cfg);
end

function id = localSnapshotID(meta, cfg)
runId = string(sixgr.util.structGet(cfg, "run.runId", ...
    sixgr.util.structGet(cfg, "run.runTag", ...
    sixgr.util.structGet(cfg, "meta.lls6gScenarioID", "run"))));
id = runId + "_" + meta.Direction + "_ue" + string(meta.UEIndex) + ...
    "_f" + string(meta.Frame) + "_s" + string(meta.Slot) + "_tb" + meta.TBId;
id = regexprep(id, "[^A-Za-z0-9_.-]", "_");
end

function T = localBaseRows(meta, panel, series, n)
T = table();
T.SnapshotID = repmat(string(meta.SnapshotID), n, 1);
T.Panel = repmat(string(panel), n, 1);
T.Series = repmat(string(series), n, 1);
T.PointIndex = nan(n, 1);
T.XValue = nan(n, 1);
T.YValue = nan(n, 1);
T.XUnit = strings(n, 1);
T.YUnit = strings(n, 1);
T.Direction = repmat(string(meta.Direction), n, 1);
T.UEIndex = repmat(double(meta.UEIndex), n, 1);
T.UEIdentitySource = repmat(string(meta.UEIdentitySource), n, 1);
T.RNTI = repmat(double(meta.RNTI), n, 1);
T.Frame = repmat(double(meta.Frame), n, 1);
T.Slot = repmat(double(meta.Slot), n, 1);
T.SFN = repmat(double(meta.SFN), n, 1);
T.AbsoluteSlot = repmat(double(meta.AbsoluteSlot), n, 1);
T.CellID = repmat(double(meta.CellID), n, 1);
T.SCS_kHz = repmat(double(meta.SCS_kHz), n, 1);
T.NStartGrid = repmat(double(meta.NStartGrid), n, 1);
T.CarrierFrequency_Hz = repmat(double(meta.CarrierFrequency_Hz), n, 1);
T.SlotsPerFrame = repmat(double(meta.SlotsPerFrame), n, 1);
T.TBId = repmat(string(meta.TBId), n, 1);
T.LayerIndex = repmat(double(meta.LayerIndex), n, 1);
T.Layers = repmat(double(meta.Layers), n, 1);
T.RxAntennaIndex = repmat(double(meta.RxAntennaIndex), n, 1);
T.TxPortIndex = repmat(double(meta.TxPortIndex), n, 1);
T.ChannelModel = repmat(string(meta.ChannelModel), n, 1);
T.DelayProfile = repmat(string(meta.DelayProfile), n, 1);
T.ChannelEstimateSource = repmat(string(meta.ChannelEstimateSource), n, 1);
T.ChannelEstimateMethod = repmat(string(meta.ChannelEstimateMethod), n, 1);
T.ChannelEstimateEngine = repmat(string(meta.ChannelEstimateEngine), n, 1);
T.ChannelEstimateInterpolationMethod = repmat(string(meta.ChannelEstimateInterpolationMethod), n, 1);
T.Modulation = repmat(string(meta.Modulation), n, 1);
T.MCSIndex = repmat(double(meta.MCSIndex), n, 1);
T.ConfiguredSNR_dB = repmat(double(meta.ConfiguredSNR_dB), n, 1);
T.ConfiguredSNRSource = repmat(string(meta.ConfiguredSNRSource), n, 1);
T.PostEqSINR_dB = repmat(double(meta.PostEqSINR_dB), n, 1);
T.PostEqSINRSource = repmat(string(meta.PostEqSINRSource), n, 1);
T.PostEqSINRValueRole = repmat(string(meta.PostEqSINRValueRole), n, 1);
T.EVM_rms_pct = repmat(double(meta.EVM_rms_pct), n, 1);
T.CRCPass = repmat(double(meta.CRCPass), n, 1);
T.SampleRate_Hz = repmat(double(meta.SampleRate_Hz), n, 1);
T.FFTLength = repmat(double(meta.FFTLength), n, 1);
T.SampleIndex = nan(n, 1);
T.SubcarrierIndex = nan(n, 1);
T.OFDMSymbolIndex = nan(n, 1);
T.MatlabSubcarrierIndex = nan(n, 1);
T.MatlabOFDMSymbolIndex = nan(n, 1);
T.ResourceBlockIndex = nan(n, 1);
T.SubcarrierInResourceBlock = nan(n, 1);
T.FrequencyOffset_Hz = nan(n, 1);
T.AbsoluteFrequency_Hz = nan(n, 1);
T.RxPortIndex0Based = nan(n, 1);
T.TxPortIndex0Based = nan(n, 1);
T.IValue = nan(n, 1);
T.QValue = nan(n, 1);
T.MagnitudeLinear = nan(n, 1);
T.Magnitude_dB = nan(n, 1);
T.MagnitudeValueStatus = strings(n, 1);
T.PhaseValueStatus = strings(n, 1);
T.PowerLinear = nan(n, 1);
T.Power_dB = nan(n, 1);
T.Phase_deg = nan(n, 1);
T.WrappedPhase_rad = nan(n, 1);
T.UnwrappedPhaseFrequency_rad = nan(n, 1);
T.UnwrappedPhaseTime_rad = nan(n, 1);
T.PhaseDeltaFrequency_rad = nan(n, 1);
T.PhaseDeltaTime_rad = nan(n, 1);
T.GridKind = strings(n, 1);
T.GridSHA256 = strings(n, 1);
T.SymbolSampleIndex = nan(n, 1);
T.CyclicPrefixLength_samples = nan(n, 1);
T.UsefulSymbolLength_samples = nan(n, 1);
T.IsCyclicPrefix = false(n, 1);
T.OFDMWindowingSamples = nan(n, 1);
T.TimeIndex = nan(n, 1);
T.Time_s = nan(n, 1);
T.PathIndex = nan(n, 1);
T.PathDelay_s = nan(n, 1);
T.DopplerFrequency_Hz = nan(n, 1);
T.AzimuthDeparture_deg = nan(n, 1);
T.AzimuthArrival_deg = nan(n, 1);
T.ZenithDeparture_deg = nan(n, 1);
T.ZenithArrival_deg = nan(n, 1);
T.AngleCoordinateFrame = strings(n, 1);
T.AngleEvidenceSource = strings(n, 1);
T.RuntimeChannelStateKey = strings(n, 1);
T.RuntimeChannelLinkKey = strings(n, 1);
T.RuntimeChannelSeed = nan(n, 1);
T.RuntimeChannelReciprocityExact = false(n, 1);
T.RuntimeChannelReciprocityDirection = strings(n, 1);
T.RuntimeChannelReciprocitySource = strings(n, 1);
T.RuntimeChannelReciprocityApproximationMode = strings(n, 1);
T.RuntimeChannelTransmitAndReceiveSwapped = false(n, 1);
T.MatrixRowIndex0Based = nan(n, 1);
T.MatrixColumnIndex0Based = nan(n, 1);
T.CorrelationDomain = strings(n, 1);
T.EqualizerREIndex = nan(n, 1);
T.EqualizerPostEqSINR_dB = nan(n, 1);
T.EqualizerAlgorithm = strings(n, 1);
T.DecoderStage = strings(n, 1);
T.BitErrors = nan(n, 1);
T.BitsCompared = nan(n, 1);
T.BER = nan(n, 1);
T.BitComparisonSource = strings(n, 1);
T.ReferenceI = nan(n, 1);
T.ReferenceQ = nan(n, 1);
T.EqualizedI = nan(n, 1);
T.EqualizedQ = nan(n, 1);
T.HardDecisionI = nan(n, 1);
T.HardDecisionQ = nan(n, 1);
T.KPIName = strings(n, 1);
T.KPINumericValue = nan(n, 1);
T.KPITextValue = strings(n, 1);
T.KPIUnit = strings(n, 1);
T.CurveConstruction = repmat(string(meta.CurveConstruction), n, 1);
T.truth_status = repmat(string(meta.TruthStatus), n, 1);
T.SourceArtifact = repmat(string(meta.SourceArtifact), n, 1);
T.Status = repmat(string(meta.Status), n, 1);
T.NAReason = repmat(string(meta.NAReason), n, 1);
end

function T = localFullChannelGridRows(meta, hest)
% Persist the exact receiver channel-estimate tensor without interpolation.
% NR coordinates are zero based; explicit MATLAB indices are retained so a
% consumer can address the original array without guessing conventions.
h4 = complex(double(hest));
sz = size(h4);
sz(end+1:4) = 1;
h4 = reshape(h4, sz(1), sz(2), sz(3), sz(4));
[kCount, symbolCount, rxCount, txCount] = size(h4);
[k0, l0, rx0, tx0] = ndgrid(0:kCount-1, 0:symbolCount-1, ...
    0:rxCount-1, 0:txCount-1);

[magnitudeDB,wrapped,unwrappedFrequency,unwrappedTime] = localMeasuredChannelPolar(h4);
deltaFrequency = nan(size(wrapped));
deltaTime = nan(size(wrapped));
if kCount > 1
    deltaFrequency(2:end,:,:,:) = diff(unwrappedFrequency, 1, 1);
end
if symbolCount > 1
    deltaTime(:,2:end,:,:) = diff(unwrappedTime, 1, 2);
end

n = numel(h4);
T = localBaseRows(meta, "channel_estimate_grid", ...
    "receiver_hest_exact_tensor", n);
T.PointIndex = (1:n).';
T.SubcarrierIndex = double(k0(:));
T.OFDMSymbolIndex = double(l0(:));
T.MatlabSubcarrierIndex = double(k0(:) + 1);
T.MatlabOFDMSymbolIndex = double(l0(:) + 1);
startGrid = double(meta.NStartGrid);
if ~isfinite(startGrid)
    startGrid = 0;
end
T.ResourceBlockIndex = startGrid + floor(double(k0(:)) ./ 12);
T.SubcarrierInResourceBlock = mod(double(k0(:)), 12);
scsHz = 1e3 .* double(meta.SCS_kHz);
if isfinite(scsHz) && scsHz > 0
    frequencyOffset = (double(k0(:)) - (double(kCount) - 1) ./ 2) .* scsHz;
    T.FrequencyOffset_Hz = frequencyOffset;
    if isfinite(double(meta.CarrierFrequency_Hz))
        T.AbsoluteFrequency_Hz = double(meta.CarrierFrequency_Hz) + frequencyOffset;
    end
end
T.RxPortIndex0Based = double(rx0(:));
T.TxPortIndex0Based = double(tx0(:));
T.RxAntennaIndex = double(rx0(:) + 1);
T.TxPortIndex = double(tx0(:) + 1);
T.XValue = T.SubcarrierIndex;
T.YValue = T.OFDMSymbolIndex;
T.XUnit(:) = "zero_based_subcarrier_index";
T.YUnit(:) = "zero_based_ofdm_symbol_index";
T.IValue = real(h4(:));
T.QValue = imag(h4(:));
T.MagnitudeLinear = abs(h4(:));
T.Magnitude_dB = magnitudeDB(:);
T.PowerLinear = abs(h4(:)).^2;
T.Power_dB = magnitudeDB(:);
T.MagnitudeValueStatus(:) = "exact_receiver_estimate_log_magnitude";
T.PhaseValueStatus(:) = "defined_nonzero_receiver_estimate";
zeroH = abs(h4(:))==0;
T.MagnitudeValueStatus(zeroH) = "negative_infinity_exact_zero_receiver_estimate";
T.PhaseValueStatus(zeroH) = "undefined_zero_receiver_estimate";
T.Phase_deg = rad2deg(wrapped(:));
T.WrappedPhase_rad = wrapped(:);
T.UnwrappedPhaseFrequency_rad = unwrappedFrequency(:);
T.UnwrappedPhaseTime_rad = unwrappedTime(:);
T.PhaseDeltaFrequency_rad = deltaFrequency(:);
T.PhaseDeltaTime_rad = deltaTime(:);
T.GridKind(:) = "receiver_channel_estimate";
T.GridSHA256(:) = localComplexTensorHash(h4);
end

function [magnitudeDB,wrapped,frequencyPhase,timePhase] = localMeasuredChannelPolar(h)
% Preserve the receiver tensor, including exact zeros. A zero has -Inf log
% magnitude and undefined phase, not an invented -6153 dB/zero-degree value.
% This is receiver-output visualization, not evidence that an unallocated
% resource has a physically zero propagation channel.
magnitudeDB=20.*log10(abs(h));
wrapped=angle(h);
wrapped(abs(h)==0 | ~isfinite(real(h)) | ~isfinite(imag(h)))=NaN;
frequencyPhase=localUnwrapDefinedPhase(wrapped,1);
timePhase=localUnwrapDefinedPhase(wrapped,2);
end

function phase=localUnwrapDefinedPhase(wrapped,dimension)
% Unwrap each contiguous defined segment; zero/unavailable REs cannot
% supply a phase reference or connect independently observed segments.
order=1:ndims(wrapped); order([1 dimension])=order([dimension 1]);
values=permute(wrapped,order); shape=size(values);
values=reshape(values,shape(1),[]);
for column=1:size(values,2)
    defined=isfinite(values(:,column));
    edges=diff([false;defined;false]); starts=find(edges==1); stops=find(edges==-1)-1;
    for segment=1:numel(starts)
        selected=starts(segment):stops(segment);
        values(selected,column)=unwrap(values(selected,column));
    end
end
phase=ipermute(reshape(values,shape),order);
end

function T = localOFDMSymbolSampleRows(meta, tx, txWave, maxSamples)
T = localEmptySourceTable();
ofdm = sixgr.util.structGet(tx, "OFDMInfo", ...
    sixgr.util.structGet(tx, "OFDM", struct()));
nfft = round(double(sixgr.util.structGet(ofdm, "Nfft", NaN)));
cp = round(double(sixgr.util.structGet(ofdm, "CyclicPrefixLengths", [])));
symbolLengths = round(double(sixgr.util.structGet(ofdm, "SymbolLengths", [])));
if isempty(symbolLengths) && isfinite(nfft) && nfft > 0 && ~isempty(cp)
    symbolLengths = nfft + cp;
end
symbolLengths = symbolLengths(:);
cp = cp(:);
if isempty(symbolLengths) || isempty(cp) || numel(cp) < numel(symbolLengths) || ...
        any(~isfinite(symbolLengths) | symbolLengths <= 0) || ...
        any(~isfinite(cp(1:numel(symbolLengths))) | cp(1:numel(symbolLengths)) < 0)
    return;
end
if ~(isfinite(nfft) && nfft > 0)
    useful = symbolLengths - cp(1:numel(symbolLengths));
    if isempty(useful) || any(useful <= 0) || any(useful ~= useful(1))
        return;
    end
    nfft = useful(1);
end
n = min([numel(txWave), maxSamples, sum(symbolLengths)]);
if n < 1
    return;
end
sample = (1:n).';
symbolIndex = nan(n, 1);
sampleWithin = nan(n, 1);
cpLength = nan(n, 1);
isCP = false(n, 1);
cursor = 1;
for symbol = 1:numel(symbolLengths)
    stop = min(n, cursor + symbolLengths(symbol) - 1);
    if stop < cursor
        break;
    end
    idx = (cursor:stop).';
    within = (0:numel(idx)-1).';
    symbolIndex(idx) = symbol - 1;
    sampleWithin(idx) = within;
    cpLength(idx) = cp(symbol);
    isCP(idx) = within < cp(symbol);
    cursor = stop + 1;
    if cursor > n
        break;
    end
end
valid = isfinite(symbolIndex);
sample = sample(valid);
symbolIndex = symbolIndex(valid);
sampleWithin = sampleWithin(valid);
cpLength = cpLength(valid);
isCP = isCP(valid);
wave = txWave(sample);
T = localBaseRows(meta, "ofdm_symbol_cp_samples", "tx", numel(sample));
T.PointIndex = double(sample);
T.SampleIndex = double(sample);
T.OFDMSymbolIndex = double(symbolIndex);
T.SymbolSampleIndex = double(sampleWithin);
T.CyclicPrefixLength_samples = double(cpLength);
T.UsefulSymbolLength_samples(:) = double(nfft);
T.IsCyclicPrefix = logical(isCP);
T.OFDMWindowingSamples(:) = double(sixgr.util.structGet(tx, ...
    "OFDMWindowingSamples", 0));
T.XValue = (double(sample) - 1) ./ double(meta.SampleRate_Hz);
T.YValue = abs(wave);
T.XUnit(:) = "s";
T.YUnit(:) = "complex_baseband_amplitude";
T.IValue = real(wave);
T.QValue = imag(wave);
T.GridKind(:) = "executed_tx_waveform_with_modulator_symbol_boundaries";
T.GridSHA256(:) = localComplexTensorHash(txWave);
end

function T = localExecutedRuntimeAngleRows(meta, context)
T = localEmptySourceTable();
if ~logical(sixgr.util.structGet(context, ...
        "RuntimeChannelAngleEvidenceAvailable", false))
    return;
end
[pathGain, pathDelay_s, pathStatus] = localSelectExecutedPathGain(context);
if pathStatus ~= "available"
    return;
end
angles = { ...
    double(sixgr.util.structGet(context, "RuntimeChannelAnglesAoD_deg", [])), ...
    double(sixgr.util.structGet(context, "RuntimeChannelAnglesAoA_deg", [])), ...
    double(sixgr.util.structGet(context, "RuntimeChannelAnglesZoD_deg", [])), ...
    double(sixgr.util.structGet(context, "RuntimeChannelAnglesZoA_deg", []))};
n = numel(pathGain);
if n < 1 || any(cellfun(@numel, angles) ~= n) || ...
        any(cellfun(@(v) any(~isfinite(v(:))), angles))
    return;
end
aoD = reshape(angles{1}, [], 1);
aoA = reshape(angles{2}, [], 1);
zoD = reshape(angles{3}, [], 1);
zoA = reshape(angles{4}, [], 1);
pathGain = reshape(pathGain, [], 1);
pathDelay_s = reshape(pathDelay_s, [], 1);

T = localBaseRows(meta, "runtime_channel_angles", ...
    "same_executed_path_gain_angles_rx1_tx1", n);
T.PointIndex = (1:n).';
T.PathIndex = (1:n).';
T.PathDelay_s = pathDelay_s;
T.XValue = aoD;
T.YValue = aoA;
T.XUnit(:) = "azimuth_departure_deg";
T.YUnit(:) = "azimuth_arrival_deg";
T.AzimuthDeparture_deg = aoD;
T.AzimuthArrival_deg = aoA;
T.ZenithDeparture_deg = zoD;
T.ZenithArrival_deg = zoA;
T.AngleCoordinateFrame(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelAngleCoordinateFrame", ""));
T.AngleEvidenceSource(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelAngleEvidenceSource", ""));
T.RuntimeChannelStateKey(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelStateKey", ""));
T.RuntimeChannelLinkKey(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelLinkKey", ""));
T.RuntimeChannelSeed(:) = double(sixgr.util.structGet(context, ...
    "RuntimeChannelSeed", NaN));
T.RuntimeChannelReciprocityExact(:) = logical(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocityExact", false));
T.RuntimeChannelReciprocityDirection(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocityDirection", ""));
T.RuntimeChannelReciprocitySource(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelReciprocitySource", ""));
T.RuntimeChannelReciprocityApproximationMode(:) = string(sixgr.util.structGet( ...
    context, "RuntimeChannelReciprocityApproximationMode", ""));
T.RuntimeChannelTransmitAndReceiveSwapped(:) = logical(sixgr.util.structGet( ...
    context, "RuntimeChannelTransmitAndReceiveSwapped", false));
T.IValue = real(pathGain);
T.QValue = imag(pathGain);
T.MagnitudeLinear = abs(pathGain);
T.Magnitude_dB = 20 .* log10(max(T.MagnitudeLinear, realmin));
T.PowerLinear = abs(pathGain).^2;
T.Power_dB = 10 .* log10(max(T.PowerLinear, realmin));
T.GridKind(:) = "angles_from_same_executed_runtime_channel_object";
T.GridSHA256(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelPathGainsSHA256", localComplexTensorHash(pathGain)));
end

function [timeRows, dopplerRows] = localExecutedTimeVaryingChannelRows(meta, context)
timeRows = localEmptySourceTable();
dopplerRows = localEmptySourceTable();
pathGains = sixgr.util.structGet(context, "RuntimeChannelPathGains", []);
sampleTimes = double(sixgr.util.structGet(context, ...
    "RuntimeChannelPathGainSampleTimes_s", []));
pathDelays = double(sixgr.util.structGet(context, "RuntimeChannelPathDelays_s", []));
if isempty(pathGains) || isempty(sampleTimes) || isempty(pathDelays)
    return;
end
sz = size(pathGains);
sz(end+1:4) = 1;
pathGains = reshape(complex(double(pathGains)), sz(1), sz(2), sz(3), sz(4));
if numel(sampleTimes) ~= sz(1) || numel(pathDelays) ~= sz(2) || sz(1) < 2
    return;
end
sampleTimes = sampleTimes(:);
pathDelays = pathDelays(:);
if any(~isfinite(sampleTimes)) || any(diff(sampleTimes) <= 0) || ...
        any(~isfinite(pathDelays))
    return;
end
% The immutable channel MAT artifact retains every coefficient sample.
% Bound only the tabular visualization plane so a slot-length MIMO CDL
% tensor cannot expand into a multi-gigabyte CSV. Uniform indices retain
% the complete observation time span; the Doppler calculation below still
% uses the full executed rx1/tx1 series.
fullPathGains=pathGains;
fullSampleTimes=sampleTimes;
maxTimeSamples=round(double(sixgr.util.structGet(context, ...
    "RuntimeChannelDiagnosticMaxTimeSamples",128)));
maxTimeSamples=max(4,min(1024,maxTimeSamples));
if sz(1)>maxTimeSamples
    keep=unique(round(linspace(1,sz(1),maxTimeSamples))).';
    pathGains=pathGains(keep,:,:,:);
    sampleTimes=sampleTimes(keep);
    sz=size(pathGains); sz(end+1:4)=1;
end
[time0, path0, tx0, rx0] = ndgrid(0:sz(1)-1, 0:sz(2)-1, ...
    0:sz(3)-1, 0:sz(4)-1);
gain = pathGains(:);
n = numel(gain);
timeRows = localBaseRows(meta, "time_varying_channel_impulse_response", ...
    "executed_path_gain_tensor", n);
timeRows.PointIndex = (1:n).';
timeRows.TimeIndex = double(time0(:));
timeRows.PathIndex = double(path0(:));
timeRows.TxPortIndex0Based = double(tx0(:));
timeRows.RxPortIndex0Based = double(rx0(:));
timeRows.TxPortIndex = double(tx0(:) + 1);
timeRows.RxAntennaIndex = double(rx0(:) + 1);
timeRows.Time_s = sampleTimes(time0(:) + 1);
timeRows.PathDelay_s = pathDelays(path0(:) + 1);
timeRows.XValue = timeRows.Time_s;
timeRows.YValue = timeRows.PathDelay_s;
timeRows.XUnit(:) = "s_runtime_channel_time";
timeRows.YUnit(:) = "s_excess_delay";
timeRows.IValue = real(gain);
timeRows.QValue = imag(gain);
timeRows.MagnitudeLinear = abs(gain);
timeRows.Magnitude_dB = 20 .* log10(max(abs(gain), realmin));
timeRows.PowerLinear = abs(gain).^2;
timeRows.Power_dB = 10 .* log10(max(timeRows.PowerLinear, realmin));
timeRows.WrappedPhase_rad = angle(gain);
timeRows.Phase_deg = rad2deg(angle(gain));
timeRows.GridKind(:) = "executed_runtime_channel_path_gain_tensor";
timeRows.GridSHA256(:) = string(sixgr.util.structGet(context, ...
    "RuntimeChannelPathGainsSHA256", localComplexTensorHash(pathGains)));

dt = median(diff(fullSampleTimes));
if ~(isfinite(dt) && dt > 0) || size(fullPathGains,1) < 4
    return;
end
pair = reshape(fullPathGains(:, :, 1, 1),size(fullPathGains,1),size(fullPathGains,2));
[~, strongestPath] = max(mean(abs(pair).^2, 1, "omitnan"));
series = pair(:, strongestPath);
if any(~isfinite(real(series)) | ~isfinite(imag(series)))
    return;
end
nFFT = 2 ^ nextpow2(numel(series));
window = 0.5 - 0.5 .* cos(2 .* pi .* (0:numel(series)-1).' ./ ...
    max(1, numel(series)-1));
spectrum = fftshift(fft(series .* window, nFFT));
power = abs(spectrum).^2;
freq = ((0:nFFT-1).' - floor(nFFT/2)) ./ (nFFT .* dt);
dopplerRows = localBaseRows(meta, "doppler_spectrum", ...
    "strongest_executed_path_rx1_tx1", nFFT);
dopplerRows.PointIndex = (1:nFFT).';
dopplerRows.PathIndex(:) = double(strongestPath - 1);
dopplerRows.DopplerFrequency_Hz = freq;
dopplerRows.XValue = freq;
dopplerRows.YValue = 10 .* log10(max(power, realmin));
dopplerRows.XUnit(:) = "Hz_doppler";
dopplerRows.YUnit(:) = "relative_power_dB";
dopplerRows.PowerLinear = power;
dopplerRows.Power_dB = dopplerRows.YValue;
dopplerRows.GridKind(:) = "fft_of_executed_runtime_path_gain_time_series";
dopplerRows.GridSHA256(:) = localComplexTensorHash(series);
end

function T = localMeasuredSpatialCorrelationRows(meta, hest)
T = localEmptySourceTable();
h4 = complex(double(hest));
sz = size(h4);
sz(end+1:4) = 1;
h4 = reshape(h4, sz(1), sz(2), sz(3), sz(4));
if any(~isfinite(real(h4(:))) | ~isfinite(imag(h4(:))))
    return;
end
rows = cell(0, 1);
rxObservations = reshape(permute(h4, [1 2 4 3]), [], sz(3));
rows{end+1,1} = localCorrelationRows(meta, rxObservations, ...
    "rx_port_correlation", "rx");
txObservations = reshape(h4, [], sz(4));
rows{end+1,1} = localCorrelationRows(meta, txObservations, ...
    "tx_port_correlation", "tx");
T = vertcat(rows{:});
end

function T = localCorrelationRows(meta, observations, seriesName, domain)
observations = complex(double(observations));
nPorts = size(observations, 2);
R = (observations' * observations) ./ max(1, size(observations, 1));
d = sqrt(max(real(diag(R)), eps));
R = R ./ max(d * d.', eps);
[row0, col0] = ndgrid(0:nPorts-1, 0:nPorts-1);
T = localBaseRows(meta, "spatial_correlation_matrix", seriesName, numel(R));
T.PointIndex = (1:numel(R)).';
T.MatrixRowIndex0Based = double(row0(:));
T.MatrixColumnIndex0Based = double(col0(:));
T.CorrelationDomain(:) = string(domain);
T.XValue = T.MatrixColumnIndex0Based;
T.YValue = T.MatrixRowIndex0Based;
T.XUnit(:) = "zero_based_matrix_column";
T.YUnit(:) = "zero_based_matrix_row";
T.IValue = real(R(:));
T.QValue = imag(R(:));
T.MagnitudeLinear = abs(R(:));
T.Phase_deg = rad2deg(angle(R(:)));
T.WrappedPhase_rad = angle(R(:));
T.GridKind(:) = "correlation_from_receiver_channel_estimate_samples";
T.GridSHA256(:) = localComplexTensorHash(R);
end

function T = localEqualizerRows(meta, rx, maxPoints)
T = localEmptySourceTable();
result = sixgr.util.structGet(rx, "EqualizerInfo.EqualizerResult", struct());
W = sixgr.util.structGet(result, "W", []);
sinr = double(sixgr.util.structGet(result, "PostEqSINRPerRE_dB", []));
if isempty(W) || isempty(sinr)
    return;
end
W = complex(double(W));
sz = size(W);
sz(end+1:3) = 1;
W = reshape(W, sz(1), sz(2), sz(3));
if size(sinr, 1) ~= sz(1) || size(sinr, 2) ~= sz(2)
    return;
end
keepRE = (1:min(sz(1), maxPoints)).';
W = W(keepRE, :, :);
sinr = sinr(keepRE, :);
[re0, layer0, rx0] = ndgrid(keepRE - 1, 0:sz(2)-1, 0:sz(3)-1);
weights = W(:);
T = localBaseRows(meta, "equalizer_weights", ...
    "executed_linear_equalizer", numel(weights));
T.PointIndex = (1:numel(weights)).';
T.EqualizerREIndex = double(re0(:));
T.LayerIndex = double(layer0(:) + 1);
T.RxPortIndex0Based = double(rx0(:));
T.RxAntennaIndex = double(rx0(:) + 1);
sinrByWeight = repmat(reshape(sinr, [], 1), sz(3), 1);
T.EqualizerPostEqSINR_dB = sinrByWeight;
T.XValue = T.EqualizerREIndex;
T.YValue = abs(weights);
T.XUnit(:) = "zero_based_data_re_index";
T.YUnit(:) = "equalizer_weight_magnitude";
T.IValue = real(weights);
T.QValue = imag(weights);
T.MagnitudeLinear = abs(weights);
T.Magnitude_dB = 20 .* log10(max(abs(weights), realmin));
T.WrappedPhase_rad = angle(weights);
T.Phase_deg = rad2deg(angle(weights));
T.EqualizerAlgorithm(:) = string(sixgr.util.structGet(result, ...
    "AlgorithmUsed", sixgr.util.structGet(rx, "EqualizerType", "")));
T.GridKind(:) = "executed_receiver_equalizer_weight_tensor";
T.GridSHA256(:) = localComplexTensorHash(W);
end

function T = localDecoderBERRows(meta, tx, rx)
T = localEmptySourceTable();
rows = cell(0, 1);
[codedBits, codedOK] = localBinaryVector(sixgr.util.structGet(tx, ...
    "Codewords", sixgr.util.structGet(tx, "Codeword", [])));
[llr, llrOK] = localNumericVector(sixgr.util.structGet(rx, ...
    "CodewordLLRCell", sixgr.util.structGet(rx, "CodewordLLR", [])));
if codedOK && llrOK && numel(codedBits) == numel(llr)
    rows{end+1,1} = localDecoderBERRow(meta, "pre_decoder_rate_matched", ...
        codedBits, int8(llr < 0), ...
        "tx_rate_matched_bits_vs_hard_descrambled_demapper_llr"); %#ok<AGROW>
end
[txTB, txOK] = localBinaryVector(sixgr.util.structGet(tx, ...
    "TransportBlocks", sixgr.util.structGet(tx, "TransportBlock", [])));
[rxTB, rxOK] = localBinaryVector(sixgr.util.structGet(rx, ...
    "TransportBlocks", sixgr.util.structGet(rx, "TransportBlock", [])));
if txOK && rxOK && numel(txTB) == numel(rxTB)
    rows{end+1,1} = localDecoderBERRow(meta, "post_decoder_transport_block", ...
        txTB, rxTB, "tx_transport_block_vs_receiver_decoded_transport_block"); %#ok<AGROW>
end
if ~isempty(rows)
    T = vertcat(rows{:});
end
end

function T = localDecoderBERRow(meta, stage, referenceBits, observedBits, source)
bitErrors = nnz(referenceBits ~= observedBits);
bitsCompared = numel(referenceBits);
T = localBaseRows(meta, "decoder_ber", stage, 1);
T.PointIndex = 1;
T.DecoderStage = string(stage);
T.BitErrors = double(bitErrors);
T.BitsCompared = double(bitsCompared);
T.BER = double(bitErrors) ./ double(bitsCompared);
T.BitComparisonSource = string(source);
T.XValue = 1;
T.YValue = T.BER;
T.XUnit = "decoder_stage";
T.YUnit = "bit_error_rate";
T.GridKind = "exact_aligned_runtime_bit_comparison";
T.GridSHA256 = localComplexTensorHash(double([referenceBits(:); observedBits(:)]));
end

function [value, ok] = localBinaryVector(value)
if iscell(value)
    try
        value = vertcat(value{:});
    catch
        value = [];
    end
end
try
    value = int8(value(:));
catch
    value = int8([]);
end
ok = ~isempty(value) && all(value == 0 | value == 1);
end

function [value, ok] = localNumericVector(value)
if iscell(value)
    try
        value = vertcat(value{:});
    catch
        value = [];
    end
end
try
    value = double(value(:));
catch
    value = [];
end
ok = ~isempty(value) && all(isfinite(value));
end

function digest = localComplexTensorHash(value)
bytes = [typecast(real(double(value(:))), "uint8"); ...
    typecast(imag(double(value(:))), "uint8")];
digest = sixgr.util.sha256Hex(bytes);
end

function [gain, delay_s, status] = localSelectExecutedPathGain(context)
gain = complex([]);
delay_s = [];
status = "unavailable";
pathGains = sixgr.util.structGet(context, "RuntimeChannelPathGains", []);
pathDelays = double(sixgr.util.structGet(context, "RuntimeChannelPathDelays_s", []));
if isempty(pathGains) || isempty(pathDelays)
    return;
end
sz = size(pathGains);
sz(end+1:4) = 1;
if sz(2) ~= numel(pathDelays)
    return;
end
pathGains = reshape(pathGains, sz(1), sz(2), sz(3), sz(4));
gain = reshape(pathGains(1,:,1,1), [], 1);
delay_s = reshape(pathDelays, [], 1);
finiteMask = isfinite(real(gain)) & isfinite(imag(gain)) & isfinite(delay_s);
gain = gain(finiteMask);
delay_s = delay_s(finiteMask);
if isempty(gain)
    gain = complex([]);
    delay_s = [];
    return;
end
status = "available";
end

function T = localKPIRows(meta)
names = [ ...
    "Direction","UEIndex","UE identity source","RNTI","Frame","Slot","TBId","ChannelModel","DelayProfile", ...
    "Modulation","MCSIndex","Layers","CRC pass","Configured SNR","Post-EQ SINR", ...
    "EVM RMS","Channel estimate source","Channel estimate method","Sample rate","FFT length"];
numeric = [ ...
    NaN,meta.UEIndex,NaN,meta.RNTI,meta.Frame,meta.Slot,NaN,NaN,NaN, ...
    NaN,meta.MCSIndex,meta.Layers,meta.CRCPass,meta.ConfiguredSNR_dB,meta.PostEqSINR_dB, ...
    meta.EVM_rms_pct,NaN,NaN,meta.SampleRate_Hz,meta.FFTLength].';
textValues = [ ...
    meta.Direction,"",meta.UEIdentitySource,"","","",meta.TBId,meta.ChannelModel,meta.DelayProfile, ...
    meta.Modulation,"","","","","","",meta.ChannelEstimateSource,meta.ChannelEstimateMethod,"",""].';
units = ["","","","","","","","","","","","","boolean","dB configured stimulus", ...
    "dB receiver-derived","percent","","","Hz","samples"].';
T = localBaseRows(meta, "kpi", "context", numel(names));
T.PointIndex = (1:numel(names)).';
T.XValue = T.PointIndex;
T.YValue = numeric;
T.XUnit(:) = "kpi_index";
T.YUnit = units;
T.KPIName = names.';
T.KPINumericValue = numeric;
T.KPITextValue = textValues;
T.KPIUnit = units;
end

function T = localEmptySourceTable()
meta = struct( ...
    "SnapshotID", "", "Direction", "", "UEIndex", NaN, "UEIdentitySource", "", "RNTI", NaN, ...
    "Frame", NaN, "Slot", NaN, "SFN", NaN, "AbsoluteSlot", NaN, "CellID", NaN, ...
    "TBId", "", "LayerIndex", NaN, "Layers", NaN, ...
    "RxAntennaIndex", NaN, "TxPortIndex", NaN, "ChannelModel", "", ...
    "DelayProfile", "", "ChannelEstimateSource", "", "ChannelEstimateMethod", "", ...
    "ChannelEstimateEngine", "", "ChannelEstimateInterpolationMethod", "", ...
    "Modulation", "", "MCSIndex", NaN, "ConfiguredSNR_dB", NaN, ...
    "ConfiguredSNRSource", "", "PostEqSINR_dB", NaN, "PostEqSINRSource", "", ...
    "PostEqSINRValueRole", "", "EVM_rms_pct", NaN, "CRCPass", NaN, ...
    "SampleRate_Hz", NaN, "FFTLength", NaN, ...
    "SCS_kHz", NaN, "NStartGrid", NaN, "CarrierFrequency_Hz", NaN, "SlotsPerFrame", NaN, ...
    "CurveConstruction", "", "TruthStatus", "", "SourceArtifact", "", ...
    "Status", "", "NAReason", "");
T = localBaseRows(meta, "", "", 0);
end
