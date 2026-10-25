function ok=testRAULTimingRetention()
% Actual coded SetupComplete DM-RS -> retained clock -> actual Format0.
% Declared TAG/final-RNTI/control lifecycle and unit channel, not full access
% or shared RF qualification. No SRS is prepared or received by this test.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
cfg.phy.carrier.NCellID=42;
cfg.lls6g.userContext.RuntimeServingCell=1;
ra=sixgr.mac.ra.RAConfig(cfg,'CellId',42,'UEId',1);
assert(ra.CellId==42 && ra.NCellID==42 && ra.ServingCell==1);
ra.SetupCompleteSlot=39;
cfg.phy.pusch.RNTI=ra.FinalCRNTI;
cfg.frequency.centerFrequencyHz=cfg.frequency.center_frequency_hz;
cfg.phy.frame.DefaultIdentity=struct('ScheduledCCID',0,'ULBWPID',0);
cfg.phy.synchronization.maxReceivedULTimingAgeSlots=4;
catalog=sixgr.lls6g.config.readConfigFile('simulator/configs/control/pucch_receiver_thresholds.yaml');
cfg.phy.pucch.receiverDetectionThresholds=catalog.pucch;
cfg.lls6g.receiverSync=struct('RuntimeWaveformSampleAligned',false);
carrier=sixgr.phy.grid.makeCarrier(cfg); nativeInfo=nrOFDMInfo(carrier); fs=nativeInfo.SampleRate;
tag=struct('DLReference',struct('NCellID',42,'SampleRateHz',fs, ...
    'Source',"declared_component_received_DL_boundary"), ...
    'Offset',struct('NTAOffset_Tc',int64(25600)), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(1,30,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'Application',struct('EffectiveULSlot0Based',30), ...
    'TimeAlignmentExpirySampleExclusive',Inf);
cfg.SharedULTimingContext=tag;
grant=sixgr.mac.ra.buildRARULGrant(ra);
message=sixgr.mac.ra.buildRRCSetupComplete('UEIdentity','UE-1');
tx=sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,ra,grant,message);
nominal=sixgr.phy.frame.slotStartSample(tx.Carrier,39,fs);
% Exact pre-roll as in the failed run: 311 is capture-local, not a TA or
% globally aligned slot origin. The measured arrival is -397 from nominal.
samples=[complex(zeros(311,1));tx.Waveform;complex(zeros(339,1))];
observation=localBuffer(samples,nominal-708,fs);
[rx,decoded]=sixgr.phy.ra.recoverRRCSetupComplete(observation,cfg,ra,tx);
assert(rx.Ok && decoded.PayloadHash==message.PayloadHash && ...
    rx.ReceiveTiming.AppliedTimingCorrectionSamples==311 && ...
    ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
row=table(1,42,"RRCSetupComplete","UL",39,observation.StartSample, ...
    observation.EndSampleExclusive,fs,size(samples,1),true,false, ...
    'VariableNames',{'UEId','CellId','StageName','Direction','StageSlot', ...
    'ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz', ...
    'RxSampleCount','RuntimeStageWaveformUsed','SelfLoopWaveformUsed'});
result=struct('SetupCompleteRx',rx,'RACompleted',true,'SetupCompleteReceiverOk',true, ...
    'RRCSetupCompleteCRC',true,'RRCSetupCompleteDecoded',true,'RRCConnected',true, ...
    'FinalCRNTI',ra.FinalCRNTI,'RuntimeStageRows',row, ...
    'TimingAdvanceCommand',tag.ReceivedRARTiming.Command, ...
    'TimingAdvanceNTA_Tc',tag.ReceivedRARTiming.NTA_Tc, ...
    'TimingAdvanceSampleRate_Hz',fs);
% Identity installation is explicitly declared; its waveform producer is
% independently exercised above. Logical cell1 is not physical PCI42.
state=struct('NumUsers',1,'CurrentServingIdx',1, ...
    'MultiUser',struct('RNTIStart',ra.FinalCRNTI),'ConnectedULTimingByUE',{{tag}});
before=state;
state=sixgr.truth.retainReceivedRAULTimingReference(state,1,cfg,result,observation,observation.EndSampleExclusive);
reference=state.ReceivedULTimingReferences{1};
assert(reference.SourceSignal=="RRCSetupComplete_PUSCH_DMRS" && ...
    reference.ArrivalOffsetFromNominalSamples==-397 && ...
    reference.AvailableAtSample==observation.EndSampleExclusive && ...
    reference.NominalStartSample==nominal && reference.Identity.NCellID==42 && ...
    reference.Identity.RNTI==ra.FinalCRNTI && isequaln(reference.TAG,tag));
assert(isequaln(state,sixgr.truth.retainReceivedRAULTimingReference( ...
    state,1,cfg,result,observation,observation.EndSampleExclusive)));
[a,c,o]=localPUCCH(cfg,43,-397);
localReject(@()sixgr.link.receivePUCCHObservation(cfg,a,c,o,[]), ...
    'sixgr:phy:pucch:PUCCHTimingReferenceRequired');
prior=sixgr.truth.selectReceivedULTimingReference(state,1,o.EndSampleExclusive, ...
    sixgr.phy.frame.slotStartSample(carrier,43,fs));
received=sixgr.link.receivePUCCHObservation(cfg,a,c,o,prior);
assert(~received.DTX && received.CRCPassed && received.DecodedSequence1==1 && ...
    received.ReceiveTiming.ReferenceAgeSlots==4 && ...
    received.ReceiveTiming.AppliedTimingCorrectionSamples==311);
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,result, ...
    observation,observation.EndSampleExclusive-1),'sixgr:truth:FutureRAULTimingReference');
