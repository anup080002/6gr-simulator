function ok=testReceivedSSBTimingDelivery()
% Original shared BCH timing for two beams, distinct from retained MIB/SI.
% The 0->1 selection is an explicitly declared reducer-boundary policy over
% actually decoded candidates, not an optimum-beam or full Msg1 qualification.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','received_ssb_timing_delivery',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('RECEIVED_SSB_TIMING_EVIDENCE %s\n',folder);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),30);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
fs=owner.SampleRateHz; carrier=sixgr.phy.grid.makeCarrier(cfg);

% One actual composite capture supplies the initial accepted BCH and SIB1.
% The later tracking capture is SSB-only and cannot replace either object.
[state,item,received,contexts,post]=localReceive(state,cfg,0,"SSB_MIB_SIB1",0,[],folder);
initial=received.CandidateResults{1}.SIB1;
assert(initial.BCHCRCValid && initial.MIBDecoded && initial.CandidateIdentityConsistent && ...
    initial.SSBIdentityVerified && initial.StrictOk && initial.DCICrcPass && initial.DLSCHCrcPass);
mib=sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,item,contexts{1}, ...
    initial.ReceivedDLTimingReference,post);
timing=sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,item,contexts{1}, ...
    initial.ReceivedDLTimingReference,post);
row=localRows(state,item,received,0);
state=sixgr.truth.BroadcastResultDelivery.enqueue(state,1,row,initial,false,mib,{timing});
clock=owner.Events.NextSampleIndex; before=rng;
[waiting,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
assert(isempty(ready) && sixgr.truth.BroadcastResultDelivery.hasPending(waiting,1));
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.current(waiting,1,cfg,0), ...
    'sixgr:truth:ReceivedSSBTimingDeliveryClockRequired');
state.CurrentSlot=state.CurrentSlot+1;
assert(clock==sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,fs));
[available,status]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,1,cfg,0);
assert(~available && status=="stale_selected_ssb_timing"); % No acquisition delivered yet.
[state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
assert(isscalar(ready) && isequaln(ready.TimingBindings,{timing}));
state=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,1,ready.Trial);
[state,installed]=sixgr.truth.ReceivedMIBDelivery.deliver(state,ready.MIBBinding); assert(installed);
[valid,~,mib]=sixgr.truth.ReceivedMIBDelivery.current(state,1); assert(valid);
state=sixgr.truth.installReceivedSIB1Recovery(state,1,initial,state.CurrentSlot,mib);
[state,installed]=sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,timing,ready.Trial); assert(installed);
[valid,status,firstTiming]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,1,cfg,0);
assert(valid && status=="current_delivered_selected_ssb_timing" && ...
    isequaln(firstTiming.ReceivedDLTimingReference,initial.ReceivedDLTimingReference) && ...
    firstTiming.DeliveredAvailableSample==clock && firstTiming.DeliveredAvailableSample<=owner.Events.NextSampleIndex);
assert(owner.Events.NextSampleIndex==clock && isequal(before,rng));
protected=localProtected(state);
assert(protected.Common{1}.Source=="decoded_sib1" && ...
    protected.Common{1}.ReceivedDLTimingReference.SSBIndex==0 && ...
    protected.MIB{1}.Context.Data.SSBIndex==0);

% Advance original idle RF/channel/noise samples to the next broadcast, not
% a manually modified owner clock or a relocated frame-zero waveform.
start=sixgr.phy.frame.slotStartSample(carrier,20,fs);
while owner.Events.NextSampleIndex<start
    [state,none]=owner.advanceSlot(state,cfg); assert(isempty(none));
    state.CurrentSlot=state.CurrentSlot+1;
end
assert(owner.Events.NextSampleIndex==start && state.CurrentSlot==21);
[state,trackingItem,tracking,trackingContexts,trackingPost]= ...
    localReceive(state,cfg,20,"SSB_MIB",[0 1],mib,folder);
originalTracking=tracking;
bindings=cell(1,2);
for k=1:2
    r=tracking.CandidateResults{k}.SIB1;
    assert(r.BCHCRCValid && r.MIBDecoded && r.CandidateIdentityConsistent && ...
        r.SSBIdentityVerified && ~r.SIB1ReceptionAttempted && r.SSBIndex==k-1);
    bindings{k}=sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,trackingItem, ...
        trackingContexts{k},r.ReceivedDLTimingReference,trackingPost,mib);
