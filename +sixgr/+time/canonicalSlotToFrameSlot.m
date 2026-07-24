function [frame1, slotInFrame1, frame0, slotInFrame0] = canonicalSlotToFrameSlot(canonicalSlot1, slotsPerFrame)
%CANONICALSLOTTOFRAMESLOT Convert 1-based canonical slots to frame/slot.

if nargin < 2 || isempty(slotsPerFrame)
    error("sixgr:time:MissingSlotsPerFrame", ...
        "Canonical slot conversion requires catalog-resolved SlotsPerFrame.");
end
slotsPerFrame = double(slotsPerFrame);
if ~(isscalar(slotsPerFrame) && isfinite(slotsPerFrame) && ...
        slotsPerFrame >= 1 && slotsPerFrame == fix(slotsPerFrame))
    error("sixgr:time:InvalidSlotsPerFrame", ...
        "SlotsPerFrame must be a positive finite integer.");
end
canonicalSlot1 = round(double(canonicalSlot1));
if any(~isfinite(canonicalSlot1(:)) | canonicalSlot1(:) < 1)
    error("sixgr:time:InvalidCanonicalSlot", "Canonical slot must be 1-based and finite.");
end

frame0 = floor((canonicalSlot1 - 1) ./ slotsPerFrame);
slotInFrame0 = mod(canonicalSlot1 - 1, slotsPerFrame);
frame1 = frame0 + 1;
slotInFrame1 = slotInFrame0 + 1;
end
