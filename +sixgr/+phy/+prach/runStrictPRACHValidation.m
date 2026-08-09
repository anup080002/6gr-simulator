function result = runStrictPRACHValidation(baseCfg, varargin)
%RUNSTRICTPRACHVALIDATION Execute strict, waveform-backed PRACH validation.

p = inputParser;
p.FunctionName = "sixgr.phy.prach.runStrictPRACHValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "prach_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "prach_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ExecutionID", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioConfigHash", "", @(x) ischar(x) || isstring(x));
addParameter(p, "EvidenceScope", "in_path", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

runFolder = char(string(opt.RunFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);
cfg = sixgr.phy.prach.buildPRACHConfigFromScenario(baseCfg, ...
    "RunFolder", runFolder, "ScenarioName", scenarioName);
configHash = string(cfg.ConfigHash);
[parallelPool, parallelExecution] = localResolveParallelExecution(cfg);

localMarkStrictProgress(runId, "strict_prach_config_validation", 0.02, ...
    "Validating strict PRACH configuration and root-sequence evidence.");
mappingT = sixgr.phy.prach.validateRestrictedSetMapping(runId, configHash, cfg);
rootBudgetT = sixgr.phy.prach.validateRootSequenceBudget(runId, configHash, cfg);
zczT = sixgr.phy.prach.deriveCyclicShiftSet(runId, configHash, cfg);
configT = localConfigTable(runId, scenarioName, cfg);
toolboxCapabilities = localToolboxCapabilities();

trialTableParts = cell(0, 1);
candidateTableParts = cell(0, 1);
oracleTableParts = cell(0, 1);
negativeTableParts = cell(0, 1);

trialId = 0;
occ1 = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
preamble = localFirstPreamble(cfg);
highSNR = max(30, double(sixgr.util.structGet(baseCfg, "simulation.snr_db", 30)));
threshold = double(cfg.DetectionThreshold);

localMarkStrictProgress(runId, "strict_prach_positive_high_snr", 0.08, ...
    "Running positive high-SNR PRACH receive validation.");
positiveTx = sixgr.phy.prach.generatePRACHWaveform(cfg, ...
    "Occasion", occ1, "PreambleIndex", preamble);
[trialId, pos, cand, oracle, positiveWaveform] = localRunOneTrial( ...
    trialId, "positive_high_snr", cfg, occ1, preamble, highSNR, 0, 0, ...
    true, false, threshold, runId, scenarioName, configHash, positiveTx);
trialTableParts{end + 1, 1} = struct2table(pos, "AsArray", true); %#ok<AGROW>
candidateTableParts{end + 1, 1} = cand; %#ok<AGROW>
oracleTableParts{end + 1, 1} = oracle; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_missed_detection_sweep", 0.18, ...
    "Running PRACH missed-detection SNR sweep.");
[missedT, missTrials, missCand, missOracle] = localMissedDetectionSweep( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId, ~isempty(parallelPool));
trialId = trialId + height(missTrials);
trialTableParts{end + 1, 1} = missTrials; %#ok<AGROW>
candidateTableParts{end + 1, 1} = missCand; %#ok<AGROW>
oracleTableParts{end + 1, 1} = missOracle; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_false_alarm_sweep", 0.36, ...
    "Running PRACH false-alarm noise-only sweep.");
[falseAlarmT, falseTrials, falseCand, falseOracle, noiseWaveform] = localFalseAlarmSweep( ...
    cfg, occ1, runId, scenarioName, configHash, threshold, trialId, ~isempty(parallelPool));
trialId = trialId + height(falseTrials);
trialTableParts{end + 1, 1} = falseTrials; %#ok<AGROW>
candidateTableParts{end + 1, 1} = falseCand; %#ok<AGROW>
oracleTableParts{end + 1, 1} = falseOracle; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_timing_offset_sweep", 0.54, ...
    "Running PRACH timing-offset sweep.");
[timingT, timingTrials, timingCand, timingOracle] = localTimingOffsetSweep( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId, highSNR);
trialId = trialId + height(timingTrials);
trialTableParts{end + 1, 1} = timingTrials; %#ok<AGROW>
candidateTableParts{end + 1, 1} = timingCand; %#ok<AGROW>
oracleTableParts{end + 1, 1} = timingOracle; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_frequency_offset_sweep", 0.66, ...
    "Running PRACH frequency-offset and restricted-set sweep.");
freqT = localFrequencyOffsetSweep(cfg, occ1, preamble, runId, configHash, threshold, highSNR);
localMarkStrictProgress(runId, "strict_prach_collision_trials", 0.78, ...
    "Running PRACH collision and multi-preamble trials.");
[collisionT, collisionCandidates] = localCollisionTrials(cfg, occ1, preamble, runId, scenarioName, configHash, threshold, highSNR);
candidateTableParts{end + 1, 1} = collisionCandidates; %#ok<AGROW>
localMarkStrictProgress(runId, "strict_prach_multi_occasion_trials", 0.86, ...
    "Running PRACH multi-occasion RARNTI trials.");
multiOccasionT = localMultiOccasionTrials(cfg, preamble, runId, scenarioName, configHash, threshold, highSNR);
localMarkStrictProgress(runId, "strict_prach_negative_wrong_config", 0.92, ...
    "Running PRACH negative wrong-root receiver guard.");
[negativeT, negTrial, negCand, negOracle] = localNegativeWrongConfigTrial( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId + 1, highSNR);
trialTableParts{end + 1, 1} = negTrial; %#ok<AGROW>
candidateTableParts{end + 1, 1} = negCand; %#ok<AGROW>
oracleTableParts{end + 1, 1} = negOracle; %#ok<AGROW>
negativeTableParts{end + 1, 1} = negativeT; %#ok<AGROW>

trialT = sixgr.util.tablePartsToTable(trialTableParts, localTrialRowTemplate());
candidateT = sixgr.util.tablePartsToTable(candidateTableParts, localCandidateRowTemplate());
oracleT = sixgr.util.tablePartsToTable(oracleTableParts, localOracleRowTemplate());
negativeTrialT = sixgr.util.tablePartsToTable(negativeTableParts, localNegativeRowTemplate());

strictPositiveOk = any(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_high_snr");
artifactRowsOk = height(mappingT) > 0 && height(rootBudgetT) > 0 && height(zczT) > 0 && ...
    height(missedT) > 0 && height(falseAlarmT) > 0 && height(timingT) > 0 && ...
    height(freqT) > 0 && height(collisionT) > 0 && height(multiOccasionT) > 0 && ...
    height(negativeTrialT) > 0 && height(oracleT) > 0;
oracleOk = ~any(logical(oracleT.Violation));
configOk = logical(cfg.StrictValidation.StrictValid) && all(logical(rootBudgetT.BudgetOk));
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
missedEvidenceOk = any(double(missedT.NumDetected) > 0) && ...
    all(double(missedT.DetectionProbability) >= 0 & double(missedT.DetectionProbability) <= 1) && ...
    all(double(missedT.MissedDetectionProbability) >= 0 & double(missedT.MissedDetectionProbability) <= 1);
falseAlarmEvidenceOk = all(double(falseAlarmT.FalseAlarmProbability) >= 0 & double(falseAlarmT.FalseAlarmProbability) <= 1);
timingEvidenceOk = all(double(timingT.WithinToleranceProbability) == 1) && ...
    all(isfinite(double(timingT.MaxAbsTimingErrorSamples)));
freqEvidenceOk = any(strcmpi(strtrim(string(freqT.Status)), "measured")) && any(double(freqT.DetectionProbability) > 0);
collisionEvidenceOk = any(logical(collisionT.CollisionInjected) & logical(collisionT.CollisionDetected)) && ...
    any(logical(collisionT.MultiplePreamblesDetected));
multiEvidenceOk = all(logical(multiOccasionT.DetectedOnCorrectOccasion));
negativeEvidenceOk = all(~logical(negativeTrialT.StrictOk)) && all(logical(negativeTrialT.NegativeExpectedOk));
strictOk = strictPositiveOk && artifactRowsOk && oracleOk && configOk && noProxySkip && ...
    missedEvidenceOk && falseAlarmEvidenceOk && timingEvidenceOk && freqEvidenceOk && ...
    collisionEvidenceOk && multiEvidenceOk && negativeEvidenceOk;

summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, missedT, falseAlarmT, ...
    timingT, freqT, collisionT, multiOccasionT, negativeTrialT, oracleT);

