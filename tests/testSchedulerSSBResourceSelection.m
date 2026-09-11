function ok=testSchedulerSSBResourceSelection()
% Authored TDD resources; no data, reference waveform or MCS is synthesized.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile('simulator','configs','scenarios','lls_causal_access_to_data_wiring_tdd.yaml')),tempname);
[chunk,i]=sixgr.l2.mac.contiguousPRBChunk([0 1 8:14],1,5,4);
assert(isequal(chunk,8:12) && i==3);
assert(isempty(sixgr.l2.mac.contiguousPRBChunk([0 1 23 24],1,4,4)));
assert(isequal(sixgr.l2.mac.contiguousPRBChunk([0 1 23 24],3,2,2),[23 24]));
ue=struct('RNTI',1,'UEIndex',1,'ServingCell',1,'DLBufferBytes',20000, ...
    'CQI',8,'RI',1,'HeadOfLineDelay_ms',1);
budget=struct('PRBSet',0:24,'SymbolAllocation',[2 12], ...
    'ControlAbsoluteSlot',40,'ControlSymbolAllocation',[0 2]);
for kind=["RR","PF"]
    for minimum=[4 2]
        testCfg=cfg; testCfg.mac.scheduler.minPRBPerUE=minimum;
        if kind=="RR"
            scheduler=sixgr.l2.mac.SchedulerRR(testCfg,'Direction','DL');
        else
            scheduler=sixgr.l2.mac.SchedulerPF(testCfg,'Direction','DL');
        end
        [grants,info]=scheduler.schedule(40,ue,budget);
        assert(height(info.ResourceExclusions)==1);
        assert(info.ResourceExclusions.DataAbsoluteSlot0==40);
        safe=jsondecode(info.ResourceExclusions.AvailablePRBSetJSON);
        assert(isequal(double(safe(:).'),[0 1 23 24]));
        if minimum==4
            assert(isempty(grants),'Do not bridge SSB to satisfy a four-PRB minimum.');
        else
            assert(~isempty(grants),'A configured two-PRB grant must use an available island.');
            for grant=grants(:).'
                assert(all(ismember(grant.PRBSet,safe)) && all(diff(grant.PRBSet)==1));
                assert(grant.ExactPHYFeasible && grant.ExactAllocationAbsoluteSlot0==40);
            end
        end
        runtime=struct('CurrentSlot',41,'CurrentFrame',5);
        runtime=sixgr.truth.CoupledTruthRuntime.recordSchedulerDecisionRuntime(runtime,info,'DL',1);
        assert(height(runtime.SchedulerResourceExclusionTable)==1 && ...
            runtime.SchedulerResourceExclusionTable.Slot==41 && ...
            runtime.SchedulerResourceExclusionTable.SchedulerAbsoluteSlot0==40);
        quiet=budget; quiet.ControlAbsoluteSlot=30;
        [next,nextInfo]=scheduler.schedule(30,ue,quiet);
        assert(~isempty(next) && isempty(nextInfo.ResourceExclusions));
        assert(all([next.ExactAllocationAbsoluteSlot0]==30));

        % The periodic Type-0/SIB1 common PDSCH occupies PRBs 0..23 over
        % the connected-data symbol allocation. A separately coded UE
        % PDSCH must be deferred instead of being silently superposed.
        commonPlan=sixgr.phy.frame.CommonDLResourcePlan(testCfg);
        sibBudget=budget;
        sibBudget.ControlAbsoluteSlot=commonPlan.SIB1Slot0;
        [sibGrant,sibInfo]=scheduler.schedule(commonPlan.SIB1Slot0,ue,sibBudget);
        assert(isempty(sibGrant));
        assert(height(sibInfo.ResourceExclusions)==1);
        sibSafe=jsondecode(sibInfo.ResourceExclusions.AvailablePRBSetJSON);
        assert(isempty(intersect(double(sibSafe(:).'),double(commonPlan.SIB1PDSCH.PRBSet(:).'))));
        assert(contains(sibInfo.ResourceExclusions.Reason,"SIB1_PDSCH_and_Type0_PDCCH"));
    end
end
ok=true;
end
