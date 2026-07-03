function result = runStrictPRACHValidation(baseCfg, varargin)
%RUNSTRICTPRACHVALIDATION Execute strict, waveform-backed PRACH validation.

p = inputParser;
p.FunctionName = "sixgr.phy.prach.runStrictPRACHValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "prach_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "prach_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

runFolder = char(string(opt.RunFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);
cfg = sixgr.phy.prach.buildPRACHConfigFromScenario(baseCfg, ...
    "RunFolder", runFolder, "ScenarioName", scenarioName);
configHash = string(cfg.ConfigHash);

localMarkStrictProgress(runId, "strict_prach_config_validation", 0.02, ...
    "Validating strict PRACH configuration and root-sequence evidence.");
mappingT = sixgr.phy.prach.validateRestrictedSetMapping(runId, configHash, cfg);
rootBudgetT = sixgr.phy.prach.validateRootSequenceBudget(runId, configHash, cfg);
zczT = sixgr.phy.prach.deriveCyclicShiftSet(runId, configHash, cfg);
configT = localConfigTable(runId, scenarioName, cfg);
toolboxCapabilities = localToolboxCapabilities();

trialRows = repmat(localTrialRowTemplate(), 0, 1);
candidateRows = repmat(localCandidateRowTemplate(), 0, 1);
oracleRows = repmat(localOracleRowTemplate(), 0, 1);
negativeRows = repmat(localNegativeRowTemplate(), 0, 1);

trialId = 0;
occ1 = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
preamble = localFirstPreamble(cfg);
highSNR = max(30, double(sixgr.util.structGet(baseCfg, "simulation.snr_db", 30)));
threshold = double(cfg.DetectionThreshold);

localMarkStrictProgress(runId, "strict_prach_positive_high_snr", 0.08, ...
    "Running positive high-SNR PRACH receive validation.");
[trialId, pos, cand, oracle, positiveWaveform] = localRunOneTrial( ...
    trialId, "positive_high_snr", cfg, occ1, preamble, highSNR, 0, 0, ...
    true, false, threshold, runId, scenarioName, configHash);
trialRows(end + 1, 1) = pos; %#ok<AGROW>
candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_missed_detection_sweep", 0.18, ...
    "Running PRACH missed-detection SNR sweep.");
[missedT, missTrials, missCand, missOracle] = localMissedDetectionSweep( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId);
trialId = trialId + height(missTrials);
trialRows = [trialRows; table2struct(missTrials)]; %#ok<AGROW>
candidateRows = [candidateRows; table2struct(missCand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(missOracle)]; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_false_alarm_sweep", 0.36, ...
    "Running PRACH false-alarm noise-only sweep.");
[falseAlarmT, falseTrials, falseCand, falseOracle, noiseWaveform] = localFalseAlarmSweep( ...
    cfg, occ1, runId, scenarioName, configHash, threshold, trialId);
trialId = trialId + height(falseTrials);
trialRows = [trialRows; table2struct(falseTrials)]; %#ok<AGROW>
candidateRows = [candidateRows; table2struct(falseCand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(falseOracle)]; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_timing_offset_sweep", 0.54, ...
    "Running PRACH timing-offset sweep.");
