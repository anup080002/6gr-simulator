function ok = testPRACHFalseAlarmSweep()
%TESTPRACHFALSEALARMSWEEP Noise-only false-alarm sweep evidence guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
faT = b.Result.ArtifactTables.prach_false_alarm_sweep;
trialT = b.Result.ArtifactTables.prach_trials;
noiseRows = trialT(string(trialT.TrialType) == "false_alarm_sweep", :);

assert(height(faT) >= 2, "Strict PRACH false-alarm sweep must contain multiple SNR/noise points.");
assert(all(double(faT.FalseAlarmProbability) >= 0 & double(faT.FalseAlarmProbability) <= 1), ...
    "False-alarm probabilities must be valid probabilities.");
assert(all(double(faT.FalseAlarmProbability) <= double(faT.TargetFalseAlarmProbability)), ...
    "Mini anchor false-alarm rate must stay below the configured target threshold.");
assert(all(~logical(noiseRows.StrictOk)), "Noise-only false-alarm rows must never count as strict positives.");
assert(all(~logical(noiseRows.ProxyUsed) & ~logical(noiseRows.Skipped) & ~logical(noiseRows.ToolboxMissing)), ...
    "Noise-only false-alarm evidence must still use the real detector path.");

ok = true;
end
