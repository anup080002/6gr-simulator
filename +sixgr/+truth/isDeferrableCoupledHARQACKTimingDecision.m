function tf = isDeferrableCoupledHARQACKTimingDecision(decision)
%ISDEFERRABLECOUPLEDHARQACKTIMINGDECISION Classify a valid no-DL occasion.
%
% A TDD control/data slot is not necessarily followed by a configured K1
% HARQ-ACK occasion.  The coupled runtime may leave that slot unscheduled,
% but malformed timing policy or allocation data must remain a hard error.

tf = false;
if ~(isstruct(decision) && isscalar(decision)) || ...
        logical(sixgr.util.structGet(decision, "Valid", false))
    return;
end

reason = string(sixgr.util.structGet(decision, "ReasonCode", ""));
deferrable = "harq_ack_timing_rejected:" + [ ...
    "target_hits_fixed_opposite_direction"
    "target_flexible_symbols_unresolved"
    "target_hits_guard_symbols"
    "target_hits_unused_symbols"];
tf = isscalar(reason) && any(reason == deferrable);
end
