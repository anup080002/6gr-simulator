function info = resolveLinkAdaptationFeedbackDelay(cfg)
%RESOLVELINKADAPTATIONFEEDBACKDELAY Resolve the causal CSI/AMC delay.
%   The numeric YAML-derived feedbackDelaySlots value is authoritative.
%   adaptation.delayModel remains a compatibility surface for direct
%   low-level callers, but it cannot override an explicit numeric delay.

arguments
    cfg (1,1) struct
end

laRaw = sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.feedbackDelaySlots", []);
csiRaw = sixgr.util.structGet(cfg, "phy.csi.feedbackDelaySlots", []);
[laPresent, laValue] = localOptionalDelay(laRaw, ...
    "phy.linkAdaptation.feedbackDelaySlots");
[csiPresent, csiValue] = localOptionalDelay(csiRaw, ...
    "phy.csi.feedbackDelaySlots");

if laPresent && csiPresent && laValue ~= csiValue
    error("sixgr:link:FeedbackDelayAuthorityMismatch", ...
        ["The resolved numeric feedback-delay aliases disagree: " + ...
        "phy.linkAdaptation.feedbackDelaySlots=%d and " + ...
        "phy.csi.feedbackDelaySlots=%d."], laValue, csiValue);
end

if laPresent || csiPresent
    if laPresent && csiPresent
        source = "phy.linkAdaptation.feedbackDelaySlots=phy.csi.feedbackDelaySlots";
        value = laValue;
    elseif laPresent
        source = "phy.linkAdaptation.feedbackDelaySlots";
        value = laValue;
    else
        source = "phy.csi.feedbackDelaySlots";
        value = csiValue;
    end
    info = localInfo(value, value, source, false, "numeric_yaml_authority");
    return;
end

legacyRaw = sixgr.util.structGet(cfg, ...
    "phy.linkAdaptation.delayModel", "baseline");
[requested, parsed] = localLegacyDelay(legacyRaw);
if ~parsed
    error("sixgr:link:InvalidLegacyFeedbackDelayModel", ...
        "Unsupported phy.linkAdaptation.delayModel value '%s'.", ...
        char(string(legacyRaw)));
end

% The decision is produced after a transport block is decoded, so it
% cannot affect that same transport block. A legacy zero-delay token is
% therefore one scheduled-TTI old in the actual before/after loop.
effective = max(1, requested);
coerced = requested < 1;
if coerced
    status = "legacy_zero_delay_coerced_to_causal_minimum";
else
    status = "legacy_delay_model_compatibility";
end
info = localInfo(effective, requested, ...
    "phy.linkAdaptation.delayModel", coerced, status);
end

function [present, value] = localOptionalDelay(raw, path)
present = ~isempty(raw);
value = NaN;
if ~present
    return;
end
if ~(isnumeric(raw) && isscalar(raw) && isfinite(double(raw)) && ...
        double(raw) >= 1 && double(raw) <= 1024 && ...
        double(raw) == fix(double(raw)))
    error("sixgr:link:InvalidFeedbackDelaySlots", ...
        "%s must be an integer in [1,1024].", char(path));
end
value = double(raw);
end

function [value, parsed] = localLegacyDelay(raw)
parsed = true;
if isnumeric(raw) && isscalar(raw) && isfinite(double(raw))
    value = round(double(raw));
    parsed = value >= 0 && value <= 1024 && value == double(raw);
    return;
end
token = lower(strtrim(string(raw)));
if token == "" || ismember(token, ["baseline","slot","frame","per_slot","per_frame"])
    value = 1;
    return;
end
if ismember(token, ["none","zero","immediate","same_frame"])
    value = 0;
    return;
end
match = regexp(char(token), '(\d+)', 'tokens', 'once');
if isempty(match)
    value = NaN;
    parsed = false;
else
    value = str2double(match{1});
    parsed = isfinite(value) && value >= 0 && value <= 1024;
end
end

function info = localInfo(effective, requested, source, coerced, status)
info = struct( ...
    "FeedbackDelaySlots", double(effective), ...
    "RequestedFeedbackDelaySlots", double(requested), ...
    "Source", char(source), ...
    "LegacyDelayCoerced", logical(coerced), ...
    "Status", char(status));
end
