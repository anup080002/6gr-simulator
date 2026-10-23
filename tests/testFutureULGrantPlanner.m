function ok=testFutureULGrantPlanner()
% Numerical planner boundary with explicitly declared installation/feedback.
% No received SRS, DCI, waveform, initial-access or full-scenario claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
nativeUCI=exist('nrULSCHMultiplex','file')==2 && exist('nrULSCHDemultiplex','file')==2 && ...
    exist('nrUCIEncode','file')==2 && exist('nrUCIDecode','file')==2;
assert(sixgr.truth.isPUSCHUCIAvailable(struct())==nativeUCI);
for disabled=["disabled","off","none","pucch_only"]
    policy=cfg; policy.phy.pusch.uciMultiplexingMode=disabled;
    assert(~sixgr.truth.isPUSCHUCIAvailable(policy));
end
[controlSlot,timing]=localLegalTiming(cfg);
dueSlot=double(timing.DataAbsoluteSlot)+1;
horizon=max(dueSlot+1,double(cfg.run.totalSlots));

% No legal control symbols means no timing event, allocation or state write.
off=struct('CurrentSlotDLAllowed',false,'CurrentSlotDLNumSymbols',0);
[unchanged,g,info]=sixgr.truth.planFutureULGrants(off,cfg,{cfg},struct([]),1,horizon);
assert(isequaln(unchanged,off) && isempty(g) && ~info.ScheduleAttempted && ...
    info.Status=="no_dl_control_symbols");

% Future traffic is not demand at this control decision. The unchanged
% production gates may also block this unacquired numerical fixture.
state=localState(cfg,controlSlot,horizon,false);
state.ULQueueBits(:)=0;
state.Traffic.OfferedBitsUL(dueSlot,:)=1e6;
before=localSnapshot(state); stats=state.ULHarq.Stats;
[planned,g,info]=sixgr.truth.planFutureULGrants(state,cfg,{cfg},struct([]),1,horizon);
assert(isempty(g) && info.ScheduleAttempted && info.Status=="no_scheduler_grants");
assert(info.Opportunity.EligibleForUEScheduling && info.ControlSlot==controlSlot && ...
    info.DataSlot==dueSlot && info.K2==double(timing.K2));
assert(height(planned.SchedulerAdmissionTable)==height(state.SchedulerAdmissionTable)+1);
admission=planned.SchedulerAdmissionTable(end,:);
assert(admission.QueueBytes==0 && ~admission.HasTrafficDemand && ...
    admission.ControlSlot==controlSlot && admission.ScheduledDataSlot==dueSlot && ...
    admission.SchedulingKnowledgeSlot==controlSlot && ...
    admission.TrafficKnowledgeThroughSlot<=controlSlot);
assert(isequaln(localSnapshot(planned),before) && isequaln(planned.ULHarq.Stats,stats));
assert(~isfield(info,'PlanState') && ~isfield(planned,'PlanningDecisionSlot'));
assert(height(planned.ULPlanningOpportunityTable)==1 && ...
    height(planned.ULPlanningTimingCandidateTable)==numel(timing.DataAttempts));

% Timing evidence must survive early horizon/duplicate deferrals, before
% any scheduler or shared HARQ handle is touched.
for mode=["outside_horizon","queued_target"]
    pending=struct([]); limit=horizon;
    if mode=="outside_horizon", limit=dueSlot-1;
    else, pending=struct('Slot',dueSlot); end
    procs=state.ULHarq.UEProcs;
    [deferred,g,info]=sixgr.truth.planFutureULGrants(state,cfg,{cfg},pending,1,limit);
    assert(isempty(g) && ~info.ScheduleAttempted && ...
        info.Status=="timing_opportunity_deferred" && ...
        isequaln(localSnapshot(deferred),before) && isequaln(state.ULHarq.UEProcs,procs));
    reason="target_outside_current_sweep_horizon";
    if mode=="queued_target", reason="target_already_has_queued_UL_grant"; end
    assert(info.Opportunity.BlockReason==reason && height(deferred.ULPlanningOpportunityTable)==1);
end
bad=state; bad.CurrentCanonicalSlot=controlSlot+1;
localThrows(@()sixgr.truth.planFutureULGrants(bad,cfg,{cfg},struct([]),1,horizon), ...
    'sixgr:truth:InvalidULPlanningClock');
bad=cfg; bad.phy.pusch.symbolAllocation=[]; bad.phy.pusch.SymbolAllocation=[];
localThrows(@()sixgr.truth.planFutureULGrants(state,bad,{bad},struct([]),1,horizon), ...
    'sixgr:truth:MissingPUSCHTimingAllocation');
bad=cfg; bad.phy.pdcch.symbolAllocation=[13 2];
localThrows(@()sixgr.truth.planFutureULGrants(state,bad,{bad},struct([]),1,horizon), ...
    'sixgr:truth:PDCCHTimingOutsideDLPartition');

