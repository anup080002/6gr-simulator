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
        verifyEqual(testCase, actual.RBStart, ...
            context.SSBFirstCommonRB - double(row.OffsetRB));
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
    verifyEqual(testCase, height(actual.MonitoringOccasions), 2);
    n0Raw = double(row.O) * 2 + ...
        floor(context.SSBIndex * localFraction(row.M));
    expectedFirst = mod(floor(n0Raw / 20), 2) * 20 + mod(n0Raw, 20);
    verifyEqual(testCase, actual.MonitoringOccasions.AbsoluteSlot, ...
        expectedFirst + [0; 1]);
    verifyEqual(testCase, actual.SearchSpace0.DurationSlots, 2);
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
context.SSBFirstCommonRB = floor((275 - ...
    20 * context.SSBSCSKHz / context.PDCCHSCSKHz) / 2);
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
    "SSBFirstCommonRB", 20, ...
    "NCellID", 17, ...
    "ConfigurationEpoch", 1);
end

function testSSBRelativeFrequencyAndRequiredContext(testCase)
context = localBaseContext();
context.InitialDLBWPStart = 10;
context.InitialDLBWPSize = 100;
context.SSBFirstCommonRB = 43;
context.CORESET0Index = 12; % Table 13-4: 48 RBs, offset 16
actual = sixgr.phy.pdcch.Type0PDCCHResolver(context);
verifyEqual(testCase, actual.RBStart, 27);
verifyEqual(testCase, actual.CORESET0.NumRB, 48);
context.SSBFirstCommonRB = 20; % 20-16 is outside BWP, not 10+16
verifyError(testCase, @() sixgr.phy.pdcch.Type0PDCCHResolver(context), ...
    'sixgr:phy:pdcch:type0_context_not_supported');
context = rmfield(context, 'SSBFirstCommonRB');
verifyError(testCase, @() sixgr.phy.pdcch.Type0PDCCHResolver(context), ...
    'sixgr:phy:pdcch:missing_dci_context');
end

function testMonitoringPairCrossesFrameAndKeepsPeriodicOffset(testCase)
context = localBaseContext();
context.SSBIndex = 5;
context.SearchSpaceZero = 6; % O=7, M=1; n0=19 for 30 kHz
context.SSBFrameNumber = 4;
actual = sixgr.phy.pdcch.Type0PDCCHResolver(context);
verifyEqual(testCase, actual.MonitoringOccasions.AbsoluteSlot, [99; 100]);
verifyEqual(testCase, actual.MonitoringOccasions.SFN, [4; 5]);
verifyEqual(testCase, actual.MonitoringOccasions.Slot, [19; 0]);
verifyEqual(testCase, actual.SearchSpace0.SlotOffset, 19);
more = sixgr.phy.pdcch.Type0PDCCHResolver(context, 'MonitoringFrameCount', 4);
verifyEqual(testCase, more.MonitoringOccasions.AbsoluteSlot, [99; 100; 139; 140]);
verifyNotEqual(testCase, actual.ResolutionSHA256, more.ResolutionSHA256);
end

function testEverySSBMonitoringPair(testCase)
% Independent clause-13 arithmetic across all FR1 SSB candidates, not just
% i_SSB=0 (which hides half-M symbol selection and parity transitions).
offsets = [0 0 2 2 5 5 7 7 0 5 0 0 2 2 5 5];
multipliers = [1 .5 1 .5 1 .5 1 .5 2 2 1 1 1 1 1 1];
for scs = [15 30]
    context = localBaseContext();
    context.SSBSCSKHz = scs;
    context.PDCCHSCSKHz = scs;
    for ssb = 0:7
        context.SSBIndex = ssb;
        for search = 0:15
            context.SearchSpaceZero = search;
            actual = sixgr.phy.pdcch.Type0PDCCHResolver(context);
            spf = 10 * scs / 15;
            raw = offsets(search+1) * scs / 15 + floor(ssb * multipliers(search+1));
            first = mod(floor(raw/spf),2) * spf + mod(raw,spf);
            verifyEqual(testCase, actual.MonitoringOccasions.AbsoluteSlot, first+[0;1]);
            if multipliers(search+1)==.5
                verifyEqual(testCase, actual.MonitoringOccasions.FirstSymbol, ...
                    repmat(mod(ssb,2)*actual.CORESETSymbols,2,1));
            end
        end
    end
end
% n0+1 is now valid: the negative executor must target a genuinely absent
% occasion, not report the second valid slot as a rejection.
negative = sixgr.phy.ia.InitialAccessNegativeCaseExecutor.run( ...
    'TYPE0_WRONG_OCCASION',struct(),struct());
verifyEqual(testCase, negative.Status, "rejected_as_expected");
evidence = sixgr.phy.pdcch.buildType0ArtifactEvidence('type0_table_fixture');
verifyEqual(testCase, height(evidence), 48);
verifyTrue(testCase, all(evidence.EvidenceClass == ...
    "resolved_configuration_not_receiver_detection"));
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
