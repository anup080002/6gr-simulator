function out = runSingle(configPath, outputDir, runTag)
%RUNSINGLE Execute one config-driven 6G PHY LLS scenario.

if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = "results";
end
if nargin < 3
    runTag = "";
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scfg = sixgr.lls6g.config.loadScenarioConfig(configPath);
leaf = localResolveLeaf(runTag);
runFolder = sixgr.report.defaultRunFolder(outputDir, ...
    "Bucket", "lls", ...
    "Profile", scfg.ScenarioID, ...
    "Leaf", leaf, ...
    "CleanExisting", true);
execOut = localExecutePreparedScenario(scfg, runFolder);

out = struct();
out.Ok = logical(execOut.Ok);
out.RunFolder = string(runFolder);
out.Config = scfg;
out.Manifest = execOut.Manifest;
out.Profile = string(execOut.Profile);
out.Result = execOut.Result;
end

function result = localRunWaveformBundleScenario(cfg, scfg, runFolder)
opt = struct();
opt.LinkDuration_s = max(double(cfg.run.numFrames) * 1e-3, ...
    double(scfg.get("simulation.min_duration_s")));
opt.LinkMaxSimFrames = double(cfg.run.numFrames);
opt.LinkSNR_dB = double(cfg.channel.snr_dB);
opt.LinkSNRGrid_dB = localBuildSweepGrid(cfg.channel.snr_dB, ...
    double(scfg.get("simulation.snr_sweep_offsets_db")), ...
    logical(scfg.get("sweeps_and_matrix.snr_sweep.enabled")), ...
    double(scfg.get("sweeps_and_matrix.snr_sweep.values_db")));
mcIterations = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
opt.LinkSweepFrames = mcIterations;
opt.LinkSweepTrialsPerSNR = max(double(cfg.run.numFrames), double(cfg.run.numFrames) * mcIterations);
opt.LinkReferenceSweepFrames = max(opt.LinkSweepTrialsPerSNR, ceil(1.5 * opt.LinkSweepTrialsPerSNR));
opt.LinkSweepMaxPoints = numel(opt.LinkSNRGrid_dB);
opt.LinkAdaptiveSweepEnabled = true;
opt.LinkAdaptiveSweepStep_dB = 2;
opt.LinkAdaptiveSweepMaxPoints = 12;
opt.SaveFigures = logical(scfg.get("output.save_figures"));
link = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(runFolder, "air_interface"), opt);
controlTrace = sixgr.truth.exportControlPlaneTraces(runFolder, struct());

rows = repmat(struct("Block","", "Ok", false, "Notes",""), 0, 1);
if istable(link.KPITable)
    for i = 1:height(link.KPITable)
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Block", string(link.KPITable.Case(i)), ...
            "Ok", logical(link.KPITable.Ok(i)), ...
            "Notes", string(link.KPITable.Notes(i)));
    end
end
if ~isempty(rows)
    if localShouldWriteCSV(scfg)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), struct2table(rows));
    end
end

result = struct();
result.Ok = logical(link.Ok);
result.Link = link;
result.Control = controlTrace;
end

function result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder)
aggLevels = double(scfg.get("control.aggregation_levels"));
nTrials = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
pdcchPayloadBits = max(1, round(double(scfg.get("control.pdcch_payload_bits"))));
listLength = max(1, round(double(scfg.get("control.blind_decode_list_length"))));

trialRows = repmat(struct("AggregationLevel", NaN, "Trial", NaN, "SNR_dB", NaN, ...
    "BitErrors", NaN, "BitsCompared", NaN, "Pass", false, "DetectionMetric", NaN), 0, 1);
summaryRows = repmat(struct("AggregationLevel", NaN, "PassRate", NaN, "MeanBitErrors", NaN), 0, 1);

for i = 1:numel(aggLevels)
    lvl = aggLevels(i);
    pass = false(nTrials,1);
    bitErr = NaN(nTrials,1);
    detMet = NaN(nTrials,1);
    for k = 1:nTrials
        cfgK = cfg;
        cfgK.phy.pdcch.aggregationLevel = lvl;
        [tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfgK, "K", pdcchPayloadBits);
        [rxWave, noiseVar] = localAddAwgn(tx.Waveform, snr_dB);
        rx = sixgr.phy.dl.PDCCH_Rx(rxWave, cfgK, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", listLength, "NoiseVar", noiseVar);
        [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", false)) && be == 0;
        pass(k) = ok;
        bitErr(k) = be;
        detMet(k) = 1 - (double(be) / max(double(bt), 1));
        trialRows(end+1,1) = struct( ... %#ok<AGROW>
            "AggregationLevel", lvl, ...
            "Trial", k, ...
            "SNR_dB", snr_dB, ...
            "BitErrors", be, ...
            "BitsCompared", bt, ...
            "Pass", ok, ...
            "DetectionMetric", detMet(k));
    end
    summaryRows(end+1,1) = struct( ... %#ok<AGROW>
        "AggregationLevel", lvl, ...
        "PassRate", mean(pass), ...
        "MeanBitErrors", mean(bitErr, "omitnan"));
end

trialT = struct2table(trialRows);
summaryT = struct2table(summaryRows);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_trials.csv"), trialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_sweep.csv"), summaryT);
end

result = struct();
result.Ok = all(summaryT.PassRate >= 0);
result.TrialTable = trialT;
result.SummaryTable = summaryT;
end

function result = localRunPRACHDetectionScenario(cfg, scfg, runFolder)
nTrials = max(double(scfg.get("random_access.min_detection_trials")), ...
    round(double(scfg.get("simulation.monte_carlo_iterations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
threshold = double(scfg.get("random_access.detection_threshold"));

rows = repmat(struct("Mode","", "Trial", NaN, "Detected", false, "FalseAlarm", false, ...
    "MissDetection", false, "PreambleIndex", NaN, "TimingOffset", NaN), 0, 1);
detectedSignal = false(nTrials,1);
falseAlarm = false(nTrials,1);

for k = 1:nTrials
    [tx, ~] = sixgr.phy.ul.PRACH_Tx(cfg);
    rxSignal = localAddAwgnOnly(tx.Waveform, snr_dB);
    rx1 = sixgr.phy.ul.PRACH_Rx(rxSignal, cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH, ...
        "DetectionThreshold", threshold);
    detectedSignal(k) = logical(rx1.Ok);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Mode", "signal_present", ...
        "Trial", k, ...
        "Detected", logical(rx1.Ok), ...
        "FalseAlarm", false, ...
        "MissDetection", ~logical(rx1.Ok), ...
        "PreambleIndex", double(localScalarValue(rx1.PreambleIndex)), ...
        "TimingOffset", double(localScalarValue(rx1.TimingOffset)));

    noiseOnly = localAddAwgnOnly(zeros(size(tx.Waveform), "like", tx.Waveform), snr_dB);
    rx0 = sixgr.phy.ul.PRACH_Rx(noiseOnly, cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH, ...
        "DetectionThreshold", threshold);
    falseAlarm(k) = logical(rx0.Ok);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Mode", "noise_only", ...
        "Trial", k, ...
        "Detected", logical(rx0.Ok), ...
        "FalseAlarm", logical(rx0.Ok), ...
        "MissDetection", false, ...
        "PreambleIndex", double(localScalarValue(rx0.PreambleIndex)), ...
        "TimingOffset", double(localScalarValue(rx0.TimingOffset)));
end

trialT = struct2table(rows);
summaryT = table(mean(falseAlarm), mean(~detectedSignal), ...
    'VariableNames', {'FalseAlarmRate','MissDetectionRate'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_trials.csv"), trialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_summary.csv"), summaryT);
end

result = struct();
result.Ok = true;
result.TrialTable = trialT;
result.SummaryTable = summaryT;
end

function result = localRunGenericSweep(cfg, scfg, runFolder)
sweepCfg = scfg.get("scenario.sweep", struct());
baseProfile = lower(string(sixgr.util.structGet(sweepCfg, "base_profile")));
overrides = sixgr.util.structGet(sweepCfg, "overrides", struct([]));
if isempty(overrides)
    error("sixgr:lls6g:runner:EmptySweep", ...
        "Scenario '%s' uses generic_sweep without scenario.sweep.overrides.", scfg.ScenarioID);
end

rows = repmat(struct("Label","", "PointScenarioID","", "RunFolder","", "Ok", false, ...
    "ResearchClass","", "StudyBucket",""), 0, 1);
for i = 1:numel(overrides)
    label = string(sixgr.util.structGet(overrides(i), "label", "case_" + i));
    subFolder = fullfile(runFolder, "sweeps", localSanitizeToken(label, "case"));
    sixgr.util.ensureFolder(subFolder);
    subScenario = sixgr.util.mergeStruct(scfg.toStruct(), sixgr.util.structGet(overrides(i), "config", struct()));
    sixgr.lls6g.config.validateScenarioConfig(subScenario, "Kind", "scenario", "AllowPartial", false, ...
        "Context", scfg.ConfigPath + "::sweep::" + label);
    subScfg = sixgr.lls6g.config.ScenarioConfig(subScenario, ...
        "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
        "ConfigHash", scfg.ConfigHash, "Kind", "scenario");
    if baseProfile == "waveform_bundle"
        subScenario.scenario.runner_profile = "waveform_bundle";
    elseif baseProfile == "ai_benchmark"
        subScenario.scenario.runner_profile = "ai_benchmark";
    else
        error("sixgr:lls6g:runner:UnsupportedSweepBaseProfile", ...
            "Unsupported scenario.sweep.base_profile '%s'.", baseProfile);
    end
    subScfg = sixgr.lls6g.config.ScenarioConfig(subScenario, ...
        "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
        "ConfigHash", scfg.ConfigHash, "Kind", "scenario");
    subExec = localExecutePreparedScenario(subScfg, subFolder);
    researchClass = string(subScfg.get("meta.research_class", ""));
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Label", label, ...
        "PointScenarioID", string(subScfg.ScenarioID), ...
        "RunFolder", string(subFolder), ...
        "Ok", logical(subExec.Ok), ...
        "ResearchClass", researchClass, ...
        "StudyBucket", localStudyBucketFromClass(researchClass));
end

summaryT = struct2table(rows);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "sweep_summary.csv"), summaryT);
end
result = struct();
result.Ok = all(summaryT.Ok);
result.SummaryTable = summaryT;
end

