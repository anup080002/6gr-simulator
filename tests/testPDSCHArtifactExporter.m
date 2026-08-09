function ok = testPDSCHArtifactExporter()
%TESTPDSCHARTIFACTEXPORTER Exercise fail-closed CSV/PNG publication.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
vectorRoot = fullfile(fileparts(mfilename("fullpath")), ...
    "vectors", "pdsch");
outputDir = fullfile(tempdir, "sixgr_pdsch_exporter_focused");
negativeDir = fullfile(tempdir, "sixgr_pdsch_exporter_negative");
localResetDirectory(outputDir);
localResetDirectory(negativeDir);
tables = localProductionDerivedTables(vectorRoot);

summary = sixgr.pdsch.PDSCHArtifactExporter.export( ...
    tables, outputDir, vectorRoot);
assert(summary.Passed && summary.PrimaryTableCount == 14 && ...
    summary.ContractedImageCount == 9 && ...
    summary.AuditedImageCount == 11, ...
    "PDSCH artifact exporter did not return a passing contract summary.");
assert(numel(summary.CSVFiles) == 15 && ...
    numel(summary.ContractedPNGFiles) == 9 && ...
    numel(summary.AdditionalPNGFiles) == 2, ...
    "PDSCH artifact exporter emitted the wrong artifact counts.");
assert(height(summary.SemanticAudit) == 11 && ...
    all(summary.SemanticAudit.Status == "PASS"), ...
    "PDSCH image semantic audit is incomplete or nonpassing.");
assert(all(summary.SemanticAudit.Width >= 900) && ...
    all(summary.SemanticAudit.Height >= 600) && ...
    all(strlength(summary.SemanticAudit.PNG_SHA256) == 64), ...
    "PDSCH image dimensions or SHA-256 records are invalid.");
dmrsAudit = summary.SemanticAudit( ...
    summary.SemanticAudit.ImageFile == "pdsch_dmrs_ptrs_map.png", :);
assert(height(dmrsAudit) == 1 ...
    && dmrsAudit.SourceCSV == ...
        "pdsch_dmrs_matrix.csv|pdsch_ptrs_matrix.csv" ...
    && dmrsAudit.ActualPlotSourceCSV == ...
        "pdsch_dmrs_matrix.csv|pdsch_ptrs_matrix.csv" ...
    && dmrsAudit.ActualXLabel == "Subcarrier / PRB" ...
    && dmrsAudit.ActualYLabel == "OFDM symbol", ...
    "DM-RS/PT-RS figure is not bound to the exact frozen semantics.");
actualPlotSources = split(dmrsAudit.ActualPlotSourceCSV, "|");
actualPlotHash = strings(numel(actualPlotSources), 1);
for i = 1:numel(actualPlotSources)
    actualPlotHash(i) = actualPlotSources(i) + "=" + ...
        localFileDigest(fullfile(outputDir, actualPlotSources(i)));
end
assert(dmrsAudit.ActualPlotSourceCSV_SHA256 ...
        == strjoin(actualPlotHash, "|"), ...
    ["DM-RS/PT-RS figure provenance is not hash-bound to its " ...
    "persisted RE mapping and reference-signal tables."]);
prgAudit = summary.SemanticAudit( ...
    summary.SemanticAudit.ImageFile == "pdsch_prg_precoding_map.png", :);
assert(height(prgAudit) == 1 ...
    && prgAudit.ActualXLabel == "PRB / PRG" ...
    && prgAudit.ActualYLabel == "Precoder index or gain", ...
    "PRG figure labels differ from the exact frozen semantics.");
assert(all(ismember([ ...
        "pdsch_pipeline_stage_dimensions.png"; ...
        "pdsch_independent_mismatch_overview.png"], ...
        summary.SemanticAudit.ImageFile)), ...
    "Both additional PNGs require hash-bound semantic audit rows.");
for name = [summary.CSVFiles; summary.ContractedPNGFiles; ...
        summary.AdditionalPNGFiles].'
    assert(isfile(fullfile(outputDir, name)), ...
        "PDSCH artifact exporter did not publish %s.", name);
end
blerImage = imread(fullfile(outputDir, "pdsch_bler_vs_snr.png"));
if isinteger(blerImage)
    normalizedBrightness = mean(double(blerImage(:))) ...
        / double(intmax(class(blerImage)));
