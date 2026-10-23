function [state,grants,info]=planFutureULGrants(state,cfg,userCfg,pendingULGrants,sweepIndex,slotsPerPoint)
% Plan tentative UL grants at the current DL control decision, without TX.
% Extracted from runWaveformLinkBundle's pretransmission K2 coordinator.
% The future view supplies resources, never future traffic or feedback.
% Scheduler/HARQ instances are shared handles: schedule exactly once, and
% never replace live state with the planning view or merge its grant traces.
% Returned grants still require joint control admission and actual DCI RX.
grants=repmat(struct(),0,1);
info=struct('Source',"control_time_future_UL_resource_planner", ...
    'EvidenceRole',"tentative_scheduling_not_DCI_reception_or_data_execution", ...
    'Status',"no_dl_control_symbols",'ControlSlot',NaN,'DataSlot',NaN,'K2',NaN, ...
    'TimingDecision',struct(),'Opportunity',struct(),'SchedulingInfo',struct(), ...
    'ScheduleAttempted',false,'SRSDeferredCount',0,'PUCCHDeferredCount',0, ...
    'SchedulerGrantCount',0,'PlannedGrantCount',0);
if ~isstruct(pendingULGrants)
    pendingULGrants=repmat(struct(),0,1);
end
slotDLControlAllowed=logical(sixgr.util.structGet(state,"CurrentSlotDLAllowed",true)) && ...
    double(sixgr.util.structGet(state,"CurrentSlotDLNumSymbols",0))>0;
if ~slotDLControlAllowed, return; end
controlSlot=double(state.CurrentSlot);
info.ControlSlot=controlSlot;
timingDecision=localResolveULTimingDecision(state,cfg,controlSlot);
info.TimingDecision=timingDecision;
[state,opportunity]=sixgr.truth.evaluateULPlanningOpportunity( ...
    state,cfg,timingDecision,pendingULGrants,sweepIndex,slotsPerPoint);
info.Opportunity=opportunity;
if ~opportunity.EligibleForUEScheduling
    info.Status="timing_opportunity_deferred";
    return;
end
k2Slots=double(timingDecision.K2);
dueSlot=double(timingDecision.DataAbsoluteSlot)+1;
info.K2=k2Slots; info.DataSlot=dueSlot;

planState=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,dueSlot);
decisionRowsBefore=height(sixgr.util.structGet(planState,"SchedulerDecisionTable",table()));
planState.TimingControlAbsoluteSlot0Based=controlSlot-1;
planState.TimingControlSymbolAllocation=localControlSymbolAllocation(state,cfg);
uciOnPUSCHAvailable=sixgr.truth.isPUSCHUCIAvailable(cfg);
% Real queue demand is not suppressed merely because UCI is also due.
[planState,grants,scheduleInfo]=sixgr.truth.CoupledTruthRuntime.scheduleDirection(planState,cfg,"UL");
info.ScheduleAttempted=true; info.SchedulingInfo=scheduleInfo;
info.SchedulerGrantCount=numel(grants);
state.SchedulerAdmissionTable=localAppendCompatTable( ...
    sixgr.util.structGet(state,"SchedulerAdmissionTable",table()),scheduleInfo.AdmissionTable);
state=localCommitPlannedDecisions(state,planState,decisionRowsBefore,controlSlot,dueSlot,k2Slots);
if isempty(grants)
    info.Status="no_scheduler_grants";
    return;
end
for gi=1:numel(grants)
    queuedGrant=sixgr.truth.bindQueuedULGrantOccasion(grants(gi), ...
        controlSlot,dueSlot,state.CurrentFrame,planState.CurrentFrame,k2Slots);
    for field=string(fieldnames(queuedGrant)).'
        grants(gi).(field)=queuedGrant.(field);
    end
end

% Resolve first-measurement priority while grants are still tentative.
% A later sounding opportunity cannot retract an already decoded command.
[srsKeep,srsPlanT]=sixgr.truth.planFirstSRSULResources(planState,cfg,userCfg,grants);
if ~isempty(srsPlanT)
    state.ControlTrials.SRSResourceDecisions=localAppendCompatTable( ...
        sixgr.util.structGet(state.ControlTrials,"SRSResourceDecisions",table()),srsPlanT);
end
for gi=reshape(find(~srsKeep),1,[])
    state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
        state,grants(gi),"UL",'DCINotIssued',true);
end
info.SRSDeferredCount=nnz(~srsKeep);
grants=grants(srsKeep);
if isempty(grants)
    info.Status="first_srs_priority_deferred";
    return;
end

if ~uciOnPUSCHAvailable
    candidates=grants;
    [grants,controlDecisions,controlKeep]=sixgr.truth.CoupledTruthRuntime. ...
        excludeULGrantsCollidingWithPUCCHRuntime(planState,candidates,dueSlot);
    for gi=reshape(find(~controlKeep),1,[])
        state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
            state,candidates(gi),"UL",'DCINotIssued',true);
    end
    info.PUCCHDeferredCount=nnz(~controlKeep);
    if ~isempty(controlDecisions)
        controlDecisions.ControlSlot=repmat(controlSlot,height(controlDecisions),1);
        controlDecisions.DecisionStage=repmat("before_ul_dci_transmission",height(controlDecisions),1);
        controlDecisions.ValueSource=repmat("scheduled_pusch_and_typed_pucch_resource_plans",height(controlDecisions),1);
        state.ControlTrials.ULControlResourceDecisions=localAppendCompatTable( ...
            state.ControlTrials.ULControlResourceDecisions,controlDecisions);
    end
    if isempty(grants)
        info.Status="pucch_collision_deferred";
        return;
    end