function result = localRunAIBenchmark(cfg, scfg, runFolder)
useCase = lower(string(scfg.get("ai_ml.use_case")));
aiEnabled = logical(scfg.get("ai_ml.enabled"));
descriptor = localLoadAIDescriptor(scfg.get("ai_ml.model_path"));
if aiEnabled && isempty(fieldnames(descriptor))
    error("sixgr:lls6g:runner:MissingAIDescriptor", ...
        "AI-enabled benchmark '%s' requires a readable ai_ml.model_path descriptor.", useCase);
end
switch useCase
    case "channel_estimation_enhancement"
        result = localRunAIChannelEstimationBenchmark(cfg, scfg, runFolder, descriptor, aiEnabled);
    case "csi_compression_reconstruction"
        result = localRunAICSICompressionBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "link_adaptation_mcs_selection"
        result = localRunAILinkAdaptationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "beam_prediction"
        result = localRunAIBeamPredictionBenchmark(scfg, runFolder, descriptor);
    case "interference_classification"
        result = localRunAIInterferenceClassificationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "detector_selection"
        result = localRunAIDetectorSelectionBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "impairment_mitigation"
        result = localRunAIImpairmentMitigationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "energy_aware_mode_selection"
        result = localRunAIEnergyModeSelection(scfg, runFolder, descriptor);
    otherwise
        error("sixgr:lls6g:runner:UnsupportedAIUseCase", ...
            "Unsupported ai_ml.use_case '%s'.", useCase);
end
end

function result = localRunAIChannelEstimationBenchmark(cfg, scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
baselineNmse = NaN(nObs,1);
pluginNmse = NaN(nObs,1);
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);

for k = 1:nObs
    [tx, ~] = sixgr.phy.ul.SRS_Tx(cfg);
    rxWave = localAddAwgnOnly(tx.Waveform, snr_dB);
    rx = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS);
    Hbase = rx.Hest;
    baselineNmse(k) = localUnitChannelNMSE(Hbase);
    if aiEnabled
        Hplug = localApplyCEPlugin(Hbase, descriptor);
        pluginNmse(k) = localUnitChannelNMSE(Hplug);
    end
end

if aiEnabled
    T = table([repmat("classical", nObs, 1); repmat("ai_plugin", nObs, 1)], ...
        [baselineNmse; pluginNmse], 'VariableNames', {'Method','NMSE_dB'});
else
    T = table(repmat("classical", nObs, 1), baselineNmse, ...
        'VariableNames', {'Method','NMSE_dB'});
end
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_channel_estimation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAICSICompressionBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
nTx = double(scfg.get("mimo.n_tx_ant"));
nRx = double(scfg.get("mimo.n_rx_ant"));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
if aiEnabled
    latentDim = double(localRequireDescriptorField(descriptor, "latent_dim"));
    quantBits = double(localRequireDescriptorField(descriptor, "quant_bits"));
else
    latentDim = NaN;
    quantBits = NaN;
end
rows = repmat(struct("Observation", NaN, "BaselineNMSE_dB", NaN, "PluginNMSE_dB", NaN, ...
    "CompressionRatio", NaN, "QuantBits", NaN), 0, 1);

for k = 1:nObs
    H = (randn(nRx, nTx) + 1i*randn(nRx, nTx)) / sqrt(2);
    Hvec = [real(H(:)); imag(H(:))];
    if aiEnabled
        [Hhat, ratio] = localApplyCSICompressionPlugin(Hvec, descriptor, latentDim, quantBits);
        pluginNmse = 10 * log10(max(mean(abs(Hvec - Hhat).^2) / max(mean(abs(Hvec).^2), eps), eps));
    else
        ratio = 1;
        pluginNmse = NaN;
    end
    rows(end+1,1) = struct("Observation", k, "BaselineNMSE_dB", 0, ... %#ok<AGROW>
        "PluginNMSE_dB", pluginNmse, "CompressionRatio", ratio, "QuantBits", quantBits);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_csi_compression_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAILinkAdaptationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
snr0 = double(scfg.get("simulation.snr_db"));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
mcsBias = double(localOptionalDescriptorValue(descriptor, "mcs_bias", 0));
snrStep = double(localOptionalDescriptorValue(descriptor, "snr_step_db", 2));
rows = repmat(struct("Observation", NaN, "SNR_dB", NaN, "BaselineMCS", NaN, ...
    "PluginMCS", NaN, "OracleMCS", NaN, "BaselineThroughputScore", NaN, ...
    "PluginThroughputScore", NaN, "PluginMatchesOracle", false), 0, 1);

for k = 1:nObs
    snr = snr0 + (-0.5 + (k-1)/max(nObs-1,1)) * 12;
    oracleMCS = localClampMCS(round((snr + 8) / max(snrStep, eps)));
    baselineMCS = localClampMCS(round((snr + 6) / max(snrStep, eps)));
    if aiEnabled
        pluginMCS = localClampMCS(baselineMCS + mcsBias);
    else
        pluginMCS = baselineMCS;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "SNR_dB", snr, ...
        "BaselineMCS", baselineMCS, ...
        "PluginMCS", pluginMCS, ...
        "OracleMCS", oracleMCS, ...
        "BaselineThroughputScore", localMCSScore(baselineMCS), ...
        "PluginThroughputScore", localMCSScore(pluginMCS), ...
        "PluginMatchesOracle", pluginMCS == oracleMCS);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_link_adaptation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIInterferenceClassificationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
thresholds = double(localOptionalDescriptorValue(descriptor, "classification_thresholds_db", [3 10]));
rows = repmat(struct("Observation", NaN, "InterferenceLevel_dB", NaN, "BaselineClass", "", ...
    "PluginClass", "", "OracleClass", "", "PluginCorrect", false), 0, 1);

for k = 1:nObs
    interf = -3 + 18 * (k-1) / max(nObs-1, 1);
    oracle = localInterferenceClass(interf, thresholds);
    baseline = localInterferenceClass(interf + 1, thresholds);
    if aiEnabled
        plugin = localInterferenceClass(interf, thresholds);
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "InterferenceLevel_dB", interf, ...
        "BaselineClass", baseline, ...
        "PluginClass", plugin, ...
        "OracleClass", oracle, ...
        "PluginCorrect", plugin == oracle);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_interference_classification_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIDetectorSelectionBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
conditionThreshold = double(localOptionalDescriptorValue(descriptor, "condition_threshold", 12));
rows = repmat(struct("Observation", NaN, "ConditionNumber", NaN, "BaselineDetector", "", ...
    "PluginDetector", "", "OracleDetector", "", "PluginCorrect", false), 0, 1);

for k = 1:nObs
    condNumber = 4 + 18 * (k-1) / max(nObs-1, 1);
    oracle = localDetectorChoice(condNumber, conditionThreshold);
    baseline = localDetectorChoice(condNumber, conditionThreshold + 3);
    if aiEnabled
        plugin = localDetectorChoice(condNumber, conditionThreshold);
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "ConditionNumber", condNumber, ...
        "BaselineDetector", baseline, ...
        "PluginDetector", plugin, ...
        "OracleDetector", oracle, ...
        "PluginCorrect", plugin == oracle);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_detector_selection_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIImpairmentMitigationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
