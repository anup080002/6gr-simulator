function ok=testRuntimeTimingAdvancePlanes()
% Core state regression. Hand-built numeric rows test plane ownership;
% native pilot/capture invariance is checked separately below.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state.CurrentSlot=30; state.CurrentCanonicalSlot=30; state.CurrentServingIdx(:)=1;
state.LastTimingAdvanceSamplesByUE(:)=12;
state.LastTimingAdvanceUsByUE(:)=12/7.68e6*1e6;
state.LastTimingAdvanceSourceByUE(:)="retained_component_TA_baseline";
state.TimeAlignmentState(:)="existing_alignment";
for trim=[32 77 91]
    row=table(30,trim,trim,trim,NaN, ...
        'VariableNames',{'Slot','TimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples', ...
        'TimingError_samples','TimingAdvance_samples'});
    after=sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceFromReceiverTrialRuntime( ...
        state,1,row,'ul_data_receiver_timing_estimate');
    assert(isequaln(after,state),'sixgr:test:CaptureTrimBecameTA', ...
        'A %g-sample capture extraction must not change TA or clear drift state.',trim);
end
% Typed initial-TAG commands come through the actual SIB1/RAR conversion.
% This is a declared component input, not a claim of physical random access.
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
[installed,~]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,decoded);
common=installed.UECommonCellConfiguration;
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier); fs=info.SampleRate;
common.ReceivedDLTimingReference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',0,'AvailableAtSample',1000,'NCellID',carrier.NCellID);
common.ULTimingAdvanceOffset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1');
state.UECommonCellConfigurationByUE={common;common};
for ue=1:2
    state.ConnectedULTimingByUE{ue}=sixgr.mac.ra.connectedTimingFromRAR( ...
        cfg,common,struct('TimingAdvanceCommand',3*(ue-1)),16,17*fs/1000,fs);
end
pending=state; pending.CurrentSlot=18; pending.CurrentCanonicalSlot=18;
pending=sixgr.truth.CoupledTruthRuntime.refreshControlState(pending);
assert(all(isnan(pending.LastTimingAdvanceSamplesByUE)), ...
    'A received command must not become applied TA before its application clock.');
state=sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
assert(isequal(state.LastTimingAdvanceSamplesByUE,[0;12]) && ...
    all(state.LastTimingAdvanceSourceByUE=="received_initial_TAG_RAR"));
assert(abs(state.LastTimingAdvanceUsByUE(2)-12/fs*1e6)<eps);
e=sixgr.truth.receivedULTimingEvidence(state,2);
assert(e.ReceivedTimingAdvanceCommand==3 && e.ReceivedTimingAdvanceNTA_Tc==3072 && ...
    e.ReceivedTimingAdvanceOffset_Tc==25600 && e.ReceivedTimingAdvanceTotalSamples==112 && ...
    e.TimingAdvanceCommandStatus=="effective",'Unexpected command-plane evidence: %s',jsonencode(e));
row.TimingAdvance_samples=77; row.TimingAdvanceValueRole="receiver_estimated_ta_not_command";
unchanged=sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceFromReceiverTrialRuntime( ...
    state,2,row,'srs_receiver_timing_estimate');
assert(isequaln(unchanged,state),'Receiver observations cannot overwrite a received TAG command.');

% Actual pilot correlation: changing capture pre-roll changes extraction,
% not measured arrival or the separately received command. A real sample
% delay changes only the arrival estimate. No TX origin is passed as an
% estimate to ReceivedULTimingReference.
guards=[32 77]; extraction=zeros(1,2); arrival=zeros(1,2);
for k=1:2
    [reference,extraction(k)]=localMeasuredReference(cfg,state.ConnectedULTimingByUE{2},guards(k),0);
    arrival(k)=reference.ArrivalOffsetFromNominalSamples;
end
assert(isequal(extraction,[20 65]) && isequal(arrival,[-112 -112]));
[delayed,~]=localMeasuredReference(cfg,state.ConnectedULTimingByUE{2},77,5);
assert(delayed.ArrivalOffsetFromNominalSamples==-107);
state=sixgr.truth.storeReceivedULTimingReference(state,2,reference);
% Completion must be known before it is published, even if present in a
% poisoned future snapshot. This does not alter the actual command plane.
e=sixgr.truth.receivedULTimingEvidence(state,2);
assert(isnan(e.ULArrivalOffsetFromNominal_samples));
state.CurrentSlot=32; state.CurrentCanonicalSlot=32;
e=sixgr.truth.receivedULTimingEvidence(state,2);
assert(e.ULArrivalOffsetFromNominal_samples==-112 && e.ULCaptureExtractionOffset_samples==65 && ...
    e.ReceivedTimingAdvanceSamples==12 && e.ULArrivalReferenceStatus=="measured");
artifacts=sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
t=artifacts.ControlGatingStateTable;
assert(t.LastTimingAdvance_samples(2)==12 && t.ULArrivalOffsetFromNominal_samples(2)==-112 && ...
    isnan(t.ULArrivalOffsetFromNominal_samples(1)) && t.ReceivedTimingAdvanceOffset_Tc(2)==25600);
