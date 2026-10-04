function [feature,channelGrid]=extractGrantCalibrationPredictor(evidence,receiverType,options)
%EXTRACTGRANTCALIBRATIONPREDICTOR Offline applied-channel spatial predictor.
% This never supplies an oracle to Rx and is NOT receiver-measured SINR.
% The current linear-channel feature domain is ideal RF with deterministic
% large-scale amplitude gain. RF distortion needs its separately qualified
% model; it must not be silently represented by ideal channel/noise inputs.
arguments
    evidence (1,1) struct
    receiverType (1,1) string {mustBeMember(receiverType,["lmmse","zf"])}
    options.Plane (1,1) string {mustBeMember(options.Plane, ...
        ["actual_receiver_fft","scheduled_nominal_fft_before_receiver_sync"])}="actual_receiver_fft"
    options.Model (1,1) string {mustBeMember(options.Model, ...
        ["diagonal_nominal_fft","finite_committed_shared_data"])}="diagonal_nominal_fft"
end
assert(string(sixgr.util.structGet(evidence,'Schema',''))== ...
    "sixgr.grant_waveform_calibration_evidence/v1" && ...
    evidence.WaveformBacked && ~evidence.Propagation.ReceiverOracleUsed && ...
    isfield(evidence,'ReceiverOFDMInfo'), ...
    'sixgr:calibration:GrantPredictorEvidence','Require captured executed grant/channel/receiver evidence.');
tx=evidence.Transmitter; rx=evidence.Receiver;
p=evidence.Propagation; imp=evidence.AppliedImpairments;
ofdm=evidence.ReceiverOFDMInfo; carrier=tx.Carrier;
assert(isfield(imp,'RFAppliedStageCount') && imp.RFAppliedStageCount==0 && ...
    ~logical(sixgr.util.structGet(rx,'IQImbalanceCorrectionApplied',false)) && ...
    ~logical(sixgr.util.structGet(rx,'PTRSCPECorrectionApplied',false)), ...
    'sixgr:calibration:GrantPredictorRFDomain', ...
    'Nonlinear/RF/tracking branches need a matching predictor; do not relabel them ideal RF.');
assert(all(isfield(ofdm,{'Nfft','SampleRate','CyclicPrefixFraction'})), ...
    'sixgr:calibration:GrantPredictorClock','Retain the actually executed receiver FFT/window metadata.');
fs=double(ofdm.SampleRate); nfft=double(ofdm.Nfft); cpFraction=double(ofdm.CyclicPrefixFraction);
assert(isfinite(fs) && fs>0 && isfinite(nfft) && nfft==fix(nfft) && nfft>0 && ...
    isfinite(cpFraction) && cpFraction>=0 && cpFraction<=1 && ...
    abs(fs-p.SampleRateHz)<=1e-9*fs && ...
    abs(fs-nfft*carrier.SubcarrierSpacing*1e3)<=1e-9*fs, ...
    'sixgr:calibration:GrantPredictorClock','Receiver and retained propagation sample clocks differ.');
timing=double(sixgr.util.structGet(rx,'AppliedTimingCorrection_samples',NaN));
assert(isscalar(timing) && isfinite(timing) && timing==fix(timing), ...
    'sixgr:calibration:GrantPredictorTiming','Actual receiver timing correction is unavailable.');
gain=double(imp.AppliedLargeScaleAmplitudeGain);
assert(isscalar(gain) && isfinite(gain) && gain>0 && ...
    abs(gain^2-evidence.Noise.AppliedLargeScalePowerGain)<= ...
    1e-12*max(gain^2,evidence.Noise.AppliedLargeScalePowerGain), ...
    'sixgr:calibration:GrantPredictorPower','Noise and channel must refer to the same applied power plane.');
nSC=12*carrier.NSizeGrid; nSymbols=carrier.SymbolsPerSlot;
nTx=size(tx.Waveform,2);
operator=sixgr.util.structGet(rx,'ReceiverChannelOperator',struct());
combiner=sixgr.util.structGet(operator,'ReceiveCombiningMatrix',[]);
% The report's CFOCorrectionApplied_Hz may be NaN when no correction ran.
% Use the recorded executed operators, not an unavailable estimate field.
assert(~isempty(combiner) && isequal(combiner,eye(size(combiner,1))) && ...
    operator.AppliedTimingCorrection_samples==timing && ...
    operator.CaptureOriginCFOCorrection_Hz==0 && operator.AlignedOriginCFOCorrection_Hz==0, ...
    'sixgr:calibration:GrantPredictorReceiverOperator', ...
    'Applied spatial/frequency receive operators need explicit projection into the predictor.');