% Fresh separate handles: this fixture declares admission and accepted SRS,
% then executes the real scheduler, both freezes and DCI authoring ONCE.
state=localState(cfg,controlSlot,horizon,true);
before=localSnapshot(state); accepted=state.LatestULFeedback(1).AcceptedSRSSpatialDecision;
[planned,g,info]=sixgr.truth.planFutureULGrants(state,cfg,{cfg},struct([]),1,horizon);
assert(isscalar(g) && info.PlannedGrantCount==1 && info.ScheduleAttempted && ...
    info.Status=="tentative_grants_planned");
assert(g.ControlAbsoluteSlot==controlSlot-1 && g.ScheduledAbsoluteSlot==dueSlot-1 && ...
    g.Slot==dueSlot && g.ControlSlot==controlSlot && g.K2==timing.K2);
assert(g.PHYGrant.IsFrozen && isequaln(g.AcceptedSRSSpatialDecision,accepted) && ...
    isequaln(g.PHYGrant.PrecodingState.AcceptedSRSSpatialDecision,accepted) && ...
    g.AcceptedSRSDecisionContext.KnownAtSlot==controlSlot && ...
    g.AcceptedSRSCausalAgeSlots==dueSlot-accepted.ProducerSlot && ...
    ~isempty(g.DCI.Bits) && ~g.ControlDecodeOk);
assert(isequaln(localSnapshot(planned),before), ...
    'A future resource view must not overwrite live clocks, feedback, queues or grant traces.');
assert(isequal(planned.ULHarq,state.ULHarq) && ...
    isequal(planned.ULSchedulers{1},state.ULSchedulers{1}));
processes=[planned.ULHarq.UEProcs{:}];
assert(nnz([processes.Active])==1 && all([processes.TxCount]==0) && ...
    all([processes.ScheduledAttemptCount]==0), ...
    'One tentative allocation is not an issued command or transmitted TB.');
newRows=planned.SchedulerDecisionTable(height(state.SchedulerDecisionTable)+1:end,:);
assert(~isempty(newRows) && all(newRows.ControlSlot==controlSlot) && ...
    all(newRows.ScheduledDataSlot==dueSlot) && all(newRows.SchedulingKnowledgeSlot==controlSlot) && ...
    all(newRows.SchedulingTimingMode=="dci_k2_future_ul") && ...
    all(endsWith(string(newRows.ValueSource),":k2_future_slot_plan")));
% Provisional grants in the future view must not appear as received grants.
assert(isequaln(planned.ULGrantTraceTable,state.ULGrantTraceTable));

% Cached future feedback is rejected, not silently promoted to current.
future=localState(cfg,controlSlot,horizon,true);
future.LatestULFeedback(1).DeliveredSlot=controlSlot+1;
localThrows(@()sixgr.truth.planFutureULGrants(future,cfg,{cfg},struct([]),1,horizon), ...
    'sixgr:truth:NoncausalULPlanningFeedback');

% A separately declared pending HARQ resource forces an actual pre-DCI
% PUCCH-overlap cancellation under the existing disabled-multiplex policy.
% This is resource-plan evidence, NOT received HARQ or PUCCH transmission.
separateCfg=cfg; separateCfg.phy.pusch.uciMultiplexingMode='pucch_only';
state=localState(separateCfg,controlSlot,horizon,true);
state=localDeclarePUCCHReservation(state,separateCfg,dueSlot);
before=localSnapshot(state);
[canceled,g,info]=sixgr.truth.planFutureULGrants( ...
    state,separateCfg,{separateCfg},struct([]),1,horizon);
assert(isempty(g) && info.PUCCHDeferredCount==1 && info.PlannedGrantCount==0 && ...
    info.Status=="pucch_collision_deferred");
processes=[canceled.ULHarq.UEProcs{:}];
assert(~isempty(processes) && ~any([processes.Active]) && all([processes.TxCount]==0) && ...
    all([processes.NDIEpoch]==0) && all([processes.ScheduledAttemptCount]==0), ...
    'Unissued candidate cancellation must undo its tentative NDI allocation.');
assert(isequaln(localSnapshot(canceled),before));
rows=canceled.ControlTrials.ULControlResourceDecisions;
assert(height(rows)==1 && rows.ControlSlot==controlSlot && rows.DueSlot==dueSlot && ...
    rows.DecisionStage=="before_ul_dci_transmission" && ...
    rows.PUSCHStartTick<rows.PUCCHEndTickExclusive && rows.PUCCHStartTick<rows.PUSCHEndTickExclusive);
ok=true;
fprintf('FUTURE_UL_GRANT_PLANNER_PASS numerical_boundary=1 physical_qualification=0\n');
end