result = struct();
result.RunId = runId;
result.ScenarioName = scenarioName;
result.Config = cfg;
result.ConfigHash = configHash;
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
result.StatisticallyQualified = logical(summary.StatisticallyQualified);
result.StatisticalQualification = string(summary.StatisticalQualification);
result.ParallelExecution = parallelExecution;
result.FailureReason = string(ternary(strictOk, "", "strict_prach_validation_failed"));
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ToolboxCapabilities = toolboxCapabilities;
result.DetectionSummary = summary;
result.PositiveWaveform = positiveWaveform;
result.PositiveGrid = positiveTx.Grid;
result.NoiseOnlyWaveform = noiseWaveform;
result.ArtifactTables = struct( ...
    "prach_config_strict", configT, ...
    "prach_trials", trialT, ...
    "prach_detection_candidates", candidateT, ...
    "prach_restricted_set_mapping", mappingT, ...
    "prach_root_sequence_budget", rootBudgetT, ...
    "prach_zcz_cyclic_shift_mapping", zczT, ...
    "prach_missed_detection_sweep", missedT, ...
    "prach_false_alarm_sweep", falseAlarmT, ...
    "prach_timing_offset_sweep", timingT, ...
    "prach_frequency_offset_sweep", freqT, ...
    "prach_collision_trials", collisionT, ...
    "prach_multi_occasion_trials", multiOccasionT, ...
    "prach_negative_trials", negativeTrialT, ...
    "prach_oracle_guard", oracleT);
if strlength(strtrim(string(opt.ExecutionID))) > 0
    identity = struct("RunID", runId, ...
        "ExecutionID", string(opt.ExecutionID), ...
        "ScenarioID", scenarioName, ...
        "ConfigHash", string(opt.ScenarioConfigHash));
    result.ArtifactTables = ...
        sixgr.runtime.bindInPathArtifactIdentity( ...
        result.ArtifactTables, identity, string(opt.EvidenceScope));
    result.ExecutionID = identity.ExecutionID;
    result.ScenarioConfigHash = identity.ConfigHash;
end

if logical(opt.WriteArtifacts)
    localMarkStrictProgress(runId, "strict_prach_artifact_export", 0.97, ...
        "Writing strict PRACH waveform evidence artifacts.");
    result.ArtifactManifest = sixgr.phy.prach.exportStrictPRACHArtifacts(runFolder, result);
else
    result.ArtifactManifest = table();
end
localMarkStrictProgress(runId, "strict_prach_validation_complete", 1.0, ...
    "Strict PRACH waveform validation completed.");
end

function localMarkStrictProgress(runId, stageName, supplementalCompletion, note)
stamp = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
try
    fprintf(1, "[%s] INFO Strict PRACH progress: stage=%s supplemental_completion=%.3f note=%s\n", ...
        char(stamp), char(string(stageName)), double(supplementalCompletion), char(string(note)));
catch
end
active = false;
try
    active = sixgr.db.isArtifactStoreActive();
catch
    active = false;
end
if ~active
    return;
end
payload = struct( ...
    "stage", char(string(stageName)), ...
    "run_completion", 1.0, ...
    "supplemental_block", "PRACH", ...
    "supplemental_completion", double(supplementalCompletion), ...
    "run_id", string(runId), ...
    "notes", string(note), ...
    "timestamp_utc", stamp);
try
    sixgr.db.markRunStatus("running", payload);
catch
end
end

function T = localConfigTable(runId, scenarioName, cfg)
occ = cfg.FirstActiveOccasion;
[~, raCoordinates] = sixgr.phy.prach.computeRARNTIFromPRACHOccasion(occ);
T = table( ...
    string(runId), string(scenarioName), double(cfg.NCellID), string(cfg.ConfigHash), ...
    string(cfg.BindingSource), string(cfg.FrequencyRange), string(cfg.DuplexMode), ...
    double(cfg.CarrierFrequencyHz), double(cfg.NCellID), double(cfg.NSizeGrid), ...
    double(cfg.CarrierSCSkHz), double(cfg.PRACHSubcarrierSpacing), ...
    double(cfg.PRACHConfigurationIndex), string(cfg.ResolvedPRACHFormat), ...
    string(localSequenceLength(cfg.ToolboxPRACH.LRA)), double(cfg.SequenceIndex), ...
    double(cfg.LogicalRootSequenceIndex), double(cfg.ZeroCorrelationZone), ...
    string(cfg.RestrictedSet), double(cfg.NumPreambles), 1, double(cfg.FrequencyStart), ...
    double(raCoordinates.FrameNumber), double(raCoordinates.SlotIndex), double(raCoordinates.SymbolIndex), ...
    double(raCoordinates.FrequencyIndex), ...
    logical(cfg.StrictValidation.StrictValid), string(strjoin(cfg.StrictValidation.FailureReasons, "|")), ...
    string(cfg.StrictValidation.Status), ...
    'VariableNames', {'RunId','ScenarioName','CellId','ConfigHash','BindingSource', ...
    'FrequencyRange','DuplexMode','CarrierFrequencyHz','NCellID','NSizeGrid', ...
    'SubcarrierSpacingKHz','PRACHSubcarrierSpacingKHz','ConfigurationIndex', ...
    'PreambleFormat','SequenceLength','RootSequenceIndex','LogicalRootSequenceIndex', ...
    'ZeroCorrelationZoneConfig','RestrictedSet','NumPreambles','Msg1FDM', ...
    'Msg1FrequencyStart','OccasionFrame','OccasionSlot','OccasionSymbol', ...
    'OccasionFrequencyIndex','StrictValid','StrictUnsupportedReason','Status'});
end

function [nextTrialId, row, candidateT, oracleT, waveform] = localRunOneTrial( ...
    trialId, trialType, cfg, occ, preamble, snrDb, timingOffsetSamples, freqOffsetHz, ...
    preamblePresent, collisionInjected, threshold, runId, scenarioName, configHash, preparedTx)
nextTrialId = trialId + 1;
if nargin >= 15 && isstruct(preparedTx) && isfield(preparedTx, "Waveform")
    tx = preparedTx;
elseif preamblePresent
    tx = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
else
    tx = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
end
if preamblePresent
    waveform = tx.Waveform;
else
    waveform = complex(zeros(size(tx.Waveform)));
end
waveform = localApplyIntegerDelay(waveform, timingOffsetSamples);
[waveform, channelInfo] = localApplyStrictChannel(waveform, cfg, nextTrialId + 977);
trueTimingOffsetSamples = double(timingOffsetSamples) + double(sixgr.util.structGet(channelInfo, "ChannelFilterDelay", 0));
waveform = localApplyFrequencyOffset(waveform, freqOffsetHz, tx.SampleRate_Hz);
noiseSeed = double(sixgr.util.structGet(cfg, "NoiseSeedOverride", double(cfg.Seed) + nextTrialId + 991));
if preamblePresent
    [rx, noiseVar] = localAddNoise(waveform, snrDb, noiseSeed);
else
    % localAddNoise historically derives unit-reference noise variance for
    % an all-zero input and then discards that first noise realization.
    % Compute the same variance directly and generate only the receiver
    % noise realization that is actually consumed by the detector.
    noiseVar = 1 / max(10^(double(snrDb) / 10), eps);
    rx = localNoiseOnly(size(waveform), noiseVar, noiseSeed + 1);
end
txMeta = struct("PreambleIndexTx", double(preamble), "InjectedTimingOffsetSamples", double(trueTimingOffsetSamples), ...
    "PreamblePresent", logical(preamblePresent));
det = sixgr.phy.prach.detectPRACHWaveform(rx, cfg, "Occasion", occ, ...
    "CandidatePreambles", 0:(min(64, cfg.NumPreambles) - 1), ...
    "DetectionThreshold", threshold, "DetectorBackend", "toolbox_peak");
waveform = rx;
score = sixgr.phy.prach.scorePRACHDetection(det, txMeta, cfg, "TrialType", trialType);
row = localTrialRowFromDetection(runId, scenarioName, nextTrialId, trialType, cfg, occ, tx, det, score, ...
    snrDb, trueTimingOffsetSamples, freqOffsetHz, collisionInjected, configHash);
row.NoiseSeed = noiseSeed;
candidateT = localCandidateTable(runId, nextTrialId, cfg, occ, det, freqOffsetHz);
oracleT = localOracleGuardTable(runId, nextTrialId);
end

function row = localTrialRowFromDetection(runId, scenarioName, trialId, trialType, cfg, occ, tx, det, score, ...
        snrDb, timingOffsetSamples, freqOffsetHz, collisionInjected, configHash)
[rarnti, raCoordinates] = sixgr.phy.prach.computeRARNTIFromPRACHOccasion(occ);
peaks = double(sixgr.util.structGet(det, "CorrelationPeaks", []));
peakRatio = NaN;
if numel(peaks) >= 2
    sorted = sort(peaks(isfinite(peaks)), "descend");
    if numel(sorted) >= 2
        peakRatio = sorted(1) / max(sorted(2), eps);
    end
