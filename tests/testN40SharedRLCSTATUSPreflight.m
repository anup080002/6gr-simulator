function ok=testN40SharedRLCSTATUSPreflight()
% Resolve bounded original-reference/STATUS profile; no RF execution.
[ok,state]=testN40SharedRLCSTATUSRecovery(true,tempname);
assert(ok&&isstruct(state)&&isempty(fieldnames(state)));
fprintf('N40_SHARED_RLC_STATUS_PREFLIGHT_PASS original_reference_prefix=1 configured_horizon=80 no_RF=1\n');
end