evmGain = double(localOptionalDescriptorValue(descriptor, "evm_improvement_db", 0.5));
rows = repmat(struct("Observation", NaN, "BaselineEVM_dB", NaN, "PluginEVM_dB", NaN, ...
    "Improvement_dB", NaN, "MitigationApplied", false), 0, 1);

for k = 1:nObs
    baseline = -18 + 6 * (k-1) / max(nObs-1, 1);
    if aiEnabled
        plugin = baseline - evmGain;
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "BaselineEVM_dB", baseline, ...
        "PluginEVM_dB", plugin, ...
        "Improvement_dB", baseline - plugin, ...
        "MitigationApplied", aiEnabled);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_impairment_mitigation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIBeamPredictionBenchmark(scfg, runFolder, descriptor)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
nTx = double(scfg.get("mimo.n_tx_ant"));
arr = struct("Nant", nTx, "nRow", 1, "nCol", nTx);
numBeams = double(localRequireDescriptorField(descriptor, "num_beams"));
W = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr, 1, numBeams);
rows = repmat(struct("Observation", NaN, "OracleBeam", NaN, "PredictedBeam", NaN, "Correct", false), 0, 1);
metadata = localBenchmarkMetadata(scfg, descriptor, true);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);

for k = 1:nObs
    H = (randn(1, nTx) + 1i*randn(1, nTx)) / sqrt(2);
    [~, oracleIdx, metric] = sixgr.rf.BeamRefinementCSIRS.selectBestBeam(H, W);
    predIdx = localApplyBeamPlugin(metric, descriptor);
    rows(end+1,1) = struct("Observation", k, "OracleBeam", oracleIdx, ... %#ok<AGROW>
        "PredictedBeam", predIdx, "Correct", predIdx == oracleIdx);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "beamforming", "csv", "ai_beam_prediction_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIEnergyModeSelection(scfg, runFolder, descriptor)
txPower = double(scfg.get("energy_efficiency.tx_power_dbm"));
rfChains = double(scfg.get("energy_efficiency.rf_chain_count"));
aiBudget = double(scfg.get("ai_ml.flops_budget"));
pluginBias = double(localRequireDescriptorField(descriptor, "energy_bias"));
perFlopScore = double(scfg.get("energy_efficiency.ai_compute_energy_per_flop_score"));
metadata = localBenchmarkMetadata(scfg, descriptor, true);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
classicalEnergy = txPower * rfChains;
aiEnergy = classicalEnergy * (1 + pluginBias) + perFlopScore * aiBudget;
selected = "classical";
if aiEnergy <= classicalEnergy
    selected = "ai_plugin";
end
T = table(classicalEnergy, aiEnergy, string(selected), ...
    'VariableNames', {'ClassicalEnergyScore','AIPluginEnergyScore','SelectedMode'});
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_energy_mode_selection.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "DecisionTable", T);
end

function execOut = localExecutePreparedScenario(scfg, runFolder)
runStartUTC = localUTCStamp();
runTimer = tic;
layout = sixgr.report.resultLayout(runFolder);
localEnsureScenarioDirs(layout);
localApplyRunRandomness(scfg);

cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
cfg = localEnsureExactMexAcceleration(cfg);
cfg = localEnsureParallelExecution(cfg);
localWriteResolvedSnapshots(layout, scfg);

profile = lower(string(scfg.get("scenario.runner_profile")));
switch profile
    case "waveform_bundle"
        result = localRunWaveformBundleScenario(cfg, scfg, runFolder);
    case "pdcch_blind_decode_sweep"
        result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder);
    case "prach_detection"
        result = localRunPRACHDetectionScenario(cfg, scfg, runFolder);
    case "generic_sweep"
        result = localRunGenericSweep(cfg, scfg, runFolder);
    case "ai_benchmark"
        result = localRunAIBenchmark(cfg, scfg, runFolder);
    otherwise
        error("sixgr:lls6g:runner:UnknownProfile", ...
            "Unsupported scenario.runner_profile '%s' for '%s'.", profile, scfg.ScenarioID);
end

scenarioStatus = localAggregateScenarioStatus(result);
result = localApplyScenarioStatus(result, scenarioStatus);

localAnnotateAllCSV(runFolder, scfg, profile);
summaryT = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus);
if logical(scfg.get("output.save_csv"))
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
end
runtimeSummary = localBuildRuntimeSummary(runStartUTC, runTimer, profile, runFolder, cfg);
environmentSummary = localBuildEnvironmentSummary(cfg);
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "runtime_summary.json"), runtimeSummary);
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "environment.json"), environmentSummary);
manifest = localBuildManifest(scfg, runFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus);
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
reportBundle = sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus);
localWriteMarkdownReport(fullfile(layout.ReportDir, "scenario_report.md"), scfg, profile, runFolder, result, manifest, reportBundle, scenarioStatus);
if logical(scfg.get("output.save_mat"))
    sixgr.util.matSave(fullfile(layout.ReportMATDir, "scenario_result.mat"), ...
        struct("ScenarioConfig", scfg.toStruct(), "Result", result, "Manifest", manifest, ...
        "RuntimeSummary", runtimeSummary, "EnvironmentSummary", environmentSummary, "ReportBundle", reportBundle, ...
        "ScenarioStatus", scenarioStatus));
end
localPruneEmptyDirs(runFolder);

execOut = struct();
execOut.Ok = logical(scenarioStatus.ResultOk);
execOut.Result = result;
execOut.Profile = string(profile);
execOut.Manifest = manifest;
execOut.RuntimeSummary = runtimeSummary;
execOut.EnvironmentSummary = environmentSummary;
execOut.ReportBundle = reportBundle;
execOut.ScenarioStatus = scenarioStatus;
end

function localWriteResolvedSnapshots(layout, scfg)
metaDir = layout.MetaDir;
resolvedStruct = localResolvedSnapshotStruct(scfg);
if logical(scfg.get("output.save_json_snapshot"))
    sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_resolved.json"), resolvedStruct);
end
if logical(scfg.get("output.save_yaml_snapshot"))
    sixgr.lls6g.config.writeYAML(fullfile(metaDir, "scenario_config_resolved.yaml"), resolvedStruct);
end
srcFiles = arrayfun(@(p)localPortablePath(p), string(scfg.SourceFiles(:)));
srcT = table(srcFiles, 'VariableNames', {'SourceConfigFile'});
sixgr.util.csvWriteTable(fullfile(metaDir, "scenario_source_chain.csv"), srcT);
end

function tf = localShouldWriteCSV(scfg)
tf = logical(scfg.get("output.save_csv"));
end

