function [ok,result]=testPUCCHUnavailableTimingOutcome()
% Native coded PUCCH with declared unit-channel delay/TAG and MAC schedule.
% No RF/channel execution, received RAR/DCI, or full-access qualification.
setup6GRSimToolkit('Verbose',false);
parent=fullfile(pwd,'results','validation','pucch_unavailable_timing');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pusch.RNTI=321; cfg.phy.synchronization.maxReceivedULTimingAgeSlots=4;
[cfg,f,a,c,o,rx]=localReceive(cfg,2,39,[],false);
assert(rx.CRCPassed && ~rx.DTX && rx.ReceiveTiming.AppliedTimingCorrectionSamples==3);
state=sixgr.truth.retainReceivedPUCCHTimingReference(struct('NumUsers',1),1,cfg,a,c,o,rx);
prior=state.ReceivedULTimingReferences{1}; original=state;
[cfg,~,a4,c4,o4,r4]=localReceive(cfg,0,43,prior,true);
assert(r4.ReceiverUsable && r4.DecodedSequence1==1 && r4.ReceiveTiming.ReferenceAgeSlots==4);
assert(isequaln(state,sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a4,c4,o4,r4)), ...
    'Format0 must not refresh its own received timing lease.');
[cfg,f5,a5,c5,o5,r5]=localReceive(cfg,0,44,prior,true);
localUnavailable(r5,o5,5);
reject(@()sixgr.link.receivePUCCHObservation(cfg,a5,c5,o5,prior), ...
    'sixgr:phy:sync:StaleULTimingReference'); % Strict direct API remains strict.
assert(isequaln(original,sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,a5,c5,o5,r5)));
missing=sixgr.link.receivePUCCHObservation(cfg,a5,c5,o5,[], 'TimingUnavailableAsOutcome',true);
assert(missing.ReceiverUnavailableReason=="missing_received_ul_timing" && ~missing.DetectionAttempted);
bad=cfg; bad.phy.pusch.RNTI=322;
reject(@()sixgr.link.receivePUCCHObservation(bad,a5,c5,o5,prior,'TimingUnavailableAsOutcome',true), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
bad=cfg; bad.SharedULTimingContext.DLReference.DLPhaseOffsetSamples=1;
reject(@()sixgr.link.receivePUCCHObservation(bad,a5,c5,o5,prior,'TimingUnavailableAsOutcome',true), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
% Exercise the actual prepared/received trial consumer, not just the new
% boundary. The channel/sample placement is explicitly a unit fixture.
trial=localTrial(cfg,f5,a5,c5,prior);
assert(trial.Status=="UNAVAILABLE" && ~trial.ReceiverDecodeFailed && ...
    ~trial.CRCFailed && ~trial.CRCApplicable && isnan(trial.CRCPass) && ...
    ~trial.ReceiverDTX && ~trial.DetectionAttempted && ~trial.ReceiverUsable && ...
    isempty(trial.DecodedBits) && isnan(trial.BitErrors) && trial.BitsCompared==0 && ...
    ~trial.ContentMismatch && strlength(trial.UCIBitErrorVector)==0);
localProjection(trial,r5,folder);
dispositions=localMAC(r5,c5);
% A later real DM-RS reception can renew the clock. Never renew from the
% unavailable Format0 result or simply from a later wall-clock timestamp.
[cfg,~,freshA,freshC,freshO,freshRX]=localReceive(cfg,2,48,prior,true);
assert(freshRX.CRCPassed && freshRX.ReceiverUsable);
state=sixgr.truth.retainReceivedPUCCHTimingReference(state,1,cfg,freshA,freshC,freshO,freshRX);
fresh=state.ReceivedULTimingReferences{1};
assert(fresh.NominalStartSample>prior.NominalStartSample && fresh.AvailableAtSample==freshO.EndSampleExclusive);
[~,~,~,~,afterO,afterRX]=localReceive(cfg,0,49,fresh,true);
assert(afterRX.ReceiverUsable && afterRX.DecodedSequence1==1 && afterRX.ReceiveTiming.ReferenceAgeSlots==1);
reject(@()sixgr.link.receivePUCCHObservation(cfg,a5,c5,o5,fresh,'TimingUnavailableAsOutcome',true), ...
    'sixgr:phy:sync:FutureULTimingReference');
result=struct('Scope',"native_PUCCH_declared_unit_channel_TAG_and_MAC_schedule_not_shared_RF", ...
    'Age4Receiver',r4,'Age5Receiver',r5,'RecoveredReceiver',afterRX, ...
    'OriginalAge5Observation',o5,'RecoveredObservation',afterO, ...
    'Trial',trial,'MACDispositions',dispositions,'EvidenceRoot',string(folder));
save(fullfile(folder,'original_receivers.mat'),'result');
ok=true;
fprintf('PUCCH_UNAVAILABLE_TIMING_PASS native_TX=5 age4_decode=1 age5_no_receiver=1 later_format2_recovery=1 declared_MAC_once_only=1 full_runtime=0 root=%s\n',folder);
end

function [cfg,f,a,c,o,rx]=localReceive(cfg,format,slot0,prior,outcome)
bits=int8(1); if format==2, bits=int8(mod((0:19).',2)); end
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,bits);
carrier=f.Carrier; carrier.NFrame=floor(slot0/carrier.SlotsPerFrame); carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
cfg.phy.carrier=struct('NSizeGrid',carrier.NSizeGrid,'NStartGrid',carrier.NStartGrid, ...
    'SubcarrierSpacing',carrier.SubcarrierSpacing,'NCellID',carrier.NCellID,'CyclicPrefix',carrier.CyclicPrefix);
cfg.channel.model='AWGN'; info=nrOFDMInfo(carrier);
if ~isfield(cfg,'SharedULTimingContext')
    % Declared lifecycle operands only. This test does not decode SIB1/RAR.
    offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(struct('Source',"decoded_sib1", ...
        'TimingAdvanceOffsetPresent',true,'TimingAdvanceOffset',"n0"),'FR1');
    cfg.SharedULTimingContext=struct('DLReference',struct( ...
        'Source',"received_SSB_timing_and_decoded_BCH",'SampleRateHz',info.SampleRate, ...
        'DLPhaseOffsetSamples',0,'AvailableAtSample',0), ...
        'Offset',offset,'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,info.SampleRate), ...
        'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
        'TimeAlignmentExpirySampleExclusive',Inf);
end
d=f.Report.Data; d.TargetSlot=slot0+1; report=sixgr.phy.pucch.UCIReport(d);
frame=f.FrameState; frame.PDSCHEndSlot=slot0; frame.TargetSlot=slot0+1;
txa=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(report,f.UEContext,frame);
c=sixgr.phy.pucch.UCIReportContext.fromReport(report);
a=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',"age-fixture-"+slot0, ...
    'ResourceID',txa.Resource.ID,'RNTI',321,'AbsoluteSlot0',slot0, ...
    'Source',"independent_component_receiver",'TimingSource',"received_pilot_clock"),f.RRCContext,c);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,txa,report);
