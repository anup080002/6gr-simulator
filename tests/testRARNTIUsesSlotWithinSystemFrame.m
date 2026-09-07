function ok = testRARNTIUsesSlotWithinSystemFrame()
% Guard absolute-slot/t_id separation and explicit PRACH-clock authority.

setup6GRSimToolkit("Verbose", false);

occasion = struct( ...
    "SlotIndex0", 95, ...              % Absolute campaign slot.
    "SymbolLocation", 14, ...          % Toolbox PRACH-grid location.
    "CarrierStartSymbol", 3, ...       % Legacy explicit-coordinate fixture.
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
    "Legacy explicit coordinates must retain their within-frame t_id.");

% In the actual mixed-numerology case the data carrier is 15 kHz, while
% B4 PRACH uses 30 kHz. The RA-RNTI authority is PRACH s_id=0/t_id=9,
% NOT carrier start symbol 7/slot 4, nor absolute repeated carrier slot 14.
resolved=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
    'FrequencyRange','FR1','DuplexMode','TDD','ConfigurationIndex',157, ...
    'CarrierSubcarrierSpacingKHz',15,'NSizeGrid',25,'PRACHSubcarrierSpacingKHz',30);
row=table2struct(resolved.Occasions(1,:));
row.CarrierStartSymbol=row.StartSymbol;
row.SlotIndex0=14;
row.Carrier=struct('NFrame',1,'NSlot',4);
[actual,coordinates]=sixgr.phy.prach.computeRARNTIFromPRACHOccasion(row);
assert(actual==127 && coordinates.SymbolIndex==0 && coordinates.SlotIndex==9);

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
