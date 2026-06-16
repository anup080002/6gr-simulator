function ok = testPDCCHCorruptedPDCCHReject()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_corruption_trials;
assert(height(T) >= 2, "Corruption evidence must include data and DM-RS corruption trials.");
assert(all(logical(T.NegativeExpectedOk)), "Corrupted PDCCH trials must reject as expected.");
ok = true;
end