samples=[complex(zeros(3,2));tx.Waveform*[1 .8i];complex(zeros(5,2))];
first=sixgr.phy.frame.slotStartSample(carrier,slot0,info.SampleRate);
o=localBuffer(samples,first,info.SampleRate);
rx=sixgr.link.receivePUCCHObservation(cfg,a,c,o,prior,'TimingUnavailableAsOutcome',outcome);
f.Carrier=carrier; f.Assignment=txa; f.Report=report; f.Context=c;
end

function trial=localTrial(cfg,f,a,c,prior)
args={'Assignment',f.Assignment,'Report',f.Report,'ReceiverContext',c, ...
    'Carrier',f.Carrier,'ChannelProfile','AWGN','TimingAdvanceSamples',0};
preparedTrial=sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'PrepareOnly',true);
p=preparedTrial.PreparedTransmission;
samples=complex(zeros(p.ReceiveEndSampleExclusive-p.ReceiveStartSample,p.NumReceiveAntennas));
nominal=sixgr.phy.frame.slotStartSample(f.Carrier,44,p.SampleRateHz);
indices=nominal+3-p.ReceiveStartSample+(1:size(p.Tx.Waveform,1));
assert(max(indices)<=size(samples,1));
samples(indices,:)=p.Tx.Waveform*ones(1,p.NumReceiveAntennas);
o=localBuffer(samples,p.ReceiveStartSample,p.SampleRateHz);
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'ue','signal','pucch','numPorts',1);
tx=localBuffer(p.Tx.Waveform*array.PortToElementMatrix.',p.StartSample,p.SampleRateHz);
received=struct('Prepared',p,'Observation',o,'PhysicalMeasurementObservation',o, ...
    'TransmitterObservation',tx,'Channel',struct('Profile','AWGN'), ...
    'Replay',struct('SampleNoiseVariance',0,'SampleNoiseVarianceDomain', ...
    'receiver_sample_waveform_post_composite_front_end'),'ChannelState',struct(), ...
    'GNBReception',struct('Assignment',a,'Context',c),'ReceivedULTimingReference',prior);
trial=sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'ReceivedContext',received);
end

function localUnavailable(rx,o,age)
assert(rx.ReceiverExecutionStatus=="unavailable_before_synchronization" && ...
    rx.ReceiverUnavailableReason=="stale_received_ul_timing" && ...
    rx.FeedbackDisposition=="receiver_unavailable_stale_ul_timing" && ...
    ~rx.DetectionAttempted && ~rx.DecodeAttempted && ~rx.DTXDecisionAvailable && ...
    ~rx.ReceiverUsable && ~rx.DTX && rx.DetectionOutcome=="unavailable" && ...
    ~rx.CRCApplicable && isempty(rx.DecodedSequence1) && ...
    isnan(rx.DetectionMetric) && isempty(fieldnames(rx.ReceiveFrequency)) && ...
    isnan(rx.ReceiveTiming.AppliedTimingCorrectionSamples) && ...
    rx.ReceiveTiming.ReferenceAgeSlots==age && ~rx.ReceiveTiming.PriorClockApplied && ...
    rx.ReceiverObservationSampleSHA256==o.sampleHash());
