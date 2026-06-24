function ok = testSRSConfiguredBandResolvedBandwidth()
setup6GRSimToolkit("Verbose", false);
cfg = localConfiguredBandCfg();
rf = tempname;
mkdir(rf);
c = onCleanup(@() rmdir(rf, "s")); %#ok<NASGU>

srsCfg = sixgr.phy.srs.buildSRSConfigFromScenario(cfg, ...
    "RunFolder", rf, "RunId", "srs_configured_band_resolved", ...
    "ScenarioName", "srs_configured_band_resolved");
mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
cov = mapping.Coverage;

assert(string(srsCfg.CoverageRequirement) == "configured_band", ...
    "Regression config must exercise configured-band SRS validation.");
assert(~logical(srsCfg.FullCarrierSoundingRequired), ...
    "Configured-band SRS must not be silently promoted to a full-carrier claim.");
assert(double(srsCfg.ExpectedNumRB) == double(srsCfg.NumRB), ...
    "Default expected configured-band width must follow the bound NR SRS bandwidth.");
assert(double(cov.OccupiedPRBCount) == double(srsCfg.ExpectedNumRB), ...
    "Configured-band coverage must be measured against actual mapped SRS PRBs.");
assert(logical(cov.ConfiguredBandClaimValid) && logical(srsCfg.StrictValidation.StrictValid), ...
    "Resolved configured-band SRS coverage must validate strictly.");
assert(~logical(cov.FullCarrierClaimValid), ...
    "A configured-band SRS resource that does not cover every carrier PRB must not claim full-carrier coverage.");

result = sixgr.phy.srs.runStrictSRSValidation(cfg, ...
    "RunFolder", rf, "RunId", "srs_configured_band_resolved", ...
    "ScenarioName", "srs_configured_band_resolved", "WriteArtifacts", false);
T = result.ArtifactTables.srs_trials;
positive = T(string(T.TrialType) == "positive_awgn", :);
wrongPort = T(string(T.TrialType) == "wrong_port", :);
assert(logical(result.StrictOk), "Configured-band SRS strict validation must pass.");
assert(logical(positive.DetectionSuccess) && logical(positive.SRSChannelEstimateAvailable) && ...
    logical(positive.ConfiguredBandClaimValid), ...
    "Configured-band positive SRS must expose detection and channel-estimate evidence.");
assert(~logical(wrongPort.StrictOk) && logical(wrongPort.NegativeExpectedOk) && ...
    contains(string(wrongPort.FailureReason), "srs_detection_failed"), ...
    "Wrong-port negative SRS must fail even for a 4-port configured-band resource.");
ok = true;
end

function cfg = localConfiguredBandCfg()
cfg = struct();
cfg.run.seed = 240619;
cfg.channel.model = "AWGN";
cfg.channel.snr_dB = 35;
cfg.phy.carrier.NCellID = 7;
cfg.phy.carrier.NSizeGrid = 273;
cfg.phy.carrier.NStartGrid = 0;
cfg.phy.numerology.scs_kHz = 30;
cfg.phy.numerology.cyclicPrefix = "normal";
cfg.phy.srs.enable = true;
cfg.phy.srs.nPorts = 4;
cfg.phy.srs.bandwidthRB = 273;
cfg.lls6g.reference_signals.srs.coverage_requirement = "configured_band";
cfg.lls6g.reference_signals.srs.full_carrier_sounding_required = false;
cfg.lls6g.reference_signals.srs.slot_numbers = 0;
cfg.lls6g.reference_signals.srs.low_snr_sweep_db = 35;
cfg.lls6g.reference_signals.srs.timing_offset_sweep_samples = 0;
end
