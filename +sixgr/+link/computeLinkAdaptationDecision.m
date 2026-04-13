function decision = computeLinkAdaptationDecision(cfg, direction, metrics)
%COMPUTELINKADAPTATIONDECISION Build the next closed-loop LLS adaptation decision.

direction = upper(string(direction));
if direction ~= "DL" && direction ~= "UL"
    error("sixgr:link:LinkAdaptation:BadDirection", ...
        "Direction must be 'DL' or 'UL'.");
end

if nargin < 3 || isempty(metrics)
    metrics = struct();
end

mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
policyPath = localPolicyPath(direction);
policy = lower(string(sixgr.util.structGet(cfg, policyPath, "fixed")));
rankPolicy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", "fixed")));
beamPolicy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.beamPolicy", "fixed")));
deltaMCSPolicy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSPolicy", "none")));

base = localBaseState(cfg, direction);
decision = struct( ...
    "Enabled", localPolicyEnabled(mode) && (localPolicyEnabled(policy) || localPolicyEnabled(rankPolicy) || localPolicyEnabled(beamPolicy)), ...
    "Direction", char(direction), ...
    "Mode", char(mode), ...
    "Policy", char(policy), ...
    "RankPolicy", char(rankPolicy), ...
    "BeamPolicy", char(beamPolicy), ...
    "Valid", false, ...
    "Reason", "", ...
    "CQI", double(sixgr.util.structGet(metrics, "CQI", NaN)), ...
    "RI", double(sixgr.util.structGet(metrics, "RI", NaN)), ...
    "PMI", double(sixgr.util.structGet(metrics, "PMI", NaN)), ...
    "CRI", double(sixgr.util.structGet(metrics, "CRI", NaN)), ...
    "MeasuredSINR_dB", double(sixgr.util.structGet(metrics, "SINR_dB", NaN)), ...
    "MCSIndex", base.MCSIndex, ...
    "Modulation", char(base.Modulation), ...
    "TargetCodeRate", double(base.TargetCodeRate), ...
    "NumLayers", double(base.NumLayers), ...
    "PMIUpdated", false, ...
    "CRIUpdated", false, ...
    "RankUpdated", false, ...
    "MCSUpdated", false, ...
    "PMIType", char(string(sixgr.util.structGet(metrics, "PMIType", ""))), ...
    "PMICodebookMode", char(string(sixgr.util.structGet(metrics, "PMICodebookMode", ""))), ...
    "CSIReportMode", char(string(sixgr.util.structGet(metrics, "CSIReportMode", ""))), ...
    "CSIPayloadBitLength", double(sixgr.util.structGet(metrics, "CSIPayloadBitLength", NaN)), ...
    "CSIPayloadHex", char(string(sixgr.util.structGet(metrics, "CSIPayloadHex", ""))));

if ~decision.Enabled
    decision.Reason = "link_adaptation_disabled";
    return;
end

if localPolicyEnabled(policy)
    cqi = decision.CQI;
    if ~isfinite(cqi)
        decision.Reason = "missing_cqi";
        return;
    end
    [modStr, targetCodeRate, mcsIdx] = sixgr.link.amcFromCQI(cqi, "", NaN, cfg, direction);
    if deltaMCSPolicy ~= "none" && deltaMCSPolicy ~= "disabled" && deltaMCSPolicy ~= "off"
        deltaMCS = round(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSOffset", 0)));
        mcsIdx = max(0, min(31, mcsIdx + deltaMCS));
    end
    decision.Modulation = char(modStr);
    decision.TargetCodeRate = double(targetCodeRate);
    decision.MCSIndex = double(mcsIdx);
    decision.MCSUpdated = true;
end

if localPolicyEnabled(rankPolicy)
    ri = decision.RI;
    if isfinite(ri)
        maxLayers = localMaxLayers(cfg, direction);
        decision.NumLayers = max(1, min(maxLayers, round(ri)));
        decision.RankUpdated = true;
    end
end

if direction == "DL" && localPolicyEnabled(beamPolicy)
    pmi = decision.PMI;
    if isfinite(pmi)
        decision.PMI = round(pmi);
        decision.PMIUpdated = true;
    end
    cri = decision.CRI;
    if isfinite(cri)
        decision.CRI = round(cri);
        decision.CRIUpdated = true;
    end
end

decision.Valid = decision.MCSUpdated || decision.RankUpdated || decision.PMIUpdated || decision.CRIUpdated;
if decision.Valid
    decision.Reason = "adaptation_scheduled";
else
    decision.Reason = "no_change";
end
end

function tf = localPolicyEnabled(token)
token = lower(string(token));
tf = ~(token == "" || ismember(token, ["disabled","none","off","false","fixed"]));
end

function path = localPolicyPath(direction)
if direction == "DL"
    path = "phy.linkAdaptation.dlPolicy";
else
    path = "phy.linkAdaptation.ulPolicy";
end
end

function base = localBaseState(cfg, direction)
if direction == "DL"
    base.Modulation = char(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "QPSK")));
    base.TargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pdsch.codeRate", 0.5));
    base.NumLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
    base.MCSIndex = double(sixgr.util.structGet(cfg, "phy.pdsch.mcsIndex", ...
        sixgr.l2.mac.SchedulerBase.approxMCSIndex(base.Modulation, base.TargetCodeRate, NaN, ...
        sixgr.link.resolveConfiguredMCSTable(cfg, "DL"))));
else
    base.Modulation = char(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", "QPSK")));
    base.TargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pusch.codeRate", 0.5));
    base.NumLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
    base.MCSIndex = double(sixgr.util.structGet(cfg, "phy.pusch.mcsIndex", ...
        sixgr.l2.mac.SchedulerBase.approxMCSIndex(base.Modulation, base.TargetCodeRate, NaN, ...
        sixgr.link.resolveConfiguredMCSTable(cfg, "UL"))));
end
end

function maxLayers = localMaxLayers(cfg, direction)
if direction == "DL"
    maxLayers = double(sixgr.util.structGet(cfg, "phy.nTxAnt", ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1))));
else
    maxLayers = double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", sixgr.util.structGet(cfg, "phy.nTxAnt", 1))));
end
maxLayers = max(1, round(maxLayers));
end
