function ok=testLiveCSVPlotCadence()
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.outputs.liveCSVPNGIntervalSlots==5 && cfg.outputs.executionStageProfileEnabled);
assert(cfg.run.checkpointFirstSlot==49 && cfg.run.checkpointEverySlots==3);
assert(isequal(find(arrayfun(@(s)sixgr.runtime.CheckpointSchedule.due(s, ...
    cfg.run.checkpointEverySlots,cfg.run.checkpointFirstSlot),1:60)),[49 52 55 58]));
due=arrayfun(@(slot)sixgr.artifact.liveCSVPlotDue(cfg,slot,103),1:103);
assert(isequal(find(due),[1 5:5:100 103]));
assert(sixgr.artifact.liveCSVPlotDue(cfg,49,100,true),'Explicit finalization must bypass display cadence.');
cfg.outputs.liveCSVPNGIntervalSlots=0;
try
    sixgr.artifact.liveCSVPlotDue(cfg,49,100);
    error('test:InvalidCadenceAccepted','Zero interval must fail validation.');
catch failure
    assert(~strcmp(failure.identifier,'test:InvalidCadenceAccepted'));
end
% Checkpoint identity ignores exactly the two new operational switches.
original=struct('run_control',struct(),'output',struct('save_csv',true),'seed',19);
changed=original; changed.output.execution_stage_profile_enabled=true;
changed.output.live_csv_png_interval_slots=5;
assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(original), ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(changed)));
changed.output.save_csv=false;
assert(~isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(original), ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(changed)));
% The actual restart binding preserves the original hash/physical config
% while applying requested display/recovery settings, not merely comparing
% them as operational and then discarding them.
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
requested=scenario.toStruct();
requested.output.live_csv_png_interval_slots=7;
requested.output.execution_stage_profile_enabled=false;
requested.run_control.checkpoint_every_slots=2;
requested.run_control.checkpoint_first_slot=49;
requested.run_control.runtime_checkpoint_keep=4;
settings=sixgr.runtime.SlotCheckpoint.operationalSettings(requested);
bound=sixgr.runtime.SlotCheckpoint.applyOperationalSettings(cfg,settings);
assert(bound.outputs.liveCSVPNGIntervalSlots==7 && ~bound.outputs.executionStageProfileEnabled);
assert(bound.run.checkpointEverySlots==2 && bound.run.runtimeCheckpointScenario.run_control.runtime_checkpoint_keep==4);
assert(bound.run.checkpointFirstSlot==49);
assert(isequaln(bound.meta,cfg.meta) && isequaln(bound.phy,cfg.phy) && isequaln(bound.channel,cfg.channel));
assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(bound.run.runtimeCheckpointScenario), ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(cfg.run.runtimeCheckpointScenario)));
settings.output.save_csv=false;
try
    sixgr.runtime.SlotCheckpoint.applyOperationalSettings(cfg,settings);
    error('test:UnreviewedSettingAccepted','Scientific output settings must not cross the operational binding.');
catch failure
    assert(strcmp(failure.identifier,'sixgr:checkpoint:InvalidOperationalSettings'));
end
fprintf('LIVE_CSV_PLOT_CADENCE_PASS first_final_preserved=1 scientific_guard_preserved=1\n');
ok=true;
end
