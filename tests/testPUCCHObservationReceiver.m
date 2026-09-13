function ok=testPUCCHObservationReceiver()
% Actual retained post-RF IQ and prior received SRS clock; no new TX for RX.
% Receiver API equivalence only: fixture lengths are NOT a scheduled gNB
% Type-2 codebook or an independent missed-DCI qualification.
setup6GRSimToolkit('Verbose',false);
root=fullfile('docs','lls','evidence_20260913','pucch_baseline_signal_04');
x=load(fullfile(root,'received_pucch.mat'));
p=x.item.Context.Prepared; cfg=p.ReceiverConfig;
prior=x.timingReferences{1};
planes=x.item.Planes;
k=find(endsWith(string({planes.ReceiverID}),":post_rf"));
assert(isscalar(k));
observation=planes(k).Observation;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
% This retained component experiment prescribed two bits, resource 0, slot 8.
context=sixgr.phy.pucch.UCIReportContext(struct( ...
    'ReportID',"receiver-only-retained-signal",'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
    'Sequence1Length',2,'Sequence2Length',0,'HARQACKBits',2, ...
    'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
data=struct('ObservationID',context.ReportID,'ResourceID',0,'RNTI',1, ...
    'AbsoluteSlot0',8,'Source','retained_component_prescribed_resource_and_length', ...
    'TimingSource','prior_received_SRS_clock');
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(data,rrc,context);
[oldSamples,oldTiming]=prior.align(p,observation);
[samples,timing]=prior.alignObservation(cfg,observation,8);
assert(isequal(samples,oldSamples) && isequaln(timing,oldTiming));
clear p x
received=sixgr.link.receivePUCCHObservation(cfg,assignment,context,observation,prior);
carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=8; carrier.NFrame=0;
[threshold,~]=sixgr.phy.pucch.resolveDetectionThreshold(assignment,cfg.phy.pucch.receiverDetectionThresholds);
direct=sixgr.phy.pucch.PUCCHReceiver.receive(samples,carrier,assignment,context, ...
    'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation', ...
    'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg),'DetectionThreshold',threshold);
assert(isequal(received.DecodedSequence1,direct.DecodedSequence1) && received.DTX==direct.DTX);
assert(received.DetectionMetric==direct.DetectionMetric && isequaln(received.ReceiveTiming,timing));
assert(received.ReceiverOnlyAssignment && received.IndependentReceiverAssignment && ...
    ~received.PreparedTransmitterConsumed && ~received.InjectedNoiseVarianceConsumed && ...
    ~received.InjectedInterferenceCovarianceConsumed && isnan(received.DecodeNoiseInterferenceVariance));
localReject(@()sixgr.link.receivePUCCHObservation(cfg,assignment,context,observation), ...
    'sixgr:phy:pucch:PUCCHTimingReferenceRequired');
bad=cfg; bad.phy.pusch.RNTI=2;
localReject(@()sixgr.link.receivePUCCHObservation(bad,assignment,context,observation,prior), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
bad=cfg; bad.phy.synchronization.maxReceivedULTimingAgeSlots=0;
localReject(@()sixgr.link.receivePUCCHObservation(bad,assignment,context,observation,prior), ...
    'sixgr:phy:sync:StaleULTimingReference');
bad=cfg; bad.SharedULTimingContext.CounterfactualGuardTest=true;
localReject(@()sixgr.link.receivePUCCHObservation(bad,assignment,context,observation,prior), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
bad=cfg; bad.phy.pucch=rmfield(bad.phy.pucch,'receiverDetectionThresholds');
localReject(@()sixgr.link.receivePUCCHObservation(bad,assignment,context,observation,prior), ...
    'sixgr:link:PUCCHDetectionYAMLAuthorityRequired');
empty=sixgr.phy.waveform.WaveformObservationBuffer(observation.StartSample, ...
    observation.EndSampleExclusive,observation.SampleRateHz,observation.NumReceiveAntennas);
localReject(@()sixgr.link.receivePUCCHObservation(cfg,assignment,context,empty,prior), ...
    'WAVEFORM:IncompleteObservation');
badData=data; badData.AbsoluteSlot0=7;
wrong=sixgr.phy.pucch.PUCCHReceptionAssignment(badData,rrc,context);
localReject(@()sixgr.link.receivePUCCHObservation(cfg,wrong,context,observation,prior), ...
    'sixgr:link:PUCCHReceiveClockMismatch');
% The already wired shared trial must not consume changed injected variance
% or oracle covariance. These are counterfactual metadata guards only; they
% do not replace the retained physical experiment or produce primary rows.
x=load(fullfile(root,'received_pucch.mat')); p=x.item.Context.Prepared;
[~,pre,tx,replay,actual]=sixgr.truth.sharedObservationEvidence(x.item.Planes,p);
channel=struct('Profile',sixgr.channel.resolveConcreteProfile(cfg));
input=struct('Prepared',p,'Observation',actual,'PhysicalMeasurementObservation',pre, ...
    'TransmitterObservation',tx,'Replay',replay,'ChannelState',struct(), ...
    'Channel',channel,'ReceivedULTimingReference',prior);
firstTrial=sixgr.link.runPUCCHWaveformTrial(x.item.Context.Config, ...
    x.item.Context.Arguments{:},'ReceivedContext',input);
input.Replay.SampleNoiseVariance=12345;
input.Replay.SampleNoiseVarianceDomain="receiver_sample_waveform_post_composite_front_end";
input.Replay.InterferenceCovariance=1e6*eye(observation.NumReceiveAntennas);
secondTrial=sixgr.link.runPUCCHWaveformTrial(x.item.Context.Config, ...
    x.item.Context.Arguments{:},'ReceivedContext',input);
% Wall-clock profiling is not a semantic PHY output.
names=string(fieldnames(firstTrial.Rx));
latency=cellstr(names(endsWith(names,'Latency_ms')));
assert(isequaln(rmfield(firstTrial.Rx,latency),rmfield(secondTrial.Rx,latency)));
assert(~firstTrial.Rx.IndependentReceiverAssignment, ...
    'Legacy transmitter-coupled assignment must not be labelled independent.');
assert(~firstTrial.ReceiverInjectedNoiseVarianceConsumed && ...
    firstTrial.ReceiverInputSampleNoiseVarianceValueRole=="physical_execution_metadata_not_receiver_estimate");
fprintf('PUCCH_OBSERVATION_RECEIVER_RETAINED_PASS guards=8 no_shared_codebook_qualification=1\n');
% Fresh standalone coded waveforms exercise received-DMRS Formats 1-4.
% The receiver takes only actual sample buffers and count/resource contexts.
catalog=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','control','pucch_receiver_thresholds.yaml'));
for format=1:4
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
    c=struct('phy',struct('carrier',struct('NSizeGrid',f.Carrier.NSizeGrid, ...
        'SubcarrierSpacing',f.Carrier.SubcarrierSpacing,'NCellID',f.Carrier.NCellID), ...
        'pucch',struct('receiverDetectionThresholds',catalog.pucch)), ...
        'channel',struct('model','AWGN'));
    data=struct('ObservationID',"dmrs-component-"+format,'ResourceID',f.Assignment.Resource.ID, ...
        'RNTI',f.Assignment.Data.RNTI,'AbsoluteSlot0',0, ...
        'Source','standalone_prescribed_resource_and_length','TimingSource','received_DMRS_correlation');
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(data,f.RRCContext,f.Context);
    waveform=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    info=nrOFDMInfo(f.Carrier);
    buffer=sixgr.phy.waveform.WaveformObservationBuffer(0,size(waveform.Waveform,1), ...
        info.SampleRate,size(waveform.Waveform,2));
    buffer.append(sixgr.phy.waveform.WaveformChunk(waveform.Waveform,0),info.SampleRate);
    rx=sixgr.link.receivePUCCHObservation(c,assignment,f.Context,buffer);
    serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(f.Report);
    assert(~rx.DTX && rx.CRCPassed && isequal(rx.DecodedSequence1,serialized.Sequence1.Bits) && ...
        isequal(rx.DecodedSequence2,serialized.Sequence2.Bits));
    assert(rx.ReceiveTiming.TimingSource=="received_reference_correlation_bounded_search" && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed && ...
        ~rx.InjectedNoiseVarianceConsumed && ~rx.PreparedTransmitterConsumed);
    fprintf('PUCCH_OBSERVATION_RECEIVER_DMRS_PASS format=%d\n',format);
end
ok=true;
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
