function ok = testLLSLinkAdaptationRadisysMCSLoop(decisionFcn)
% Preserve legacy ILLA smoothing without misusing the shared dB OLLA state.
if nargin < 1
    decisionFcn = @sixgr.link.computeLinkAdaptationDecision;
end

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.domain", "legacy_mcs");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", "olla");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", 0.2);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnMCSJump", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mcsJumpResetThreshold", 5);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 2.0);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 1.0);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", -10);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", 10);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", "qam64_table1");
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");

[d1, s1] = decisionFcn(cfg, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", false));
assert(logical(d1.Valid) && double(d1.CQIBasedMCS) == 22, ...
    "First CQI report must initialize cqiBasedMCS directly from the CQI-to-MCS map.");
assert(double(d1.DeltaMCS) == -1, ...
    "A NACK must decrement deltaMCS before final MCS selection.");

[d2, s2] = decisionFcn(cfg, "DL", ...
    struct("CQI", 13, "RI", 1, "CombinedDecodeOK", true), "AdaptationState", s1);
assert(abs(double(d2.CQIBasedMCS) - 22.4) < 1e-12, ...
    "MCS-domain inner loop must smooth in hundredth-MCS precision.");
[thresholds, ~] = sixgr.link.mcsRequiredSINRTable( ...
    'qam64_table1','table1','DL','Config',cfg);
targetSINR = thresholds(round(d2.CQIBasedMCS)+1) + d2.OLLADeltaDb;
expectedMCS = find(isfinite(thresholds) & thresholds <= targetSINR+1e-12,1,'last')-1;
expectedMCS = min(expectedMCS,d2.InstantaneousCQIMCS);
assert(double(d2.MCSIndex) == expectedMCS && ...
    string(d2.OLLADomain) == "delta_db_required_sinr_margin", ...
    "Legacy ILLA smoothing must still apply shared OLLA through required-SINR thresholds.");

[d3, s3] = decisionFcn(cfg, "DL", ...
    struct("CQI", 5, "RI", 1, "CombinedDecodeOK", true), "AdaptationState", s2);
assert(logical(d3.StateReset) && string(d3.StateResetReason) == "mcs_jump", ...
    "A CQI-to-MCS jump greater than five steps must reset deltaMCS.");
assert(double(s3.DeltaMCS) == double(d3.DeltaMCS), ...
    "The persisted state must expose the post-reset deltaMCS value.");

ok = true;
end