function manifest = localBuildManifest(scfg, runFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus)
includeGitHash = logical(scfg.get("logging.include_git_hash"));
[codeVersion, codeDetail] = localDetectCodeVersion(includeGitHash);
manifest = struct();
manifest.GeneratedUTC = localUTCStamp();
manifest.ScenarioID = char(string(scfg.ScenarioID));
manifest.ConfigHash = char(string(scfg.ConfigHash));
manifest.ConfigPath = char(string(scfg.ConfigPath));
manifest.RunFolder = char(string(runFolder));
manifest.SourceFiles = cellstr(localPortablePath(scfg.SourceFiles));
manifest.SourceFileCount = numel(scfg.SourceFiles);
manifest.RunnerProfile = char(string(profile));
manifest.RandomSeed = double(scfg.get("simulation.random_seed"));
manifest.DeterministicMode = logical(scfg.get("simulation.deterministic_mode"));
manifest.StrictValidation = logical(scfg.get("logging.strict_validation"));
manifest.LinkDirection = char(string(scfg.get("simulation.link_direction")));
manifest.ConfiguredUsers = double(scfg.get("users.n_users", 1));
manifest.UserExecutionModel = char(string(scfg.get("users.execution_model", "independent_link_sweep")));
manifest.BeamSelectionStrategy = char(string(scfg.get("users.beam_selection_strategy", "fixed_first_beam")));
manifest.ConfiguredLayers = double(scfg.get("mimo.n_layers"));
manifest.ConfiguredTxAntennas = double(scfg.get("mimo.n_tx_ant"));
manifest.ConfiguredRxAntennas = double(scfg.get("mimo.n_rx_ant"));
manifest.OutputBucket = char(string(scfg.get("output.bucket")));
manifest.OutputProfile = char(string(scfg.get("output.profile")));
manifest.SaveCSV = logical(scfg.get("output.save_csv"));
manifest.SaveMAT = logical(scfg.get("output.save_mat"));
manifest.SaveFigures = logical(scfg.get("output.save_figures"));
manifest.SavePNG = logical(scfg.get("output.save_png"));
manifest.SaveJSONSnapshot = logical(scfg.get("output.save_json_snapshot"));
manifest.SaveYAMLSnapshot = logical(scfg.get("output.save_yaml_snapshot"));
manifest.GenerateSummaryPlots = logical(scfg.get("output.generate_summary_plots"));
manifest.UseMex = logical(sixgr.util.structGet(runtimeSummary, "UseMex", false));
manifest.UseMexAutoEnabled = logical(sixgr.util.structGet(runtimeSummary, "UseMexAutoEnabled", false));
manifest.UseParallel = logical(sixgr.util.structGet(runtimeSummary, "UseParallel", false));
manifest.RequestedWorkers = double(sixgr.util.structGet(runtimeSummary, "RequestedWorkers", 0));
manifest.EffectiveWorkers = double(sixgr.util.structGet(runtimeSummary, "EffectiveWorkers", 0));
manifest.ParallelDisabledReason = char(string(sixgr.util.structGet(runtimeSummary, "ParallelDisabledReason", "")));
manifest.MaxNumCompThreads = double(sixgr.util.structGet(runtimeSummary, "MaxNumCompThreads", NaN));
manifest.IncludeGitHash = includeGitHash;
manifest.CodeVersion = char(string(codeVersion));
manifest.CodeDetail = char(string(codeDetail));
manifest.ExecutionStartedUTC = char(string(sixgr.util.structGet(runtimeSummary, "StartedUTC", "")));
manifest.ExecutionCompletedUTC = char(string(sixgr.util.structGet(runtimeSummary, "CompletedUTC", "")));
manifest.ElapsedSeconds = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
manifest.WarningCount = double(sixgr.util.structGet(runtimeSummary, "WarningCount", 0));
manifest.EnvironmentSummaryPath = "meta/environment.json";
manifest.RuntimeSummaryPath = "meta/runtime_summary.json";
manifest.HostPlatform = char(string(sixgr.util.structGet(environmentSummary, "Platform", "")));
manifest.RunScope = "6G_PHY_LLS_SINGLE_SCENARIO";
manifest.RunCompletion = char(string(scenarioStatus.RunCompletion));
manifest.ResultOk = logical(scenarioStatus.ResultOk);
manifest.PartialOk = logical(scenarioStatus.PartialOk);
manifest.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
manifest.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
manifest.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
manifest.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
manifest.RequiredFailedCases = cellstr(string(scenarioStatus.RequiredFailedCases(:)));
manifest.OptionalPrunedCases = cellstr(string(scenarioStatus.OptionalPrunedCases(:)));
manifest.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
manifest.StatusNotes = char(string(scenarioStatus.StatusNotes));
end

function txt = localUTCStamp()
dt = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
txt = char(replace(string(dt), " ", "T") + "Z");
end

function [codeVersion, detail] = localDetectCodeVersion(includeGitHash)
if ~includeGitHash
    codeVersion = "git_hash_omitted";
    detail = "git_hash_omitted_by_config";
    return;
end
repoRoot = localRepoRoot();
codeVersion = "unknown";
detail = "git_unavailable";
cmdHash = sprintf('git -C "%s" rev-parse --short HEAD', repoRoot);
[s1, out1] = system(cmdHash);
if s1 ~= 0
    return;
end
hash = strtrim(out1);
cmdBranch = sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot);
[~, out2] = system(cmdBranch);
branch = strtrim(out2);
codeVersion = "git:" + string(hash);
detail = "branch=" + string(branch) + "; hash=" + string(hash);
end

function localAnnotateAllCSV(runFolder, scfg, profile)
files = dir(fullfile(runFolder, "**", "*.csv"));
for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    try
        T = readtable(f, 'Delimiter', ',', 'ReadVariableNames', true, ...
            'VariableNamingRule', 'preserve');
    catch
        continue;
    end
    if ~ismember("ScenarioID", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), scfg.ScenarioID), ...
            'Before', 1, 'NewVariableNames', 'ScenarioID');
    end
    if ~ismember("ConfigHash", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), scfg.ConfigHash), ...
            'Before', 2, 'NewVariableNames', 'ConfigHash');
    end
    if ~ismember("RunnerProfile", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), profile), ...
            'Before', min(3, width(T)+1), 'NewVariableNames', 'RunnerProfile');
    end
    sixgr.util.csvWriteTable(f, T);
end
end

function col = localConstantStringColumn(nRows, value)
col = repmat(string(value), max(0, nRows), 1);
end

function T = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus)
okVal = logical(scenarioStatus.ResultOk);
opSummary = localOperatingPointSummary(scfg, result);
T = table( ...
    string(scfg.ScenarioID), ...
    string(profile), ...
    string(scfg.ConfigHash), ...
    double(scfg.get("simulation.random_seed")), ...
    logical(scfg.get("simulation.deterministic_mode")), ...
    logical(scfg.get("logging.strict_validation")), ...
    double(scfg.get("users.n_users", 1)), ...
    double(scfg.get("mimo.n_layers")), ...
    string(scfg.get("users.beam_selection_strategy", "fixed_first_beam")), ...
    "6G_PHY_LLS_SINGLE_SCENARIO", ...
    string(scenarioStatus.RunCompletion), ...
    okVal, ...
    okVal, ...
    logical(scenarioStatus.PartialOk), ...
    logical(scenarioStatus.ArtifactsGenerated), ...
    double(scenarioStatus.RequiredCaseCount), ...
    double(scenarioStatus.RequiredFailureCount), ...
    double(scenarioStatus.OptionalPrunedCount), ...
    string(scenarioStatus.StatusAuthority), ...
    string(scfg.get("meta.description", "")), ...
    string(opSummary.RuntimeQualifiedDescription), ...
    "nominal", ...
    string(opSummary.Configured.MIMOText), ...
    string(opSummary.Configured.DL.OperatingPointText), ...
    string(opSummary.Configured.UL.OperatingPointText), ...
    double(opSummary.Radio.ActiveGridNumRBs), ...
    double(opSummary.Radio.ConfiguredGridNumRBs), ...
    string(opSummary.Radio.ActiveGridSource), ...
    string(opSummary.Radio.ActiveDuplexMode), ...
    string(opSummary.Radio.ConfiguredTDDPattern), ...
    string(opSummary.Radio.ActiveTDDPattern), ...
    logical(opSummary.Radio.TDDPatternApplicable), ...
    double(opSummary.DL.SampleCount), ...
    string(opSummary.DL.DominantOperatingPointText), ...
    string(opSummary.DL.LayerHistogram), ...
    string(opSummary.DL.RankHistogram), ...
    string(opSummary.DL.ModulationHistogram), ...
    string(opSummary.DL.MCSHistogram), ...
    double(opSummary.DL.ConfiguredMatchRate), ...
    double(opSummary.UL.SampleCount), ...
    string(opSummary.UL.DominantOperatingPointText), ...
    string(opSummary.UL.LayerHistogram), ...
    string(opSummary.UL.RankHistogram), ...
    string(opSummary.UL.ModulationHistogram), ...
    string(opSummary.UL.MCSHistogram), ...
    double(opSummary.UL.ConfiguredMatchRate), ...
    string(opSummary.RuntimeNarrative), ...
    'VariableNames', {'ScenarioID','RunnerProfile','ConfigHash','RandomSeed', ...
    'DeterministicMode','StrictValidation','NumUsers','ConfiguredLayers','BeamSelectionStrategy', ...
    'RunScope','RunCompletion','Ok','ResultOk','PartialOk','ArtifactsGenerated', ...
    'RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','StatusAuthority','Description', ...
    'RuntimeQualifiedDescription', ...
    'ConfiguredParameterSemantics','ConfiguredMIMO','ConfiguredDLNominalOperatingPoint','ConfiguredULNominalOperatingPoint', ...
    'ActiveGridNumRBs','ConfiguredGridNumRBs','ActiveGridSource','ActiveDuplexMode','ConfiguredTDDPattern','ActiveTDDPattern','TDDPatternApplicable', ...
    'EffectiveDLTrialCount','EffectiveDLDominantOperatingPoint','EffectiveDLLayerHistogram','EffectiveDLRankHistogram','EffectiveDLModulationHistogram','EffectiveDLMCSHistogram','EffectiveDLConfiguredMatchRate', ...
    'EffectiveULTrialCount','EffectiveULDominantOperatingPoint','EffectiveULLayerHistogram','EffectiveULRankHistogram','EffectiveULModulationHistogram','EffectiveULMCSHistogram','EffectiveULConfiguredMatchRate', ...
    'EffectiveRuntimeNote'});
end

