function ok = testStrictMode_NoFallbackAnywhere()
%TESTSTRICTMODE_NOFALLBACKANYWHERE Strict mode must reject fallback paths.

setup6GRSimToolkit("Verbose", false);

% Strict LUT fallback guard.
threwLUT = false;
try
    sixgr.system.BLER_LUT("StrictMode", true); %#ok<NASGU>
catch
    threwLUT = true;
end
assert(threwLUT, "Strict BLER_LUT build should reject synthetic fallback.");

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
    threwLogistic = contains(string(ME.identifier), "StrictLogisticForbidden");
end
assert(threwLogistic, "Strict E2E mode must reject logistic air-model fallback.");

threwMissingLUT = false;
try
    sixgr_run_3gpp_full_campaign(cfg, common{:}, "E2EAirModel", "lut");
catch ME
    threwMissingLUT = contains(string(ME.identifier), "StrictMissingDLLUT");
end
assert(threwMissingLUT, "Strict E2E LUT mode must fail when calibrated LUT is missing.");

ok = true;
end

