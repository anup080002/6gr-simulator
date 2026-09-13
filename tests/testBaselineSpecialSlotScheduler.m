function ok=testBaselineSpecialSlotScheduler(outputRoot)
% Main-created scheduler and budget, explicit UE-input component fixture.
% Actual generated grants/TBS/DCI, NOT acquired access or received feedback.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot);
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/baseline_special_slot_scheduler.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(v.scenario_path);
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
multi=struct('Enabled',true,'NumUsers',double(s.Data.users.n_users), ...
    'RNTIStart',double(s.Data.users.rnti_start),'ExecutionModel','slot_coupled_truth');
base=sixgr.truth.CoupledTruthRuntime.initialize(cfg,outputRoot,multi,struct(),1);
rows={}; captures={};
for slot0=0:base.SlotsPerFrame-1
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot0);
    if ~partition.IsSpecialSlot, continue; end
    % Fresh scheduler/HARQ per independent grant case; no prior ACK invented.
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,outputRoot,multi,struct(),1);
    region=double(partition.DLSymbolAllocation);
    state.CurrentSlot=slot0+1; state.CurrentDirection='DL';
    state.CurrentSlotDLSymbolStart=region(1); state.CurrentSlotDLNumSymbols=region(2);
    state.TimingControlAbsoluteSlot0Based=slot0;
    budget=sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
    ue=struct('RNTI',multi.RNTIStart,'DLBufferBytes',double(v.ue_fixture.buffer_bytes), ...
        'CQI',double(v.ue_fixture.cqi),'RI',double(v.ue_fixture.rank), ...
        'HeadOfLineDelay_ms',double(v.ue_fixture.head_of_line_delay_ms));
    probe=struct('Direction','DL','ControlAbsoluteSlot',budget.ControlAbsoluteSlot, ...
        'ControlSymbolAllocation',budget.ControlSymbolAllocation, ...
        'SymbolAllocation',budget.SymbolAllocation,'HARQProcess',0);
    grants=[]; info=struct(); timing=struct(); problem=""; detail=""; verified=false;
    try
        timing=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
        assert(timing.Valid,'sixgr:test:SpecialSlotTimingRejected','Main timing precheck rejected the special slot.');
        scheduler=state.DLSchedulers{1};
        [grants,info]=scheduler.schedule(slot0,ue,budget);
        for field=["CandidateTable","DecisionTable","ResourceExclusions","HARQDeferrals"]
            if isfield(info,field) && istable(info.(field)) && width(info.(field))>0
                writetable(info.(field),fullfile(outputRoot,"slot_"+slot0+"_"+field+".csv"));
            end
        end
        assert(~isempty(grants),'sixgr:test:SpecialSlotNoGrant','An eligible queued UE produced no grant.');
        for g=reshape(grants,1,[])
            assert(isequal(g.SymbolAllocation,budget.SymbolAllocation));
            assert(g.TBSBits>0 && g.ExactPHYFeasibilityChecked && g.ExactPHYFeasible);
            assert(g.DCI.TimeDomainAssignmentIndex==budget.TDRAIndex);
            assert(g.TimingDecision.Valid && g.TimingDecision.ControlAbsoluteSlot==slot0);
            sixgr.phy.grant.assertGrantTimingIdentity(g,'DL');
            parsed=sixgr.phy.pdcch.decodeDCIPayload(g.DCI.Bits,g.DCI.Format,g.DCI.ContextData);
            assert(parsed.Fields.time_resource_assignment==budget.TDRAIndex);
        end
        verified=true;
    catch cause
        problem=string(cause.identifier); detail=string(cause.message);
    end
    rows{end+1}=struct('AbsoluteSlot0',slot0,'BudgetPRBs',budget.NPRB, ...
        'SymbolStart',budget.SymbolAllocation(1),'NumSymbols',budget.SymbolAllocation(2), ...
        'TDRAIndex',budget.TDRAIndex,'GrantCount',numel(grants), ...
        'Verified',verified,'ErrorID',problem,'ErrorDetail',detail, ...
        'EvidenceScope',string(v.evidence_scope)); %#ok<AGROW>
    captures{end+1}=struct('Budget',budget,'UEFixture',ue,'Timing',timing,'Grants',grants,'Info',info); %#ok<AGROW>
end
results=struct2table(vertcat(rows{:})); resolvedScenario=s.Data;
writetable(results,fullfile(outputRoot,'special_slot_scheduler.csv'));
save(fullfile(outputRoot,'special_slot_scheduler.mat'),'cfg','resolvedScenario','v','results','captures');
disp(results);
assert(~isempty(results) && all(results.Verified), ...
    'sixgr:test:BaselineSpecialSlotSchedulerFailure','Special-slot scheduler/timing/DCI checks failed; inspect retained evidence.');
ok=true; disp('BASELINE_SPECIAL_SLOT_SCHEDULER_PASS');
end
