function ok = testPDCCHWrongRNTIReject()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_wrong_rnti_trials;
assert(height(T) > 0, "Wrong-RNTI evidence table must exist.");
assert(all(logical(T.NegativeExpectedOk)), "Wrong-RNTI trials must reject without strict success.");
assert(any(double(T.WrongRNTIRejectCount) > 0), "Wrong-RNTI reject count must be positive.");
ok = true;
end
