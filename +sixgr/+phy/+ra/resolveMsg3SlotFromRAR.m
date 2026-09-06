function slot = resolveMsg3SlotFromRAR(raCfg, grant)
%RESOLVEMSG3SLOTFROMRAR Consume the decoded RAR timing, never a private delay.
% The current RA carrier context uses one DL/UL numerology. Cross-numerology
% RA requires an explicit scheduling/UL-BWP time conversion, not this sum.
fields = ["K2","Msg3AdditionalDelaySlots"];
for field = fields
    if ~isfield(grant,field) || ~isnumeric(grant.(field)) || ...
            ~isreal(grant.(field)) || ~isscalar(grant.(field)) || ...
            ~isfinite(grant.(field)) || grant.(field) < 0 || grant.(field) ~= fix(grant.(field))
        error("sixgr:phy:ra:MissingDecodedRARTiming", ...
            "Msg3 requires decoded RAR timing field %s.",field);
    end
end
slot = double(raCfg.Msg2Slot) + double(grant.K2) + double(grant.Msg3AdditionalDelaySlots);
if slot ~= double(raCfg.Msg3Slot)
    error("sixgr:phy:ra:DecodedRARSlotMismatch", ...
        "Decoded RAR schedules Msg3 at %d, but the queued allocation is at %d.", ...
        slot,double(raCfg.Msg3Slot));
end
end
