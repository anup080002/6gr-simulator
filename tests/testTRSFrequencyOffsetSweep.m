function ok = testTRSFrequencyOffsetSweep()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_frequency_offset_sweep;
assert(height(T) >= 3 && any(isfinite(double(T.FrequencyError_Hz))), ...
    "TRS CFO sweep must export measured frequency errors.");
ok = true;
end
