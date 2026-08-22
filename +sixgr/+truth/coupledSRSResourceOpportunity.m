function tf = coupledSRSResourceOpportunity(cfg, slotIdx, ueIdx, numUsers, periodSlots, schedulingPolicy, maxUEsPerSlot)
%COUPLEDSRSRESOURCEOPPORTUNITY Resolve whether a coupled-runtime SRS resource is active.
% The opportunity gate must honor configured SRS slots; multiplexing controls
% how many due UEs share an occasion, not whether the occasion itself exists.

slotIdx = max(1, round(double(slotIdx)));
ueIdx = max(1, round(double(ueIdx)));
numUsers = max(1, round(double(numUsers)));
periodSlots = max(1, round(double(periodSlots)));
schedulingPolicy = lower(strtrim(string(schedulingPolicy)));
maxUEsPerSlot = max(1, round(double(maxUEsPerSlot)));

slotWithinPeriod1 = double(sixgr.util.structGet(cfg, "phy.srs.slotWithinPeriod1Based", []));
slotWithinPeriod1 = unique(round(slotWithinPeriod1(isfinite(slotWithinPeriod1) & slotWithinPeriod1 >= 1)), "stable");
if ~isempty(slotWithinPeriod1)
    slotInPeriod = mod(slotIdx - 1, periodSlots) + 1;
    matchIdx = find(slotWithinPeriod1 == slotInPeriod, 1, "first");
    if isempty(matchIdx)
        tf = false;
        return;
    end
    if schedulingPolicy == "multiplex_due_users" || maxUEsPerSlot >= numUsers
        tf = true;
        return;
    end
    targetUE = mod(double(matchIdx) - 1, numUsers) + 1;
    tf = ueIdx == targetUE;
    return;
end
absoluteSlots0 = double(sixgr.util.structGet(cfg, "phy.srs.slotNumbers", []));
absoluteSlots0 = unique(round(absoluteSlots0(isfinite(absoluteSlots0) & absoluteSlots0 >= 0)), "stable");
if ~isempty(absoluteSlots0)
    tf = ismember(slotIdx - 1, absoluteSlots0);
    return;
end
error("sixgr:truth:MissingSRSSlotAuthority", ...
    "Enabled SRS requires phy.srs.slotWithinPeriod1Based or phy.srs.slotNumbers; no hardcoded phase is permitted.");
end
