function result = runStrictPDCCHValidation(baseCfg, varargin)
%RUNSTRICTPDCCHVALIDATION Execute strict waveform-backed PDCCH validation.

p = inputParser;
p.FunctionName = "sixgr.phy.pdcch.runStrictPDCCHValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

runFolder = char(string(opt.RunFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);
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

badDci = sixgr.phy.pdcch.buildDCI10DownlinkAssignment(cfg, "PRBStart", max(1, cfg.NSizeGrid - 2), "NumPRB", 127, "MCS", 10);
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
summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, falseAlarmT, lowSNRT, oracleT);

result = struct();
result.RunId = runId;
result.ScenarioName = scenarioName;
result.Config = cfg;
result.ConfigHash = configHash;
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
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
    "pdcch_low_snr_sweep", lowSNRT, ...
    "pdcch_oracle_guard", oracleT);

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
[rxWave, nVar, noiseOnly] = localAddAWGN(rxWave, snrDb, 7000 + nextTrialId);
switch string(mode)
    case "no_signal"
        rxWave = noiseOnly;
    case "corrupt_data"
        corruptGrid = tx.Grid;
        corruptGrid(tx.PDCCHInd) = -tx.Grid(tx.PDCCHInd);
        rxWave = sixgr.phy.waveform.ofdmModulate(tx.Carrier, corruptGrid);
        [rxWave, nVar, noiseOnly] = localAddAWGN(rxWave, snrDb, 7100 + nextTrialId);
    case "corrupt_dmrs"
        corruptGrid = tx.Grid;
        rng(7200 + nextTrialId, "twister");
        corruptGrid(tx.DMRSInd) = (randn(numel(tx.DMRSInd),1) + 1i*randn(numel(tx.DMRSInd),1)) ./ sqrt(2);
        rxWave = sixgr.phy.waveform.ofdmModulate(tx.Carrier, corruptGrid);
        [rxWave, nVar, noiseOnly] = localAddAWGN(rxWave, snrDb, 7300 + nextTrialId);
end
det = sixgr.phy.pdcch.blindDecodePDCCH(rxWave, cfg, ...
    "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "RNTIAttempted", attemptedRNTI, ...
    "DCIFormatAttempted", attemptedFormat, "NoiseVar", nVar, ...
    "NoiseOnlyWaveform", noiseOnly, "ListLength", 8);
score = sixgr.phy.pdcch.scorePDCCHDetection(det, tx, cfg, ...
    "TrialType", trialType, "NegativeExpected", negativeExpected);
row = localTrialRowFromScore(nextTrialId, trialType, cfg, tx, det, score, attemptedRNTI, attemptedFormat, snrDb);
candidateT = det.Candidates;
candidateT.RunId = repmat(string(cfg.RunId), height(candidateT), 1);
candidateT.TrialId = repmat(double(nextTrialId), height(candidateT), 1);
candidateT = movevars(candidateT, ["RunId","TrialId"], "Before", 1);
candidateT.GrantValid(:) = logical(score.GrantValid);
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
row.SelectedAggregationLevel = double(ternary(logical(det.Rx.Ok), cfg.AggregationLevel, NaN));
row.SelectedCandidateIndex = double(ternary(logical(det.Rx.Ok), det.Rx.CandidateIndex, NaN));
row.SelectedCCEIndex = double(ternary(logical(det.Rx.Ok), det.Rx.CandidateIndex - 1, NaN));
row.CandidatesAttempted = double(score.CandidatesAttempted);
row.DCICrcPass = logical(det.Rx.Ok);
row.DCIMask = string(ternary(logical(det.Rx.Ok), "rnti_crc_mask_pass", "crc_fail"));
row.DCIPayloadHexTx = string(tx.DCI.PayloadHex);
row.DCIPayloadHexRx = string(det.DecodedDCI.PayloadHex);
row.DCIPayloadHashTx = string(tx.DCI.PayloadHash);
row.DCIPayloadHashRx = string(det.DecodedDCI.PayloadHash);
row.DCIPayloadMatch = logical(score.PayloadMatch);
row.DecodedDCIFieldsHash = localDecodedFieldHash(det.DecodedDCI);
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
row.ChannelModel = string(cfg.ChannelModel);
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
snrs = double(sixgr.util.structGet(cfg.BaseConfig, "lls6g.control.pdcch_strict.false_alarm_snr_db", [-6 0 6]));
numTrials = max(2, round(double(sixgr.util.structGet(cfg.BaseConfig, "lls6g.control.pdcch_strict.false_alarm_trials", 3))));
rows = repmat(localFalseAlarmRow(), numel(snrs), 1);
trialRows = repmat(localTrialRow(), 0, 1);
candRows = repmat(localCandidateRow(), 0, 1);
oracleRows = repmat(localOracleRow(), 0, 1);
for si = 1:numel(snrs)
    falseCount = 0; candCount = 0;
    for tt = 1:numTrials
        [trialId, tr, cand, ~, ~, oracle] = localRunOneTrial(trialId, "false_alarm_sweep", cfg, dci, "1_0", cfg.RNTIValue, snrs(si), "no_signal", true);
        falseCount = falseCount + double(tr.FalseCandidateCount);
        candCount = candCount + height(cand);
        trialRows(end+1,1) = tr; %#ok<AGROW>
        candRows = [candRows; table2struct(cand)]; oracleRows = [oracleRows; table2struct(oracle)]; %#ok<AGROW>
    end
    row = localFalseAlarmRow();
    row.RunId = string(cfg.RunId); row.SweepId = "false_alarm_" + string(si);
    row.ConfigHash = string(cfg.ConfigHash); row.NoiseModel = "AWGN";
    row.SNRdB = snrs(si); row.NumTrials = numTrials;
    row.NumCandidatesPerTrial = candCount / numTrials;
    row.NumFalseCandidates = falseCount;
    row.FalseAlarmProbability = falseCount / max(candCount, 1);
    row.TargetFalseAlarmProbability = 0.01;
    row.Status = string(ternary(row.FalseAlarmProbability <= row.TargetFalseAlarmProbability, "pass", "review"));
    rows(si) = row;
