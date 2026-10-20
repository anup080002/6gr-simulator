function ok=testH4100ULPlanningTimingEvidence()
% Actual installed 100 MHz timing engine; no RF execution or fake grants.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.carrier.NSizeGrid==273);
% Source10 becomes available at the start of11. The continuity harness
% must hand off before executing11: configured K2four then reaches15 at
% exactly the installed five-slot SRS limit. Returning after11 misses it.
assert(cfg.run.controlGating.srsMaxAgeSlots==5);
legalControl=[]; legalData=[];
for handoffSlot=11:31
    handoff=struct('Direction','UL','ControlAbsoluteSlot',handoffSlot-1, ...
        'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
        'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
    option=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,handoff);
    if option.Valid && option.DataAbsoluteSlot+1-10<=cfg.run.controlGating.srsMaxAgeSlots
        legalControl(end+1)=handoffSlot; %#ok<AGROW>
        legalData(end+1)=option.DataAbsoluteSlot+1; %#ok<AGROW>
    end
end
assert(isequal(legalControl,11) && isequal(legalData,15), ...
    'test:H4SRSControlHandoffTiming','Only the unconsumed slot11 opportunity meets this actual SRS age policy.');
% Allocation-only preflight at that exact H4 control occasion. Explicit
% diagnostic bits do not claim a decoded semantic DCI or a channel trial.
% Omitting configured common reservations reproduced the failed continuity
% harness; the normal allocator must choose another configured candidate.
control=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,11);
carrier=sixgr.phy.grid.makeCarrier(control);
reserved=sixgr.truth.commonPDCCHReservations(struct(),control,10,1,carrier);
installed=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(control,'0_1');
rnti=installed.Data.RNTIValue;
bits=int8(mod((0:63).',2));
[defaultTX,defaultInfo]=sixgr.phy.dl.PDCCH_Tx(control,'DCIBits',bits,'RNTI',rnti,'OFDMModulate',false);
[allocatedTX,allocatedInfo]=sixgr.phy.dl.PDCCH_Tx(control,'DCIBits',bits, ...
    'RNTI',rnti,'ReservedRECoordinates',reserved,'OFDMModulate',false);
assert(~isempty(intersect(reserved,defaultInfo.AllocatedRECoordinates,'rows')) && ...
    isempty(intersect(reserved,allocatedInfo.AllocatedRECoordinates,'rows')) && ...
    defaultTX.PDCCH.AggregationLevel==allocatedTX.PDCCH.AggregationLevel && ...
    defaultTX.PDCCH.AllocatedCandidate~=allocatedTX.PDCCH.AllocatedCandidate);
state=struct('CurrentSlot',41,'CurrentSNR_dB',40,'ULQueueBits',800, ...
    'PendingCSITable',table(),'ULHarq',sixgr.l2.mac.HARQEntityUL(cfg));
probe=struct('Direction','UL','ControlAbsoluteSlot',40, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
    'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
d=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
assert(d.Valid && d.K2==4 && d.DataAbsoluteSlot==44);
rngBefore=rng; stats=state.ULHarq.Stats; procs=state.ULHarq.UEProcs;
[actual,row]=sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct([]),1,100);
assert(row.EligibleForUEScheduling && row.ControlSlot==41 && ...
    row.ControlAbsoluteSlot0Based==40 && row.TimingSelectedDataSlot==45 && ...
    row.TimingSelectedK2==4 && row.TargetSlotHasUL==1 && row.ExistingQueuedGrantForTarget==0);
assert(row.DecisionSequence==1 && row.SweepStartSlot==1 && row.SweepEndSlot==100);
assert(height(actual.ULPlanningTimingCandidateTable)==numel(d.DataAttempts));
assert(isequaln(rngBefore,rng) && isequaln(state.ULHarq.Stats,stats) && ...
    isequaln(state.ULHarq.UEProcs,procs));
assert(actual.CurrentSlot==41 && isequaln(actual.ULQueueBits,state.ULQueueBits) && ...
    isequaln(actual.PendingCSITable,state.PendingCSITable));

% Slot42 cannot use fixed K2=4 to schedule a DL-only target. Retain the
% actual rejected candidate, but do not advertise it as a legal data slot.
actual.CurrentSlot=42; probe.ControlAbsoluteSlot=41;
rejected=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
assert(~rejected.Valid && sixgr.truth.isDeferrableCoupledULTimingDecision(rejected));
[actual,row]=sixgr.truth.evaluateULPlanningOpportunity(actual,cfg,rejected,struct([]),1,100);
assert(~row.EligibleForUEScheduling && isnan(row.TimingSelectedDataSlot) && ...
    contains(row.BlockReason,'target_hits_fixed_opposite_direction'));
last=actual.ULPlanningTimingCandidateTable(end,:);
assert(~last.TimingValid && ~last.SelectedByTimingEngine && ...
    last.ReasonCode==string(rejected.DataAttempts(end).ReasonCode));
assert(row.DecisionSequence==2 && last.DecisionSequence==2);

% A legal timing result can still be outside the chosen run horizon.
[~,row]=sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct([]),1,44);
assert(row.TimingEngineValid && ~row.EligibleForUEScheduling && ...
    row.BlockReason=="target_outside_current_sweep_horizon" && isnan(row.TargetSlotHasUL));
% Existing queued grants are not silently lost or treated as new failures.
[~,row]=sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct('Slot',45),1,100);
assert(row.TimingEngineValid && ~row.EligibleForUEScheduling && ...
    row.ExistingQueuedGrantForTarget==1 && row.BlockReason=="target_already_has_queued_UL_grant");
