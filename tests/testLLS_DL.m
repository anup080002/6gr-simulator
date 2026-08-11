function ok = testLLS_DL()
%TESTLLS_DL Regression checks for DL BLER/throughput behavior.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
% This test qualifies the PDSCH/DL-SCH chain only. CSI-RS has its own
% strict resource/codebook tests and must be explicitly configured rather
% than inheriting the system-level default without a physical codebook.
cfg.phy.csirs.enable = false;
cfg.phy.csirs.enabled = false;

resLow = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 6, ...
    "SNR_dB", 0, "ExecutionProfile", "phy_calibration");
resHigh = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 6, ...
    "SNR_dB", 18, "ExecutionProfile", "phy_calibration");
assert(isfield(resLow, "Ok") && isfield(resHigh, "Ok"), "Result missing Ok");
assert(isfield(resLow, "BLER") && isfield(resHigh, "BLER"), "Result missing BLER");
assert(isfield(resLow, "BER") && isfield(resHigh, "BER"), "Result missing BER");
assert(isfield(resLow, "Throughput_Mbps") && isfield(resHigh, "Throughput_Mbps"), "Result missing throughput");

if logical(resLow.Skipped) || logical(resHigh.Skipped)
    assert(logical(resLow.Skipped) && logical(resHigh.Skipped), ...
        "DL runs must both skip or both execute.");
    ok = true;
    return;
end

assert(isfinite(double(resLow.BLER)) && double(resLow.BLER) >= 0 && double(resLow.BLER) <= 1, "Invalid low-SNR BLER.");
assert(isfinite(double(resHigh.BLER)) && double(resHigh.BLER) >= 0 && double(resHigh.BLER) <= 1, "Invalid high-SNR BLER.");
assert(isfinite(double(resLow.BER)) && double(resLow.BER) >= 0 && double(resLow.BER) <= 1, "Invalid low-SNR BER.");
assert(isfinite(double(resHigh.BER)) && double(resHigh.BER) >= 0 && double(resHigh.BER) <= 1, "Invalid high-SNR BER.");
assert(double(resHigh.BLER) <= double(resLow.BLER) + 0.15, "DL BLER should improve with SNR.");
assert(double(resHigh.Throughput_Mbps) + 0.1 >= double(resLow.Throughput_Mbps), "DL throughput should not regress at high SNR.");
if istable(resLow.TrialTable) && istable(resHigh.TrialTable) && ...
        all(ismember(["WidebandCQI","MCS"], string(resLow.TrialTable.Properties.VariableNames))) && ...
        all(ismember(["WidebandCQI","MCS"], string(resHigh.TrialTable.Properties.VariableNames)))
    assert(mean(double(resHigh.TrialTable.WidebandCQI), "omitnan") >= mean(double(resLow.TrialTable.WidebandCQI), "omitnan"), ...
        "DL wideband CQI should not regress at higher SNR.");
end
ok = true;
end
