function T = rarDCIFieldEvidence(result,ra,tx,rx)
T = sixgr.phy.ra.commonDCIFieldEvidence(result,ra.Msg2Slot,ra.RARNTI,tx,rx,"RAR");
end