else
    normalizedBrightness = mean(double(blerImage(:)));
end
assert(normalizedBrightness > 0.75, ...
    ["PDSCH PNG must use the canonical light raster theme; " ...
    "dark desktop graphics defaults leaked into the artifact."]);

bad = tables;
bad.pdsch_bler_curve.StopReason = [];
localAssertError(@() sixgr.pdsch.PDSCHArtifactExporter.export( ...
    bad, negativeDir, vectorRoot), ...
    "sixgr:pdsch:ArtifactSchemaMismatch");
assert(isempty(dir(fullfile(negativeDir, "*.csv"))) && ...
    isempty(dir(fullfile(negativeDir, "*.png"))), ...
    "A failed export published partial artifacts.");
ok = true;
fprintf("PDSCH_EXPORTER_OUTPUT=%s\n", outputDir);
end

function tables = localProductionDerivedTables(vectorRoot)
caseIDs = "ART-" + string((1:4).');
maps = cell(4, 1);
plans = cell(4, 1);
codingPlans = cell(4, 1);
for i = 1:4
    reservedCount = (i - 1) * 12;
    dmrsIndices = 24:35;
    ptrsIndices = 72:75;
    if reservedCount == 0
        reserved = zeros(1, 0);
    else
        reserved = (168 - reservedCount):167;
    end
    maps{i} = sixgr.pdsch.PDSCHResourceOwnershipMap( ...
        0:167, struct("RateMatchPattern", reserved));
    context = struct( ...
        "PRBSet", 0, "SymbolAllocation", [0 14], ...
        "GridNumPRB", 1, ...
        "GridSymbolsPerSlot",14,"BWPStartPRB",0,"AbsoluteSlot",0, ...
        "UnavailableIndices",zeros(1,0), ...
        "DMRSIndicesPerPort", {{dmrsIndices}}, ...
        "PTRSIndicesPerPort", {{ptrsIndices}}, ...
        "DMRSLogicalPortSet",0, ...
        "PTRSLogicalPortSet",0, ...
        "LayerCountPerCodeword", 1, ...
        "QmPerCodeword", 2, ...
        "CodeBlockCountPerCodeword", 1);
    plans{i} = sixgr.pdsch.PDSCHResourcePlan(maps{i}, context);
    codingPlans{i} = sixgr.pdsch.DLSCHCodingPlan.resolve( ...
        "TransportBlockSize", 120, "TargetCodeRate", 0.5, ...
        "RateMatchedBitCount", plans{i}.GPerCodeword, ...
        "RV", mod(i - 1, 4), "Modulation", "QPSK", ...
        "NumLayers", 1, "CodewordIndex", 0);
end

tables = struct();
tables.pdsch_assignment_resolution = ...
    localAssignment(vectorRoot);
[tables.pdsch_resource_ownership, tables.pdsch_re_mapping] = ...
    localOwnershipAndMapping(vectorRoot, caseIDs, maps, plans);
tables.pdsch_dmrs_matrix = localDMRS(vectorRoot);
tables.pdsch_ptrs_matrix = localPTRS(vectorRoot);
tables.pdsch_coding_chain = ...
    localCoding(vectorRoot, caseIDs, codingPlans);
tables.pdsch_independent_vector_results = ...
    localIndependent(vectorRoot);
tables.pdsch_layer_codeword_map = localLayers(vectorRoot);
tables.pdsch_precoding_application = localPrecoding(vectorRoot);
tables.pdsch_harq_trials = localHARQ(vectorRoot);
tables.pdsch_receiver_metrics = localReceiver(vectorRoot);
tables.pdsch_bler_curve = localBLER(vectorRoot);
tables.pdsch_negative_tests = localNegative(vectorRoot);
tables.pdsch_test_summary = localSummary(vectorRoot);
end

function value = localAssignment(vectorRoot)
value = localBlank(vectorRoot, "pdsch_assignment_resolution.csv", 1);
value.CaseID = "ASSIGN-CAL-1";
value.Profile = "phy_calibration";
value.UEID = "UE-1";
value.ServingCellID = "0";
value.CCID = "0";
value.BWPId = "0";
value.AbsoluteSlot = "0";
value.ConfigurationEpoch = "1";
value.DCIFormat = "";
value.DCICRCPass = "0";
value.DCIRNTIMatch = "0";
value.RNTIType = "C-RNTI";
value.FDRAType = "type1";
value.VRBToPRBMapping = "non_interleaved";
value.K0 = "0";
value.PRBSet = "0";
value.SymbolAllocation = "0|14";
value.MappingType = "A";
value.MCSTable = "qam64";
value.MCSIndex = "4";
value.Modulation = "QPSK";
value.TargetCodeRate = "0.5";
value.TBScaling = "1";
value.XOverhead = "0";
value.NumLayers = "1";
value.NDI = "1";
value.RV = "0";
value.HARQProcessID = "0";
value.DMRSPortSet = "0";
value.TCIStateId = "0";
value.SPSActivationDCICRCPass = "0";
value.SPSActivationDCIRNTIMatch = "0";
value.SPSActivated = "0";
value.SPSReleased = "0";
value.Source = "phy_calibration_factory";
value.AssignmentCreated = "1";
value.WaveformAllowed = "1";
end

function [ownership, mapping] = localOwnershipAndMapping( ...
        vectorRoot, caseIDs, maps, plans)
n = sum(cellfun(@(x) height(x.Entries), maps));
ownership = localBlank( ...
    vectorRoot, "pdsch_resource_ownership.csv", n);
mapping = localBlank(vectorRoot, "pdsch_re_mapping.csv", n);
cursor = 0;
for c = 1:numel(maps)
    map = maps{c};
    plan = plans{c};
    dmrs = unique([plan.DMRSIndicesPerPort{:}]);
    ptrs = unique([plan.PTRSIndicesPerPort{:}]);
    for row = 1:height(map.Entries)
        cursor = cursor + 1;
        index = map.Entries.Index0Based(row);
        owner = map.Entries.Owner(row);
        if ismember(index, dmrs)
            owner = "pdsch_dmrs";
            domain = "DMRS";
        elseif ismember(index, ptrs)
            owner = "pdsch_ptrs";
            domain = "PTRS";
        elseif contains(owner, "reserved")
            domain = "RESERVED";
        else
            domain = "DATA";
        end
        ownership.CaseID(cursor) = caseIDs(c);
        ownership.Slot(cursor) = "0";
        ownership.PRB(cursor) = "0";
        ownership.Symbol(cursor) = string(floor(index / 12));
        ownership.Subcarrier(cursor) = string(mod(index, 12));
        ownership.Owner(cursor) = owner;
        if contains(owner, "reserved")
            ownership.SourceResourceId(cursor) = "RMP-" + string(c);
            ownership.OwnerPriority(cursor) = "10";
        elseif domain == "DMRS"
            ownership.SourceResourceId(cursor) = "DMRS-" + string(c);
            ownership.OwnerPriority(cursor) = "5";
        elseif domain == "PTRS"
            ownership.SourceResourceId(cursor) = "PTRS-" + string(c);
            ownership.OwnerPriority(cursor) = "4";
        else
            ownership.SourceResourceId(cursor) = "ASSIGN-" + string(c);
            ownership.OwnerPriority(cursor) = "1";
        end
        ownership.CollisionCount(cursor) = "0";

        mapping.CaseID(cursor) = caseIDs(c);
        mapping.Domain(cursor) = domain;
        mapping.Codeword(cursor) = "0";
        mapping.Layer(cursor) = "0";
        mapping.Port(cursor) = "0";
        mapping.PRB(cursor) = "0";
        mapping.Symbol(cursor) = string(floor(index / 12));
        mapping.Subcarrier(cursor) = string(mod(index, 12));
        mapping.LinearIndex0Based(cursor) = string(index);
    end
end
end

function value = localDMRS(vectorRoot)
value = localBlank(vectorRoot, "pdsch_dmrs_matrix.csv", 10);
for i = 1:height(value)
    value.CaseID(i) = "DMRS-ART-" + string(i);
    if mod(i, 2)
        value.MappingType(i) = "A";
    else
        value.MappingType(i) = "B";
    end
    value.DMRSConfigurationType(i) = string(1 + mod(i, 2));
    value.DMRSLength(i) = "1";
    value.DMRSAdditionalPosition(i) = "3";
    value.DMRSTypeAPosition(i) = "2";
    value.DMRSMultiplexing(i) = "basic";
    value.NumCDMGroupsWithoutData(i) = "1";
    value.NIDNSCID(i) = string(70 + i);
    value.NSCID(i) = string(mod(i, 2));
    value.DMRSPortSet(i) = "0";
    value.DMRSSymbols(i) = "2|5|8|11";
    if str2double(value.DMRSConfigurationType(i)) == 1
        value.DMRSRECount(i) = "24";
        subcarriers = [0 2 4 6 8 10];
    else
        value.DMRSRECount(i) = "16";
        subcarriers = [0 1 6 7];
    end
    [subcarrier, symbol] = ndgrid(subcarriers, [2 5 8 11]);
    value.PlotCoordinates0Based(i) = ...
        localCoordinateText([subcarrier(:), symbol(:)]);
    value.SequenceDigest(i) = localDigestText( ...
        "dmrs-sequence-" + string(i));
    value.SequenceNMSE(i) = "0";
    value.IndexMismatchCount(i) = "0";
end
end

function value = localPTRS(vectorRoot)
value = localBlank(vectorRoot, "pdsch_ptrs_matrix.csv", 4);
offsets = ["00","01","10","11"];
for i = 1:height(value)
    value.CaseID(i) = "PTRS-ART-" + string(i);
    value.TimeDensity(i) = string(1 + mod(i - 1, 2));
    value.FrequencyDensity(i) = string(2 + 2 * mod(i - 1, 2));
    value.REOffset(i) = offsets(i);
    value.PTRSPortSet(i) = "0";
    value.AssociatedDMRSPort(i) = "0";
    value.PTRSRECount(i) = string(8 + i);
    count = str2double(value.PTRSRECount(i));
    value.PlotCoordinates0Based(i) = localCoordinateText([ ...
        mod((0:(count - 1)).', 12), ...
        (i + floor((0:(count - 1)).' / 12))]);
    value.ExpectedPresent(i) = "1";
    value.PresenceReason(i) = "PTRSPresent";
    value.CPEBeforeDeg(i) = string(i - 1);
    value.CPEAfterDeg(i) = string(0.2 * (i - 1));
    value.EVMBeforePercent(i) = string(i);
    value.EVMAfterPercent(i) = string(0.4 * i);
end
end

function text = localCoordinateText(coordinates)
text = strjoin(compose("%.0f:%.0f", ...
    coordinates(:, 1), coordinates(:, 2)), "|");
end

function value = localCoding(vectorRoot, caseIDs, plans)
value = localBlank(vectorRoot, "pdsch_coding_chain.csv", numel(plans));
for i = 1:numel(plans)
    plan = plans{i};
    value.CaseID(i) = caseIDs(i);
    value.Codeword(i) = "0";
    value.TBS(i) = string(plan.TransportBlockSize);
    value.TBCRCType(i) = string(plan.TBCRCType);
    value.TBCRCLength(i) = string(plan.TBCRCLength);
    value.BaseGraph(i) = string(plan.BaseGraph);
    value.NumCodeBlocks(i) = string(plan.NumCodeBlocks);
    value.CodeBlockCRCType(i) = string(plan.CBCRCType);
    value.LiftingSize(i) = string(plan.LiftingSize);
    value.K(i) = string(plan.CodeBlockLength);
    value.N(i) = string(plan.MotherCodeLength);
    value.Ncb(i) = string(plan.Ncb);
    value.FillerBits(i) = string(plan.FillerCount);
    value.RV(i) = string(plan.RV);
    value.K0(i) = string(plan.K0);
    value.EPerCodeBlock(i) = strjoin(string(plan.EPerCodeBlock), "|");
    value.G(i) = string(plan.RateMatchedBitCount);
    value.RateMatchedBits(i) = string(plan.RateMatchedBitCount);
    value.CRCOK(i) = "1";
end
end

function value = localIndependent(vectorRoot)
families = [ ...
    "scrambling","modulation","layer_mapping","tbs","tb_crc", ...
    "ldpc_segmentation","ldpc_encoding","rate_matching", ...
    "dmrs_positions","dmrs_ports","dmrs_sequence","ptrs_indices", ...
    "reserved_re","precoding_application","harq_combining", ...
    "receiver_chain"].';
value = localBlank(vectorRoot, ...
    "pdsch_independent_vector_results.csv", numel(families));
for i = 1:numel(families)
    digest = localDigestText(families(i) + "-actual");
    value.VectorFamily(i) = families(i);
    value.CaseID(i) = "IND-" + string(i);
    value.ComparedField(i) = "digest";
    value.OracleImplementation(i) = "independent_matlab_spec";
    value.OracleVersion(i) = "1";
    value.OracleArtifactSHA256(i) = ...
        localDigestText(families(i) + "-oracle");
    value.ExpectedDigest(i) = digest;
    value.ActualDigest(i) = digest;
    value.MismatchCount(i) = "0";
    value.MaxAbsError(i) = "0";
    value.Tolerance(i) = "1e-12";
end
end

function value = localLayers(vectorRoot)
n = sum(1:8);
value = localBlank(vectorRoot, "pdsch_layer_codeword_map.csv", n);
cursor = 0;
for rank = 1:8
    for layer = 0:(rank - 1)
        cursor = cursor + 1;
        value.CaseID(cursor) = "RANK-" + string(rank);
        value.Rank(cursor) = string(rank);
        value.Codeword(cursor) = string(double(layer >= 4));
        value.Layer(cursor) = string(layer);
        value.SourceSymbolCount(cursor) = string(96 + layer);
        value.MappedSymbolCount(cursor) = string(96 + layer);
        value.MismatchCount(cursor) = "0";
    end
end
end

function value = localPrecoding(vectorRoot)
value = localBlank(vectorRoot, ...
    "pdsch_precoding_application.csv", 4);
modes = ["wideband_codebook","wideband_noncodebook", ...
    "prg_codebook","prg_frequency_selective"];
for i = 1:4
    digest = localDigestText("precoder-" + string(i));
    value.CaseID(i) = "PREC-ART-" + string(i);
    value.Mode(i) = modes(i);
    value.PRG(i) = string(i - 1);
    value.SymbolGroup(i) = "0";
    value.PRBStart(i) = string((i - 1) * 2);
    value.PRBEnd(i) = string((i - 1) * 2 + 1);
    value.NPorts(i) = "2";
    value.NLayers(i) = "1";
    value.MatrixDigest(i) = digest;
    value.AppliedMatrixDigest(i) = digest;
    value.NormalizationConvention(i) = "unit_frobenius_per_layer";
    value.TXApplicationCount(i) = string(i);
    value.RXApplicationCount(i) = string(i);
    value.PowerRelativeError(i) = "0";
end
end

function value = localHARQ(vectorRoot)
value = localBlank(vectorRoot, "pdsch_harq_trials.csv", 4);
rv = [0 2 3 1];
for i = 1:4
    value.CaseID(i) = "HARQ-ART-1";
    value.HARQProcessID(i) = "1";
    value.Codeword(i) = "0";
    value.TransmissionIndex(i) = string(i - 1);
    value.NDI(i) = "1";
    value.RV(i) = string(rv(i));
    value.TBIdentity(i) = "TB-1";
    value.TBS(i) = "120";
    value.CodeBlockLayoutDigest(i) = localDigestText("layout");
    value.SoftBufferInputDigest(i) = localDigestText( ...
        "soft-in-" + string(i));
    value.SoftBufferOutputDigest(i) = localDigestText( ...
        "soft-out-" + string(i));
    if i == 1
        value.HARQAction(i) = "new_data";
        value.Combined(i) = "0";
    else
        value.HARQAction(i) = "position_aware_combine";
        value.Combined(i) = "1";
    end
    value.TBCRCOK(i) = string(i == 4);
end
end

function value = localReceiver(vectorRoot)
ranks = [1 2 4 8];
n = sum(ranks);
value = localBlank(vectorRoot, "pdsch_receiver_metrics.csv", n);
cursor = 0;
for rank = ranks
    for layer = 0:(rank - 1)
        cursor = cursor + 1;
        value.CaseID(cursor) = "RX-RANK-" + string(rank);
        value.SNRdB(cursor) = "15";
        value.ChannelModel(cursor) = "AWGN";
        value.Rank(cursor) = string(rank);
        value.Codeword(cursor) = string(double(layer >= 4));
        value.Layer(cursor) = string(layer);
        value.DataRECount(cursor) = "132";
        value.LLRCount(cursor) = "264";
        value.RateRecoveredBitCount(cursor) = "264";
        value.MeasuredSINRdB(cursor) = string(15 - 0.2 * layer);
        value.EVMPercent(cursor) = string(2 + 0.1 * layer);
        value.BER(cursor) = "0";
        value.BLER(cursor) = "0";
        value.TBCRCOK(cursor) = "1";
        value.ChannelEstimateNMSEdB(cursor) = "-35";
        value.LDPCIterations(cursor) = "3";
    end
end
end

function value = localBLER(vectorRoot)
value = localBlank(vectorRoot, "pdsch_bler_curve.csv", 4);
errors = [80 50 20 0];
for i = 1:4
    bler = errors(i) / 100;
    value.CampaignID(i) = "AWGN-QPSK";
    value.OperatingPointID(i) = "SNR-" + string(i);
    value.SNRdB(i) = string(i - 3);
    value.ChannelModel(i) = "AWGN";
    value.Rank(i) = "1";
    value.MCSIndex(i) = "4";
    value.Modulation(i) = "QPSK";
    value.Trials(i) = "100";
    value.TBErrors(i) = string(errors(i));
    value.BLER(i) = string(bler);
    value.ConfidenceLevel(i) = "0.95";
    value.CILower(i) = string(max(0, bler - 0.05));
    if errors(i) == 0
        value.CIUpper(i) = string(1 - 0.05^(1/100));
        value.CIHalfWidth(i) = string(str2double(value.CIUpper(i))/2);
        value.StopReason(i) = "MAX_TB_CENSORED_BOUND_MET";
    else
        value.CIUpper(i) = string(min(1, bler + 0.05));
        value.CIHalfWidth(i) = "0.05";
        value.StopReason(i) = "FIXED_TRIAL_BUDGET_COMPLETE";
    end
    value.MinErrorsRequired(i) = "5";
end
end

function value = localNegative(vectorRoot)
value = localBlank(vectorRoot, "pdsch_negative_tests.csv", 1);
value.CaseID = "NEG-ART-1";
value.TestKind = "invalid_dmrs_port";
value.ExpectedErrorIdentifier = ...
    "sixgr:pdsch:DMRSPortUnsupportedForConfiguration";
value.ActualErrorIdentifier = value.ExpectedErrorIdentifier;
value.WaveformGenerated = "0";
end

function value = localSummary(vectorRoot)
value = localBlank(vectorRoot, "pdsch_test_summary.csv", 1);
value.TestSuite = "testPDSCHArtifactExporterFixture";
value.Total = "8";
value.Passed = "8";
value.Failed = "0";
value.Skipped = "0";
value.Blocked = "0";
end

function value = localBlank(vectorRoot, fileName, rows)
contract = readtable(fullfile( ...
    vectorRoot, "desired_pdsch_csv_contract.csv"), ...
    "TextType", "string");
match = contract.FileName == string(fileName);
assert(nnz(match) == 1, "Missing CSV contract for %s.", fileName);
names = split(contract.RequiredColumns(match), "|");
names = names(:).';
value = table();
for name = names
    value.(char(name)) = strings(rows, 1);
end
value.Status(:) = "PASS";
end

function digest = localDigestText(text)
bytes = unicode2native(char(string(text)), "UTF-8");
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(typecast(uint8(bytes), "int8"));
raw = typecast(engine.digest(), "uint8");
digest = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end

function digest = localFileDigest(path)
fid = fopen(path, "rb");
assert(fid >= 0, "Unable to read focused exporter artifact %s.", path);
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");
digest = string(sixgr.util.sha256Hex(bytes));
clear cleanup
end

function localResetDirectory(path)
if isfolder(path)
    rmdir(path, "s");
end
[created, message] = mkdir(path);
assert(created, "Unable to create focused exporter directory: %s", message);
end

function localAssertError(fn, expectedID)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(expectedID), ...
        "Observed %s, expected %s.", ME.identifier, expectedID);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", ...
    "Expected error %s was not thrown.", expectedID);
end
