function ok = testSRSTimingOffsetSweep()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_timing_offset_sweep;
assert(height(T) >= 3, "SRS timing-offset sweep must contain configured offsets.");
assert(all(double(T.WithinToleranceProbability) >= 0 & double(T.WithinToleranceProbability) <= 1), ...
    "SRS timing tolerance probability must stay within [0,1].");
assert(any(isfinite(double(T.MeanTimingErrorSamples))), "SRS timing sweep must export finite timing-error evidence.");
ok = true;
end
