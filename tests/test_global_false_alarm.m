function test_global_false_alarm()
%TEST_GLOBAL_FALSE_ALARM Verify independent full-search threshold seeds.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
cfg.false_alarm.calibration_trials=32; cfg.false_alarm.validation_trials=32;
cfg.false_alarm.progress_interval=16; cfg.false_alarm.checkpoint_interval=16;
cfg.search.cfo_hypotheses_hz=[-17587.5 0 17587.5];
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9105);
folder=string(tempname); mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,"s")); %#ok<NASGU>
calCheckpoint=fullfile(folder,"calibration.mat");
calProgress=fullfile(folder,"calibration.csv");
valCheckpoint=fullfile(folder,"validation.mat");
valProgress=fullfile(folder,"validation.csv");
c=sixgr.phy.ia.c0.search.calibrateGlobalFalseAlarm(b,cfg, ...
    "CheckpointPath",calCheckpoint,"ProgressCSVPath",calProgress);
v=sixgr.phy.ia.c0.search.validateGlobalFalseAlarm(b,cfg,c, ...
    "CheckpointPath",valCheckpoint,"ProgressCSVPath",valProgress);
assert(v.IndependentFromCalibration);
assert(c.SeedLast<v.SeedFirst||v.SeedLast<c.SeedFirst);
assert(c.ReceiverExceptionCount==0&&v.ReceiverExceptionCount==0);
assert(isfile(calCheckpoint)&&isfile(calProgress)&& ...
    isfile(valCheckpoint)&&isfile(valProgress));
calStatus=readtable(calProgress,"TextType","string");
valStatus=readtable(valProgress,"TextType","string");
assert(calStatus.Status=="COMPLETE"&&calStatus.CompletedTrials==32);
assert(valStatus.Status=="COMPLETE"&&valStatus.CompletedTrials==32);
assert(v.DeclarationPath=="blind_pss_timing_cfo_nid2_then_all_pci_sss_confirmation");
assert(numel(c.PSSMetrics)==32&&numel(c.SSSMetrics)==32);
assert(~v.Passed, ...
    "A 32-window development test must not satisfy the production CI-precision gate.");
assert(isfinite(c.Threshold)&&c.Threshold>0);
fprintf('test_global_false_alarm: PASS\n');
end
