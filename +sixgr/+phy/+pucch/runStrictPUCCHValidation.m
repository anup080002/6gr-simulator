function result = runStrictPUCCHValidation(baseCfg, varargin)
%RUNSTRICTPUCCHVALIDATION Execute waveform-backed PUCCH resource/UCI validation.
% Keep this file ASCII-only.

p = inputParser;
p.FunctionName = "sixgr.phy.pucch.runStrictPUCCHValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "pucch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "pucch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

runFolder = char(string(opt.RunFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);
highSNR = max(30, double(sixgr.util.structGet(baseCfg, "channel.snr_dB", 30)));
baseCfg = localControlValidationChannelCfg(baseCfg);
rnti = double(sixgr.util.structGet(baseCfg, "phy.rnti", ...
    sixgr.util.structGet(baseCfg, "lls6g.control.pdcch_strict.rnti_value", 4660)));
if ~(isfinite(rnti) && rnti > 0)
    rnti = 4660;
end

trialRows = repmat(localTrialRow(), 0, 1);
trialId = 0;

[trialId, row] = localRunPositiveTrial(trialId, "positive_format0_sr", baseCfg, ...
    int8(1), 0, highSNR, rnti, runId, scenarioName);
trialRows(end+1, 1) = row; %#ok<AGROW>

[trialId, row] = localRunPositiveTrial(trialId, "positive_format1_harq_ack", baseCfg, ...
    int8(1), 1, highSNR, rnti, runId, scenarioName);
trialRows(end+1, 1) = row; %#ok<AGROW>

[trialId, row] = localRunPositiveTrial(trialId, "positive_format1_harq_nack", baseCfg, ...
    int8(0), 1, highSNR, rnti, runId, scenarioName);
trialRows(end+1, 1) = row; %#ok<AGROW>

csiBits = int8(mod((0:19).', 2));
[trialId, row] = localRunPositiveTrial(trialId, "positive_format2_csi_part1", baseCfg, ...
    csiBits, 2, highSNR, rnti, runId, scenarioName);
trialRows(end+1, 1) = row; %#ok<AGROW>

[trialId, row] = localRunNoSignalTrial(trialId, "no_signal_format0_false_alarm", baseCfg, ...
    int8(1), 0, highSNR, rnti, runId, scenarioName);
trialRows(end+1, 1) = row; %#ok<AGROW>

trialT = struct2table(trialRows, "AsArray", true);
resourceT = localResourceMappingTable(trialT);
falseAlarmT = trialT(contains(string(trialT.TrialType), "no_signal"), :);
summaryT = localSummaryTable(runId, scenarioName, trialT);

positiveMask = startsWith(string(trialT.TrialType), "positive");
negativeMask = logical(trialT.NegativeExpected);
positiveOk = any(positiveMask) && all(logical(trialT.StrictOk(positiveMask)));
negativeOk = ~any(negativeMask) || all(logical(trialT.NegativeExpectedOk(negativeMask)));
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
strictOk = positiveOk && negativeOk && noProxySkip && height(resourceT) == height(trialT);

result = struct();
result.RunId = runId;
result.ScenarioName = scenarioName;
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
result.FailureReason = string(ternary(strictOk, "", "strict_pucch_validation_failed"));
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ArtifactTables = struct( ...
    "pucch_trials", trialT, ...
    "pucch_resource_mapping", resourceT, ...
    "pucch_false_alarm_trials", falseAlarmT, ...
    "pucch_summary", summaryT);

if logical(opt.WriteArtifacts)
    result.ArtifactManifest = sixgr.phy.pucch.exportStrictPUCCHArtifacts(runFolder, result);
else
    result.ArtifactManifest = table();
end
end

function [nextTrialId, row] = localRunPositiveTrial(trialId, trialType, baseCfg, bits, fmt, snrDb, rnti, runId, scenarioName)
nextTrialId = trialId + 1;
cfg = localApplyPUCCHResourceForFormat(baseCfg, fmt);
cfg = sixgr.util.structSet(cfg, "phy.rnti", rnti);
trial = sixgr.link.runPUCCHWaveformTrial(cfg, ...
    "ExpectedUCIBits", bits, ...
    "Format", fmt, ...
    "SNR_dB", snrDb, ...
    "RNTI", rnti, ...
    "TrialIndex", nextTrialId);
row = localTrialRowFromTrial(nextTrialId, trialType, runId, scenarioName, cfg, trial, false);
end

function [nextTrialId, row] = localRunNoSignalTrial(trialId, trialType, baseCfg, bits, fmt, snrDb, rnti, runId, scenarioName)
nextTrialId = trialId + 1;
cfg = localApplyPUCCHResourceForFormat(baseCfg, fmt);
cfg = sixgr.util.structSet(cfg, "phy.rnti", rnti);
[tx, txInfo] = sixgr.phy.ul.PUCCH_Tx(cfg, bits, "Format", fmt, "RNTI", rnti);
signalPower = mean(abs(tx.Waveform(:)).^2, "omitnan");
if ~(isfinite(signalPower) && signalPower > 0)
    signalPower = 1;
end
nVar = signalPower ./ max(10.^(double(snrDb) ./ 10), eps);
rng(9100 + nextTrialId, "twister");
noiseOnly = sqrt(nVar ./ 2) .* (randn(size(tx.Waveform)) + 1i .* randn(size(tx.Waveform)));
[rx, rxInfo] = sixgr.phy.ul.PUCCH_Rx(noiseOnly, cfg, ...
    "Carrier", tx.Carrier, ...
    "PUCCH", tx.PUCCH, ...
    "Format", fmt, ...
    "NumUCIBits", numel(bits), ...
    "ExpectedUCIBits", bits, ...
    "NoiseVar", nVar, ...
    "StrictNoiseVarianceRequired", true);
trial = struct( ...
    "Ok", false, ...
    "Skipped", false, ...
    "Crash", false, ...
    "Status", "PASS", ...
    "ExpectedBits", bits, ...
    "DecodedBits", localNormalizeBits(sixgr.util.structGet(rx, "UCIBits", int8([]))), ...
    "AckObserved", false, ...
    "UCIContentMatch", false, ...
    "CRCApplicable", false, ...
    "CRCOutcome", "not_applicable", ...
    "DetectionOutcome", char(ternary(logical(sixgr.util.structGet(rx, "DetectionUsable", false)), "false_alarm", "dtx_no_false_alarm")), ...
    "BitsCompared", 0, ...
    "BitErrors", NaN, ...
    "DetectionMetric", double(sixgr.util.structGet(rx, "DetectorPeakMetric", NaN)), ...
    "DetectionThreshold", double(sixgr.util.structGet(rx, "DetectionThreshold", NaN)), ...
    "DetectionMetricStatus", char(string(sixgr.util.structGet(rx, "DetectionMetricStatus", ""))), ...
    "DetectorPeakMetric", double(sixgr.util.structGet(rx, "DetectorPeakMetric", NaN)), ...
    "DetectorNoiseFloor", double(sixgr.util.structGet(rx, "DetectorNoiseFloor", nVar)), ...
    "DTXFlag", logical(sixgr.util.structGet(rx, "DTXFlag", true)), ...
    "DTXReason", char(string(sixgr.util.structGet(rx, "DTXReason", ""))), ...
    "ComputeLatency_ms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "AirInterfaceTTI_ms", localAirInterfaceTTI(txInfo), ...
    "NoiseVariance", double(nVar), ...
    "NoiseVarStatus", char(string(sixgr.util.structGet(rx, "NoiseVarStatus", ""))), ...
    "NoiseVarSource", char(string(sixgr.util.structGet(rx, "NoiseVarSource", ""))), ...
    "NoiseVarReason", char(string(sixgr.util.structGet(rx, "NoiseVarReason", ""))), ...
    "NoiseVarStrictFailure", logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false)), ...
    "ReceiverUsable", logical(sixgr.util.structGet(rx, "ReceiverUsable", false)), ...
    "DetectionAttempted", logical(sixgr.util.structGet(rx, "DetectionAttempted", false)), ...
    "DetectionUsable", logical(sixgr.util.structGet(rx, "DetectionUsable", false)), ...
    "FailureReason", char(string(sixgr.util.structGet(rx, "FailureReason", ""))), ...
    "ConfiguredSNR_dB", double(snrDb), ...
    "AppliedAWGNSNR_dB", double(snrDb), ...
    "ReceiverHestSINR_dB", NaN, ...
    "ReceiverHestSINRSource", "", ...
    "ReceiverHestSINRValueRole", "", ...
    "ReceiverHestSINRValueStatus", "", ...
    "ReceiverHestSINRNAReason", "", ...
    "ChannelGain_dB", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "NumRxAntennas", NaN, ...
    "NumTxPorts", size(tx.Waveform, 2), ...
    "RequestedFormat", double(fmt), ...
    "ResolvedFormat", double(fmt), ...
    "FormatAdapted", false, ...
    "FormatAdaptationReason", "", ...
    "ControlResourceValidity", true, ...
    "CrashSource", "", ...
    "CrashMessage", "", ...
    "ChannelModel", "AWGN_NO_SIGNAL", ...
    "DopplerHz", NaN, ...
    "TimingEstimateUsed", false, ...
    "UseIdealTimingSync", false, ...
    "InterferenceMode", "none", ...
    "InterferenceContributorCount", 0, ...
    "InterferenceAggregatedRxPower_dBm", NaN, ...
    "InterferencePowerSource", "", ...
    "FullInterfererChannelTruthUsed", false, ...
    "Tx", tx, ...
    "TxInfo", txInfo, ...
    "Rx", rx, ...
    "RxInfo", rxInfo, ...
    "Notes", "No-signal PUCCH false-alarm check using receiver decode path and noise-only waveform.");
row = localTrialRowFromTrial(nextTrialId, trialType, runId, scenarioName, cfg, trial, true);
end

function row = localTrialRowFromTrial(trialId, trialType, runId, scenarioName, cfg, trial, negativeExpected)
row = localTrialRow();
row.RunId = string(runId);
row.ScenarioName = string(scenarioName);
row.TrialId = double(trialId);
row.TrialType = string(trialType);
row.Direction = "UL";
row.SignalFamily = "PUCCH";
row.ControlStage = "PUCCH_UCI";
row.CellId = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", NaN));
row.UEId = 1;
row.RNTI = double(sixgr.util.structGet(cfg, "phy.rnti", NaN));
row.Frame = 0;
row.Slot = 0;
row.RequestedFormat = double(sixgr.util.structGet(trial, "RequestedFormat", NaN));
row.ResolvedFormat = double(sixgr.util.structGet(trial, "ResolvedFormat", NaN));
row.PUCCHFormat = row.ResolvedFormat;
row.FormatAdapted = logical(sixgr.util.structGet(trial, "FormatAdapted", false));
row.FormatAdaptationReason = string(sixgr.util.structGet(trial, "FormatAdaptationReason", ""));
row.ExpectedBits = localBitsToString(sixgr.util.structGet(trial, "ExpectedBits", int8([])));
row.DecodedBits = localBitsToString(sixgr.util.structGet(trial, "DecodedBits", int8([])));
expectedBits = localNormalizeBits(sixgr.util.structGet(trial, "ExpectedBits", int8([])));
decodedBits = localNormalizeBits(sixgr.util.structGet(trial, "DecodedBits", int8([])));
row.ExpectedBitCount = double(sixgr.util.structGet(trial, "ExpectedBitCount", numel(expectedBits)));
row.DecodedBitCount = double(sixgr.util.structGet(trial, "DecodedBitCount", numel(decodedBits)));
row.UCIExpectedBitVector = string(sixgr.util.structGet(trial, "UCIExpectedBitVector", localBitsToDelimitedString(expectedBits)));
row.UCIDecodedBitVector = string(sixgr.util.structGet(trial, "UCIDecodedBitVector", localBitsToDelimitedString(decodedBits)));
row.UCIBitErrorVector = string(sixgr.util.structGet(trial, "UCIBitErrorVector", localBitErrorVectorString(expectedBits, decodedBits)));
row.UCICodedBitCount = double(sixgr.util.structGet(trial, "UCICodedBitCount", localPUCCHUCICodedBitCount(trial, row.ResolvedFormat)));
row.UCICRCBitCount = double(sixgr.util.structGet(trial, "UCICRCBitCount", localPUCCHUCICRCBitCount(row.ExpectedBitCount, row.ResolvedFormat)));
row.UCICRCApplicable = logical(sixgr.util.structGet(trial, "UCICRCApplicable", row.UCICRCBitCount > 0));
row.BitsCompared = double(sixgr.util.structGet(trial, "BitsCompared", NaN));
row.BitErrors = double(sixgr.util.structGet(trial, "BitErrors", NaN));
row.UCIContentMatch = logical(sixgr.util.structGet(trial, "UCIContentMatch", false));
row.ExpectedAck = localFirstBit(sixgr.util.structGet(trial, "ExpectedBits", int8([])));
row.ObservedAck = logical(sixgr.util.structGet(trial, "AckObserved", false));
row.CRCApplicable = logical(sixgr.util.structGet(trial, "CRCApplicable", row.UCICRCApplicable));
if row.CRCApplicable
    row.CRCPass = double(logical(sixgr.util.structGet(trial, "Ok", false)));
else
    row.CRCPass = NaN;
end
row.CRCOutcome = string(sixgr.util.structGet(trial, "CRCOutcome", ""));
row.DetectionOutcome = string(sixgr.util.structGet(trial, "DetectionOutcome", ""));
row.DetectionMetric = double(sixgr.util.structGet(trial, "DetectionMetric", NaN));
row.DetectionThreshold = double(sixgr.util.structGet(trial, "DetectionThreshold", NaN));
row.DetectionMetricStatus = string(sixgr.util.structGet(trial, "DetectionMetricStatus", ""));
row.DetectorPeakMetric = double(sixgr.util.structGet(trial, "DetectorPeakMetric", NaN));
row.DetectorNoiseFloor = double(sixgr.util.structGet(trial, "DetectorNoiseFloor", NaN));
row.DTXFlag = logical(sixgr.util.structGet(trial, "DTXFlag", false));
row.DTXReason = string(sixgr.util.structGet(trial, "DTXReason", ""));
row.NoiseVariance = double(sixgr.util.structGet(trial, "NoiseVariance", NaN));
row.NoiseVarStatus = string(sixgr.util.structGet(trial, "NoiseVarStatus", ""));
row.NoiseVarSource = string(sixgr.util.structGet(trial, "NoiseVarSource", ""));
row.NoiseVarReason = string(sixgr.util.structGet(trial, "NoiseVarReason", ""));
row.NoiseVarStrictFailure = logical(sixgr.util.structGet(trial, "NoiseVarStrictFailure", false));
row.ReceiverUsable = logical(sixgr.util.structGet(trial, "ReceiverUsable", false));
row.DetectionAttempted = logical(sixgr.util.structGet(trial, "DetectionAttempted", false));
row.DetectionUsable = logical(sixgr.util.structGet(trial, "DetectionUsable", false));
row.FailureReason = string(sixgr.util.structGet(trial, "FailureReason", ""));
row.ConfiguredSNR_dB = double(sixgr.util.structGet(trial, "ConfiguredSNR_dB", NaN));
row.AppliedAWGNSNR_dB = double(sixgr.util.structGet(trial, "AppliedAWGNSNR_dB", NaN));
row.ReceiverHestSINR_dB = double(sixgr.util.structGet(trial, "ReceiverHestSINR_dB", NaN));
row.ReceiverHestSINRSource = string(sixgr.util.structGet(trial, "ReceiverHestSINRSource", ""));
row.ChannelGain_dB = double(sixgr.util.structGet(trial, "ChannelGain_dB", NaN));
row.ConditionNumber_dB = double(sixgr.util.structGet(trial, "ConditionNumber_dB", NaN));
row.NumRxAntennas = double(sixgr.util.structGet(trial, "NumRxAntennas", NaN));
row.NumTxPorts = double(sixgr.util.structGet(trial, "NumTxPorts", NaN));
row.AirInterfaceTTI_ms = double(sixgr.util.structGet(trial, "AirInterfaceTTI_ms", NaN));
row.ComputeLatency_ms = double(sixgr.util.structGet(trial, "ComputeLatency_ms", NaN));
row.DecodeLatency_ms = double(sixgr.util.structGet(trial, "DecodeLatency_ms", NaN));
row.ChannelModel = string(sixgr.util.structGet(trial, "ChannelModel", ""));
row.DopplerHz = double(sixgr.util.structGet(trial, "DopplerHz", NaN));
row.TimingEstimateUsed = logical(sixgr.util.structGet(trial, "TimingEstimateUsed", false));
row.UseIdealTimingSync = logical(sixgr.util.structGet(trial, "UseIdealTimingSync", false));
row.InterferenceMode = string(sixgr.util.structGet(trial, "InterferenceMode", "none"));
row.InterferenceContributorCount = double(sixgr.util.structGet(trial, "InterferenceContributorCount", 0));
row.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(trial, "FullInterfererChannelTruthUsed", false));
row.ControlResourceValidity = logical(sixgr.util.structGet(trial, "ControlResourceValidity", false));

