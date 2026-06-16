function ok = testPDCCHLowSNRSweep()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_low_snr_sweep;
assert(height(T) >= 4, "Strict PDCCH low-SNR sweep must cover configured SNR points.");
assert(all(double(T.DetectionProbability) >= 0 & double(T.DetectionProbability) <= 1), ...
    "Detection probabilities must be bounded.");
assert(all(double(T.CrcPassProbability) >= 0 & double(T.CrcPassProbability) <= 1), ...
    "CRC pass probabilities must be bounded.");
ok = true;
end
