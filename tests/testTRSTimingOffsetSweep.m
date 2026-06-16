function ok = testTRSTimingOffsetSweep()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_timing_offset_sweep;
assert(height(T) >= 3 && any(isfinite(double(T.TimingError_samples))), ...
    "TRS timing-offset sweep must export measured timing errors.");
ok = true;
end
