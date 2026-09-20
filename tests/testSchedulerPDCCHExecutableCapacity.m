function ok=testSchedulerPDCCHExecutableCapacity()
% Scheduler selection must use the same resolved candidate set as PHY TX.
% This exercises state construction, not a claimed decoded DCI experiment.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
assert(cfg.phy.pdcch.searchSpace.numCandidates(5)==0);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
for policy=["most_robust","configured_scheduler_level"]
    candidate=cfg;
    candidate.phy.pdcch.aggregationSelectionPolicy=policy;
    candidate.phy.pdcch.schedulerAggregationLevel=16;
    state=sixgr.truth.CoupledTruthRuntime.initialize(candidate,tempname,multi,struct(),10);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,candidate,'DL',1,1,1,10,12);
    budget=sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
    assert(budget.DefaultPDCCHAggregationLevel==8 && budget.PDCCHCCEBudget==8);
    for direction=["DL","UL"]
        [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,candidate,1,direction,1);
        assert(ue.PDCCHAggregationLevel==8, ...
            'Scheduler selected an aggregation level without a resolved candidate.');
    end
    invalid=state;
    invalid.CfgMobility.phy.pdcch.searchSpace.numCandidates=zeros(1,5);
    rejected=false;
    try
        sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(invalid,candidate,1,'DL',1);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:phy:pdcch:no_executable_aggregation_level'), ...
            'Expected no executable aggregation level; got %s: %s',cause.identifier,cause.message);
        rejected=true;
    end
    assert(rejected,'An empty receive search space must not be rescued by scheduler defaults.');
end
% A UL grant's DCI is downlink: changing only UL feedback must not change
% its control aggregation. These are declared scheduler fixture inputs.
cfg.phy.pdcch.aggregationSelectionPolicy="snr_threshold";
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,12);
state.LatestDLFeedback(1).Valid=true;
state.LatestDLFeedback(1).SINR_dB=6;
state.LatestULFeedback(1).Valid=true;
for ulSINR=[-20 30]
    state.LatestULFeedback(1).SINR_dB=ulSINR;
    for direction=["DL","UL"]
        [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,direction,1);
        assert(ue.PDCCHAggregationLevel==4,'UL data SINR changed downlink control aggregation.');
    end
end
ok=true;
fprintf('SCHEDULER_PDCCH_EXECUTABLE_CAPACITY_PASS TDD_DL_UL=1 empty_candidate_guard=1\n');
end
