function tf = isActivePRACHOccasion(cfg, slotIdx)
%ISACTIVEPRACHOCCASION Test an absolute carrier slot against canonical PRACH timing.
%
% FrameStructureEngine/PRACHOccasionResolver already materializes every
% candidate through nrPRACHIndices and rejects resources that do not fit
% the resolved UL symbol map.  Runtime gating must therefore consume its
% absolute carrier-slot aliases directly.  NPRACHSlot is a PRACH-timeline
% index and must not be populated with an absolute carrier slot merely to
% repeat that validation.

tf = false;
prachRequired = logical(sixgr.util.structGet( ...
    cfg, "run.controlGating.prachRequired", false));
if ~(isnumeric(slotIdx) && isscalar(slotIdx) && ...
        isfinite(double(slotIdx)) && double(slotIdx) >= 1)
    return;
end

validSlots1 = double(sixgr.util.structGet( ...
    cfg, "phy.prach.validSlots1Based", []));
validSlots1 = validSlots1(isfinite(validSlots1) & validSlots1 >= 1);
if ~isempty(validSlots1)
    slotsPerFrame = double(sixgr.util.structGet( ...
        cfg, "phy.numerology.slotsPerFrame", ...
        sixgr.util.structGet(cfg, "frame_timing.slots_per_frame", ...
        max(validSlots1))));
    slotsPerFrame = max(1, round(double(slotsPerFrame)));
    canonicalSlotInFrame = mod(round(double(slotIdx)) - 1, ...
        slotsPerFrame) + 1;
    tf = ismember(canonicalSlotInFrame, ...
        round(validSlots1(:).'));
    return;
end

try
    frameStructure = sixgr.phy.FrameStructureEngine(cfg);
    tf = logical(frameStructure.IsPRACHSlot(slotIdx));
catch ME
    if prachRequired
        rethrow(ME);
    end
    partition = sixgr.util.resolveTDDSlotPartition(cfg, slotIdx);
    tf = logical(partition.AllowUL) && ...
        ~logical(partition.IsSpecialSlot);
end
end
