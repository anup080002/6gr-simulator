function ok = testSRSLowSNRSweep()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_low_snr_sweep;
assert(height(T) >= 4, "SRS low-SNR sweep must contain configured sweep rows.");
assert(all(double(T.DetectionProbability) >= 0 & double(T.DetectionProbability) <= 1), ...
    "SRS detection probability must stay within [0,1].");
assert(any(double(T.ChannelAvailabilityProbability) < 1) && any(double(T.ChannelAvailabilityProbability) > 0), ...
    "SRS low-SNR sweep must show measured availability variation.");
ok = true;
end