actualReceiverTiming=timing;
if options.Plane=="scheduled_nominal_fft_before_receiver_sync"
    % This is the SLS modeled input plane for ALL trials, selected before
    % observing CRC/timing outcomes. Acquisition errors remain in decoder
    % outcomes; they must not select or censor calibration samples. Never
    % feed this nominal channel into the physical receiver or call it the
    % actually synchronized receiver response.
    timing=0;
end
if p.UseFading
    offset=double(p.ImplementationFilterTrimSamples)+timing;
    assert(offset>=0 && offset==fix(offset) && ~isempty(p.PathGains) && ...
        ~isempty(p.PathFilters) && ~isempty(p.SampleTimes) && ...
        size(p.PathGains,3)==nTx, ...
        'sixgr:calibration:GrantPredictorChannel','Missing executed path realization or unsupported timing origin.');
    channelGrid=nrPerfectChannelEstimate(carrier,p.PathGains,p.PathFilters, ...
        offset,p.SampleTimes,'Nfft',nfft,'SampleRate',fs,'CyclicPrefixFraction',cpFraction);
    executedOFDM=nrOFDMInfo(carrier,'Nfft',nfft,'SampleRate',fs);
    cpSupport=sixgr.phy.waveform.channelCyclicPrefixSupport( ...
        p.PathFilters,offset,executedOFDM.CyclicPrefixLengths,cpFraction);
    source="executed_path_gains_filters_at_actual_receiver_fft_window";