function [slot,decision]=localLegalTiming(cfg)
for slot=1:double(cfg.run.totalSlots)-1
    probe=struct('Direction','UL','ControlAbsoluteSlot',slot-1, ...
        'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
        'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
    decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
    [dl,~]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    if dl && decision.Valid && decision.DataAbsoluteSlot+1>slot && ...
            decision.DataAbsoluteSlot+1-slot<=cfg.run.controlGating.srsMaxAgeSlots
        return;
    end
end
error('test:NoULPlanningFixtureTiming','Installed configuration has no bounded fresh K2 occasion.');
end

function state=localState(cfg,slot,horizon,declaredAdmission)
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),horizon);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,slot,cfg.channel.snr_dB);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,slot,horizon,cfg.channel.snr_dB);
state.CurrentServingIdx(:)=1;
state.Traffic.FlowDirection="BIDIR";
state.ULQueueBits(:)=0;
if ~declaredAdmission, return; end
% Explicit numerical boundary, matching testSchedulerAdmissionEvidence.
% No declared flags enter a physical owner or primary exported measurement.
state.ControlGating.PBCHRequired=false;
state.ControlGating.PRACHRequired=false;
state.ControlGating.TRSRequired=false;
state.ControlGating.SRSRequired=false;
state.ULQueueBits(:)=8*1024;
[producer,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
strict=sixgr.phy.srs.buildSRSConfigFromScenario(producer);
rnti=sixgr.truth.CoupledRadioIdentity.resolve(state,1);
measurement=struct('MeasurementId',"declared_planner_srs",'SignalType',"SRS", ...
    'TargetType',"UE",'TargetId',1,'ServingCell',1,'ProducerSlot',slot, ...
    'AvailableSlot',slot,'Valid',true,'RI',1,'PMI',0,'CQI',10,'SINR_dB',20, ...
    'MeasurementSource',"declared_planner_component_fixture",'MeasurementClockDomain',"slot_only", ...
    'ResourceId',strict.ResourceId,'SRSConfigurationEpoch',cfg.rf.configurationEpoch, ...
    'SRSConfigurationContextID',sixgr.truth.srsConfigurationContextID(producer,cfg.rf.configurationEpoch,1,1), ...
    'SRSConfigurationContextVersion',"srs_configuration_context/v1", ...
    'SRSNumPorts',strict.NumSRSPorts,'SRSResourceID',strict.ResourceId, ...
    'SRSResourceIDsJSON',string(jsonencode(strict.ResourceIds)));
accepted=sixgr.truth.captureAcceptedSRSSpatialDecision(measurement,rnti,1,0);
state.ReferenceSignalMeasurementTable=struct2table(measurement,'AsArray',true);
state.SRSValidityState(1)="valid";
state.LastSuccessfulSRSSlotByUE(1)=slot; state.LastSRSObservedSlotByUE(1)=slot;
fb=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
fb.Valid=true; fb.Direction='UL'; fb.RI=1; fb.PMI=0; fb.ServingCell=1;
% Use the production feedback schema; the installed single-resource SRI
% is resolved by ULReferenceSignaling, not injected as an extra field here.
fb.CQI=10; fb.SINR_dB=20; fb.SourceSlot=slot; fb.DeliveredSlot=slot; fb.DueSlot=slot;
fb.SpatialDecisionSourceSlot=slot; fb.SpatialDecisionDeliveredSlot=slot;
fb.AcceptedSRSSpatialDecision=accepted; state.LatestULFeedback(1)=fb;
end

function state=localDeclarePUCCHReservation(state,cfg,dueSlot)
row=struct('Direction',"DL",'UEIndex',1,'RNTI',sixgr.truth.CoupledRadioIdentity.resolve(state,1), ...
    'HarqID',0,'SourceSlot',state.CurrentSlot,'DueSlot',dueSlot,'Ack',true, ...
    'ServingCell',1,'BaseStationID',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID,'UCIBitCount',1, ...
    'UCIType',"harq_ack",'Processed',false,'DeliveryMechanism',"pucch", ...
    'ControlResourceSource',"declared_planner_resource_fixture");
resource=sixgr.truth.CoupledTruthRuntime.resolvePUCCHResourceAssignmentRuntime(state,struct2table(row));
row.RequestedFormat=resource.RequestedFormat; row.ResolvedFormat=resource.ResolvedFormat;
row.PUCCHResourceId=string(resource.ResourceId);
row.PUCCHPRBStart=resource.PRBStart; row.PUCCHPRBCount=resource.PRBCount;
row.PUCCHSymbolStart=resource.SymbolStart; row.PUCCHNumSymbols=resource.NumSymbols;
row.ControlResourceValidity=resource.ControlResourceValidity;
state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,struct2table(row));
assert(height(state.PUCCHGrantTraceTable)==1 && ~state.PUCCHGrantTraceTable.GrantExecutedFlag);
end

function snapshot=localSnapshot(state)
snapshot=struct();
for name=["CurrentSlot","CurrentCanonicalSlot","CurrentFrame","CurrentDirection", ...
        "LastTrafficFrameApplied","ULQueueBits","DLQueueBits","Traffic", ...
        "LatestULFeedback","LatestDLFeedback","ReferenceSignalMeasurementTable", ...
        "PendingFeedbackTable","PendingCSITable","PUCCHGrantTraceTable", ...
        "ULGrantTraceTable","SlotTraceTable"]
    snapshot.(name)=state.(name);
end
end

function localThrows(fn,expected)
try, fn(); catch cause
    assert(string(cause.identifier)==expected,'Expected %s; got %s: %s', ...
        expected,cause.identifier,cause.message);
    return;
end
error('test:ExpectedULPlannerFailure','Expected %s.',expected);
end
