function t = slotStartTimeSec(canonicalSlot1, slotDuration_s)
%SLOTSTARTTIMESEC Start time for a 1-based canonical slot.

if nargin < 2 || isempty(slotDuration_s)
    slotDuration_s = 0.5e-3;
end
slotDuration_s = double(slotDuration_s);
if ~(isscalar(slotDuration_s) && isfinite(slotDuration_s) && slotDuration_s > 0)
    error("sixgr:time:InvalidSlotDuration", "Slot duration must be a positive finite scalar.");
end

canonicalSlot1 = double(canonicalSlot1);
if any(~isfinite(canonicalSlot1(:)) | canonicalSlot1(:) < 1)
    error("sixgr:time:InvalidCanonicalSlot", "Canonical slot must be 1-based and finite.");
end
t = (canonicalSlot1 - 1) .* slotDuration_s;
end