else
    % Identity is valid only for the explicitly executed identity-AWGN path.
    assert(string(p.Source)=="executed_identity_awgn_channel" && ...
        isempty(p.PathGains), ...
        'sixgr:calibration:GrantPredictorChannel', ...
        'An identity grid cannot represent a fading channel.');
    channelGrid=repmat(reshape(eye(nTx),1,1,nTx,nTx),nSC,nSymbols,1,1);
    if timing~=0
        % An integer FFT shift *inside* the untouched cyclic prefix changes
        % subcarrier phase, not power. Model the actual receiver shift; do
        % not drop low-SNR trials or silently reset the timing estimator.
        txOFDM=sixgr.util.structGet(tx,'OFDMInfo',sixgr.util.structGet(tx,'OFDM',struct()));
        window=double(sixgr.util.structGet(txOFDM,'Windowing',NaN));
        assert(isfinite(window) && window>=0 && isfield(ofdm,'CyclicPrefixLengths'), ...
            'sixgr:calibration:GrantPredictorTimingWindow','Missing executed CP/windowing evidence.');
        cp=double(ofdm.CyclicPrefixLengths(:)); guard=ceil(window/2);
        assert(all(floor(cpFraction*cp)+timing>=guard) && ...
            all(ceil(cpFraction*cp)+timing<=cp-guard), ...
            'sixgr:calibration:GrantPredictorTimingWindow', ...
            'Timing leaves the cyclic-prefix interval; an ISI/ICI-aware predictor is required.');
        phase=exp(1i*2*pi*(-nSC/2:nSC/2-1).'*timing/nfft);
        channelGrid=channelGrid.*reshape(phase,nSC,1,1,1);
    end
    offset=timing; source="executed_identity_awgn_channel_at_actual_receiver_fft_window";
end
assert(size(channelGrid,1)==nSC && size(channelGrid,2)>=nSymbols && ...
    size(channelGrid,4)==nTx && size(channelGrid,3)==size(combiner,1) && ...
    all(isfinite(channelGrid),'all'), ...
    'sixgr:calibration:GrantPredictorChannel','Reconstructed channel does not cover the transmitted slot.');
channelGrid=double(channelGrid(:,1:nSymbols,:,:)).*gain;
diagnostic=struct('Tx',tx,'TrueChannelGrid',channelGrid,'NoiseInfo',evidence.Noise);
if options.Model=="finite_committed_shared_data"
    % Validate the executed allocation/power without running a DIFFERENT
    % detector first. In particular, a diagonal ZF rank test is not a valid
    % precondition for the finite receive-window channel. Its own detector
    % performs the rank/covariance validation below.
    [feature,allocation]=sixgr.calibration.resolveAppliedSpatialEvidence(diagnostic);
else
    [feature,allocation]=sixgr.calibration.extractAppliedSpatialSINR(diagnostic,receiverType);
end
assert(feature.DataRECount==evidence.DataREMap.LayerRECount, ...
    'sixgr:calibration:GrantPredictorPopulation','Predictor must cover exactly the executed data-layer REs.');
feature.PropagationSource=source;
if options.Plane=="scheduled_nominal_fft_before_receiver_sync"
    feature.PropagationSource="executed_channel_reconstructed_at_scheduled_nominal_fft_before_receiver_sync";
end
feature.PredictorPlane=options.Plane;
feature.PredictorFFTOffsetFromChannelOrigin_samples=offset;
feature.ActualReceiverTimingCorrection_samples=actualReceiverTiming;
feature.ReceiverFFTOffsetFromChannelOrigin_samples=double(p.ImplementationFilterTrimSamples)+actualReceiverTiming;
feature.CyclicPrefixFraction=cpFraction;
feature.AppliedLargeScaleAmplitudeGain=gain;
feature.DataREAllocationSHA256=evidence.ScheduledDataREMap.AllocationIdentitySHA256;
feature.ReceiverOracleUsed=false;
feature.CalibrationQualified=false;
feature.PrimaryStudyAccepted=false;
if p.UseFading
    % Do not censor low-SNR episodes or repair their CRC outcomes. This is
    % predictor-domain evidence, not a qualification pass or receiver input.
    feature.ChannelCyclicPrefixSupport=cpSupport;
    feature.ResidualISIICIIncluded=false;
end
feature.SINRPredictorModel=options.Model;
if options.Model=="finite_committed_shared_data"
    % Do not merely attach the finite recipe to diagonal features. Reuse
    % only the checked power/allocation metadata and replace the numerical
    % features with the finite operator on the actual retained realization.
    assert(options.Plane=="scheduled_nominal_fft_before_receiver_sync", ...
        'sixgr:calibration:FinitePredictorPlane','Finite SLS calibration uses the predeclared nominal FFT plane.');
    txOFDM=sixgr.util.structGet(tx,'OFDMInfo',sixgr.util.structGet(tx,'OFDM',struct()));
    assert(isequal(double(sixgr.util.structGet(txOFDM,'Windowing',NaN)),0), ...
        'sixgr:calibration:FinitePredictorWindowing', ...
        'The finite reference currently requires actually executed zero OFDM windowing; do not relabel a windowed waveform.');
    r=struct('PathFilters',p.PathFilters,'PathGains',p.PathGains.*gain, ...
        'SampleTimes',p.SampleTimes,'SampleRateHz',fs,'TrimSamples',double(p.ImplementationFilterTrimSamples), ...
        'NumberOfSymbols',double(nSymbols),'Nfft',nfft,'CyclicPrefixFraction',cpFraction);
    if ~p.UseFading
        % Explicit executed identity-AWGN only (validated above), never a
        % replacement for unavailable fading gains.
        ns=size(tx.Waveform,1)+r.TrimSamples;
        r.PathFilters=1;
        r.PathGains=repmat(reshape(gain*eye(nTx),1,1,nTx,nTx),ns,1,1,1);
        r.SampleTimes=double(p.ChannelInitialTime_s)+(0:ns-1)'/fs;
    end
    coordinates=allocation.Coordinates0Based;
    finite=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
        carrier,coordinates,allocation.NormalizedPrecoder, ...
        repmat(allocation.TotalPowerPerRE,size(coordinates,1),1),coordinates,r, ...
        'Algorithm','fft_transfer');
    spatial=sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR( ...
        finite,feature.GridNoiseVariance*eye(allocation.NumRx),receiverType);
    feature.SINRLinear=spatial.SINRLinear;
    feature.InterLayerInterferencePower=spatial.InterLayerInterferencePower;
    feature.SINRSource="finite_executed_channel_per_data_re_per_layer_"+receiverType+"_not_receiver_measurement";
    feature.SourceClassification="finite_channel_predictor_from_executed_waveform_not_receiver_measurement";
    feature.ResidualISIICIIncluded=true;
    feature.PredictorResourcePopulation="executed_shared_data_re_only";
    feature.PredictorBoundaryPolicy=finite.BoundaryPolicy;
    feature.ChannelCyclicPrefixSupport=finite.CyclicPrefixSupport;
    feature.CommonControlInterferenceQualified=false;
    feature.ReferenceSignalInterferenceQualified=false;
    feature.FullNetworkInterferenceQualified=false;
end
end