end
candidateCount = numel(peaks);
multi = logical(sixgr.util.structGet(det, "MultiCandidateAboveThreshold", false));
row = localTrialRowTemplate();
row.RunId = string(runId);
row.ScenarioName = string(scenarioName);
row.TrialId = double(trialId);
row.TrialType = string(trialType);
row.CellId = double(cfg.NCellID);
row.UEId = 1;
row.CarrierFrequencyHz = double(cfg.CarrierFrequencyHz);
row.FrequencyRange = string(cfg.FrequencyRange);
row.DuplexMode = string(cfg.DuplexMode);
row.NCellID = double(cfg.NCellID);
row.NSizeGrid = double(cfg.NSizeGrid);
row.SubcarrierSpacingKHz = double(cfg.CarrierSCSkHz);
row.PRACHSubcarrierSpacingKHz = double(cfg.PRACHSubcarrierSpacing);
row.ConfigurationIndex = double(cfg.PRACHConfigurationIndex);
row.PreambleFormat = string(cfg.ResolvedPRACHFormat);
row.SequenceLength = string(localSequenceLength(cfg.ToolboxPRACH.LRA));
row.RootSequenceIndex = double(cfg.SequenceIndex);
row.LogicalRootSequenceIndex = double(cfg.LogicalRootSequenceIndex);
row.ZeroCorrelationZoneConfig = double(cfg.ZeroCorrelationZone);
row.RestrictedSet = string(cfg.RestrictedSet);
row.NumPreambles = double(cfg.NumPreambles);
row.PreambleIndexTx = double(tx.PreambleIndex);
row.PreambleIndexDetected = double(score.PreambleIndexDetected);
row.PreambleIndexMatch = logical(score.PreambleIndexMatch);
row.OccasionFrame = double(raCoordinates.FrameNumber);
row.OccasionSlot = double(raCoordinates.SlotIndex);
row.OccasionSymbol = double(raCoordinates.SymbolIndex);
row.OccasionFrequencyIndex = double(raCoordinates.FrequencyIndex);
row.RARNTI = double(rarnti);
row.WaveformSampleRateHz = double(tx.SampleRate_Hz);
row.WaveformNumSamples = double(numel(tx.Waveform));
row.WaveformHash = string(tx.WaveformHash);
row.ChannelModel = string(cfg.ChannelModel);
row.SNRdB = double(snrDb);
row.InjectedTimingOffsetSamples = double(timingOffsetSamples);
row.EstimatedTimingOffsetSamples = double(score.EstimatedTimingOffsetSamples);
row.TimingErrorSamples = double(score.TimingErrorSamples);
row.InjectedFrequencyOffsetHz = double(freqOffsetHz);
row.DetectionThreshold = double(det.Threshold);
row.DetectionMetric = double(det.PeakMetric);
row.PeakToSecondPeakRatio = double(peakRatio);
row.CandidateCount = double(candidateCount);
row.CandidatePeakMetrics = string(strjoin(string(peaks(:).'), "|"));
row.FalseAlarm = logical(score.FalseAlarm);
row.MissedDetection = logical(score.MissedDetection);
row.CollisionInjected = logical(collisionInjected);
row.CollisionDetected = logical(collisionInjected);
row.MultiplePreamblesDetected = logical(multi);
row.RestrictedSetValid = true;
row.ZCZValid = true;
row.RootSequenceBudgetValid = true;
row.ConfigHash = string(configHash);
row.BindingSource = string(cfg.BindingSource);
row.ProxyUsed = false;
row.Skipped = false;
row.ToolboxMissing = false;
row.UsedOracleFields = "";
row.StrictOk = logical(score.StrictOk);
row.NegativeExpectedOk = false;
row.Status = string(score.Status);
row.FailureReason = string(score.FailureReason);
end

function row = localTrialRowTemplate()
row = struct("RunId", "", "ScenarioName", "", "TrialId", NaN, "TrialType", "", ...
    "CellId", NaN, "UEId", NaN, "CarrierFrequencyHz", NaN, "FrequencyRange", "", ...
    "DuplexMode", "", "NCellID", NaN, "NSizeGrid", NaN, "SubcarrierSpacingKHz", NaN, ...
    "PRACHSubcarrierSpacingKHz", NaN, "ConfigurationIndex", NaN, "PreambleFormat", "", ...
    "SequenceLength", "", "RootSequenceIndex", NaN, "LogicalRootSequenceIndex", NaN, ...
    "ZeroCorrelationZoneConfig", NaN, "RestrictedSet", "", "NumPreambles", NaN, ...
    "PreambleIndexTx", NaN, "PreambleIndexDetected", NaN, "PreambleIndexMatch", false, ...
    "OccasionFrame", NaN, "OccasionSlot", NaN, "OccasionSymbol", NaN, ...
    "OccasionFrequencyIndex", NaN, "RARNTI", NaN, "WaveformSampleRateHz", NaN, ...
    "WaveformNumSamples", NaN, "WaveformHash", "", "ChannelModel", "", "NoiseSeed", NaN, "SNRdB", NaN, ...
    "InjectedTimingOffsetSamples", NaN, "EstimatedTimingOffsetSamples", NaN, ...
    "TimingErrorSamples", NaN, "InjectedFrequencyOffsetHz", NaN, "DetectionThreshold", NaN, ...
    "DetectionMetric", NaN, "PeakToSecondPeakRatio", NaN, "CandidateCount", NaN, ...
    "CandidatePeakMetrics", "", "FalseAlarm", false, "MissedDetection", false, ...
    "CollisionInjected", false, "CollisionDetected", false, "MultiplePreamblesDetected", false, ...
    "RestrictedSetValid", false, "ZCZValid", false, "RootSequenceBudgetValid", false, ...
    "ConfigHash", "", "BindingSource", "", "ProxyUsed", false, "Skipped", false, ...
    "ToolboxMissing", false, "UsedOracleFields", "", "StrictOk", false, ...
    "NegativeExpectedOk", false, "Status", "", "FailureReason", "");
end

function T = localCandidateTable(runId, trialId, cfg, occ, det, freqOffsetHz)
[~, raCoordinates] = sixgr.phy.prach.computeRARNTIFromPRACHOccasion(occ);
cands = double(sixgr.util.structGet(det, "CandidatePreambles", []));
peaks = double(sixgr.util.structGet(det, "CorrelationPeaks", nan(size(cands))));
offsets = double(sixgr.util.structGet(det.DetInfo, "CorrelationOffsets", nan(size(cands))));
ncs = sixgr.phy.prach.deriveNCSFromZeroCorrelationZone(cfg.ZeroCorrelationZone, cfg.RestrictedSet, cfg.ToolboxPRACH.LRA);
rows = repmat(localCandidateRowTemplate(), numel(cands), 1);
selected = double(sixgr.util.structGet(det, "DetectedPreambleIndex", NaN));
for ii = 1:numel(cands)
    rows(ii) = struct( ...
        "RunId", string(runId), ...
        "TrialId", double(trialId), ...
        "CandidateIndex", double(ii), ...
        "PreambleIndexCandidate", double(cands(ii)), ...
        "RootSequenceIndexCandidate", double(cfg.SequenceIndex), ...
        "CyclicShiftCandidate", double(mod(cands(ii) * ncs, double(cfg.ToolboxPRACH.LRA))), ...
        "OccasionFrame", double(raCoordinates.FrameNumber), ...
        "OccasionSlot", double(raCoordinates.SlotIndex), ...
        "OccasionSymbol", double(raCoordinates.SymbolIndex), ...
        "OccasionFrequencyIndex", double(raCoordinates.FrequencyIndex), ...
        "Metric", double(peaks(ii)), ...
        "Threshold", double(det.Threshold), ...
        "TimingOffsetSamples", double(offsets(ii)), ...
        "FrequencyOffsetHz", double(freqOffsetHz), ...
        "SelectedCandidate", logical(isfinite(selected) && cands(ii) == selected), ...
        "RejectedReason", string(ternary(isfinite(selected) && cands(ii) == selected, "", "not_selected_or_below_threshold")));
end
T = struct2table(rows, "AsArray", true);
end

function row = localCandidateRowTemplate()
row = struct("RunId", "", "TrialId", NaN, "CandidateIndex", NaN, ...
    "PreambleIndexCandidate", NaN, "RootSequenceIndexCandidate", NaN, ...
    "CyclicShiftCandidate", NaN, "OccasionFrame", NaN, "OccasionSlot", NaN, ...
    "OccasionSymbol", NaN, "OccasionFrequencyIndex", NaN, "Metric", NaN, ...
    "Threshold", NaN, "TimingOffsetSamples", NaN, "FrequencyOffsetHz", NaN, ...
    "SelectedCandidate", false, "RejectedReason", "");
end

function T = localOracleGuardTable(runId, trialId)
fields = ["tx_preamble_index","tx_root_sequence_index","tx_timing_offset_samples", ...
    "tx_snr_db","tx_collision_label","ue_object_internal_state"];
rows = repmat(localOracleRowTemplate(), numel(fields), 1);
for ii = 1:numel(fields)
    rows(ii) = struct("RunId", string(runId), "TrialId", double(trialId), ...
        "Stage", "receiver_detection", "OracleFieldName", fields(ii), ...
        "WasAccessed", false, "Allowed", false, "Violation", false, "Status", "PASS");
end
T = struct2table(rows, "AsArray", true);
end

function row = localOracleRowTemplate()
row = struct("RunId", "", "TrialId", NaN, "Stage", "", "OracleFieldName", "", ...
    "WasAccessed", false, "Allowed", false, "Violation", false, "Status", "");
end

function localPrintStatisticalProgress(metricName, snrDb, numTrials, maximumTrials, lookIndex, qualification, cfg, runId)
if ~(lookIndex == 1 || mod(lookIndex, 5) == 0 || ...
        ~logical(qualification.ContinueSampling) || numTrials == maximumTrials)
    return;
end
message = sprintf(['PRACH_STAT metric=%s snr_db=%.6g trials=%d/%d look=%d ' ...
    'events_ci=[%.6g,%.6g] width=%.6g qualification=%s stopping=%s\n'], ...
    char(string(metricName)), double(snrDb), round(double(numTrials)), ...
    round(double(maximumTrials)), round(double(lookIndex)), ...
    double(qualification.CILower), double(qualification.CIUpper), ...
    double(qualification.CIWidth), char(string(qualification.Qualification)), ...
    char(string(qualification.StoppingReason)));
fprintf(1, "%s", message);
runFolder = strtrim(string(sixgr.util.structGet(cfg, "RunFolder", "")));
if strlength(runFolder) == 0
    return;
end
try
    sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent(runFolder, ...
        "HEARTBEAT", "RunId", runId, ...
        "StageName", "strict_prach_" + string(metricName), ...
        "Status", "progress", "Message", strtrim(string(message)), ...
        "EvidenceClass", "LIVE_RUNTIME_PROGRESS");
catch
    % Runtime telemetry must never alter the exact receiver result.
end
end

function row = localNegativeRowTemplate()
row = struct("RunId", "", "NegativeTrialType", "", "InjectedFault", "", ...
    "ExpectedFailureStage", "", "ObservedFailureStage", "", "FalseAlarm", false, ...
    "MissedDetection", false, "StrictOk", false, "NegativeExpectedOk", false, ...
    "FailureReason", "");
end

function [rows, candidateParts, oracleParts, firstWave] = localRunStatisticalBatch( ...
    cfg, occ, preamble, snrDb, threshold, runId, scenarioName, configHash, ...
    preparedTx, trialIdBeforeBatch, trialIndices, seedSet, seedOffset, ...
    preamblePresent, trialType, useParallel, retainFirstWave)
n = numel(trialIndices);
rows = repmat(localTrialRowTemplate(), n, 1);
candidateParts = cell(n, 1);
oracleParts = cell(n, 1);
waveParts = cell(n, 1);
if useParallel
    parfor j = 1:n
        [rows(j), candidateParts{j}, oracleParts{j}, waveParts{j}] = ...
            localRunStatisticalBatchTrial(cfg, occ, preamble, snrDb, ...
            threshold, runId, scenarioName, configHash, preparedTx, ...
            trialIdBeforeBatch, trialIndices(j), j, seedSet, seedOffset, ...
            preamblePresent, trialType, retainFirstWave && j == 1);
    end
else
    for j = 1:n
        [rows(j), candidateParts{j}, oracleParts{j}, waveParts{j}] = ...
            localRunStatisticalBatchTrial(cfg, occ, preamble, snrDb, ...
            threshold, runId, scenarioName, configHash, preparedTx, ...
            trialIdBeforeBatch, trialIndices(j), j, seedSet, seedOffset, ...
            preamblePresent, trialType, retainFirstWave && j == 1);
    end
end
firstWave = complex([]);
if retainFirstWave && ~isempty(waveParts) && ~isempty(waveParts{1})
    firstWave = waveParts{1};
end
end

function [row, candidateRows, oracleRows, retainedWave] = localRunStatisticalBatchTrial( ...
    cfg, occ, preamble, snrDb, threshold, runId, scenarioName, configHash, ...
    preparedTx, trialIdBeforeBatch, trialNumber, batchOrdinal, seedSet, seedOffset, ...
    preamblePresent, trialType, retainWave)
cfgTrial = cfg;
seedBase = seedSet(mod(trialNumber - 1, numel(seedSet)) + 1);
cfgTrial.NoiseSeedOverride = seedBase + seedOffset + trialNumber;
inputTrialId = trialIdBeforeBatch + batchOrdinal - 1;
[~, row, cand, oracle, wave] = localRunOneTrial(inputTrialId, trialType, ...
    cfgTrial, occ, preamble, snrDb, 0, 0, preamblePresent, false, ...
    threshold, runId, scenarioName, configHash, preparedTx);
candidateRows = table2struct(cand);
oracleRows = table2struct(oracle);
if retainWave
    retainedWave = wave;
else
    retainedWave = complex([]);
end
end

function [sweepT, trialT, candT, oracleT] = localMissedDetectionSweep(cfg, occ, preamble, runId, scenarioName, configHash, threshold, trialIdStart, useParallel)
snrs = localVectorOrDefault(sixgr.util.structGet(cfg, "SNRSweep_dB", []), [-24 -12 0 18]);
design = cfg.StatisticalQualification;
seedSet = double(design.DeterministicSeeds(:).');
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "SNRdB",NaN, ...
    "NumTrials",NaN, "NumDetected",NaN, "NumMissed",NaN, "DetectionProbability",NaN, ...
    "MissedDetectionProbability",NaN, "Threshold",NaN, ...
    "TargetMissedDetectionProbability",NaN, "QualificationRequired",false, ...
    "MissedDetectionCILower",NaN, "MissedDetectionCIUpper",NaN, ...
    "DetectionCILower",NaN, "DetectionCIUpper",NaN, "CIWidth",NaN, ...
    "CIWidthTarget",NaN, "ConfidenceLevel",NaN, ...
    "EffectiveDirectionalConfidenceLevel",NaN, "AlphaSpentThisLook",NaN, ...
    "IntervalMethod","", "SequentialDesign","", "LookIndex",NaN, "PlannedLooks",NaN, ...
    "MinimumTrials",NaN, "MaximumTrials",NaN, "MinimumMissedDetectionEvents",NaN, ...
    "PointEstimatePass",false, "StatisticalQualification","NOT_EVALUATED", ...
    "StatisticallyQualified",false, "StoppingReason","", ...
    "DeterministicSeedCount",NaN, "DeterministicSeedSet","", "SeedDerivation","", ...
    "EvidenceUnit","preamble_present_prach_occasion", "Status","NOT_EVALUATED"), numel(snrs), 1);
maxRowBudget = numel(snrs) * max(round(double(design.DetectionMaximumTrials)), ...
    max(1, round(double(cfg.NumTrials))));
trialRows = repmat(localTrialRowTemplate(), maxRowBudget, 1);
candidateTableParts = cell(numel(snrs), 1);
oracleTableParts = cell(numel(snrs), 1);
writeIndex = 0;
trialId = trialIdStart;
preparedTx = sixgr.phy.prach.generatePRACHWaveform(cfg, ...
    "Occasion", occ, "PreambleIndex", preamble);
for iSNR = 1:numel(snrs)
    qualificationRequired = any(abs(double(snrs(iSNR))-double(design.DetectionRequiredSNRdB(:).')) < 1e-9);
    if qualificationRequired
        maximumTrials = round(double(design.DetectionMaximumTrials));
        minimumTrials = round(double(design.DetectionMinimumTrials));
        batchSize = round(double(design.DetectionBatchSizeTrials));
        plannedLooks = round(double(design.DetectionPlannedLooks));
        widthTarget = double(design.DetectionCIWidthTarget);
        minimumEvents = round(double(design.MinimumMissedDetectionEvents));
    else
        % Informational sweep points still publish measured probabilities and
        % confidence intervals.  They must therefore honor the scenario's
        % YAML-authoritative trial count rather than using a hidden three-run
        % plotting shortcut.
        maximumTrials = max(1, round(double(cfg.NumTrials)));
        minimumTrials = maximumTrials;
        batchSize = maximumTrials;
        plannedLooks = 1;
        widthTarget = 1;
        minimumEvents = 0;
    end
    detected = false(maximumTrials, 1);
    missed = false(maximumTrials, 1);
    maximumBatches = ceil(maximumTrials / batchSize);
    pointCandidateTableParts = cell(maximumBatches, 1);
    pointOracleTableParts = cell(maximumBatches, 1);
    pointBatchIndex = 0;
    qualification = localUnevaluatedQualification("no_preamble_present_trials_observed");
    actualTrials = 0;
    lookIndex = 0;
    iTrial = 0;
    while iTrial < maximumTrials
        batchEnd = min(maximumTrials, iTrial + batchSize);
        trialIndices = (iTrial + 1):batchEnd;
        [batchRows, batchCandidates, batchOracles] = localRunStatisticalBatch( ...
            cfg, occ, preamble, snrs(iSNR), threshold, runId, scenarioName, ...
            configHash, preparedTx, trialId, trialIndices, seedSet, ...
            200000*iSNR, true, "missed_detection_sweep", useParallel, false);
        nBatch = numel(trialIndices);
        for j = 1:nBatch
            row = batchRows(j);
            row.StrictOk = false;
            trialNumber = trialIndices(j);
            detected(trialNumber) = ~row.MissedDetection && isfinite(row.PreambleIndexDetected);
            missed(trialNumber) = logical(row.MissedDetection);
            writeIndex = writeIndex + 1;
            trialRows(writeIndex, 1) = row;
        end
        pointBatchIndex = pointBatchIndex + 1;
        pointCandidateTableParts{pointBatchIndex} = sixgr.util.structPartsToTable( ...
            batchCandidates, localCandidateRowTemplate());
        pointOracleTableParts{pointBatchIndex} = sixgr.util.structPartsToTable( ...
            batchOracles, localOracleRowTemplate());
        trialId = trialId + nBatch;
        iTrial = batchEnd;
        actualTrials = iTrial;
        if iTrial >= minimumTrials
            lookIndex = lookIndex + 1;
            qualification = sixgr.stats.evaluateBinomialStopping( ...
                sum(missed(1:iTrial)),iTrial,double(design.DetectionTargetProbability), ...
                "ConfidenceLevel",double(design.ConfidenceLevel), ...
                "MinimumTrials",minimumTrials,"MaximumTrials",maximumTrials, ...
                "MinimumEvents",minimumEvents,"CIWidthTarget",widthTarget, ...
                "LookIndex",lookIndex,"PlannedLooks",plannedLooks, ...
                "FinalLook",iTrial == maximumTrials, ...
                "MetricName","prach_missed_detection_probability");
            localPrintStatisticalProgress("missed_detection", snrs(iSNR), ...
                iTrial, maximumTrials, lookIndex, qualification, cfg, runId);
            if ~qualification.ContinueSampling
                break;
            end
        end
    end
    detectedCount = sum(detected(1:actualTrials));
    missedCount = sum(missed(1:actualTrials));
    statisticalQualification = qualification.Qualification;
    statisticallyQualified = qualification.StatisticallyQualified;
    stoppingReason = qualification.StoppingReason;
    if ~qualificationRequired
        statisticalQualification = "NOT_APPLICABLE";
        statisticallyQualified = false;
        stoppingReason = "informational_snr_not_selected_for_qualification:" + stoppingReason;
    end
    rows(iSNR) = struct("RunId", string(runId), "SweepId", double(iSNR), "ConfigHash", string(configHash), ...
        "SNRdB", double(snrs(iSNR)), "NumTrials", double(actualTrials), "NumDetected", double(detectedCount), ...
        "NumMissed", double(missedCount), "DetectionProbability", double(detectedCount/max(actualTrials,1)), ...
        "MissedDetectionProbability", double(missedCount/max(actualTrials,1)), "Threshold", double(threshold), ...
        "TargetMissedDetectionProbability",double(design.DetectionTargetProbability), ...
        "QualificationRequired",logical(qualificationRequired), ...
        "MissedDetectionCILower",qualification.CILower, ...
        "MissedDetectionCIUpper",qualification.CIUpper, ...
        "DetectionCILower",1-qualification.CIUpper, ...
        "DetectionCIUpper",1-qualification.CILower, ...
        "CIWidth",qualification.CIWidth, "CIWidthTarget",widthTarget, ...
        "ConfidenceLevel",double(design.ConfidenceLevel), ...
        "EffectiveDirectionalConfidenceLevel",qualification.EffectiveDirectionalConfidenceLevel, ...
        "AlphaSpentThisLook",qualification.AlphaSpentThisLook, ...
        "IntervalMethod",qualification.IntervalMethod, "SequentialDesign",qualification.SequentialDesign, ...
        "LookIndex",qualification.LookIndex, "PlannedLooks",double(plannedLooks), ...
        "MinimumTrials",double(minimumTrials), "MaximumTrials",double(maximumTrials), ...
        "MinimumMissedDetectionEvents",double(minimumEvents), ...
        "PointEstimatePass",qualification.PointEstimatePass, ...
        "StatisticalQualification",string(statisticalQualification), ...
        "StatisticallyQualified",logical(statisticallyQualified), ...
        "StoppingReason",string(stoppingReason), ...
        "DeterministicSeedCount",double(numel(seedSet)), ...
        "DeterministicSeedSet",strjoin(string(seedSet),"|"), ...
        "SeedDerivation","configured_seed_plus_snr_and_trial_index", ...
        "EvidenceUnit","preamble_present_prach_occasion", ...
        "Status",string(statisticalQualification));
    candidateTableParts{iSNR} = sixgr.util.tablePartsToTable( ...
        pointCandidateTableParts(1:pointBatchIndex), localCandidateRowTemplate());
    oracleTableParts{iSNR} = sixgr.util.tablePartsToTable( ...
        pointOracleTableParts(1:pointBatchIndex), localOracleRowTemplate());
end
trialRows = trialRows(1:writeIndex);
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = sixgr.util.tablePartsToTable(candidateTableParts, localCandidateRowTemplate());
oracleT = sixgr.util.tablePartsToTable(oracleTableParts, localOracleRowTemplate());
end

function [sweepT, trialT, candT, oracleT, noiseWaveform] = localFalseAlarmSweep(cfg, occ, runId, scenarioName, configHash, threshold, trialIdStart, useParallel)
snrs = localVectorOrDefault(sixgr.util.structGet(cfg, "SNRSweep_dB", []), [-24 -12 0 18]);
design = cfg.StatisticalQualification;
maximumTrials = round(double(design.MaximumTrials));
batchSize = round(double(design.BatchSizeTrials));
seedSet = double(design.DeterministicSeeds(:).');
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "SNRdB",NaN, ...
    "NumTrials",NaN, "NumFalseAlarms",NaN, "FalseAlarmProbability",NaN, ...
    "Threshold",NaN, "TargetFalseAlarmProbability",NaN, ...
    "CILower",NaN, "CIUpper",NaN, "CIWidth",NaN, "CIWidthTarget",NaN, ...
    "ConfidenceLevel",NaN, "EffectiveDirectionalConfidenceLevel",NaN, ...
    "AlphaSpentThisLook",NaN, "IntervalMethod","", "SequentialDesign","", ...
    "LookIndex",NaN, "PlannedLooks",NaN, "MinimumTrials",NaN, "MaximumTrials",NaN, ...
    "MinimumFalseAlarmEvents",NaN, "PointEstimatePass",false, ...
    "StatisticalQualification","NOT_EVALUATED", "StatisticallyQualified",false, ...
    "StoppingReason","", "DeterministicSeedCount",NaN, "DeterministicSeedSet","", ...
    "SeedDerivation","", "EvidenceUnit","no_signal_prach_occasion", ...
    "Status","NOT_EVALUATED"), numel(snrs), 1);
maxRowBudget = numel(snrs) * maximumTrials;
trialRows = repmat(localTrialRowTemplate(), maxRowBudget, 1);
candidateTableParts = cell(numel(snrs), 1);
oracleTableParts = cell(numel(snrs), 1);
writeIndex = 0;
trialId = trialIdStart;
noiseWaveform = complex([]);
preparedTx = sixgr.phy.prach.generatePRACHWaveform(cfg, ...
    "Occasion", occ, "PreambleIndex", localFirstPreamble(cfg));
for iSNR = 1:numel(snrs)
    falseAlarm = false(maximumTrials, 1);
    maximumBatches = ceil(maximumTrials / batchSize);
    pointCandidateTableParts = cell(maximumBatches, 1);
    pointOracleTableParts = cell(maximumBatches, 1);
    pointBatchIndex = 0;
    qualification = localUnevaluatedQualification("no_noise_only_trials_observed");
    lookIndex = 0;
    actualTrials = 0;
    iTrial = 0;
    while iTrial < maximumTrials
        batchEnd = min(maximumTrials, iTrial + batchSize);
        trialIndices = (iTrial + 1):batchEnd;
        [batchRows, batchCandidates, batchOracles, batchFirstWave] = localRunStatisticalBatch( ...
            cfg, occ, localFirstPreamble(cfg), snrs(iSNR), threshold, runId, scenarioName, ...
            configHash, preparedTx, trialId, trialIndices, seedSet, ...
            100000*iSNR, false, "false_alarm_sweep", useParallel, isempty(noiseWaveform));
        nBatch = numel(trialIndices);
        for j = 1:nBatch
            row = batchRows(j);
            row.StrictOk = false;
            trialNumber = trialIndices(j);
            falseAlarm(trialNumber) = logical(row.FalseAlarm);
            writeIndex = writeIndex + 1;
            trialRows(writeIndex, 1) = row;
        end
        pointBatchIndex = pointBatchIndex + 1;
        pointCandidateTableParts{pointBatchIndex} = sixgr.util.structPartsToTable( ...
            batchCandidates, localCandidateRowTemplate());
        pointOracleTableParts{pointBatchIndex} = sixgr.util.structPartsToTable( ...
            batchOracles, localOracleRowTemplate());
        if isempty(noiseWaveform) && ~isempty(batchFirstWave)
            noiseWaveform = batchFirstWave;
        end
        trialId = trialId + nBatch;
        iTrial = batchEnd;
        actualTrials = iTrial;
        if iTrial >= round(double(design.MinimumTrials))
            lookIndex = lookIndex + 1;
            qualification = sixgr.stats.evaluateBinomialStopping( ...
                sum(falseAlarm(1:iTrial)),iTrial,double(design.TargetProbability), ...
                "ConfidenceLevel",double(design.ConfidenceLevel), ...
                "MinimumTrials",round(double(design.MinimumTrials)), ...
                "MaximumTrials",maximumTrials, ...
                "MinimumEvents",round(double(design.MinimumFalseAlarmEvents)), ...
                "CIWidthTarget",double(design.CIWidthTarget), ...
                "LookIndex",lookIndex,"PlannedLooks",round(double(design.PlannedLooks)), ...
                "FinalLook",iTrial == maximumTrials, ...
                "MetricName","prach_false_alarm_probability");
            localPrintStatisticalProgress("false_alarm", snrs(iSNR), ...
                iTrial, maximumTrials, lookIndex, qualification, cfg, runId);
            if ~qualification.ContinueSampling
                break;
            end
        end
    end
    eventCount = sum(falseAlarm(1:actualTrials));
    rows(iSNR) = struct("RunId", string(runId), "SweepId", double(iSNR), "ConfigHash", string(configHash), ...
        "SNRdB", double(snrs(iSNR)), "NumTrials", double(actualTrials), "NumFalseAlarms", double(eventCount), ...
        "FalseAlarmProbability", double(eventCount/max(actualTrials,1)), "Threshold", double(threshold), ...
        "TargetFalseAlarmProbability", double(design.TargetProbability), ...
        "CILower",qualification.CILower, "CIUpper",qualification.CIUpper, ...
        "CIWidth",qualification.CIWidth, "CIWidthTarget",double(design.CIWidthTarget), ...
        "ConfidenceLevel",double(design.ConfidenceLevel), ...
        "EffectiveDirectionalConfidenceLevel",qualification.EffectiveDirectionalConfidenceLevel, ...
        "AlphaSpentThisLook",qualification.AlphaSpentThisLook, ...
        "IntervalMethod",qualification.IntervalMethod, "SequentialDesign",qualification.SequentialDesign, ...
        "LookIndex",qualification.LookIndex, "PlannedLooks",double(design.PlannedLooks), ...
        "MinimumTrials",double(design.MinimumTrials), "MaximumTrials",double(design.MaximumTrials), ...
        "MinimumFalseAlarmEvents",double(design.MinimumFalseAlarmEvents), ...
        "PointEstimatePass",qualification.PointEstimatePass, ...
        "StatisticalQualification",qualification.Qualification, ...
        "StatisticallyQualified",qualification.StatisticallyQualified, ...
        "StoppingReason",qualification.StoppingReason, ...
        "DeterministicSeedCount",double(numel(seedSet)), ...
        "DeterministicSeedSet",strjoin(string(seedSet),"|"), ...
        "SeedDerivation","configured_seed_plus_snr_and_trial_index", ...
        "EvidenceUnit","no_signal_prach_occasion", "Status",qualification.Qualification);
    candidateTableParts{iSNR} = sixgr.util.tablePartsToTable( ...
        pointCandidateTableParts(1:pointBatchIndex), localCandidateRowTemplate());
    oracleTableParts{iSNR} = sixgr.util.tablePartsToTable( ...
        pointOracleTableParts(1:pointBatchIndex), localOracleRowTemplate());
end
trialRows = trialRows(1:writeIndex);
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = sixgr.util.tablePartsToTable(candidateTableParts, localCandidateRowTemplate());
oracleT = sixgr.util.tablePartsToTable(oracleTableParts, localOracleRowTemplate());
end

function [sweepT, trialT, candT, oracleT] = localTimingOffsetSweep(cfg, occ, preamble, runId, scenarioName, configHash, threshold, trialIdStart, highSNR)
offsets = localVectorOrDefault(sixgr.util.structGet(cfg, "TimingOffsetSweepSamples", []), [0 4 8]);
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "InjectedTimingOffsetSamples",NaN, ...
    "MeanEstimatedTimingOffsetSamples",NaN, "MeanTimingErrorSamples",NaN, "MaxAbsTimingErrorSamples",NaN, ...
    "NumTrials",NaN, "NumWithinTolerance",NaN, "WithinToleranceProbability",NaN, "Status",""), numel(offsets), 1);
trialRows = repmat(localTrialRowTemplate(), 0, 1);
candRows = repmat(localCandidateRowTemplate(), 0, 1);
oracleRows = repmat(localOracleRowTemplate(), 0, 1);
trialId = trialIdStart;
for ii = 1:numel(offsets)
    [trialId, row, cand, oracle] = localRunOneTrial(trialId, "timing_offset_sweep", cfg, occ, ...
        preamble, highSNR, offsets(ii), 0, true, false, threshold, runId, scenarioName, configHash);
    row.StrictOk = false;
    trialRows(end + 1, 1) = row; %#ok<AGROW>
    candRows = [candRows; table2struct(cand)]; %#ok<AGROW>
    oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
    toleranceSamples = localStrictTimingToleranceSamples(cfg);
    within = isfinite(row.TimingErrorSamples) && abs(row.TimingErrorSamples) <= toleranceSamples;
    rows(ii) = struct("RunId", string(runId), "SweepId", double(ii), "ConfigHash", string(configHash), ...
        "InjectedTimingOffsetSamples", double(offsets(ii)), ...
        "MeanEstimatedTimingOffsetSamples", double(row.EstimatedTimingOffsetSamples), ...
        "MeanTimingErrorSamples", double(row.TimingErrorSamples), ...
        "MaxAbsTimingErrorSamples", abs(double(row.TimingErrorSamples)), ...
        "NumTrials", 1, "NumWithinTolerance", double(within), ...
        "WithinToleranceProbability", double(within), "Status", "measured");
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
end

function T = localFrequencyOffsetSweep(cfg, occ, preamble, runId, configHash, threshold, highSNR)
offsets = localVectorOrDefault(sixgr.util.structGet(cfg, "FrequencyOffsetSweepHz", []), [0 250]);
sets = ["UnrestrictedSet", "RestrictedSetTypeA", "RestrictedSetTypeB"];
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "RestrictedSet","", ...
    "InjectedFrequencyOffsetHz",NaN, "SNRdB",NaN, "NumTrials",NaN, "DetectionProbability",NaN, ...
    "MeanDetectionMetric",NaN, "MeanTimingErrorSamples",NaN, "Status",""), numel(offsets) * numel(sets), 1);
