function ok = testFrameNumerologyCatalog()
%TESTFRAMENUMEROLOGYCATALOG Execute the supplied Release-18 numerology vectors.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

vectors = readtable(localVectorPath("frame_numerology_test_vectors.csv"), ...
    "TextType", "string");
golden = readtable(localVectorPath("expected_frame_numerology_matrix.csv"), ...
    "TextType", "string");
assert(height(vectors) == 18, ...
    "The mandatory numerology vector file must contain all 18 supplied rows.");

n = height(vectors);
testID = string(vectors.TestID);
mu = nan(n, 1);
scs = double(vectors.SCS_kHz);
cp = string(vectors.CyclicPrefix);
expectedValid = false(n, 1);
resolvedValid = false(n, 1);
expectedSymbols = nan(n, 1);
resolvedSymbols = nan(n, 1);
expectedSlotsSubframe = nan(n, 1);
resolvedSlotsSubframe = nan(n, 1);
expectedSlotsFrame = nan(n, 1);
resolvedSlotsFrame = nan(n, 1);
errorID = strings(n, 1);
status = repmat("PASS", n, 1);

for i = 1:n
    expectedValid(i) = localTruth(vectors.ExpectedValid(i));
    mu(i) = double(vectors.Mu(i));
    expectedSymbols(i) = double(vectors.ExpectedSymbolsPerSlot(i));
    expectedSlotsSubframe(i) = double(vectors.ExpectedSlotsPerSubframe(i));
    expectedSlotsFrame(i) = double(vectors.ExpectedSlotsPerFrame(i));
    expectedError = string(vectors.ExpectedErrorID(i));

    try
        num = sixgr.phy.frame.NumerologyCatalog.resolve( ...
            scs(i), cp(i), "generic_waveform_test", "");
        resolvedValid(i) = true;
        resolvedSymbols(i) = num.SymbolsPerSlot;
        resolvedSlotsSubframe(i) = num.SlotsPerSubframe;
        resolvedSlotsFrame(i) = num.SlotsPerFrame;
        assert(expectedValid(i), ...
            "Vector %s unexpectedly resolved as valid.", testID(i));
        assert(num.Mu == mu(i), ...
            "Vector %s resolved mu=%g, expected %g.", testID(i), num.Mu, mu(i));
        assert(num.SubcarrierSpacingKHz == scs(i), ...
            "Vector %s changed its configured SCS.", testID(i));
        assert(string(num.CyclicPrefix) == lower(cp(i)), ...
            "Vector %s changed its configured cyclic prefix.", testID(i));
        assert(num.SymbolsPerSlot == expectedSymbols(i), ...
            "Vector %s symbols/slot mismatch.", testID(i));
        assert(num.SlotsPerSubframe == expectedSlotsSubframe(i), ...
            "Vector %s slots/subframe mismatch.", testID(i));
        assert(num.SlotsPerFrame == expectedSlotsFrame(i), ...
            "Vector %s slots/frame mismatch.", testID(i));
        assert(abs(num.SlotDurationMilliseconds - ...
            double(vectors.ExpectedSlotDuration_ms(i))) < 1e-12, ...
            "Vector %s slot-duration mismatch.", testID(i));
        assert(abs(sixgr.time.slotDurationSec(scs(i)) - ...
            num.SlotDurationSeconds) < 1e-15, ...
            "Vector %s differs from sixgr.time.slotDurationSec.", testID(i));
    catch ME
        errorID(i) = string(ME.identifier);
        assert(~expectedValid(i), ...
            "Valid vector %s failed with %s: %s", ...
            testID(i), string(ME.identifier), string(ME.message));
        assert(errorID(i) == expectedError, ...
            "Vector %s failed with %s, expected %s.", ...
            testID(i), errorID(i), expectedError);
    end
end

actual = table(testID, mu, scs, cp, expectedValid, resolvedValid, ...
    expectedSymbols, resolvedSymbols, expectedSlotsSubframe, ...
    resolvedSlotsSubframe, expectedSlotsFrame, resolvedSlotsFrame, ...
    errorID, status, ...
    'VariableNames', [ ...
    "TestID", "Mu", "SCS_kHz", "CyclicPrefix", "ExpectedValid", ...
    "ResolvedValid", "ExpectedSymbolsPerSlot", "ResolvedSymbolsPerSlot", ...
    "ExpectedSlotsPerSubframe", "ResolvedSlotsPerSubframe", ...
    "ExpectedSlotsPerFrame", "ResolvedSlotsPerFrame", "ErrorID", "Status"]);