end
assert(isequaln(localProtected(state),protected));
trackingRows=localRows(state,trackingItem,tracking,1);
pending=sixgr.truth.BroadcastResultDelivery.enqueue(state,1,trackingRows,struct(),true,[],bindings);
clock=owner.Events.NextSampleIndex; before=rng; originalHash=trackingPost.sampleHash();
[pending,notYet]=sixgr.truth.BroadcastResultDelivery.takeAvailable(pending);
assert(isempty(notYet));
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.deliver(pending,bindings{2},trackingRows), ...
    'sixgr:truth:ReceivedSSBTimingDeliveryClockRequired');
pending.CurrentSlot=pending.CurrentSlot+1;
assert(clock==sixgr.phy.frame.slotStartSample(carrier,pending.CurrentSlot-1,fs));
[valid,status]=sixgr.truth.ReceivedSSBTimingDelivery.current(pending,1,cfg,1);
assert(~valid && status=="no_delivered_selected_ssb_timing", ...
    'A physically completed but undelivered candidate must not become a selected UL clock.');
[raCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,pending,1,'UL');
raCfg.random_access.associated_ssb_index=1;
accessBefore=localAccessSHA(pending);
[denied,decision]=sixgr.truth.bindSharedRAPowerReference(raCfg,pending,1,pending.CurrentSlot);
assert(~decision.ReferenceUsable && ~decision.SelectedSSBTimingAvailable && ...
    decision.Status=="no_available_selected_ssb_timing" && ...
    ~isfield(denied,'SharedULTimingContext') && ~isfield(denied,'SharedRATimingBinding') && ...
    localAccessSHA(pending)==accessBefore && owner.Events.NextSampleIndex==clock && isequal(before,rng));
[state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(pending);
assert(isscalar(ready) && ready.TrackingOnly && isequaln(ready.TimingBindings,bindings));
state=sixgr.truth.CoupledTruthRuntime.applyServingSSBTrackingTrial(state,1,ready.Trial);
assert(state.SelectedSSBIndexByUE(1)==1 && state.LastSuccessfulPBCHSlotByUE(1)==mib.DeliverySlot);
for k=1:2
    [state,installed]=sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{k},ready.Trial);
    assert(installed);
end
[valid,status,selected]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,1,cfg,1);
assert(valid && status=="current_delivered_selected_ssb_timing" && ...
    selected.ReceivedDLTimingReference.SSBIndex==1 && ...
    selected.ReceivedDLTimingReference.AvailableAtSample==trackingPost.EndSampleExclusive && ...
    selected.DeliveredAvailableSample==clock && ...
    isequaln(selected.ReceivedDLTimingReference,tracking.CandidateResults{2}.SIB1.ReceivedDLTimingReference));
[valid,~,otherBeam]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,1,cfg,0);
assert(valid && isequaln(otherBeam.ReceivedDLTimingReference,tracking.CandidateResults{1}.SIB1.ReceivedDLTimingReference));
[again,installed]=sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{2},ready.Trial);
assert(installed && isequaln(again.ReceivedSSBTimingByUE,state.ReceivedSSBTimingByUE));
assert(isequaln(localProtected(state),protected), ...
    'Tracking timing must not replace original acquisition MIB, received SI, or its common UL offset.');
[raCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
raCfg.random_access.associated_ssb_index=state.SelectedSSBIndexByUE(1);
accessBefore=localAccessSHA(state);
[admitted,decision]=sixgr.truth.bindSharedRAPowerReference(raCfg,state,1,state.CurrentSlot);
assert(decision.ReferenceUsable && decision.SelectedSSBTimingAvailable && ...
    decision.SelectedSSBTimingBindingSHA256==selected.BindingSHA256 && ...
    decision.SelectedSSBTimingDeliveredAtSample==selected.DeliveredAvailableSample && ...
    isequaln(admitted.SharedRATimingBinding,selected) && ...
    isequaln(admitted.SharedULTimingContext.DLReference,selected.ReceivedDLTimingReference) && ...
    isequaln(admitted.SharedULTimingContext.Offset,protected.Common{1}.ULTimingAdvanceOffset) && ...
    localAccessSHA(state)==accessBefore);
% Exercise the same pure clock mapper used by actual shared Msg1. This is
% not a generated/transmitted PRACH waveform or a detection trial.
nominal=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot+2,fs);
ulClock=sixgr.phy.ra.sharedULStageTiming(admitted,nominal/fs,fs,1,0);
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
offset=double(protected.Common{1}.ULTimingAdvanceOffset.NTAOffset_Tc)/ticksPerSample;
assert(ulClock.TransmitStartSample==nominal+selected.ReceivedDLTimingReference.DLPhaseOffsetSamples-offset && ...
    ulClock.ReceiveStartSample==nominal-offset-ulClock.ReceiveSearchGuardSamples && ...
    ulClock.NTA_Tc==0 && isequaln(ulClock.DLReference,selected.ReceivedDLTimingReference));
