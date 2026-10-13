function ok=testReceivedPUCCHTimingRetention()
% Physical DM-RS correlation may refresh the UE clock for later pilot-free
% PUCCH. Unit-channel component evidence, not detector qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pusch.RNTI=321;
cfg.SharedULTimingContext=struct('Source','declared_component_received_TAG','TAGID',0);
cfg.phy.synchronization.maxReceivedULTimingAgeSlots=4;
[cfg,a,c,o,rx]=receiveFixture(cfg,2,8,[]);
assert(~rx.DTX && rx.CRCPassed && rx.ReceiveTiming.AppliedTimingCorrectionSamples==3);
state=struct('NumUsers',1);
state=sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a,c,o,rx);
reference=state.ReceivedULTimingReferences{1};
assert(reference.SourceSignal=="PUCCH_DMRS" && reference.ArrivalOffsetFromNominalSamples==3);
[cfg,a0,c0,o0,rx0]=receiveFixture(cfg,0,9,reference);
assert(~rx0.DTX && rx0.CRCPassed && rx0.DecodedSequence1==1 && ...
    rx0.ReceiveTiming.ReferenceSource=="PUCCH_DMRS" && rx0.ReceiveTiming.ReferenceAgeSlots==1);
unchanged=sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a0,c0,o0,rx0);
assert(isequaln(unchanged,state),'Pilot-free PUCCH must not renew its own timing lease.');
again=sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a,c,o,rx);
assert(isequaln(again,state),'Repeated completion must be idempotent.');
bad=rx; bad.DTX=true; bad.ReceiverUsable=false;
emptyState=struct('NumUsers',1);
assert(isequaln(sixgr.truth.retainReceivedPUCCHTimingReference(emptyState,1,cfg,a,c,o,bad),emptyState));
bad=rx; bad.CRCPassed=false;
assert(isequaln(sixgr.truth.retainReceivedPUCCHTimingReference(emptyState,1,cfg,a,c,o,bad),emptyState));
bad=rx; bad.PreparedTransmitterConsumed=true;
reject(@()sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a,c,o,bad), ...
    'sixgr:truth:PUCCHTimingReceiverIdentity');
bad=cfg; bad.phy.pusch.RNTI=322;
reject(@()reference.alignCompletedObservation(bad,o0,9), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
bad=cfg; bad.phy.synchronization.maxReceivedULTimingAgeSlots=0;
reject(@()reference.alignCompletedObservation(bad,o0,9),'sixgr:phy:sync:StaleULTimingReference');
assert(isempty(sixgr.truth.selectReceivedULTimingReference(state,1,reference.AvailableAtSample-1, ...
    reference.NominalStartSample)),'A future completion cannot become a prior clock.');
fprintf('RECEIVED_PUCCH_TIMING_RETENTION_PASS real_format2_to_format0=1 stale_identity_future_guards_preserved=1\n');
ok=true;
end

function [cfg,assignment,context,observation,rx]=receiveFixture(cfg,format,slot0,prior)
bits=int8(1); if format==2, bits=int8(mod((0:19).',2)); end
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,bits);
carrier=f.Carrier; carrier.NSlot=mod(slot0,carrier.SlotsPerFrame); carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
cfg.phy.carrier=struct('NSizeGrid',carrier.NSizeGrid,'NStartGrid',carrier.NStartGrid, ...
    'SubcarrierSpacing',carrier.SubcarrierSpacing,'NCellID',carrier.NCellID,'CyclicPrefix',carrier.CyclicPrefix);
cfg.channel.model='AWGN';
reportData=f.Report.Data; reportData.TargetSlot=slot0+1;
report=sixgr.phy.pucch.UCIReport(reportData);
frame=f.FrameState; frame.PDSCHEndSlot=slot0; frame.TargetSlot=slot0+1;
tx=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(report,f.UEContext,frame);
context=sixgr.phy.pucch.UCIReportContext.fromReport(report);
data=struct('ObservationID',"component-pucch-"+slot0,'ResourceID',tx.Resource.ID, ...
    'RNTI',321,'AbsoluteSlot0',slot0,'Source','independent_component_receive_resource', ...
    'TimingSource','received_pilot_clock');
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(data,f.RRCContext,context);
wave=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,tx,report);
info=nrOFDMInfo(carrier); first=sixgr.phy.frame.slotStartSample(carrier,slot0,info.SampleRate);
% Three actual leading samples represent this component channel's delay.
samples=[complex(zeros(3,size(wave.Waveform,2)));wave.Waveform;complex(zeros(5,size(wave.Waveform,2)))];
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),info.SampleRate,size(samples,2));
observation.append(sixgr.phy.waveform.WaveformChunk(samples,first),info.SampleRate);
rx=sixgr.link.receivePUCCHObservation(cfg,assignment,context,observation,prior);
end

function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
