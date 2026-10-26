function ok=testN40SweepCheckpointHorizon()
% Production YAML binding/negative guards, not a completed physical run.
setup6GRSimToolkit('Verbose',false);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
s=scfg.toStruct();
parent=sixgr.lls6g.buildInternalConfig(scfg,tempname);
check(parent);
overrides=s.scenario.sweep.overrides;
if iscell(overrides), overrides=[overrides{:}]; end
expectedSNR=[20 0];
assert(numel(overrides)==2);
for k=1:numel(overrides)
    child=sixgr.util.mergeStruct(s,overrides(k).config);
    child=sixgr.lls6g.config.normalizeScenarioAliases(child,'Authority',overrides(k).config);
    child.scenario.runner_profile='waveform_bundle';
    sixgr.lls6g.config.validateScenarioConfig(child,'Kind','scenario','AllowPartial',false);
    cfg=sixgr.lls6g.buildInternalConfig(child,tempname);
    check(cfg);
    assert(string(cfg.run.runtimeCheckpointScenario.scenario.runner_profile)=="waveform_bundle");
    assert(cfg.run.runtimeCheckpointScenario.simulation.snr_db==expectedSNR(k));
end
bad=s; bad.run_control.runtime_checkpoint_resume_from='child/state.mat';
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:checkpoint:SweepParentResumeUnsupported');
bad=s; bad.scenario.sweep.base_profile='ai_benchmark';
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:checkpoint:UnsupportedRuntime');
bad=s; bad.run_control.deterministic_mode=false; bad.simulation.deterministic_mode=false;
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:checkpoint:DeterminismRequired');
fprintf('N40_SWEEP_CHECKPOINT_HORIZON_PASS points=2 slots=60 duration_ms=30 terminal_checkpoint=60 physical_execution=0\n');
ok=true;
end

function check(cfg)
assert(cfg.run.totalSlots==60 && cfg.run.totalTime_ms==30 && cfg.run.measurementSlots==60);
assert(cfg.run.runtimeCheckpointEnabled && cfg.run.checkpointFirstSlot==60 && cfg.run.checkpointEverySlots==60);
slots=1:cfg.run.totalSlots;
due=arrayfun(@(slot)sixgr.runtime.CheckpointSchedule.due(slot,cfg.run.checkpointEverySlots,cfg.run.checkpointFirstSlot),slots);
assert(isequal(slots(due),60));
end

function reject(call,identifier)
caught=false;
try, call(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    caught=true;
end
assert(caught,'Expected %s.',identifier);
end
