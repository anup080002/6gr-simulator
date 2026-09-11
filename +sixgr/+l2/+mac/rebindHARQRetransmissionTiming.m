function grant = rebindHARQRetransmissionTiming(grant)
%REBINDHARQRETRANSMISSIONTIMING Clear expired timing from a HARQ replay.
%
% The PHY/TB contract of a retransmission remains frozen.  Timing fields are
% different: they describe the control, data and feedback occasions of one
% transmission attempt.  Clear only those derived fields so the canonical
% TimingRelationEngine can select a standards-valid K0/K1/K2 from the
% attached configuration for the new control occasion.

if ~(isstruct(grant) && isscalar(grant)) || ~localIsRetransmission(grant)
    return;
end

% Scheduler grant templates carry K fields, so retain the schema while
% removing the previous attempt's explicit timing override.
for field = ["K0", "K1", "K2"]
    grant.(char(field)) = NaN;
end

if isfield(grant, "TimingDecision")
    grant.TimingDecision = struct();
end
for field = ["ControlSlot", "ControlFrame", ...
        "ScheduledAbsoluteSlot", "HARQFeedbackAbsoluteSlot", ...
        "DataAbsoluteSlot", "FeedbackAbsoluteSlot"]
    name = char(field);
    if isfield(grant, name)
        grant.(name) = NaN;
    end
end
end

function tf = localIsRetransmission(grant)
tf = false;
if isfield(grant, "IsRetransmission") && ~isempty(grant.IsRetransmission)
    tf = logical(grant.IsRetransmission);
end
if ~tf && isfield(grant, "HARQ") && isstruct(grant.HARQ) && ...
        isscalar(grant.HARQ) && isfield(grant.HARQ, "IsRetransmission") && ...
        ~isempty(grant.HARQ.IsRetransmission)
    tf = logical(grant.HARQ.IsRetransmission);
end
if ~tf && isfield(grant, "GrantReason")
    reason = lower(strtrim(string(grant.GrantReason)));
    tf = isscalar(reason) && startsWith(reason, "harq_retx");
end
end
