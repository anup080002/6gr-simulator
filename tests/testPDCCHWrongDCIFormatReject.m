function ok = testPDCCHWrongDCIFormatReject()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_trials;
row = T(string(T.TrialType) == "wrong_dci_format", :);
assert(height(row) == 1, "Wrong-format PDCCH trial must be present.");
assert(~logical(row.StrictOk(1)) && logical(row.NegativeExpectedOk(1)), ...
    "Wrong-format DCI must not become strict PDCCH success.");
ok = true;
end
