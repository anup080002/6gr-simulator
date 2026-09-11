function ok = testE2E_FastVsTruth()
%TESTE2E_FASTVSTRUTH Removed fast/LUT modes must fail while truth still runs.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg = withCanonicalSchedulerTiming(cfg);
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.run.seed = 11;

tmpRoot = tempname;
mkdir(tmpRoot);
c = onCleanup(@() rmdir(tmpRoot, "s")); %#ok<NASGU>

commonArgs = { ...
    "ResultsRoot", tmpRoot, ...
    "Verbose", false, ...
    "SetupToolboxChecks", false, ...
    "OnlyE2E", true, ...
    "RunE2EStackProbe", true, ...
    "E2EDuration_s", 0.02, ...
    "E2EMaxSlots", 32, ...
    "E2EUECount", 2, ...
    "E2EEnableAI", false, ...
    "E2ESaveFigures", false, ...
    "UseMexAcceleration", false, ...
    "AutoBuildMexAcceleration", false, ...
    "VerifyArtifacts", false, ...
    "GenerateCampaignPlots", false, ...
    "E2EStrictValidation", false, ...
    "E2ETruthMaxSlots", 40};

scenarios = [ ...
    struct("TrafficModel", "xr",   "NumUE", 2, "Seed", 111), ...
    struct("TrafficModel", "mmtc", "NumUE", 2, "Seed", 303) ...
    ];

for i = 1:numel(scenarios)
    sc = scenarios(i);
    cfg.run.seed = double(sc.Seed);
    runArgs = [commonArgs, {"E2ETrafficModel", sc.TrafficModel, "E2EUECount", sc.NumUE}];

    rng(double(sc.Seed), "twister");
    repTruth = sixgr_run_3gpp_full_campaign(cfg, runArgs{:}, "E2EAirModel", "truth");
    verifyCampaignSeedAuthority(repTruth,double(sc.Seed));

    assert(isfield(repTruth, "E2E") && istable(repTruth.E2E.SummaryTable), "Truth run missing E2E summary.");
    assert(height(repTruth.E2E.SummaryTable) == 1, "Truth run must produce one E2E summary row.");

    sTruth = repTruth.E2E.SummaryTable(1,:);
    assert(lower(string(sTruth.E2EAirModel)) == "truth", "Truth run should use truth air model.");

    localAssertUnitInterval(double(sTruth.DeliveryRatio), "Truth DeliveryRatio");
    localAssertUnitInterval(double(sTruth.ACKRate), "Truth ACKRate");
    localAssertUnitInterval(double(sTruth.NACKRate), "Truth NACKRate");
    localAssertUnitInterval(double(sTruth.HARQ_RetxProbability), "Truth HARQ retx");

    assert(isfinite(double(sTruth.Offered_Mbps)) && double(sTruth.Offered_Mbps) >= 0, "Truth Offered_Mbps invalid.");
    assert(isfinite(double(sTruth.Goodput_Mbps)) && double(sTruth.Goodput_Mbps) >= 0, "Truth Goodput_Mbps invalid.");
    assert(isfield(repTruth.E2E, "CheckTable") && ~isempty(repTruth.E2E.CheckTable), "Truth run missing component checks.");

    threw = false;
    try
        sixgr_run_3gpp_full_campaign(cfg, runArgs{:}, "E2EAirModel", "lut"); %#ok<NASGU>
    catch ME
        threw = strcmp(ME.identifier, "sixgr:campaign:ProxyModeRemoved");
    end
    assert(threw, "Removed LUT/fast E2E mode must fail closed.");
end
ok = true;
end

function localAssertUnitInterval(x, name)
assert(isfinite(x), "%s must be finite.", name);
assert(x >= 0 && x <= 1, "%s must be within [0,1].", name);
end
