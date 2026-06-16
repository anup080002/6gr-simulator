function ok = testPRACHTimingOffsetSweep()
%TESTPRACHTIMINGOFFSETSWEEP Timing-offset evidence guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
timingT = b.Result.ArtifactTables.prach_timing_offset_sweep;
trialT = b.Result.ArtifactTables.prach_trials;
timingRows = trialT(string(trialT.TrialType) == "timing_offset_sweep", :);

assert(height(timingT) >= 3, "Strict PRACH timing sweep must exercise at least three offsets.");
assert(all(double(timingT.WithinToleranceProbability) == 1), ...
    "All strict mini-anchor timing offsets must be estimated within tolerance.");
assert(all(double(timingT.MaxAbsTimingErrorSamples) <= 1.5), ...
    "Strict mini-anchor timing errors must stay within the configured sample tolerance.");
assert(all(logical(timingRows.PreambleIndexMatch)), ...
    "Timing-offset trials must still detect the configured preamble.");
assert(all(~logical(timingRows.StrictOk)), ...
    "Timing-offset sweep rows must remain measurement evidence, not positive strict pass rows.");

ok = true;
end
