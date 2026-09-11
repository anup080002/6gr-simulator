function slot = runtimeULGrantSlot(grant)
%RUNTIMEULGRANTSLOT Cross the canonical-zero/runtime-one slot boundary once.
% Runtime resource-only fixtures may carry Slot without a timing decision.
% A scheduler-issued decision must agree with that label; never reinterpret
% ScheduledAbsoluteSlot as one-based or silently repair a stale decision.
assert(isstruct(grant) && isscalar(grant), ...
    'sixgr:truth:InvalidQueuedPUSCHDueSlot','Expected one queued UL grant.');
slot = sixgr.util.structGet(grant,'Slot',NaN);
assert(isnumeric(slot) && isreal(slot) && isscalar(slot) && ...
    isfinite(slot) && slot>=1 && slot==fix(slot), ...
    'sixgr:truth:InvalidQueuedPUSCHDueSlot', ...
    'Queued PUSCH requires an explicit positive one-based runtime Slot.');
slot = double(slot);
if isfield(grant,'TimingDecision')
    sixgr.phy.grant.assertGrantTimingIdentity(grant,'UL');
    decision = grant.TimingDecision;
    if ~isempty(fieldnames(decision))
        assert(slot==double(decision.DataAbsoluteSlot)+1, ...
            'sixgr:truth:QueuedULTimingMismatch', ...
            'Runtime Slot must equal canonical DataAbsoluteSlot plus one.');
    end
end
end
