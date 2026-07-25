function tests = testInitialAccessType0PhaseCore
%TESTINITIALACCESSTYPE0PHASECORE Release-18 bounded Type-0 table floor.
tests = functiontests(localfunctions);
end

function testType0CORESET0Tables(testCase)
root = localVectorRoot();
vectors = readtable(fullfile(root, ...
    "ia_type0_coreset0_test_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
vectors = vectors(vectors.FR == "FR1", :);
verifyEqual(testCase, height(vectors), 144);

passCount = 0;
failCount = 0;
for ii = 1:height(vectors)
    row = vectors(ii, :);
    context = localCORESETContext(row);
    if row.ExpectedOutcome == "PASS"
        actual = sixgr.phy.pdcch.Type0PDCCHResolver( ...
            context, "TableID", row.Table);
        verifyEqual(testCase, actual.CORESETTable, row.Table, ...
            sprintf("Vector %s selected the wrong table.", row.VectorID));
        verifyEqual(testCase, actual.CORESET0Index, ...
            double(row.ControlResourceSetZero));
        verifyEqual(testCase, actual.MultiplexingPattern, ...
            double(row.MultiplexingPattern));
        verifyEqual(testCase, actual.CORESETRBs, ...
            double(row.CORESETRBs));
        verifyEqual(testCase, actual.CORESETSymbols, ...
            double(row.CORESETSymbols));
        verifyEqual(testCase, actual.OffsetRB, double(row.OffsetRB));
        verifyFalse(testCase, actual.ProxyUsed);
        verifyFalse(testCase, actual.FallbackUsed);
        passCount = passCount + 1;
    else
        localVerifyError(testCase, @() ...
            sixgr.phy.pdcch.Type0PDCCHResolver( ...
            context, "TableID", row.Table), ...
            row.ExpectedError, row.VectorID);
        failCount = failCount + 1;
    end
end
verifyEqual(testCase, passCount, 101);
verifyEqual(testCase, failCount, 43);
end

function testType0SearchSpace0Tables(testCase)
root = localVectorRoot();
path = fullfile(root, "ia_expected_type0_monitoring_tables.csv");
importOptions = detectImportOptions(path, ...
    "TextType", "string", "VariableNamingRule", "preserve");
importOptions = setvartype(importOptions, "M", "string");
vectors = readtable(path, importOptions);
vectors = vectors(vectors.FR == "FR1", :);
verifyEqual(testCase, height(vectors), 16);

for ii = 1:height(vectors)
    row = vectors(ii, :);
    context = localBaseContext();
    context.SearchSpaceZero = double(row.SearchSpaceZero);
    actual = sixgr.phy.pdcch.Type0PDCCHResolver(context, ...
        "TableID", "13-4");
    verifyEqual(testCase, actual.MonitoringTable, row.Table);
    verifyEqual(testCase, actual.O, double(row.O));
    verifyEqual(testCase, actual.M, localFraction(row.M), ...
        "AbsTol", eps);
    verifyEqual(testCase, actual.SearchSpaceSetsPerSlot, ...
        double(row.SearchSpaceSetsPerSlot));
    verifyEqual(testCase, actual.FirstSymbolRule, ...
        row.FirstSymbolRule);
    verifyEqual(testCase, height(actual.MonitoringOccasions), 1);
    verifyGreaterThanOrEqual(testCase, ...
        actual.MonitoringOccasions.AbsoluteSlot, 0);
    verifyLessThan(testCase, ...
        actual.MonitoringOccasions.FirstSymbol, 14);
end

context = localBaseContext();
context.SearchSpaceZero = 16;
localVerifyError(testCase, @() ...
    sixgr.phy.pdcch.Type0PDCCHResolver(context), ...
    "sixgr:phy:pdcch:type0_searchspace_reserved_index", ...
    "searchSpaceZero=16");
end

function testType0GSCNOffsets(testCase)
vectors = readtable(fullfile(localVectorRoot(), ...
    "ia_expected_type0_gscn_offset_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
verifyEqual(testCase, height(vectors), 40);
for ii = 1:height(vectors)
    row = vectors(ii, :);
    call = @() sixgr.phy.pdcch.type0GSCNOffset( ...
        row.FR, double(row.KSSB), ...
        double(row.CombinedIndex16xCORESET0PlusSearchSpace0));
    if row.ExpectedOutcome == "PASS"
        verifyEqual(testCase, call(), double(row.NGSCNOffset), ...
            sprintf("GSCN vector %s mismatched.", row.VectorID));
    else
        localVerifyError(testCase, call, row.ExpectedError, row.VectorID);
    end
end
end

function testType0ContextualDCIAndCandidates(testCase)
context = localBaseContext();
context.InitialDLBWPSize = 52;
actual = sixgr.phy.pdcch.Type0PDCCHResolver(context);
[expectedBits, ~] = sixgr.phy.pdcch.dciPayloadSizeBits(52, "1_0");
verifyEqual(testCase, actual.DCIPayloadBits, expectedBits);
verifyNotEqual(testCase, actual.DCIPayloadBits, 32);
verifyEqual(testCase, actual.CandidateCounts, [0 0 2 1 0]);
verifyEqual(testCase, height(actual.Candidates), 3);
verifyEqual(testCase, actual.Candidates.FirstCCE, [0; 4; 0]);
verifyEqual(testCase, actual.SearchSpace0.SlotPeriod, 40);
verifyEqual(testCase, actual.Type0PDCCHCSS.RNTIType, "SI-RNTI");
verifyEqual(testCase, actual.Type0PDCCHCSS.PDCCHScramblingRNTI, 0);
end

function context = localCORESETContext(row)
context = localBaseContext();
context.SSBSCSKHz = double(row.SSBSCSkHz);
context.PDCCHSCSKHz = double(row.PDCCHSCSkHz);
context.SharedSpectrum = lower(row.SharedSpectrum) == "true";
context.CORESET0Index = double(row.ControlResourceSetZero);
context.ChannelBandwidthMHz = localTableBandwidth(row.Table);
context.InitialDLBWPSize = 275;
end

function context = localBaseContext()
context = struct( ...
    "FrequencyRange", "FR1", ...
    "SSBSCSKHz", 30, ...
    "PDCCHSCSKHz", 30, ...
    "ChannelBandwidthMHz", 10, ...
    "SharedSpectrum", false, ...
    "Note17Band", false, ...
    "KSSB", 0, ...
    "CORESET0Index", 0, ...
    "SearchSpaceZero", 0, ...
    "SSBIndex", 0, ...
    "SSBFrameNumber", 0, ...
    "InitialDLBWPStart", 0, ...
    "InitialDLBWPSize", 275, ...
    "NCellID", 17, ...
    "ConfigurationEpoch", 1);
end

function value = localTableBandwidth(tableID)
switch string(tableID)
    case "13-0"
        value = 3;
    case {"13-1", "13-2", "13-3", "13-4"}
        value = 10;
    case {"13-5", "13-6"}
        value = 40;
    otherwise
        value = 100;
end
end

function value = localFraction(token)
token = string(token);
parts = split(token, "/");
if numel(parts) == 1
    value = str2double(parts(1));
else
    value = str2double(parts(1)) / str2double(parts(2));
end
end

function localVerifyError(testCase, call, expectedID, vectorID)
try
    call();
    verifyFail(testCase, sprintf( ...
        "Vector %s did not raise %s.", vectorID, expectedID));
catch ME
    verifyEqual(testCase, string(ME.identifier), string(expectedID), ...
        sprintf("Vector %s raised the wrong typed error.", vectorID));
end
end

function root = localVectorRoot()
root = fullfile(fileparts(mfilename("fullpath")), ...
    "vectors", "initial_access");
end
