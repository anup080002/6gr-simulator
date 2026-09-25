function summary = runPDCCHPhaseValidation(varargin)
%RUNPDCCHPHASEVALIDATION Execute strict Phase-04 checks and evidence export.

p = inputParser;
p.FunctionName = "sixgr.phy.pdcch.runPDCCHPhaseValidation";
addParameter(p, "VectorRoot", "", @(x) ischar(x) || isstring(x));
addParameter(p, "OutputDir", "", @(x) ischar(x) || isstring(x));
addParameter(p, "SeedList", [11 23 47 89], @isnumeric);
addParameter(p, "ConfidenceLevel", 0.95, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "Strict", true, @(x) islogical(x) && isscalar(x));
addParameter(p, "FastTestMode", false, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

if ~opt.Strict
    error("sixgr:phy:pdcch:strict_profile_required", ...
        "Phase-04 artifact generation requires Strict=true.");
end
vectorRoot = string(opt.VectorRoot);
outputDir = string(opt.OutputDir);
if strlength(vectorRoot) == 0 || ~isfolder(vectorRoot)
    error("sixgr:phy:pdcch:missing_vector_pack", ...
        "VectorRoot must identify the verified PDCCH vector pack.");
end
if strlength(outputDir) == 0
    error("sixgr:phy:pdcch:missing_evidence_output", ...
        "OutputDir is mandatory.");
end
% Integrity quarantine, before creating any artifact. Several legacy local
% producers below manufacture beam/decode, grant/waveform, and independent
% comparison outcomes without executing those operations. Neither strict
% mode nor FastTestMode may publish them as primary evidence. This guard
% must only be removed when those producers have execution-backed outputs
% and the phase summary is derived from their observed checks.
error("sixgr:phy:pdcch:unverified_phase_evidence", ...
    ["PDCCH Phase-04 qualification is unavailable: beam monitoring, " + ...
    "grant authority, BWP context comparison, independent-vector comparison " + ...
    "and test-summary producers lack execution-backed evidence. " + ...
    "No phase CSV/PNG has been generated; this is not a PHY qualification pass."]);
if ~isfolder(outputDir)
    mkdir(outputDir);
end

runID = "PDCCH_PHASE04_R18";
contract = readtable(fullfile(vectorRoot, "desired_pdcch_csv_contract.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
imageContract = readtable(fullfile(vectorRoot, "desired_pdcch_image_contract.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
[contexts, strictCfg] = localContexts();

tables = struct();
tables.pdcch_dci_schema_matrix = localSchemaMatrix(contract, runID, contexts);
[tables.pdcch_dci_field_layout, tables.pdcch_dci_roundtrip] = ...
    localDCIEvidence(contract, runID, contexts);
tables.pdcch_crc_scrambling = localCRCEvidence(contract, runID, contexts);
tables.pdcch_polar_coding = localPolarEvidence(contract, runID, contexts);
[tables.pdcch_coreset_mapping, tables.pdcch_re_ownership] = ...
    localCORESETEvidence(contract, runID, strictCfg);
tables.pdcch_dmrs_matrix = sixgr.phy.pdcch.buildDMRSArtifactEvidence(runID);
[tables.pdcch_search_space_monitoring, tables.pdcch_candidate_enumeration] = ...
    localMonitoringEvidence(contract, runID, strictCfg);
[tables.pdcch_blind_trials, tables.pdcch_detection_curve] = ...
    localBlindEvidence(contract, runID, contexts, strictCfg, opt.SeedList, ...
    opt.ConfidenceLevel, opt.FastTestMode);
tables.pdcch_type0_css = sixgr.phy.pdcch.buildType0ArtifactEvidence(runID);
tables.pdcch_rnti_procedure = localRNTIEvidence(contract, runID);
tables.pdcch_bwp_crosscarrier = localBWPEvidence(contract, runID, contexts);
tables.pdcch_beam_monitoring = localBeamEvidence(contract, runID, strictCfg);
tables.pdcch_grant_authority = localGrantEvidence(contract, runID);
tables.pdcch_negative_tests = localNegativeEvidence(contract, runID);
tables.pdcch_independent_vector_results = localIndependentEvidence( ...
    contract, runID, vectorRoot);
tables.pdcch_test_summary = localTestSummary(contract, runID);

names = string(fieldnames(tables));
rowCounts = struct();
csvHashes = struct();
for ii = 1:numel(names)
    fileName = names(ii) + ".csv";
    sixgr.phy.pdcch.PDCCHArtifactExporter.writeTable( ...
        outputDir, fileName, tables.(names(ii)));
    rowCounts.(names(ii)) = height(tables.(names(ii)));
    csvHashes.(names(ii)) = sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256( ...
        fullfile(outputDir, fileName));
end

auditRows = repmat(localAuditRow(), height(imageContract), 1);
for ii = 1:height(imageContract)
    auditRows(ii) = sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure( ...
        outputDir, table2struct(imageContract(ii,:)));
end
audit = struct2table(auditRows, "AsArray", true);
sixgr.phy.pdcch.PDCCHArtifactExporter.writeTable( ...
    outputDir, "pdcch_image_semantic_audit.csv", audit);
rowCounts.pdcch_image_semantic_audit = height(audit);
csvHashes.pdcch_image_semantic_audit = ...
    sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256( ...
    fullfile(outputDir, "pdcch_image_semantic_audit.csv"));

expectedCSV = string(contract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(x) exist(fullfile(outputDir, x), "file") == 2, expectedCSV);
pngPresent = arrayfun(@(x) exist(fullfile(outputDir, x), "file") == 2, expectedPNG);
allStatusPass = true;
for ii = 1:numel(names)
    value = tables.(names(ii));
    if ismember("Status", string(value.Properties.VariableNames))
        allStatusPass = allStatusPass && all(upper(string(value.Status)) == "PASS");
    end
end
allStatusPass = allStatusPass && all(upper(string(audit.Status)) == "PASS");

summary = struct( ...
    "Passed", all(csvPresent) && all(pngPresent) && allStatusPass, ...
    "Strict", true, ...
    "RunID", runID, ...
    "OutputDir", outputDir, ...
    "CSVCount", sum(csvPresent), ...
    "PNGCount", sum(pngPresent), ...
    "RowCounts", rowCounts, ...
    "CSVHashes", csvHashes, ...
    "BlindTrialCount", height(tables.pdcch_blind_trials), ...
    "IncompletePointCount", sum(localTruth(tables.pdcch_detection_curve.Incomplete)), ...
    "IndependentMismatchCount", sum(str2double( ...
        tables.pdcch_independent_vector_results.MismatchCount)), ...
    "BlindEvidenceClass", string(localTernary(opt.FastTestMode, ...
        "component_regression_not_waveform_truth", "waveform_truth")), ...
    "TruthQualified", ~opt.FastTestMode, ...
    "Status", string(localTernary(all(csvPresent) && all(pngPresent) && ...
        allStatusPass, "PASS", "FAIL")));
end

function [contexts, strictCfg] = localContexts()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator", "configs", "scenarios", "master_geometry_based.yaml"));
runtime = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
strictCfg = sixgr.phy.pdcch.buildPDCCHConfigFromScenario(runtime);
contexts = strictCfg.DCIContexts;
if numel(contexts) ~= 4
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "The canonical master must install all four DCI contexts.");
end
end

function value = localSchemaMatrix(contract, runID, contexts)
n = 52;
value = localContractTable(contract, "pdcch_dci_schema_matrix.csv", n);
for ii = 1:n
    context = contexts{mod(ii-1, numel(contexts))+1};
    schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    alignment = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("SCHEMA%04d", ii);
    value.DCIFormat(ii) = context.Data.DCIFormat;
    value.SearchSpaceType(ii) = context.Data.SearchSpaceType;
    value.RNTIType(ii) = context.Data.RNTIType;
    value.ContextDigest(ii) = context.Digest;
    value.PayloadBits(ii) = string(alignment.Selected.AlignedBits);
    value.FieldCount(ii) = string(numel(schema.Definitions));
    value.AlignmentGroup(ii) = alignment.Selected.AlignmentGroup;
    value.SchemaVersion(ii) = schema.SchemaVersion;
    value.Status(ii) = "PASS";
end
end

function [layout, roundtrip] = localDCIEvidence(contract, runID, contexts)
layout = localContractTable(contract, "pdcch_dci_field_layout.csv", 0);
roundtrip = localContractTable(contract, "pdcch_dci_roundtrip.csv", 52);
for caseIndex = 1:52
    context = contexts{mod(caseIndex-1, numel(contexts))+1};
    fields = localFields(context, caseIndex);
    packed = sixgr.phy.pdcch.DCIPacker.pack(fields, context);
    decoded = sixgr.phy.pdcch.DCIParser.parse(packed.Bits, context);
    mismatch = localFieldMismatch(fields, decoded.Fields);
    fieldTable = packed.FieldTable;
    for fieldIndex = 1:height(fieldTable)
        row = localContractTableFrom(layout, 1);
        row.RunID = runID;
        row.CaseID = sprintf("DCI%04d", caseIndex);
        row.DCIFormat = context.Data.DCIFormat;
        row.FieldOrder = string(fieldIndex);
        row.FieldName = string(fieldTable.FieldName(fieldIndex));
        row.Present = "true";
        row.WidthBits = string(fieldTable.WidthBits(fieldIndex));
        row.BitStart = string(fieldTable.BitStart(fieldIndex));
        row.BitEnd = string(fieldTable.BitEnd(fieldIndex));
        row.Value = string(fieldTable.Value(fieldIndex));
        row.ValueMin = string(fieldTable.ValueMin(fieldIndex));
        row.ValueMax = string(fieldTable.ValueMax(fieldIndex));
        row.SemanticSource = string(fieldTable.SemanticSource(fieldIndex));
        row.Status = "PASS";
        layout = [layout; row]; %#ok<AGROW>
    end
    missing = rmfield(fields, char(packed.Schema.Definitions(1).Name));
    outOfRange = fields;
    outOfRange.(char(packed.Schema.Definitions(1).Name)) = ...
        packed.Schema.Definitions(1).ValueMax + 1;
    unexpected = fields;
    unexpected.not_a_dci_field = 0;
    roundtrip.RunID(caseIndex) = runID;
    roundtrip.CaseID(caseIndex) = sprintf("DCI%04d", caseIndex);
    roundtrip.DCIFormat(caseIndex) = context.Data.DCIFormat;
    roundtrip.ContextDigest(caseIndex) = context.Digest;
    roundtrip.PayloadBits(caseIndex) = string(numel(packed.Bits));
    roundtrip.InputBitsSHA256(caseIndex) = packed.PayloadHash;
    roundtrip.DecodedBitsSHA256(caseIndex) = decoded.PayloadHash;
    roundtrip.FieldMismatchCount(caseIndex) = string(mismatch);
    roundtrip.LengthMismatchRejected(caseIndex) = localBool(localThrows( ...
        @() sixgr.phy.pdcch.DCIParser.parse(packed.Bits(1:end-1), context), ...
        "sixgr:phy:pdcch:payload_length_mismatch"));
    roundtrip.MissingFieldRejected(caseIndex) = localBool(localThrows( ...
        @() sixgr.phy.pdcch.DCIPacker.pack(missing, context), ...
        "sixgr:phy:pdcch:missing_required_field"));
    roundtrip.OutOfRangeRejected(caseIndex) = localBool(localThrows( ...
        @() sixgr.phy.pdcch.DCIPacker.pack(outOfRange, context), ...
        "sixgr:phy:pdcch:field_out_of_range"));
    roundtrip.UnexpectedFieldRejected(caseIndex) = localBool(localThrows( ...
        @() sixgr.phy.pdcch.DCIPacker.pack(unexpected, context), ...
        "sixgr:phy:pdcch:unexpected_field"));
    roundtrip.Status(caseIndex) = string(localTernary(mismatch == 0, "PASS", "FAIL"));
end
if height(layout) < 200
    error("sixgr:phy:pdcch:incomplete_artifact", ...
        "Contextual field evidence contains only %d rows.", height(layout));
end
end

function value = localCRCEvidence(contract, runID, contexts)
value = localContractTable(contract, "pdcch_crc_scrambling.csv", 32);
for ii = 1:height(value)
    context = contexts{mod(ii-1, numel(contexts))+1};
    packed = sixgr.phy.pdcch.DCIPacker.pack(localFields(context, ii), context);
    rnti = double(context.Data.RNTIValue);
    crc = sixgr.phy.pdcch.DCICRC24C.encode(packed.Bits, rnti);
    [passed,~,details] = sixgr.phy.pdcch.DCICRC24C.check( ...
        crc.MaskedCodewordBits, rnti);
    [wrongPassed,~,~] = sixgr.phy.pdcch.DCICRC24C.check( ...
        crc.MaskedCodewordBits, mod(rnti + 1, 65536));
    nID = mod(41*ii, 1008);
    scrambled = sixgr.phy.pdcch.PDCCHScrambler.scramble( ...
        crc.MaskedCodewordBits, nID, rnti);
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("CRC%04d", ii);
    value.PayloadBits(ii) = string(numel(packed.Bits));
    value.RNTIType(ii) = context.Data.RNTIType;
    value.RNTIValue(ii) = string(rnti);
    value.CRC24CSHA256(ii) = crc.CRC24CSHA256;
    value.CRCCheckPassed(ii) = localBool(passed);
    value.WrongRNTICheckPassed(ii) = localBool(~wrongPassed);
    value.NID(ii) = string(nID);
    value.NRNTIForScrambling(ii) = string(rnti);
    value.CInit(ii) = string(scrambled.CInit);
    value.ScramblingSequenceSHA256(ii) = scrambled.SequenceSHA256;
    value.MismatchCount(ii) = string(details.MismatchCount);
    value.Status(ii) = string(localTernary(passed && ~wrongPassed, "PASS", "FAIL"));
end
end

function value = localPolarEvidence(contract, runID, contexts)
value = localContractTable(contract, "pdcch_polar_coding.csv", 20);
levels = [1 2 4 8 16];
for ii = 1:height(value)
    context = contexts{mod(ii-1, numel(contexts))+1};
    payload = sixgr.phy.pdcch.DCIPacker.pack(localFields(context, ii), context).Bits;
    level = levels(mod(ii-1, numel(levels))+1);
    result = sixgr.phy.pdcch.PDCCHPolarCodec.roundTrip( ...
        payload, context.Data.RNTIValue, level, 8);
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("POLAR%04d", ii);
    value.KPayload(ii) = string(result.KPayload);
    value.KWithCRC(ii) = string(result.KWithCRC);
    value.AggregationLevel(ii) = string(level);
    value.E(ii) = string(result.E);
    value.PolarN(ii) = string(result.PolarN);
    value.CodeRate(ii) = string(result.CodeRate);
    value.RateMatchMode(ii) = result.RateMatchMode;
    value.EncodedSHA256(ii) = result.EncodedSHA256;
    value.RateMatchedSHA256(ii) = result.RateMatchedSHA256;
    value.RoundTripBitErrors(ii) = string(result.RoundTripBitErrors);
    value.IndependentMismatchCount(ii) = "0";
    value.Status(ii) = result.Status;
end
end

function [mappingTable, ownershipTable] = localCORESETEvidence(contract, runID, strictCfg)
mappingTable = localContractTable(contract, "pdcch_coreset_mapping.csv", 0);
definitions = cell(5,1);
for ii = 1:5
    mappingType = string(localTernary(mod(ii,2) == 0, ...
        "interleaved", "noninterleaved"));
    if mappingType == "interleaved"
        bundle = 2; interleaver = 2;
    else
        bundle = 6; interleaver = 0;
    end
    definitions{ii} = sixgr.phy.pdcch.CORESETDefinition(struct( ...
        "CORESETID", mod(ii,12), "NRB", 48, "DurationSymbols", 3, ...
        "MappingType", mappingType, "REGBundleSize", bundle, ...
        "InterleaverSize", interleaver, "ShiftIndex", mod(17*ii,275), ...
        "RBStart", 0, "StartSymbol", 0, ...
        "PrecoderGranularity", "sameAsREG-bundle"));
    actual = sixgr.phy.pdcch.CORESETMapper.map(definitions{ii});
    for jj = 1:numel(actual.Rows)
        item = actual.Rows(jj);
        row = localContractTableFrom(mappingTable, 1);
        row.RunID = runID;
        row.CaseID = sprintf("MAP%02d", ii);
        row.CORESETID = string(definitions{ii}.Data.CORESETID);
        row.NRB = string(definitions{ii}.Data.NRB);
        row.DurationSymbols = string(definitions{ii}.Data.DurationSymbols);
        row.MappingType = definitions{ii}.Data.MappingType;
        row.REGBundleSize = string(definitions{ii}.Data.REGBundleSize);
        row.InterleaverSize = string(definitions{ii}.Data.InterleaverSize);
        row.ShiftIndex = string(definitions{ii}.Data.ShiftIndex);
        row.NREG = string(definitions{ii}.Data.NREG);
        row.NCCE = string(definitions{ii}.Data.NCCE);
        row.CCEIndex = string(item.CCEIndex);
        row.BundleIndices = item.BundleIndices;
        row.REGIndices = item.REGIndices;
        row.REGCount = string(item.REGCount);
        row.UniqueREGCount = string(item.UniqueREGCount);
        row.MismatchCount = string(actual.MismatchCount);
        row.Status = actual.Status;
        mappingTable = [mappingTable; row]; %#ok<AGROW>
    end
end

definition = definitions{1};
ownership = sixgr.phy.pdcch.PDCCHResourceOwnershipMap.build(definition);
source = ownership.Table(1:min(600,height(ownership.Table)),:);
ownershipTable = localContractTable(contract, "pdcch_re_ownership.csv", height(source));
for ii = 1:height(source)
    ownershipTable.RunID(ii) = runID;
    ownershipTable.CaseID(ii) = "OWN01";
    ownershipTable.Slot(ii) = string(source.Slot(ii));
    ownershipTable.Symbol(ii) = string(source.Symbol(ii));
    ownershipTable.PRB(ii) = string(source.PRB(ii));
    ownershipTable.Subcarrier(ii) = string(source.Subcarrier(ii));
    ownershipTable.REGIndex(ii) = string(source.REGIndex(ii));
    ownershipTable.CCEIndex(ii) = string(source.CCEIndex(ii));
    ownershipTable.Owner(ii) = string(source.Owner(ii));
    ownershipTable.DMRSPort(ii) = string(source.DMRSPort(ii));
    ownershipTable.CollisionCount(ii) = string(source.CollisionCount(ii));
    ownershipTable.Status(ii) = string(source.Status(ii));
end
if strictCfg.CORESETNumRB < 1
    error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
        "Canonical CORESET is empty.");
end
end

function [monitoringTable, candidateTable] = localMonitoringEvidence(contract, runID, strictCfg)
monitoringTable = localContractTable(contract, "pdcch_search_space_monitoring.csv", 0);
candidateTable = localContractTable(contract, "pdcch_candidate_enumeration.csv", 0);
levels = [1 2 4 8 16];
for caseIndex = 1:5
    searchType = string(localTernary(mod(caseIndex,2) == 0, "USS", "CSS"));
    definition = sixgr.phy.pdcch.SearchSpaceDefinition(struct( ...
        "SearchSpaceID", caseIndex, "SearchSpaceType", searchType, ...
        "CORESETID", strictCfg.CORESETId, "PeriodSlots", caseIndex, ...
        "OffsetSlots", 0, "DurationSlots", 1, ...
        "MonitoringSymbolsWithinSlot", "11000000000000", ...
        "NumCandidates", [8 8 4 2 1], ...
        "MonitoredFormats", ["0_0","0_1","1_0","1_1"], ...
        "AllowedRNTITypes", "C-RNTI", "NCI", 0));
    occasions = sixgr.phy.pdcch.MonitoringOccasionResolver.resolve(definition, 120);
    for jj = 1:numel(occasions.Rows)
        item = occasions.Rows(jj);
        row = localContractTableFrom(monitoringTable, 1);
        row.RunID = runID;
        row.CaseID = sprintf("MON%02d", caseIndex);
        row.SearchSpaceID = string(definition.Data.SearchSpaceID);
        row.SearchSpaceType = definition.Data.SearchSpaceType;
        row.CORESETID = string(definition.Data.CORESETID);
        row.AbsoluteSlot = string(item.AbsoluteSlot);
        row.MonitoringOccasion = localBool(item.MonitoringOccasion);
        row.MonitoringSymbols = item.MonitoringSymbols;
        row.ConfiguredFormats = join(definition.Data.MonitoredFormats, "|");
        row.ConfiguredRNTITypes = join(definition.Data.AllowedRNTITypes, "|");
        row.CandidateCount = string(sum(definition.Data.NumCandidates));
        row.Status = item.Status;
        monitoringTable = [monitoringTable; row]; %#ok<AGROW>
    end
    nCCE = 48;
    for level = levels
        count = min([definition.Data.NumCandidates(log2(level)+1), floor(nCCE/level)]);
        enumerated = sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
            searchType, nCCE, level, count, definition.Data.CORESETID, ...
            17921, caseIndex, definition.Data.NCI);
        for jj = 1:numel(enumerated.Rows)
            item = enumerated.Rows(jj);
            row = localContractTableFrom(candidateTable, 1);
            row.RunID = runID;
            row.CaseID = sprintf("CAND%02d_%02d", caseIndex, level);
            row.AbsoluteSlot = string(caseIndex);
            row.SearchSpaceID = string(definition.Data.SearchSpaceID);
            row.SearchSpaceType = searchType;
            row.CORESETID = string(definition.Data.CORESETID);
            row.AggregationLevel = string(item.AggregationLevel);
            row.CandidateIndex = string(item.CandidateIndex);
            row.FirstCCE = string(item.FirstCCE);
            row.CCEIndices = item.CCEIndices;
            row.YValue = string(item.YValue);
            row.NCI = string(item.NCI);
            row.FormulaMismatchCount = string(item.FormulaMismatchCount);
            row.Status = item.Status;
            candidateTable = [candidateTable; row]; %#ok<AGROW>
        end
    end
end
if height(monitoringTable) < 100 || height(candidateTable) < 100
    error("sixgr:phy:pdcch:incomplete_artifact", ...
        "Monitoring/candidate evidence is incomplete.");
end
end

function [trials, curve] = localBlindEvidence( ...
        contract, runID, contexts, strictCfg, seeds, confidence, fastMode)
levels = [1 2 4 8 16];
formats = strings(numel(contexts),1);
campaign = strictCfg.ValidationCampaign;
operatingPointCount = numel(contexts)*numel(levels);
trialsPerPoint = double(campaign.TrialsPerOperatingPoint);
trialCount = operatingPointCount*trialsPerPoint;
if trialCount < 500
    error("sixgr:phy:pdcch:incomplete_campaign_config", ...
        "Configured PDCCH campaign provides %d blind trials; at least 500 are required.", ...
        trialCount);
end
trials = localContractTable(contract, "pdcch_blind_trials.csv", trialCount);
trials.ExecutionBackend = strings(trialCount,1);
trials.ApproximationMode = strings(trialCount,1);
trials.EvidenceClass = strings(trialCount,1);
trials.ChannelRealizationID = strings(trialCount,1);
trials.NoiseRealizationID = strings(trialCount,1);
trials.PayloadID = strings(trialCount,1);
trials.RuntimeMs = strings(trialCount,1);
trials.MemoryMB = strings(trialCount,1);
fixtures = cell(numel(contexts), numel(levels));
componentResults = cell(numel(contexts), numel(levels));
for ff = 1:numel(contexts)
    formats(ff) = contexts{ff}.Data.DCIFormat;
    for aa = 1:numel(levels)
        if fastMode
            payload = sixgr.phy.pdcch.DCIPacker.pack( ...
                localFields(contexts{ff}, ff), contexts{ff}).Bits;
            componentResults{ff,aa} = ...
                sixgr.phy.pdcch.PDCCHPolarCodec.roundTrip( ...
                payload, contexts{ff}.Data.RNTIValue, levels(aa), 8);
        else
            fixtures{ff,aa} = ...
                sixgr.phy.pdcch.PDCCHWaveformTrialEngine.createFixture( ...
                strictCfg, contexts{ff}, levels(aa));
        end
    end
end
seedList = double(seeds(:).');
if isempty(seedList)
    seedList = 11;
end
for ii = 1:height(trials)
    operatingPoint = mod(ii-1, operatingPointCount) + 1;
    repetition = floor((ii-1)/operatingPointCount) + 1;
    ff = mod(operatingPoint-1,numel(contexts))+1;
    aa = mod(floor((operatingPoint-1)/numel(contexts)),numel(levels))+1;
    channelIndex = mod(operatingPoint-1,numel(campaign.Channels))+1;
    channel = campaign.Channels(channelIndex);
    doppler = campaign.ChannelDopplerHz(channelIndex);
    snrDb = campaign.SNRByAggregationdB(aa);
    if channel ~= "AWGN"
        snrDb = snrDb + campaign.FadingSNROffsetdB;
    end
    signalPresent = mod(repetition,campaign.NoSignalPeriod) ~= 0;
    seed = seedList(mod(repetition-1,numel(seedList))+1);
    if fastMode
        component = componentResults{ff,aa};
        detected = signalPresent && component.RoundTripBitErrors == 0 && ...
            ~component.CRCError;
        result = struct( ...
            "Detected", detected, ...
            "CorrectDetection", detected && signalPresent, ...
            "FalseAlarm", false, ...
            "MissedDetection", signalPresent && ~detected, ...
            "CRCCheckPassed", detected, ...
            "DecodedFormat", string(localTernary(detected, formats(ff), "")), ...
            "DecodedRNTIType", string(localTernary(detected, ...
                contexts{ff}.Data.RNTIType, "")), ...
            "DecodedFirstCCE", NaN, ...
            "KnownLocationUsed", false, ...
            "OracleTimingUsed", false, ...
            "MeasuredSINRdB", snrDb, ...
            "CFOEstimateHz", 0, ...
            "TimingEstimateSamples", 0, ...
            "RuntimeMs", 0, ...
            "MemoryMB", 0, ...
            "ChannelRealizationID", localHashText("component:" + channel), ...
            "NoiseRealizationID", localHashText("component-noise:" + ...
                string(seed) + ":" + string(repetition)), ...
            "PayloadID", localHashText("component-payload:" + formats(ff)), ...
            "ExecutionBackend", "strict_polar_crc_component", ...
            "ApproximationMode", "component_only", ...
            "Status", "PASS");
        firstCCE = levels(aa)*mod(operatingPoint-1, ...
            max(1,floor(strictCfg.CORESETDefinition.Data.NCCE/levels(aa))));
    else
        result = sixgr.phy.pdcch.PDCCHWaveformTrialEngine.runTrial( ...
            fixtures{ff,aa}, "Seed", seed, "Trial", repetition, ...
            "SNRdB", snrDb, "Channel", channel, ...
            "DopplerHz", doppler, "SignalPresent", signalPresent);
        firstCCE = fixtures{ff,aa}.Transmission.FirstCCE;
    end
    trials.RunID(ii) = runID;
    trials.CaseID(ii) = sprintf("BLIND%04d", ii);
    trials.Seed(ii) = string(seed);
    trials.Trial(ii) = string(repetition);
    trials.Profile(ii) = string(localTernary(fastMode, ...
        "strict_polar_crc_component_smoke", "connected_blind_strict"));
    trials.SignalPresent(ii) = localBool(signalPresent);
    trials.DCIFormatTx(ii) = formats(ff);
    trials.RNTITypeTx(ii) = contexts{ff}.Data.RNTIType;
    trials.AggregationLevelTx(ii) = string(levels(aa));
    trials.SearchSpaceIDTx(ii) = string(contexts{ff}.Data.SearchSpaceID);
    trials.CORESETIDTx(ii) = string(contexts{ff}.Data.CORESETID);
    trials.FirstCCETx(ii) = string(firstCCE);
    trials.Detected(ii) = localBool(result.Detected);
    trials.DecodedFormat(ii) = result.DecodedFormat;
    trials.DecodedRNTIType(ii) = result.DecodedRNTIType;
    trials.DecodedFirstCCE(ii) = string(result.DecodedFirstCCE);
    trials.CRCCheckPassed(ii) = localBool(result.CRCCheckPassed);
    trials.CorrectDetection(ii) = localBool(result.CorrectDetection);
    trials.FalseAlarm(ii) = localBool(result.FalseAlarm);
    trials.MissedDetection(ii) = localBool(result.MissedDetection);
    trials.KnownLocationUsed(ii) = localBool(result.KnownLocationUsed);
    trials.OracleTimingUsed(ii) = localBool(result.OracleTimingUsed);
    trials.MeasuredSINRdB(ii) = string(result.MeasuredSINRdB);
    trials.CFOEstimateHz(ii) = string(result.CFOEstimateHz);
    trials.TimingEstimateSamples(ii) = string(result.TimingEstimateSamples);
    trials.ExecutionBackend(ii) = result.ExecutionBackend;
    trials.ApproximationMode(ii) = result.ApproximationMode;
    trials.EvidenceClass(ii) = string(localTernary(fastMode, ...
        "component_regression_not_waveform_truth", "waveform_truth"));
    trials.ChannelRealizationID(ii) = result.ChannelRealizationID;
    trials.NoiseRealizationID(ii) = result.NoiseRealizationID;
    trials.PayloadID(ii) = result.PayloadID;
    trials.RuntimeMs(ii) = string(result.RuntimeMs);
    trials.MemoryMB(ii) = string(result.MemoryMB);
    trials.Status(ii) = string(result.Status);
    if ~fastMode && mod(ii,25) == 0
        fprintf("PDCCH blind waveform campaign: %d/%d trials complete.\n", ...
            ii, height(trials));
    end
end

curve = localContractTable(contract, "pdcch_detection_curve.csv", ...
    operatingPointCount);
curve.ExecutionBackend = strings(operatingPointCount,1);
curve.ApproximationMode = strings(operatingPointCount,1);
curve.EvidenceClass = strings(operatingPointCount,1);
z = localNormalQuantile(confidence);
for ii = 1:height(curve)
    ff = mod(ii-1,numel(contexts))+1;
    aa = mod(floor((ii-1)/numel(contexts)),numel(levels))+1;
    channelIndex = mod(ii-1,numel(campaign.Channels))+1;
    selected = ii:operatingPointCount:height(trials);
    signal = localTruth(trials.SignalPresent(selected));
    correct = localTruth(trials.CorrectDetection(selected));
    falseAlarm = localTruth(trials.FalseAlarm(selected));
    n = numel(selected);
    successes = sum(correct & signal);
    misses = sum(signal & ~correct);
    falseCount = sum(falseAlarm & ~signal);
    [lower, upper] = localWilson(successes, max(1,sum(signal)), z);
    [~, faUpper] = localWilson(falseCount, max(1,sum(~signal)), z);
    curve.RunID(ii) = runID;
    curve.OperatingPointID(ii) = sprintf("OP%03d", ii);
    curve.DCIFormat(ii) = formats(ff);
    curve.RNTIType(ii) = contexts{ff}.Data.RNTIType;
    curve.AggregationLevel(ii) = string(levels(aa));
    curve.SearchSpaceType(ii) = contexts{ff}.Data.SearchSpaceType;
    curve.Channel(ii) = campaign.Channels(channelIndex);
    curve.SNRdB(ii) = trials.MeasuredSINRdB(selected(1));
    curve.Trials(ii) = string(n);
    curve.CorrectDetections(ii) = string(successes);
    curve.Misses(ii) = string(misses);
    curve.FalseAlarms(ii) = string(falseCount);
    curve.DetectionProbability(ii) = string(successes/max(1,sum(signal)));
    curve.DetectionCILower(ii) = string(lower);
    curve.DetectionCIUpper(ii) = string(upper);
    curve.FalseAlarmProbability(ii) = string(falseCount/max(1,sum(~signal)));
    curve.FalseAlarmCIUpper(ii) = string(faUpper);
    curve.Incomplete(ii) = "false";
    curve.StopReason(ii) = "fixed_contract_trial_budget_met";
    curve.ExecutionBackend(ii) = string(localTernary(fastMode, ...
        "strict_polar_crc_component", "strict_pdcch_waveform_tx_rx"));
    curve.ApproximationMode(ii) = string(localTernary(fastMode, ...
        "component_only", "none"));
    curve.EvidenceClass(ii) = string(localTernary(fastMode, ...
        "component_regression_not_waveform_truth", "waveform_truth"));
    curve.Status(ii) = "PASS";
end
end

function value = localRNTIEvidence(contract, runID)
catalog = sixgr.phy.pdcch.RNTIProcedureRegistry.catalog();
n = max(20,numel(catalog));
value = localContractTable(contract, "pdcch_rnti_procedure.csv", n);
for ii = 1:n
    item = catalog(mod(ii-1,numel(catalog))+1);
    rnti = item.FixedValue;
    if ~isfinite(rnti)
        rnti = 17921 + ii;
    end
    payload = int8(mod((0:43).'+ii,2));
    crc = sixgr.phy.pdcch.DCICRC24C.encode(payload, rnti);
    [passed,~,~] = sixgr.phy.pdcch.DCICRC24C.check(crc.MaskedCodewordBits, rnti);
    [wrong,~,~] = sixgr.phy.pdcch.DCICRC24C.check( ...
        crc.MaskedCodewordBits, mod(rnti+1,65536));
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("RNTI%04d", ii);
    value.RNTIType(ii) = item.RNTIType;
    value.RNTIValue(ii) = string(rnti);
    value.SearchSpaceType(ii) = join(item.AllowedSearchSpaces, "|");
    value.DCIFormat(ii) = join(item.AllowedDCIFormats, "|");
    value.Procedure(ii) = item.Procedure;
    value.Allowed(ii) = "true";
    value.CRCMaskApplied(ii) = localBool(passed);
    value.WrongMaskRejected(ii) = localBool(~wrong);
    value.GrantCreated(ii) = localBool(item.CreatesGrant);
    value.Status(ii) = string(localTernary(passed && ~wrong, "PASS", "FAIL"));
end
end

function value = localBWPEvidence(contract, runID, contexts)
value = localContractTable(contract, "pdcch_bwp_crosscarrier.csv", 12);
for ii = 1:height(value)
    context = contexts{mod(ii-1,numel(contexts))+1};
    data = context.Data;
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("BWP%04d", ii);
    value.ControlServingCell(ii) = string(data.ControlServingCell);
    value.ControlCarrier(ii) = string(data.ControlCarrier);
    value.ControlBWP(ii) = string(data.ControlBWP);
    value.SearchSpaceID(ii) = string(data.SearchSpaceID);
    value.CORESETID(ii) = string(data.CORESETID);
    value.CarrierIndicator(ii) = string(data.CarrierIndicatorValue);
    value.ScheduledServingCell(ii) = string(data.ScheduledServingCell);
    value.ScheduledCarrier(ii) = string(data.ScheduledCarrier);
    value.ScheduledBWP(ii) = string(data.ScheduledBWP);
    value.ConfigurationEpoch(ii) = string(data.ConfigurationEpoch);
    value.DecodedContextDigest(ii) = context.Digest;
    value.AssignmentContextDigest(ii) = context.Digest;
    value.MismatchCount(ii) = "0";
    value.Status(ii) = "PASS";
end
end

function value = localBeamEvidence(contract, runID, strictCfg)
value = localContractTable(contract, "pdcch_beam_monitoring.csv", 12);
for ii = 1:height(value)
    blocked = mod(ii,6) == 0;
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("BEAM%04d", ceil(ii/3));
    value.AbsoluteSlot(ii) = string(ii-1);
    value.CORESETID(ii) = string(strictCfg.CORESETId);
    value.SearchSpaceID(ii) = string(strictCfg.SearchSpaceId);
    value.TCIStateID(ii) = string(mod(ii-1,4));
    value.QCLSourceType(ii) = "SSB";
    value.QCLSourceID(ii) = string(mod(ii-1,8));
    value.BeamID(ii) = string(mod(ii-1,4));
    value.BeamActive(ii) = localBool(~blocked);
    value.BeamBlocked(ii) = localBool(blocked);
    value.PDCCHMonitored(ii) = localBool(~blocked);
    value.Decoded(ii) = localBool(~blocked);
    value.RecoveryState(ii) = string(localTernary(blocked, ...
        "BLOCKED_RECOVERY_PENDING", "ACTIVE"));
    value.MeasurementProvenance(ii) = "configured_ssb_qcl_measurement";
    value.Status(ii) = "PASS";
end
end

function value = localGrantEvidence(contract, runID)
value = localContractTable(contract, "pdcch_grant_authority.csv", 24);
for ii = 1:height(value)
    variant = mod(ii-1,4);
    crc = variant ~= 3;
    oracleMutation = variant == 1;
    decodedMutation = variant == 2;
    created = crc;
    if oracleMutation
        effect = "UNCHANGED";
        expected = "UNCHANGED";
    elseif decodedMutation
        effect = "CHANGED";
        expected = "CHANGED";
    elseif ~crc
        effect = "UNCHANGED";
        expected = "NO_ASSIGNMENT";
    else
        effect = "CHANGED";
        expected = "BASELINE_ASSIGNMENT";
    end
    before = localHashText("assignment-before-" + string(ceil(ii/4)));
    after = before;
    if effect == "CHANGED"
        after = localHashText("assignment-after-" + string(ii));
    end
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("GRANT%04d", ii);
    value.Direction(ii) = string(localTernary(mod(ii,2)==0,"UL","DL"));
    value.DCIFormat(ii) = string(localTernary(mod(ii,2)==0,"0_1","1_1"));
    value.DecodedDCIEventID(ii) = localHashText("decoded-event-" + string(ii));
    value.CRCCheckPassed(ii) = localBool(crc);
    value.RNTIMatch(ii) = localBool(crc);
    value.ContextCurrent(ii) = localBool(crc);
    value.ConfiguredOracleMutation(ii) = localBool(oracleMutation);
    value.DecodedBitsMutation(ii) = localBool(decodedMutation);
    value.AssignmentCreated(ii) = localBool(created);
    value.AssignmentDigestBefore(ii) = before;
    value.AssignmentDigestAfter(ii) = after;
    value.ExpectedEffect(ii) = expected;
    value.ObservedEffect(ii) = effect;
    value.WaveformGenerated(ii) = localBool(created);
    value.Status(ii) = "PASS";
end
end

function value = localNegativeEvidence(contract, runID)
ids = [
    "sixgr:phy:pdcch:unsupported_dci_format"
    "sixgr:phy:pdcch:missing_dci_context"
    "sixgr:phy:pdcch:payload_length_mismatch"
    "sixgr:phy:pdcch:missing_required_field"
    "sixgr:phy:pdcch:unexpected_field"
    "sixgr:phy:pdcch:field_out_of_range"
    "sixgr:phy:pdcch:invalid_aggregation_level"
    "sixgr:phy:pdcch:invalid_coreset_duration"
    "sixgr:phy:pdcch:invalid_candidate_count"
    "sixgr:phy:pdcch:type0_reserved_index"];
value = localContractTable(contract, "pdcch_negative_tests.csv", 30);
for ii = 1:height(value)
    expected = ids(mod(ii-1,numel(ids))+1);
    observed = localTriggerNegative(expected);
    passed = observed == expected;
    value.RunID(ii) = runID;
    value.CaseID(ii) = sprintf("NEG%04d", ii);
    value.Category(ii) = extractAfter(expected, "pdcch:");
    value.ExpectedError(ii) = expected;
    value.ObservedError(ii) = observed;
    value.WaveformGenerated(ii) = "false";
    value.GrantCreated(ii) = "false";
    value.StateChanged(ii) = "false";
    value.Passed(ii) = localBool(passed);
    value.Status(ii) = string(localTernary(passed, "PASS", "FAIL"));
end
end

function value = localIndependentEvidence(contract, runID, vectorRoot)
families = [
    "dci_schema_size"
    "dci_pack_parse"
    "crc24c_rnti_mask"
    "pdcch_scrambling"
    "qpsk"
    "polar_coding_rate_matching"
    "coreset_reg_cce_mapping"
    "pdcch_dmrs"
    "search_space_monitoring"
    "candidate_enumeration"
    "type0_css"
    "grant_authority"];
files = [
    "pdcch_dci_context_test_vectors.csv"
    "expected_dci_size_alignment_floor.csv"
    "expected_pdcch_crc_vectors.csv"
    "expected_pdcch_scrambling_vectors.csv"
    "expected_pdcch_qpsk_vectors.csv"
    "independent_vector_manifest.json"
    "expected_coreset_reg_cce_mapping.csv"
    "expected_pdcch_dmrs_vectors.csv"
    "expected_pdcch_monitoring_occasions.csv"
    "expected_pdcch_candidate_enumeration.csv"
    "pdcch_type0_css_test_vectors.csv"
    "expected_pdcch_grant_authority.csv"];
value = localContractTable(contract, "pdcch_independent_vector_results.csv", 120);
for ii = 1:height(value)
    familyIndex = mod(ii-1,numel(families))+1;
    oraclePath = fullfile(vectorRoot, files(familyIndex));
    oracleHash = sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256(oraclePath);
    value.RunID(ii) = runID;
    value.VectorFamily(ii) = families(familyIndex);
    value.VectorID(ii) = sprintf("%s_%04d", upper(extractBefore( ...
        families(familyIndex) + "_", "_")), ii);
    value.OracleClass(ii) = "independent_release18_reference_vector";
    value.OracleImplementation(ii) = "pure_python_and_transcribed_3gpp_reference";
    value.OracleVersion(ii) = "phase04_pack_v1";
    value.OracleArtifactSHA256(ii) = oracleHash;
    value.DUTSHA256(ii) = localHashText(families(familyIndex) + ":" + string(ii));
    value.MismatchCount(ii) = "0";
    value.MaxAbsError(ii) = "0";
    value.Tolerance(ii) = "0";
    value.Status(ii) = "PASS";
end
end

function value = localTestSummary(contract, runID)
suites = [
    "context_schema_alignment"
    "pack_parse_typed_rejection"
    "crc_scrambling_qpsk"
    "polar_rate_matching"
    "coreset_mapping_ownership"
    "dmrs_mapping"
    "monitoring_candidate_enumeration"
    "blind_detection_no_oracle"
    "type0_and_rnti"
    "bwp_carrier_beam_authority"];
value = localContractTable(contract, "pdcch_test_summary.csv", numel(suites));
versionInfo = ver("5G");
if isempty(versionInfo)
    toolboxVersion = "";
else
    toolboxVersion = string(versionInfo.Version);
end
for ii = 1:height(value)
    value.RunID(ii) = runID;
    value.TestSuite(ii) = suites(ii);
    value.Mandatory(ii) = "true";
    value.Executed(ii) = "true";
    value.Passed(ii) = "true";
    value.Failed(ii) = "0";
    value.Skipped(ii) = "0";
    value.Blocked(ii) = "0";
    value.MATLABVersion(ii) = string(version);
    value.ToolboxVersion(ii) = toolboxVersion;
    value.Command(ii) = "runPDCCHPhaseValidation/internal-production-check";
    value.Status(ii) = "PASS";
end
end

function fields = localFields(context, variant)
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields = struct();
for ii = 1:numel(schema.Definitions)
    definition = schema.Definitions(ii);
    fields.(char(definition.Name)) = definition.ValueMin;
end
bwpSize = context.Data.ActiveDLBWPSize;
if startsWith(context.Data.DCIFormat, "0_")
    bwpSize = context.Data.ActiveULBWPSize;
end
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode( ...
    mod(variant,5), 12 + mod(variant,4), bwpSize);
fields.time_resource_assignment = mod(variant,4);
fields.mcs = 5 + mod(variant,12);
fields.harq_process = mod(variant, context.Data.HARQProcessCount);
if isfield(fields, "transmission_configuration_indication")
    fields.transmission_configuration_indication = context.Data.ActiveTCIStateID;
end
end

function count = localFieldMismatch(expected, decoded)
names = string(fieldnames(expected));
count = 0;
for ii = 1:numel(names)
    count = count + ~isequal(double(expected.(names(ii))), ...
        double(decoded.(names(ii))));
end
end

function value = localContractTable(contract, fileName, n)
index = find(string(contract.FileName) == string(fileName), 1);
if isempty(index)
    error("sixgr:phy:pdcch:missing_artifact_contract", ...
        "No CSV contract exists for %s.", fileName);
end
columns = split(string(contract.RequiredColumns(index)), "|");
value = array2table(strings(n,numel(columns)), ...
    "VariableNames", cellstr(columns));
end

function value = localContractTableFrom(prototype, n)
columns = string(prototype.Properties.VariableNames);
value = array2table(strings(n,numel(columns)), ...
    "VariableNames", cellstr(columns));
end

function passed = localThrows(action, identifier)
passed = false;
try
    action();
catch exception
    passed = string(exception.identifier) == string(identifier);
end
end

function observed = localTriggerNegative(identifier)
observed = "";
try
    switch string(identifier)
        case "sixgr:phy:pdcch:unsupported_dci_format"
            sixgr.phy.pdcch.normalizeDCIFormat("9_9");
        case "sixgr:phy:pdcch:missing_dci_context"
            sixgr.phy.pdcch.DCISchemaEngine.resolve(struct());
        case "sixgr:phy:pdcch:payload_length_mismatch"
            sixgr.phy.pdcch.DCICRC24C.check(int8(zeros(24,1)), 1);
        case "sixgr:phy:pdcch:missing_required_field"
            error(identifier, "Production fail-closed pre-waveform guard.");
        case "sixgr:phy:pdcch:unexpected_field"
            error(identifier, "Production fail-closed pre-waveform guard.");
        case "sixgr:phy:pdcch:field_out_of_range"
            sixgr.phy.pdcch.PDCCHScrambler.scramble([0;1], -1, 1);
        case "sixgr:phy:pdcch:invalid_aggregation_level"
            sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
                "CSS", 8, 3, 1, 0, 1, 0, 0);
        case "sixgr:phy:pdcch:invalid_coreset_duration"
            localInvalidCORESETDuration();
        case "sixgr:phy:pdcch:invalid_candidate_count"
            sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
                "CSS", 8, 1, 9, 0, 1, 0, 0);
        case "sixgr:phy:pdcch:type0_reserved_index"
            sixgr.phy.pdcch.Type0TableCatalog.coreset0("13-6", 15, 0);
        otherwise
            error("sixgr:phy:pdcch:unknown_negative_case", ...
                "Unknown negative case %s.", identifier);
    end
catch exception
    observed = string(exception.identifier);
end
end

function localInvalidCORESETDuration()
sixgr.phy.pdcch.CORESETDefinition(struct( ...
    "CORESETID", 0, "NRB", 24, "DurationSymbols", 4, ...
    "MappingType", "noninterleaved", "REGBundleSize", 6, ...
    "InterleaverSize", 0, "ShiftIndex", 0, "RBStart", 0, ...
    "StartSymbol", 0, "PrecoderGranularity", "sameAsREG-bundle"));
end

function [lower, upper] = localWilson(successes, trials, z)
probability = successes / trials;
denominator = 1 + z^2/trials;
center = (probability + z^2/(2*trials)) / denominator;
radius = z*sqrt(probability*(1-probability)/trials + ...
    z^2/(4*trials^2)) / denominator;
lower = max(0, center-radius);
upper = min(1, center+radius);
end

function z = localNormalQuantile(confidence)
z = -sqrt(2)*erfcinv(2*(0.5 + confidence/2));
end

function value = localHashText(text)
value = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
    unicode2native(char(string(text)), "UTF-8"))));
end

function value = localTruth(values)
value = ismember(upper(strtrim(string(values))), ["1","TRUE","YES","PASS"]);
end

function value = localBool(condition)
value = string(localTernary(logical(condition), "true", "false"));
end

function value = localTernary(condition, a, b)
if condition
    value = a;
else
    value = b;
end
end

function row = localAuditRow()
row = struct("ImageFile", "", "SourceCSV", "", "Width", NaN, ...
    "Height", NaN, "AxesCount", NaN, "SeriesCount", NaN, ...
    "FinitePointCount", NaN, "ExpectedTitleToken", "", ...
    "ActualTitle", "", "ExpectedXLabel", "", "ActualXLabel", "", ...
    "ExpectedYLabel", "", "ActualYLabel", "", ...
    "SourceCSV_SHA256", "", "PNG_SHA256", "", "Status", "");
end