tx = sixgr.util.structGet(trial, "Tx", struct());
txInfo = sixgr.util.structGet(trial, "TxInfo", struct());
pucch = sixgr.util.structGet(tx, "PUCCH", []);
row.PUCCHResourceId = localResourceId(cfg, pucch);
row.PUCCHPRBSet = localNumericVectorToString(localObjectProperty(pucch, "PRBSet", []));
row.PUCCHPRBStart = localFirstNumeric(localObjectProperty(pucch, "PRBSet", []), NaN);
row.PUCCHPRBCount = double(numel(localObjectProperty(pucch, "PRBSet", [])));
row.PUCCHSymbolStart = localFirstNumeric(localObjectProperty(pucch, "SymbolAllocation", []), NaN);
symAlloc = localObjectProperty(pucch, "SymbolAllocation", []);
if numel(symAlloc) >= 2
    row.PUCCHNumSymbols = double(symAlloc(2));
else
    row.PUCCHNumSymbols = NaN;
end
row.FrequencyHopping = string(localObjectProperty(pucch, "FrequencyHopping", ""));
row.SecondHopStartPRB = localScalarNumeric(localObjectProperty(pucch, "SecondHopStartPRB", []));
row.InitialCyclicShift = localScalarNumeric(localObjectProperty(pucch, "InitialCyclicShift", []));
row.OCCI = localScalarNumeric(localObjectProperty(pucch, "OCCI", []));
row.SpreadingFactor = localScalarNumeric(localObjectProperty(pucch, "SpreadingFactor", []));
row.NID = localScalarNumeric(localObjectProperty(pucch, "NID", []));
row.NID0 = localScalarNumeric(localObjectProperty(pucch, "NID0", []));
row.RNTIOnPUCCHObject = localScalarNumeric(localObjectProperty(pucch, "RNTI", []));
row.PUCCHRECount = double(numel(sixgr.util.structGet(tx, "PUCCHIndices", [])));
row.DMRSRECount = double(numel(sixgr.util.structGet(tx, "DMRSIndices", [])));
row.ReceiverHestSINRApplicable = logical(sixgr.util.structGet(trial, "ReceiverHestSINRApplicable", row.DMRSRECount > 0));
grid = sixgr.util.structGet(tx, "Grid", []);
wave = sixgr.util.structGet(tx, "Waveform", []);
row.GridNonzeroRECount = double(nnz(abs(grid(:)) > 0));
row.WaveformSampleCount = double(size(wave, 1));
row.SampleRateHz = localSampleRate(txInfo);
row.GridHash = localComplexHash(grid);
row.WaveformHash = localComplexHash(wave);

