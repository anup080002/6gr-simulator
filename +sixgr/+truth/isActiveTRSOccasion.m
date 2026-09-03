function tf = isActiveTRSOccasion(cfg, slotIdx)
%ISACTIVETRSOCCASION Resolve an authored TRS carrier-slot occasion.
% Slot numbers are zero-based within the carrier frame.  No last-run-time
% or hardcoded phase heuristic is permitted.

enabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
if ~enabled
    tf = false;
    return;
end
if ~(isnumeric(slotIdx) && isscalar(slotIdx) && isfinite(slotIdx) && slotIdx >= 1)
    error("sixgr:truth:InvalidTRSSlot", ...
        "TRS slot index must be a positive one-based carrier slot.");
end
slotNumbers0 = double(sixgr.util.structGet(cfg, "phy.trs.slotNumbers", []));
slotNumbers0 = unique(round(slotNumbers0(isfinite(slotNumbers0) & slotNumbers0 >= 0)), "stable");
if isempty(slotNumbers0)
    periodSlots = double(sixgr.util.structGet(cfg, "phy.trs.period_slots", NaN));
    periodOffset = double(sixgr.util.structGet(cfg, "phy.trs.period_offset", 0));
    if ~(isscalar(periodSlots) && isfinite(periodSlots) && periodSlots >= 1 && ...
            periodSlots == round(periodSlots) && isscalar(periodOffset) && ...
            isfinite(periodOffset) && periodOffset >= 0 && ...
            periodOffset < periodSlots && periodOffset == round(periodOffset))
        error("sixgr:truth:MissingTRSSlotAuthority", ...
            ["Enabled TRS requires explicit slotNumbers or an integer " + ...
             "period_slots/period_offset pair resolved from YAML."]);
    end
    absoluteSlot0 = round(double(slotIdx)) - 1;
    tf = mod(absoluteSlot0 - periodOffset, periodSlots) == 0;
    return;
end
slotsPerFrame = double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", ...
    sixgr.util.structGet(cfg, "frame_timing.slots_per_frame", NaN)));
if ~(isscalar(slotsPerFrame) && isfinite(slotsPerFrame) && slotsPerFrame >= 1)
    error("sixgr:truth:MissingTRSFrameTiming", ...
        "TRS gating requires the resolved carrier slots per frame.");
end
slotInFrame0 = mod(round(double(slotIdx)) - 1, round(slotsPerFrame));
tf = ismember(slotInFrame0, slotNumbers0);
end
