function ok = testLLSClosedLoopLinkAdaptation()
%TESTLLSCLOSEDLOOPLINKADAPTATION Verify runtime LLS closed-loop AMC uses measured CSI.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.nTxAnt = 2;
cfg.phy.nRxAnt = 2;
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csirs.enable", false);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", 0);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", "ack_nack_olla");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 0.9);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.targetBLER", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMinDb", -10);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMaxDb", 10);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.periodicity", "slot");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.feedbackDelaySlots", 2);
cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 2);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.delayModel", "zero");

cfg = sixgr.util.structSet(cfg, "phy.pdsch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.codeRate", 120/1024);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numLayers", 1);

dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 4, "SNR_dB", 24);
assert(istable(dl.TrialTable) && height(dl.TrialTable) == 4, "DL closed-loop run must produce trial rows.");
assert(all(ismember(["Modulation","TargetCodeRate","LinkAdaptationApplied","LinkAdaptationScheduled","LinkAdaptationDomain","CQISource","MCSSelectionSource", ...
    "LinkAdaptationFeedbackDelaySlots","LinkAdaptationAppliedFeedbackSourceSlot", ...
    "LinkAdaptationAppliedFeedbackAgeSlots","LinkAdaptationScheduledApplySlot", ...
    "AppliedLinkAdaptationResolvedCQI","AppliedLinkAdaptationMCS", ...
    "AppliedLinkAdaptationOLLADeltaDb","AppliedLinkAdaptationOLLAUpdateCount", ...
    "ILLAUpdateScheduled","OLLAFeedbackUpdateScheduled"], ...
    string(dl.TrialTable.Properties.VariableNames))), ...
    "DL closed-loop run must export adaptation state.");
assert(all(string(dl.TrialTable.LinkAdaptationDomain) == "cqi"), ...
    "Default closed-loop DL adaptation must label CQI-space domain explicitly.");
assert(any(dl.TrialTable.LinkAdaptationScheduled), ...
    "DL closed-loop run must schedule at least one adaptation update. " + ...
    localAdaptationTrace(dl.TrialTable));
assert(all(dl.TrialTable.MCS(1:2) == dl.TrialTable.MCS(1)) && ...
    any(dl.TrialTable.MCS(3:end) > dl.TrialTable.MCS(1)), ...
    "DL closed-loop AMC must apply measured feedback only after two slots.");
assert(any(string(dl.TrialTable.Modulation(3:end)) ~= string(dl.TrialTable.Modulation(1))), ...
    "DL closed-loop AMC must update modulation after the configured delay.");
localAssertCausalLoopEvidence(dl.TrialTable, "DL");

cfg = sixgr.util.structSet(cfg, "phy.pusch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pusch.codeRate", 120/1024);
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pusch.numLayers", 1);

ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 4, "SNR_dB", 24);
assert(istable(ul.TrialTable) && height(ul.TrialTable) == 4, "UL closed-loop run must produce trial rows.");
assert(all(logical(ul.TrialTable.AdaptiveMode)) && ...
    all(~logical(ul.TrialTable.FixedAnchorMode)), ...
    "UL truth rows must preserve the same resolved adaptive/fixed-mode classification as DL rows.");
assert(all(string(ul.TrialTable.LinkAdaptationDomain) == "cqi"), ...
    "Default closed-loop UL adaptation must label CQI-space domain explicitly.");
assert(any(ul.TrialTable.LinkAdaptationScheduled), ...
    "UL closed-loop run must schedule at least one adaptation update. " + ...
    localAdaptationTrace(ul.TrialTable));
assert(all(ul.TrialTable.MCS(1:2) == ul.TrialTable.MCS(1)) && ...
    any(ul.TrialTable.MCS(3:end) > ul.TrialTable.MCS(1)), ...
    "UL closed-loop AMC must apply measured feedback only after two slots.");
assert(any(string(ul.TrialTable.Modulation(3:end)) ~= string(ul.TrialTable.Modulation(1))), ...
    "UL closed-loop AMC must update modulation after the configured delay.");
localAssertCausalLoopEvidence(ul.TrialTable, "UL");

cfgNoCQI = sixgr.util.structSet(cfg, "phy.csi.reportCQI", false);

