function [decision, adaptationState] = computeLinkAdaptationDecision(cfg, direction, metrics, varargin)
%COMPUTELINKADAPTATIONDECISION Build the next closed-loop LLS adaptation decision.

ip = inputParser;
ip.addParameter("AdaptationState", struct(), @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

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
adaptationState = localInitAdaptationState(cfg, direction, opt.AdaptationState);
[ackKnown, ackObserved, ackSource] = localResolveAckOutcome(metrics);
[instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable] = localResolveInstantaneousAMC(cfg, direction, metrics);
[resetState, resetReason] = localShouldResetState(adaptationState, metrics, cfg);

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
    "CSIPayloadHex", char(string(sixgr.util.structGet(metrics, "CSIPayloadHex", ""))), ...
    "CQITable", char(cqiTable), ...
    "MCSTable", char(mcsTable), ...
    "InstantaneousCQIMCS", double(instantMCS), ...
    "InstantaneousCQIModulation", char(instantMod), ...
    "InstantaneousCQITargetCodeRate", double(instantCodeRate), ...
    "CQISmoothingAlpha", double(adaptationState.CQISmoothingAlpha), ...
    "CQIBasedMCS", double(adaptationState.CQIBasedMCS), ...
    "DeltaMCS", double(adaptationState.DeltaMCS), ...
    "StaticDeltaMCS", double(adaptationState.StaticDeltaMCS), ...
    "OuterLoopEnabled", logical(adaptationState.OuterLoopEnabled), ...
    "InnerLoopEnabled", logical(adaptationState.InnerLoopEnabled), ...
    "AckObserved", logical(ackObserved), ...
    "AckObservedValid", logical(ackKnown), ...
    "AckObservedSource", char(ackSource), ...
    "StateReset", logical(resetState), ...
    "StateResetReason", char(resetReason), ...
    "StateInitialized", logical(adaptationState.Initialized), ...
    "StateUpdateCount", double(adaptationState.UpdateCount));

if ~decision.Enabled
    decision.Reason = "link_adaptation_disabled";
    return;
end

if localPolicyEnabled(policy)
    [decision, adaptationState] = localResolveMCSDecision(decision, adaptationState, cfg, direction, metrics, ...
        instantMCS, instantMod, instantCodeRate, mcsTable, ackKnown, ackObserved, resetState, resetReason, deltaMCSPolicy);
    if ~decision.MCSUpdated && ~(isfinite(decision.CQIBasedMCS) || adaptationState.Initialized)
        decision.Reason = "missing_cqi";
        return;
    end
end

if localPolicyEnabled(rankPolicy)
    ri = decision.RI;
    if isfinite(ri)
        maxLayers = localMaxLayers(cfg, direction);
        requestedLayers = max(1, min(maxLayers, round(ri)));
        if abs(requestedLayers - decision.NumLayers) > 1e-9
            decision.NumLayers = requestedLayers;
            decision.RankUpdated = true;
        end
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

decision.Valid = logical(decision.MCSUpdated || decision.RankUpdated || decision.PMIUpdated || decision.CRIUpdated);
if decision.Valid
    decision.Reason = "adaptation_scheduled";
else
    if strlength(decision.Reason) == 0
        decision.Reason = "no_change";
    end
end
end

function [decision, adaptationState] = localResolveMCSDecision(decision, adaptationState, cfg, direction, metrics, instantMCS, instantMod, instantCodeRate, mcsTable, ackKnown, ackObserved, resetState, resetReason, deltaMCSPolicy)
previousMCS = double(decision.MCSIndex);
previousCodeRate = double(decision.TargetCodeRate);
previousModulation = char(string(decision.Modulation));
if isfinite(instantMCS)
    if resetState || ~adaptationState.Initialized || ~isfinite(adaptationState.CQIBasedMCS)
        cqiBasedMCS = double(instantMCS);
    elseif logical(adaptationState.InnerLoopEnabled)
        alpha = min(max(double(adaptationState.CQISmoothingAlpha), 0), 1);
        cqiBasedMCS = alpha * double(instantMCS) + (1 - alpha) * double(adaptationState.CQIBasedMCS);
    else
        cqiBasedMCS = double(instantMCS);
    end
    adaptationState.CQIBasedMCS = double(cqiBasedMCS);
    adaptationState.LastInstantaneousMCS = double(instantMCS);
    adaptationState.LastInstantaneousModulation = char(instantMod);
    adaptationState.LastInstantaneousTargetCodeRate = double(instantCodeRate);
