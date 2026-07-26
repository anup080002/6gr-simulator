function ok = pdcchPhaseCase(caseName)
%PDCCHPHASECASE Shared production assertions for Phase-04 focused tests.

setup6GRSimToolkit("Verbose", false);
name = string(caseName);
switch name
    case "testDCIContextValidation"
        [~, strictCfg] = localRuntime();
        assert(numel(strictCfg.DCIContexts) == 4);
        localAssertError(@() sixgr.phy.pdcch.DCIContext(struct()), ...
            "sixgr:phy:pdcch:missing_dci_context");
    case {"testDCISchema00","testDCISchema01","testDCISchema10","testDCISchema11"}
        formats = containers.Map( ...
            {'testDCISchema00','testDCISchema01','testDCISchema10','testDCISchema11'}, ...
            {'0_0','0_1','1_0','1_1'});
        context = localContext(formats(char(name)));
        schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
        assert(schema.RawBits > 0 && numel(schema.Definitions) >= 9);
        assert(schema.Format == context.Data.DCIFormat);
    case "testDCISizeAlignment"
        T = readtable(localVector("expected_dci_size_alignment_floor.csv"), ...
            "Delimiter", ",", "TextType", "string");
        for ii = 1:height(T)
            [sizes, details] = sixgr.phy.pdcch.dciPayloadSizeBits( ...
                T.BWPSize(ii), ["0_0","1_0"]);
            assert(all(sizes == T.AlignedDCI00Bits(ii)));
            assert(details.DCI00UnpaddedPayloadBits == T.DCI00RawBits(ii));
            assert(details.DCI10PayloadBits == T.DCI10RawBits(ii));
        end
    case "testDCIPackParseRoundTrip"
        for format = ["0_0","0_1","1_0","1_1"]
            context = localContext(format);
            fields = localFields(context, 3);
            tx = sixgr.phy.pdcch.DCIPacker.pack(fields, context);
            rx = sixgr.phy.pdcch.DCIParser.parse(tx.Bits, context);
            assert(isequal(tx.Bits, rx.Bits));
            assert(localFieldMismatch(fields, rx.Fields) == 0);
        end
    case "testDCIWrongContextRejection"
        context = localContext("1_1");
        packed = sixgr.phy.pdcch.DCIPacker.pack(localFields(context, 2), context);
        wrong = localContext("0_1");
        localAssertError(@() sixgr.phy.pdcch.DCIParser.parse(packed.Bits, wrong), ...
            "sixgr:phy:pdcch:payload_length_mismatch");
    case "testDCICRC24CAndRNTIMask"
        localCheckCRC();
    case "testPDCCHPhysicalScrambling"
        localCheckScrambling();
    case "testPDCCHQPSK"
        localCheckQPSK();
    case "testPDCCHPolarCodingAndRateMatching"
        for al = [1 2 4 8 16]
            result = sixgr.phy.pdcch.PDCCHPolarCodec.roundTrip( ...
                int8(mod((0:43).'+al,2)), 4660, al, 8);
            assert(result.Status == "PASS" && result.E == 108*al);
        end
    case {"testCORESETNonInterleavedMapping","testCORESETInterleavedMapping"}
        localCheckCORESET(contains(name, "Interleaved") && ...
            ~contains(name, "NonInterleaved"));
    case "testPDCCHDMRS"
        localCheckDMRS();
    case "testPDCCHResourceOwnership"
        definition = localCORESETDefinition("noninterleaved");
        ownership = sixgr.phy.pdcch.PDCCHResourceOwnershipMap.build(definition);
        assert(ownership.CollisionCount == 0);
        assert(ownership.DataRECount == definition.Data.NREG*9);
        assert(ownership.DMRSRECount == definition.Data.NREG*3);
    case "testSearchSpaceMonitoringOccasions"
        localCheckMonitoring();
    case {"testPDCCHCandidateEnumerationCSS","testPDCCHCandidateEnumerationUSS"}
        localCheckCandidates(erase(name, "testPDCCHCandidateEnumeration"));
    case "testPDCCHMonitoringBudget"
        candidate = sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
            "CSS", 24, 1, 8, 1, 4660, 0, 0);
        result = sixgr.phy.pdcch.PDCCHMonitoringBudget.validate(30, candidate.Rows);
        assert(result.Status == "PASS");
        rows = repmat(candidate.Rows, 5, 1);
        localAssertError(@() sixgr.phy.pdcch.PDCCHMonitoringBudget.validate(30, rows), ...
            "sixgr:phy:pdcch:monitoring_budget_exceeded");
    case "testType0CORESETTables"
        localCheckType0CORESET();
    case "testType0MonitoringOccasions"
        localCheckType0Monitoring();
    case "testPDCCHRNTIProcedureMatrix"
        localCheckRNTI();
    case "testPDCCHBlindSearchNoOracle"
        result = localBlind("1_0", 4, 35, true, "normal");
        assert(result.Detected && ~result.UsedKnownLocation && ...
            ~result.UsedOracleTiming);
        [~, strictCfg] = localRuntime();
        localAssertError(@() sixgr.phy.pdcch.PDCCHReceiver.receive( ...
            zeros(10,1), strictCfg, "SynchronizationState", ...
            struct("CandidateIndex",0)), ...
            "sixgr:phy:pdcch:known_location_forbidden_in_blind_profile");
    case "testPDCCHBlindSearchAllAL"
        for al = [1 2 4 8 16]
            assert(localBlind("1_0", al, 35, true, "normal").Detected);
        end
    case "testPDCCHBlindSearchFormats001011"
        for format = ["0_0","0_1","1_0","1_1"]
            assert(localBlind(format, 4, 35, true, "normal").Detected);
        end
    case "testPDCCHWrongRNTI"
        assert(~localBlind("1_0", 4, 35, true, "wrong_rnti").Detected);
    case "testPDCCHWrongFormatAndSize"
        assert(~localBlind("1_1", 4, 35, true, "wrong_format").Detected);
    case "testPDCCHNoSignalFalseAlarm"
        result = localBlind("1_0", 4, 35, false, "normal");
        assert(~result.Detected && result.ValidHypothesisCount == 0);
    case "testPDCCHLowSNRDetection"
        low = localBlind("1_0", 1, -12, true, "normal");
        high = localBlind("1_0", 1, 35, true, "normal");
        assert(islogical(low.Detected) && high.Detected);
    case "testPDCCHTDLAndCDL"
        tx = localBlindFixture("1_0", 4);
        ofdmInfo = nrOFDMInfo(tx.Carrier);
        tdl = nrTDLChannel;
        tdl.DelayProfile = "TDL-C";
        tdl.SampleRate = ofdmInfo.SampleRate;
        tdl.NumTransmitAntennas = 1;
        tdl.NumReceiveAntennas = 1;
        y1 = tdl(tx.Waveform);
        cdl = nrCDLChannel;
        cdl.DelayProfile = "CDL-D";
        cdl.SampleRate = ofdmInfo.SampleRate;
        cdl.TransmitAntennaArray.Size = [1 1 1 1 1];
        cdl.ReceiveAntennaArray.Size = [1 1 1 1 1];
        y2 = cdl(tx.Waveform);
        assert(~isempty(y1) && ~isempty(y2) && ...
            localBlind("1_0",4,35,true,"normal").Detected);
    case "testPDCCHCFOAndTiming"
        result = localBlind("1_0", 4, 35, true, "small_cfo");
        assert(result.Detected);
    case "testPDCCHBWPAndCrossCarrier"
        localCheckBWPAndCarrier();
    case "testPDCCHBeamMonitoring"
        beam = localBeamState();
        beam.validateForSlot(0);
        blocked = beam.Data;
        blocked.BeamBlocked = true;
        bad = sixgr.phy.pdcch.ControlBeamState(blocked);
        localAssertError(@() bad.validateForSlot(0), ...
            "sixgr:phy:pdcch:inactive_tci_state");
    case "testDecodedDCIGrantAuthority"
        localCheckGrantAuthority();
    case "testStrictPDCCHCannotImportStudyModules"
        result = sixgr.phy.pdcch.assertStrictDependencyIsolation();
        assert(result.ViolationCount == 0);
    case "testPDCCHArtifactGeneration"
        out = tempname;
        summary = sixgr.phy.pdcch.runPDCCHPhaseValidation( ...
            "VectorRoot", fileparts(localVector("README_PACK.md")), ...
            "OutputDir", out, "SeedList", 11, "Strict", true, ...
            "FastTestMode", true);
        assert(summary.Passed);
        assert(exist(fullfile(out, "pdcch_dci_schema_matrix.csv"), "file") == 2);
    otherwise
        error("sixgr:test:pdcch:UnknownCase", "Unknown PDCCH phase test %s.", name);
end
ok = true;
end

function [cfg, strictCfg] = localRuntime()
persistent cachedCfg cachedStrict
if isempty(cachedCfg)
    root = fileparts(fileparts(mfilename("fullpath")));
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
        "simulator", "configs", "scenarios", "master_geometry_based.yaml"));
    cachedCfg = sixgr.lls6g.buildInternalConfig(scfg, tempdir);
    cachedStrict = sixgr.phy.pdcch.buildPDCCHConfigFromScenario(cachedCfg);