dlNoCQI = sixgr.link.runDLPDSCHThroughput(cfgNoCQI, "NumFrames", 4, "SNR_dB", 24);
assert(all(~isfinite(double(dlNoCQI.TrialTable.WidebandCQI))), ...
    "DL closed-loop AMC must leave CQI unavailable when no measured CQI was reported.");
assert(~any(dlNoCQI.TrialTable.LinkAdaptationScheduled), ...
    "DL closed-loop AMC must not schedule updates from synthesized CQI when measurement-backed CQI is unavailable.");
assert(all(double(dlNoCQI.TrialTable.MCS) == double(dlNoCQI.TrialTable.MCS(1))), ...
    "DL closed-loop AMC must keep MCS fixed when measured CQI is unavailable.");

ulNoCQI = sixgr.link.runULPUSCHThroughput(cfgNoCQI, "NumFrames", 4, "SNR_dB", 24);
assert(all(~isfinite(double(ulNoCQI.TrialTable.WidebandCQI))), ...
    "UL closed-loop AMC must leave CQI unavailable when no measured CQI was reported.");
assert(~any(ulNoCQI.TrialTable.LinkAdaptationScheduled), ...
    "UL closed-loop AMC must not schedule updates from synthesized CQI when measurement-backed CQI is unavailable.");
assert(all(double(ulNoCQI.TrialTable.MCS) == double(ulNoCQI.TrialTable.MCS(1))), ...
    "UL closed-loop AMC must keep MCS fixed when measured CQI is unavailable.");

ok = true;
end

function localAssertCausalLoopEvidence(T, direction)
assert(all(double(T.LinkAdaptationFeedbackDelaySlots) == 2), ...
    "%s rows must preserve the configured feedback delay.", direction);
applied = logical(T.LinkAdaptationApplied);
assert(any(applied) && all(double(T.LinkAdaptationAppliedFeedbackAgeSlots(applied)) == 2), ...
    "%s applied decisions must be exactly two slots old.", direction);
assert(all(double(T.LinkAdaptationAppliedFeedbackSourceSlot(applied)) == ...
    double(T.Slot(applied)) - 2), ...
    "%s applied decisions must identify their exact source slot.", direction);
assert(all(double(T.AppliedLinkAdaptationMCS(applied)) == double(T.MCS(applied))), ...
    "%s applied-decision MCS must equal the transmitted MCS.", direction);
assert(all(isfinite(double(T.AppliedLinkAdaptationResolvedCQI(applied)))), ...
    "%s applied ILLA decisions must retain the delayed receiver CQI.", direction);
assert(any(logical(T.ILLAUpdateScheduled)) && ...
    any(logical(T.OLLAFeedbackUpdateScheduled)), ...
    "%s must separately expose scheduled ILLA and OLLA updates.", direction);
outerApplied = logical(T.OuterLoopApplied);
assert(any(outerApplied) && ...
    all(double(T.AppliedLinkAdaptationOLLAUpdateCount(outerApplied)) >= 1) && ...
    all(isfinite(double(T.AppliedLinkAdaptationOLLADeltaDb(outerApplied)))), ...
    "%s delayed transmissions must carry applied ACK/NACK OLLA state.", direction);
scheduled = logical(T.LinkAdaptationScheduled);
assert(all(double(T.LinkAdaptationScheduledApplySlot(scheduled)) == ...
    double(T.LinkAdaptationScheduledFeedbackSourceSlot(scheduled)) + 2), ...
    "%s scheduled decisions must preserve source-to-apply causality.", direction);
end

function text = localAdaptationTrace(T)
fields = ["Status", "Crash", "TruthStatus", "MCS", "WidebandCQI", "CQISource", "MCSSelectionSource", ...
    "LinkAdaptationApplied", "LinkAdaptationScheduled", "PostEqSINR_dB", ...
    "PostEqSINRSource", "ReceiverUsable", "DecodeAttempted", "DecodeUsable", ...
    "StrictReceiverEvidenceOk", "ChannelEstimateAvailable", "EqualizationAvailable", ...
    "DLSCHDecodeAvailable", "FailureReason", "Notes"];
parts = strings(0, 1);
for name = fields
    if ~ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    value = string(T.(char(name)));
    value(ismissing(value)) = "<missing>";
    parts(end+1, 1) = name + "=[" + join(value(:).', ",") + "]"; %#ok<AGROW>
end
text = join(parts, "; ");
end