moving=state; moving.ControlGating.TimingAdvanceUpdateMode="geometry_predictive";
moving.ControlGating.TimingAdvanceUpdateThresholdSamples=0.01;
moving.MobilityEnabled=false; moving.UE.pos_m(2,3)=moving.UE.pos_m(2,3)+100;
moving=sixgr.truth.CoupledTruthRuntime.advanceFrame(moving,cfg,multi,4,10);
assert(moving.LastTimingAdvanceSamplesByUE(2)==12 && ...
    moving.LastTimingAdvanceSourceByUE(2)=="received_initial_TAG_RAR", ...
    'A geometry prediction cannot rewrite an actual received command.');
bad=state; bad.ConnectedULTimingByUE{2}.DLReference.NCellID=carrier.NCellID+1;
localReject(@()sixgr.truth.receivedULTimingEvidence(bad,2),'sixgr:truth:ReceivedULTimingServingCellMismatch');
bad=state; bad.UECommonCellConfigurationByUE{2}.InitialULBWP.SubcarrierSpacing_kHz=30;
localReject(@()sixgr.truth.receivedULTimingEvidence(bad,2),'sixgr:truth:ConnectedULTimingBWPChanged');
bad=state; bad.CfgMobility.phy.carrier.NSizeGrid=24;
localReject(@()sixgr.truth.receivedULTimingEvidence(bad,2),'sixgr:truth:TimingEvidenceIdentityMismatch');
bad=state; bad.CfgMobility.phy.frame.DefaultIdentity.ULBWPID=1;
localReject(@()sixgr.truth.receivedULTimingEvidence(bad,2),'sixgr:truth:TimingEvidenceIdentityMismatch');
% A retained old pilot is historical evidence, never a fresh alignment.
stale=state; stale.CurrentSlot=100; stale.CurrentCanonicalSlot=100;
e=sixgr.truth.receivedULTimingEvidence(stale,2);
assert(e.ULArrivalReferenceStatus=="measured_stale_not_current_alignment");
expired=state;
expired.ConnectedULTimingByUE{2}.TimeAlignmentExpirySampleExclusive=29*fs/1000;
expired=sixgr.truth.CoupledTruthRuntime.refreshControlState(expired);
assert(expired.TimeAlignmentState(2)=="received_TAG_expired" && expired.TimingAdvanceUpdateRequiredByUE(2));
removed=state; removed.ConnectedULTimingByUE{2}=[];
removed=sixgr.truth.CoupledTruthRuntime.refreshControlState(removed);
assert(isnan(removed.LastTimingAdvanceSamplesByUE(2)) && removed.LastTimingAdvanceSourceByUE(2)=="");
fprintf('RUNTIME_TIMING_ADVANCE_PLANES_PASS native_pilot=1 capture_guard_invariant=1 physical_RA_qualified=0\n');
ok=true;
end

function [reference,estimate]=localMeasuredReference(cfg,tag,guard,delay)
slot0=30; carrier=sixgr.phy.grid.makeCarrier(cfg);
carrier.NFrame=floor(slot0/carrier.SlotsPerFrame); carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
srs=nrSRSConfig('NumSRSPorts',4,'SRSPeriod',[1 0], ...
    'SymbolStart',carrier.SymbolsPerSlot-3,'NumSRSSymbols',1);
grid=nrResourceGrid(carrier,4); indices=nrSRSIndices(carrier,srs); grid(indices)=nrSRS(carrier,srs);
[waveform,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0); fs=ofdm.SampleRate;
cfg.phy.pusch.RNTI=2; cfg.SharedULTimingContext=tag;
cfg.phy.synchronization.maxTimingUncertaintySamples=guard;
cfg.phy.synchronization.maxTimingUncertainty_us=[];
cfg.lls6g.userContext.RuntimeSlotStartTime_s=sixgr.phy.frame.slotStartSample(carrier,slot0,fs)/fs;
cfg.lls6g.runtime.AbsoluteSlotIndex0=slot0;
[waveform,cfg.lls6g.runtimePowerContext]=sixgr.rf.applyPowerContext( ...
    waveform,cfg,'UL',struct('OFDMInfo',ofdm),'ApplyPA',false);
tx=struct('Carrier',carrier,'Waveform',waveform,'SRSIndices',indices,'PowerContext',cfg.lls6g.runtimePowerContext);
prepared=sixgr.link.PreparedUplinkControlTransmission('SRS',cfg, ...
    struct('TimingAdvanceSamples',tag.ReceivedRARTiming.Samples),tx,struct('OFDMInfo',ofdm),cfg,slot0,struct());
first=prepared.ReceiveStartSample; last=prepared.ReceiveEndSampleExclusive;
y=complex(zeros(last-first,prepared.NumReceiveAntennas));
assert(size(y,2)==size(waveform,2));
offset=prepared.StartSample+delay-first;
y(offset+(1:size(waveform,1)),:)=waveform;
observed=sixgr.phy.waveform.WaveformObservationBuffer(first,last,fs,size(y,2));
observed.append(sixgr.phy.waveform.WaveformChunk(y,first),fs);
estimate=nrTimingEstimate(carrier,y,grid);
timing=struct('AppliedTimingCorrectionSamples',estimate,'DemodulatedSampleCount',size(waveform,1), ...
    'TimingSource',"received_reference_correlation_bounded_search", ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
reference=sixgr.phy.sync.ReceivedULTimingReference(prepared,observed,timing);
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s.',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
