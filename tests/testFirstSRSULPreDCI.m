function ok=testFirstSRSULPreDCI()
% Configured resource planning, not a new production air-interface run.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
% Explicit unit fixture exercises the alternate authored scheduler policy.
cfg.phy.srs.puschCollisionPolicy='prioritize_srs_until_first_valid_measurement';
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,1,12);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,12);
% This is only the boundary's known-access input, not an access measurement.
state.AccessState(:)="succeeded";
state.LastSuccessfulPRACHSlotByUE(:)=1;
plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,5);
srs=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
grant=struct('UEIndex',1,'RNTI',1,'Slot',5, ...
    'PRBSet',0:cfg.phy.carrier.NSizeGrid-1, ...
    'SymbolAllocation',[0 double(srs.ToolboxSRS.SymbolStart)+1], ...
    'Modulation','QPSK','NumLayers',1,'PDCCHGatingActive',true, ...
    'ControlDecodeOk',false,'PDCCHGrantBindingOk',false,'GrantContextId','tentative-unit-grant');
before=rng; harq=state.ULHarq.Stats;
[keep,T]=sixgr.truth.planFirstSRSULResources(plan,cfg,{cfg},grant);
assert(~keep && T.Collision && T.OverlapRECount>0 && T.PUSCHCandidateDeferred && ...
    ~T.PUSCHGrantCancelled && T.ControlSlot==1 && T.AbsoluteSlotOneBased==5 && ...
    T.DecisionStage=="before_ul_dci_transmission" && T.Exact && ~T.ApproximationUsed);
assert(isequaln(before,rng) && isequaln(harq,state.ULHarq.Stats));
assert(contains(T.SRSAllocationSource,'nrSRS') && contains(T.PUSCHAllocationSource,'nrPUSCH'));

% A real TDD timing decision must address the SAME resource-only fixture
% occasion. The scheduler's zero-based slot cannot be compared to plan.Slot.
canonical=grant; canonical.Direction='UL';
canonical.ControlAbsoluteSlot=3; canonical.ControlSymbolAllocation=[0 2];
canonical.TimingDecision=sixgr.phy.frame.TimingRelationEngine. ...
    resolveProductionGrant(cfg,canonical);
assert(canonical.TimingDecision.Valid && canonical.TimingDecision.DataAbsoluteSlot==4, ...
    'The TDD component must have a legal canonical PUSCH occasion.');
canonical.ScheduledAbsoluteSlot=double(canonical.TimingDecision.DataAbsoluteSlot);
sixgr.phy.grant.assertGrantTimingIdentity(canonical,'UL');
[canonicalKeep,canonicalT]=sixgr.truth.planFirstSRSULResources(plan,cfg,{cfg},canonical);
assert(isequal(canonicalKeep,keep) && isequaln(canonicalT,T), ...
    'Canonical scheduler timing must retain exact first-SRS resource arbitration.');

clearGrant=grant; clearGrant.SymbolAllocation=[0 double(srs.ToolboxSRS.SymbolStart)];
[keep,T]=sixgr.truth.planFirstSRSULResources(plan,cfg,{cfg},clearGrant);
assert(keep && ~T.Collision && ~T.PUSCHCandidateDeferred);
known=plan; known.LastSuccessfulSRSSlotByUE(:)=1;
[keep,T]=sixgr.truth.planFirstSRSULResources(known,cfg,{cfg},grant);
assert(keep && isempty(T),'Already-measured SRS must not suppress a data candidate.');
unknown=plan; unknown.AccessState(:)="not_attempted";
[keep,T]=sixgr.truth.planFirstSRSULResources(unknown,cfg,{cfg},grant);
assert(keep && isempty(T),'Unacquired access cannot claim a future SRS occasion.');
future=plan; future.LastSuccessfulPRACHSlotByUE(:)=4;
[keep,T]=sixgr.truth.planFirstSRSULResources(future,cfg,{cfg},grant);
assert(keep && isempty(T),'Future access success leaked into control-time SRS planning.');
future=plan; future.LastSuccessfulSRSSlotByUE(:)=4;
localReject(@()sixgr.truth.planFirstSRSULResources(future,cfg,{cfg},grant), ...
    'sixgr:truth:NoncausalSRSMeasurementHistory');