idx = 0;
for iSet = 1:numel(sets)
    cfgSet = cfg;
    status = "measured";
    try
        cfgSet.RestrictedSet = char(sets(iSet));
        cfgSet.ToolboxPRACH.RestrictedSet = char(sets(iSet));
        sixgr.phy.prach.deriveNCSFromZeroCorrelationZone(cfgSet.ZeroCorrelationZone, cfgSet.RestrictedSet, cfgSet.ToolboxPRACH.LRA);
    catch ME
        status = "unsupported_config_strict_failure:" + string(ME.identifier);
    end
    for iOffset = 1:numel(offsets)
        idx = idx + 1;
        metric = NaN;
        detected = false;
        timingError = NaN;
        if status == "measured"
            [~, row] = localRunOneTrial(0, "frequency_offset_sweep", cfgSet, occ, ...
                preamble, highSNR, 0, offsets(iOffset), true, false, threshold, runId, "prach_frequency_sweep", configHash);
            metric = row.DetectionMetric;
            detected = isfinite(row.PreambleIndexDetected) && ~row.MissedDetection;
            timingError = row.TimingErrorSamples;
        end
        rows(idx) = struct("RunId", string(runId), "SweepId", double(idx), "ConfigHash", string(configHash), ...
            "RestrictedSet", sets(iSet), "InjectedFrequencyOffsetHz", double(offsets(iOffset)), ...
            "SNRdB", double(highSNR), "NumTrials", 1, "DetectionProbability", double(detected), ...
            "MeanDetectionMetric", double(metric), "MeanTimingErrorSamples", double(timingError), ...
            "Status", string(status));
    end