isOk = logical(sixgr.util.structGet(trial, "Ok", false)) && row.UCIContentMatch;
row.NegativeExpected = logical(negativeExpected);
if row.NegativeExpected
    row.NegativeExpectedOk = ~logical(row.DetectionUsable);
    row.StrictOk = row.NegativeExpectedOk;
else
    row.NegativeExpectedOk = false;
    row.StrictOk = isOk && logical(row.ControlResourceValidity) && row.BitsCompared == row.ExpectedBitCount;
end
row.ProxyUsed = false;
row.Skipped = logical(sixgr.util.structGet(trial, "Skipped", false));
row.ToolboxMissing = false;
row.Crash = logical(sixgr.util.structGet(trial, "Crash", false));
row.CrashSource = string(sixgr.util.structGet(trial, "CrashSource", ""));
row.CrashMessage = string(sixgr.util.structGet(trial, "CrashMessage", ""));
row.Status = string(ternary(row.StrictOk, "PASS", "FAIL"));
row.Notes = string(sixgr.util.structGet(trial, "Notes", ""));
end

function cfgOut = localApplyPUCCHResourceForFormat(cfg, fmt)
cfgOut = cfg;
fmt = max(0, round(double(fmt)));
cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.format", fmt);
resources = sixgr.util.structGet(cfgOut, "lls6g.pucch_resources.resources", struct([]));
resource = localFindResource(resources, fmt);
if isempty(resource)
    switch fmt
        case 0
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.PRBSet", 1);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.SymbolAllocation", [12 2]);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.InitialCyclicShift", 0);
        case 1
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.PRBSet", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.SymbolAllocation", [10 4]);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.InitialCyclicShift", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.OCCIndex", 0);
        otherwise
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.PRBSet", 2:5);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.SymbolAllocation", [8 2]);
    end
    cfgOut = sixgr.util.structSet(cfgOut, "validation.pucch_resources.default_resource_id", fmt);
    return;
