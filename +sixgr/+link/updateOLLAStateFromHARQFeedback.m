function [adaptationState, event] = updateOLLAStateFromHARQFeedback( ...
        cfg, direction, feedback, adaptationState)
%UPDATEOLLASTATEFROMHARQFEEDBACK Update OLLA once at the HARQ boundary.
%   ACK/NACK from a retransmission is excluded because it reflects HARQ
%   combining, not first-transmission BLER at the selected AMC point.

arguments
    cfg (1,1) struct
    direction (1,1) string
    feedback (1,1) struct
    adaptationState (1,1) struct = struct()
end

direction = upper(strtrim(direction));
if ~any(direction == ["DL","UL"])
    error("sixgr:link:InvalidOLLADirection", ...
        "OLLA direction must be DL or UL, got %s.", direction);
end

policy = sixgr.link.resolveOLLAConfig(cfg);
adaptationState = localMergePolicy(adaptationState, policy, direction);
[ackKnown, ack] = localAck(feedback);
isRetx = logical(sixgr.util.structGet(feedback, "IsRetransmission", ...
    sixgr.util.structGet(feedback, "HARQIsRetransmission", false)));
rv = double(sixgr.util.structGet(feedback, "RV", ...
    sixgr.util.structGet(feedback, "HARQRV", NaN)));

eligible = false;
reason = "outer_loop_disabled";
if policy.Enabled
    if ~ackKnown
        reason = "no_ack_nack_feedback";
    elseif isRetx
        reason = "harq_retransmission_feedback_excluded";
    elseif isfinite(rv) && round(rv) ~= 0
        reason = "nonzero_rv_feedback_excluded";
    else
        eligible = true;
        reason = "first_transmission_harq_feedback";
    end
end

offsetBefore = double(adaptationState.DeltaMCS);
if eligible
    if ack
        adaptationState.DeltaMCS = min(policy.MaximumOffsetDb, ...
            offsetBefore + policy.StepUpDb);
    else
        adaptationState.DeltaMCS = max(policy.MinimumOffsetDb, ...
            offsetBefore - policy.StepDownDb);
    end
    adaptationState.LastObservedAck = logical(ack);
    adaptationState.OLLAUpdateCount = ...
        double(adaptationState.OLLAUpdateCount) + 1;
end

adaptationState.LastOLLAFeedbackEligible = logical(eligible);
adaptationState.LastOLLAFeedbackExclusionReason = char(reason);
adaptationState.LastOLLAFeedbackSourceSlot = double(sixgr.util.structGet( ...
    feedback, "SourceSlot", NaN));
adaptationState.LastOLLAFeedbackHarqID = double(sixgr.util.structGet( ...
    feedback, "HarqID", sixgr.util.structGet(feedback, "HARQProcess", NaN)));
adaptationState.OLLAStateAuthority = char(policy.StateAuthority);

event = struct( ...
    "Direction", char(direction), ...
    "Authority", char(policy.StateAuthority), ...
    "Enabled", logical(policy.Enabled), ...
    "FeedbackKnown", logical(ackKnown), ...
    "Ack", logical(ack), ...
    "Eligible", logical(eligible), ...
    "ExclusionReason", char(reason), ...
    "IsRetransmission", logical(isRetx), ...
    "RV", double(rv), ...
    "OffsetBeforeDb", double(offsetBefore), ...
    "OffsetAfterDb", double(adaptationState.DeltaMCS), ...
    "UpdateCount", double(adaptationState.OLLAUpdateCount), ...
    "ImpliedTargetBLER", double(policy.ImpliedTargetBLER));
end

function state = localMergePolicy(state, policy, direction)
state.Direction = char(direction);
state.OuterLoopEnabled = logical(policy.Enabled);
state.OLLAStepUp = double(policy.StepUpDb);
state.OLLAStepDown = double(policy.StepDownDb);
state.DeltaMCSMin = double(policy.MinimumOffsetDb);
state.DeltaMCSMax = double(policy.MaximumOffsetDb);
state.OLLAStateAuthority = char(policy.StateAuthority);
if ~isfield(state, "DeltaMCS") || ...
        ~(isscalar(state.DeltaMCS) && isfinite(double(state.DeltaMCS)))
    state.DeltaMCS = 0;
end
state.DeltaMCS = min(policy.MaximumOffsetDb, ...
    max(policy.MinimumOffsetDb, double(state.DeltaMCS)));
if ~isfield(state, "OLLAUpdateCount") || ...
        ~(isscalar(state.OLLAUpdateCount) && ...
        isfinite(double(state.OLLAUpdateCount)) && ...
        double(state.OLLAUpdateCount) >= 0)
    state.OLLAUpdateCount = 0;
end
if ~isfield(state, "LastObservedAck")
    state.LastObservedAck = false;
end
end

function [known, ack] = localAck(feedback)
known = false;
ack = false;
valid = sixgr.util.structGet(feedback, "AckObservedValid", []);
observed = sixgr.util.structGet(feedback, "AckObserved", []);
if ~isempty(valid) && logical(valid) && ~isempty(observed) && ...
        isscalar(observed) && isfinite(double(observed))
    known = true;
    ack = logical(observed);
    return;
end
candidates = ["ObservedAck","Ack","CombinedDecodeOK", ...
    "CurrentDecodeOK","CRCPass"];
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(feedback, candidates(i), []);
    if ~isempty(raw) && (isnumeric(raw) || islogical(raw)) && ...
            isscalar(raw) && isfinite(double(raw))
        known = true;
        ack = logical(raw);
        return;
    end
end
end
