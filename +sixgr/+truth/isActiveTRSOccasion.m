function tf = isActiveTRSOccasion(cfg, slotIdx)
%ISACTIVETRSOCCASION Resolve an authored TRS carrier-slot occasion.
% Slot numbers are zero-based within the carrier frame.  No last-run-time
% or hardcoded phase heuristic is permitted.

enabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
if ~enabled
    tf = false;
    return;
end
window = sixgr.truth.resolveTRSObservationWindow(cfg,slotIdx);
tf = window.ResourceActive;
end