end
info.Status="tentative_grants_planned";
info.PlannedGrantCount=numel(grants);
end

function decision=localResolveULTimingDecision(state,cfg,controlSlot)
symbolAllocation=sixgr.util.structGet(cfg,"phy.pusch.symbolAllocation",[]);
if isempty(symbolAllocation)
    symbolAllocation=sixgr.util.structGet(cfg,"phy.pusch.SymbolAllocation",[]);
end
if ~(isnumeric(symbolAllocation) && numel(symbolAllocation)==2 && ...
        all(isfinite(double(symbolAllocation(:)))))
    error("sixgr:truth:MissingPUSCHTimingAllocation", ...
        "Coupled UL K2 scheduling requires an explicit PUSCH SymbolAllocation.");
end
probe=struct("Direction","UL","ControlAbsoluteSlot",double(controlSlot)-1, ...
    "ControlSymbolAllocation",localControlSymbolAllocation(state,cfg), ...
    "SymbolAllocation",reshape(double(symbolAllocation),1,2),"HARQProcess",0);
decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
if ~decision.Valid
    if sixgr.truth.isDeferrableCoupledULTimingDecision(decision), return; end
    error("sixgr:truth:CoupledULTimingRejected", ...
        "Canonical coupled UL K2 timing rejected control slot %d: %s", ...
        round(double(controlSlot)),char(string(decision.ReasonCode)));
end
end

function allocation=localControlSymbolAllocation(state,cfg)
allocation=sixgr.util.structGet(cfg,"phy.pdcch.symbolAllocation",[]);
if isempty(allocation)
    allocation=sixgr.util.structGet(cfg,"phy.pdcch.SymbolAllocation",[]);
end
if ~(isnumeric(allocation) && isreal(allocation) && numel(allocation)==2 && ...
        all(isfinite(double(allocation(:)))) && ...
        all(double(allocation(:))==fix(double(allocation(:)))) && ...
        double(allocation(1))>=0 && double(allocation(2))>=1)
    error("sixgr:truth:MissingPDCCHTimingAllocation", ...
        "Coupled timing requires the explicit configured PDCCH SymbolAllocation.");
end
allocation=reshape(double(allocation),1,2);
dlPartition=[double(sixgr.util.structGet(state,"CurrentSlotDLSymbolStart",NaN)), ...
    double(sixgr.util.structGet(state,"CurrentSlotDLNumSymbols",NaN))];
if numel(dlPartition)~=2 || any(~isfinite(dlPartition)) || dlPartition(2)<1 || ...
        allocation(1)<dlPartition(1) || allocation(1)+allocation(2)>sum(dlPartition)
    error("sixgr:truth:PDCCHTimingOutsideDLPartition", ...
        "Configured PDCCH SymbolAllocation=%s is outside the current DL partition=%s.", ...
        mat2str(allocation),mat2str(dlPartition));
end
end

function state=localCommitPlannedDecisions(state,planState,rowsBefore,controlSlot,dueSlot,k2Slots)
planned=sixgr.util.structGet(planState,"SchedulerDecisionTable",table());
if ~(istable(planned) && height(planned)>rowsBefore), return; end
rowsBefore=max(0,min(height(planned),round(double(rowsBefore))));
newRows=planned((rowsBefore+1):height(planned),:); n=height(newRows);
newRows.Direction=repmat("UL",n,1);
newRows.ControlSlot=repmat(double(controlSlot),n,1);
newRows.ScheduledDataSlot=repmat(double(dueSlot),n,1);
newRows.K2Slots=repmat(double(k2Slots),n,1);
newRows.SchedulingKnowledgeSlot=repmat(double(planState.PlanningDecisionSlot),n,1);
newRows.TrafficKnowledgeThroughSlot=repmat(double(planState.PlanningTrafficThroughSlot),n,1);
newRows.SchedulingTimingMode=repmat("dci_k2_future_ul",n,1);
newRows.ValueSource=string(newRows.ValueSource)+":k2_future_slot_plan";
newRows.ValueDefinition=repmat( ...
    "UL scheduler candidate/rejection decision evaluated at the DL control slot for the explicit K2 data slot.",n,1);
state.SchedulerDecisionTable=localAppendCompatTable( ...
    sixgr.util.structGet(state,"SchedulerDecisionTable",table()),newRows);
end

function out=localAppendCompatTable(a,b)
% Preserve the coordinator's compatibility semantics for diagnostics only.
if ~(istable(a) && ~isempty(a))
    if istable(b), out=b; else, out=table(); end
    return;
end
if ~(istable(b) && ~isempty(b)), out=a; return; end
vars=union(string(a.Properties.VariableNames),string(b.Properties.VariableNames),"stable");
a=localEnsureVars(a,vars,b); b=localEnsureVars(b,vars,a);
out=[a(:,cellstr(vars));b(:,cellstr(vars))];
end

function t=localEnsureVars(t,vars,reference)
for k=1:numel(vars)
    name=char(vars(k));
    if ismember(name,t.Properties.VariableNames), continue; end
    value=reference.(name); n=height(t);
    if isstring(value), t.(name)=strings(n,1);
    elseif islogical(value), t.(name)=false(n,1);
    elseif isnumeric(value), t.(name)=NaN(n,1);
    else, t.(name)=strings(n,1);
    end
end
end
