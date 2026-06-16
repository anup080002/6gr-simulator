function ok = testPDCCHNoSignalFalseAlarm()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_no_signal_trials;
assert(height(T) > 0, "No-signal PDCCH evidence table must exist.");
assert(any(logical(T.NegativeExpectedOk)), "At least one no-signal trial must reject as expected.");
fa = b.Result.ArtifactTables.pdcch_false_alarm_sweep;
assert(height(fa) > 0 && all(double(fa.FalseAlarmProbability) >= 0 & double(fa.FalseAlarmProbability) <= 1), ...
    "False-alarm sweep must export valid probabilities.");
ok = true;
end