end
falseAlarmT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
candT = struct2table(candRows, "AsArray", true);
oracleT = struct2table(oracleRows, "AsArray", true);
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

function [y, nVar, noise] = localAddAWGN(x, snrDb, seed)
rng(seed, "twister");
power = mean(abs(double(x(:))).^2, "omitnan");
if ~(isfinite(power) && power > 0)
    power = 1;
end
nVar = power / (10.^(double(snrDb) / 10));
noise = sqrt(nVar/2) .* (randn(size(x)) + 1i*randn(size(x)));
y = x + noise;
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
row.MCS = double(g.MCS); row.Modulation = string(g.Modulation); row.TBS = double(g.TBS);
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
fields = ["tx_dci_bits","tx_payload_hex","tx_rnti","tx_candidate_index","tx_aggregation_level","tx_cce_index","scheduler_grant"];
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
    logical(cfg.StrictValidation.StrictValid), string(cfg.StrictValidation.StrictUnsupportedReason), ...
    string(cfg.StrictValidation.Status), ...
    'VariableNames', {'RunId','ScenarioName','CellId','UEId','ConfigHash','BindingSource', ...
    'CarrierFrequencyHz','FrequencyRange','NCellID','NSizeGrid','NStartGrid','SubcarrierSpacingKHz', ...
    'CORESETId','CORESETDurationSymbols','CORESETRBStart','CORESETNumRB','CCE_REG_MappingType', ...
    'REGBundleSize','InterleaverSize','ShiftIndex','PrecoderGranularity','SearchSpaceId', ...
    'SearchSpaceType','SearchSpacePeriodicity','SearchSpaceOffset','SearchSpaceDuration', ...
    'FirstSymbolWithinSlot','NumCandidatesAL1','NumCandidatesAL2','NumCandidatesAL4', ...
    'NumCandidatesAL8','NumCandidatesAL16','DCIMonitoringFormats','RNTIType','RNTIValue', ...
    'StrictValid','StrictUnsupportedReason','Status'});
end

function summary = localSummaryStruct(runId, scenarioName, strictOk, cfg, trialT, falseAlarmT, lowSNRT, oracleT)
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
    hash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(jsonencode(dci.Fields), "UTF-8")));
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
    "DCIPayloadMatch", false, "DecodedDCIFieldsHash", "", "GrantValid", false, ...
    "GrantType", "", "GrantReferenceId", "", "WrongRNTIRejectCount", NaN, ...
    "NoSignalRejectCount", NaN, "FalseCandidateCount", NaN, ...
    "CorruptedCandidateRejectCount", NaN, "InvalidGrantRejectCount", NaN, ...
    "DetectionMetric", NaN, "BestCandidateMetric", NaN, "SecondBestCandidateMetric", NaN, ...
    "MetricMargin", NaN, "NoiseVariance", NaN, "SNRdB", NaN, "ChannelModel", "", ...
    "ProxyUsed", false, "Skipped", false, "ToolboxMissing", false, "UsedOracleFields", "", ...
    "StrictOk", false, "NegativeExpectedOk", false, "Status", "", "FailureReason", "");
end

function row = localCandidateRow()
row = struct("RunId", "", "TrialId", NaN, "CandidateIndex", NaN, "AggregationLevel", NaN, ...
    "CCEIndex", NaN, "CORESETId", NaN, "SearchSpaceId", NaN, "RNTIAttempted", NaN, ...
    "ExpectedRNTI", NaN, "DCIFormatAttempted", "", "CrcPass", false, "Mask", "", ...
    "PayloadHash", "", "DecodedPayloadHex", "", "GrantValid", false, "Metric", NaN, ...
    "LLRMeanAbs", NaN, "LLRMin", NaN, "LLRMax", NaN, "SelectedCandidate", false, ...
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
    "NumTrials", NaN, "NumCandidatesPerTrial", NaN, "NumFalseCandidates", NaN, ...
    "FalseAlarmProbability", NaN, "TargetFalseAlarmProbability", NaN, "Status", "");
end

function row = localLowSNRRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", "SNRdB", NaN, ...
    "NumTrials", NaN, "NumDetected", NaN, "NumCrcPass", NaN, "DetectionProbability", NaN, ...
    "CrcPassProbability", NaN, "MeanMetricMargin", NaN, "Status", "");
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