localAssertGolden(actual, golden);

normalTable = sixgr.phy.grid.nrNumerologyTable();
assert(isequal(normalTable.mu(:), (0:6).'), ...
    "nrNumerologyTable must delegate all normal-CP mu=0...6 rows.");
assert(all(normalTable.symbols_per_slot == 14), ...
    "Normal-CP numerology rows must have 14 symbols/slot.");
extendedTable = sixgr.phy.grid.nrNumerologyTable("extended");
assert(height(extendedTable) == 1 && extendedTable.mu == 2 && ...
    extendedTable.scs_kHz == 60 && extendedTable.symbols_per_slot == 12, ...
    "The delegated extended-CP table must contain only mu=2 / 60 kHz.");

assertThrows(@() sixgr.phy.frame.NumerologyCatalog.resolve( ...
    120, "normal", "carrier_transmission_grid", "FR1"), ...
    "sixgr:phy:frame:UnsupportedNumerologyForRole");
assertThrows(@() sixgr.phy.frame.NumerologyCatalog.resolve( ...
    15, "normal", "carrier_transmission_grid", ""), ...
    "sixgr:phy:frame:MissingFrequencyRange");

facadeCfg = struct();
facadeCfg = sixgr.util.structSet( ...
    facadeCfg, "frequency.center_frequency_hz", 4e9);
facadeCfg = sixgr.util.structSet( ...
    facadeCfg, "frequency.range_name", "FR1");
facadeCfg = sixgr.util.structSet( ...
    facadeCfg, "frequency.bandwidth_hz", 20e6);
facadeCfg = sixgr.util.structSet( ...
    facadeCfg, "frequency.duplex_mode", "FDD");
facadeCfg = sixgr.util.structSet( ...
    facadeCfg, "frequency.n_size_grid", 51);
facadeCfg = sixgr.util.structSet(facadeCfg, "frame.scs_khz", 30);
facadeCfg = sixgr.util.structSet(facadeCfg, "frame.cp_type", "normal");
facade = sixgr.phy.FrameStructureEngine(facadeCfg);
facadeNum = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    30, "normal", "carrier_transmission_grid", "FR1");
assert(facade.Mu == facadeNum.Mu && ...
    facade.SymbolsPerSlot == facadeNum.SymbolsPerSlot && ...
    facade.SlotsPerFrame == facadeNum.SlotsPerFrame && ...
    abs(facade.SlotDuration_ms - ...
        facadeNum.SlotDurationMilliseconds) < 1e-12, ...
    "FrameStructureEngine facade must expose the canonical numerology values.");

ok = true;
end

function localAssertGolden(actual, golden)
assert(height(actual) == height(golden), ...
    "Resolved numerology output row count differs from the supplied golden output.");
assert(isequal(string(actual.Properties.VariableNames), ...
    string(golden.Properties.VariableNames)), ...
    "Resolved numerology output schema differs from the supplied golden output.");
for i = 1:width(actual)
    name = actual.Properties.VariableNames{i};
    a = actual.(name);
    g = golden.(name);
    if isnumeric(a) || islogical(a)
        if islogical(a)
            g = arrayfun(@localTruth, g);
            assert(isequal(a, logical(g)), ...
                "Golden mismatch in logical column %s.", name);
        else
            g = double(g);
            assert(all((isnan(a) & isnan(g)) | abs(a - g) < 1e-12), ...
                "Golden mismatch in numeric column %s.", name);
        end
    else
        assert(isequal(localText(a), localText(g)), ...
            "Golden mismatch in text column %s.", name);
    end
end

function value = localText(value)
value = string(value);
value(ismissing(value)) = "";
end
end

function tf = localTruth(value)
if islogical(value)
    tf = logical(value);
elseif isnumeric(value)
    tf = logical(value ~= 0);
else
    tf = any(strcmpi(strtrim(string(value)), ["true", "1", "yes"]));
end
end

function assertThrows(fn, expectedID)
try
    fn();
catch ME
    assert(strcmp(ME.identifier, expectedID), ...
        "Expected error %s, received %s.", expectedID, ME.identifier);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", ...
    "Expected error %s was not thrown.", expectedID);
end

function path = localVectorPath(name)
testDirectory = fileparts(mfilename("fullpath"));
path = fullfile(testDirectory, "vectors", "frame_grid", name);
assert(isfile(path), "Mandatory frame/grid vector is missing: %s", path);
end