end
T = struct2table(rows, "AsArray", true);
end

function [T, candT] = localCollisionTrials(cfg, occ, preamble, runId, scenarioName, configHash, threshold, highSNR)
tx1 = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
tx2 = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", mod(preamble + 1, 64));
cases = [
    struct("SamePreamble", true, "Waveform", tx1.Waveform + tx1.Waveform, "Preambles", [preamble preamble])
    struct("SamePreamble", false, "Waveform", tx1.Waveform + tx2.Waveform, "Preambles", [preamble mod(preamble + 1, 64)])];
rows = repmat(struct("RunId","", "CollisionGroupId",NaN, "TrialId",NaN, "UEId",NaN, ...
    "PreambleIndexTx",NaN, "PreambleIndexDetected",NaN, "SamePreamble",false, "SameOccasion",true, ...
    "CollisionInjected",true, "CollisionDetected",false, "MultiplePreamblesDetected",false, ...
    "DetectedCandidateCount",NaN, "Outcome","", "Status",""), numel(cases) * 2, 1);
candRows = repmat(localCandidateRowTemplate(), 0, 1);
idx = 0;
for iCase = 1:numel(cases)
    [caseWaveform, ~] = localApplyStrictChannel(cases(iCase).Waveform, cfg, 700 + iCase);
    [rx, ~] = localAddNoise(caseWaveform, highSNR, 700 + iCase);
    det = sixgr.phy.prach.detectPRACHWaveform(rx, cfg, "Occasion", occ, ...
        "CandidatePreambles", 0:(min(64, cfg.NumPreambles) - 1), ...
        "DetectionThreshold", threshold, "DetectorBackend", "toolbox_peak");
    cand = localCandidateTable(runId, 9000 + iCase, cfg, occ, det, 0);
    candRows = [candRows; table2struct(cand)]; %#ok<AGROW>
    detectedCandidateCount = localCollisionCandidateCount(det);
    for iUE = 1:2
        idx = idx + 1;
        rows(idx) = struct("RunId", string(runId), "CollisionGroupId", double(iCase), ...
            "TrialId", double(9000 + iCase), "UEId", double(iUE), ...
            "PreambleIndexTx", double(cases(iCase).Preambles(iUE)), ...
            "PreambleIndexDetected", double(sixgr.util.structGet(det, "DetectedPreambleIndex", NaN)), ...
            "SamePreamble", logical(cases(iCase).SamePreamble), "SameOccasion", true, ...
            "CollisionInjected", true, "CollisionDetected", true, ...
            "MultiplePreamblesDetected", logical(detectedCandidateCount > 1), ...
            "DetectedCandidateCount", double(detectedCandidateCount), ...
            "Outcome", string(ternary(cases(iCase).SamePreamble, "same_preamble_collision", "different_preamble_multi_peak")), ...
            "Status", "measured");
    end