assert(isempty(sixgr.truth.selectReceivedULTimingReference(state,1,observation.EndSampleExclusive-1)));
bad=result; bad.RACompleted=false;
assert(isequaln(before,sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,bad,observation,observation.EndSampleExclusive)));
bad=result; bad.SetupCompleteRx.ReceivedULTimingReceipt.Stage="Msg3";
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,bad,observation,observation.EndSampleExclusive), ...
    'sixgr:truth:RAULTimingIdentityMismatch');
bad=result; bad.FinalCRNTI=ra.FinalCRNTI+1;
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,bad,observation,observation.EndSampleExclusive), ...
    'sixgr:truth:RAULTimingIdentityMismatch');
bad=result; bad.RuntimeStageRows.CellId=1;
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,bad,observation,observation.EndSampleExclusive), ...
    'sixgr:truth:RAULTimingStageMismatch');
changed=samples; changed(312)=changed(312)+1;
other=localBuffer(changed,observation.StartSample,fs);
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,cfg,result,other,other.EndSampleExclusive), ...
    'sixgr:phy:sync:RATimingObservationMismatch');
bad=cfg; bad.SharedULTimingContext.Offset.NTAOffset_Tc=int64(0);
localReject(@()sixgr.truth.retainReceivedRAULTimingReference(before,1,bad,result,observation,observation.EndSampleExclusive), ...
    'sixgr:truth:RAULTimingTAGMismatch');
[a5,c5,o5]=localPUCCH(cfg,44,-397);
localReject(@()sixgr.link.receivePUCCHObservation(cfg,a5,c5,o5,reference), ...
    'sixgr:phy:sync:StaleULTimingReference');
bad=cfg; bad.phy.carrier.NCellID=43;
localReject(@()reference.alignCompletedObservation(bad,o,43), ...
    'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
fprintf('RA_UL_TIMING_RETENTION_PASS actual_SetupComplete=1 actual_Format0=1 age4=1 arrival=-397 no_SRS=1 declared_TAG_and_identity=1 full_access=0\n');
ok=true;
end

function [assignment,context,observation]=localPUCCH(cfg,slot0,arrival)
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,int8(1), ...
    'RNTI',cfg.phy.pusch.RNTI,'NSizeGrid',51,'SCS',30);
carrier=f.Carrier; carrier.NCellID=cfg.phy.carrier.NCellID;
carrier.NFrame=floor(slot0/carrier.SlotsPerFrame); carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
reportData=f.Report.Data; reportData.TargetSlot=slot0+1;
report=sixgr.phy.pucch.UCIReport(reportData);
frame=f.FrameState; frame.PDSCHEndSlot=slot0; frame.TargetSlot=slot0+1;
tx=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(report,f.UEContext,frame);
context=sixgr.phy.pucch.UCIReportContext.fromReport(report);
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',"ra-clock-f0-"+slot0,'ResourceID',tx.Resource.ID, ...
    'RNTI',cfg.phy.pusch.RNTI,'AbsoluteSlot0',slot0, ...
    'Source','independent_component_receiver_resource','TimingSource','received_UL_pilot'),f.RRCContext,context);
wave=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,tx,report);
info=nrOFDMInfo(carrier); nominal=sixgr.phy.frame.slotStartSample(carrier,slot0,info.SampleRate);
samples=[complex(zeros(708+arrival,1));wave.Waveform;complex(zeros(339,1))];
observation=localBuffer(samples,nominal-708,info.SampleRate);
end

function observation=localBuffer(samples,first,fs)
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
observation.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end

function localReject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