[~,row]=sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct('Slot',50),1,100);
assert(row.EligibleForUEScheduling);

% A separately labelled configured-list fixture exercises all evaluated
% alternatives. The fifth candidate is NOT evaluated after K2=4 succeeds.
listed=cfg;
policy=listed.phy.frameStructure.TimingContext.Policy;
policy=rmfield(policy,'SelectedK2');
policy.AllowedK2=1:5;
policy.K2Rows=sixgr.phy.frame.TimingPolicyCatalog.configuredRows( ...
    'K2',1:5,'testH4100ULPlanningTimingEvidence_explicit_list_fixture');
listed.phy.frameStructure.TimingContext.Policy=policy;
probe.ControlAbsoluteSlot=40;
choice=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(listed,probe);
assert(choice.Valid && choice.K2==4 && numel(choice.DataAttempts)==4);
[listedState,row]=sixgr.truth.evaluateULPlanningOpportunity(state,listed,choice,struct([]),1,100);
T=listedState.ULPlanningTimingCandidateTable;
assert(row.EvaluatedCandidateCount==4 && isequal(T.K2,(1:4)') && ...
    nnz(T.SelectedByTimingEngine)==1 && T.SelectedByTimingEngine(4));
for k=1:4
    assert(T.SourceTick(k)==choice.DataAttempts(k).SourceTick && ...
        T.TargetTick(k)==choice.DataAttempts(k).TargetTick && ...
        T.MinimumProcessingTicks(k)==choice.DataAttempts(k).MinimumProcessingTicks && ...
        T.TargetStartSymbol0Based(k)==choice.DataAttempts(k).TargetStartSymbol);
end
assert(~any(T.K2==5),'Never label an untested configured option as an evaluated candidate.');
% Directional policy errors still cannot be turned into a passed grant.
bad=state; bad.CurrentSlot=42;
localReject(@()sixgr.truth.evaluateULPlanningOpportunity(bad,cfg,d,struct([]),1,100), ...
    'sixgr:truth:ULTimingDecisionClockMismatch');
localReject(@()sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct([]),0,100), ...
    'sixgr:truth:InvalidULPlanningHorizon');
assert(isequaln(rngBefore,rng) && isequaln(state.ULHarq.Stats,stats) && ...
    isequaln(state.ULHarq.UEProcs,procs));

% Production must commit this preflight before constructing the future view
% or filtering inactive UEs, including all its early no-grant branches.
code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
first=regexp(code,'(?m)^function[^\r\n]*= localScheduleCoupledFutureULGrantsFromDLControl\(','start');
last=strfind(code,'function decision = localResolveCoupledULTimingDecision');
body=code(first:last-1);
record=strfind(body,'sixgr.truth.evaluateULPlanningOpportunity(');
future=strfind(body,'CoupledTruthRuntime.futureULPlanningView(');
assert(isscalar(record)&&isscalar(future)&&record<future);
assert(contains(body,'if ~opportunity.EligibleForUEScheduling') && ...
    ~contains(body,'localHasPendingCoupledULGrantForSlot'));
ok=true;
fprintf('H4_100_UL_PLANNING_TIMING_EVIDENCE_PASS\n');
end

function localReject(fn,id)
try, fn(); catch ME
    assert(string(ME.identifier)==id,'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return;
end
error('testH4100ULPlanningTimingEvidence:MissingError','Expected %s.',id);
end
