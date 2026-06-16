function ok = testTRSWrongScramblingIdNegative()
setup6GRSimToolkit("Verbose", false);
localAssertNegative("wrong_scrambling_id");
ok = true;
end

function localAssertNegative(name)
T = trsStrictAnchorResult().Result.ArtifactTables.trs_negative_trials;
row = T(string(T.TrialType) == string(name), :);
assert(height(row) == 1 && ~logical(row.StrictOk(1)) && logical(row.NegativeExpectedOk(1)), ...
    "%s must fail strict as an expected negative.", name);
end
