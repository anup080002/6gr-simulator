function ok = testSRSRuntimeCanonicalWidebandResource()
setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile("simulator", "configs", "scenarios", "master_geometry_based.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tempname);

cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";

slotIndex = 10;
out = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", 35, "SlotIndex", slotIndex);

assert(logical(out.Ok), "Runtime SRS channel-estimation path must execute successfully.");
assert(logical(out.MeasurementUsable), "Runtime SRS must produce a usable measured CSI row.");
assert(isfinite(double(out.SRSOccupiedPRBCount)) && isfinite(double(out.SRSCarrierPRBCount)), ...
    "Runtime SRS must export finite mapped/carrier PRB counts.");
assert(double(out.SRSOccupiedPRBCount) >= double(out.SRSCarrierPRBCount) - 1, ...
    "Runtime SRS must use the canonical wideband SRS resource, not the 4-PRB Toolbox default.");
assert(double(out.SRSBandwidthFraction) >= 0.99, ...
    "Runtime SRS wideband fraction must be sufficient for the SRS CSI freshness gate.");
assert(isfinite(double(out.SINR_dB)) && string(out.SINRValueStatus) == "OK", ...
    "Runtime SRS must produce finite receiver SINR for CSI/AMC consumption.");

ok = true;
end
