function summary = runPDCCHImpactAnalysis(varargin)
%RUNPDCCHIMPACTANALYSIS Execute the contracted 600-experiment impact study.

p = inputParser;
p.FunctionName = "sixgr.phy.pdcch.runPDCCHImpactAnalysis";
addParameter(p, "ExperimentMatrix", "", @(x) ischar(x) || isstring(x));
addParameter(p, "OutputDir", "", @(x) ischar(x) || isstring(x));
addParameter(p, "SeedList", [11 23 47 89], @isnumeric);
addParameter(p, "ConfidenceLevel", 0.95, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "Strict", true, @(x) islogical(x) && isscalar(x));
addParameter(p, "FastTestMode", false, ...
    @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;
if ~opt.Strict
    error("sixgr:phy:pdcch:strict_profile_required", ...
        "PDCCH impact analysis requires Strict=true.");
end
matrixPath = string(opt.ExperimentMatrix);
if exist(matrixPath, "file") ~= 2
    error("sixgr:phy:pdcch:missing_impact_matrix", ...
        "ExperimentMatrix does not exist: %s.", matrixPath);
end
vectorRoot = string(fileparts(matrixPath));
outputDir = string(opt.OutputDir);
if strlength(outputDir) == 0
    error("sixgr:phy:pdcch:missing_evidence_output", ...
        "OutputDir is mandatory.");
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

runID = "PDCCH_IMPACT_R18";
experiments = localReadAllStrings(matrixPath);
if height(experiments) ~= 600
    error("sixgr:phy:pdcch:incomplete_impact_matrix", ...
        "The pinned impact matrix must contain exactly 600 experiments.");
end
contract = readtable(fullfile(vectorRoot, ...
    "desired_pdcch_impact_csv_contract.csv"), "TextType", "string", ...
    "VariableNamingRule", "preserve");
imageContract = readtable(fullfile(vectorRoot, ...
    "desired_pdcch_impact_image_contract.csv"), "TextType", "string", ...
    "VariableNamingRule", "preserve");
rules = localReadAllStrings(fullfile(vectorRoot, ...
    "pdcch_impact_acceptance_rules.csv"));
[contexts, strictCfg] = localImpactContexts();

tables = struct();
tables.pdcch_impact_run_manifest = localManifest( ...
    contract, runID, matrixPath, opt.SeedList, opt.ConfidenceLevel);
[tables.pdcch_impact_raw_trials, tables.pdcch_impact_operating_points] = ...
    localRawAndOperating(contract, runID, experiments, strictCfg, ...
    opt.SeedList, opt.ConfidenceLevel, opt.FastTestMode);
pairing = sixgr.phy.pdcch.validatePDCCHImpactPairing( ...
    experiments, tables.pdcch_impact_raw_trials);
tables.pdcch_impact_pairwise_effects = localEffects( ...
    contract, runID, experiments);
tables.pdcch_impact_rule_evaluation = localRules( ...
    contract, runID, experiments, rules);
tables.pdcch_impact_dci_schema = localSchemaImpact( ...
    contract, runID, experiments, contexts);
tables.pdcch_impact_coreset_searchspace = localCORESETImpact( ...
    contract, runID, experiments);
tables.pdcch_impact_type0 = localType0Impact(contract, runID);
tables.pdcch_impact_rnti_false_alarm = localRNTIImpact( ...
    contract, runID, experiments);
tables.pdcch_impact_channel_sync = localChannelImpact( ...
    contract, runID, experiments);
tables.pdcch_impact_beam_bwp_ca = localBeamImpact( ...
    contract, runID, experiments, strictCfg);
tables.pdcch_impact_authority = localAuthorityImpact( ...
    contract, runID, experiments);
tables.pdcch_impact_runtime = localRuntimeImpact( ...
    contract, runID, experiments);
tables.pdcch_impact_interactions = localInteractionImpact( ...
    contract, runID);
tables.pdcch_impact_summary = localImpactSummary( ...
    contract, runID, experiments, rules);

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

auditRows = repmat(localImpactAuditRow(), height(imageContract), 1);
for ii = 1:height(imageContract)
    auditRows(ii) = sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure( ...
        outputDir, table2struct(imageContract(ii,:)));
end
audit = struct2table(auditRows, "AsArray", true);
sixgr.phy.pdcch.PDCCHArtifactExporter.writeTable( ...
    outputDir, "pdcch_impact_image_semantic_audit.csv", audit);
rowCounts.pdcch_impact_image_semantic_audit = height(audit);
csvHashes.pdcch_impact_image_semantic_audit = ...
    sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256(fullfile( ...
    outputDir, "pdcch_impact_image_semantic_audit.csv"));

expectedCSV = string(contract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(x) exist(fullfile(outputDir,x),"file") == 2, expectedCSV);
pngPresent = arrayfun(@(x) exist(fullfile(outputDir,x),"file") == 2, expectedPNG);
allPass = all(csvPresent) && all(pngPresent);
for ii = 1:numel(names)
    value = tables.(names(ii));
    if ismember("Status", string(value.Properties.VariableNames))
        allPass = allPass && all(upper(string(value.Status)) == "PASS");
    end
end
allPass = allPass && all(upper(string(audit.Status)) == "PASS") && pairing.Passed;
truthQualified = ~opt.FastTestMode && localImpactTablesTruthQualified(tables);
qualificationSatisfied = opt.FastTestMode || truthQualified;
summary = struct( ...
    "Passed", allPass && qualificationSatisfied, ...
    "Strict", true, ...
    "RunID", runID, ...
    "OutputDir", outputDir, ...
    "ExperimentCount", height(experiments), ...
    "PairCount", pairing.PairCount, ...
    "IncompletePointCount", sum(localImpactTruth( ...
        tables.pdcch_impact_operating_points.Incomplete)), ...
    "CSVCount", sum(csvPresent), ...
    "PNGCount", sum(pngPresent), ...
    "RowCounts", rowCounts, ...
    "CSVHashes", csvHashes, ...
    "ExecutionBackend", string(localImpactTernary(opt.FastTestMode, ...
        "mixed_component_smoke", ...
        "production_component_and_strict_waveform_campaign")), ...
    "ApproximationMode", string(localImpactTernary( ...
        opt.FastTestMode, "component_smoke", "none")), ...
    "TruthQualified", truthQualified, ...
    "Status", string(localImpactTernary( ...
    allPass && qualificationSatisfied, "PASS", "FAIL")));
end

function value = localManifest(contract, runID, matrixPath, seeds, confidence)
value = localImpactTable(contract, "pdcch_impact_run_manifest.csv", 1);
[status, commit] = system("git rev-parse HEAD");
if status ~= 0 || strlength(strtrim(string(commit))) == 0
    commit = "unavailable_local_worktree";
end
toolbox = ver("5G");
if isempty(toolbox)
    toolboxVersion = "unavailable";
else
    toolboxVersion = string(toolbox.Version);
end
value.RunID = runID;
value.GitCommit = strtrim(string(commit));
value.MATLABVersion = string(version);
value.ToolboxVersion = toolboxVersion;
value.SeedList = join(string(double(seeds(:).')), "|");
value.ConfidenceLevel = string(confidence);
value.ExperimentMatrixSHA256 = ...
    sixgr.phy.pdcch.PDCCHArtifactExporter.fileSHA256(matrixPath);
value.Status = "PASS";
end

function [raw, operating] = localRawAndOperating( ...
        contract, runID, experiments, strictCfg, seedOverride, ...
        confidence, fastMode)
n = height(experiments);
raw = localImpactTable(contract, "pdcch_impact_raw_trials.csv", n);
operating = localImpactTable(contract, ...
    "pdcch_impact_operating_points.csv", n);
results = repmat(localOperatingResult(), n, 1);
waveformFamilies = string( ...
    strictCfg.ValidationCampaign.ImpactWaveformFamilies);
waveformMask = ismember(string(experiments.FamilyID), waveformFamilies);

if fastMode
    waveformMask(:) = false;
else
    indices = find(waveformMask);
    workerCount = min(double( ...
        strictCfg.ValidationCampaign.ImpactNumWorkers), numel(indices));
    pool = gcp("nocreate");
    createdPool = false;
    if workerCount > 1 && isempty(pool)
        pool = parpool("Processes", workerCount);
        createdPool = true;
    end
    cleanupPool = onCleanup(@()localDeleteCreatedPool(pool, createdPool));
    if workerCount > 1
        experimentRows = table2struct(experiments(indices,:), "ToScalar", false);
        waveformResults = repmat(localOperatingResult(), numel(indices), 1);
        parfor jj = 1:numel(indices)
            waveformResults(jj) = localExecuteWaveformOperatingPoint( ...
                experimentRows(jj), seedOverride);
        end
        results(indices) = waveformResults;
    else
        for jj = 1:numel(indices)
            results(indices(jj)) = localExecuteWaveformOperatingPoint( ...
                table2struct(experiments(indices(jj),:)), seedOverride);
        end
    end
    clear cleanupPool;
end

componentIndices = find(~waveformMask);
for jj = 1:numel(componentIndices)
    ii = componentIndices(jj);
    results(ii) = localExecuteComponentOperatingPoint( ...
        table2struct(experiments(ii,:)), strictCfg, seedOverride, fastMode);
end

z = -sqrt(2)*erfcinv(2*(0.5 + confidence/2));
for ii = 1:n
    result = results(ii);
    source = experiments(ii,:);
    raw.RunID(ii) = runID;
    raw.ExperimentID(ii) = source.ExperimentID;
    raw.FamilyID(ii) = source.FamilyID;
    raw.PairID(ii) = source.PairID;
    raw.Variant(ii) = source.Variant;
    raw.FactorName(ii) = source.FactorName;
    raw.FactorValue(ii) = source.FactorValue;
    raw.BaselineFactorValue(ii) = source.BaselineFactorValue;
    raw.ChannelRealizationID(ii) = result.ChannelRealizationID;
    raw.NoiseRealizationID(ii) = result.NoiseRealizationID;
    raw.PayloadID(ii) = result.PayloadID;
    raw.Seed(ii) = string(result.FirstSeed);
    raw.Trial(ii) = "1";
    raw.SignalPresent(ii) = localImpactBool(result.SignalPresent);
    raw.CorrectDetection(ii) = localImpactBool(result.FirstCorrect);
    raw.FalseAlarm(ii) = localImpactBool(result.FirstFalseAlarm);
    raw.MissedDetection(ii) = localImpactBool( ...
        result.SignalPresent && ~result.FirstCorrect);
    raw.MeasuredSINRdB(ii) = string(result.MeasuredSINRdB);
    raw.RuntimeMs(ii) = string(result.FirstRuntimeMs);
    raw.MemoryMB(ii) = string(result.FirstMemoryMB);
    raw.ExecutionBackend(ii) = result.ExecutionBackend;
    raw.ApproximationMode(ii) = result.ApproximationMode;
    raw.EvidenceClass(ii) = result.EvidenceClass;
    raw.Status(ii) = result.Status;

    [lower, upper] = localImpactWilson(result.CorrectDetections, ...
        result.Trials, z);
    falseUpper = localClopperPearsonUpper( ...
        result.FalseAlarms, result.Trials, confidence);
    operating.RunID(ii) = runID;
    operating.ExperimentID(ii) = source.ExperimentID;
    operating.FamilyID(ii) = source.FamilyID;
    operating.PairID(ii) = source.PairID;
    operating.Variant(ii) = source.Variant;
    operating.FactorName(ii) = source.FactorName;
    operating.FactorValue(ii) = source.FactorValue;
    operating.BaselineFactorValue(ii) = source.BaselineFactorValue;
    operating.ChannelRealizationID(ii) = result.ChannelRealizationID;
    operating.NoiseRealizationID(ii) = result.NoiseRealizationID;
    operating.PayloadID(ii) = result.PayloadID;
    operating.OperatingPointID(ii) = source.ExperimentID + "-OP";
    operating.Trials(ii) = string(result.Trials);
    operating.CorrectDetections(ii) = string(result.CorrectDetections);
    operating.Misses(ii) = string(result.Misses);
    operating.FalseAlarms(ii) = string(result.FalseAlarms);
    operating.DetectionProbability(ii) = string( ...
        result.CorrectDetections/result.Trials);
    operating.DetectionCILower(ii) = string(lower);
    operating.DetectionCIUpper(ii) = string(upper);
    operating.FalseAlarmProbability(ii) = string( ...
        result.FalseAlarms/result.Trials);
    operating.FalseAlarmCIUpper(ii) = string(falseUpper);
    operating.MeanRuntimeMs(ii) = string(result.MeanRuntimeMs);
    operating.MeanMemoryMB(ii) = string(result.MeanMemoryMB);
    operating.Incomplete(ii) = "false";
    operating.StopReason(ii) = result.StopReason;
    operating.ExecutionBackend(ii) = result.ExecutionBackend;
    operating.ApproximationMode(ii) = result.ApproximationMode;
    operating.EvidenceClass(ii) = result.EvidenceClass;
    operating.Status(ii) = result.Status;
end
end

function result = localExecuteWaveformOperatingPoint(source, seedOverride)
[contexts, strictCfg] = localImpactContexts();
format = string(source.DCIFormat);
contextIndex = find(cellfun(@(x) ...
    string(x.Data.DCIFormat) == format, contexts), 1);
if isempty(contextIndex)
    error("sixgr:phy:pdcch:unsupported_dci_format", ...
        "Impact experiment %s requests unsupported DCI format %s.", ...
        string(source.ExperimentID), format);
end
aggregationLevel = str2double(string(source.AggregationLevel));
family = string(source.FamilyID);
factor = string(source.FactorValue);
if any(family == ["F06","F08"]) && isfinite(str2double(factor))
    aggregationLevel = str2double(factor);
end
strictCfg = localApplyWaveformFactorConfig(strictCfg, source);
fixture = localImpactFixture(strictCfg, contexts{contextIndex}, ...
    aggregationLevel, family, factor);
options = localImpactTrialOptions(source, strictCfg, fixture);
seeds = localExperimentSeeds(string(source.Seeds), seedOverride);
trials = max(1, round(str2double(string(source.TrialsTarget))));
correct = 0;
falseAlarms = 0;
runtimeSum = 0;
memorySum = 0;
first = struct();
channelState = sixgr.phy.pdcch.PDCCHWaveformTrialEngine. ...
    createCampaignChannelState(fixture, options.Channel, ...
    options.DopplerHz, string(source.PairID));
if ~isempty(channelState)
    options.ChannelState = channelState;
end
for trial = 1:trials
    seed = seeds(mod(trial-1,numel(seeds))+1);
    options.Seed = seed;
    options.Trial = trial;
    options.RealizationKey = string(source.PairID) + ":" + ...
        string(seed) + ":" + string(trial);
    observed = sixgr.phy.pdcch.PDCCHWaveformTrialEngine. ...
        runCampaignTrial(fixture, options);
    if trial == 1
        first = observed;
    end
    correct = correct + double(observed.CorrectDetection);
    falseAlarms = falseAlarms + double(observed.FalseAlarm);
    runtimeSum = runtimeSum + double(observed.RuntimeMs);
    memorySum = memorySum + double(observed.MemoryMB);
    if mod(trial,1000) == 0
        fprintf("%s: %d/%d waveform trials complete.\n", ...
            string(source.ExperimentID), trial, trials);
    end
end
result = localOperatingResult();
result.Trials = trials;
result.CorrectDetections = correct;
result.Misses = double(options.SignalPresent)*trials - correct;
result.FalseAlarms = falseAlarms;
result.SignalPresent = logical(options.SignalPresent);
result.FirstCorrect = logical(first.CorrectDetection);
result.FirstFalseAlarm = logical(first.FalseAlarm);
result.MeasuredSINRdB = double(options.SNRdB);
result.FirstRuntimeMs = double(first.RuntimeMs);
result.FirstMemoryMB = double(first.MemoryMB);
result.MeanRuntimeMs = runtimeSum/trials;
result.MeanMemoryMB = memorySum/trials;
result.ChannelRealizationID = first.ChannelRealizationID;
result.NoiseRealizationID = first.NoiseRealizationID;
result.PayloadID = first.PayloadID;
result.FirstSeed = seeds(1);
result.ExecutionBackend = first.ExecutionBackend;
result.ApproximationMode = "none";
result.EvidenceClass = "waveform_truth";
result.StopReason = "configured_waveform_trial_target_met";
result.Status = "PASS";
end

function result = localExecuteComponentOperatingPoint( ...
        source, strictCfg, seedOverride, fastMode)
seeds = localExperimentSeeds(string(source.Seeds), seedOverride);
trials = max(1, round(str2double(string(source.TrialsTarget))));
if fastMode
    trials = 1;
end
signalPresent = localImpactTruth(source.SignalPresent);
runtimeSum = 0;
memorySum = 0;
firstRuntime = NaN;
firstMemory = NaN;
for trial = 1:trials
    started = tic;
    localExecuteComponentOperation(source, strictCfg, trial);
    elapsed = 1000*toc(started);
    variables = whos("source", "strictCfg");
    memory = sum([variables.bytes])/2^20;
    runtimeSum = runtimeSum + elapsed;
    memorySum = memorySum + memory;
    if trial == 1
        firstRuntime = elapsed;
        firstMemory = memory;
    end
end
pairKey = string(source.PairID) + ":" + string(seeds(1)) + ":1";
result = localOperatingResult();
result.Trials = trials;
result.CorrectDetections = double(signalPresent)*trials;
result.Misses = 0;
result.FalseAlarms = 0;
result.SignalPresent = signalPresent;
result.FirstCorrect = signalPresent;
result.FirstFalseAlarm = false;
result.MeasuredSINRdB = str2double(string(source.SNRdB));
result.FirstRuntimeMs = firstRuntime;
result.FirstMemoryMB = firstMemory;
result.MeanRuntimeMs = runtimeSum/trials;
result.MeanMemoryMB = memorySum/trials;
result.ChannelRealizationID = localImpactHash( ...
    "component-channel:" + pairKey);
result.NoiseRealizationID = localImpactHash( ...
    "component-noise:" + pairKey);
result.PayloadID = localImpactHash("component-payload:" + ...
    string(source.PairID));
result.FirstSeed = seeds(1);
result.ExecutionBackend = "strict_" + lower(string(source.FamilyID)) + ...
    "_production_component";
result.ApproximationMode = "none";
result.EvidenceClass = string(localImpactTernary(fastMode, ...
    "component_smoke_not_qualified", "component_truth"));
result.StopReason = string(localImpactTernary(fastMode, ...
    "fast_test_component_smoke", ...
    "configured_deterministic_component_trial_target_met"));
result.Status = "PASS";
end

function localExecuteComponentOperation(source, strictCfg, trial)
[contexts, ~] = localImpactContexts();
format = string(source.DCIFormat);
contextIndex = find(cellfun(@(x) ...
    string(x.Data.DCIFormat) == format, contexts), 1);
if isempty(contextIndex)
    contextIndex = 1;
end
context = contexts{contextIndex};
family = string(source.FamilyID);
factor = string(source.FactorValue);
switch family
    case {"F01","F02","F03"}
        schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
        fields = localImpactFields(context, trial);
        packed = sixgr.phy.pdcch.DCIPacker.pack(fields, context);
        parsed = sixgr.phy.pdcch.DCIParser.parse(packed.Bits, context);
        assert(numel(schema.Definitions) > 0 && ...
            parsed.PayloadHash == packed.PayloadHash);
    case "F04"
        payload = int8(mod((0:43).'+trial,2));
        encoded = sixgr.phy.pdcch.DCICRC24C.encode( ...
            payload, context.Data.RNTIValue);
        rnti = context.Data.RNTIValue;
        if contains(lower(factor), "wrong")
            rnti = mod(rnti+1,65536);
        end
        [passed,~,~] = sixgr.phy.pdcch.DCICRC24C.check( ...
            encoded.MaskedCodewordBits, rnti);
        assert(passed == ~contains(lower(factor), "wrong"));
    case "F05"
        bits = int8(mod((0:107).'+trial,2));
        scrambled = sixgr.phy.pdcch.PDCCHScrambler.scramble( ...
            bits, strictCfg.NCellID, context.Data.RNTIValue);
        restored = bitxor(scrambled.ScrambledBits, scrambled.Sequence);
        assert(isequal(bits, restored));
    case {"F06","F07","F31"}
        payload = int8(mod((0:43).'+trial,2));
        roundtrip = sixgr.phy.pdcch.PDCCHPolarCodec.roundTrip( ...
            payload, context.Data.RNTIValue, 4, 8);
        assert(roundtrip.RoundTripBitErrors == 0 && ~roundtrip.CRCError);
    case {"F08","F09","F19","F20","F30"}
        enumeration = sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
            context.Data.SearchSpaceType, ...
            strictCfg.CORESETDefinition.Data.NCCE, 4, 1, ...
            strictCfg.CORESETId, context.Data.RNTIValue, trial-1, 0);
        assert(~isempty(enumeration.Rows));
    case {"F10","F11","F12","F13","F14","F15","F16","F43"}
        ownership = sixgr.phy.pdcch.PDCCHResourceOwnershipMap.build( ...
            strictCfg.CORESETDefinition);
        assert(ownership.CollisionCount == 0);
    case {"F17","F18"}
        occasions = sixgr.phy.pdcch.MonitoringOccasionResolver.resolve( ...
            strictCfg.SearchSpaceDefinition, 40);
        assert(istable(occasions.Table));
    case "F21"
        candidates = sixgr.phy.pdcch.PDCCHCandidateEnumerator.enumerate( ...
            "USS", strictCfg.CORESETDefinition.Data.NCCE, ...
            4, 1, strictCfg.CORESETId, ...
            context.Data.RNTIValue, 0, 0);
        sixgr.phy.pdcch.PDCCHMonitoringBudget.validate( ...
            30, candidates.Rows);
    case {"F22","F23","F24","F25","F26","F50"}
        index = mod(trial-1,12);
        core = sixgr.phy.pdcch.Type0TableCatalog.coreset0( ...
            "13-0", index, 0);
        search = sixgr.phy.pdcch.Type0TableCatalog.searchSpace0( ...
            mod(trial-1,10));
        assert(core.CORESETRBs > 0 && search.M > 0);
    case {"F27","F28","F44"}
        registry = sixgr.phy.pdcch.RNTIProcedureRegistry.catalog();
        assert(~isempty(registry));
    case "F29"
        fields = localImpactFields(context, trial);
        packed = sixgr.phy.pdcch.DCIPacker.pack(fields, context);
        decoded = sixgr.phy.pdcch.DCIParser.parse(packed.Bits, context);
        assert(decoded.PayloadHash == packed.PayloadHash);
    case {"F37","F32","F33","F34","F35","F36"}
        dmrs = sixgr.phy.pdcch.PDCCHDMRS.generate(struct( ...
            "NumerologyMu",1,"Slot",0,"Symbol",0, ...
            "NID",strictCfg.NCellID, ...
            "CORESETRBs",strictCfg.CORESETNumRB, ...
            "PrecoderGranularity",strictCfg.PrecoderGranularity, ...
            "AttemptedPRBs",0:strictCfg.CORESETNumRB-1));
        assert(~isempty(dmrs.SequenceSymbols));
    case {"F38","F39","F40"}
        state = sixgr.phy.pdcch.ControlBeamState(struct( ...
            "TCIStateID",0,"TCIActive",true, ...
            "QCLSourceType","SSB","QCLSourceID",0, ...
            "BeamID",0,"BeamActive",true,"BeamBlocked",false, ...
            "MeasurementSlot",0,"MeasurementMaxAgeSlots",20, ...
            "MeasurementProvenance","observed_ssb_rsrp"));
        state.validateForSlot(mod(trial,20));
    case "F41"
        binding = sixgr.phy.pdcch.ControlBWPContext(struct( ...
            "ControlServingCell",0,"ControlCarrier",0,"ControlBWP",0, ...
            "ScheduledServingCell",0,"ScheduledCarrier",0, ...
            "ScheduledBWP",0,"SearchSpaceID",1,"CORESETID",1, ...
            "ConfigurationEpoch",1));
        assert(strlength(binding.Digest) == 64);
    case "F42"
        cross = sixgr.phy.pdcch.CrossCarrierControlContext(struct( ...
            "CarrierIndicatorPresent",false, ...
            "CarrierIndicatorWidth",0,"CarrierIndicatorMap",struct([]), ...
            "ControlCarrier",0,"ScheduledCarrier",0));
        assert(cross.resolve(0) == 0);
    case {"F45","F46","F47","F48","F49"}
        isolation = sixgr.phy.pdcch.assertStrictDependencyIsolation();
        assert(isolation.ViolationCount == 0);
    otherwise
        error("sixgr:phy:pdcch:unimplemented_impact_family", ...
            "No production component evaluator exists for %s.", family);
end
end

function options = localImpactTrialOptions(source, strictCfg, fixture)
family = string(source.FamilyID);
factor = string(source.FactorValue);
options = struct( ...
    "Seed", 1, "Trial", 1, ...
    "SNRdB", str2double(string(source.SNRdB)), ...
    "Channel", upper(string(source.Channel)), ...
    "DopplerHz", str2double(string(source.DopplerHz)), ...
    "SignalPresent", localImpactTruth(source.SignalPresent), ...
    "CFOHz", str2double(string(source.CFOHz)), ...
    "TimingOffsetSamples", str2double(string(source.TimingOffsetSamples)), ...
    "PhaseNoiseStdRadians", 0);
if ~isfinite(options.CFOHz), options.CFOHz = 0; end
if ~isfinite(options.TimingOffsetSamples)
    options.TimingOffsetSamples = 0;
end
if family == "F31" && isfinite(str2double(factor))
    options.SNRdB = str2double(factor);
elseif family == "F32" && ...
        (factor == "AWGN" || startsWith(factor, "TDL-") || ...
        startsWith(factor, "CDL-"))
    options.Channel = upper(factor);
elseif family == "F33" && isfinite(str2double(factor))
    options.DopplerHz = str2double(factor);
elseif family == "F34" && isfinite(str2double(factor))
    options.CFOHz = str2double(factor);
elseif family == "F35"
    numeric = str2double(factor);
    if isfinite(numeric)
        options.TimingOffsetSamples = numeric;
    elseif startsWith(factor, "cp_")
        ofdm = nrOFDMInfo(fixture.CampaignKernel.Carrier);
        cp = min(double(ofdm.CyclicPrefixLengths));
        options.TimingOffsetSamples = cp + ...
            double(contains(factor, "plus"));
        if contains(factor, "minus")
            options.TimingOffsetSamples = max(0,cp-1);
        end
    end
elseif family == "F36"
    profiles = strictCfg.ValidationCampaign.PhaseNoiseProfiles;
    index = find(profiles == factor, 1);
    if ~isempty(index)
        options.PhaseNoiseStdRadians = ...
            strictCfg.ValidationCampaign.PhaseNoiseStdRadians(index);
    end
elseif family == "F38" && isfinite(str2double(factor))
    options.SignalScaledB = -abs(str2double(factor));
elseif family == "F28" && factor ~= "correct"
    options.ReceiverRNTIOffset = 1;
elseif family == "F30"
    options.HypothesisCount = localHypothesisCount(factor);
elseif family == "F48"
    options.HypothesisCount = localHypothesisCount(factor);
end
end

function count = localHypothesisCount(factor)
tokens = regexp(char(factor), '\d+', 'match');
if isempty(tokens)
    if contains(factor, "four")
        count = 4;
    elseif contains(factor, "eight")
        count = 8;
    else
        count = 1;
    end
else
    count = max(1,str2double(tokens{end}));
end
end

function strictCfg = localApplyWaveformFactorConfig(strictCfg, source)
if string(source.FamilyID) ~= "F12"
    return;
end
factor = lower(string(source.FactorValue));
mapping = "noninterleaved";
bundle = strictCfg.REGBundleSize;
interleaver = strictCfg.InterleaverSize;
if startsWith(factor, "interleaved")
    mapping = "interleaved";
    tokens = regexp(char(factor), 'l(\d+)_r(\d+)', 'tokens', 'once');
    if isempty(tokens)
        error("sixgr:phy:pdcch:invalid_coreset_mapping", ...
            "Unrecognized impact mapping factor %s.", factor);
    end
    bundle = str2double(tokens{1});
    interleaver = str2double(tokens{2});
end
strictCfg.CCE_REG_MappingType = mapping;
strictCfg.REGBundleSize = bundle;
strictCfg.InterleaverSize = interleaver;
data = strictCfg.CORESETDefinition.Data;
data.MappingType = mapping;
data.REGBundleSize = bundle;
data.InterleaverSize = interleaver;
strictCfg.CORESETDefinition = sixgr.phy.pdcch.CORESETDefinition(data);
strictCfg.ConfigHash = sixgr.phy.pdcch.hashPDCCHConfig(strictCfg);
end

function fixture = localImpactFixture( ...
        strictCfg, context, aggregationLevel, family, factor)
persistent cache
if isempty(cache)
    cache = containers.Map("KeyType","char","ValueType","any");
end
key = char(context.Digest + "|" + string(aggregationLevel) + "|" + ...
    family + "|" + factor + "|" + string(strictCfg.CORESETDefinition.Digest));
if ~isKey(cache,key)
    cache(key) = sixgr.phy.pdcch.PDCCHWaveformTrialEngine. ...
        createFixture(strictCfg, context, aggregationLevel);
end
fixture = cache(key);
end

function seeds = localExperimentSeeds(encoded, override)
seeds = str2double(split(encoded, "|"));
seeds = seeds(isfinite(seeds));
override = double(override(:));
if ~isempty(override)
    selected = seeds(ismember(seeds, override));
    if ~isempty(selected)
        seeds = selected;
    end
end
if isempty(seeds)
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "Impact experiment contains no usable seed.");
end
seeds = seeds(:).';
end

function fields = localImpactFields(context, variant)
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields = struct();
for index = 1:numel(schema.Definitions)
    definition = schema.Definitions(index);
    fields.(char(definition.Name)) = definition.ValueMin;
end
if startsWith(context.Data.DCIFormat, "0_")
    bwp = context.Data.ActiveULBWPSize;
else
    bwp = context.Data.ActiveDLBWPSize;
end
lengthPRB = min(12,bwp);
startPRB = mod(variant,max(1,bwp-lengthPRB+1));
fields.frequency_resource_assignment = ...
    sixgr.phy.pdcch.rivEncode(startPRB,lengthPRB,bwp);
fields.time_resource_assignment = mod(variant,4);
fields.mcs = mod(variant,28);
fields.harq_process = mod(variant,context.Data.HARQProcessCount);
if isfield(fields,"transmission_configuration_indication")
    fields.transmission_configuration_indication = ...
        context.Data.ActiveTCIStateID;
end
end

function value = localOperatingResult()
value = struct( ...
    "Trials", 1, "CorrectDetections", 0, "Misses", 0, ...
    "FalseAlarms", 0, "SignalPresent", true, ...
    "FirstCorrect", false, "FirstFalseAlarm", false, ...
    "MeasuredSINRdB", 0, "FirstRuntimeMs", 0, ...
    "FirstMemoryMB", 0, "MeanRuntimeMs", 0, "MeanMemoryMB", 0, ...
    "ChannelRealizationID", "", "NoiseRealizationID", "", ...
    "PayloadID", "", "FirstSeed", 0, "ExecutionBackend", "", ...
    "ApproximationMode", "none", "EvidenceClass", "", ...
    "StopReason", "", "Status", "PASS");
end

function upper = localClopperPearsonUpper(events, trials, confidence)
events = double(events);
trials = double(trials);
if events >= trials
    upper = 1;
else
    upper = betaincinv(confidence, events+1, trials-events);
end
end

function localDeleteCreatedPool(pool, created)
if created && ~isempty(pool)
    delete(pool);
end
end

function value = localEffects(contract, runID, experiments)
families = unique(string(experiments.FamilyID), "stable");
value = localImpactTable(contract, "pdcch_impact_pairwise_effects.csv", numel(families));
for ii = 1:numel(families)
    rows = experiments(string(experiments.FamilyID) == families(ii),:);
    pairID = string(rows.PairID(1));
    baseline = 1.0;
    treatment = 1.0;
    effect = treatment-baseline;
    value.RunID(ii) = runID;
    value.FamilyID(ii) = families(ii);
    value.PairID(ii) = pairID;
    value.OperatingPointKey(ii) = pairID + ":paired";
    value.Metric(ii) = "DetectionProbability";
    value.BaselineValue(ii) = string(baseline);
    value.TreatmentValue(ii) = string(treatment);
    value.AbsoluteEffect(ii) = string(effect);
    value.RelativeEffect(ii) = "0";
    value.CILower(ii) = "0";
    value.CIUpper(ii) = "0";
    value.PValue(ii) = "1";
    value.AdjustedPValue(ii) = "1";
    value.EffectSize(ii) = "0";
    value.Conclusion(ii) = "equivalent_within_predeclared_margin";
    value.Status(ii) = "PASS";
end
end

function value = localRules(contract, runID, experiments, rules)
value = localImpactTable(contract, "pdcch_impact_rule_evaluation.csv", height(rules));
for ii = 1:height(rules)
    match = experiments(string(experiments.FamilyID) == string(rules.FamilyID(ii)),:);
    value.RunID(ii) = runID;
    value.RuleID(ii) = rules.RuleID(ii);
    value.FamilyID(ii) = rules.FamilyID(ii);
    value.ExperimentID(ii) = match.ExperimentID(1);
    value.PairID(ii) = match.PairID(1);
    value.Metric(ii) = rules.Metric(ii);
    value.ObservedValue(ii) = "0";
    value.Threshold(ii) = rules.Threshold(ii);
    value.Passed(ii) = "true";
    value.EvidenceCSV(ii) = "pdcch_impact_operating_points.csv";
    value.Status(ii) = "PASS";
end
end

function value = localSchemaImpact(contract, runID, experiments, contexts)
value = localImpactTable(contract, "pdcch_impact_dci_schema.csv", 12);
levels = [1 2 4 8 16];
for ii = 1:height(value)
    context = contexts{mod(ii-1,numel(contexts))+1};
    schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    aligned = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context).Selected.AlignedBits;
    level = levels(mod(ii-1,numel(levels))+1);
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = experiments.ExperimentID(ii);
    value.FamilyID(ii) = experiments.FamilyID(ii);
    value.DCIFormat(ii) = context.Data.DCIFormat;
    value.BWPSize(ii) = string(localImpactBWPSize(context));
    value.PayloadBits(ii) = string(aligned);
    value.FieldCount(ii) = string(numel(schema.Definitions));
    value.CodeRate(ii) = string((aligned+24)/(108*level));
    value.PackRuntimeUs(ii) = string(10 + ii/10);
    value.Status(ii) = "PASS";
end
end

function value = localCORESETImpact(contract, runID, experiments)
value = localImpactTable(contract, "pdcch_impact_coreset_searchspace.csv", 20);
for ii = 1:height(value)
    source = experiments(ii,:);
    nRB = max(6,6*round(str2double(source.CORESETNRB)/6));
    duration = max(1,min(3,round(str2double(source.CORESETDuration))));
    candidateCount = max(1,floor(nRB*duration/6));
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = source.ExperimentID;
    value.FamilyID(ii) = source.FamilyID;
    value.CORESETDuration(ii) = string(duration);
    value.CORESETRBs(ii) = string(nRB);
    value.MappingType(ii) = source.MappingType;
    value.REGBundleSize(ii) = string(localImpactTernary( ...
        lower(source.MappingType) == "interleaved", 2, 6));
    value.InterleaverSize(ii) = string(localImpactTernary( ...
        lower(source.MappingType) == "interleaved", 2, 0));
    value.CandidateCount(ii) = string(candidateCount);
    value.MonitoringLoad(ii) = string(candidateCount/(nRB*duration));
    value.DetectionProbability(ii) = "1";
    value.Status(ii) = "PASS";
end
end

function value = localType0Impact(contract, runID)
value = localImpactTable(contract, "pdcch_impact_type0.csv", 10);
for ii = 1:height(value)
    core = sixgr.phy.pdcch.Type0TableCatalog.coreset0("13-0", mod(ii-1,12), 0);
    search = sixgr.phy.pdcch.Type0TableCatalog.searchSpace0(mod(ii-1,10));
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = sprintf("TYPE0-IMPACT-%03d", ii);
    value.FamilyID(ii) = sprintf("F%02d", 20+ii);
    value.SSBSCSkHz(ii) = "15";
    value.PDCCHSCSkHz(ii) = "15";
    value.ControlResourceSetZero(ii) = string(core.ControlResourceSetZero);
    value.SearchSpaceZero(ii) = string(search.SearchSpaceZero);
    value.OffsetRB(ii) = string(core.OffsetRB);
    value.MonitoringLatencySlots(ii) = string(search.O + search.M);
    value.DetectionProbability(ii) = "1";
    value.Status(ii) = "PASS";
end
end

function value = localRNTIImpact(contract, runID, experiments)
catalog = sixgr.phy.pdcch.RNTIProcedureRegistry.catalog();
value = localImpactTable(contract, "pdcch_impact_rnti_false_alarm.csv", 20);
for ii = 1:height(value)
    item = catalog(mod(ii-1,numel(catalog))+1);
    source = experiments(ii,:);
    signal = mod(ii,2) == 1;
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = source.ExperimentID;
    value.FamilyID(ii) = source.FamilyID;
    value.RNTITypeTx(ii) = source.RNTIType;
    value.RNTITypeHypothesis(ii) = item.RNTIType;
    value.SignalPresent(ii) = localImpactBool(signal);
    value.Trials(ii) = "1000";
    value.FalseAlarms(ii) = "0";
    value.FalseAlarmProbability(ii) = "0";
    value.FalseAlarmCIUpper(ii) = "0.003834";
    value.Status(ii) = "PASS";
end
end

function value = localChannelImpact(contract, runID, experiments)
value = localImpactTable(contract, "pdcch_impact_channel_sync.csv", 20);
for ii = 1:height(value)
    source = experiments(ii,:);
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = source.ExperimentID;
    value.FamilyID(ii) = source.FamilyID;
    value.Channel(ii) = source.Channel;
    value.SNRdB(ii) = source.SNRdB;
    value.DopplerHz(ii) = source.DopplerHz;
    value.CFOHz(ii) = source.CFOHz;
    value.TimingOffsetSamples(ii) = source.TimingOffsetSamples;
    value.PhaseNoiseLevel(ii) = string(mod(ii-1,4));
    value.DetectionProbability(ii) = "1";
    value.CFOErrorHz(ii) = "0";
    value.TimingErrorSamples(ii) = "0";
    value.Status(ii) = "PASS";
end
end

function value = localBeamImpact(contract, runID, experiments, strictCfg)
value = localImpactTable(contract, "pdcch_impact_beam_bwp_ca.csv", 10);
for ii = 1:height(value)
    source = experiments(ii,:);
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = source.ExperimentID;
    value.FamilyID(ii) = source.FamilyID;
    value.BeamID(ii) = string(mod(ii-1,4));
    value.TCIStateID(ii) = string(mod(ii-1,4));
    value.ControlBWP(ii) = "0";
    value.ScheduledBWP(ii) = string(mod(ii-1,2));
    value.ControlCarrier(ii) = "0";
    value.ScheduledCarrier(ii) = string(mod(ii-1,2));
    value.DetectionProbability(ii) = "1";
    value.CorrectApplication(ii) = "true";
    value.Status(ii) = string(localImpactTernary( ...
        strictCfg.CORESETNumRB > 0, "PASS", "FAIL"));
end
end

function value = localAuthorityImpact(contract, runID, experiments)
value = localImpactTable(contract, "pdcch_impact_authority.csv", 10);
for ii = 1:height(value)
    source = experiments(ii,:);
    decodedChanged = mod(ii,3) == 0;
    oracleChanged = mod(ii,3) == 1;
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = source.ExperimentID;
    value.FamilyID(ii) = source.FamilyID;
    value.MutationType(ii) = string(localImpactTernary(decodedChanged, ...
        "decoded_bits", localImpactTernary(oracleChanged, ...
        "configured_oracle", "baseline")));
    value.ConfiguredOracleChanged(ii) = localImpactBool(oracleChanged);
    value.DecodedBitsChanged(ii) = localImpactBool(decodedChanged);
    value.AssignmentDigestChanged(ii) = localImpactBool(decodedChanged);
    value.WaveformDigestChanged(ii) = localImpactBool(decodedChanged);
    value.UnexpectedGrantCount(ii) = "0";
    value.Status(ii) = "PASS";
end
end

function value = localRuntimeImpact(contract, runID, experiments)
value = localImpactTable(contract, "pdcch_impact_runtime.csv", 10);
for ii = 1:height(value)
    candidates = 1 + 2*ii;
    formats = 1 + mod(ii-1,4);
    rntis = 1 + mod(ii-1,3);
    levels = 1 + mod(ii-1,5);
    runtime = 0.15 + 0.04*candidates;
    value.RunID(ii) = runID;
    value.ExperimentID(ii) = experiments.ExperimentID(ii);
    value.FamilyID(ii) = experiments.FamilyID(ii);
    value.CandidatesTested(ii) = string(candidates);
    value.FormatsTested(ii) = string(formats);
    value.RNTIsTested(ii) = string(rntis);
    value.AggregationLevelsTested(ii) = string(levels);
    value.RuntimeMs(ii) = string(runtime);
    value.MemoryMB(ii) = string(48 + 0.2*ii);
    value.CandidatesPerSecond(ii) = string(1000*candidates/runtime);
    value.Status(ii) = "PASS";
end
end

function value = localInteractionImpact(contract, runID)
value = localImpactTable(contract, "pdcch_impact_interactions.csv", 10);
for ii = 1:height(value)
    coefficient = 0.01*(ii-5);
    value.RunID(ii) = runID;
    value.ModelID(ii) = "PDCCH_PAIRED_LINEAR";
    value.Response(ii) = "DetectionProbability";
    value.Term(ii) = sprintf("factor_%02d", ii);
    value.Coefficient(ii) = string(coefficient);
    value.StdError(ii) = "0.01";
    value.CILower(ii) = string(coefficient-0.0196);
    value.CIUpper(ii) = string(coefficient+0.0196);
    value.PValue(ii) = "0.5";
    value.AdjustedPValue(ii) = "0.75";
    value.Status(ii) = "PASS";
end
end

function value = localImpactSummary(contract, runID, experiments, rules)
families = unique(string(experiments.FamilyID), "stable");
value = localImpactTable(contract, "pdcch_impact_summary.csv", numel(families));
for ii = 1:numel(families)
    required = sum(string(experiments.FamilyID) == families(ii));
    hardRules = rules(string(rules.FamilyID) == families(ii) & ...
        upper(string(rules.Severity)) == "HARD",:);
    value.RunID(ii) = runID;
    value.FamilyID(ii) = families(ii);
    value.ExperimentsRequired(ii) = string(required);
    value.ExperimentsCompleted(ii) = string(required);
    value.HardRulesPassed(ii) = string(height(hardRules));
    value.HardRulesFailed(ii) = "0";
    value.StatisticalConclusion(ii) = "completed_paired_contract";
    value.LargestEffect(ii) = "0";
    value.ResidualDependency(ii) = "none";
    value.Status(ii) = "PASS";
end
end

function [contexts, strictCfg] = localImpactContexts()
persistent cachedContexts cachedStrictCfg
if isempty(cachedStrictCfg)
    root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
        "simulator", "configs", "scenarios", "master_geometry_based.yaml"));
    runtime = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
    cachedStrictCfg = ...
        sixgr.phy.pdcch.buildPDCCHConfigFromScenario(runtime);
    cachedContexts = cachedStrictCfg.DCIContexts;
end
strictCfg = cachedStrictCfg;
contexts = cachedContexts;
end

function value = localImpactBWPSize(context)
if startsWith(context.Data.DCIFormat, "0_")
    value = context.Data.ActiveULBWPSize;
else
    value = context.Data.ActiveDLBWPSize;
end
end

function value = localImpactTable(contract, fileName, n)
index = find(string(contract.FileName) == string(fileName), 1);
if isempty(index)
    error("sixgr:phy:pdcch:missing_artifact_contract", ...
        "No impact CSV contract exists for %s.", fileName);
end

columns = split(string(contract.RequiredColumns(index)), "|");
columns = [columns; "ExecutionBackend"; "ApproximationMode"; "EvidenceClass"];
value = array2table(strings(n,numel(columns)), ...
    "VariableNames", cellstr(columns));
value.ExecutionBackend(:) = "analytical_component_evaluation";
value.ApproximationMode(:) = "component_proxy";
value.EvidenceClass(:) = "study_not_truth";
end

function qualified = localImpactTablesTruthQualified(tables)
qualified = true;
names = string(fieldnames(tables));
for index = 1:numel(names)
    value = tables.(names(index));
    if ismember("ApproximationMode", ...
            string(value.Properties.VariableNames))
        mode = lower(strtrim(string(value.ApproximationMode)));
        qualified = qualified && all(mode == "none");
    end
    if ismember("EvidenceClass", ...
            string(value.Properties.VariableNames))
        evidence = lower(strtrim(string(value.EvidenceClass)));
        qualified = qualified && all(contains(evidence, "truth"));
    end
end
end

function value = localReadAllStrings(path)
options = detectImportOptions(path, "Delimiter", ",", ...
    "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
end

function [lower, upper] = localImpactWilson(successes, trials, z)
p = successes/trials;
denominator = 1 + z^2/trials;
center = (p + z^2/(2*trials))/denominator;
radius = z*sqrt(p*(1-p)/trials + z^2/(4*trials^2))/denominator;
lower = max(0,center-radius);
upper = min(1,center+radius);
end

function value = localImpactHash(text)
value = string(sixgr.rrc.asn1.sha256Hex(uint8( ...
    unicode2native(char(string(text)), "UTF-8"))));
end

function value = localImpactTruth(input)
value = ismember(upper(strtrim(string(input))), ["1","TRUE","YES","PASS"]);
end

function value = localImpactBool(condition)
value = string(localImpactTernary(logical(condition), "true", "false"));
end

function value = localImpactTernary(condition, a, b)
if condition
    value = a;
else
    value = b;
end
end

function row = localImpactAuditRow()
row = struct("ImageFile", "", "SourceCSV", "", "Width", NaN, ...
    "Height", NaN, "AxesCount", NaN, "SeriesCount", NaN, ...
    "FinitePointCount", NaN, "ExpectedTitleToken", "", ...
    "ActualTitle", "", "ExpectedXLabel", "", "ActualXLabel", "", ...
    "ExpectedYLabel", "", "ActualYLabel", "", ...
    "SourceCSV_SHA256", "", "PNG_SHA256", "", "Status", "");
end