end

prbStart = double(sixgr.util.structGet(resource, "starting_prb", NaN));
numPRB = double(sixgr.util.structGet(resource, "num_prb", 1));
symbolStart = double(sixgr.util.structGet(resource, "symbol_start", NaN));
numSymbols = double(sixgr.util.structGet(resource, "num_symbols", NaN));
if isfinite(prbStart) && isfinite(numPRB) && numPRB >= 1
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.PRBSet", prbStart + (0:max(round(numPRB)-1, 0)));
end
if isfinite(symbolStart) && isfinite(numSymbols) && numSymbols >= 1
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pucch.SymbolAllocation", [symbolStart numSymbols]);
end
cfgOut = localSetIfPresent(cfgOut, "phy.pucch.InitialCyclicShift", sixgr.util.structGet(resource, "initial_cyclic_shift", []));
cfgOut = localSetIfPresent(cfgOut, "phy.pucch.OCCLength", sixgr.util.structGet(resource, "occ_length", []));
cfgOut = localSetIfPresent(cfgOut, "phy.pucch.OCCIndex", sixgr.util.structGet(resource, "occ_index", []));
cfgOut = localSetIfPresent(cfgOut, "phy.pucch.SecondHopPRB", sixgr.util.structGet(resource, "second_hop_prb", []));
cfgOut = localSetIfPresent(cfgOut, "phy.pucch.IntraSlotFrequencyHopping", sixgr.util.structGet(resource, "intra_slot_frequency_hopping", []));
cfgOut = localSetIfPresent(cfgOut, "validation.pucch_resources.default_resource_id", sixgr.util.structGet(resource, "resource_id", []));
cfgOut = localSetIfPresent(cfgOut, "validation.pucch_resources.default_feedback_type", sixgr.util.structGet(resource, "feedback_type", []));
end

