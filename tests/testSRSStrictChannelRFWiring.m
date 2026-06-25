function ok = testSRSStrictChannelRFWiring()
%TESTSRSSTRICTCHANNELRFWIRING Strict SRS/TRS over fading channels requires Channel/RF evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_scenaio_all_file.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);

assert(logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", false)), ...
    "Fixture must require strict SRS evidence.");
assert(~strcmpi(char(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))), "AWGN"), ...
    "Fixture must use a non-AWGN channel model.");
assert(logical(sixgr.util.structGet(cfg, "validation.channel_rf_configured_vs_applied.enabled", false)), ...
    "Strict reference-signal validation over non-AWGN channels must enable Channel/RF configured-vs-applied evidence.");

objectives = string(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)));
assert(any(objectives == "channel_rf_strict_validation"), ...
    "Strict reference-signal validation over non-AWGN channels must call sixgr.channel.runStrictChannelRFValidation.");

ok = true;
end