assert(owner.Events.NextSampleIndex==clock && isequal(before,rng) && ...
    trackingPost.sampleHash()==originalHash && isequaln(tracking,originalTracking));

% Identity/availability negatives operate only on copies of original
% evidence. No synthetic reference, new receiver call, or physical mutation.
localIdentityNegatives(state,cfg,trackingItem,trackingContexts,trackingPost,mib,bindings,ready.Trial);
for kind=["lost","cell","acquisition","configuration"]
    stale=state;
    switch kind
        case "lost", stale.CellAcquisitionState(1)="searching";
        case "cell", stale.CurrentServingIdx(1)=2;
        case "acquisition", stale.LastSuccessfulPBCHSlotByUE(1)=state.CurrentSlot;
        case "configuration", stale.CfgMobility.initial_access.configuration_epoch= ...
                stale.CfgMobility.initial_access.configuration_epoch+1;
    end
    [valid,~]=sixgr.truth.ReceivedSSBTimingDelivery.current(stale,1,stale.CfgMobility,1);
    assert(~valid,'A stale %s must not resolve selected-beam timing.',kind);
    [unchanged,installed]=sixgr.truth.ReceivedSSBTimingDelivery.deliver(stale,bindings{2},ready.Trial);
    assert(~installed && isequaln(unchanged.ReceivedSSBTimingByUE,stale.ReceivedSSBTimingByUE));
end
[valid,~]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,2,cfg,1); assert(~valid);
[valid,~]=sixgr.truth.ReceivedSSBTimingDelivery.current(state,1,cfg,3); assert(~valid);
assert(owner.Events.NextSampleIndex==clock && isequal(before,rng) && ...
    trackingPost.sampleHash()==originalHash && isequaln(localProtected(state),protected));
save(fullfile(folder,'original_delivered_timing.mat'),'cfg','mib','firstTiming','bindings', ...
    'selected','otherBeam','protected','row','trackingRows','decision','ulClock');
fprintf('RECEIVED_SSB_TIMING_PASS original_BCH_receivers=3 original_SI_receivers=1 declared_selection=0_to_1 Msg1_waveform=0 root=%s\n',folder);
ok=true;
end