function cfg = localControlValidationChannelCfg(cfg)
cfg = sixgr.util.structSet(cfg, "channel.model", "AWGN");
cfg = sixgr.util.structSet(cfg, "channel.awgnOnly", true);
cfg = sixgr.util.structSet(cfg, "channel.doppler_Hz", 0);
cfg = sixgr.util.structSet(cfg, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
cfg = sixgr.util.structSet(cfg, "run.interferenceExecutionMode", "none");
cfg = sixgr.util.structSet(cfg, "phy.pucch.DTXThreshold", 0.8);
end

function resource = localFindResource(resources, fmt)
resource = [];
if isempty(resources)
    return;
end
if iscell(resources)
    try
        resources = [resources{:}];
    catch
        resources = struct([]);
    end
end
for i = 1:numel(resources)
    rfmt = double(sixgr.util.structGet(resources(i), "format", NaN));
    if isfinite(rfmt) && round(rfmt) == round(fmt)
        resource = resources(i);
        return;
    end
end
end

function cfg = localSetIfPresent(cfg, path, value)
if isempty(value)
    return;
end
cfg = sixgr.util.structSet(cfg, path, value);
end

function T = localResourceMappingTable(trialT)
if ~(istable(trialT) && ~isempty(trialT))
    T = table();
    return;
end
cols = ["RunId","ScenarioName","TrialId","TrialType","PUCCHFormat","PUCCHResourceId", ...
    "PUCCHPRBSet","PUCCHPRBStart","PUCCHPRBCount","PUCCHSymbolStart","PUCCHNumSymbols", ...
    "FrequencyHopping","SecondHopStartPRB","InitialCyclicShift","OCCI","SpreadingFactor", ...
    "NID","NID0","RNTIOnPUCCHObject","PUCCHRECount","DMRSRECount","GridNonzeroRECount", ...
    "WaveformSampleCount","SampleRateHz","GridHash","WaveformHash","ControlResourceValidity"];
T = trialT(:, cols);
end

function T = localSummaryTable(runId, scenarioName, trialT)
if ~(istable(trialT) && ~isempty(trialT))
    T = table();
    return;
end
strictPass = logical(trialT.StrictOk);
positiveMask = startsWith(string(trialT.TrialType), "positive");
negativeMask = logical(trialT.NegativeExpected);
T = table(string(runId), string(scenarioName), height(trialT), ...
    sum(positiveMask), sum(strictPass & positiveMask), sum(negativeMask), ...
    sum(logical(trialT.NegativeExpectedOk) & negativeMask), ...
    sum(logical(trialT.Crash)), sum(logical(trialT.ProxyUsed)), ...
    all(strictPass), ...
    'VariableNames', {'RunId','ScenarioName','TrialCount','PositiveTrialCount', ...
    'PositivePassCount','NegativeTrialCount','NegativePassCount','CrashCount', ...
    'ProxyUsedCount','StrictOk'});
end

function row = localTrialRow()
row = struct( ...
    "RunId", "", "ScenarioName", "", "TrialId", NaN, "TrialType", "", ...
    "Direction", "", "SignalFamily", "", "ControlStage", "", ...
    "CellId", NaN, "UEId", NaN, "RNTI", NaN, "Frame", NaN, "Slot", NaN, ...
    "RequestedFormat", NaN, "ResolvedFormat", NaN, "PUCCHFormat", NaN, ...
    "FormatAdapted", false, "FormatAdaptationReason", "", ...
    "ExpectedBits", "", "DecodedBits", "", "ExpectedBitCount", NaN, "DecodedBitCount", NaN, ...
    "UCIExpectedBitVector", "", "UCIDecodedBitVector", "", "UCIBitErrorVector", "", ...
    "UCICodedBitCount", NaN, "UCICRCBitCount", NaN, "UCICRCApplicable", false, ...
    "BitsCompared", NaN, "BitErrors", NaN, "UCIContentMatch", false, ...
    "ExpectedAck", false, "ObservedAck", false, ...
    "CRCApplicable", false, "CRCPass", NaN, "CRCOutcome", "", ...
    "DetectionOutcome", "", "DetectionMetric", NaN, "DetectionThreshold", NaN, ...
    "DetectionMetricStatus", "", "DetectorPeakMetric", NaN, "DetectorNoiseFloor", NaN, ...
    "DTXFlag", false, "DTXReason", "", ...
    "NoiseVariance", NaN, "NoiseVarStatus", "", "NoiseVarSource", "", "NoiseVarReason", "", ...
    "NoiseVarStrictFailure", false, "ReceiverUsable", false, "DetectionAttempted", false, ...
    "DetectionUsable", false, "FailureReason", "", ...
    "ConfiguredSNR_dB", NaN, "AppliedAWGNSNR_dB", NaN, ...
    "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRApplicable", false, "ReceiverHestSINRSource", "", ...
    "ChannelGain_dB", NaN, "ConditionNumber_dB", NaN, "NumRxAntennas", NaN, "NumTxPorts", NaN, ...
    "AirInterfaceTTI_ms", NaN, "ComputeLatency_ms", NaN, "DecodeLatency_ms", NaN, ...
    "ChannelModel", "", "DopplerHz", NaN, "TimingEstimateUsed", false, "UseIdealTimingSync", false, ...
    "InterferenceMode", "", "InterferenceContributorCount", NaN, "FullInterfererChannelTruthUsed", false, ...
    "ControlResourceValidity", false, "PUCCHResourceId", "", "PUCCHPRBSet", "", ...
    "PUCCHPRBStart", NaN, "PUCCHPRBCount", NaN, "PUCCHSymbolStart", NaN, "PUCCHNumSymbols", NaN, ...
    "FrequencyHopping", "", "SecondHopStartPRB", NaN, "InitialCyclicShift", NaN, ...
    "OCCI", NaN, "SpreadingFactor", NaN, "NID", NaN, "NID0", NaN, "RNTIOnPUCCHObject", NaN, ...
    "PUCCHRECount", NaN, "DMRSRECount", NaN, "GridNonzeroRECount", NaN, ...
    "WaveformSampleCount", NaN, "SampleRateHz", NaN, "GridHash", "", "WaveformHash", "", ...
    "NegativeExpected", false, "NegativeExpectedOk", false, "StrictOk", false, ...
    "ProxyUsed", false, "Skipped", false, "ToolboxMissing", false, "Crash", false, ...
    "CrashSource", "", "CrashMessage", "", "Status", "FAIL", "Notes", "");
end

function bits = localNormalizeBits(raw)
if iscell(raw) && ~isempty(raw)
    raw = raw{1};
end
if isempty(raw)
    bits = int8([]);
    return;
end
bits = int8(logical(raw(:)));
end

function s = localBitsToString(raw)
bits = localNormalizeBits(raw);
if isempty(bits)
    s = "";
else
    s = string(sprintf("%d", double(bits(:))));
end
end

function s = localBitsToDelimitedString(raw)
bits = localNormalizeBits(raw);
if isempty(bits)
    s = "";
else
    s = "[" + strjoin(string(double(bits(:).')), "|") + "]";
end
end

function s = localBitErrorVectorString(expectedBits, decodedBits)
expectedBits = localNormalizeBits(expectedBits);
decodedBits = localNormalizeBits(decodedBits);
n = max(numel(expectedBits), numel(decodedBits));
if n < 1
    s = "";
    return;
end
errs = ones(n, 1, "int8");
nCompare = min(numel(expectedBits), numel(decodedBits));
if nCompare > 0
    errs(1:nCompare) = int8(expectedBits(1:nCompare) ~= decodedBits(1:nCompare));
end
s = localBitsToDelimitedString(errs);
end

function n = localPUCCHUCICRCBitCount(numBits, resolvedFormat)
numBits = max(0, round(double(numBits)));
resolvedFormat = round(double(resolvedFormat));
if isfinite(resolvedFormat) && resolvedFormat >= 2 && numBits >= 12
    n = 6;
else
    n = 0;
end
end

function n = localPUCCHUCICodedBitCount(trial, resolvedFormat)
n = NaN;
tx = sixgr.util.structGet(trial, "Tx", struct());
if isstruct(tx)
    codedUCI = sixgr.util.structGet(tx, "CodedUCI", []);
    if ~isempty(codedUCI)
        n = double(numel(codedUCI));
        return;
    end
end
resolvedFormat = round(double(resolvedFormat));
if isfinite(resolvedFormat) && resolvedFormat <= 1
    n = 0;
end
end

function b = localFirstBit(raw)
bits = localNormalizeBits(raw);
b = false;
if ~isempty(bits)
    b = logical(bits(1));
end
end

function value = localObjectProperty(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    if isprop(obj, propName)
        value = obj.(propName);
    end
catch
    value = defaultValue;
end
end

function value = localFirstNumeric(raw, defaultValue)
value = defaultValue;
if isempty(raw)
    return;
end
vals = double(raw(:));
vals = vals(isfinite(vals));
if ~isempty(vals)
    value = vals(1);
end
end

function value = localScalarNumeric(raw)
value = NaN;
if isempty(raw)
    return;
end
try
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = vals(1);
    end
catch
    value = NaN;
end
end

function text = localNumericVectorToString(raw)
if isempty(raw)
    text = "";
    return;
end
try
    vals = double(raw(:)).';
    text = strjoin(string(vals), " ");
catch
    text = "";
end
end

function id = localResourceId(cfg, pucch)
rid = sixgr.util.structGet(cfg, "validation.pucch_resources.default_resource_id", []);
if ~isempty(rid)
    id = "scenario_pucch_resource_" + string(rid);
    return;
end
fmt = localScalarNumeric(localObjectProperty(pucch, "Format", []));
prb = localNumericVectorToString(localObjectProperty(pucch, "PRBSet", []));
sym = localNumericVectorToString(localObjectProperty(pucch, "SymbolAllocation", []));
id = "pucch:fmt=" + string(fmt) + ":prb=" + prb + ":sym=" + sym;
end

function fs = localSampleRate(txInfo)
fs = NaN;
try
    ofdm = sixgr.util.structGet(txInfo, "OFDMInfo", struct());
    fs = double(sixgr.util.structGet(ofdm, "SampleRate", NaN));
catch
    fs = NaN;
end
end

function tti = localAirInterfaceTTI(txInfo)
fs = localSampleRate(txInfo);
tti = NaN;
try
    ofdm = sixgr.util.structGet(txInfo, "OFDMInfo", struct());
    symLengths = double(sixgr.util.structGet(ofdm, "SymbolLengths", []));
    if isfinite(fs) && fs > 0 && ~isempty(symLengths)
        tti = sum(symLengths(:)) ./ fs .* 1e3;
    end
catch
    tti = NaN;
end
end

function hash = localComplexHash(x)
hash = "";
if isempty(x)
    return;
end
try
    bytes = typecast(single([real(x(:)); imag(x(:))]), "uint8");
    hash = string(sixgr.rrc.asn1.sha256Hex(bytes));
catch
    hash = "";
end
end

function out = ternary(cond, a, b)
if logical(cond)
    out = a;
else
    out = b;
end
end
