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

tf = localCoupledUEControlOpportunity(slotIdx, ueIdx, periodSlots, 2);
end

function tf = localCoupledUEControlOpportunity(slotIdx, ueIdx, periodSlots, phaseOffset)
slotIdx = max(1, round(double(slotIdx)));
ueIdx = max(1, round(double(ueIdx)));
periodSlots = max(1, round(double(periodSlots)));
phaseOffset = round(double(phaseOffset));
tf = mod(slotIdx - 1, periodSlots) == mod((ueIdx - 1) + phaseOffset, periodSlots);
end
