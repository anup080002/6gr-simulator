function ok = testLLS_UL()
%TESTLLS_UL Regression checks for UL PAPR and PUSCH BLER behavior.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

papr = sixgr.link.runULLowPAPR(cfg, "NumFrames", 4);
assert(isfield(papr, "PAPR_CP_dB") && isfield(papr, "PAPR_DFTs_dB"), "PAPR metrics missing");
if isfinite(double(papr.PAPR_CP_dB)) && isfinite(double(papr.PAPR_DFTs_dB))
    assert(double(papr.PAPR_DFTs_dB) <= double(papr.PAPR_CP_dB) + 1.0, ...
        "DFT-s-OFDM PAPR should be <= CP-OFDM PAPR (with margin).");
end

puschLow = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 6, "SNR_dB", 0);
puschHigh = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 6, "SNR_dB", 18);
assert(isfield(puschLow, "Ok") && isfield(puschHigh, "Ok"), "PUSCH metrics missing Ok");
assert(isfield(puschLow, "BLER") && isfield(puschHigh, "BLER"), "PUSCH metrics missing BLER");
assert(isfield(puschLow, "BER") && isfield(puschHigh, "BER"), "PUSCH metrics missing BER");
assert(isfield(puschLow, "Throughput_Mbps") && isfield(puschHigh, "Throughput_Mbps"), "PUSCH metrics missing throughput");

if ~(logical(puschLow.Skipped) || logical(puschHigh.Skipped))
    assert(all(ismember(["NoiseVariance","NoiseVarStatus","NoiseVarSource","NoiseVarReason","NoiseVarStrictFailure", ...
        "ReceiverUsable","DecodeAttempted","DecodeUsable","FailureReason"], string(puschLow.TrialTable.Properties.VariableNames))) && ...
        all(ismember(["NoiseVariance","NoiseVarStatus","NoiseVarSource","NoiseVarReason","NoiseVarStrictFailure", ...
        "ReceiverUsable","DecodeAttempted","DecodeUsable","FailureReason"], string(puschHigh.TrialTable.Properties.VariableNames))), ...
        "UL PUSCH trial tables must expose explicit noise-variance and receiver-availability provenance.");
    assert(~any(abs(double(puschLow.TrialTable.NoiseVariance(:)) - 1e-10) < 1e-18) && ...
        ~any(abs(double(puschHigh.TrialTable.NoiseVariance(:)) - 1e-10) < 1e-18), ...
        "UL PUSCH truth trials must not export the legacy 1e-10 missing-noise fallback.");
    assert(all(strlength(string(puschLow.TrialTable.NoiseVarStatus)) > 0) && all(strlength(string(puschHigh.TrialTable.NoiseVarStatus)) > 0), ...
        "UL PUSCH trial tables must carry explicit noise-variance status on every observed row.");
    assert(double(puschLow.BLER) >= 0 && double(puschLow.BLER) <= 1, "Invalid low-SNR UL BLER.");
    assert(double(puschHigh.BLER) >= 0 && double(puschHigh.BLER) <= 1, "Invalid high-SNR UL BLER.");
    assert(double(puschHigh.BLER) <= double(puschLow.BLER) + 0.15, "UL BLER should improve with SNR.");
    assert(double(puschHigh.Throughput_Mbps) + 0.1 >= double(puschLow.Throughput_Mbps), ...
        "UL throughput should not regress at high SNR.");
    if istable(puschLow.TrialTable) && istable(puschHigh.TrialTable) && ...
            all(ismember(["WidebandCQI","MCS"], string(puschLow.TrialTable.Properties.VariableNames))) && ...
            all(ismember(["WidebandCQI","MCS"], string(puschHigh.TrialTable.Properties.VariableNames)))
        lowCQI = double(puschLow.TrialTable.WidebandCQI);
        highCQI = double(puschHigh.TrialTable.WidebandCQI);
        assert(all(~isfinite(lowCQI) | (lowCQI >= 1 & lowCQI <= 15)), ...
            "UL exported CQI must be NaN or a valid 3GPP CQI index in 1..15.");
        assert(all(~isfinite(highCQI) | (highCQI >= 1 & highCQI <= 15)), ...
            "UL exported CQI must be NaN or a valid 3GPP CQI index in 1..15.");
        assert(mean(double(puschHigh.TrialTable.WidebandCQI), "omitnan") >= mean(double(puschLow.TrialTable.WidebandCQI), "omitnan"), ...
            "UL wideband CQI should not regress at higher SNR.");
    end
else
    localAssertAllowedPUSCHSkip(puschLow, "low-SNR");
    localAssertAllowedPUSCHSkip(puschHigh, "high-SNR");
end

srs = sixgr.link.runSRSChannelEstimation(cfg);
assert(isfield(srs, "Ok"), "SRS result missing Ok");
assert(all(ismember(["NoiseVariance","NoiseVarStatus","NoiseVarSource","NoiseVarReason","NoiseVarStrictFailure","MeasurementAttempted","MeasurementUsable","FailureReason"], ...
    string(fieldnames(srs)))), ...
    "SRS truth helper must expose explicit noise-variance and measurement-availability provenance.");
assert(~isfinite(double(srs.NoiseVariance)) || abs(double(srs.NoiseVariance) - 1e-10) > 1e-18, ...
    "SRS truth helper must not report the legacy 1e-10 missing-noise fallback.");

prach = sixgr.link.runPRACHDetection(cfg);
assert(isfield(prach, "Ok"), "PRACH result missing Ok");
ok = true;
end

function localAssertAllowedPUSCHSkip(res, label)
if ~logical(res.Skipped)
    return;
end
note = lower(string(sixgr.util.structGet(res, "Notes", "")));
allowed = contains(note, "nrpusch apis unavailable") || contains(note, "phy.pusch.enable=false");
assert(allowed, sprintf("Unexpected %s PUSCH skip must not hide runtime frame crashes: %s", label, note));
end