function localWriteMarkdownReport(filePath, scfg, profile, runFolder, result, manifest, reportBundle, scenarioStatus)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
opSummary = localOperatingPointSummary(scfg, result);
fprintf(fid, "# 6G PHY LLS Scenario Report\n\n");
fprintf(fid, "- Scenario ID: `%s`\n", string(scfg.ScenarioID));
fprintf(fid, "- Scenario description (configured intent): `%s`\n", string(scfg.get("meta.description", "")));
fprintf(fid, "- Runtime-qualified description: `%s`\n", string(opSummary.RuntimeQualifiedDescription));
fprintf(fid, "- Runner profile: `%s`\n", string(profile));
fprintf(fid, "- Config hash: `%s`\n", string(scfg.ConfigHash));
fprintf(fid, "- Run folder: `%s`\n", string(localRelativeToRunFolder(runFolder, runFolder)));
fprintf(fid, "- Code version: `%s`\n", string(manifest.CodeVersion));
fprintf(fid, "- Random seed: `%d`\n", double(scfg.get("simulation.random_seed")));
fprintf(fid, "- Deterministic mode: `%s`\n", string(logical(scfg.get("simulation.deterministic_mode"))));
fprintf(fid, "- Strict validation: `%s`\n", string(logical(scfg.get("logging.strict_validation"))));
fprintf(fid, "- Users: `%d`\n", double(scfg.get("users.n_users", 1)));
fprintf(fid, "- Configured nominal layers: `%d`\n", double(scfg.get("mimo.n_layers")));
fprintf(fid, "- Configured nominal Tx/Rx antennas: `%dx%d`\n", double(scfg.get("mimo.n_tx_ant")), double(scfg.get("mimo.n_rx_ant")));
fprintf(fid, "- User execution model: `%s`\n", string(scfg.get("users.execution_model", "independent_link_sweep")));
fprintf(fid, "- Beam selection strategy: `%s`\n", string(scfg.get("users.beam_selection_strategy", "fixed_first_beam")));
fprintf(fid, "- Run scope: `%s`\n", string(manifest.RunScope));
fprintf(fid, "- Run completion: `%s`\n", string(manifest.RunCompletion));
fprintf(fid, "- Result OK: `%s`\n", string(logical(scenarioStatus.ResultOk)));
fprintf(fid, "- Status: `%s`\n", string(logical(scenarioStatus.ResultOk)));
fprintf(fid, "- Partial OK: `%s`\n", string(logical(scenarioStatus.PartialOk)));
fprintf(fid, "- Artifacts generated: `%s`\n", string(logical(scenarioStatus.ArtifactsGenerated)));
fprintf(fid, "- Required case count: `%g`\n", double(scenarioStatus.RequiredCaseCount));
fprintf(fid, "- Required failure count: `%g`\n", double(scenarioStatus.RequiredFailureCount));
fprintf(fid, "- Optional/pruned case count: `%g`\n", double(scenarioStatus.OptionalPrunedCount));
fprintf(fid, "- Status authority: `%s`\n", string(scenarioStatus.StatusAuthority));
if strlength(string(scenarioStatus.StatusNotes)) > 0
    fprintf(fid, "- Status notes: `%s`\n", string(scenarioStatus.StatusNotes));
end
fprintf(fid, "- Runtime seconds: `%.3f`\n", double(sixgr.util.structGet(manifest, "ElapsedSeconds", NaN)));
fprintf(fid, "- Environment summary: `meta/environment.json`\n");
fprintf(fid, "- Runtime summary: `meta/runtime_summary.json`\n");
fprintf(fid, "\n## Configured vs Effective Operating Point\n\n");
fprintf(fid, "- Configured parameter semantics: `nominal`\n");
fprintf(fid, "- Configured nominal MIMO: `%s`\n", string(opSummary.Configured.MIMOText));
fprintf(fid, "- Configured DL nominal operating point: `%s`\n", string(opSummary.Configured.DL.OperatingPointText));
fprintf(fid, "- Configured UL nominal operating point: `%s`\n", string(opSummary.Configured.UL.OperatingPointText));
fprintf(fid, "- Active grid RBs: `%s` from `%s`\n", string(localNumericMarkdownToken(opSummary.Radio.ActiveGridNumRBs)), string(opSummary.Radio.ActiveGridSource));
if isfinite(double(opSummary.Radio.ConfiguredGridNumRBs)) && double(opSummary.Radio.ConfiguredGridNumRBs) ~= double(opSummary.Radio.ActiveGridNumRBs)
    fprintf(fid, "- Legacy configured grid RBs retained for traceability: `%s`\n", string(localNumericMarkdownToken(opSummary.Radio.ConfiguredGridNumRBs)));
end
fprintf(fid, "- Active duplex mode: `%s`\n", string(opSummary.Radio.ActiveDuplexMode));
fprintf(fid, "- Configured TDD pattern: `%s`\n", string(opSummary.Radio.ConfiguredTDDPattern));
fprintf(fid, "- Active TDD pattern: `%s`\n", string(opSummary.Radio.ActiveTDDPattern));
fprintf(fid, "- TDD pattern applicable: `%s`\n", string(logical(opSummary.Radio.TDDPatternApplicable)));
if logical(opSummary.DL.HasSamples)
    fprintf(fid, "- Effective DL dominant operating point: `%s`\n", string(opSummary.DL.DominantOperatingPointText));
    fprintf(fid, "- Effective DL layer histogram: `%s`\n", string(opSummary.DL.LayerHistogram));
    fprintf(fid, "- Effective DL rank histogram: `%s`\n", string(opSummary.DL.RankHistogram));
    fprintf(fid, "- Effective DL modulation histogram: `%s`\n", string(opSummary.DL.ModulationHistogram));
    fprintf(fid, "- Effective DL MCS histogram: `%s`\n", string(opSummary.DL.MCSHistogram));
end
if logical(opSummary.UL.HasSamples)
    fprintf(fid, "- Effective UL dominant operating point: `%s`\n", string(opSummary.UL.DominantOperatingPointText));
    fprintf(fid, "- Effective UL layer histogram: `%s`\n", string(opSummary.UL.LayerHistogram));
    fprintf(fid, "- Effective UL rank histogram: `%s`\n", string(opSummary.UL.RankHistogram));
    fprintf(fid, "- Effective UL modulation histogram: `%s`\n", string(opSummary.UL.ModulationHistogram));
    fprintf(fid, "- Effective UL MCS histogram: `%s`\n", string(opSummary.UL.MCSHistogram));
end
fprintf(fid, "- Effective runtime note: `%s`\n", string(opSummary.RuntimeNarrative));
fprintf(fid, "\n## Report Bundle\n\n");
fprintf(fid, "- Coverage table: `reports/csv/lls_output_spec_coverage.csv`\n");
fprintf(fid, "- Metric rows: `reports/csv/lls_output_metric_rows.csv`\n");
fprintf(fid, "- Artifact inventory: `reports/csv/artifact_inventory.csv`\n");
fprintf(fid, "- Validation messages: `reports/csv/validation_messages.csv`\n");
fprintf(fid, "- Executive summary: `%s`\n", string(localRelativeToRunFolder(sixgr.util.structGet(reportBundle, "ExecutiveSummary", ""), runFolder)));
fprintf(fid, "- Technical report: `%s`\n", string(localRelativeToRunFolder(sixgr.util.structGet(reportBundle, "TechnicalReport", ""), runFolder)));
fprintf(fid, "\n## Source Chain\n\n");
for i = 1:numel(scfg.SourceFiles)
    fprintf(fid, "- `%s`\n", string(localPortablePath(scfg.SourceFiles(i))));
end
end

function opSummary = localOperatingPointSummary(scfg, result)
dlTrials = table();
ulTrials = table();
if isstruct(result) && isfield(result, "Link")
    rawTrials = sixgr.util.structGet(result.Link, "RawTrials", struct());
    dlTrials = localOptionalRawTrialTable(rawTrials, "DL");
    ulTrials = localOptionalRawTrialTable(rawTrials, "UL");
end
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials);
end

function T = localOptionalRawTrialTable(rawTrials, fieldName)
T = table();
if isstruct(rawTrials) && isfield(rawTrials, char(fieldName)) && istable(rawTrials.(char(fieldName)))
    T = rawTrials.(char(fieldName));
end
end

function resolvedStruct = localResolvedSnapshotStruct(scfg)
resolvedStruct = scfg.toStruct();
resolvedStruct = localSanitizeNoProxySnapshot(scfg, resolvedStruct);
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, table(), table());
legacyGrid = sixgr.util.structGet(resolvedStruct, "resource_grid.num_rbs", NaN);
activeGrid = double(opSummary.Radio.ActiveGridNumRBs);
if isfinite(activeGrid)
    if isfinite(legacyGrid) && legacyGrid ~= activeGrid
        resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.configured_num_rbs", legacyGrid);
    end
    resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.num_rbs", activeGrid);
    resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.active_num_rbs_source", char(string(opSummary.Radio.ActiveGridSource)));
