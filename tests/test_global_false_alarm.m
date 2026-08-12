function test_global_false_alarm()
%TEST_GLOBAL_FALSE_ALARM Verify independent full-search threshold seeds.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
cfg.false_alarm.calibration_trials=32; cfg.false_alarm.validation_trials=32;
cfg.search.cfo_hypotheses_hz=[-17587.5 0 17587.5];
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9105);
c=sixgr.phy.ia.c0.search.calibrateGlobalFalseAlarm(b,cfg);
v=sixgr.phy.ia.c0.search.validateGlobalFalseAlarm(b,cfg,c.Threshold);
assert(v.IndependentFromCalibration);
assert(v.CILow<=cfg.false_alarm.target_probability&&v.CIHigh>=cfg.false_alarm.target_probability);
assert(isfinite(c.Threshold)&&c.Threshold>0);
fprintf('test_global_false_alarm: PASS\n');
end
