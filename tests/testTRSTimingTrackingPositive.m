function ok = testTRSTimingTrackingPositive()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(logical(row.TimingTrackingAttempted(1)) && logical(row.TRSTimingEstimateAvailable(1)), ...
    "Positive TRS trial must expose attempted and available timing tracking.");
assert(abs(double(row.TimingError_samples(1))) <= 2, "TRS timing error must be within tolerance.");
ok = true;
end