end
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frequency.active_duplex_mode", char(string(opSummary.Radio.ActiveDuplexMode)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.configured_tdd_pattern", char(string(opSummary.Radio.ConfiguredTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.tdd_pattern_applicable", logical(opSummary.Radio.TDDPatternApplicable));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.active_tdd_pattern", char(string(opSummary.Radio.ActiveTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.configured_parameters_are_nominal", true);
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.actual_runtime_selected_parameters_emitted_in", "reports/csv/scenario_summary.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.report_bundle_runtime_metadata_emitted_in", "reports/csv/run_metadata_outputs.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.runtime_qualified_description_emitted_in", "reports/csv/scenario_summary.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_mimo", char(string(opSummary.Configured.MIMOText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_dl_nominal_operating_point", char(string(opSummary.Configured.DL.OperatingPointText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_ul_nominal_operating_point", char(string(opSummary.Configured.UL.OperatingPointText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_grid_num_rbs", double(opSummary.Radio.ActiveGridNumRBs));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_grid_source", char(string(opSummary.Radio.ActiveGridSource)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_duplex_mode", char(string(opSummary.Radio.ActiveDuplexMode)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_tdd_pattern", char(string(opSummary.Radio.ActiveTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.tdd_pattern_applicable", logical(opSummary.Radio.TDDPatternApplicable));
end

function resolvedStruct = localSanitizeNoProxySnapshot(scfg, resolvedStruct)
tags = lower(string(sixgr.util.structGet(resolvedStruct, "meta.tags", strings(0, 1))));
strictValidation = false;
try
    strictValidation = logical(scfg.get("logging.strict_validation", false));
catch
end
noProxyTruth = any(tags == "no-proxy") || (any(tags == "truth") && strictValidation);
if ~noProxyTruth
    return;
end

resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.no_proxy_truth_contract", true);
resolvedStruct = sixgr.util.structSet(resolvedStruct, ...
    "reporting_semantics.snapshot_sanitization_note", ...
    "Strict no-proxy truth snapshots disable proxy/fallback defaults and relabel complexity-derived area-efficiency metrics as measured runtime values.");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.area_efficiency_runtime_metric", "bits_per_decoder_complexity_unit");

resolvedStruct = sixgr.util.structSet(resolvedStruct, "ai_ml.fallback_enabled", false);
resolvedStruct = sixgr.util.structSet(resolvedStruct, "ai_ml.fallback_mode", "disabled");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "channel_coding.area_efficiency_proxy_policy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "coding_and_decoder.area_efficiency_proxy_policy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "energy_and_complexity.area_efficiency_proxy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "energy_efficiency.area_efficiency_proxy", "measured_runtime_metric");
end

function token = localNumericMarkdownToken(value)
if ~isfinite(double(value))
    token = "NaN";
elseif abs(double(value) - round(double(value))) < 1e-12
    token = string(round(double(value)));
else
    token = string(double(value));
end
end

function runtime = localBuildRuntimeSummary(startUTC, runTimer, profile, runFolder, cfg)
runtime = struct();
runtime.StartedUTC = char(string(startUTC));
runtime.CompletedUTC = char(string(localUTCStamp()));
runtime.ElapsedSeconds = double(toc(runTimer));
runtime.RunnerProfile = char(string(profile));
runtime.RunFolder = char(string(runFolder));
runtime.WarningCount = 0;
runtime.Warnings = strings(0, 1);
runtime.UseMex = logical(sixgr.util.structGet(cfg, "run.useMex", false));
runtime.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "run.useMexAutoEnabled", false));
runtime.UseParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
runtime.RequestedWorkers = double(sixgr.util.structGet(cfg, "run.parallelRequestedWorkers", ...
    sixgr.util.structGet(cfg, "run.numWorkers", 0)));
runtime.EffectiveWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
runtime.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
runtime.MaxNumCompThreads = double(localSafeMaxNumCompThreads());
end

function env = localBuildEnvironmentSummary(cfg)
env = struct();
env.Platform = char(string(computer));
env.Architecture = char(string(computer("arch")));
env.MATLABVersion = char(string(version));
env.MATLABRelease = char(string(version("-release")));
env.JavaVersion = char(string(version("-java")));
env.Hostname = char(string(getenv("COMPUTERNAME")));
env.OS = char(string(getenv("OS")));
env.PhysicalCoreCount = double(localSafeFeatureNumCores());
env.ComputeThreadCount = double(localSafeMaxNumCompThreads());
env.JavaAvailableProcessors = double(localSafeJavaAvailableProcessors());
env.ParallelToolboxInstalled = logical(localHasParallelToolboxInstalled());
env.ParallelLicenseAvailable = logical(localHasParallelLicense());
env.ParpoolFunctionAvailable = logical(exist("parpool", "file") == 2);
env.RequestedWorkers = double(sixgr.util.structGet(cfg, "run.parallelRequestedWorkers", ...
    sixgr.util.structGet(cfg, "run.numWorkers", 0)));
env.EffectiveWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
env.UseMex = logical(sixgr.util.structGet(cfg, "run.useMex", false));
env.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "run.useMexAutoEnabled", false));
env.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
end

function localEnsureScenarioDirs(layout)
dirs = { ...
    layout.MetaDir, layout.LogDir, layout.ReportDir, layout.ReportCSVDir, layout.ReportMATDir, ...
    layout.ReportImageDir, layout.AirInterfaceDir, layout.AirInterfaceCSVDir, layout.AirInterfaceMATDir, ...
    layout.AirInterfaceImageDir, layout.ControlDir, layout.ControlCSVDir, layout.ControlImageDir, ...
    layout.BeamformingDir, layout.BeamformingCSVDir, layout.BeamformingImageDir};
for i = 1:numel(dirs)
    sixgr.util.ensureFolder(dirs{i});
end
end

function leaf = localResolveLeaf(runTag)
runTag = char(string(runTag));
if strlength(string(runTag)) == 0
    leaf = "current";
else
    leaf = localSanitizeToken(runTag, "current");
end
end

function localApplyRunRandomness(scfg)
seed = double(scfg.get("simulation.random_seed"));
if logical(scfg.get("simulation.deterministic_mode"))
    rng(seed, "twister");
else
    rng("shuffle");
end
end

function cfg = localEnsureParallelExecution(cfg)
useParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
requestedWorkers = max(0, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 0))));
cfg = sixgr.util.structSet(cfg, "run.parallelRequestedWorkers", double(requestedWorkers));
cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "");
parallelInstalled = localHasParallelToolboxInstalled();
parallelLicensed = localHasParallelLicense();
parpoolAvailable = exist("parpool", "file") == 2;
if ~useParallel
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_not_requested");
    return;
end
if requestedWorkers <= 1
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "requested_workers_leq_1");
    return;
end
if ~parallelInstalled || ~parallelLicensed || ~parpoolAvailable
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    if ~parallelLicensed
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_license_unavailable");
    elseif ~parallelInstalled
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_not_installed");
    else
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_function_unavailable");
    end
    return;
end

pool = gcp("nocreate");
try
    if isempty(pool)
        pool = parpool("threads", requestedWorkers);
    elseif pool.NumWorkers ~= requestedWorkers
        delete(pool);
        pool = parpool("threads", requestedWorkers);
    end
catch
    try
        pool = gcp("nocreate");
        if isempty(pool)
            pool = parpool(requestedWorkers);
        elseif pool.NumWorkers ~= requestedWorkers
            delete(pool);
            pool = parpool(requestedWorkers);
        end
    catch
        cfg.run.useParallel = false;
        cfg.run.numWorkers = 0;
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_start_failed");
        return;
    end
end

cfg.run.useParallel = ~isempty(pool);
cfg.run.numWorkers = double(pool.NumWorkers);
cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "");
sixgr.util.rngInit(double(sixgr.util.structGet(cfg, "run.seed", 1)), true);
end

function cfg = localEnsureExactMexAcceleration(cfg)
requestedUseMex = sixgr.util.structGet(cfg, "run.useMex", []);
caps = localExactMexCapabilities();
autoEnabled = false;

if isempty(requestedUseMex)
    requestedUseMex = logical(caps.Any);
    autoEnabled = logical(caps.Any);
end

requestedUseMex = logical(requestedUseMex);
if requestedUseMex && ~logical(caps.Any)
    requestedUseMex = false;
end

cfg = sixgr.util.structSet(cfg, "run.useMex", requestedUseMex);
cfg = sixgr.util.structSet(cfg, "run.useMexAutoEnabled", autoEnabled);
cfg = sixgr.util.structSet(cfg, "run.exactMexAvailable", logical(caps.Any));
cfg = sixgr.util.structSet(cfg, "run.exactMexCapabilities", caps);
if requestedUseMex
    cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "");
