function ok = testStrictMode_NoFallbackAnywhere()
%TESTSTRICTMODE_NOFALLBACKANYWHERE Strict mode must reject fallback paths.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));

% Strict LUT fallback guard.
assert(exist(fullfile(repoRoot, "+sixgr", "+system", "BLER_LUT.m"), "file") == 0, ...
    "BLER_LUT proxy backend source should be removed from the repo.");

% Strict scheduler TBS fallback guard.
cfgS = sixgr.config.defaultConfig();
cfgS.run.strictMode = true;
sch = sixgr.l2.mac.SchedulerPF(cfgS, "Direction", "DL");
threwSched = false;
try
    sch.estimateTBS("BADMOD", 1, 10, [0 14], 0.5);
catch ME
    threwSched = contains(string(ME.identifier), "SchedulerBase:TBSFallback");
end
assert(threwSched, "Strict scheduler must reject rough TBS fallback.");

% Campaign strict mode: logistic air model is forbidden.
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

common = { ...
    "ResultsRoot", tmp, ...
    "Verbose", false, ...
    "SetupToolboxChecks", false, ...
    "OnlyE2E", true, ...
    "RunE2EStackProbe", true, ...
    "E2EDuration_s", 0.02, ...
    "E2EMaxSlots", 24, ...
    "E2EUECount", 2, ...
    "E2EEnableAI", false, ...
    "E2ESaveFigures", false, ...
    "UseMexAcceleration", false, ...
    "AutoBuildMexAcceleration", false, ...
    "VerifyArtifacts", false, ...
    "GenerateCampaignPlots", false, ...
    "E2EStrictValidation", true, ...
    "E2ETruthMaxSlots", 24 ...
    };

threwLogistic = false;
try
    sixgr_run_3gpp_full_campaign(cfg, common{:}, "E2EAirModel", "logistic");
catch ME
    threwLogistic = strcmp(ME.identifier, "sixgr:campaign:ProxyModeRemoved");
end
assert(threwLogistic, "Campaign runner must reject removed logistic air-model mode.");

threwMissingLUT = false;
try
    sixgr_run_3gpp_full_campaign(cfg, common{:}, "E2EAirModel", "lut");
catch ME
    threwMissingLUT = strcmp(ME.identifier, "sixgr:campaign:ProxyModeRemoved");
end
assert(threwMissingLUT, "Campaign runner must reject removed LUT air-model mode.");

ok = true;
end
