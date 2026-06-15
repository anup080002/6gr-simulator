function ok = testRANegativeMsg3CrcFail()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "msg3_pusch_corrupted", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "Corrupt MSG3 must not complete RA.");
assert(string(res.FailureReason) == "msg3_pusch_crc_fail", "MSG3 CRC failure must be explicit.");
ok = true;
end