[timingT, timingTrials, timingCand, timingOracle] = localTimingOffsetSweep( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId, highSNR);
trialId = trialId + height(timingTrials);
trialRows = [trialRows; table2struct(timingTrials)]; %#ok<AGROW>
candidateRows = [candidateRows; table2struct(timingCand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(timingOracle)]; %#ok<AGROW>

localMarkStrictProgress(runId, "strict_prach_frequency_offset_sweep", 0.66, ...
    "Running PRACH frequency-offset and restricted-set sweep.");
freqT = localFrequencyOffsetSweep(cfg, occ1, preamble, runId, configHash, threshold, highSNR);
localMarkStrictProgress(runId, "strict_prach_collision_trials", 0.78, ...
    "Running PRACH collision and multi-preamble trials.");
[collisionT, collisionCandidates] = localCollisionTrials(cfg, occ1, preamble, runId, scenarioName, configHash, threshold, highSNR);
candidateRows = [candidateRows; table2struct(collisionCandidates)]; %#ok<AGROW>
localMarkStrictProgress(runId, "strict_prach_multi_occasion_trials", 0.86, ...
    "Running PRACH multi-occasion RARNTI trials.");
multiOccasionT = localMultiOccasionTrials(cfg, preamble, runId, scenarioName, configHash, threshold, highSNR);
localMarkStrictProgress(runId, "strict_prach_negative_wrong_config", 0.92, ...
    "Running PRACH negative wrong-root receiver guard.");
[negativeT, negTrial, negCand, negOracle] = localNegativeWrongConfigTrial( ...
    cfg, occ1, preamble, runId, scenarioName, configHash, threshold, trialId + 1, highSNR);
trialRows = [trialRows; table2struct(negTrial)]; %#ok<AGROW>
candidateRows = [candidateRows; table2struct(negCand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(negOracle)]; %#ok<AGROW>
negativeRows = [negativeRows; table2struct(negativeT)]; %#ok<AGROW>

trialT = struct2table(trialRows, "AsArray", true);
candidateT = struct2table(candidateRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
negativeTrialT = struct2table(negativeRows, "AsArray", true);

strictPositiveOk = any(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_high_snr");
artifactRowsOk = height(mappingT) > 0 && height(rootBudgetT) > 0 && height(zczT) > 0 && ...
    height(missedT) > 0 && height(falseAlarmT) > 0 && height(timingT) > 0 && ...
    height(freqT) > 0 && height(collisionT) > 0 && height(multiOccasionT) > 0 && ...
    height(negativeTrialT) > 0 && height(oracleT) > 0;
oracleOk = ~any(logical(oracleT.Violation));
configOk = logical(cfg.StrictValidation.StrictValid) && all(logical(rootBudgetT.BudgetOk));
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
missedEvidenceOk = all(double(missedT.NumMissed) == 0) && any(double(missedT.NumDetected) > 0) && ...
    all(double(missedT.DetectionProbability) >= 0 & double(missedT.DetectionProbability) <= 1);
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
result.FailureReason = string(ternary(strictOk, "", "strict_prach_validation_failed"));
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ToolboxCapabilities = toolboxCapabilities;
result.DetectionSummary = summary;
result.PositiveWaveform = positiveWaveform;
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
T = table( ...
    string(runId), string(scenarioName), double(cfg.NCellID), string(cfg.ConfigHash), ...
    string(cfg.BindingSource), string(cfg.FrequencyRange), string(cfg.DuplexMode), ...
    double(cfg.CarrierFrequencyHz), double(cfg.NCellID), double(cfg.NSizeGrid), ...
    double(cfg.CarrierSCSkHz), double(cfg.PRACHSubcarrierSpacing), ...
    double(cfg.PRACHConfigurationIndex), string(cfg.ResolvedPRACHFormat), ...
    string(localSequenceLength(cfg.ToolboxPRACH.LRA)), double(cfg.SequenceIndex), ...
    double(cfg.LogicalRootSequenceIndex), double(cfg.ZeroCorrelationZone), ...
    string(cfg.RestrictedSet), double(cfg.NumPreambles), 1, double(cfg.FrequencyStart), ...
    0, double(occ.SlotIndex0), double(occ.SymbolLocation), 0, ...
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
    preamblePresent, collisionInjected, threshold, runId, scenarioName, configHash)
nextTrialId = trialId + 1;
if preamblePresent
    tx = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
    waveform = tx.Waveform;
else
    ref = sixgr.phy.prach.generatePRACHWaveform(cfg, "Occasion", occ, "PreambleIndex", preamble);
    tx = ref;
    waveform = complex(zeros(size(ref.Waveform)));
end
waveform = localApplyIntegerDelay(waveform, timingOffsetSamples);
[waveform, channelInfo] = localApplyStrictChannel(waveform, cfg, nextTrialId + 977);
trueTimingOffsetSamples = double(timingOffsetSamples) + double(sixgr.util.structGet(channelInfo, "ChannelFilterDelay", 0));
waveform = localApplyFrequencyOffset(waveform, freqOffsetHz, tx.SampleRate_Hz);
[rx, noiseVar] = localAddNoise(waveform, snrDb, nextTrialId + 991);
if ~preamblePresent
    rx = localNoiseOnly(size(rx), noiseVar, nextTrialId + 992);
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
candidateT = localCandidateTable(runId, nextTrialId, cfg, occ, det, freqOffsetHz);
oracleT = localOracleGuardTable(runId, nextTrialId);
end

function row = localTrialRowFromDetection(runId, scenarioName, trialId, trialType, cfg, occ, tx, det, score, ...
        snrDb, timingOffsetSamples, freqOffsetHz, collisionInjected, configHash)
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
row.OccasionFrame = 0;
row.OccasionSlot = double(occ.SlotIndex0);
row.OccasionSymbol = double(occ.SymbolLocation);
row.OccasionFrequencyIndex = 0;
row.RARNTI = double(sixgr.phy.prach.computeRARNTIFromPRACHOccasion(occ));
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
    "WaveformNumSamples", NaN, "WaveformHash", "", "ChannelModel", "", "SNRdB", NaN, ...
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
        "OccasionFrame", 0, ...
        "OccasionSlot", double(occ.SlotIndex0), ...
        "OccasionSymbol", double(occ.SymbolLocation), ...
        "OccasionFrequencyIndex", 0, ...
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

function row = localNegativeRowTemplate()
row = struct("RunId", "", "NegativeTrialType", "", "InjectedFault", "", ...
    "ExpectedFailureStage", "", "ObservedFailureStage", "", "FalseAlarm", false, ...
    "MissedDetection", false, "StrictOk", false, "NegativeExpectedOk", false, ...
    "FailureReason", "");
end

function [sweepT, trialT, candT, oracleT] = localMissedDetectionSweep(cfg, occ, preamble, runId, scenarioName, configHash, threshold, trialIdStart)
snrs = localVectorOrDefault(sixgr.util.structGet(cfg, "SNRSweep_dB", []), [-24 -12 0 18]);
numTrials = max(1, min(3, round(double(cfg.NumTrials))));
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "SNRdB",NaN, ...
    "NumTrials",NaN, "NumDetected",NaN, "NumMissed",NaN, "DetectionProbability",NaN, ...
    "MissedDetectionProbability",NaN, "Threshold",NaN, "Status",""), numel(snrs), 1);
trialRows = repmat(localTrialRowTemplate(), 0, 1);
candRows = repmat(localCandidateRowTemplate(), 0, 1);
oracleRows = repmat(localOracleRowTemplate(), 0, 1);
trialId = trialIdStart;
for iSNR = 1:numel(snrs)
    detected = false(numTrials, 1);
    missed = false(numTrials, 1);
    for iTrial = 1:numTrials
        [trialId, row, cand, oracle] = localRunOneTrial(trialId, "missed_detection_sweep", cfg, occ, ...
            preamble, snrs(iSNR), 0, 0, true, false, threshold, runId, scenarioName, configHash);
        row.StrictOk = false;
        detected(iTrial) = ~row.MissedDetection && isfinite(row.PreambleIndexDetected);
        missed(iTrial) = logical(row.MissedDetection);
        trialRows(end + 1, 1) = row; %#ok<AGROW>
        candRows = [candRows; table2struct(cand)]; %#ok<AGROW>
        oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
    end
    rows(iSNR) = struct("RunId", string(runId), "SweepId", double(iSNR), "ConfigHash", string(configHash), ...
        "SNRdB", double(snrs(iSNR)), "NumTrials", double(numTrials), "NumDetected", double(sum(detected)), ...
        "NumMissed", double(sum(missed)), "DetectionProbability", mean(double(detected)), ...
        "MissedDetectionProbability", mean(double(missed)), "Threshold", double(threshold), "Status", "measured");
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
end

function [sweepT, trialT, candT, oracleT, noiseWaveform] = localFalseAlarmSweep(cfg, occ, runId, scenarioName, configHash, threshold, trialIdStart)
snrs = localVectorOrDefault(sixgr.util.structGet(cfg, "SNRSweep_dB", []), [-24 -12 0 18]);
numTrials = max(1, min(3, round(double(cfg.NumTrials))));
rows = repmat(struct("RunId","", "SweepId",NaN, "ConfigHash","", "SNRdB",NaN, ...
    "NumTrials",NaN, "NumFalseAlarms",NaN, "FalseAlarmProbability",NaN, ...
    "Threshold",NaN, "TargetFalseAlarmProbability",NaN, "Status",""), numel(snrs), 1);
trialRows = repmat(localTrialRowTemplate(), 0, 1);
candRows = repmat(localCandidateRowTemplate(), 0, 1);
oracleRows = repmat(localOracleRowTemplate(), 0, 1);
trialId = trialIdStart;
noiseWaveform = complex([]);
for iSNR = 1:numel(snrs)
    falseAlarm = false(numTrials, 1);
    for iTrial = 1:numTrials
        [trialId, row, cand, oracle, wave] = localRunOneTrial(trialId, "false_alarm_sweep", cfg, occ, ...
            localFirstPreamble(cfg), snrs(iSNR), 0, 0, false, false, threshold, runId, scenarioName, configHash);
        row.StrictOk = false;
        falseAlarm(iTrial) = logical(row.FalseAlarm);
        trialRows(end + 1, 1) = row; %#ok<AGROW>
        candRows = [candRows; table2struct(cand)]; %#ok<AGROW>
        oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
        if isempty(noiseWaveform)
            noiseWaveform = wave;
        end
    end
    rows(iSNR) = struct("RunId", string(runId), "SweepId", double(iSNR), "ConfigHash", string(configHash), ...
        "SNRdB", double(snrs(iSNR)), "NumTrials", double(numTrials), "NumFalseAlarms", double(sum(falseAlarm)), ...
        "FalseAlarmProbability", mean(double(falseAlarm)), "Threshold", double(threshold), ...
        "TargetFalseAlarmProbability", double(cfg.TargetFalseAlarmProbability), "Status", "measured");
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
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
        "ConfigHash", string(configHash), "OccasionFrame", 0, "OccasionSlot", double(occ.SlotIndex0), ...
        "OccasionSymbol", double(occ.SymbolLocation), "OccasionFrequencyIndex", 0, ...
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
summary.TimingOffsetSweepRows = height(timingT);
summary.FrequencyOffsetSweepRows = height(freqT);
summary.CollisionRows = height(collisionT);
summary.MultiOccasionRows = height(multiT);
summary.NegativeRows = height(negT);
summary.OracleGuardRows = height(oracleT);
summary.OracleGuardViolationCount = sum(logical(oracleT.Violation));
end

function y = ternary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
