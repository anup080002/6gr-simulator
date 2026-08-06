function ok = testHARQRetransmissionTBSFailClosed()
%TESTHARQRETRANSMISSIONTBSFAILCLOSED Reject replay without frozen exact TBS.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
cfg = withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;

localAssertSchedulerRejectsMissingTBS(cfg, "RR");
localAssertSchedulerRejectsMissingTBS(cfg, "PF");
ok = true;
end

function localAssertSchedulerRejectsMissingTBS(cfg, policy)
rnti = 8101 + double(policy == "PF");
harq = sixgr.l2.mac.HARQEntityDL(cfg, "MaxRetx", 3);
txp = harq.allocate(rnti, 0, 100, "NewData", true);
% Preserve enough scheduling geometry to reach replay, but deliberately
% omit TBSBits/TBSBytes. The process byte count is not a substitute for the
% exact frozen PHY allocation and must never be promoted into a grant.
malformedGrant = struct( ...
    "Direction", "DL", "RNTI", rnti, "Slot", 0, ...
    "PRBSet", 0:3, "SymbolAllocation", [2 12], ...
    "Modulation", "QPSK", "NumLayers", 1, ...
    "TargetCodeRate", 0.3, "MCSIndex", 1);
harq.onTx(rnti, txp.HARQ.HarqID, uint8([]), malformedGrant, 0);
harq.onFeedback(rnti, txp.HARQ.HarqID, "NACK", ...
    "SourceSlot", 0, "FeedbackSlot", 1);

if policy == "PF"
    scheduler = sixgr.l2.mac.SchedulerPF(cfg, ...
        "Direction", "DL", "HARQ", harq);
    expectedId = "sixgr:SchedulerPF:MissingRetransmissionTBS";
else
    scheduler = sixgr.l2.mac.SchedulerRR(cfg, ...
        "Direction", "DL", "HARQ", harq);
    expectedId = "sixgr:SchedulerRR:MissingRetransmissionTBS";
end
ue = struct("RNTI", rnti, "DLBufferBytes", 100, ...
    "CQI", 4, "RI", 1, "HeadOfLineDelay_ms", 1);
localAssertThrows(@() scheduler.schedule(2, ue, ...
    struct("NPRB", 12, "SymbolAllocation", [2 12])), expectedId);
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