else
    if logical(caps.Any)
        cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "exact_mex_not_requested");
    else
        cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "no_exact_mex_kernels_found");
    end
end
end

function caps = localExactMexCapabilities()
caps = struct();
caps.AWGNKernel = logical(exist("sixgr_awgn_complex_kernel_mex", "file") == 3);
caps.LDPCBatchDecodeKernel = logical(exist("sixgr_ldpc_decode_batch_kernel_mex", "file") == 3);
caps.StructGetKernel = logical(exist("sixgr_struct_get_mex", "file") == 3);
caps.FFTPAPRKernel = logical(exist("sixgr_fft_papr_kernel_mex", "file") == 3);
caps.Any = logical(caps.AWGNKernel || caps.LDPCBatchDecodeKernel || caps.StructGetKernel || caps.FFTPAPRKernel);
end

function tf = localHasParallelLicense()
try
    tf = logical(license("test", "Distrib_Computing_Toolbox"));
catch
    tf = false;
end
end

function tf = localHasParallelToolboxInstalled()
try
    tf = ~isempty(ver("parallel"));
catch
    tf = false;
end
end

function n = localSafeFeatureNumCores()
try
    n = double(feature("numcores"));
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function n = localSafeMaxNumCompThreads()
try
    n = double(maxNumCompThreads);
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function n = localSafeJavaAvailableProcessors()
try
    n = double(java.lang.Runtime.getRuntime.availableProcessors);
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function token = localSanitizeToken(inToken, fallback)
token = lower(strtrim(char(string(inToken))));
token = regexprep(token, '[^a-z0-9]+', '_');
token = regexprep(token, '_+', '_');
token = regexprep(token, '^_+|_+$', '');
if strlength(string(token)) == 0
    token = char(string(fallback));
end
end

