function testPRACHFiniteReceiverSNRResolution
%TESTPRACHFINITERECEIVERSNRRESOLUTION Null scenario SNR must not crash PRACH.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "__web_runtime_webgui_master_2cell_2ue_full_profile_optimized_20260624_1758.yaml");
if exist(scenarioPath, "file") ~= 2
    scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "master_geometry_based.yaml");
end
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "prach_finite_snr_resolution"));
cfg.channel.snr_dB = NaN;
cfg.random_access.snr_sweep_db = [5 12 18];
cfg.phy.prach.enable = true;

slot = 5;
validSlots = double(sixgr.util.structGet(cfg, "phy.prach.validSlots1Based", []));
if ~isempty(validSlots)
    slot = validSlots(1);
end
out = sixgr.link.runPRACHDetection(cfg, "SNR_dB", NaN, "CanonicalSlot", slot);

assert(isfinite(double(out.ConfiguredSNR_dB)) || isinf(double(out.ConfiguredSNR_dB)), ...
    "PRACH detector must resolve a finite/noise-free receiver Es/N0 axis when scenario SNR is null.");
assert(~contains(string(out.Notes), "finite scalar"), ...
    "PRACH detector must not fail through addAwgnComplex with a non-finite SNR.");
assert(strlength(string(out.AppliedAWGNSNRSource)) > 0, ...
    "PRACH detector must publish the applied PRACH SNR source.");
assert(contains(string(out.SNRValueRole), "prach_receiver_esn0"), ...
    "Resolved PRACH SNR must remain labelled as a PRACH receiver acquisition axis.");
end