end
T = struct2table(rows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
end

function count = localCollisionCandidateCount(det)
peaks = double(sixgr.util.structGet(det, "CorrelationPeaks", []));
peaks = peaks(isfinite(peaks));
if isempty(peaks)
    count = 0;
    return;
end
primary = max(peaks, [], "omitnan");
singleThreshold = double(sixgr.util.structGet(det, "Threshold", NaN));
relativeThreshold = 0.95 * double(primary);
noiseGuard = 0.25 * double(singleThreshold);
if ~(isfinite(noiseGuard) && noiseGuard >= 0)
    noiseGuard = 0;
end
candidateMask = peaks >= relativeThreshold & peaks >= noiseGuard;
count = double(sum(candidateMask));
end

function T = localMultiOccasionTrials(cfg, preamble, runId, scenarioName, configHash, threshold, highSNR) %#ok<INUSD>
numOcc = min(2, max(1, round(double(cfg.NumPRACHOccasions))));
rows = repmat(struct("RunId","", "TrialId",NaN, "ConfigHash","", "OccasionFrame",NaN, ...
    "OccasionSlot",NaN, "OccasionSymbol",NaN, "OccasionFrequencyIndex",NaN, ...
    "PreambleIndexTx",NaN, "PreambleIndexDetected",NaN, "RARNTI",NaN, ...
    "DetectedOnCorrectOccasion",false, "Status",""), numOcc, 1);
for iOcc = 1:numOcc
    occ = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", iOcc);
    [~, row] = localRunOneTrial(8000 + iOcc, "multi_occasion", cfg, occ, ...
        preamble, highSNR, 0, 0, true, false, threshold, runId, scenarioName, configHash);
    rows(iOcc) = struct("RunId", string(runId), "TrialId", double(8000 + iOcc + 1), ...
        "ConfigHash", string(configHash), "OccasionFrame", double(row.OccasionFrame), "OccasionSlot", double(row.OccasionSlot), ...
        "OccasionSymbol", double(row.OccasionSymbol), "OccasionFrequencyIndex", double(row.OccasionFrequencyIndex), ...
        "PreambleIndexTx", double(preamble), "PreambleIndexDetected", double(row.PreambleIndexDetected), ...
        "RARNTI", double(row.RARNTI), "DetectedOnCorrectOccasion", logical(row.PreambleIndexMatch), ...
        "Status", "measured");
end
T = struct2table(rows, "AsArray", true);
end

function [negT, trialT, candT, oracleT] = localNegativeWrongConfigTrial(cfg, occ, preamble, runId, scenarioName, configHash, threshold, trialId, highSNR)
tx = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
[waveform, channelInfo] = localApplyStrictChannel(tx.Waveform, cfg, 4401);
trueTimingOffsetSamples = double(sixgr.util.structGet(channelInfo, "ChannelFilterDelay", 0));
[rx, ~] = localAddNoise(waveform, highSNR, 4401);
badCfg = cfg;
badCfg.SequenceIndex = mod(double(cfg.SequenceIndex) + 13, 838);
badCfg.ToolboxPRACH.SequenceIndex = double(badCfg.SequenceIndex);
det = sixgr.phy.prach.detectPRACHWaveform(rx, badCfg, "Occasion", occ, ...
    "CandidatePreambles", 0:(min(64, cfg.NumPreambles) - 1), ...
    "DetectionThreshold", threshold, "DetectorBackend", "toolbox_peak");
txMeta = struct("PreambleIndexTx", double(preamble), "InjectedTimingOffsetSamples", trueTimingOffsetSamples, "PreamblePresent", true);
score = sixgr.phy.prach.scorePRACHDetection(det, txMeta, badCfg, "TrialType", "negative_wrong_root");
row = localTrialRowFromDetection(runId, scenarioName, trialId, "negative_wrong_root", badCfg, occ, tx, det, score, ...
    highSNR, trueTimingOffsetSamples, 0, false, configHash);
row.StrictOk = false;
row.NegativeExpectedOk = ~logical(score.StrictOk);
row.Status = string(ternary(row.NegativeExpectedOk, "PASS", "FAIL"));
row.FailureReason = "wrong_root_sequence_rejected_or_not_strict_positive";
trialT = struct2table(row, "AsArray", true);
candT = localCandidateTable(runId, trialId, badCfg, occ, det, 0);
oracleT = localOracleGuardTable(runId, trialId);
negT = table(string(runId), "wrong_root_sequence", "receiver_sequence_index_shifted", ...
    "receiver_correlation", string(row.FailureReason), logical(row.FalseAlarm), logical(row.MissedDetection), ...
    logical(row.StrictOk), logical(row.NegativeExpectedOk), string(row.FailureReason), ...
    'VariableNames', {'RunId','NegativeTrialType','InjectedFault','ExpectedFailureStage', ...
    'ObservedFailureStage','FalseAlarm','MissedDetection','StrictOk','NegativeExpectedOk','FailureReason'});
end

function [rx, noiseVar] = localAddNoise(waveform, snrDb, seed)
rng(double(seed), "twister");
signalPower = mean(abs(waveform(:)).^2, "omitnan");
if ~(isfinite(signalPower) && signalPower > 0)
    signalPower = 1;
end
noiseVar = signalPower / max(10^(double(snrDb) / 10), eps);
noise = sqrt(noiseVar / 2) .* (randn(size(waveform)) + 1i .* randn(size(waveform)));
rx = waveform + noise;
end

function [rxWaveform, channelInfo] = localApplyStrictChannel(waveform, cfg, seed)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "ChannelModel", "AWGN"))));
channelInfo = struct("ChannelFilterDelay", 0, "ChannelModelApplied", model);
switch model
    case {"", "AWGN", "NONE", "OFF"}
        rxWaveform = waveform;
    case {"TDL-A","TDL-B","TDL-C","TDL-D","TDL-E"}
        chan = nrTDLChannel;
        chan.DelayProfile = char(model);
        chan.DelaySpread = double(sixgr.util.structGet(cfg, "DelaySpread_ns", 30)) * 1e-9;
        chan.MaximumDopplerShift = localSpeedToDoppler(cfg);
        chan.SampleRate = double(sixgr.util.structGet(cfg, "SampleRate_Hz", 1));
        chan.NumTransmitAntennas = size(waveform, 2);
        chan.NumReceiveAntennas = round(double(sixgr.util.structGet(cfg, "NumRxAntennas", 1)));
        chan.Seed = double(seed);
        channelInfo = localChannelInfo(chan, model);
        rxWaveform = chan(waveform);
    case {"CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"}
        chan = nrCDLChannel;
        chan.DelayProfile = char(model);
        chan.DelaySpread = double(sixgr.util.structGet(cfg, "DelaySpread_ns", 30)) * 1e-9;
        chan.MaximumDopplerShift = localSpeedToDoppler(cfg);
        chan.SampleRate = double(sixgr.util.structGet(cfg, "SampleRate_Hz", 1));
        chan.Seed = double(seed);
        chan.ReceiveAntennaArray.Size = [round(double(sixgr.util.structGet(cfg, "NumRxAntennas", 1))) 1 1 1 1];
        chan.TransmitAntennaArray.Size = [size(waveform, 2) 1 1 1 1];
        channelInfo = localChannelInfo(chan, model);
        rxWaveform = chan(waveform);
    otherwise
        error("sixgr:phy:prach:UnsupportedStrictChannel", ...
            "Strict PRACH validation requires AWGN or a concrete TDL/CDL profile. Got '%s'.", model);
