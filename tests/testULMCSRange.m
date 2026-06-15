function ok = testULMCSRange()
%TESTULMCSRANGE Verify UL MCS responds to measured high-SINR evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(42, "twister");

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.periodicity", "slot");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.delayModel", "zero");
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pusch.codeRate", 0.12);

out = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 4, "SNR_dB", 24);
if isfield(out, "Skipped") && out.Skipped
    ok = true;
    return;
end
T = out.TrialTable;
assert(istable(T) && height(T) >= 2, "UL run must produce multiple trial rows.");
assert(max(double(T.PostEqSINR_dB), [], "omitnan") > 5, ...
    "UL post-equalization SINR must exceed 5 dB at 24 dB AWGN.");
assert(max(double(T.MCS), [], "omitnan") > 1, ...
    "UL MCS must exceed 1 at high measured SINR when AMC is enabled.");
assert(any(string(T.MeasuredTrialSINRSource) == "post_equalization_sinr_from_equalizer_channel_estimate"), ...
    "UL selected measured SINR must come from post-equalization receiver evidence.");

ok = true;
end