elseif adaptationState.Initialized && isfinite(adaptationState.CQIBasedMCS)
    cqiBasedMCS = double(adaptationState.CQIBasedMCS);
else
    decision.Reason = "missing_cqi";
    return;
end

if resetState
    adaptationState.DeltaMCS = 0;
    adaptationState.LastResetReason = char(resetReason);
end

if adaptationState.OuterLoopEnabled && localDeltaPolicyEnabled(deltaMCSPolicy, cfg)
    if ackKnown
        if ackObserved
            adaptationState.DeltaMCS = min(adaptationState.DeltaMCSMax, adaptationState.DeltaMCS + adaptationState.OLLAStepUp);
        else
            adaptationState.DeltaMCS = max(adaptationState.DeltaMCSMin, adaptationState.DeltaMCS - adaptationState.OLLAStepDown);
        end
        adaptationState.LastObservedAck = logical(ackObserved);
    end
end

dynamicMCS = double(cqiBasedMCS) + double(adaptationState.DeltaMCS) + double(adaptationState.StaticDeltaMCS);
dynamicMCS = max(0, min(31, dynamicMCS));
selectedMCS = round(dynamicMCS);
profile = sixgr.link.resolveMCSProfile(mcsTable, selectedMCS);
if ~logical(sixgr.util.structGet(profile, "Valid", false))
    decision.Reason = "invalid_mcs_profile";
    return;
end

decision.CQIBasedMCS = double(cqiBasedMCS);
decision.DeltaMCS = double(adaptationState.DeltaMCS);
decision.StaticDeltaMCS = double(adaptationState.StaticDeltaMCS);
decision.Modulation = char(string(profile.Modulation));
decision.TargetCodeRate = double(profile.TargetCodeRate);
decision.MCSIndex = double(selectedMCS);
decision.MCSUpdated = resetState || ...
    ~(isfinite(previousMCS) && abs(previousMCS - double(selectedMCS)) <= 1e-9 && ...
    isfinite(previousCodeRate) && abs(previousCodeRate - double(profile.TargetCodeRate)) <= 1e-12 && ...
    strcmpi(previousModulation, char(string(profile.Modulation))));
decision.StateReset = logical(resetState);
decision.StateResetReason = char(resetReason);
decision.OuterLoopEnabled = logical(adaptationState.OuterLoopEnabled);
decision.InnerLoopEnabled = logical(adaptationState.InnerLoopEnabled);
decision.StateInitialized = true;
decision.StateUpdateCount = double(adaptationState.UpdateCount + 1);

adaptationState.Initialized = true;
adaptationState.LastCQI = double(decision.CQI);
adaptationState.LastRI = double(decision.RI);
adaptationState.LastMCSIndex = double(selectedMCS);
adaptationState.UpdateCount = adaptationState.UpdateCount + 1;
end

function tf = localDeltaPolicyEnabled(token, cfg)
token = lower(string(token));
outerLoopFlag = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", false));
tf = outerLoopFlag || ~(token == "" || ismember(token, ["disabled", "none", "off", "false"]));
end

function [instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable] = localResolveInstantaneousAMC(cfg, direction, metrics)
mcsTable = sixgr.link.resolveConfiguredMCSTable(cfg, direction);
cqiTable = sixgr.link.resolveConfiguredCQITable(cfg, direction);
instantMCS = NaN;
instantMod = "";
instantCodeRate = NaN;
cqi = double(sixgr.util.structGet(metrics, "CQI", NaN));
if ~(isfinite(cqi))
    return;
end
[instantMod, instantCodeRate, instantMCS] = sixgr.link.amcFromCQI(cqi, "", NaN, cfg, direction);
end

function [ackKnown, ackObserved, source] = localResolveAckOutcome(metrics)
ackKnown = false;
ackObserved = false;
source = "";
candidates = { ...
    "AckObserved"
    "ObservedAck"
    "CombinedDecodeOK"
    "CurrentDecodeOK"
    "CRCPass"};
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(metrics, candidates{i}, []);
    if isempty(raw)
        continue;
    end
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            ackKnown = true;
            ackObserved = logical(raw);
            source = candidates{i};
            return;
        end
    end
end
end

function [resetState, resetReason] = localShouldResetState(adaptationState, metrics, cfg)
resetState = false;
resetReason = "";
if ~adaptationState.Initialized
    return;
end

