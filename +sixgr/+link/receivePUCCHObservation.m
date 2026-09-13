function rx=receivePUCCHObservation(cfg,assignment,context,observation,prior)
% Receive actual PUCCH samples without preparing or inspecting a UE waveform.
% ReceptionAssignment is the independent gNB hypothesis API. The legacy
% TransmissionAssignment remains explicitly labelled as transmitter-coupled;
% accepting it does not qualify an independent shared HARQ codebook.
if nargin<5, prior=[]; end
receiverOnly=isa(assignment,'sixgr.phy.pucch.PUCCHReceptionAssignment');
legacy=isa(assignment,'sixgr.phy.pucch.PUCCHTransmissionAssignment');
assert(isscalar(assignment) && (receiverOnly || legacy), ...
    'sixgr:phy:pucch:WrongResource','Supply a typed receiver allocation.');
assert(isa(context,'sixgr.phy.pucch.UCIReportContext') && isscalar(context), ...
    'sixgr:phy:pucch:MissingUCIReportContext','Supply the receiver length hypothesis, not payload bits.');
assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && isscalar(observation), ...
    'sixgr:link:PUCCHObservationRequired','Supply complete contiguous actual received samples.');
if receiverOnly
    slot0=double(assignment.Data.AbsoluteSlot0);
else
    slot0=double(assignment.DueSlot)-1;
end
validateattributes(slot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
carrier=sixgr.phy.grid.makeCarrier(cfg);
carrier.NFrame=floor(slot0/double(carrier.SlotsPerFrame));
carrier.NSlot=mod(slot0,double(carrier.SlotsPerFrame));
info=nrOFDMInfo(carrier);
first=sixgr.phy.frame.slotStartSample(carrier,slot0,double(info.SampleRate));
stop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,double(info.SampleRate));
assert(observation.SampleRateHz==double(info.SampleRate) && ...
    observation.StartSample<=first && observation.EndSampleExclusive>first && ...
    observation.EndSampleExclusive-observation.StartSample>=stop-first, ...
    'sixgr:link:PUCCHReceiveClockMismatch', ...
    'The capture must straddle the scheduled slot origin and contain a complete FFT interval.');
% A timing-advanced waveform can finish before the nominal slot ends.
% Actual pilot alignment below, not nominal TX duration, bounds its FFT.
raw=observation.readComplete();
policy=sixgr.util.structGet(cfg,'phy.pucch.receiverDetectionThresholds',[]);
assert(~isempty(policy),'sixgr:link:PUCCHDetectionYAMLAuthorityRequired', ...
    'The shared receiver requires resolved YAML detector thresholds.');
[threshold,thresholdSource]=sixgr.phy.pucch.resolveDetectionThreshold(assignment,policy);
args={'NoiseVariance',NaN,'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
    'DetectionThreshold',threshold};
timing=[];
if assignment.Format==0
    assert(isa(prior,'sixgr.phy.sync.ReceivedULTimingReference') && isscalar(prior), ...
        'sixgr:phy:pucch:PUCCHTimingReferenceRequired', ...
        'Pilot-free Format 0 requires an available retained measured gNB UL clock.');
    [raw,timing]=prior.alignObservation(cfg,observation,slot0);
    args=[args {'NoiseVarianceMode','noncoherent_correlation'}];
else
    % Received DM-RS, not injected noise/covariance or TX pilot samples.
    % The full actual capture bounds timing search; no padding is allowed.
    args=[args {'NoiseVarianceMode','received_dmrs_estimate', ...
        'TimingSearchWindowSamples',[0 size(raw,1)-(stop-first)]}];
end
rx=sixgr.phy.pucch.PUCCHReceiver.receive(raw,carrier,assignment,context,args{:});
if ~isempty(timing), rx.ReceiveTiming=timing; end
rx.DetectionThresholdSource=thresholdSource;
rx.ReceiverObservationStartSample=observation.StartSample;
rx.ReceiverObservationEndSampleExclusive=observation.EndSampleExclusive;
rx.ReceiverObservationSampleRateHz=observation.SampleRateHz;
rx.PreparedTransmitterConsumed=false;
rx.InjectedNoiseVarianceConsumed=false;
rx.InjectedInterferenceCovarianceConsumed=false;
rx.IndependentReceiverAssignment=receiverOnly;
end
