function ok = testPDCCHBlindDecodePositiveDCI00()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_trials;
row = T(string(T.TrialType) == "positive_dci_0_0", :);
assert(height(row) == 1 && logical(row.StrictOk(1)), "DCI 0_0 positive strict PDCCH trial must pass.");
assert(string(row.GrantType(1)) == "PUSCH", "DCI 0_0 positive trial must decode a UL/PUSCH grant.");
ok = true;
end