ri = double(sixgr.util.structGet(metrics, "RI", NaN));
if logical(adaptationState.ResetOnRIChange) && isfinite(ri) && isfinite(adaptationState.LastRI) && round(ri) ~= round(adaptationState.LastRI)
    resetState = true;
    resetReason = "ri_change";
    return;
end

cqi = double(sixgr.util.structGet(metrics, "CQI", NaN));
jumpThreshold = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", adaptationState.CQIJumpResetThreshold));
if ~(isfinite(jumpThreshold) && jumpThreshold >= 1)
    jumpThreshold = adaptationState.CQIJumpResetThreshold;
end
if isfinite(cqi) && isfinite(adaptationState.LastCQI) && abs(cqi - adaptationState.LastCQI) >= jumpThreshold
    resetState = true;
    resetReason = "cqi_jump";
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

function adaptationState = localInitAdaptationState(cfg, direction, previousState)
adaptationState = struct( ...
    "Direction", char(direction), ...
    "Initialized", false, ...
    "InnerLoopEnabled", logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.innerLoopFlag", true)), ...
    "OuterLoopEnabled", logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", true)), ...
    "CQISmoothingAlpha", localResolveCQISmoothingAlpha(cfg), ...
    "CQIBasedMCS", NaN, ...
    "DeltaMCS", 0, ...
    "StaticDeltaMCS", localResolveStaticDeltaMCS(cfg), ...
    "OLLAStepUp", localResolveOLLAStep(cfg, "up"), ...
    "OLLAStepDown", localResolveOLLAStep(cfg, "down"), ...
    "DeltaMCSMin", localResolveDeltaBound(cfg, "min"), ...
    "DeltaMCSMax", localResolveDeltaBound(cfg, "max"), ...
    "ResetOnRIChange", logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.resetOnRIChange", true)), ...
    "CQIJumpResetThreshold", localResolveCQIJumpResetThreshold(cfg), ...
    "LastCQI", NaN, ...
    "LastRI", NaN, ...
    "LastMCSIndex", NaN, ...
    "LastInstantaneousMCS", NaN, ...
    "LastInstantaneousModulation", "", ...
    "LastInstantaneousTargetCodeRate", NaN, ...
    "LastObservedAck", false, ...
    "LastResetReason", "", ...
    "UpdateCount", 0);

if isempty(previousState) || ~isstruct(previousState)
    return;
end
prevFields = fieldnames(previousState);
for i = 1:numel(prevFields)
    adaptationState.(prevFields{i}) = previousState.(prevFields{i});
end
end

function alpha = localResolveCQISmoothingAlpha(cfg)
alpha = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", NaN));
if ~(isfinite(alpha) && alpha >= 0 && alpha <= 1)
    alpha = 0.2;
end
end

function delta = localResolveStaticDeltaMCS(cfg)
delta = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSOffset", 0));
if ~(isfinite(delta))
    delta = 0;
end
end

function value = localResolveOLLAStep(cfg, stepDirection)
if nargin < 2
    stepDirection = "down";
end
stepDirection = lower(string(stepDirection));
if stepDirection == "up"
    candidates = [ ...
        "phy.linkAdaptation.ollaStepUp"
        "phy.linkAdaptation.stepUpMCS"];
else
    candidates = [ ...
        "phy.linkAdaptation.ollaStepDown"
        "phy.linkAdaptation.stepDownMCS"];
end
value = NaN;
for i = 1:numel(candidates)
    raw = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    if isfinite(raw) && raw > 0
        value = raw;
        break;
    end
end
if isfinite(value) && value > 0
    return;
end
targetBLER = double(sixgr.util.structGet(cfg, "phy.csi.targetBLER", ...
    sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", sixgr.util.structGet(cfg, "phy.pusch.targetBLER", 0.1))));
if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
    targetBLER = 0.1;
end
if stepDirection == "up"
    value = targetBLER / max(1 - targetBLER, eps);
else
    value = 1.0;
end
end

function value = localResolveDeltaBound(cfg, boundDirection)
if nargin < 2
    boundDirection = "max";
end
boundDirection = lower(string(boundDirection));
if boundDirection == "min"
    value = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSMin", -6));
else
    value = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSMax", 6));
end
if ~isfinite(value)
    if boundDirection == "min"
        value = -6;
    else
        value = 6;
    end
end
end

function threshold = localResolveCQIJumpResetThreshold(cfg)
threshold = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 4));
if ~(isfinite(threshold) && threshold >= 1)
    threshold = 4;
end
end
