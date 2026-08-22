function test_c0_run_mode_guard()
%TEST_C0_RUN_MODE_GUARD Enforce immutable TDOC statistical minima.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","tdoc");
assert(cfg.run.mode=="tdoc");
assert(cfg.run.max_trials_per_snr>=200000&&cfg.run.min_errors_per_snr>=500);
assert(cfg.false_alarm.calibration_trials>=100000&& ...
    cfg.false_alarm.validation_trials>=100000);
bad=cfg; bad.run.max_trials_per_snr=199999;
localExpect(@()sixgr.phy.ia.c0.config.validateC0StudyScenario(bad), ...
    "sixgr:phy:ia:c0:config:TDocStatisticalMinimum");
[quick,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","tdoc_preflight");
assert(quick.run.mode=="quick_sanity"&&quick.run.max_trials_per_snr==1000);
[engineering,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","engineering_1000");
assert(engineering.run.mode=="quick_sanity");
assert(engineering.false_alarm.calibration_trials==1000&& ...
    engineering.false_alarm.validation_trials==1000);
assert(engineering.run.max_trials_per_snr==1000&& ...
    engineering.run.min_errors_per_snr==100);
assert(engineering.run.developer_allow_non_tdoc_tdoc_figures);
localExpect(@()sixgr.phy.ia.c0.campaigns.runC0Study( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke", ...
    "RunId","misleading_tdoc_name"), ...
    "sixgr:phy:ia:c0:campaign:MisleadingRunId");
fprintf('test_c0_run_mode_guard: PASS\n');
end

function localExpect(f,id)
try
    f();
    error("test_c0_run_mode_guard:MissingError","Expected %s.",id);
catch ME
    assert(string(ME.identifier)==string(id),"Unexpected error: %s",ME.identifier);
end
end