end
end

function channelInfo = localChannelInfo(chan, model)
try
    channelInfo = info(chan);
catch
    channelInfo = struct();
end
channelInfo.ChannelModelApplied = model;
if ~isfield(channelInfo, "ChannelFilterDelay")
    channelInfo.ChannelFilterDelay = 0;
end
end

function fd = localSpeedToDoppler(cfg)
speedKmh = double(sixgr.util.structGet(cfg, "Speed_kmh", 0));
fcHz = double(sixgr.util.structGet(cfg, "CarrierFrequencyHz", 0));
if ~(isfinite(speedKmh) && speedKmh >= 0 && isfinite(fcHz) && fcHz > 0)
    fd = 0;
else
    fd = (speedKmh / 3.6) * fcHz / 299792458;
end
end

function tol = localStrictTimingToleranceSamples(cfg)
tolUs = double(sixgr.util.structGet(cfg, "TimingTolerance_us", NaN));
sampleRateHz = double(sixgr.util.structGet(cfg, "SampleRate_Hz", NaN));
if isfinite(tolUs) && tolUs >= 0 && isfinite(sampleRateHz) && sampleRateHz > 0
    tol = tolUs * sampleRateHz / 1e6;
else
    tol = NaN;
end
if ~(isfinite(tol) && tol >= 0)
    tol = 1.5;