end
cfg = cachedCfg;
strictCfg = cachedStrict;
end

function context = localContext(format)
[~, strictCfg] = localRuntime();
formats = strings(numel(strictCfg.DCIContexts),1);
for ii = 1:numel(formats)
    formats(ii) = strictCfg.DCIContexts{ii}.Data.DCIFormat;
end
idx = find(formats == string(format), 1);
assert(~isempty(idx));
context = strictCfg.DCIContexts{idx};
end

function fields = localFields(context, variant)
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields = struct();
for ii = 1:numel(schema.Definitions)
    definition = schema.Definitions(ii);
    fields.(char(definition.Name)) = definition.ValueMin;
end
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode( ...
    mod(variant,5), 12 + mod(variant,4), ...
    localBWPSize(context));
fields.time_resource_assignment = mod(variant, 4);
fields.mcs = 5 + mod(variant, 12);
fields.harq_process = mod(variant, context.Data.HARQProcessCount);
if isfield(fields, "transmission_configuration_indication")
    fields.transmission_configuration_indication = ...
        context.Data.ActiveTCIStateID;
end
end

function value = localBWPSize(context)
if startsWith(context.Data.DCIFormat, "0_")
    value = context.Data.ActiveULBWPSize;
else
    value = context.Data.ActiveDLBWPSize;