function [state,item,received,contexts,post]=localReceive(state,cfg,slot0,scope,candidates,acquisition,folder)
owner=state.SharedWaveformStream;
prototype=sixgr.link.runCellSearch_MIB_SIB1(cfg,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',slot0,'Content',scope,'NumSubframes',5);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
p=prototype.PreparedBroadcast;
context=struct('Config',cfg,'Slot',slot0+1,'Frame',floor(slot0/10)+1,'RNTI',1, ...
    'ServingCell',1,'SNR',20,'Prototype',prototype,'TrackingOnly',~isempty(acquisition));
if ~isempty(acquisition), context.AcquisitionMIBBinding=acquisition; end
owner.queueDownlink('PBCH',1,p,context);
item=[];
while isempty(item)
    [state,completed]=owner.advanceSlot(state,cfg);
    for candidate=completed
        if candidate.Kind=="PBCH", item=candidate; end
        % Per-occasion captures complete normally, but are not decoded by
        % this full-burst timing-owner test (no per-occasion update claim).
    end
    if isempty(item), state.CurrentSlot=state.CurrentSlot+1; end
end
[~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
prototype.RuntimeChannelReplay=replay;
prototype.RuntimeDLChannelState=owner.channelState(1,'DL');
prototype.PowerContext=p.PowerContext; prototype.RuntimeChannelStateUsed=true;
options=struct('UseRuntimeChannel',true,'RuntimeSlot',slot0,'CandidateSSBIndices',candidates, ...
    'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','received_ssb_timing_delivery', ...
    'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
before=rng; clock=owner.Events.NextSampleIndex; hash=post.sampleHash();
[received,contexts]=sixgr.link.completeCellSearchBroadcast(p,post,prototype,options,tic);
save(fullfile(folder,sprintf('original_BCH_slot%d.mat',slot0)), ...
    'item','received','contexts','p','-v7.3');
assert(isequal(before,rng) && owner.Events.NextSampleIndex==clock && post.sampleHash()==hash && ...
    numel(received.CandidateResults)==numel(candidates));
end

function rows=localRows(state,item,received,selected)
rows=table(); owner=state.SharedWaveformStream;
for k=1:numel(received.CandidateResults)
    q=received.CandidateResults{k}; r=q.SIB1;
    row=table(double(item.Context.Slot),double(item.UE),double(item.Context.ServingCell), ...
        q.ObservationStartSample,q.ObservationEndSampleExclusive,q.ObservationSampleRateHz, ...
        q.ObservationCompletionTime_s,string(q.ObservationCoverageSource), ...
        'VariableNames',{'Slot','UEId','ServingCell','ObservationStartSample','ObservationEndSampleExclusive', ...
        'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource'});
    for name=["BCHCRCValid","MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified", ...
            "PBCHStrictReceiverEvidenceOk","SSBIndex","NCellID","SS_RSRP_dBm", ...
            "SS_RSRP_dB_re_UnitOccupiedRE_Es","SS_SINR_dB","SSSINRMeasurementMethod", ...
            "SSSINRReferencePlane","PowerReferencePlane","SSBPhysicalMeasurementReferencePlane"]
        if isfield(r,name), row.(name)=r.(name);
        elseif isfield(q,name), row.(name)=q.(name); end
    end
    row.CRCPass=logical(r.BCHCRCValid);
    row.RequestedSSBOccasionIndex=q.RequestedSSBOccasionIndex;
    row.ReferenceSignalId=r.SSBIndex;
    row.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
    row.ReferenceConfigurationEpoch=item.Context.Config.initial_access.configuration_epoch;
    row.ResultCompletedAtSample=owner.Events.NextSampleIndex;
    row.SelectedBeamFlag=logical(r.SSBIndex==selected);
    row.SelectedSSBIndex=double(selected); row.SelectedBeamIndex=double(selected);
    metric=r.SS_RSRP_dBm;
    if ~isfinite(metric), metric=r.SS_RSRP_dB_re_UnitOccupiedRE_Es; end
    assert(isfinite(metric),'Use an actual finite received selection operand.');
    row.SelectionMetricValue_dB=double(metric);
    row.SelectionSource="declared_test_candidate_choice_with_original_received_power_not_optimum_selection";
    if isempty(rows), rows=row; else, rows=[rows;row]; end %#ok<AGROW>
end
assert(rows.SelectedBeamFlag(end));
end

function value=localProtected(state)
value=struct('Common',{state.UECommonCellConfigurationByUE}, ...
    'Recovery',{state.DecodedSIB1RecoveryByUE},'MIB',{state.ReceivedMIBByUE}, ...
    'AcquisitionState',state.CellAcquisitionState,'AcquisitionSlot',state.LastSuccessfulPBCHSlotByUE);
end

function localIdentityNegatives(state,cfg,item,contexts,post,mib,bindings,trial)
% A copied completed item cannot rewrite the original armed acquisition,
% even when the caller supplies the same replacement to the timing binder.
bad=item; bad.Context.TrackingOnly=false;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,mib),'sixgr:truth:BroadcastCompletedCaptureMismatch');
replacementMIB=mib; replacementMIB.BindingSHA256=string(repmat('0',1,64));
bad=item; bad.Context.AcquisitionMIBBinding=replacementMIB;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,replacementMIB),'sixgr:truth:BroadcastCompletedCaptureMismatch');
bad=item; bad.Context=rmfield(bad.Context,'AcquisitionMIBBinding'); bad.Context.TrackingOnly=false;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,[]),'sixgr:truth:BroadcastCompletedCaptureMismatch');
bad=item; bad.UE=2;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,mib),'sixgr:truth:BroadcastCompletedCaptureMismatch');
bad=item; bad.Context.Prepared.ReceiverConfig.initial_access.configuration_epoch= ...
    bad.Context.Prepared.ReceiverConfig.initial_access.configuration_epoch+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,mib),'sixgr:phy:broadcast:ReceivedMIBGeometryChanged');
