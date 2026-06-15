function ok = testRANegativeRAPIDMismatch()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "wrong_rapid_in_rar", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "Wrong RAPID must not complete RA.");
assert(string(res.FailureReason) == "rar_rapid_mismatch", "RAPID mismatch must be explicit.");
ok = true;
end
