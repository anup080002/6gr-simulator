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
localAssertTDDTimingDeferral(cfg,ue,budget);
ok=true;
end

function localAssertTDDTimingDeferral(cfg,ue,budget)
% Select an actual configured DL-control/UL-data boundary with K0=1.
% The candidate is rejected, not shifted or silently issued in the UL slot.
fixture=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs', ...
    'fixtures','scheduler_feedback_timing.yaml'));
k0=double(fixture.tdd.resource_deferral_k0);
cfg.phy.schedulingTiming.allowedK0=k0;
cfg.phy.schedulingTiming.pdcchToPDSCHK0=k0;
cfg.phy.frameStructure=rmfield(cfg.phy.frameStructure,'TimingContext');
cfg=sixgr.phy.frame.FrameRuntimeStateBuilder.attachTimingContext(cfg);
assert(cfg.phy.frameStructure.TimingContext.Policy.SelectedK0==k0);
boundary=NaN;
for slot0=20:39
    source=sixgr.util.resolveTDDSlotPartition(cfg,slot0);
    target=sixgr.util.resolveTDDSlotPartition(cfg,slot0+k0);
    if source.DLSymbolAllocation(2)>=2 && target.ULSymbolAllocation(2)==14
        boundary=slot0; break;
    end
end
assert(isfinite(boundary),'The TDD fixture must contain the intended DL-to-UL boundary.');
budget.ControlAbsoluteSlot=boundary;
for kind=["RR","PF"]
    harq=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
    if kind=="RR"
        scheduler=sixgr.l2.mac.SchedulerRR(cfg,'Direction','DL','HARQ',harq);
    else
        scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL','HARQ',harq);
    end
    before=harq.Stats;
    [grants,info]=scheduler.schedule(boundary,ue,budget);
    assert(isempty(grants),'No PDSCH/DCI may be issued in the rejected TDD data occasion.');
    assert(isequaln(harq.Stats,before) && isempty(harq.getDeliveryLedger()), ...
        'A rejected candidate must not allocate a TB, synthesize feedback or consume HARQ state.');
    assert(height(info.ResourceExclusions)==1 && ...
        info.ResourceExclusions.ControlAbsoluteSlot0==boundary && ...
        info.ResourceExclusions.DataAbsoluteSlot0==boundary+k0 && ...
        info.ResourceExclusions.Reason== ...
        "common_dl_resource_timing_deferral:data_timing_rejected:target_hits_fixed_opposite_direction" && ...
        isempty(jsondecode(info.ResourceExclusions.AvailablePRBSetJSON)), ...
        'Retain the exact rejected candidate and reason; do not hide it as successful scheduling.');
    % Corrupt the already-installed context, not the configured TDD pattern.
    % The new physical-deferral branch must not rescue missing authority.
    scheduler.Cfg.phy.frameStructure=rmfield(scheduler.Cfg.phy.frameStructure,'TimingContext');
    rejected=false;
    try
        scheduler.schedule(boundary,ue,budget);
    catch cause
        rejected=strcmp(cause.identifier,'sixgr:SchedulerBase:TimingDecisionRejected') && ...
            contains(cause.message,'frame_timing_context_not_attached');
    end
    assert(rejected,'Missing timing context must still raise a diagnostic execution error.');
end
end
