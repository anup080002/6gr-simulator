function ok = testRANegativeMsg4IdentityMismatch()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "msg4_identity_mismatch", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "Wrong MSG4 identity must not complete RA.");
assert(string(res.FailureReason) == "contention_resolution_identity_mismatch", "Contention mismatch must be explicit.");
ok = true;
end
