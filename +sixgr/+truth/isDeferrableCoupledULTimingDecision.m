function tf = isDeferrableCoupledULTimingDecision(decision)
%ISDEFERRABLECOUPLEDULTIMINGDECISION Identify a valid no-UL-occasion result.
%
% A TDD DL control slot is not guaranteed to have a configured K2 value
% whose PUSCH allocation lands on UL symbols. These availability outcomes
% mean "do not schedule UL from this control slot"; malformed or incomplete
% timing configuration remains a hard failure.

tf = false;
if ~(isstruct(decision) && isscalar(decision)) || ...
        logical(sixgr.util.structGet(decision, "Valid", false))
    return;
end

reason = string(sixgr.util.structGet(decision, "ReasonCode", ""));
deferrable = "data_timing_rejected:" + [ ...
    "target_hits_fixed_opposite_direction", ...
    "target_flexible_symbols_unresolved", ...
    "target_hits_guard_symbols", ...
    "target_hits_unused_symbols"];
tf = isscalar(reason) && any(reason == deferrable);
end
