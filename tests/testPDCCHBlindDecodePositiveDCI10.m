function ok = testPDCCHBlindDecodePositiveDCI10()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_trials;
row = T(string(T.TrialType) == "positive_dci_1_0", :);
assert(height(row) == 1 && logical(row.StrictOk(1)), "DCI 1_0 positive strict PDCCH trial must pass.");
assert(logical(row.DCICrcPass(1)) && logical(row.DCIPayloadMatch(1)) && logical(row.GrantValid(1)), ...
    "DCI 1_0 positive trial must have CRC, payload hash, and grant validation success.");
ok = true;
end