committed=grant; committed.ControlDecodeOk=true;
localReject(@()sixgr.truth.planFirstSRSULResources(plan,cfg,{cfg},committed), ...
    'sixgr:truth:SRSReservationAfterULCommit');
wrong=grant; wrong.Slot=10;
localReject(@()sixgr.truth.planFirstSRSULResources(plan,cfg,{cfg},wrong), ...
    'sixgr:truth:SRSPUSCHCollisionSlotMismatch');

% A known standalone HARQ PUCCH prevents first-SRS priority from claiming
% overlapping resources and indirectly dropping the feedback transmission.
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
withPUCCH=plan;
withPUCCH.PUCCHGrantTraceTable=table(5,false,1,1,string(pri.ResourceId), ...
    'VariableNames',{'ScheduledAbsoluteSlot','GrantExecutedFlag','UEIndex','RNTI','PUCCHResourceId'});
check=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,withPUCCH.PUCCHGrantTraceTable,5,1);
assert(check.Collision,'Fixture must exercise the configured overlapping HARQ PUCCH.');
[keep,T]=sixgr.truth.planFirstSRSULResources(withPUCCH,cfg,{cfg},grant);
assert(keep && T.SRSPUCCHConflictKnownAtDecision && ~T.PUSCHCandidateDeferred);

% Explicit multi-UE capacity fixture: UE 1 already has SRS, but its next
% SRS overlaps data and will be deferred. It cannot consume the only SRS
% opportunity and starve UE 2's first measurement at planning time.
two=plan; two.NumUsers=2;
two.LastSuccessfulSRSSlotByUE=[1;NaN]; two.LastSRSSlotByUE=[0;0];
two.AccessState=["succeeded";"succeeded"];
two.LastSuccessfulPRACHSlotByUE=[1;1];
cfgTwo=cfg; cfgTwo.phy.srs.slotWithinPeriod1Based=[];
cfgTwo.phy.srs.slotNumbers=4; cfgTwo.phy.srs.maxUEsPerSlot=1;
[keep,T]=sixgr.truth.planFirstSRSULResources(two,cfgTwo,{cfgTwo,cfgTwo},grant);
assert(~keep && height(T)==1 && T.SRSUEIndex==2 && T.PUSCHCandidateDeferred);

% Current-slot execution and the earlier resource planner use one common
% eligibility function; no configured occasion is replaced by a new phase.
assert(sixgr.truth.coupledSRSAttemptDue(plan,cfg,5,1));
futureAttempt=plan; futureAttempt.LastSRSSlotByUE(:)=4;
localReject(@()sixgr.truth.coupledSRSAttemptDue(futureAttempt,cfg,5,1), ...
    'sixgr:truth:NoncausalSRSAttemptHistory');

code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
first=strfind(code,'function [state, pendingULGrants] = localScheduleCoupledFutureULGrantsFromDLControl');
last=strfind(code,'function decision = localResolveCoupledULTimingDecision');
body=code(first(1):last(1)-1);
reservation=strfind(body,'sixgr.truth.planFirstSRSULResources');
dci=strfind(body,'[state, qualifiedGrants] = localQualifyCoupledGrantsWithPDCCH');
assert(numel(reservation)==1 && numel(dci)==1 && reservation<dci);
ok=true;
fprintf('FIRST_SRS_UL_PRE_DCI_PASS\n');
end

function localReject(fn,id)
try, fn(); catch ME
    assert(string(ME.identifier)==id,'Expected %s; got %s: %s',id,ME.identifier,ME.message);
    return;
end
error('testFirstSRSULPreDCI:MissingError','Expected %s.',id);
end
