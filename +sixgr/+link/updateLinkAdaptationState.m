function [cfgOut, state, event] = updateLinkAdaptationState(cfgIn, state, direction, frameIdx, varargin)
%UPDATELINKADAPTATIONSTATE Manage apply/schedule phases for LLS link adaptation.

ip = inputParser;
ip.addParameter("Phase", "before", @(x) ischar(x) || isstring(x));
ip.addParameter("Metrics", struct(), @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

phase = lower(string(opt.Phase));
direction = upper(string(direction));
if isempty(state) || ~isstruct(state) || isempty(fieldnames(state)) || ...
        ~isfield(state, "Enabled")
    state = localInitState(cfgIn, direction);
end
if ~isfield(state, "CurrentConfig") || isempty(state.CurrentConfig)
    state.CurrentConfig = cfgIn;
end
state = localUpgradeState(state, cfgIn);

cfgOut = state.CurrentConfig;
event = struct( ...
    "Applied", false, ...
    "Scheduled", false, ...
    "Frame", double(frameIdx), ...
    "Slot", double(frameIdx), ...
    "ApplyFrame", NaN, ...
    "ApplySlot", NaN, ...
    "FeedbackSourceSlot", NaN, ...
    "FeedbackAgeSlots", NaN, ...
    "ConfiguredFeedbackDelaySlots", double(state.DelaySlots), ...
    "RequestedFeedbackDelaySlots", double(state.RequestedDelaySlots), ...
    "FeedbackDelaySource", char(state.DelaySource), ...
    "FeedbackDelayStatus", char(state.DelayStatus), ...
    "Direction", char(direction), ...
    "Decision", struct(), ...
    "Reason", "");

switch phase
    case "before"
        if ~state.Enabled
            event.Reason = "link_adaptation_disabled";
            cfgOut = state.CurrentConfig;
            return;
        end
        if ~isempty(state.Pending)
            applyIdx = find([state.Pending.ApplyFrame] <= double(frameIdx), 1, "last");
            if ~isempty(applyIdx)
                pendingDecision = state.Pending(applyIdx);
                decision = pendingDecision.Decision;
                state.Pending(1:applyIdx) = [];
                state.CurrentConfig = sixgr.link.applyLinkAdaptationDecision(state.CurrentConfig, direction, decision);
                state.LastAppliedFrame = double(frameIdx);
                cfgOut = state.CurrentConfig;
                event.Applied = true;
                event.ApplyFrame = double(frameIdx);
                event.ApplySlot = double(frameIdx);
                event.FeedbackSourceSlot = double(pendingDecision.SourceSlot);
                event.FeedbackAgeSlots = double(frameIdx) - double(pendingDecision.SourceSlot);
                event.Decision = decision;
                event.Reason = "decision_applied";
                return;
            end
        end
        cfgOut = state.CurrentConfig;
        event.Reason = "no_pending_decision";
    case "after"
        if ~state.Enabled
            event.Reason = "link_adaptation_disabled";
            cfgOut = state.CurrentConfig;
            return;
        end
        if ~localFrameEligible(frameIdx, state.PeriodFrames)
            event.Reason = "periodicity_hold";
            cfgOut = state.CurrentConfig;
            return;
        end
        [decision, runtimeState] = sixgr.link.computeLinkAdaptationDecision(state.CurrentConfig, direction, opt.Metrics, ...
            "AdaptationState", sixgr.util.structGet(state, "RuntimeDecisionState", struct()));
        state.RuntimeDecisionState = runtimeState;
        if ~logical(sixgr.util.structGet(decision, "Valid", false))
            event.Decision = decision;
            event.Reason = char(string(sixgr.util.structGet(decision, "Reason", "no_valid_decision")));
            cfgOut = state.CurrentConfig;
            return;
        end
        applyFrame = double(frameIdx) + double(state.DelaySlots);
        decision.FeedbackSourceSlot = double(frameIdx);
        decision.ScheduledApplySlot = double(applyFrame);
        decision.ConfiguredFeedbackDelaySlots = double(state.DelaySlots);
        decision.FeedbackDelaySource = char(state.DelaySource);
        state.Pending(end+1,1) = struct( ...
            "ApplyFrame", applyFrame, ...
            "SourceSlot", double(frameIdx), ...
            "Decision", decision); %#ok<AGROW>
        state.LastObservedFrame = double(frameIdx);
        cfgOut = state.CurrentConfig;
        event.Scheduled = true;
        event.ApplyFrame = applyFrame;
        event.ApplySlot = applyFrame;
        event.FeedbackSourceSlot = double(frameIdx);
        event.FeedbackAgeSlots = 0;
        event.Decision = decision;
        event.Reason = "decision_scheduled";
    otherwise
        error("sixgr:link:LinkAdaptation:BadPhase", ...
            "Phase must be 'before' or 'after'.");
end
end

function state = localInitState(cfg, direction)
state = struct();
state.Direction = char(direction);
mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
state.Enabled = localModeEnabled(mode);
state.PeriodFrames = localParseFrameCount(sixgr.util.structGet(cfg, "phy.linkAdaptation.periodicity", "slot"), 1);
delay = sixgr.link.resolveLinkAdaptationFeedbackDelay(cfg);
state.DelaySlots = double(delay.FeedbackDelaySlots);
state.DelayFrames = double(delay.FeedbackDelaySlots); % compatibility alias
state.RequestedDelaySlots = double(delay.RequestedFeedbackDelaySlots);
state.DelaySource = char(delay.Source);
state.DelayStatus = char(delay.Status);
state.Pending = repmat(struct("ApplyFrame", NaN, "SourceSlot", NaN, "Decision", struct()), 0, 1);
state.LastObservedFrame = 0;
state.LastAppliedFrame = 0;
state.CurrentConfig = cfg;
state.RuntimeDecisionState = struct();
end

function state = localUpgradeState(state, cfg)
% Preserve resumable state created by an older schema while making delay
% authority explicit. This does not reset accumulated ILLA/OLLA state.
if ~isfield(state, "DelaySlots") || ...
        ~(isscalar(state.DelaySlots) && isfinite(double(state.DelaySlots)))
    delay = sixgr.link.resolveLinkAdaptationFeedbackDelay(cfg);
    state.DelaySlots = double(delay.FeedbackDelaySlots);
    state.DelayFrames = double(delay.FeedbackDelaySlots);
    state.RequestedDelaySlots = double(delay.RequestedFeedbackDelaySlots);
    state.DelaySource = char(delay.Source);
    state.DelayStatus = char(delay.Status);
end
if ~isfield(state, "RequestedDelaySlots")
    state.RequestedDelaySlots = double(state.DelaySlots);
end
if ~isfield(state, "DelaySource")
    state.DelaySource = "legacy_resumed_state";
end
if ~isfield(state, "DelayStatus")
    state.DelayStatus = "legacy_resumed_state";
end
if ~isfield(state, "Pending") || isempty(state.Pending)
    state.Pending = repmat(struct( ...
        "ApplyFrame", NaN, "SourceSlot", NaN, "Decision", struct()), 0, 1);
elseif ~isfield(state.Pending, "SourceSlot")
    for i = 1:numel(state.Pending)
        state.Pending(i).SourceSlot = double(state.Pending(i).ApplyFrame) - ...
            double(state.DelaySlots);
    end
end
end

function tf = localModeEnabled(mode)
mode = lower(string(mode));
tf = ~(mode == "" || ismember(mode, ["disabled","none","off","false","fixed"]));
end

function tf = localFrameEligible(frameIdx, periodFrames)
periodFrames = max(1, round(double(periodFrames)));
tf = mod(max(0, round(double(frameIdx))) - 1, periodFrames) == 0;
end

function count = localParseFrameCount(raw, defaultValue)
if nargin < 2
    defaultValue = 1;
end
if isnumeric(raw) && isscalar(raw) && isfinite(raw)
    count = max(1, round(double(raw)));
    return;
end
token = lower(strtrim(string(raw)));
if token == "" || ismember(token, ["slot","frame","per_slot","per_frame"])
    count = 1;
    return;
end
match = regexp(char(token), '(\d+)', 'tokens', 'once');
if isempty(match)
    count = max(1, round(double(defaultValue)));
else
    count = max(1, round(str2double(match{1})));
end
end
