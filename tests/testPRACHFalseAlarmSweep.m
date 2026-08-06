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
required = ["CILower","CIUpper","CIWidth","ConfidenceLevel", ...
    "StatisticalQualification","StatisticallyQualified","StoppingReason", ...
    "DeterministicSeedSet","EvidenceUnit"];
assert(all(ismember(required,string(faT.Properties.VariableNames))), ...
    "PRACH false-alarm evidence must export exact interval and stopping provenance.");
assert(all(string(faT.StatisticalQualification) == "NOT_EVALUATED") && ...
    all(~logical(faT.StatisticallyQualified)), ...
    "The two-occasion mini anchor must remain statistically unqualified.");
assert(all(double(faT.CIUpper) > double(faT.TargetFalseAlarmProbability)), ...
    "A zero-event mini anchor cannot prove a 0.1%% false-alarm target.");
assert(~logical(b.Result.StatisticallyQualified), ...
    "Functional PRACH health must not be promoted to statistical qualification.");
assert(all(~logical(noiseRows.StrictOk)), "Noise-only false-alarm rows must never count as strict positives.");
assert(all(~logical(noiseRows.ProxyUsed) & ~logical(noiseRows.Skipped) & ~logical(noiseRows.ToolboxMissing)), ...
    "Noise-only false-alarm evidence must still use the real detector path.");

ok = true;
end
