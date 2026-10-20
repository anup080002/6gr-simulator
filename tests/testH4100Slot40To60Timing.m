function ok=testH4100Slot40To60Timing()
% Production config/timing preflight. NOT a physical slot-40--60 execution.
% No UE is attached, no SRS/CSI state inserted and no clock is rewound here.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
plan=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_slot40_60.yaml');
assert(string(plan.schema)=="SixGRSlotWindow/v1" && ...
    string(plan.slot_numbering)=="one_based_absolute_carrier_slot");
scenario=sixgr.lls6g.config.loadScenarioConfig(plan.scenario_config);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(scenario.ScenarioID==string(plan.scenario_id));
assert(cfg.run.totalSlots==plan.expected_horizon && plan.last_slot<cfg.run.totalSlots, ...
    'test:H4WindowHorizon','Do not truncate the production scheduling horizon to the audit window.');
assert(cfg.phy.carrier.NSizeGrid==plan.n_prb && cfg.phy.nTxAnt==64 && ...
    cfg.phy.nRxAnt==4 && cfg.phy.pdsch.maxRankDefault==plan.max_layers && ...
    cfg.phy.pusch.maxRankDefault==plan.max_layers && ...
    sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD");
assert(scenario.get('run_control.runtime_checkpoint_enable') && ...
    scenario.get('run_control.checkpoint_every_slots')==1 && ...
    cfg.run.runtimeCheckpointEnabled && cfg.run.checkpointEverySlots==1);
before=rng;
controls=[]; targets=[]; rejects=0; partitions=strings(0,1);
for slot=plan.first_slot:plan.last_slot
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot-1);
    partitions(end+1)=string(partition.SlotLabel); %#ok<AGROW>
    if ~partition.AllowDL, continue; end
    probe=struct('Direction','UL','ControlAbsoluteSlot',slot-1, ...
        'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
        'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
    decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
    if decision.Valid
        target=decision.DataAbsoluteSlot+1;
        targetPartition=sixgr.util.resolveTDDSlotPartition(cfg,target-1);
        assert(targetPartition.AllowUL && target-slot==decision.K2);
        if target<=plan.last_slot
            controls(end+1)=slot; targets(end+1)=target; %#ok<AGROW>
        end
    else
        assert(sixgr.truth.isDeferrableCoupledULTimingDecision(decision), ...
            'test:H4WindowUnexpectedTimingFailure','Unexpected timing rejection: %s',decision.ReasonCode);
        rejects=rejects+1;
    end
end
assert(~isempty(controls) && rejects>0 && numel(unique(partitions))>1);
assert(any(controls==41 & targets==45) && any(controls==46 & targets==50), ...
    'test:H4WindowKnownTransition','The original failing handoff opportunities must remain exercised.');
period=cfg.phy.csi.reportPeriodicitySlots; offset=cfg.phy.csi.reportOffsetSlots;
reports=(offset:period:cfg.run.totalSlots-1)+1;
reports=reports(reports>=plan.first_slot & reports<=plan.last_slot);
assert(~isempty(reports),'test:H4WindowNoCSI','Window must contain an installed CSI reporting occasion.');
trs=[];
for slot=plan.first_slot:plan.last_slot
    observation=sixgr.truth.resolveTRSObservationWindow(cfg,slot);
    if observation.ObservationStarts, trs(end+1)=slot; end %#ok<AGROW>
end
assert(~isempty(trs) && isequaln(before,rng),'Preflight must not evolve random channel/noise state.');
fprintf('H4_WINDOW_TIMING_PREFLIGHT_PASS controls=%s targets=%s CSI_report_calendar=%s TRS_starts=%s physical_window_executed=0\n', ...
    mat2str(controls),mat2str(targets),mat2str(reports),mat2str(trs));
ok=true;
end
