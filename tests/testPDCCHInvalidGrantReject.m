function ok = testPDCCHInvalidGrantReject()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_trials;
row = T(string(T.TrialType) == "invalid_grant_fields", :);
assert(height(row) == 1, "Invalid-grant PDCCH trial must be present.");
assert(~logical(row.StrictOk(1)) && logical(row.NegativeExpectedOk(1)), ...
    "Invalid DCI grant fields must not become strict PDCCH success.");
G = b.Result.ArtifactTables.pdcch_grant_validation;
assert(any(~logical(G.Valid)), "Grant validation table must expose an invalid grant row.");
ok = true;
end