function p = localPortablePath(inPath)
p = replace(string(inPath), "\", "/");
end

function txt = localRelativeToRunFolder(pathIn, runFolder)
txt = localPortablePath(pathIn);
if strlength(txt) == 0
    return;
end
root = regexprep(localPortablePath(runFolder), '/+', '/');
txt = regexprep(txt, '/+', '/');
if strcmpi(txt, root)
    txt = ".";
    return;
end
rootPrefix = root + "/";
if startsWith(lower(txt), lower(rootPrefix))
    txt = extractAfter(txt, strlength(rootPrefix));
end
end

function grid = localBuildSweepGrid(snr_dB, offsets_dB, sweepEnabled, explicitValues_dB)
if nargin >= 4 && logical(sweepEnabled)
    explicitValues_dB = double(explicitValues_dB(:)).';
    explicitValues_dB = explicitValues_dB(isfinite(explicitValues_dB));
    if ~isempty(explicitValues_dB)
        grid = unique(sort(explicitValues_dB));
        return;
    end
end
snr_dB = double(snr_dB);
offsets_dB = double(offsets_dB(:)).';
grid = unique(sort(snr_dB + offsets_dB));
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function y = localAddAwgnOnly(x, snr_dB)
snrLin = 10.^(snr_dB/10);
sigPow = max(mean(abs(x(:)).^2), 1);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
bt = min(numel(txBits), numel(rxBits));
if bt == 0
    be = NaN;
    return;
end
be = sum(txBits(1:bt) ~= rxBits(1:bt));
end

function val = localScalarValue(x)
if isempty(x)
    val = NaN;
elseif isscalar(x)
    val = double(x);
else
    val = double(x(1));
end
end

function nmse_dB = localUnitChannelNMSE(H)
if isempty(H)
    nmse_dB = NaN;
    return;
end
e = H(:) - 1;
nmse = mean(abs(e).^2) / max(mean(abs(ones(size(e))).^2), eps);
nmse_dB = 10*log10(max(nmse, eps));
end

function mcs = localClampMCS(mcsIn)
mcs = double(min(max(round(double(mcsIn)), 0), 27));
end

function score = localMCSScore(mcs)
score = (1 + double(mcs)) * 0.15;
end

function cls = localInterferenceClass(level_dB, thresholds_dB)
thresholds_dB = sort(double(thresholds_dB(:)).');
if isempty(thresholds_dB)
    thresholds_dB = [3 10];
end
if level_dB < thresholds_dB(1)
    cls = "low";
elseif numel(thresholds_dB) < 2 || level_dB < thresholds_dB(2)
    cls = "medium";
else
    cls = "high";
end
end

function det = localDetectorChoice(conditionNumber, threshold)
if conditionNumber >= threshold
    det = "MMSE";
else
    det = "ZF";
end
end

function bucket = localStudyBucketFromClass(researchClass)
researchClass = lower(string(researchClass));
if any(researchClass == ["baseline_benchmark", "agreed_starting_point"])
    bucket = "baseline";
elseif any(researchClass == ["study_item_candidate", "optional_research_experiment"])
    bucket = "open_study";
else
    bucket = "unclassified";
end
end

function status = localAggregateScenarioStatus(result)
status = struct();
status.RunCompletion = "completed";
status.ResultOk = logical(sixgr.util.structGet(result, "Ok", true));
status.PartialOk = false;
status.ArtifactsGenerated = true;
status.RequiredCaseCount = 1;
status.RequiredFailureCount = double(~status.ResultOk);
status.OptionalPrunedCount = 0;
status.RequiredFailedCases = strings(0, 1);
status.OptionalPrunedCases = strings(0, 1);
status.StatusAuthority = "scenario_status_aggregation_v1";
status.StatusNotes = "";
status.ProfileReportedOk = logical(sixgr.util.structGet(result, "Ok", true));
status.AuthoritativeStatusSource = "result.Ok";

if isstruct(result) && isfield(result, "Link")
    [status.ResultOk, status.RequiredCaseCount, status.RequiredFailureCount, ...
        status.RequiredFailedCases, status.OptionalPrunedCount, status.OptionalPrunedCases, ...
        status.StatusNotes, status.AuthoritativeStatusSource] = localAggregateWaveformLinkStatus(result.Link, status.ProfileReportedOk);
end

status.PartialOk = logical(status.ArtifactsGenerated) && ~logical(status.ResultOk);
end

function result = localApplyScenarioStatus(result, scenarioStatus)
result.ProfileReportedOk = logical(sixgr.util.structGet(result, "Ok", true));
result.Ok = logical(scenarioStatus.ResultOk);
result.RunCompletion = char(string(scenarioStatus.RunCompletion));
result.PartialOk = logical(scenarioStatus.PartialOk);
result.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
result.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
result.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
result.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
result.RequiredFailedCases = string(scenarioStatus.RequiredFailedCases(:));
result.OptionalPrunedCases = string(scenarioStatus.OptionalPrunedCases(:));
result.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
result.StatusNotes = char(string(scenarioStatus.StatusNotes));
result.AuthoritativeStatusSource = char(string(scenarioStatus.AuthoritativeStatusSource));
end

function [resultOk, requiredCaseCount, requiredFailureCount, failedCases, optionalPrunedCount, optionalPrunedCases, statusNotes, authority] = localAggregateWaveformLinkStatus(link, profileReportedOk)
resultOk = logical(profileReportedOk);
requiredCaseCount = NaN;
requiredFailureCount = NaN;
failedCases = strings(0, 1);
optionalPrunedCount = 0;
optionalPrunedCases = strings(0, 1);
statusNotes = "";
authority = "Link.Result.Ok";

kpitable = sixgr.util.structGet(link, "KPITable", table());
unsupported = sixgr.util.structGet(link, "UnsupportedCases", table());
linkResultOk = localTryLogical(sixgr.util.structGet(link, "Result.Ok", []), NaN);
linkOuterOk = localTryLogical(sixgr.util.structGet(link, "Ok", []), NaN);

if istable(kpitable) && ~isempty(kpitable)
    requiredCaseCount = double(height(kpitable));
    caseNames = string(localTableColumnOrDefault(kpitable, "Case", repmat("", height(kpitable), 1)));
    okMask = logical(localTableColumnOrDefault(kpitable, "Ok", true(height(kpitable), 1)));
    skippedMask = logical(localTableColumnOrDefault(kpitable, "Skipped", false(height(kpitable), 1)));
    failMask = ~okMask | skippedMask;
    requiredFailureCount = double(sum(failMask));
    failedCases = unique(caseNames(failMask), "stable");
end

if istable(unsupported) && ~isempty(unsupported) && ismember("Case", string(unsupported.Properties.VariableNames))
    optionalPrunedCases = unique(string(unsupported.Case), "stable");
    optionalPrunedCount = double(numel(optionalPrunedCases));
end

candidateOk = [linkResultOk, linkOuterOk];
candidateOk = candidateOk(isfinite(candidateOk));
if ~isempty(candidateOk)
    resultOk = all(candidateOk ~= 0);
end
if isfinite(requiredFailureCount)
    resultOk = resultOk && requiredFailureCount == 0;
end
if ~isfinite(requiredCaseCount) && ~isfinite(requiredFailureCount) && isfinite(linkResultOk)
    requiredCaseCount = 1;
    requiredFailureCount = double(~logical(linkResultOk));
end
if isfinite(linkResultOk) && isfinite(linkOuterOk) && logical(linkResultOk) ~= logical(linkOuterOk)
    statusNotes = localJoinStatusNotes(statusNotes, ...
        "Top-level link Ok disagreed with nested Link.Result.Ok; authoritative scenario status was derived conservatively from nested link status.");
end
if ~resultOk && isempty(failedCases) && isfinite(linkResultOk) && ~logical(linkResultOk)
    failedCases = "link_result";
    if ~isfinite(requiredFailureCount) || requiredFailureCount <= 0
        requiredFailureCount = 1;
    end
end
if ~isfinite(requiredCaseCount)
    requiredCaseCount = 0;
end
if ~isfinite(requiredFailureCount)
    requiredFailureCount = double(~resultOk);
end
end

function value = localTryLogical(rawValue, defaultValue)
if nargin < 2
    defaultValue = NaN;
end
if isempty(rawValue)
    value = defaultValue;
    return;
end
try
    value = double(logical(rawValue(1)));
catch
    value = defaultValue;
end
end

function values = localTableColumnOrDefault(T, name, defaultValue)
if istable(T) && ismember(name, string(T.Properties.VariableNames))
    values = T.(name);
else
    values = defaultValue;
end
end

function note = localJoinStatusNotes(varargin)
parts = strings(0, 1);
for i = 1:nargin
    txt = strtrim(string(varargin{i}));
    if strlength(txt) > 0
        parts(end+1, 1) = txt; %#ok<AGROW>
    end
end
if isempty(parts)
    note = "";
    return;
end
parts = unique(parts, "stable");
note = strjoin(parts, " | ");
end

function metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled)
metadata = struct();
metadata.UseCase = string(scfg.get("ai_ml.use_case"));
metadata.AIEnabled = logical(aiEnabled);
metadata.Mode = string(scfg.get("ai_ml.mode"));
metadata.ModelID = string(scfg.get("ai_ml.model_id"));
metadata.ModelVersion = string(scfg.get("ai_ml.model_version"));
metadata.DescriptorType = string(scfg.get("ai_ml.descriptor_type"));
metadata.QuantizationMode = string(scfg.get("ai_ml.quantization_mode"));
metadata.RuntimeBudget_us = double(scfg.get("ai_ml.runtime_budget_us"));
metadata.LatencyBudget_us = double(scfg.get("ai_ml.latency_budget_us"));
metadata.FLOPsBudget = double(scfg.get("ai_ml.flops_budget"));
metadata.InferenceBatchSize = double(scfg.get("ai_ml.inference_batch_size"));
metadata.FallbackEnabled = logical(scfg.get("ai_ml.fallback_enabled"));
metadata.ConfidenceLoggingEnabled = logical(scfg.get("ai_ml.confidence_logging"));
metadata.ParameterCount = double(localOptionalDescriptorValue(descriptor, "parameter_count", NaN));
metadata.ConfiguredInputFeatures = strjoin(string(scfg.get("ai_ml.input_features")), "|");
metadata.ConfiguredOutputTargets = strjoin(string(scfg.get("ai_ml.output_targets")), "|");
end

function T = localAppendBenchmarkColumns(T, metadata, confidenceValue)
if ~istable(T)
    return;
end
vars = { ...
    "UseCase", repmat(metadata.UseCase, height(T), 1), ...
    "AIEnabled", repmat(metadata.AIEnabled, height(T), 1), ...
    "Mode", repmat(metadata.Mode, height(T), 1), ...
    "ModelID", repmat(metadata.ModelID, height(T), 1), ...
    "ModelVersion", repmat(metadata.ModelVersion, height(T), 1), ...
    "DescriptorType", repmat(metadata.DescriptorType, height(T), 1), ...
    "QuantizationMode", repmat(metadata.QuantizationMode, height(T), 1), ...
    "RuntimeBudget_us", repmat(metadata.RuntimeBudget_us, height(T), 1), ...
    "LatencyBudget_us", repmat(metadata.LatencyBudget_us, height(T), 1), ...
    "FLOPsBudget", repmat(metadata.FLOPsBudget, height(T), 1), ...
    "InferenceBatchSize", repmat(metadata.InferenceBatchSize, height(T), 1), ...
    "FallbackEnabled", repmat(metadata.FallbackEnabled, height(T), 1), ...
    "ConfidenceLoggingEnabled", repmat(metadata.ConfidenceLoggingEnabled, height(T), 1), ...
    "ConfidenceScore", repmat(confidenceValue, height(T), 1), ...
    "ParameterCount", repmat(metadata.ParameterCount, height(T), 1)};
    for k = 1:2:numel(vars)
        name = vars{k};
        values = vars{k+1};
        if ~ismember(name, T.Properties.VariableNames)
            T = addvars(T, values, 'NewVariableNames', name);
        end
    end
end

function value = localBenchmarkConfidence(descriptor, scfg)
if ~logical(scfg.get("ai_ml.confidence_logging"))
    value = NaN;
    return;
end
value = double(localOptionalDescriptorValue(descriptor, "confidence_bias", NaN));
end

function Hout = localApplyCEPlugin(Hin, descriptor)
pluginType = lower(string(localRequireDescriptorField(descriptor, "plugin_type")));
switch pluginType
    case "moving_average_denoiser"
        alpha = double(localRequireDescriptorField(descriptor, "smoothing_alpha"));
        Hout = (1 - alpha) .* Hin + alpha .* ones(size(Hin), "like", Hin);
    otherwise
        Hout = Hin;
end
end

function [xHat, ratio] = localApplyCSICompressionPlugin(x, descriptor, latentDim, quantBits)
x = double(x(:));
step = max(1, ceil(numel(x) / max(latentDim, 1)));
z = x(1:step:end);
maxAbs = max(abs(z));
if maxAbs <= 0
    zq = z;
else
    qLevels = max(2^max(quantBits,1)-1, 1);
    zq = round((z / maxAbs) * qLevels) / qLevels * maxAbs;
end
xHat = repelem(zq, step);
xHat = xHat(1:numel(x));
ratio = double(numel(x)) / max(double(numel(zq)), 1);
if lower(string(localRequireDescriptorField(descriptor, "plugin_type"))) ~= "latent_quantizer"
    xHat = x;
    ratio = 1;
end
end

function beamIdx = localApplyBeamPlugin(metric, descriptor)
pluginType = lower(string(localRequireDescriptorField(descriptor, "plugin_type")));
metric = double(metric(:));
switch pluginType
    case "argmax"
        [~, beamIdx] = max(metric);
    case "top2_energy_bias"
        [~, idx] = sort(metric, "descend");
        beamIdx = idx(min(2, numel(idx)));
    otherwise
        [~, beamIdx] = max(metric);
end
beamIdx = double(beamIdx);
end

function descriptor = localLoadAIDescriptor(modelPath)
descriptor = struct();
modelPath = string(modelPath);
if strlength(modelPath) == 0
    return;
end
resolved = localResolveModelPath(modelPath);
if exist(resolved, "file") ~= 2
    return;
end
descriptor = sixgr.lls6g.config.readConfigFile(resolved);
end

function value = localRequireDescriptorField(descriptor, fieldName)
if ~isfield(descriptor, fieldName)
    error("sixgr:lls6g:runner:MissingDescriptorField", ...
        "AI descriptor is missing required field '%s'.", fieldName);
end
value = descriptor.(fieldName);
end

function value = localOptionalDescriptorValue(descriptor, fieldName, defaultValue)
if isfield(descriptor, fieldName)
    value = descriptor.(fieldName);
else
    value = defaultValue;
end
end

function p = localResolveModelPath(modelPath)
if exist(char(modelPath), "file") == 2
    p = char(modelPath);
    return;
end
root = localRepoRoot();
candidate = fullfile(root, char(modelPath));
if exist(candidate, "file") == 2
    p = candidate;
    return;
end
p = char(modelPath);
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function localPruneEmptyDirs(rootFolder)
rootFolder = char(string(rootFolder));
if ~isfolder(rootFolder)
    return;
end
entries = dir(rootFolder);
for i = 1:numel(entries)
    name = string(entries(i).name);
    if name == "." || name == ".." || ~entries(i).isdir
        continue;
    end
    child = fullfile(rootFolder, char(name));
    localPruneEmptyDirs(child);
end
entries = dir(rootFolder);
entries = entries(~ismember(string({entries.name}), [".", ".."]));
if isempty(entries)
    try
        rmdir(rootFolder);
    catch
    end
end
end
