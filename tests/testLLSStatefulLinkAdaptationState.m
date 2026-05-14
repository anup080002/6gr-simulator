function ok = testLLSStatefulLinkAdaptationState()
%TESTLLSSTATEFULLINKADAPTATIONSTATE Verify stateful CQI smoothing and OLLA updates.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", 0.2);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", "olla");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 0.2);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 0.6);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", -6);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", 6);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnRIChange", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 4);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.codeRate", 0.12);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 0);

[decision1, state1] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", true));
assert(logical(decision1.Valid) && decision1.MCSIndex > 0, ...
    "First stateful decision must initialize a nonzero MCS from CQI.");
assert(string(decision1.LinkAdaptationDomain) == "cqi", ...
    "Default stateful AMC must operate in explicit CQI-space.");
assert(logical(state1.Initialized) && isfinite(state1.CQIBasedMCS), ...
    "Stateful link adaptation must persist the CQI-based MCS state.");
assert(isfinite(state1.SmoothedCQI), ...
    "CQI-domain stateful adaptation must persist smoothed CQI state.");

[decision2, state2] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", false), "AdaptationState", state1);
assert(decision2.DeltaMCS < decision1.DeltaMCS, ...
    "A NACK must reduce the OLLA deltaMCS state.");
assert(logical(state2.Initialized), ...
    "State must remain initialized after follow-up observations.");

[decision3, state3] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", ...
    struct("CQI", 12, "RI", 2, "CombinedDecodeOK", true), "AdaptationState", state2);
assert(logical(decision3.StateReset) && strcmpi(string(decision3.StateResetReason), "ri_change"), ...
    "RI changes must reset the vendor-style adaptation state.");
assert(isfinite(state3.CQIBasedMCS), ...
    "Resetting on RI change must rebuild a finite CQI-based MCS state.");

ok = true;
end
