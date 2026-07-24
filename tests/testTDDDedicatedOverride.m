function ok = testTDDDedicatedOverride()
%TESTTDDDEDICATEDOVERRIDE Validate dedicated changes to flexible symbols only.

setup6GRSimToolkit("Verbose", false);
base = fullfile(fileparts(mfilename("fullpath")), "vectors", "frame_grid");
vectors = readtable(fullfile(base, "frame_tdd_test_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
golden = readtable(fullfile(base, "expected_slot_symbol_ownership.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
rows = vectors(~ismissing(vectors.DedicatedMode) & ...
    strlength(strtrim(vectors.DedicatedMode)) > 0, :);

for i = 1:height(rows)
    row = rows(i, :);
    expectedValid = upper(row.ExpectedValid) == "TRUE";
    common = localCommon(row);
    override = struct("SlotIndex", row.DedicatedSlotIndex, ...
        "Mode", row.DedicatedMode);
    if lower(row.DedicatedMode) == "explicit"
        override.FirstDownlinkSymbols = row.DedicatedDLSymbols;
        override.LastUplinkSymbols = row.DedicatedULSymbols;
    end
    before = common.CommonDirection;
    try
        dedicated = sixgr.phy.frame.TDDDedicatedConfig.apply(common, override);
        assert(expectedValid, "%s unexpectedly resolved.", row.TestID);
        assert(isequal(dedicated.CommonDirection, before), ...
            "%s mutated common symbol ownership.", row.TestID);
        assert(dedicated.compactMap() == row.ExpectedSlotSymbolMap, ...
            "%s dedicated map differs from the supplied vector.", row.TestID);
        localCompare(dedicated, golden(golden.TestID == row.TestID, :));
    catch ME
        if expectedValid
            rethrow(ME);
        end
        assert(string(ME.identifier) == row.ExpectedErrorID, ...
            "%s threw %s, expected %s.", ...
            row.TestID, ME.identifier, row.ExpectedErrorID);
    end
end

% The vector-backed extended-CP override must remain anchored to the same
% reference slot over a long absolute-frame interval.
extendedRow = vectors(vectors.TestID == "TDD-011", :);
assert(height(extendedRow) == 1);
extendedCommon = localCommon(extendedRow);
extendedOverride = struct("SlotIndex", ...
    extendedRow.DedicatedSlotIndex, "Mode", ...
    extendedRow.DedicatedMode, "FirstDownlinkSymbols", ...
    extendedRow.DedicatedDLSymbols, "LastUplinkSymbols", ...
    extendedRow.DedicatedULSymbols);
extendedDedicated = sixgr.phy.frame.TDDDedicatedConfig.apply( ...
    extendedCommon, extendedOverride);
assert(isequal(extendedDedicated.directionsForFrame(0), ...
    extendedDedicated.directionsForFrame(10000)), ...
    "Extended-CP dedicated ownership drifted across frame boundaries.");
ok = true;
end

function common = localCommon(row)
cp = "normal";
if row.TestID == "TDD-011"
    cp = "extended";
end
p1 = struct("PeriodicityMilliseconds", row.Pattern1Periodicity_ms, ...
    "NumDownlinkSlots", row.P1_DLSlots, ...
    "NumDownlinkSymbols", row.P1_DLSymbols, ...
    "NumUplinkSlots", row.P1_ULSlots, ...
    "NumUplinkSymbols", row.P1_ULSymbols);
p2 = struct();
if isfinite(row.Pattern2Periodicity_ms)
    p2 = struct("PeriodicityMilliseconds", row.Pattern2Periodicity_ms, ...
        "NumDownlinkSlots", row.P2_DLSlots, ...
        "NumDownlinkSymbols", row.P2_DLSymbols, ...
        "NumUplinkSlots", row.P2_ULSlots, ...
        "NumUplinkSymbols", row.P2_ULSymbols);
end
common = sixgr.phy.frame.TDDCommonConfig.resolve( ...
    "ReferenceSubcarrierSpacingKHz", row.ReferenceSCS_kHz, ...
    "ActiveSubcarrierSpacingKHz", row.ActiveSCS_kHz, ...
    "CyclicPrefix", cp, "Pattern1", p1, "Pattern2", p2);
end

function localCompare(actual, golden)
for i = 1:height(golden)
    slot = golden.Slot(i) + 1;
    symbol = golden.Symbol(i) + 1;
    expectedDedicated = golden.DedicatedDirection(i);
    if ismissing(expectedDedicated)
        expectedDedicated = "";
    end
    assert(string(actual.CommonDirection(slot, symbol)) == ...
        golden.CommonDirection(i));
    assert(actual.DedicatedDirection(slot, symbol) == expectedDedicated);
    assert(actual.ResolvedDirection(slot, symbol) == ...
        golden.ResolvedDirection(i));
end
end
