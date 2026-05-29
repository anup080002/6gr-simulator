function ok = testLLS_ReferencePoints()
%TESTLLS_REFERENCEPOINTS Golden-style PHY reference points (AWGN baseline).
% Reference envelopes were recalibrated on 2026-05-29 after fixing payload
% and DM-RS index-base alignment in the DL/UL waveform grids. The bounds below are based on the fixed
% `rng(2026,"twister")` reference run, with a small tolerance band and an
% additional three-seed sanity check kept outside this test.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

rng(2026, "twister");
dl0 = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 0);
dl20 = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 20);
ul0 = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 0);
ul20 = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 20);

if logical(dl0.Skipped) || logical(dl20.Skipped)
    assert(logical(dl0.Skipped) && logical(dl20.Skipped), ...
        "DL reference runs must both skip or both execute.");
else
    localAssertRange(double(dl0.BER), 0.17, 0.21, "DL BER @0dB out of reference envelope.");
    localAssertRange(double(dl20.BER), 0.0, 0.005, "DL BER @20dB out of reference envelope.");
    localAssertRange(double(dl20.BLER), 0.0, 0.25, "DL BLER @20dB out of reference envelope.");
    assert(double(dl20.BER) <= double(dl0.BER), "DL BER must improve with SNR.");
    assert(double(dl20.BER) <= 0.15 * max(double(dl0.BER), eps), "DL BER improvement is below reference expectation.");
    if istable(dl0.TrialTable) && istable(dl20.TrialTable) && ...
            all(ismember(["WidebandCQI","MCS"], string(dl0.TrialTable.Properties.VariableNames))) && ...
            all(ismember(["WidebandCQI","MCS"], string(dl20.TrialTable.Properties.VariableNames)))
        assert(mean(double(dl20.TrialTable.WidebandCQI), "omitnan") >= mean(double(dl0.TrialTable.WidebandCQI), "omitnan"), ...
            "DL reference CQI should improve with SNR.");
    end
end

if logical(ul0.Skipped) || logical(ul20.Skipped)
    assert(logical(ul0.Skipped) && logical(ul20.Skipped), ...
        "UL reference runs must both skip or both execute.");
else
    localAssertRange(double(ul0.BER), 0.25, 0.40, "UL BER @0dB out of reference envelope.");
    localAssertRange(double(ul20.BER), 0.0, 0.005, "UL BER @20dB out of reference envelope.");
    localAssertRange(double(ul20.BLER), 0.0, 0.25, "UL BLER @20dB out of reference envelope.");
    assert(double(ul20.BER) <= double(ul0.BER), "UL BER must improve with SNR.");
    assert(double(ul20.BER) <= 0.45 * max(double(ul0.BER), eps), "UL BER improvement is below reference expectation.");
    if istable(ul0.TrialTable) && istable(ul20.TrialTable) && ...
            all(ismember(["WidebandCQI","MCS"], string(ul0.TrialTable.Properties.VariableNames))) && ...
            all(ismember(["WidebandCQI","MCS"], string(ul20.TrialTable.Properties.VariableNames)))
        assert(mean(double(ul20.TrialTable.WidebandCQI), "omitnan") >= mean(double(ul0.TrialTable.WidebandCQI), "omitnan"), ...
            "UL reference CQI should improve with SNR.");
    end
end

ok = true;
end

function localAssertRange(x, lo, hi, msg)
assert(isfinite(x), "Reference metric must be finite.");
assert(x >= lo && x <= hi, msg);
end
