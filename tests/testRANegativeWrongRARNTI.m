function ok = testRANegativeWrongRARNTI()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "wrong_ra_rnti", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "Wrong RA-RNTI must not complete RA.");
assert(string(res.FailureReason) == "rar_pdcch_not_detected", "Wrong RA-RNTI must fail at MSG2 PDCCH.");
ok = true;
end
