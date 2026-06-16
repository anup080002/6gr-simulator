function ok = testTRSFrequencyTrackingPositive()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(logical(row.FrequencyTrackingAttempted(1)) && logical(row.TRSCFOEstimateAvailable(1)), ...
    "Positive TRS trial must expose attempted and available CFO tracking.");
assert(abs(double(row.FrequencyError_Hz(1))) <= 50, "TRS CFO estimate must be within tolerance.");
ok = true;
end