bad=bindings{2}.ReceivedDLTimingReference; bad.AvailableAtSample=bad.AvailableAtSample+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,item,contexts{2},bad,post,mib), ...
    'sixgr:truth:ReceivedMIBTimingMismatch');
bad=bindings{2}.ReceivedDLTimingReference; bad.SSBIndex=0;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,item,contexts{2},bad,post,mib), ...
    'sixgr:truth:ReceivedMIBTimingMismatch');
bad=item; j=find(endsWith(string({bad.Planes.ReceiverID}),':post_rf'));
raw=bad.Planes(j).Observation; x=raw.readComplete(); x(1)=x(1)+1;
replacement=sixgr.phy.waveform.WaveformObservationBuffer(raw.StartSample,raw.EndSampleExclusive, ...
    raw.SampleRateHz,size(x,2));
replacement.append(sixgr.phy.waveform.WaveformChunk(x,raw.StartSample),raw.SampleRateHz);
bad.Planes(j).Observation=replacement;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted(state,bad,contexts{2}, ...
    bindings{2}.ReceivedDLTimingReference,post,mib),'sixgr:truth:BroadcastCompletedCaptureMismatch');
for name=["SSBIndex","ReceivedDLTimingReference","Delivered","AcquisitionGenerationAtCapture"]
    bad=bindings{2};
    switch name
        case "SSBIndex", bad.SSBIndex=0;
        case "ReceivedDLTimingReference", bad.ReceivedDLTimingReference.DLPhaseOffsetSamples= ...
                bad.ReceivedDLTimingReference.DLPhaseOffsetSamples+1;
        case "Delivered", bad.Delivered=0; % Numeric false is not an original logical receipt flag.
        case "AcquisitionGenerationAtCapture", bad.AcquisitionGenerationAtCapture=string(repmat('0',1,64));
    end
    reject(@()sixgr.truth.ReceivedSSBTimingDelivery.validate(bad,false),'sixgr:truth:InvalidReceivedSSBTiming');
end
bad=bindings{2}; bad.OriginalBCHBinding.PhysicalConfigurationEpoch= ...
    bad.OriginalBCHBinding.PhysicalConfigurationEpoch+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.validate(bad,false),'sixgr:truth:InvalidReceivedMIBDelivery');
bad=trial; bad.SSBIndex(2)=0;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{2},bad), ...
    'sixgr:truth:ReceivedSSBTimingCandidateMismatch');
bad=trial; bad.ResultAvailableAtSample(2)=bad.ResultAvailableAtSample(2)+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{2},bad), ...
    'sixgr:truth:ReceivedSSBTimingCandidateMismatch');
bad=trial; bad.MeasurementClockEpoch(2)=bad.MeasurementClockEpoch(2)+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{2},bad), ...
    'sixgr:truth:ReceivedSSBTimingCandidateMismatch');
bad=trial; bad.CandidateIdentityConsistent(2)=false;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.deliver(state,bindings{2},bad), ...
    'sixgr:truth:ReceivedSSBTimingCandidateMismatch');
bad=state; bad.CurrentSlot=state.CurrentSlot+1;
reject(@()sixgr.truth.ReceivedSSBTimingDelivery.current(bad,1,cfg,1), ...
    'sixgr:truth:ReceivedSSBTimingDeliveryClockRequired');
reject(@()sixgr.truth.BroadcastResultDelivery.enqueue(state,1,trial,struct(),true,[], ...
    {bindings{2},bindings{2}}),'sixgr:truth:ReceivedSSBTimingCandidateMismatch');
end

function digest=localAccessSHA(state)
value=struct();
for name=["PendingRAAttempts","RARetryByUE","LastPRACHSlotByUE", ...
        "HARQTimelineTable","HARQSummaryTable","SharedGNBULHARQReceivers", ...
        "SharedGNBULHARQCommands"]
    if isfield(state,name), value.(name)=state.(name); end
end
digest=sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(value));
end

function reject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message); return;
end
error('test:MissingSSBTimingRejection','Expected %s.',identifier);
end
