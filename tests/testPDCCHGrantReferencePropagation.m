function ok = testPDCCHGrantReferencePropagation()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_trials;
G = b.Result.ArtifactTables.pdcch_grant_validation;
validTrials = T(logical(T.StrictOk), :);
assert(~isempty(validTrials), "Strict PDCCH must produce valid decoded-grant trial references.");
assert(all(strlength(string(validTrials.GrantReferenceId)) > 0), ...
    "Strict positive PDCCH rows must carry GrantReferenceId.");
assert(all(ismember(string(validTrials.GrantReferenceId), string(G.GrantReferenceId))), ...
    "Strict positive GrantReferenceId values must exist in grant validation table.");
ok = true;
end
