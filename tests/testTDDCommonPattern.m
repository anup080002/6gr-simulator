function ok = testTDDCommonPattern()
%TESTTDDCOMMONPATTERN Validate vector-driven symbol-level common TDD maps.

setup6GRSimToolkit("Verbose", false);
[vectors, golden] = localTables();
rows = vectors(ismissing(vectors.DedicatedMode) | ...
    strlength(strtrim(vectors.DedicatedMode)) == 0, :);

for i = 1:height(rows)
    row = rows(i, :);
    expectedValid = localLogical(row.ExpectedValid);
    try
        common = localResolve(row);
        assert(expectedValid, "%s unexpectedly resolved.", row.TestID);
        assert(common.compactMap() == row.ExpectedSlotSymbolMap, ...
            "%s common symbol map differs from the supplied vector.", row.TestID);
        localCompareGolden(common, [], golden(golden.TestID == row.TestID, :));
        assert(~any(common.CommonDirection == 'F' & ...
            common.ResolvedDirection ~= "UNRESOLVED_FLEX", "all"), ...
            "%s resolved a common flexible symbol without a decision.", row.TestID);
    catch ME
        if expectedValid
            rethrow(ME);
        end
        assert(string(ME.identifier) == row.ExpectedErrorID, ...
            "%s threw %s, expected %s.", ...
            row.TestID, ME.identifier, row.ExpectedErrorID);
    end
end

% A 20 ms P1+P2 map is anchored at the first symbol of an even frame.
p1 = localPattern(10, 10, 0, 0, 0);
p2 = localPattern(10, 0, 0, 10, 0);
twenty = sixgr.phy.frame.TDDCommonConfig.resolve( ...
    "ReferenceSubcarrierSpacingKHz", 15, ...
    "ActiveSubcarrierSpacingKHz", 15, ...
    "CyclicPrefix", "normal", "Pattern1", p1, "Pattern2", p2);
assert(all(twenty.directionsForFrame(0) == 'D', "all"));
assert(all(twenty.directionsForFrame(1) == 'U', "all"));
assert(all(twenty.directionsForFrame(2) == 'D', "all"));
assert(all(twenty.directionsForFrame(3) == 'U', "all"));

% Extended-CP P1/P2 remains exact at a frame boundary.  With 60 kHz SCS
% there are 40 slots/frame; this one-millisecond cycle ends in UL at slot
% 39 and restarts in DL at absolute slot 40 without a rounded offset.
extendedP1 = localPattern(0.5, 2, 0, 0, 0);
extendedP2 = localPattern(0.5, 0, 0, 2, 0);
extended = sixgr.phy.frame.TDDCommonConfig.resolve( ...
    "ReferenceSubcarrierSpacingKHz", 60, ...
    "ActiveSubcarrierSpacingKHz", 60, ...
    "CyclicPrefix", "extended", ...
    "Pattern1", extendedP1, "Pattern2", extendedP2);
assert(extended.SymbolsPerSlot == 12 && ...
    extended.ActiveSlotsPerPattern == 4);
boundary = extended.directionsAtAbsoluteSlots([39, 40, 79, 80]);
assert(all(boundary([1, 3], :) == 'U', "all") && ...
    all(boundary([2, 4], :) == 'D', "all"));
assert(isequal(extended.directionsForFrame(0), ...
    extended.directionsForFrame(10000)), ...
    "Extended-CP P1/P2 drifted over a long multi-frame timeline.");

% No synthetic S direction is accepted or emitted.
assert(~any(twenty.CommonDirection == 'S', "all"));
ok = true;
end

function common = localResolve(row)
cp = "normal";
if row.TestID == "TDD-011"
    cp = "extended";
end
p1 = localPattern(row.Pattern1Periodicity_ms, row.P1_DLSlots, ...
    row.P1_DLSymbols, row.P1_ULSlots, row.P1_ULSymbols);
p2 = struct();
if isfinite(row.Pattern2Periodicity_ms)
    p2 = localPattern(row.Pattern2Periodicity_ms, row.P2_DLSlots, ...
        row.P2_DLSymbols, row.P2_ULSlots, row.P2_ULSymbols);
end
common = sixgr.phy.frame.TDDCommonConfig.resolve( ...
    "ReferenceSubcarrierSpacingKHz", row.ReferenceSCS_kHz, ...
    "ActiveSubcarrierSpacingKHz", row.ActiveSCS_kHz, ...
    "CyclicPrefix", cp, "Pattern1", p1, "Pattern2", p2);
end

function p = localPattern(period, dlSlots, dlSymbols, ulSlots, ulSymbols)
p = struct( ...
    "PeriodicityMilliseconds", double(period), ...
    "NumDownlinkSlots", double(dlSlots), ...
    "NumDownlinkSymbols", double(dlSymbols), ...
    "NumUplinkSlots", double(ulSlots), ...
    "NumUplinkSymbols", double(ulSymbols));
end

function localCompareGolden(common, dedicated, golden)
for i = 1:height(golden)
    slot = golden.Slot(i) + 1;
    symbol = golden.Symbol(i) + 1;
    assert(string(common.CommonDirection(slot, symbol)) == ...
        golden.CommonDirection(i));
    if isempty(dedicated)
        actualDedicated = "";
        actualResolved = common.ResolvedDirection(slot, symbol);
    else
        actualDedicated = dedicated.DedicatedDirection(slot, symbol);
        actualResolved = dedicated.ResolvedDirection(slot, symbol);
    end
    expectedDedicated = golden.DedicatedDirection(i);
    if ismissing(expectedDedicated)
        expectedDedicated = "";
    end
    assert(actualDedicated == expectedDedicated);
    assert(actualResolved == golden.ResolvedDirection(i));
end
end

function [vectors, golden] = localTables()
base = fullfile(fileparts(mfilename("fullpath")), "vectors", "frame_grid");
assert(isfolder(base), "Canonical frame/grid vector directory is missing.");
vectors = readtable(fullfile(base, "frame_tdd_test_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
golden = readtable(fullfile(base, "expected_slot_symbol_ownership.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
end

function tf = localLogical(value)
tf = upper(strtrim(string(value))) == "TRUE";
end
