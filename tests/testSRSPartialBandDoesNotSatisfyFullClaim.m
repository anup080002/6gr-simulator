function ok = testSRSPartialBandDoesNotSatisfyFullClaim()
setup6GRSimToolkit("Verbose", false);
neg = srsStrictAnchorResult().Result.ArtifactTables.srs_negative_trials;
row = neg(string(neg.TrialType) == "partial_band_claimed_full", :);
assert(height(row) == 1, "Partial-band/full-claim negative SRS row must exist.");
assert(~logical(row.StrictOk) && contains(string(row.FailureReason), "srs_partial_band_claimed_full"), ...
    "Partial-band SRS must not satisfy a full-carrier sounding claim.");
ok = true;
end
