function result = runStrictPDCCHValidation(baseCfg, varargin)
%RUNSTRICTPDCCHVALIDATION Execute strict waveform-backed PDCCH validation.

p = inputParser;
p.FunctionName = "sixgr.phy.pdcch.runStrictPDCCHValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ExecutionID", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioConfigHash", "", @(x) ischar(x) || isstring(x));
addParameter(p, "EvidenceScope", "component_anchor", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

runFolder = char(string(opt.RunFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);
tpSelf = sixgr.perf.TimeProfiler.scope("sixgr.phy.pdcch.runStrictPDCCHValidation", ...
    "Stage", "strict_pdcch_validation", ...
    "Metadata", struct("RunId", runId, "ScenarioName", scenarioName)); %#ok<NASGU>
cfg = sixgr.phy.pdcch.buildPDCCHConfigFromScenario(baseCfg, ...
    "RunFolder", runFolder, "RunId", runId, "ScenarioName", scenarioName);
configHash = string(cfg.ConfigHash);
toolboxCapabilities = localToolboxCapabilities();
configT = localConfigTable(runId, scenarioName, cfg);

dci10 = sixgr.phy.pdcch.buildDCI10DownlinkAssignment(cfg, "PRBStart", 0, "NumPRB", min(24, cfg.NSizeGrid), "MCS", 10);
dci00 = sixgr.phy.pdcch.buildDCI00UplinkGrant(cfg, "PRBStart", 4, "NumPRB", min(12, cfg.NSizeGrid), "MCS", 8);

trialRows = repmat(localTrialRow(), 0, 1);
candidateRows = repmat(localCandidateRow(), 0, 1);
dciFieldRows = repmat(localDCIFieldRow(), 0, 1);
grantRows = repmat(localGrantRow(), 0, 1);
oracleRows = repmat(localOracleRow(), 0, 1);
trialId = 0;
highSNR = max(32, double(sixgr.util.structGet(baseCfg, "channel.snr_dB", 35)));

[trialId, tr, cand, fields, grant, oracle, posTx] = localRunOneTrial( ...
    trialId, "positive_dci_1_0", cfg, dci10, "1_0", cfg.RNTIValue, highSNR, "normal", false);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
dciFieldRows = [dciFieldRows; table2struct(fields)]; grantRows = [grantRows; table2struct(grant)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, fields, grant, oracle] = localRunOneTrial( ...
    trialId, "positive_dci_0_0", cfg, dci00, "0_0", cfg.RNTIValue, highSNR, "normal", false);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
dciFieldRows = [dciFieldRows; table2struct(fields)]; grantRows = [grantRows; table2struct(grant)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, ~, ~, oracle] = localRunOneTrial( ...
    trialId, "wrong_rnti", cfg, dci10, "1_0", cfg.RNTIValue + 17, highSNR, "normal", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, ~, ~, oracle, noSignalTx] = localRunOneTrial( ...
    trialId, "no_signal_coreset", cfg, dci10, "1_0", cfg.RNTIValue, highSNR, "no_signal", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, ~, ~, oracle] = localRunOneTrial( ...
    trialId, "corrupted_pdcch_symbols", cfg, dci10, "1_0", cfg.RNTIValue, highSNR, "corrupt_data", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, ~, ~, oracle] = localRunOneTrial( ...
    trialId, "corrupted_pdcch_dmrs", cfg, dci10, "1_0", cfg.RNTIValue, highSNR, "corrupt_dmrs", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

[trialId, tr, cand, ~, ~, oracle] = localRunOneTrial( ...
    trialId, "wrong_dci_format", cfg, dci10, "0_0", cfg.RNTIValue, highSNR, "normal", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

badDci = sixgr.phy.pdcch.buildDCI10DownlinkAssignment(cfg, "PRBStart", 0, "NumPRB", min(24, cfg.NSizeGrid), "MCS", 31);
[trialId, tr, cand, fields, grant, oracle] = localRunOneTrial( ...
    trialId, "invalid_grant_fields", cfg, badDci, "1_0", cfg.RNTIValue, highSNR, "normal", true);
trialRows(end+1,1) = tr; candidateRows = [candidateRows; table2struct(cand)]; %#ok<AGROW>
dciFieldRows = [dciFieldRows; table2struct(fields)]; grantRows = [grantRows; table2struct(grant)]; %#ok<AGROW>
oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>

trialT = struct2table(trialRows, "AsArray", true);
candidateT = struct2table(candidateRows, "AsArray", true);
dciFieldT = struct2table(dciFieldRows, "AsArray", true);
grantT = struct2table(grantRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);

[falseAlarmT, faTrials, faCand, faOracle] = localFalseAlarmSweep(cfg, dci10, trialId);
trialId = trialId + height(faTrials);
trialT = [trialT; faTrials]; candidateT = [candidateT; faCand]; oracleT = [oracleT; faOracle];
[missT, missTrials, missCand, missFields, missGrant, missOracle] = localMissedDetectionSweep(cfg, dci10, dci00, trialId);
trialId = trialId + height(missTrials);
trialT = [trialT; missTrials]; candidateT = [candidateT; missCand]; oracleT = [oracleT; missOracle];
dciFieldT = [dciFieldT; missFields]; grantT = [grantT; missGrant];
[lowSNRT, lowTrials, lowCand, lowFields, lowGrant, lowOracle] = localLowSNRSweep(cfg, dci10, trialId);
trialT = [trialT; lowTrials]; candidateT = [candidateT; lowCand];
dciFieldT = [dciFieldT; lowFields]; grantT = [grantT; lowGrant]; oracleT = [oracleT; lowOracle];

wrongRNTIT = localWrongRNTITable(trialT);
noSignalT = localNoSignalTable(trialT);
corruptionT = localCorruptionTable(trialT);

strictPositiveOk = sum(logical(trialT.StrictOk) & ismember(string(trialT.TrialType), ["positive_dci_1_0","positive_dci_0_0"])) >= 2;
negativeOk = all(logical(trialT.NegativeExpectedOk(ismember(string(trialT.TrialType), ...
    ["wrong_rnti","no_signal_coreset","corrupted_pdcch_symbols","corrupted_pdcch_dmrs","wrong_dci_format","invalid_grant_fields"]))));
artifactRowsOk = height(configT) > 0 && height(candidateT) > 0 && height(dciFieldT) > 0 && ...
    height(grantT) > 0 && height(wrongRNTIT) > 0 && height(noSignalT) > 0 && ...
    height(corruptionT) > 0 && height(falseAlarmT) > 0 && height(lowSNRT) > 0 && height(oracleT) > 0;
oracleOk = ~any(logical(oracleT.Violation));
configOk = logical(cfg.StrictValidation.StrictValid);
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
strictOk = strictPositiveOk && negativeOk && artifactRowsOk && oracleOk && configOk && noProxySkip;
summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, falseAlarmT, missT, lowSNRT, oracleT);

result = struct();
result.RunId = runId;
result.ScenarioName = scenarioName;
result.Config = cfg;
result.ConfigHash = configHash;
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
result.StatisticallyQualified = logical(summary.StatisticallyQualified);
result.StatisticalQualification = string(summary.StatisticalQualification);
result.FailureReason = string(ternary(strictOk, "", "strict_pdcch_validation_failed"));
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ToolboxCapabilities = toolboxCapabilities;
result.DetectionSummary = summary;
result.PositiveGrid = posTx.Grid;
result.NoSignalGrid = noSignalTx.Grid .* 0;
result.TxDCI10 = dci10;
result.TxDCI00 = dci00;
result.RxDCIHex = localFirstNonEmpty(trialT.DCIPayloadHexRx);
result.ArtifactTables = struct( ...
    "pdcch_config_strict", configT, ...
    "pdcch_trials", trialT, ...
    "pdcch_candidates", candidateT, ...
    "pdcch_dci_fields", dciFieldT, ...
    "pdcch_grant_validation", grantT, ...
    "pdcch_wrong_rnti_trials", wrongRNTIT, ...
    "pdcch_no_signal_trials", noSignalT, ...
    "pdcch_corruption_trials", corruptionT, ...
    "pdcch_false_alarm_sweep", falseAlarmT, ...
    "pdcch_missed_detection_sweep", missT, ...
    "pdcch_low_snr_sweep", lowSNRT, ...
    "pdcch_oracle_guard", oracleT);

if strlength(strtrim(string(opt.ExecutionID))) > 0
    identity = struct("RunID", runId, ...
        "ExecutionID", string(opt.ExecutionID), ...
        "ScenarioID", scenarioName, ...
        "ConfigHash", string(opt.ScenarioConfigHash));
    result.ArtifactTables = sixgr.runtime.bindInPathArtifactIdentity( ...
        result.ArtifactTables, identity, string(opt.EvidenceScope));
    result.ExecutionID = identity.ExecutionID;
    result.ScenarioConfigHash = identity.ConfigHash;
    result.EvidenceScope = string(opt.EvidenceScope);
end

if logical(opt.WriteArtifacts)
    result.ArtifactManifest = sixgr.phy.pdcch.exportStrictPDCCHArtifacts(runFolder, result);
else
    result.ArtifactManifest = table();
end
end

function [nextTrialId, row, candidateT, fieldT, grantT, oracleT, tx] = localRunOneTrial( ...
    trialId, trialType, cfg, dci, attemptedFormat, attemptedRNTI, snrDb, mode, negativeExpected)
nextTrialId = trialId + 1;
tx = sixgr.phy.pdcch.generatePDCCHWaveform(cfg, dci);
rxWave = tx.Waveform;
noiseOnly = [];
noiseSeed = double(sixgr.util.structGet(cfg, "NoiseSeedOverride", 7000 + nextTrialId));
noiseSubstream = double(sixgr.util.structGet(cfg,"NoiseSubstreamOverride",NaN));
[rxWave, noiseReference, noiseOnly] = localAddAWGN(rxWave, tx, snrDb, noiseSeed,noiseSubstream);
switch string(mode)
    case "no_signal"
        rxWave = noiseOnly;
    case "corrupt_data"
        corruptGrid = tx.Grid;
        corruptGrid(tx.PDCCHInd) = -tx.Grid(tx.PDCCHInd);
        rxWave = sixgr.phy.waveform.ofdmModulate(tx.Carrier, corruptGrid);
        noiseSeed=7100+nextTrialId; noiseSubstream=NaN;
        [rxWave, noiseReference, noiseOnly] = localAddAWGN(rxWave, tx, snrDb, noiseSeed);
    case "corrupt_dmrs"
        corruptGrid = tx.Grid;
        rng(7200 + nextTrialId, "twister");
        corruptGrid(tx.DMRSInd) = (randn(numel(tx.DMRSInd),1) + 1i*randn(numel(tx.DMRSInd),1)) ./ sqrt(2);
        rxWave = sixgr.phy.waveform.ofdmModulate(tx.Carrier, corruptGrid);
        noiseSeed=7300+nextTrialId; noiseSubstream=NaN;
        [rxWave, noiseReference, noiseOnly] = localAddAWGN(rxWave, tx, snrDb, noiseSeed);
end
det = sixgr.phy.pdcch.blindDecodePDCCH(rxWave, cfg, ...
    "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "RNTIAttempted", attemptedRNTI, ...
    "DCIFormatAttempted", attemptedFormat, "ListLength", 8);
% Generated noise and its variance belong to scoring only. The practical
% receiver must estimate noise from its own received samples/DMRS.
score = sixgr.phy.pdcch.scorePDCCHDetection(det, tx, cfg, ...
    "TrialType", trialType, "NegativeExpected", negativeExpected);
row = localTrialRowFromScore(nextTrialId, trialType, cfg, tx, det, score, attemptedRNTI, attemptedFormat, snrDb);
row.NoiseSeed = noiseSeed;
row.NoiseSubstream = noiseSubstream;
row.SignalEnergyPerOccupiedRE=noiseReference.SignalEnergyPerOccupiedRE;
row.AppliedGridNoiseVariance=noiseReference.GridNoiseVariance;
row.AppliedSampleNoiseVariance=noiseReference.SampleNoiseVariance;
row.SampleToGridNoiseVarianceGain=noiseReference.SampleToGridNoiseVarianceGain;
row.SNRReferencePlane=noiseReference.SNRReferencePlane;
row.NoiseCalibrationSource=noiseReference.Source;
row.ReceiverNoiseVarianceSource=string(det.Rx.NoiseVarSource);
row.GeneratedNoiseSuppliedToReceiver=false;
noiseGrid=sixgr.phy.waveform.ofdmDemodulate(tx.Carrier,noiseOnly);
row.ScoringMeasuredGridNoiseVariance=mean(abs(noiseGrid(:)).^2);
row.ScoringNoiseComparedRECount=numel(noiseGrid);
row.NoiseGenerator = "mt19937ar";
if isfinite(noiseSubstream), row.NoiseGenerator="Threefry"; end
candidateT = det.Candidates;
candidateT.RunId = repmat(string(cfg.RunId), height(candidateT), 1);
candidateT.TrialId = repmat(double(nextTrialId), height(candidateT), 1);
candidateT = movevars(candidateT, ["RunId","TrialId"], "Before", 1);
candidateT.GrantValid(:) = logical(score.GrantValid) & logical(candidateT.SelectedCandidate);
fieldT = score.FieldEquality;
if isempty(fieldT)
    fieldT = struct2table(repmat(localDCIFieldRow(), 0, 1));
else
    fieldT.TrialId(:) = double(nextTrialId);
end
grantT = localGrantTable(cfg, nextTrialId, score);
oracleT = localOracleGuardTable(cfg.RunId, nextTrialId);
end

function row = localTrialRowFromScore(trialId, trialType, cfg, tx, det, score, attemptedRNTI, attemptedFormat, snrDb)
row = localTrialRow();
row.RunId = string(cfg.RunId);
row.ScenarioName = string(cfg.ScenarioName);
row.TrialId = double(trialId);
row.TrialType = string(trialType);
row.CellId = double(cfg.CellId);
row.UEId = double(cfg.UEId);
row.ConfigHash = string(cfg.ConfigHash);
row.Frame = double(cfg.FrameNumber);
row.Slot = double(cfg.SlotNumber);
row.RNTITypeTx = string(cfg.RNTIType);
row.RNTITx = double(tx.RNTI);
row.RNTIAttempted = double(attemptedRNTI);
row.DCIFormatTx = string(tx.DCI.Format);
row.DCIFormatAttempted = upper(strrep(string(attemptedFormat), "-", "_"));
row.DCIPayloadSizeBits = double(cfg.DCIPayloadSizeBits);
row.TxAggregationLevel = double(tx.AggregationLevel);
row.TxCandidateIndex = double(tx.CandidateIndex);
row.TxCCEIndex = double(tx.CCEIndex);
selected = logical(det.Rx.PhysicalHypothesisSelected);
row.SelectedAggregationLevel = double(ternary(selected, det.Rx.CandidateAggregationLevel, NaN));
row.SelectedCandidateIndex = double(ternary(selected, det.Rx.CandidateIndex, NaN));
row.SelectedCCEIndex = double(ternary(selected, det.Rx.CandidateCCEIndex, NaN));
row.CandidatesAttempted = double(score.CandidatesAttempted);
row.DCICrcPass = isfinite(det.Rx.ErrFlag) && det.Rx.ErrFlag==0;
row.DCIMask = string(ternary(row.DCICrcPass, "rnti_crc_mask_pass", "crc_fail"));
row.DCIPayloadHexTx = string(tx.DCI.PayloadHex);
row.DCIPayloadHexRx = string(det.DecodedDCI.PayloadHex);
row.DCIPayloadHashTx = string(tx.DCI.PayloadHash);
row.DCIPayloadHashRx = string(det.DecodedDCI.PayloadHash);
if selected
    selectedRow=det.Candidates(logical(det.Candidates.SelectedCandidate),:);
    assert(height(selectedRow)==1,'sixgr:phy:pdcch:AmbiguousSelectedCandidate');
    row.DCIPayloadHexRx=string(selectedRow.DecodedPayloadHex);
    row.DCIPayloadHashRx=string(selectedRow.PayloadHash);
end
row.DCIPayloadMatch = logical(score.PayloadMatch);
row.DecodedDCIFieldsHash = localDecodedFieldHash(det.DecodedDCI);
row.ControlResourceValidity = logical(score.ControlResourceValidity);
row.ControlResourceSource = "strict_pdcch_coreset_searchspace_config";
row.ControlResourceFailureReason = string(score.ControlResourceFailureReason);
row.GrantValid = logical(score.GrantValid);
row.GrantType = string(sixgr.util.structGet(score.Grant, "GrantType", ""));
row.GrantReferenceId = string(sixgr.util.structGet(score.Grant, "GrantReferenceId", ""));
row.WrongRNTIRejectCount = double(string(trialType) == "wrong_rnti" && logical(score.NegativeExpectedOk));
row.NoSignalRejectCount = double(string(trialType) == "no_signal_coreset" && logical(score.NegativeExpectedOk));
row.FalseCandidateCount = double(score.FalseCandidateCount);
row.CorruptedCandidateRejectCount = double(startsWith(string(trialType), "corrupted") && logical(score.NegativeExpectedOk));
row.InvalidGrantRejectCount = double(string(trialType) == "invalid_grant_fields" && logical(score.NegativeExpectedOk));
row.DetectionMetric = double(score.DetectionMetric);
row.BestCandidateMetric = double(score.BestCandidateMetric);
row.SecondBestCandidateMetric = double(score.SecondBestCandidateMetric);
row.MetricMargin = double(score.MetricMargin);
row.NoiseVariance = double(det.Rx.NoiseVar);
row.SNRdB = double(snrDb);
row.ChannelModel = "AWGN_STRICT_PDCCH_CONTROL_VALIDATION";
row.ProxyUsed = false;
row.Skipped = false;
row.ToolboxMissing = false;
row.UsedOracleFields = "";
row.StrictOk = logical(score.StrictOk);
row.NegativeExpectedOk = logical(score.NegativeExpectedOk);
row.Status = string(score.Status);
row.FailureReason = string(score.FailureReason);
end

function [falseAlarmT, trialT, candT, oracleT] = localFalseAlarmSweep(cfg, dci, trialId)
snrs = cfg.StatisticalQualification.FalseAlarmSNRdB;
design = cfg.StatisticalQualification;
maximumWaveformTrials = round(double(design.MaximumWaveformTrials));
batchSize = round(double(design.BatchSizeWaveformTrials));
seedSet = double(design.DeterministicSeeds(:).');
plan=localStatisticalPlan(cfg);
rows = repmat(localFalseAlarmRow(), numel(snrs), 1);
trialRows = repmat(localTrialRow(), 0, 1);
candRows = repmat(localCandidateRow(), 0, 1);
oracleRows = repmat(localOracleRow(), 0, 1);
for si = 1:numel(snrs)
    falseCount = 0; candCount = 0; falseWaveforms = 0;
    qualification = localUnevaluatedQualification("no_candidate_decisions_observed");
    lookIndex = 0;
    waveformTrialCount = 0;
    for tt = 1:maximumWaveformTrials
        cfgTrial = cfg;
        identity=sixgr.phy.pdcch.noiseTrialIdentity(seedSet,si,tt,plan.EpisodeBlockSize);
        cfgTrial.NoiseSeedOverride = identity.Seed;
        cfgTrial.NoiseSubstreamOverride = identity.Substream;
        [trialId, tr, cand, ~, ~, oracle] = localRunOneTrial(trialId, "false_alarm_sweep", cfgTrial, dci, "1_0", cfg.RNTIValue, snrs(si), "no_signal", true);
        falseCount = falseCount + double(tr.FalseCandidateCount);
        falseWaveforms = falseWaveforms + double(tr.FalseCandidateCount > 0);
        candCount = candCount + height(cand);
        waveformTrialCount = tt;
        trialRows(end+1,1) = tr; %#ok<AGROW>
        candRows = [candRows; table2struct(cand)]; oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
        atLook = mod(tt,batchSize) == 0 || tt == maximumWaveformTrials;
        if atLook && candCount >= round(double(design.MinimumCandidateDecisions)) && ...
                tt >= round(double(design.MinimumWaveformTrials))
            lookIndex = lookIndex + 1;
            qualification = sixgr.stats.evaluateBinomialStopping( ...
                falseWaveforms,tt,double(design.TargetProbability), ...
                "ConfidenceLevel",plan.PerPointConfidenceLevel, ...
                "MinimumTrials",round(double(design.MinimumWaveformTrials)), ...
                "MaximumTrials",maximumWaveformTrials, ...
                "MinimumEvents",round(double(design.MinimumFalseAlarmEvents)), ...
                "CIWidthTarget",double(design.CIWidthTarget), ...
                "LookIndex",lookIndex,"PlannedLooks",round(double(design.PlannedLooks)), ...
                "FinalLook",tt == maximumWaveformTrials, ...
                "MetricName","pdcch_false_alarm_probability");
            if ~qualification.ContinueSampling
                break;
            end
        end
    end
    row = localFalseAlarmRow();
    row.RunId = string(cfg.RunId); row.SweepId = "false_alarm_" + string(si);
    row.ConfigHash = string(cfg.ConfigHash); row.NoiseModel = "AWGN";
    row.QualificationContextHash=string(cfg.ConfigHash);
    row.QualificationScope="awgn_component_not_nr_conformance";
    row.PlannedOperatingPointCount=numel(snrs);
    row.SNRdB = snrs(si); row.NumTrials = waveformTrialCount;
    row.WaveformTrialCount = waveformTrialCount;
    row.NumCandidatesPerTrial = candCount / max(waveformTrialCount,1);
    row.CandidateDecisionCount = candCount;
    row.NumFalseCandidates = falseCount;
    row.FalseAlarmWaveformCount = falseWaveforms;
    if waveformTrialCount > 0, row.FalseAlarmProbability = falseWaveforms/waveformTrialCount; end
    if candCount > 0, row.CandidateFalseAlarmFraction = falseCount/candCount; end
    row.TargetFalseAlarmProbability = double(design.TargetProbability);
    row.CILower = qualification.CILower; row.CIUpper = qualification.CIUpper;
    row.CIWidth = qualification.CIWidth; row.CIWidthTarget = double(design.CIWidthTarget);
    row.ConfidenceLevel = double(design.ConfidenceLevel);
    row.PerPointConfidenceLevel=plan.PerPointConfidenceLevel;
    row.JointOperatingPointCount=plan.JointOperatingPointCount;
    row.EffectiveDirectionalConfidenceLevel = qualification.EffectiveDirectionalConfidenceLevel;
    row.AlphaSpentThisLook = qualification.AlphaSpentThisLook;
    row.IntervalMethod = qualification.IntervalMethod;
    row.SequentialDesign = qualification.SequentialDesign;
    row.LookIndex = qualification.LookIndex; row.PlannedLooks = double(design.PlannedLooks);
    row.MinimumCandidateDecisions = double(design.MinimumCandidateDecisions);
    row.MaximumWaveformTrials = maximumWaveformTrials;
    row.MinimumFalseAlarmEvents = double(design.MinimumFalseAlarmEvents);
    row.PointEstimatePass = qualification.PointEstimatePass;
    row.StatisticalQualification = qualification.Qualification;
    row.StatisticallyQualified = qualification.StatisticallyQualified;
    row.StoppingReason = qualification.StoppingReason;
    row.DeterministicSeedCount = numel(seedSet);
    row.DeterministicSeedSet = strjoin(string(seedSet), "|");
    row.SeedDerivation = "first_configured_seed_Threefry_disjoint_episode_blocks_configured_family_offset";
    row.EvidenceUnit = "independent_noise_only_waveform";
    row.Status = qualification.Qualification;
    rows(si) = row;
end
falseAlarmT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
end

function plan=localStatisticalPlan(cfg)
snrs=cfg.StatisticalQualification.FalseAlarmSNRdB;
h1=cfg.MissedDetectionQualification;
count=numel(snrs); block=double(cfg.StatisticalQualification.MaximumWaveformTrials);
if h1.Enabled
    count=count+numel(h1.SNRdB)*numel(h1.DCIFormats);
    block=max(block,h1.MaximumWaveformTrials);
end
% One family-wise confidence budget across all declared H0/H1 points;
% evaluateBinomialStopping additionally divides it across looks/directions.
confidence=1-(1-double(cfg.StatisticalQualification.ConfidenceLevel))/count;
assert(confidence<1,'sixgr:phy:pdcch:InvalidStatisticalQualification', ...
    'Joint population count makes confidence rounding invalid.');
plan=struct('PerPointConfidenceLevel',confidence,'JointOperatingPointCount',count, ...
    'EpisodeBlockSize',block,'FalseAlarmPointCount',numel(snrs));
end

function [sweepT,trialT,candT,fieldT,grantT,oracleT]=localMissedDetectionSweep(cfg,dci10,dci00,trialId)
design=cfg.MissedDetectionQualification;
rows=repmat(localMissedDetectionRow(),0,1);
trials=repmat(localTrialRow(),0,1); candidates=repmat(localCandidateRow(),0,1);
fields=repmat(localDCIFieldRow(),0,1); grants=repmat(localGrantRow(),0,1);
oracles=repmat(localOracleRow(),0,1);
if design.Enabled
    plan=localStatisticalPlan(cfg); seeds=double(cfg.StatisticalQualification.DeterministicSeeds(:).');
    point=0; total=numel(design.SNRdB)*numel(design.DCIFormats);
    for format=design.DCIFormats
        dci=dci10; if format=="0_0", dci=dci00; end
        for snr=design.SNRdB
            point=point+1; missed=0; crcFailures=0; falseCandidates=0; look=0;
            for episode=1:design.MaximumWaveformTrials
                current=cfg;
                id=sixgr.phy.pdcch.noiseTrialIdentity(seeds, ...
                    plan.FalseAlarmPointCount+point,episode,plan.EpisodeBlockSize);
                current.NoiseSeedOverride=id.Seed; current.NoiseSubstreamOverride=id.Substream;
                [trialId,tr,cand,f,g,o,tx]=localRunOneTrial(trialId,"missed_detection_sweep", ...
                    current,dci,format,cfg.RNTIValue,snr,"normal",false);
                % Count the intended grant once per received waveform. Extra
                % blind hypotheses are not independent Bernoulli trials, and
                % a CRC pass for the wrong payload/resource is not delivery.
                delivered=tr.DCICrcPass && tr.DCIPayloadMatch && tr.GrantValid && ...
                    tr.ControlResourceValidity && tr.SelectedAggregationLevel==tr.TxAggregationLevel && ...
                    tr.SelectedCandidateIndex==tr.TxCandidateIndex && tr.SelectedCCEIndex==tr.TxCCEIndex;
                missed=missed+double(~delivered); crcFailures=crcFailures+double(~tr.DCICrcPass);
                falseCandidates=falseCandidates+tr.FalseCandidateCount;
                trials(end+1,1)=tr; %#ok<AGROW>
                candidates=[candidates;table2struct(cand)]; fields=[fields;table2struct(f)]; %#ok<AGROW>
                grants=[grants;table2struct(g)]; oracles=[oracles;table2struct(o)]; %#ok<AGROW>
                if mod(episode,design.BatchSizeWaveformTrials)==0 || episode==design.MaximumWaveformTrials
                    look=look+1;
                    q=sixgr.stats.evaluateBinomialStopping(missed,episode,design.TargetProbability, ...
                        'ConfidenceLevel',plan.PerPointConfidenceLevel, ...
                        'MinimumTrials',design.MinimumWaveformTrials,'MaximumTrials',design.MaximumWaveformTrials, ...
                        'MinimumEvents',design.MinimumEvents,'CIWidthTarget',design.CIWidthTarget, ...
                        'LookIndex',look,'PlannedLooks',design.PlannedLooks, ...
                        'FinalLook',episode==design.MaximumWaveformTrials,'MetricName',"pdcch_missed_grant_probability");
                    if ~q.ContinueSampling, break; end
                end
            end
            row=localMissedDetectionRow();
            row.RunId=string(cfg.RunId); row.SweepId="missed_detection_"+string(point);
            row.ConfigHash=string(cfg.ConfigHash); row.QualificationContextHash=string(cfg.ConfigHash);
            row.PlannedOperatingPointCount=total; row.JointOperatingPointCount=plan.JointOperatingPointCount;
            row.SNRdB=snr; row.DCIFormat=format; row.AggregationLevel=double(cfg.AggregationLevel);
            row.TxDimensions=size(tx.Waveform,2); row.RxDimensions=size(tx.Waveform,2);
            row.WaveformTrialCount=episode; row.MissedGrantCount=missed; row.DeliveredGrantCount=episode-missed;
            row.CRCFailureCount=crcFailures; row.FalseCandidateCount=falseCandidates;
            row.MissedGrantProbability=missed/episode; row.TargetMissedGrantProbability=design.TargetProbability;
            row.ConfidenceLevel=double(cfg.StatisticalQualification.ConfidenceLevel);
            row.PerPointConfidenceLevel=plan.PerPointConfidenceLevel;
            for name=["CILower","CIUpper","CIWidth","CIWidthTarget","EffectiveDirectionalConfidenceLevel", ...
                    "AlphaSpentThisLook","IntervalMethod","SequentialDesign","LookIndex","PlannedLooks", ...
                    "MinimumTrials","MaximumTrials","MinimumEvents","PointEstimatePass","StatisticallyQualified","StoppingReason"]
                row.(name)=q.(name);
            end
            row.StatisticalQualification=q.Qualification; row.Status=q.Qualification;
            row.DeterministicSeedSet=strjoin(string(seeds),'|');
            rows(end+1,1)=row; %#ok<AGROW>
        end
    end
end
sweepT=struct2table(rows,'AsArray',true); trialT=struct2table(trials,'AsArray',true);
candT=struct2table(candidates,'AsArray',true); fieldT=struct2table(fields,'AsArray',true);
grantT=struct2table(grants,'AsArray',true); oracleT=struct2table(oracles,'AsArray',true);
end

function [sweepT, trialT, candT, fieldT, grantT, oracleT] = localLowSNRSweep(cfg, dci, trialId)
snrs = double(sixgr.util.structGet(cfg.BaseConfig, "lls6g.control.pdcch_strict.low_snr_sweep_db", [-8 0 10 35]));
numTrials = max(1, round(double(sixgr.util.structGet(cfg.BaseConfig, "lls6g.control.pdcch_strict.low_snr_trials", 1))));
rows = repmat(localLowSNRRow(), numel(snrs), 1);
trialRows = repmat(localTrialRow(), 0, 1);
candRows = repmat(localCandidateRow(), 0, 1);
fieldRows = repmat(localDCIFieldRow(), 0, 1);
grantRows = repmat(localGrantRow(), 0, 1);
oracleRows = repmat(localOracleRow(), 0, 1);
for si = 1:numel(snrs)
    detected = 0; crc = 0; margins = zeros(numTrials, 1);
    for tt = 1:numTrials
        [trialId, tr, cand, fields, grant, oracle] = localRunOneTrial(trialId, "low_snr_sweep", cfg, dci, "1_0", cfg.RNTIValue, snrs(si), "normal", false);
        detected = detected + double(tr.StrictOk);
        crc = crc + double(tr.DCICrcPass);
        margins(tt) = double(tr.MetricMargin);
        trialRows(end+1,1) = tr; %#ok<AGROW>
        candRows = [candRows; table2struct(cand)]; fieldRows = [fieldRows; table2struct(fields)]; %#ok<AGROW>
        grantRows = [grantRows; table2struct(grant)]; oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
    end
    row = localLowSNRRow();
    row.RunId = string(cfg.RunId); row.SweepId = "low_snr_" + string(si);
    row.ConfigHash = string(cfg.ConfigHash); row.SNRdB = snrs(si);
    row.NumTrials = numTrials; row.NumDetected = detected; row.NumCrcPass = crc;
    row.DetectionProbability = detected / numTrials; row.CrcPassProbability = crc / numTrials;
    detectionInterval = sixgr.validation.BinomialIntervalEngine.exactTwoSided( ...
        detected,numTrials,double(cfg.StatisticalQualification.ConfidenceLevel), ...
        "LookIndex",1,"AlphaSpent",1-double(cfg.StatisticalQualification.ConfidenceLevel), ...
        "DesignID","fixed_sample_characterization");
    crcInterval = sixgr.validation.BinomialIntervalEngine.exactTwoSided( ...
        crc,numTrials,double(cfg.StatisticalQualification.ConfidenceLevel), ...
        "LookIndex",1,"AlphaSpent",1-double(cfg.StatisticalQualification.ConfidenceLevel), ...
        "DesignID","fixed_sample_characterization");
    row.DetectionCILower = detectionInterval.Lower;
    row.DetectionCIUpper = detectionInterval.Upper;
    row.CrcPassCILower = crcInterval.Lower;
    row.CrcPassCIUpper = crcInterval.Upper;
    row.ConfidenceLevel = double(cfg.StatisticalQualification.ConfidenceLevel);
    row.IntervalMethod = "CLOPPER_PEARSON_TWO_SIDED";
    row.EvidenceUnit = "pdcch_waveform_trial";
    row.MeanMetricMargin = mean(margins, "omitnan");
    row.Status = "measured_waveform_sweep";
    rows(si) = row;
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
fieldT = struct2table(fieldRows, "AsArray", true);
grantT = struct2table(grantRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
end

function [y, provenance, noise] = localAddAWGN(x, tx, snrDb, seed,substream)
if nargin<5, substream=NaN; end
if isfinite(substream)
    stream=RandStream('Threefry','Seed',seed);
    stream.Substream=substream;
else
    stream=RandStream('mt19937ar','Seed',seed);
end
reference=double(tx.Grid([tx.PDCCHInd(:);tx.DMRSInd(:)]));
energy=mean(abs(reference).^2);
if ~(isfinite(energy) && energy > 0)
    error('sixgr:phy:pdcch:MissingNoiseReferencePower', ...
        'Noise-only trials require a nonzero transmitted reference for the declared noise calibration.');
end
[y,provenance,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
    x,tx.Carrier,snrDb,'Stream',stream,'SignalEnergyPerOccupiedRE',energy);
end

function T = localGrantTable(cfg, trialId, score)
if ~isfield(score, "Grant") || isempty(fieldnames(score.Grant))
    T = struct2table(repmat(localGrantRow(), 0, 1));
    return;
end
g = score.Grant;
row = localGrantRow();
row.RunId = string(cfg.RunId); row.TrialId = double(trialId);
row.GrantReferenceId = string(g.GrantReferenceId); row.GrantType = string(g.GrantType);
row.DCIFormat = string(g.DCIFormat); row.RNTIType = string(g.RNTIType);
row.FrequencyResourceAssignment = double(g.FrequencyResourceAssignment);
row.TimeResourceAssignment = double(g.TimeResourceAssignment);
row.PRBStart = double(g.PRBStart); row.NumPRB = double(g.NumPRB);
row.SymbolStart = double(g.SymbolStart); row.NumSymbols = double(g.NumSymbols);
row.MCS = double(g.MCS); row.Modulation = string(g.Modulation); row.TBS = NaN;
row.HARQProcess = double(g.HARQProcess); row.NDI = double(g.NDI); row.RV = double(g.RV);
row.TPC = double(g.TPC); row.PUCCHResourceIndicator = double(g.PUCCHResourceIndicator);
row.PDSCHToHARQFeedbackTiming = double(g.PDSCHToHARQFeedbackTiming);
row.Valid = logical(g.Valid); row.FailureReason = string(g.FailureReason);
T = struct2table(row, "AsArray", true);
end

function T = localWrongRNTITable(trialT)
T0 = trialT(string(trialT.TrialType) == "wrong_rnti", :);
T = table(T0.RunId, T0.TrialId, T0.RNTITx, T0.RNTIAttempted, T0.CandidatesAttempted, ...
    T0.FalseCandidateCount, T0.WrongRNTIRejectCount, T0.NegativeExpectedOk, T0.FailureReason, ...
    'VariableNames', {'RunId','TrialId','RNTITx','RNTIAttempted','CandidatesAttempted', ...
    'FalsePassCount','WrongRNTIRejectCount','NegativeExpectedOk','FailureReason'});
end

function T = localNoSignalTable(trialT)
T0 = trialT(ismember(string(trialT.TrialType), ["no_signal_coreset","false_alarm_sweep"]), :);
T = table(T0.RunId, T0.TrialId, repmat("AWGN", height(T0), 1), T0.SNRdB, ...
    T0.CandidatesAttempted, T0.FalseCandidateCount, T0.FalseCandidateCount > 0, ...
    T0.NegativeExpectedOk, T0.FailureReason, ...
    'VariableNames', {'RunId','TrialId','NoiseModel','SNRdB','CandidatesAttempted', ...
    'FalseCandidateCount','FalseAlarm','NegativeExpectedOk','FailureReason'});
end

function T = localCorruptionTable(trialT)
T0 = trialT(startsWith(string(trialT.TrialType), "corrupted"), :);
T = table(T0.RunId, T0.TrialId, string(T0.TrialType), erase(string(T0.TrialType), "corrupted_pdcch_"), ...
    repmat(1, height(T0), 1), repmat("dci_crc_or_grant_reject", height(T0), 1), ...
    string(T0.Status), T0.DCICrcPass, T0.GrantValid, T0.NegativeExpectedOk, T0.FailureReason, ...
    'VariableNames', {'RunId','TrialId','CorruptionType','CorruptionTarget','CorruptionStrength', ...
    'ExpectedFailureStage','ObservedFailureStage','DCICrcPass','GrantValid','NegativeExpectedOk','FailureReason'});
end

function T = localOracleGuardTable(runId, trialId)
fields = ["tx_dci_bits","tx_payload_hex","tx_rnti","tx_candidate_index","tx_aggregation_level","tx_cce_index","scheduler_grant", ...
    "generated_noise_samples","injected_noise_variance"];
rows = repmat(localOracleRow(), numel(fields), 1);
for ii = 1:numel(fields)
    rows(ii).RunId = string(runId);
    rows(ii).TrialId = double(trialId);
    rows(ii).Stage = "receiver_before_decode";
    rows(ii).OracleFieldName = fields(ii);
    rows(ii).WasAccessed = false;
    rows(ii).Allowed = false;
    rows(ii).Violation = false;
    rows(ii).Status = "not_accessed";
end
T = struct2table(rows, "AsArray", true);
end

function T = localConfigTable(runId, scenarioName, cfg)
T = table(string(runId), string(scenarioName), double(cfg.CellId), double(cfg.UEId), ...
    string(cfg.ConfigHash), string(cfg.BindingSource), double(cfg.CarrierFrequencyHz), ...
    string(cfg.FrequencyRange), double(cfg.NCellID), double(cfg.NSizeGrid), double(cfg.NStartGrid), ...
    double(cfg.SubcarrierSpacingKHz), double(cfg.CORESETId), double(cfg.CORESETDurationSymbols), ...
    double(cfg.CORESETRBStart), double(cfg.CORESETNumRB), string(cfg.CCE_REG_MappingType), ...
    double(cfg.REGBundleSize), double(cfg.InterleaverSize), double(cfg.ShiftIndex), ...
    string(cfg.PrecoderGranularity), double(cfg.SearchSpaceId), string(cfg.SearchSpaceType), ...
    double(cfg.SearchSpacePeriodicity), double(cfg.SearchSpaceOffset), double(cfg.SearchSpaceDuration), ...
    double(cfg.SearchSpaceFirstSymbolWithinSlot), double(cfg.NumCandidatesAL1), double(cfg.NumCandidatesAL2), ...
    double(cfg.NumCandidatesAL4), double(cfg.NumCandidatesAL8), double(cfg.NumCandidatesAL16), ...
    strjoin(string(cfg.DCIMonitoringFormats), "|"), string(cfg.RNTIType), double(cfg.RNTIValue), ...
    double(cfg.ConfiguredDCIPayloadSizeBits), double(cfg.DCIPayloadSizeBits), ...
    double(cfg.DCIPayloadFrequencyAssignmentBits), string(cfg.DCIPayloadSizeSource), ...
    logical(cfg.DCIPayloadConfiguredMismatch), ...
    logical(cfg.StrictValidation.StrictValid), string(cfg.StrictValidation.StrictUnsupportedReason), ...
    string(cfg.StrictValidation.Status), ...
    'VariableNames', {'RunId','ScenarioName','CellId','UEId','ConfigHash','BindingSource', ...
    'CarrierFrequencyHz','FrequencyRange','NCellID','NSizeGrid','NStartGrid','SubcarrierSpacingKHz', ...
    'CORESETId','CORESETDurationSymbols','CORESETRBStart','CORESETNumRB','CCE_REG_MappingType', ...
    'REGBundleSize','InterleaverSize','ShiftIndex','PrecoderGranularity','SearchSpaceId', ...
    'SearchSpaceType','SearchSpacePeriodicity','SearchSpaceOffset','SearchSpaceDuration', ...
    'FirstSymbolWithinSlot','NumCandidatesAL1','NumCandidatesAL2','NumCandidatesAL4', ...
    'NumCandidatesAL8','NumCandidatesAL16','DCIMonitoringFormats','RNTIType','RNTIValue', ...
    'ConfiguredDCIPayloadSizeBits','DCIPayloadSizeBits','DCIPayloadFrequencyAssignmentBits', ...
    'DCIPayloadSizeSource','DCIPayloadConfiguredMismatch', ...
    'StrictValid','StrictUnsupportedReason','Status'});
T.CRCLength=double(cfg.CRCLength);
T.CRCPolynomial=string(cfg.CRCPolynomial);
T.RNTIMaskLength=double(cfg.RNTIMaskLength);
end

function summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, falseAlarmT, missT, lowSNRT, oracleT)
summary = struct();
summary.RunId = string(runId);
summary.scenario = string(scenarioName);
summary.timestamp = sixgr.util.utcNowISO8601();
summary.implementation_status = "strict_pdcch_waveform_blind_decode_validation";
summary.ProducerModule = "sixgr.phy.pdcch.runStrictPDCCHValidation";
summary.ConfigHash = string(cfg.ConfigHash);
summary.StrictOk = logical(strictOk);
summary.PositiveStrictOkCount = sum(logical(trialT.StrictOk));
summary.NegativeExpectedOkCount = sum(logical(trialT.NegativeExpectedOk));
summary.WrongRNTIRows = sum(string(trialT.TrialType) == "wrong_rnti");
summary.NoSignalRows = sum(string(trialT.TrialType) == "no_signal_coreset");
summary.CorruptionRows = sum(startsWith(string(trialT.TrialType), "corrupted"));
summary.FalseAlarmSweepRows = height(falseAlarmT);
[summary.StatisticallyQualified,summary.StatisticalQualification,summary.PopulationQualification] = ...
    sixgr.phy.pdcch.summarizeDetectorQualification(falseAlarmT,missT);
summary.MissedDetectionSweepRows=height(missT);
summary.QualificationScope="awgn_component_not_nr_conformance";
summary.NRConformanceQualified=false;
summary.LowSNRSweepRows = height(lowSNRT);
summary.OracleGuardViolationCount = sum(logical(oracleT.Violation));
summary.ProxyUsed = any(logical(trialT.ProxyUsed));
summary.Skipped = any(logical(trialT.Skipped));
summary.ToolboxMissing = any(logical(trialT.ToolboxMissing));
end

function caps = localToolboxCapabilities()
caps = struct();
caps.MATLABVersion = string(version);
caps.ToolboxVersion = string(localVer("5g"));
names = ["nrCarrierConfig","nrCORESETConfig","nrSearchSpaceConfig","nrPDCCHConfig", ...
    "nrPDCCHSpace","nrDCIEncode","nrDCIDecode","nrPDCCH","nrPDCCHDecode", ...
    "nrPDCCHDMRS","nrPDCCHDMRSIndices","nrOFDMModulate","nrOFDMDemodulate", ...
    "nrChannelEstimate","nrEqualizeMMSE","awgn"];
for ii = 1:numel(names)
    field = names(ii) + "Available";
    caps.(field) = ~isempty(which(char(names(ii))));
end
caps.StrictModeToolboxFallbackAllowed = false;
caps.GeneratedAt = sixgr.util.utcNowISO8601();
caps.ProducerModule = "sixgr.phy.pdcch.runStrictPDCCHValidation";
end

function txt = localVer(name)
v = ver(char(name));
if isempty(v)
    txt = "";
else
    txt = string(v(1).Version);
end
end

function hash = localDecodedFieldHash(dci)
hash = "";
if isstruct(dci) && isfield(dci, "Fields")
    hash = sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(dci.Fields), "UTF-8")));
end
end

function out = localFirstNonEmpty(values)
values = string(values(:));
idx = find(strlength(values) > 0, 1);
if isempty(idx)
    out = "";
else
    out = values(idx);
end
end

function row = localTrialRow()
row = struct("RunId", "", "ScenarioName", "", "TrialId", NaN, "TrialType", "", ...
    "CellId", NaN, "UEId", NaN, "ConfigHash", "", "Frame", NaN, "Slot", NaN, ...
    "RNTITypeTx", "", "RNTITx", NaN, "RNTIAttempted", NaN, "DCIFormatTx", "", ...
    "DCIFormatAttempted", "", "DCIPayloadSizeBits", NaN, "TxAggregationLevel", NaN, ...
    "TxCandidateIndex", NaN, "TxCCEIndex", NaN, "SelectedAggregationLevel", NaN, ...
    "SelectedCandidateIndex", NaN, "SelectedCCEIndex", NaN, "CandidatesAttempted", NaN, ...
    "CandidatesDecoded", NaN, "DCICrcPass", false, "DCIMask", "", "DCIPayloadHexTx", "", ...
    "DCIPayloadHexRx", "", "DCIPayloadHashTx", "", "DCIPayloadHashRx", "", ...
    "DCIPayloadMatch", false, "DecodedDCIFieldsHash", "", ...
    "ControlResourceValidity", false, "ControlResourceSource", "", "ControlResourceFailureReason", "", ...
    "GrantValid", false, ...
    "GrantType", "", "GrantReferenceId", "", "WrongRNTIRejectCount", NaN, ...
    "NoSignalRejectCount", NaN, "FalseCandidateCount", NaN, ...
    "CorruptedCandidateRejectCount", NaN, "InvalidGrantRejectCount", NaN, ...
    "DetectionMetric", NaN, "BestCandidateMetric", NaN, "SecondBestCandidateMetric", NaN, ...
    "MetricMargin", NaN, "NoiseVariance", NaN, "NoiseSeed", NaN, "NoiseSubstream", NaN, ...
    "SignalEnergyPerOccupiedRE", NaN, "AppliedGridNoiseVariance", NaN, ...
    "AppliedSampleNoiseVariance", NaN, "SampleToGridNoiseVarianceGain", NaN, ...
    "SNRReferencePlane", "", "NoiseCalibrationSource", "", ...
    "ReceiverNoiseVarianceSource", "", "GeneratedNoiseSuppliedToReceiver", false, ...
    "ScoringMeasuredGridNoiseVariance", NaN, "ScoringNoiseComparedRECount", 0, ...
    "NoiseGenerator", "", "SNRdB", NaN, "ChannelModel", "", ...
    "ProxyUsed", false, "Skipped", false, "ToolboxMissing", false, "UsedOracleFields", "", ...
    "StrictOk", false, "NegativeExpectedOk", false, "Status", "", "FailureReason", "");
end

function row = localCandidateRow()
row = struct("RunId", "", "TrialId", NaN, "CandidateIndex", NaN, "AggregationLevel", NaN, ...
    "CCEIndex", NaN, "CORESETId", NaN, "SearchSpaceId", NaN, "RNTIAttempted", NaN, ...
    "ExpectedRNTI", NaN, "DCIFormatAttempted", "", "CrcPass", false, "Mask", "", ...
    "PayloadHash", "", "DecodedPayloadHex", "", "GrantValid", false, ...
    "DecodeAttempted", false, "Metric", NaN, ...
    "LLRMeanAbs", NaN, "LLRMin", NaN, "LLRMax", NaN, "LLRCount", 0, "SelectedCandidate", false, ...
    "RejectedReason", "");
end

function row = localDCIFieldRow()
row = struct("RunId", "", "TrialId", NaN, "Direction", "", "DCIFormat", "", ...
    "RNTIType", "", "FieldName", "", "TxValue", "", "RxValue", "", "Equal", false, ...
    "BitOffsetStart", NaN, "BitOffsetEnd", NaN, "Status", "");
end

function row = localGrantRow()
row = struct("RunId", "", "TrialId", NaN, "GrantReferenceId", "", "GrantType", "", ...
    "DCIFormat", "", "RNTIType", "", "FrequencyResourceAssignment", NaN, ...
    "TimeResourceAssignment", NaN, "PRBStart", NaN, "NumPRB", NaN, "SymbolStart", NaN, ...
    "NumSymbols", NaN, "MCS", NaN, "Modulation", "", "TBS", NaN, "HARQProcess", NaN, ...
    "NDI", NaN, "RV", NaN, "TPC", NaN, "PUCCHResourceIndicator", NaN, ...
    "PDSCHToHARQFeedbackTiming", NaN, "Valid", false, "FailureReason", "");
end

function row = localFalseAlarmRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", "NoiseModel", "", "SNRdB", NaN, ...
    "QualificationContextHash","","QualificationScope","", ...
    "PlannedOperatingPointCount",NaN,"JointOperatingPointCount",NaN,"PerPointConfidenceLevel",NaN, ...
    "NumTrials", NaN, "WaveformTrialCount", NaN, "NumCandidatesPerTrial", NaN, ...
    "CandidateDecisionCount", NaN, "NumFalseCandidates", NaN, ...
    "FalseAlarmWaveformCount",NaN,"CandidateFalseAlarmFraction",NaN, ...
    "FalseAlarmProbability", NaN, "TargetFalseAlarmProbability", NaN, ...
    "CILower", NaN, "CIUpper", NaN, "CIWidth", NaN, "CIWidthTarget", NaN, ...
    "ConfidenceLevel", NaN, "EffectiveDirectionalConfidenceLevel", NaN, ...
    "AlphaSpentThisLook", NaN, "IntervalMethod", "", "SequentialDesign", "", ...
    "LookIndex", NaN, "PlannedLooks", NaN, "MinimumCandidateDecisions", NaN, ...
    "MaximumWaveformTrials", NaN, "MinimumFalseAlarmEvents", NaN, ...
    "PointEstimatePass", false, "StatisticalQualification", "NOT_EVALUATED", ...
    "StatisticallyQualified", false, "StoppingReason", "", ...
    "DeterministicSeedCount", NaN, "DeterministicSeedSet", "", "SeedDerivation", "", ...
    "EvidenceUnit", "independent_noise_only_waveform", "Status", "NOT_EVALUATED");
end

function row=localMissedDetectionRow()
row=struct('RunId',"",'SweepId',"",'ConfigHash',"",'QualificationContextHash',"", ...
    'QualificationScope',"awgn_component_not_nr_conformance",'ChannelModel',"AWGN", ...
    'PlannedOperatingPointCount',NaN,'JointOperatingPointCount',NaN, ...
    'SNRdB',NaN,'DCIFormat',"",'AggregationLevel',NaN,'TxDimensions',NaN,'RxDimensions',NaN, ...
    'WaveformTrialCount',0,'MissedGrantCount',0,'DeliveredGrantCount',0,'CRCFailureCount',0, ...
    'FalseCandidateCount',0,'MissedGrantProbability',NaN,'TargetMissedGrantProbability',NaN, ...
    'ConfidenceLevel',NaN,'PerPointConfidenceLevel',NaN,'CILower',NaN,'CIUpper',NaN, ...
    'CIWidth',NaN,'CIWidthTarget',NaN,'EffectiveDirectionalConfidenceLevel',NaN, ...
    'AlphaSpentThisLook',NaN,'IntervalMethod',"",'SequentialDesign',"", ...
    'LookIndex',NaN,'PlannedLooks',NaN,'MinimumTrials',NaN,'MaximumTrials',NaN,'MinimumEvents',NaN, ...
    'PointEstimatePass',false,'StatisticallyQualified',false,'StatisticalQualification',"NOT_EVALUATED", ...
    'StoppingReason',"",'Status',"NOT_EVALUATED",'DeterministicSeedSet',"", ...
    'EvidenceUnit',"independent_signal_present_waveform");
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

function row = localLowSNRRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", "SNRdB", NaN, ...
    "NumTrials", NaN, "NumDetected", NaN, "NumCrcPass", NaN, "DetectionProbability", NaN, ...
    "CrcPassProbability", NaN, "DetectionCILower", NaN, "DetectionCIUpper", NaN, ...
    "CrcPassCILower", NaN, "CrcPassCIUpper", NaN, "ConfidenceLevel", NaN, ...
    "IntervalMethod", "", "EvidenceUnit", "pdcch_waveform_trial", ...
    "MeanMetricMargin", NaN, "Status", "");
end

function row = localOracleRow()
row = struct("RunId", "", "TrialId", NaN, "Stage", "", "OracleFieldName", "", ...
    "WasAccessed", false, "Allowed", false, "Violation", false, "Status", "");
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
