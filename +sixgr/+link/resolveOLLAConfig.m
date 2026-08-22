function policy = resolveOLLAConfig(cfg)
%RESOLVEOLLACONFIG Resolve one canonical dB-domain OLLA policy from config.

arguments
    cfg (1,1) struct
end

mode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.mode", "fixed"))));
dlPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.dlPolicy", ""))));
ulPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.ulPolicy", ""))));
deltaPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.deltaMCSPolicy", ""))));
outerFlag = logical(sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.outerLoopFlag", false));
standaloneAdaptationEnabled = logical(sixgr.util.structGet(cfg, ...
    "linkAdaptation.enabled", false));
standaloneOLLAEnabled = logical(sixgr.util.structGet(cfg, ...
    "linkAdaptation.olla.enabled", false));
outerFlag = logical(outerFlag || standaloneOLLAEnabled);

fixedTokens = ["fixed","fixed_mcs","configured_fixed", ...
    "disabled","off","none","false",""];
policyUnspecified = strlength(dlPolicy) == 0 && strlength(ulPolicy) == 0;
adaptationEnabled = ~ismember(mode, fixedTokens) && ...
    (policyUnspecified || ~ismember(dlPolicy, fixedTokens) || ...
    ~ismember(ulPolicy, fixedTokens));
adaptationEnabled = logical(adaptationEnabled || standaloneAdaptationEnabled);
if any(deltaPolicy == ["","baseline","default","auto"]) && ...
        outerFlag && adaptationEnabled
    deltaPolicy = "ack_nack_olla";
end

stepDown = localFirstPositive(cfg, [ ...
    "phy.linkAdaptation.ollaStepDown"
    "phy.linkAdaptation.olla_step_down_db"
    "link_adaptation.olla_step_down_db"
    "linkAdaptation.olla.nackStepDb"
    "phy.linkAdaptation.stepDownMCS"], 1.0);
stepUp = localFirstPositive(cfg, [ ...
    "phy.linkAdaptation.ollaStepUp"
    "phy.linkAdaptation.olla_step_up_db"
    "link_adaptation.olla_step_up_db"
    "linkAdaptation.olla.ackStepDb"
    "phy.linkAdaptation.stepUpMCS"], NaN);
if ~(isfinite(stepUp) && stepUp > 0)
    ackNackRatio = double(sixgr.util.structGet(cfg, ...
        "phy.linkAdaptation.ackNackTDDPatternRatio", 1));
    if ~(isfinite(ackNackRatio) && ackNackRatio > 0)
        ackNackRatio = 1;
    end
    stepUp = (stepDown * ackNackRatio) / 10;
end

minimum = localFirstFinite(cfg, [ ...
    "phy.linkAdaptation.ollaMarginMinDb"
    "phy.linkAdaptation.olla_margin_min_db"
    "link_adaptation.olla_margin_min_db"
    "linkAdaptation.olla.minimumOffsetDb"
    "phy.linkAdaptation.deltaMCSMin"], -10);
maximum = localFirstFinite(cfg, [ ...
    "phy.linkAdaptation.ollaMarginMaxDb"
    "phy.linkAdaptation.olla_margin_max_db"
    "link_adaptation.olla_margin_max_db"
    "linkAdaptation.olla.maximumOffsetDb"
    "phy.linkAdaptation.deltaMCSMax"], 10);
if minimum > maximum
    error("sixgr:link:InvalidOLLAMarginBounds", ...
        "OLLA minimum margin %.6g dB exceeds maximum margin %.6g dB.", ...
        minimum, maximum);
end

targetBLER = stepUp / (stepUp + stepDown);
configuredTarget = localFirstFinite(cfg, [ ...
    "phy.linkAdaptation.targetBLER"
    "phy.linkAdaptation.ollaTargetBLER"
    "link_adaptation.olla_target_bler"
    "linkAdaptation.olla.targetBLER"], NaN);
ollaEnabled = logical(outerFlag && adaptationEnabled && ...
    any(deltaPolicy == ["olla","outer_loop","outerloop", ...
    "ack_nack","ack_nack_olla"]));
if ollaEnabled && isfinite(configuredTarget) && ...
        abs(double(configuredTarget) - double(targetBLER)) > 1e-12
    error("sixgr:link:OLLATargetBLERStepMismatch", ...
        ['Configured OLLA target BLER %.12g is inconsistent with the ' ...
        'ACK/NACK step-implied target %.12g. For ACK=+stepUp and ' ...
        'NACK=-stepDown, targetBLER must equal stepUp/(stepUp+stepDown).'], ...
        configuredTarget, targetBLER);
end

policy = struct( ...
    "Enabled", logical(ollaEnabled), ...
    "OuterLoopFlag", logical(outerFlag), ...
    "AdaptationEnabled", logical(adaptationEnabled), ...
    "Policy", char(deltaPolicy), ...
    "StepUpDb", double(stepUp), ...
    "StepDownDb", double(stepDown), ...
    "MinimumOffsetDb", double(minimum), ...
    "MaximumOffsetDb", double(maximum), ...
    "ImpliedTargetBLER", double(targetBLER), ...
    "ConfiguredTargetBLER", double(configuredTarget), ...
    "StateAuthority", "receiver_harq_feedback_state");
end

function value = localFirstPositive(cfg, paths, defaultValue)
value = localFirstFinite(cfg, paths, defaultValue);
if ~(isfinite(value) && value > 0)
    value = defaultValue;
end
end

function value = localFirstFinite(cfg, paths, defaultValue)
value = defaultValue;
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(raw)
        continue;
    end
    try
        candidate = double(raw);
    catch
        continue;
    end
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = double(candidate(1));
        return;
    end
end
end
