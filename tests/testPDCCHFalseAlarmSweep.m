function ok = testPDCCHFalseAlarmSweep()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_false_alarm_sweep;
assert(height(T) >= 3, "Strict PDCCH false-alarm sweep must cover multiple SNR points.");
assert(all(double(T.NumTrials) >= 2), "False-alarm sweep must use repeated noise-only trials.");
assert(all(double(T.FalseAlarmProbability) >= 0 & double(T.FalseAlarmProbability) <= 1), ...
    "False-alarm probabilities must be bounded.");
ok = true;
end