end
end

function count = localFieldMismatch(a, b)
names = string(fieldnames(a));
count = 0;
for ii = 1:numel(names)
    count = count + ~isequal(double(a.(names(ii))), double(b.(names(ii))));
end
end

function path = localVector(name)
root = fileparts(fileparts(mfilename("fullpath")));
path = fullfile(root, "tests", "vectors", "pdcch", name);
end

function localCheckCRC()
path = localVector("expected_pdcch_crc_vectors.csv");
options = detectImportOptions(path, "Delimiter", ",");
options = setvartype(options, ...
    ["RNTI","PayloadBits","CRC24CBits","MaskedCodewordBits"], "string");
T = readtable(path, options);
for ii = 1:height(T)
    bits = int8(char(T.PayloadBits(ii)).' - '0');
    rnti = double(hex2dec(extractAfter(T.RNTI(ii),2)));
    result = sixgr.phy.pdcch.DCICRC24C.encode(bits, rnti);
    assert(join(string(result.CRC24CBits.'),"") == T.CRC24CBits(ii));
    assert(join(string(result.MaskedCodewordBits.'),"") == T.MaskedCodewordBits(ii));
    [passed,~,~] = sixgr.phy.pdcch.DCICRC24C.check( ...
        result.MaskedCodewordBits, rnti);
    [wrong,~,~] = sixgr.phy.pdcch.DCICRC24C.check( ...
        result.MaskedCodewordBits, mod(rnti+1,65536));
    assert(passed && ~wrong);
end
end

function localCheckScrambling()
T = readtable(localVector("expected_pdcch_scrambling_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(T)
    e = T.E(ii);
    bits = int8(mod((0:e-1).'+ii, 2));
    rnti = double(T.NRNTI(ii));
    result = sixgr.phy.pdcch.PDCCHScrambler.scramble(bits, T.NID(ii), rnti);
    assert(result.CInit == T.CInit(ii));
    assert(result.SequenceSHA256 == T.SequenceSHA256(ii));
end
end

function localCheckQPSK()
T = readtable(localVector("expected_pdcch_qpsk_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(T)
    symbol = sixgr.phy.pdcch.PDCCHQPSK.modulate( ...
        int8([T.Bit0(ii);T.Bit1(ii)]));
    assert(abs(real(symbol)-T.Real(ii)) < 1e-6);
    assert(abs(imag(symbol)-T.Imag(ii)) < 1e-6);
end
end

function definition = localCORESETDefinition(mapping)
if mapping == "interleaved"
    bundle = 2; interleaver = 2;
else
    bundle = 6; interleaver = 0;
end
definition = sixgr.phy.pdcch.CORESETDefinition(struct( ...
    "CORESETID",1,"NRB",24,"DurationSymbols",2, ...
    "MappingType",mapping,"REGBundleSize",bundle, ...
    "InterleaverSize",interleaver,"ShiftIndex",1,"RBStart",0, ...
    "StartSymbol",0,"PrecoderGranularity","sameAsREG-bundle"));
end

function localCheckCORESET(interleavedOnly)
cases = readtable(localVector("pdcch_coreset_mapping_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
expected = readtable(localVector("expected_coreset_reg_cce_mapping.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(cases)
    isInterleaved = lower(cases.MappingType(ii)) == "interleaved";
    if isInterleaved ~= interleavedOnly || cases.ExpectedOutcome(ii) ~= "PASS"
        continue;
    end
    definition = sixgr.phy.pdcch.CORESETDefinition(struct( ...
        "CORESETID",1,"NRB",cases.NRB(ii), ...
        "DurationSymbols",cases.DurationSymbols(ii), ...
        "MappingType",cases.MappingType(ii), ...
        "REGBundleSize",cases.REGBundleSize(ii), ...
        "InterleaverSize",cases.InterleaverSize(ii), ...
        "ShiftIndex",cases.ShiftIndex(ii),"RBStart",0,"StartSymbol",0, ...
        "PrecoderGranularity","sameAsREG-bundle"));
    actual = sixgr.phy.pdcch.CORESETMapper.map(definition);
    exp = expected(expected.CaseID == cases.CaseID(ii),:);
    assert(height(exp) == height(actual.Table));
    assert(all(string(actual.Table.REGIndices) == exp.REGIndices));
end
end

function localCheckDMRS()
input = readtable(localVector("pdcch_dmrs_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
expected = readtable(localVector("expected_pdcch_dmrs_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(expected)
    source = input(input.CaseID == expected.VectorID(ii),:);
    attempted = str2double(split(source.AttemptedPRBs, "|")).';
    result = sixgr.phy.pdcch.PDCCHDMRS.generate(struct( ...
        "NumerologyMu", source.NumerologyMu, ...
        "Slot", source.SlotWithinFrame, ...
        "Symbol", source.SymbolWithinSlot, "NID", source.NID, ...
        "CORESETRBs", source.CORESETRBs, ...
        "PrecoderGranularity", source.PrecoderGranularity, ...
        "AttemptedPRBs", attempted));
    assert(result.CInit == expected.CInit(ii));
    assert(result.SequenceBitsSHA256 == expected.SequenceBitsSHA256(ii));
    assert(result.IndexSHA256 == expected.MappedIndexSHA256(ii));
end
end

function localCheckMonitoring()
input = readtable(localVector("pdcch_monitoring_occasion_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string", "VariableNamingRule", "preserve");
expected = readtable(localVector("expected_pdcch_monitoring_occasions.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(expected)
    source = input(input.CaseID == expected.CaseID(ii),:);
    bitmap = sprintf("%014.0f", source.MonitoringSymbolsWithinSlot);
    ss = sixgr.phy.pdcch.SearchSpaceDefinition(struct( ...
        "SearchSpaceID",1,"SearchSpaceType","CSS","CORESETID",1, ...
        "PeriodSlots",source.PeriodSlots,"OffsetSlots",source.OffsetSlots, ...
        "DurationSlots",source.DurationSlots, ...
        "MonitoringSymbolsWithinSlot",bitmap,"NumCandidates",[1 0 0 0 0], ...
        "MonitoredFormats","1_0","AllowedRNTITypes","C-RNTI","NCI",0));
    actual = sixgr.phy.pdcch.MonitoringOccasionResolver.resolve( ...
        ss, source.WindowSlots);
    assert(actual.MonitoredSlotCount == expected.MonitoredSlotCount(ii));
    assert(join(string(actual.MonitoredSlots),"|") == expected.MonitoredSlots(ii));
end
end

function localCheckCandidates(space)
input = readtable(localVector("pdcch_candidate_enumeration_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
expected = readtable(localVector("expected_pdcch_candidate_enumeration.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(input)
    if upper(input.SearchSpaceType(ii)) ~= upper(space) || ...
            input.ExpectedOutcome(ii) ~= "PASS"
        continue;
    end
    rnti = double(input.RNTI(ii));
    actual = sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
        input.SearchSpaceType(ii), input.NCCE(ii), ...
        input.AggregationLevel(ii), input.NumCandidates(ii), ...
        input.CORESETID(ii), rnti, input.Slot(ii), input.NCI(ii));
    exp = expected(expected.CaseID == input.CaseID(ii),:);
    assert(join(string(actual.FirstCCEIndices),"|") == exp.FirstCCEIndices);
    assert(actual.Y == exp.Y);
end
end

function localCheckType0CORESET()
T = readtable(localVector("pdcch_type0_css_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(T)
    kSSB = double(T.KSSBClass(ii) == "positive");
    if T.ExpectedOutcome(ii) == "PASS"
        row = sixgr.phy.pdcch.Type0TableCatalog.coreset0( ...
            T.Table(ii), T.ControlResourceSetZero(ii), kSSB);
        assert(row.CORESETRBs == T.CORESETRBs(ii));
        assert(row.CORESETSymbols == T.CORESETSymbols(ii));
        assert(row.OffsetRB == T.OffsetRB(ii));
    else
        localAssertError(@() sixgr.phy.pdcch.Type0TableCatalog.coreset0( ...
            T.Table(ii), T.ControlResourceSetZero(ii), kSSB), ...
            T.ExpectedError(ii));
    end
end
end

function localCheckType0Monitoring()
type0Path = localVector("expected_type0_monitoring_tables.csv");
type0Options = detectImportOptions(type0Path, "Delimiter", ",");
type0Options = setvartype(type0Options, ...
    ["Table","PDCCHSCSkHz","ExpectedOutcome","ExpectedError"], "string");
T = readtable(type0Path, type0Options);
for ii = 1:height(T)
    scsToken = split(T.PDCCHSCSkHz(ii),"|");
    scs = str2double(scsToken(1));
    if T.ExpectedOutcome(ii) == "PASS"
        row = sixgr.phy.pdcch.Type0TableCatalog.searchSpace0( ...
            T.SearchSpaceZero(ii), "TableID", T.Table(ii), ...
            "PDCCHSCSKHz", scs);
        assert(abs(row.O - T.O(ii)) < 1e-12);
        assert(row.SearchSpaceSetsPerSlot == T.SearchSpaceSetsPerSlot(ii));
    else
        localAssertError(@() ...
            sixgr.phy.pdcch.Type0TableCatalog.searchSpace0( ...
            T.SearchSpaceZero(ii), "TableID", T.Table(ii), ...
            "PDCCHSCSKHz", scs), T.ExpectedError(ii));
    end
end
P = readtable(localVector("pdcch_type0_pattern23_monitoring_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(P)
    if P.ExpectedOutcome(ii) == "PASS"
        row = sixgr.phy.pdcch.Type0TableCatalog.pattern23Monitoring( ...
            P.Table(ii), P.SearchSpaceZero(ii), 0);
        assert(row.MultiplexingPattern == P.MultiplexingPattern(ii));
    else
        localAssertError(@() ...
            sixgr.phy.pdcch.Type0TableCatalog.pattern23Monitoring( ...
            P.Table(ii), P.SearchSpaceZero(ii), 0), P.ExpectedError(ii));
    end
end
end

function localCheckRNTI()
T = readtable(localVector("pdcch_rnti_procedure_test_vectors.csv"), ...
    "Delimiter", ",", "TextType", "string");
for ii = 1:height(T)
    procedure = sixgr.phy.pdcch.RNTIProcedureRegistry.resolve(T.RNTIType(ii));
    if T.ExpectedOutcome(ii) == "PASS"
        assert(procedure.Procedure == T.Procedure(ii));
    end
    if lower(string(T.CorePhaseRequired(ii))) == "true"
        spaces = split(T.AllowedSearchSpaces(ii),"|");
        formats = split(T.AllowedDCIFormats(ii),"|");
        value = localRNTIValue(T.RNTIType(ii));
        if T.ExpectedOutcome(ii) == "PASS"
            sixgr.phy.pdcch.RNTIProcedureRegistry.validate( ...
                T.RNTIType(ii), value, spaces(1), formats(1));
        else
            localAssertError(@() ...
                sixgr.phy.pdcch.RNTIProcedureRegistry.validate( ...
                T.RNTIType(ii), value, spaces(1), formats(1)), ...
                "sixgr:phy:pdcch:invalid_rnti_procedure");
        end
    end
end
end

function value = localRNTIValue(type)
switch string(type)
    case "SI-RNTI"
        value = 65535;
    case "P-RNTI"
        value = 65534;
    otherwise
        value = 4660;
end
end

function result = localBlind(format, al, snrDb, signalPresent, variant)
persistent cache
if isempty(cache)
    cache = containers.Map("KeyType","char","ValueType","any");
end
key = sprintf("%s_%d_%g_%d_%s", format, al, snrDb, signalPresent, variant);
if isKey(cache, key)
    result = cache(key);
    return;
end
[tx, strictCfg] = localBlindFixture(format, al);
rxWaveform = tx.Waveform;
signalPower = mean(abs(rxWaveform(:)).^2);
noiseVariance = max(signalPower / 10^(snrDb/10), eps);
rng(1701 + al + sum(double(char(format))) + round(snrDb), "twister");
noise = sqrt(noiseVariance/2) * (randn(size(rxWaveform)) + ...
    1i*randn(size(rxWaveform)));
if signalPresent
    rxWaveform = rxWaveform + noise;
else
    rxWaveform = noise;
end
if variant == "wrong_rnti"
    data = strictCfg.DCIContexts{1}.Data;
    data.RNTIValue = data.RNTIValue + 1;
    strictCfg.DCIContexts = {sixgr.phy.pdcch.DCIContext(data)};
elseif variant == "wrong_format"
    alternatives = setdiff(["0_0","0_1","1_0","1_1"], string(format));
    strictCfg.DCIContexts = {localContext(alternatives(1))};
elseif variant == "small_cfo"
    ofdmInfo = nrOFDMInfo(tx.Carrier);
    sampleRate = ofdmInfo.SampleRate;
    n = (0:size(rxWaveform,1)-1).';
    rxWaveform = rxWaveform .* exp(1i*2*pi*5*n/sampleRate);
end
result = sixgr.phy.pdcch.PDCCHReceiver.receive( ...
    rxWaveform, strictCfg, "NoiseVar", noiseVariance, ...
    "SynchronizationState", struct( ...
    "SlotBoundaryOffsetSamples",0,"Source","declared_aligned_slot"));
cache(key) = result;
end

function [tx, strictCfg] = localBlindFixture(format, al)
[~, base] = localRuntime();
context = localContext(format);
strictCfg = base;
strictCfg.DCIContexts = {context};
counts = zeros(1,5);
idx = find([1 2 4 8 16] == al);
maxCounts = [8 8 4 2 1];
counts(idx) = min(maxCounts(idx), ...
    floor(strictCfg.CORESETDefinition.Data.NCCE/al));
strictCfg.NumCandidatesAL1 = counts(1);
strictCfg.NumCandidatesAL2 = counts(2);
strictCfg.NumCandidatesAL4 = counts(3);
strictCfg.NumCandidatesAL8 = counts(4);
strictCfg.NumCandidatesAL16 = counts(5);
tx = sixgr.phy.pdcch.PDCCHTransmitter.transmit( ...
    strictCfg, localFields(context, al), context, ...
    "AggregationLevel", al, "CandidateIndex", 0);
end

function localCheckBWPAndCarrier()
binding = sixgr.phy.pdcch.ControlBWPContext(struct( ...
    "ControlServingCell",0,"ControlCarrier",0,"ControlBWP",0, ...
    "ScheduledServingCell",0,"ScheduledCarrier",1,"ScheduledBWP",1, ...
    "SearchSpaceID",1,"CORESETID",1,"ConfigurationEpoch",7));
map = struct("Indicator",1,"ScheduledCarrier",1);
cross = sixgr.phy.pdcch.CrossCarrierControlContext(struct( ...
    "CarrierIndicatorPresent",true,"CarrierIndicatorWidth",1, ...
    "CarrierIndicatorMap",map,"ControlCarrier",0,"ScheduledCarrier",1));
assert(cross.resolve(1) == 1 && strlength(binding.Digest) == 64);
localAssertError(@() cross.resolve(0), ...
    "sixgr:phy:pdcch:wrong_scheduled_carrier");
end

function beam = localBeamState()
beam = sixgr.phy.pdcch.ControlBeamState(struct( ...
    "TCIStateID",0,"TCIActive",true,"QCLSourceType","SSB", ...
    "QCLSourceID",0,"BeamID",0,"BeamActive",true,"BeamBlocked",false, ...
    "MeasurementSlot",0,"MeasurementMaxAgeSlots",20, ...
    "MeasurementProvenance","observed_ssb_rsrp"));
end

function localCheckGrantAuthority()
result = localBlind("1_0",4,35,true,"normal");
event = result.DecodedDCIEvent;
e = event.Data;
binding = sixgr.phy.pdcch.ControlBWPContext(struct( ...
    "ControlServingCell",e.ControlServingCell, ...
    "ControlCarrier",e.ControlCarrier,"ControlBWP",e.ControlBWP, ...
    "ScheduledServingCell",e.ScheduledServingCell, ...
    "ScheduledCarrier",e.ScheduledCarrier,"ScheduledBWP",e.ScheduledBWP, ...
    "SearchSpaceID",e.SearchSpaceID,"CORESETID",e.CORESETID, ...
    "ConfigurationEpoch",e.ConfigurationEpoch));
cross = sixgr.phy.pdcch.CrossCarrierControlContext(struct( ...
    "CarrierIndicatorPresent",false,"CarrierIndicatorWidth",0, ...
    "CarrierIndicatorMap",struct([]),"ControlCarrier",e.ControlCarrier, ...
    "ScheduledCarrier",e.ScheduledCarrier));
state = struct("ConfigurationEpoch",e.ConfigurationEpoch, ...
    "ActiveServingCell",e.ScheduledServingCell, ...
    "ActiveCarrier",e.ScheduledCarrier,"ActiveDLBWP",e.ScheduledBWP, ...
    "ActiveULBWP",e.ScheduledBWP,"DLMCSTable","qam64_table1", ...
    "ULMCSTable","qam64_table1","ControlBWPContext",binding, ...
    "CrossCarrierControlContext",cross,"ControlBeamState",localBeamState());
one = sixgr.phy.pdcch.DecodedGrantMaterializer.materialize(event, state);
state.ConfiguredOracleGrant = struct("MCS",31,"PRBStart",200);
two = sixgr.phy.pdcch.DecodedGrantMaterializer.materialize(event, state);
assert(one.AssignmentDigest == two.AssignmentDigest);
stale = state;
stale.ConfigurationEpoch = stale.ConfigurationEpoch + 1;
localAssertError(@() sixgr.phy.pdcch.DecodedGrantMaterializer.materialize( ...
    event, stale), "sixgr:phy:pdcch:stale_bwp_context");
end

function localAssertError(fcn, identifier)
observed = "";
try
    fcn();
catch ME
    observed = string(ME.identifier);
end
assert(observed == string(identifier), ...
    "Expected %s, observed %s.", string(identifier), observed);
end
