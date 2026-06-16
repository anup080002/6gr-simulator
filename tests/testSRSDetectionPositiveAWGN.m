function ok = testSRSDetectionPositiveAWGN()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(height(row) == 1, "SRS positive AWGN trial must exist.");
assert(logical(row.StrictOk) && logical(row.DetectionAttempted) && logical(row.DetectionSuccess), ...
    "Positive SRS AWGN trial must pass with attempted successful detection.");
assert(logical(row.ResourceExtractionAttempted) && logical(row.ResourceExtractionAvailable), ...
    "Positive SRS AWGN trial must expose receiver extraction evidence.");
ok = true;
end
