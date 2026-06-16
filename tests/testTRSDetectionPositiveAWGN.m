function ok = testTRSDetectionPositiveAWGN()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(height(row) == 1 && logical(row.StrictOk(1)), "Positive TRS AWGN trial must pass strict.");
assert(logical(row.DetectionAttempted(1)) && logical(row.DetectionSuccess(1)), ...
    "Positive TRS trial must attempt and succeed detection.");
ok = true;
end
