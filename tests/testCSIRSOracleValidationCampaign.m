function ok = testCSIRSOracleValidationCampaign()
%TESTCSIRSORACLEVALIDATIONCAMPAIGN Dedicated CSI-RS oracle validation path.
setup6GRSimToolkit("Verbose", false);
if exist("nrCSIRS", "file") ~= 2 || exist("nrChannelEstimate", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.numerology.scs_kHz = 30;
cfg.phy.csirs.enable = true;
cfg.phy.csirs.rbOffset = 0;
cfg.phy.csirs.numRB = 24;
cfg.phy.csirs.density = "one";

res = sixgr.phy.refsig.runCSIRSOracleValidation(cfg, ...
    "RunId", "test_csirs_oracle_validation", ...
    "PortCounts", [1 2 4], ...
    "SNRdB", Inf);
T = res.TrialTable;
assert(logical(res.StrictOk), "CSI-RS oracle validation campaign must pass all configured anchors.");
assert(istable(T) && height(T) == 3, "CSI-RS oracle validation must emit one row per port-count anchor.");
assert(all(double(T.NRE) > 0), "Every CSI-RS oracle validation row must map real CSI-RS REs.");
assert(all(logical(T.OracleTestMode) & logical(T.OracleAvailable)), ...
    "CSI-RS validation rows must expose test-only oracle diagnostics.");
assert(~any(logical(T.EstimatorUsesTrueChannel)) && all(strlength(strtrim(string(T.UsedOracleFields))) == 0), ...
    "CSI-RS practical estimator must not consume the true-channel oracle.");
assert(all(isfinite(double(T.OracleNMSE_dB))) && all(double(T.OracleNMSE_dB) < -90), ...
    "CSI-RS oracle NMSE must be tight in the noiseless deterministic channel anchor.");
assert(all(string(T.EffectiveChannelConvention) == "csirs_effective_channel_grid_validation_only"), ...
    "CSI-RS validation rows must declare the effective-channel convention.");
ok = true;
end

