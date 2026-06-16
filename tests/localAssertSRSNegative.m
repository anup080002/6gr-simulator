function localAssertSRSNegative(trialType, expectedReason)
T = srsStrictAnchorResult().Result.ArtifactTables.srs_negative_trials;
row = T(string(T.TrialType) == string(trialType), :);
assert(height(row) == 1, "Missing SRS negative trial '%s'.", string(trialType));
assert(~logical(row.StrictOk) && logical(row.NegativeExpectedOk), ...
    "SRS negative trial '%s' must fail strict validation as expected.", string(trialType));
assert(contains(string(row.FailureReason), string(expectedReason)), ...
    "SRS negative trial '%s' must expose expected failure reason '%s'.", string(trialType), string(expectedReason));
end
