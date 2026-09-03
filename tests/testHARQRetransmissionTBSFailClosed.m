function ok = testHARQRetransmissionTBSFailClosed()
%TESTHARQRETRANSMISSIONTBSFAILCLOSED Reject a HARQ TB without frozen exact TBS.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
cfg = withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;

localAssertHARQEntityRejectsMissingTBS(cfg);
ok = true;
end

function localAssertHARQEntityRejectsMissingTBS(cfg)
rnti = 8101;
harq = sixgr.l2.mac.HARQEntityDL(cfg, "MaxRetx", 3);
txp = harq.allocate(rnti, 0, 100, "NewData", true);
% Provide a real LDPC coding layout and scheduling geometry, but deliberately
% omit TBSBits/TBSBytes and the transmitted payload. The tentative byte count
% reserved by allocate() is not a PHY TBS authority and must never be promoted
% into a first-transmission or retransmission grant.
malformedGrant = struct( ...
    "Direction", "DL", "RNTI", rnti, "Slot", 0, ...
    "PRBSet", 0:3, "SymbolAllocation", [2 12], ...
    "Modulation", "QPSK", "NumLayers", 1, ...
    "TargetCodeRate", 0.3, "MCSIndex", 1, ...
    "CodingLayout", localCodingLayout(800));
localAssertThrows(@() harq.onTx(rnti, txp.HARQ.HarqID, ...
    uint8([]), malformedGrant, 0), "sixgr:harq:BadTBContextTBS");
end

function layout = localCodingLayout(tbsBits)
targetCodeRate = 0.3;
rateMatchedBits = 2 * ceil((double(tbsBits) + 24) / targetCodeRate / 2);
layout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", "DL", ...
    "TransportBlockSize", double(tbsBits), ...
    "TargetCodeRate", targetCodeRate, ...
    "RV", 0, ...
    "Modulation", "QPSK", ...
    "NumLayers", 1, ...
    "RateMatchedBitCount", rateMatchedBits);
end

function localAssertThrows(fh, expectedId)
try
    fh();
catch cause
    assert(string(cause.identifier) == string(expectedId), ...
        "Expected %s, got %s: %s", expectedId, ...
        cause.identifier, cause.message);
    return;
end
error("ExpectedException:notThrown", ...
    "Expected %s to be thrown.", expectedId);
end
