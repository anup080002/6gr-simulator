function ok = testTRSLowSNRSweep()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_low_snr_sweep;
assert(height(T) >= 4 && all(double(T.DetectionProbability) >= 0 & double(T.DetectionProbability) <= 1), ...
    "TRS low-SNR sweep must export measured detection probabilities.");
ok = true;
end
