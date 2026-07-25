function ok = testPrompt2FixedLinkCalibrationSchemaValidation()
%TESTPROMPT2FIXEDLINKCALIBRATIONSCHEMAVALIDATION Cover fixed-link sweep schema and validation rules.

setup6GRSimToolkit("Verbose", false);

repoRoot = pwd;

sweepCfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(repoRoot, ...
    "simulator", "configs", "scenarios", "master_sinr_sweep.yaml"));
assert(string(sweepCfg.get("validation.run_class", "")) == "fixed_snr_sweep_lls", ...
    "Sweep scenario should resolve to fixed_snr_sweep_lls.");
assert(logical(sweepCfg.get("sweeps_and_matrix.snr_sweep.enabled", false)), ...
    "Sweep scenario should keep sweeps_and_matrix.snr_sweep.enabled=true.");
assert(string(sweepCfg.get("simulation.noise_operating_mode", "")) == "standalone_awgn_snr_argument", ...
    "Fixed-link-only sweep scenario should auto-normalize simulation.noise_operating_mode.");

geometryCfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(repoRoot, ...
    "simulator", "configs", "scenarios", "master_geometry_based.yaml"));
assert(string(geometryCfg.get("validation.run_class", "")) == "ue_placement_geometry_lls", ...
    "Geometry scenario should resolve to ue_placement_geometry_lls.");
assert(~logical(geometryCfg.get("sweeps_and_matrix.snr_sweep.enabled", true)), ...
    "Geometry scenario should keep sweeps_and_matrix.snr_sweep.enabled=false.");

baselineCfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(repoRoot, ...
    "simulator", "configs", "scenarios", "dl_4ghz_baseline.yaml"));
assert(strlength(baselineCfg.ScenarioID) > 0, "Existing baseline scenario should continue to load.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

localExpectInvalid(tmp, "one_point_snr_sweep", struct( ...
    "sweeps_and_matrix", struct("snr_sweep", struct("enabled", true, "values_db", 0))), ...
    "SNRSweepNeedsAtLeastTwoPoints");

localExpectInvalid(tmp, "fixed_link_bad_trial_range", struct( ...
    "sweeps_and_matrix", struct("fixed_link_calibration", struct( ...
        "enabled", true, ...
        "snr_db", [0 2], ...
        "min_trials", 10, ...
        "max_trials", 9))), ...
    "FixedLinkCalibrationTrialRangeInvalid");

ok = true;
end

function localExpectInvalid(tmp, name, patch, expectedID)
cfg = localBaseScenarioStruct(name);
cfg = sixgr.util.mergeStruct(cfg, patch);
path = localWriteConfig(tmp, name, cfg);
threw = false;
try
    sixgr.lls6g.config.loadScenarioConfig(path);
catch ME
    threw = contains(string(ME.identifier), string(expectedID));
end
assert(threw, "Expected %s to fail with %s.", name, expectedID);
end

function path = localWriteConfig(tmp, name, cfg)
path = char(fullfile(char(tmp), sprintf("%s.yaml", char(name))));
sixgr.util.jsonWrite(path, cfg);
end

function cfg = localBaseScenarioStruct(name)
cfg = struct();
cfg.inherits = {fullfile(pwd, "simulator", "configs", "defaults", "global.yaml")};
cfg.meta = struct( ...
    "scenario_id", char(name), ...
    "description", char(name), ...
    "version", "1.0", ...
    "owner", "test", ...
    "maturity_tag", "smoke");
end
