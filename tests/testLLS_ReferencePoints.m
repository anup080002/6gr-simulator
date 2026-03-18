function ok = testLLS_ReferencePoints()
%TESTLLS_REFERENCEPOINTS Golden-style PHY reference points (AWGN baseline).

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
    localAssertRange(double(dl0.BER), 0.25, 0.40, "DL BER @0dB out of reference envelope.");
    localAssertRange(double(dl20.BER), 0.001, 0.03, "DL BER @20dB out of reference envelope.");
    localAssertRange(double(dl20.BLER), 0.75, 1.0, "DL BLER @20dB out of reference envelope.");
    assert(double(dl20.BER) <= double(dl0.BER), "DL BER must improve with SNR.");
    assert(double(dl20.BER) <= 0.15 * max(double(dl0.BER), eps), "DL BER improvement is below reference expectation.");
end

if logical(ul0.Skipped) || logical(ul20.Skipped)
    assert(logical(ul0.Skipped) && logical(ul20.Skipped), ...
        "UL reference runs must both skip or both execute.");
else
    localAssertRange(double(ul0.BER), 0.25, 0.40, "UL BER @0dB out of reference envelope.");
    localAssertRange(double(ul20.BER), 0.005, 0.12, "UL BER @20dB out of reference envelope.");
    localAssertRange(double(ul20.BLER), 0.75, 1.0, "UL BLER @20dB out of reference envelope.");
    assert(double(ul20.BER) <= double(ul0.BER), "UL BER must improve with SNR.");
    assert(double(ul20.BER) <= 0.45 * max(double(ul0.BER), eps), "UL BER improvement is below reference expectation.");
end

ok = true;
end

function localAssertRange(x, lo, hi, msg)
assert(isfinite(x), "Reference metric must be finite.");
assert(x >= lo && x <= hi, msg);
end

