function ok = testTRSMissingResourceCoverageNegative()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_negative_trials;
row = T(string(T.TrialType) == "missing_resource_subset", :);
assert(height(row) == 1 && ~logical(row.StrictOk(1)) && logical(row.NegativeExpectedOk(1)), ...
    "Missing TRS resource subset must fail strict as an expected negative.");
assert(double(row.ResourceCoverageRatio(1)) < 0.95 || ~logical(row.DetectionSuccess(1)), ...
    "Missing-resource negative must expose coverage or detection failure.");
ok = true;
end
