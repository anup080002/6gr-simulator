function ok = testRANegativeRARWindowExpiry()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "response_window_expiry", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "RAR outside window must not complete RA.");
assert(string(res.FailureReason) == "ra_response_window_expired", "RAR window expiry must be explicit.");
ok = true;
end
