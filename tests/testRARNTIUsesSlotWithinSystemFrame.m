function ok = testRARNTIUsesSlotWithinSystemFrame()
%TESTRARNTIUSESSLOTWITHINSYSTEMFRAME Guard absolute-slot/t_id separation.

setup6GRSimToolkit("Verbose", false);

occasion = struct( ...
    "SlotIndex0", 95, ...              % Absolute campaign slot.
    "SymbolLocation", 14, ...          % Toolbox PRACH-grid location.
    "CarrierStartSymbol", 3, ...       % TS 38.321 s_id.
    "FrequencyIndex", 2, ...
    "ULCarrierId", 0, ...
    "Carrier", struct("NFrame", 4, "NSlot", 15));

actual = sixgr.phy.prach.computeRARNTIFromPRACHOccasion(occasion);
expected = sixgr.phy.ra.computeRARNTI( ...
    "SymbolIndex", 3, ...
    "SlotIndex", 15, ...
    "FrequencyIndex", 2, ...
    "ULCarrierId", 0);
assert(actual == expected, ...
    "RA-RNTI must use carrier-slot s_id/t_id, not Toolbox/absolute timing coordinates.");

% Without exact within-frame metadata, an out-of-range absolute slot must
% remain fail-closed rather than being silently wrapped or clamped.
legacy = rmfield(occasion, "Carrier");
try
    sixgr.phy.prach.computeRARNTIFromPRACHOccasion(legacy);
    error("sixgr:test:ExpectedRARNTICoordinateFailure", ...
        "Expected an invalid-coordinate failure for ambiguous absolute-slot input.");
catch cause
    assert(string(cause.identifier) == "sixgr:phy:ia:InvalidRARNTICoordinates", ...
        "Ambiguous out-of-range slot input must retain the typed fail-closed error.");
end

ok = true;
end