end

function localProjection(trial,rx,folder)
row=sixgr.link.pucchReceiverStageEvidence(rx);
for name=["Status","CRCPass","CRCApplicable","BitsCompared","BitErrors", ...
        "ReceiverUsable","DetectionUsable","NoiseVariance","PUCCHFormat", ...
        "ResourceExtractionAvailable","UCIContentMatch"]
    row.(name)=trial.(name);
end
row.Slot=45; row.MeasurementAttempted=false; row.MeasurementUsable=false;
T=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable('pucch',struct2table(row,'AsArray',true));
for name=["DetectionAttempted","DetectionUsable","MeasurementAttempted","MeasurementUsable","ReceiverUsable"]
    assert(~T.(name));
end
% Guard historical canonicalization against metadata-only finite variance
% and a nonapplicable CRC flag. These are NOT new physical measurements.
changed=T; changed.NoiseVariance=1; changed.CRCPass=0;
changed=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable('pucch',changed);
assert(~changed.DetectionAttempted && ~changed.DetectionUsable && ~changed.MeasurementAttempted && ~changed.MeasurementUsable);
out=sixgr.truth.buildLLSPublicOutputTables(struct('pucch_table',T), ...
    sixgr.truth.llsOutputContract(),struct('logical_run_id',"native_unavailable_pucch_component",'run_id',1));
P=out.pucch_uci_table;
assert(~P.DetectionAttempted && ~P.DetectionUsable && ~P.ReceiverUsable && ...
    ~P.DTXDecisionAvailable && P.ReceiverUnavailableReason==rx.ReceiverUnavailableReason);
path=fullfile(folder,'original_unavailable_pucch.csv');
sixgr.util.csvWriteTable(path,P,'PreserveSchema',true);
R=sixgr.util.csvReadTable(path,'TextType','string');
assert(R.ReceiverExecutionStatus==P.ReceiverExecutionStatus && R.FeedbackDisposition==P.FeedbackDisposition);
end

function rows=localMAC(rx,context)
% Declared MAC schedule and real immutable TB, NOT a received DL grant.
cfg=sixgr.config.defaultConfig(); h=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
allocation=h.allocate(321,43,100,'NewData',true);
layout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL','TransportBlockSize',800, ...
    'TargetCodeRate',.3,'RV',0,'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
grant=struct('TBSBits',800,'Direction',"DL",'Modulation',"QPSK", ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout);
bits=uint8(mod((0:799).',2)); h.onTx(321,0,bits,grant,43);
r=struct('BitIndex',1,'TransmissionID',"declared-DL-attempt",'PHYGrantContextId',"declared-context", ...
    'UEIndex',1,'RNTI',321,'HARQProcess',0,'NDI',allocation.HARQ.NDI, ...
    'SourceSlot',43,'TargetSlot',45,'ConfigurationEpoch',context.ConfigurationEpoch);
m=struct('Records',r,'BitCount',1,'UEIndex',1,'RNTI',321,'TargetSlot',45, ...
    'ConfigurationEpoch',context.ConfigurationEpoch,'ContextDigest',context.Digest, ...
    'LastGrant',grant,'Source',"declared_MAC_schedule_not_DL_PHY");
m.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(m,'LastGrant'));
observed=struct('MappingDigest',m.Digest,'UEIndex',1,'RNTI',321,'TargetSlot',45, ...
    'DecodedBits',rx.DecodedSequence1,'DecodeOk',rx.ReceiverUsable,'DTXFlag',rx.DTX,'Transport',"PUCCH");
observed=sixgr.truth.bindPUCCHFeedbackReceptionStatus(observed,rx);
rows=sixgr.truth.mapScheduledHARQFeedback(m,observed);
assert(rows.FeedbackOutcome=="DTX" && ~rows.ObservedAck && ~rows.ReceiverUsable && ...
    rows.FeedbackDisposition=="receiver_unavailable_stale_ul_timing" && ~rows.DTXDecisionAvailable);
assert(h.onFeedback(321,0,rows.FeedbackOutcome,'SourceSlot',43,'FeedbackSlot',45));
assert(h.Stats.Dtx==1 && h.Stats.Nack==0 && h.Stats.Ack==0 && h.UEProcs{1}(1).NeedsRetx);
assert(~h.onFeedback(321,0,rows.FeedbackOutcome,'SourceSlot',43,'FeedbackSlot',45));
assert(h.Stats.Dtx==1 && h.Stats.Nack==0 && h.Stats.StaleFeedbackIgnored==1);
retry=h.peekRetx(321); assert(isequal(retry.TB,bits));
bad=observed; bad.DecodeAttempted=true;
reject(@()sixgr.truth.mapScheduledHARQFeedback(m,bad),'sixgr:truth:InvalidUnavailableHARQReception');
end

function o=localBuffer(samples,first,fs)
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
o.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end
function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
