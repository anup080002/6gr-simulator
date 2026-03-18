function ok = testE2E_FastVsTruth()
%TESTE2E_FASTVSTRUTH Multi-scenario envelope checks: fast LUT vs truth PHY.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
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
    struct("TrafficModel", "xr",   "NumUE", 2, "Seed", 111, "MaxDRGap", 0.80), ...
    struct("TrafficModel", "mmtc", "NumUE", 2, "Seed", 303, "MaxDRGap", 0.60) ...
    ];

for i = 1:numel(scenarios)
    sc = scenarios(i);
    runArgs = [commonArgs, {"E2ETrafficModel", sc.TrafficModel, "E2EUECount", sc.NumUE}];

    rng(double(sc.Seed), "twister");
    repFast = sixgr_run_3gpp_full_campaign(cfg, runArgs{:}, "E2EAirModel", "lut");
    rng(double(sc.Seed), "twister");
    repTruth = sixgr_run_3gpp_full_campaign(cfg, runArgs{:}, "E2EAirModel", "truth");

    assert(isfield(repFast, "E2E") && istable(repFast.E2E.SummaryTable), "Fast run missing E2E summary.");
    assert(isfield(repTruth, "E2E") && istable(repTruth.E2E.SummaryTable), "Truth run missing E2E summary.");
    assert(height(repFast.E2E.SummaryTable) == 1, "Fast run must produce one E2E summary row.");
    assert(height(repTruth.E2E.SummaryTable) == 1, "Truth run must produce one E2E summary row.");

    sFast = repFast.E2E.SummaryTable(1,:);
    sTruth = repTruth.E2E.SummaryTable(1,:);
    assert(lower(string(sFast.E2EAirModel)) == "lut", "Fast run should use LUT air model.");
    assert(lower(string(sTruth.E2EAirModel)) == "truth", "Truth run should use truth air model.");

    localAssertUnitInterval(double(sFast.DeliveryRatio), "Fast DeliveryRatio");
    localAssertUnitInterval(double(sTruth.DeliveryRatio), "Truth DeliveryRatio");
    localAssertUnitInterval(double(sFast.ACKRate), "Fast ACKRate");
    localAssertUnitInterval(double(sTruth.ACKRate), "Truth ACKRate");
    localAssertUnitInterval(double(sFast.NACKRate), "Fast NACKRate");
    localAssertUnitInterval(double(sTruth.NACKRate), "Truth NACKRate");
    localAssertUnitInterval(double(sFast.HARQ_RetxProbability), "Fast HARQ retx");
    localAssertUnitInterval(double(sTruth.HARQ_RetxProbability), "Truth HARQ retx");

    assert(isfinite(double(sFast.Offered_Mbps)) && double(sFast.Offered_Mbps) >= 0, "Fast Offered_Mbps invalid.");
    assert(isfinite(double(sTruth.Offered_Mbps)) && double(sTruth.Offered_Mbps) >= 0, "Truth Offered_Mbps invalid.");
    assert(isfinite(double(sFast.Goodput_Mbps)) && double(sFast.Goodput_Mbps) >= 0, "Fast Goodput_Mbps invalid.");
    assert(isfinite(double(sTruth.Goodput_Mbps)) && double(sTruth.Goodput_Mbps) >= 0, "Truth Goodput_Mbps invalid.");

    drFast = double(sFast.DeliveryRatio);
    drTruth = double(sTruth.DeliveryRatio);
    drGap = abs(drFast - drTruth);
    assert(drGap <= double(sc.MaxDRGap), "Fast-vs-truth delivery-ratio gap exceeds scenario envelope.");
    assert(drFast + 0.05 >= drTruth, "Fast proxy should not underperform truth beyond tolerance.");

    gpFast = double(sFast.Goodput_Mbps);
    gpTruth = double(sTruth.Goodput_Mbps);
    if gpTruth > 0.05
        gpRatio = gpFast / gpTruth;
        assert(gpRatio >= 0.5 && gpRatio <= 30, "Fast-vs-truth goodput ratio outside acceptance envelope.");
    end

    assert(isfield(repFast.E2E, "CheckTable") && ~isempty(repFast.E2E.CheckTable), "Fast run missing component checks.");
    assert(isfield(repTruth.E2E, "CheckTable") && ~isempty(repTruth.E2E.CheckTable), "Truth run missing component checks.");
end
ok = true;
end

function localAssertUnitInterval(x, name)
assert(isfinite(x), "%s must be finite.", name);
assert(x >= 0 && x <= 1, "%s must be within [0,1].", name);
end