end
tol = max(1.5, double(tol));
end

function wave = localNoiseOnly(sz, noiseVar, seed)
rng(double(seed), "twister");
wave = sqrt(double(noiseVar) / 2) .* (randn(sz) + 1i .* randn(sz));
end

function wave = localApplyIntegerDelay(wave, delaySamples)
delaySamples = round(double(delaySamples));
if delaySamples > 0
    wave = [complex(zeros(delaySamples, size(wave, 2))); wave(1:end-delaySamples, :)];
elseif delaySamples < 0
    d = abs(delaySamples);
    wave = [wave(d+1:end, :); complex(zeros(d, size(wave, 2)))];
end
end

function wave = localApplyFrequencyOffset(wave, freqOffsetHz, sampleRateHz)
freqOffsetHz = double(freqOffsetHz);
if abs(freqOffsetHz) < eps
    return;
end
n = (0:size(wave, 1)-1).';
rot = exp(1i * 2 * pi * freqOffsetHz .* n ./ max(double(sampleRateHz), eps));
wave = wave .* rot;
end

function values = localVectorOrDefault(raw, defaultValue)
values = double(raw);
values = values(:).';
values = values(isfinite(values));
if isempty(values)
    values = double(defaultValue);
end
end

function preamble = localFirstPreamble(cfg)
p = double(cfg.PreambleIndex(:));
p = p(isfinite(p));
if isempty(p)
    preamble = 0;
else
    preamble = p(1);
end
end

function txt = localSequenceLength(lra)
if round(double(lra)) == 839
    txt = "long";
else
    txt = "short";
end
end

function s = localToolboxCapabilities()
s = struct();
s.MATLABVersion = version;
v = ver("5g");
if isempty(v)
    s.ToolboxVersion = "";
else
    s.ToolboxVersion = string(v(1).Version);
end
s.nrPRACHConfigAvailable = ~isempty(which("nrPRACHConfig"));
s.nrPRACHAvailable = ~isempty(which("nrPRACH"));
s.nrPRACHIndicesAvailable = ~isempty(which("nrPRACHIndices"));
s.nrPRACHDetectAvailable = ~isempty(which("nrPRACHDetect"));
s.StrictModeToolboxFallbackAllowed = false;
s.GeneratedAt = sixgr.util.utcNowISO8601();
s.ProducerModule = "sixgr.phy.prach.runStrictPRACHValidation";
end

function summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, missedT, falseAlarmT, timingT, freqT, collisionT, multiT, negT, oracleT)
summary = struct();
summary.RunId = string(runId);
summary.scenario = string(scenarioName);
summary.timestamp = sixgr.util.utcNowISO8601();
summary.implementation_status = "strict_prach_waveform_validation";
summary.ProducerModule = "sixgr.phy.prach.runStrictPRACHValidation";
summary.StrictOk = logical(strictOk);
summary.ConfigHash = string(cfg.ConfigHash);
summary.PositiveTrialCount = sum(string(trialT.TrialType) == "positive_high_snr");
summary.PositiveStrictOkCount = sum(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_high_snr");
summary.MissedDetectionSweepRows = height(missedT);
summary.FalseAlarmSweepRows = height(falseAlarmT);
summary.FalseAlarmStatisticallyQualified = ~isempty(falseAlarmT) && ...
    all(logical(falseAlarmT.StatisticallyQualified));
requiredDetection = logical(missedT.QualificationRequired);
summary.RequiredDetectionOperatingPointCount = sum(requiredDetection);
summary.MissedDetectionStatisticallyQualified = any(requiredDetection) && ...
    all(logical(missedT.StatisticallyQualified(requiredDetection))) && ...
    all(string(missedT.StatisticalQualification(requiredDetection)) == "PASS");
summary.StatisticallyQualified = summary.FalseAlarmStatisticallyQualified && ...
    summary.MissedDetectionStatisticallyQualified;
if summary.StatisticallyQualified
    summary.StatisticalQualification = "PASS";
elseif any(string(falseAlarmT.StatisticalQualification) == "FAIL") || ...
        any(string(missedT.StatisticalQualification(requiredDetection)) == "FAIL")
    summary.StatisticalQualification = "FAIL";
else
    summary.StatisticalQualification = "NOT_EVALUATED";
end

summary.TimingOffsetSweepRows = height(timingT);
summary.FrequencyOffsetSweepRows = height(freqT);
summary.CollisionRows = height(collisionT);
summary.MultiOccasionRows = height(multiT);
summary.NegativeRows = height(negT);
summary.OracleGuardRows = height(oracleT);
summary.OracleGuardViolationCount = sum(logical(oracleT.Violation));
end

function [pool, evidence] = localResolveParallelExecution(cfg)
pool = [];
requested = max(1, round(double(sixgr.util.structGet(cfg, ...
    "ParallelRequestedWorkers", 1))));
enabled = logical(sixgr.util.structGet(cfg, "UseParallel", false)) && requested > 1;
evidence = struct("Requested", enabled, "RequestedWorkers", requested, ...
    "Active", false, "EffectiveWorkers", 1, "PoolType", "serial", ...
    "Status", "parallel_not_requested", "FailureReason", "", ...
    "Authority", string(sixgr.util.structGet(cfg, ...
    "ParallelExecutionAuthority", "resolved_scenario_run_control")));
if ~enabled
    return;
end
if ~(license("test", "Distrib_Computing_Toolbox") && exist("parpool", "file") == 2)
    evidence.Status = "parallel_toolbox_or_license_unavailable_exact_serial_execution";
    return;
end
try
    pool = gcp("nocreate");
    if isempty(pool)
        pool = parpool("Processes", requested);
    end
    evidence.Active = true;
    evidence.EffectiveWorkers = double(pool.NumWorkers);
    evidence.PoolType = string(class(pool));
    evidence.Status = "parallel_process_pool_active";
catch cause
    pool = [];
    evidence.Status = "parallel_start_failed_exact_serial_execution";
    evidence.FailureReason = string(cause.identifier) + " | " + string(cause.message);
end
fprintf(1, "PRACH_PARALLEL requested=%d requested_workers=%d active=%d effective_workers=%d status=%s\n", ...
    evidence.Requested, evidence.RequestedWorkers, evidence.Active, ...
    evidence.EffectiveWorkers, char(evidence.Status));
end

function q = localUnevaluatedQualification(reason)
q = struct("CILower",NaN,"CIUpper",NaN,"CIWidth",NaN, ...
    "EffectiveDirectionalConfidenceLevel",NaN,"AlphaSpentThisLook",0, ...
    "IntervalMethod","CLOPPER_PEARSON_EXACT_ONE_SIDED_BOUNDS", ...
    "SequentialDesign","planned_look_bonferroni_two_direction", ...
    "LookIndex",0,"PointEstimatePass",false, ...
    "Qualification","NOT_EVALUATED","StatisticallyQualified",false, ...
    "ContinueSampling",false,"StoppingReason",string(reason));
end

function y = ternary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
