function result = runStrictSRSValidation(baseCfg, varargin)
%RUNSTRICTSRSVALIDATION Execute strict waveform-backed SRS validation.

p = inputParser;
p.FunctionName = "sixgr.phy.srs.runStrictSRSValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "srs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "srs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ExecutionID", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioConfigHash", "", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

srsCfg = sixgr.phy.srs.buildSRSConfigFromScenario(baseCfg, ...
    "RunFolder", opt.RunFolder, "RunId", opt.RunId, "ScenarioName", opt.ScenarioName);
toolboxCapabilities = localToolboxCapabilities(opt.RunId, opt.ScenarioName);
configT = localConfigTable(srsCfg);
resourceSetT = localResourceSetTable(srsCfg);
resourceT = localResourceTable(srsCfg);
triggerT = localTriggerTable(srsCfg);
baseTx = sixgr.phy.srs.generateSRSWaveform(srsCfg);
txWaveformT = localTxWaveformTable(srsCfg, baseTx);

trialT = table();
negativeT = table();
extractionT = table();
detectionT = table();
channelT = table();
channelPrbT = table();
channelPortT = table();
timingT = table();
oracleT = table();
trialId = 0;
highSNR = max(35, double(srsCfg.HighSNRdB));

[trialId, one] = localRunOneTrial(trialId, srsCfg, baseTx, "positive_awgn", highSNR, 0, "normal", false, []);
trialT = localAppend(trialT, one.TrialTable);
extractionT = localAppend(extractionT, one.ExtractionTable);
detectionT = localAppend(detectionT, one.DetectionTable);
channelT = localAppend(channelT, one.ChannelTable);
channelPrbT = localAppend(channelPrbT, one.ChannelPRBTable);
channelPortT = localAppend(channelPortT, one.ChannelPortTable);
timingT = localAppend(timingT, one.TimingTable);
oracleT = localAppend(oracleT, one.OracleTable);

negativeModes = ["no_signal_srs","wrong_sequence_id","wrong_resource_mapping", ...
    "wrong_comb_cyclic_shift","wrong_port","corrupted_srs_symbols", ...
    "partial_band_claimed_full","missing_aperiodic_dci_trigger"];
for ii = 1:numel(negativeModes)
    mode = negativeModes(ii);
    faultMode = "normal";
    rxCfg = [];
    txCfg = srsCfg;
    tx = baseTx;
    if mode == "no_signal_srs"
        faultMode = "no_signal";
    elseif mode == "corrupted_srs_symbols"
        faultMode = "corrupted_symbols";
    elseif mode == "wrong_sequence_id"
        rxCfg = localReceiverOverride(srsCfg, "wrong_sequence_id");
    elseif mode == "wrong_resource_mapping"
        rxCfg = localReceiverOverride(srsCfg, "wrong_resource_mapping");
    elseif mode == "wrong_comb_cyclic_shift"
        rxCfg = localReceiverOverride(srsCfg, "wrong_comb_cyclic_shift");
    elseif mode == "wrong_port"
        if double(srsCfg.NumSRSPorts) >= 4
            txCfg = localWrongPortTransmitConfig(srsCfg);
            tx = sixgr.phy.srs.generateSRSWaveform(txCfg);
            rxCfg = srsCfg;
        else
            rxCfg = localReceiverOverride(srsCfg, "wrong_port");
        end
    elseif mode == "partial_band_claimed_full"
        txCfg = localPartialFullClaimConfig(srsCfg);
        tx = sixgr.phy.srs.generateSRSWaveform(txCfg);
    elseif mode == "missing_aperiodic_dci_trigger"
        txCfg = localAperiodicMissingTriggerConfig(srsCfg);
        tx = sixgr.phy.srs.generateSRSWaveform(txCfg);
    end
    [trialId, one] = localRunOneTrial(trialId, txCfg, tx, mode, highSNR, 0, faultMode, true, rxCfg);
    trialT = localAppend(trialT, one.TrialTable);
    negativeT = localAppend(negativeT, one.TrialTable);
    extractionT = localAppend(extractionT, one.ExtractionTable);
    detectionT = localAppend(detectionT, one.DetectionTable);
    channelT = localAppend(channelT, one.ChannelTable);
    channelPrbT = localAppend(channelPrbT, one.ChannelPRBTable);
    channelPortT = localAppend(channelPortT, one.ChannelPortTable);
    timingT = localAppend(timingT, one.TimingTable);
    oracleT = localAppend(oracleT, one.OracleTable);
end

[lowSNRT, lowTrials, lowEvidence, trialId] = localLowSNRSweep(srsCfg, baseTx, trialId);
trialT = localAppend(trialT, lowTrials);
extractionT = localAppend(extractionT, lowEvidence.ExtractionTable);
detectionT = localAppend(detectionT, lowEvidence.DetectionTable);
channelT = localAppend(channelT, lowEvidence.ChannelTable);
channelPrbT = localAppend(channelPrbT, lowEvidence.ChannelPRBTable);
channelPortT = localAppend(channelPortT, lowEvidence.ChannelPortTable);
timingT = localAppend(timingT, lowEvidence.TimingTable);
oracleT = localAppend(oracleT, lowEvidence.OracleTable);
[timingSweepT, timingTrials, timingEvidence, trialId] = localTimingOffsetSweep(srsCfg, baseTx, trialId);
trialT = localAppend(trialT, timingTrials);
extractionT = localAppend(extractionT, timingEvidence.ExtractionTable);
detectionT = localAppend(detectionT, timingEvidence.DetectionTable);
channelT = localAppend(channelT, timingEvidence.ChannelTable);
channelPrbT = localAppend(channelPrbT, timingEvidence.ChannelPRBTable);
channelPortT = localAppend(channelPortT, timingEvidence.ChannelPortTable);
timingT = localAppend(timingT, timingEvidence.TimingTable);
oracleT = localAppend(oracleT, timingEvidence.OracleTable);
multiUET = localMultiUETrials(srsCfg);
coverageT = localCoverageTable(srsCfg, trialT, detectionT, channelT, timingT);

positiveOk = any(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_awgn");
negativeOk = height(negativeT) >= numel(negativeModes) && ...
    all(~logical(negativeT.StrictOk)) && all(logical(negativeT.NegativeExpectedOk));
artifactRowsOk = height(configT) > 0 && height(resourceSetT) > 0 && height(resourceT) > 0 && ...
    height(txWaveformT) > 0 && height(extractionT) > 0 && height(detectionT) > 0 && ...
    height(channelT) > 0 && height(channelPrbT) > 0 && height(channelPortT) > 0 && ...
    height(timingT) > 0 && height(coverageT) > 0 && ...
    height(triggerT) > 0 && height(lowSNRT) > 0 && height(timingSweepT) > 0 && ...
    height(multiUET) > 0 && height(oracleT) > 0;
oracleOk = ~any(logical(oracleT.Violation));
configOk = logical(srsCfg.StrictValidation.StrictValid);
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
coverageOk = any(logical(trialT.StrictOk) & logical(trialT.ConfiguredBandClaimValid) & ...
    (~logical(trialT.FullCarrierSoundingRequired) | ...
    (logical(trialT.FullCarrierClaimValid) & string(trialT.BandwidthCoverageStatus) == "full_carrier")));
partialNegativeOk = any(string(negativeT.TrialType) == "partial_band_claimed_full" & ...
    ~logical(negativeT.StrictOk) & contains(string(negativeT.FailureReason), "srs_partial_band_claimed_full"));
strictOk = positiveOk && negativeOk && artifactRowsOk && oracleOk && configOk && ...
    noProxySkip && coverageOk && partialNegativeOk;

gateT = table( ...
    ["positive_waveform"; "negative_fail_closed"; "artifact_rows"; ...
     "oracle_guard"; "strict_config"; "no_proxy_or_skip"; ...
     "configured_coverage"; "partial_band_negative"], ...
    logical([positiveOk; negativeOk; artifactRowsOk; oracleOk; configOk; ...
     noProxySkip; coverageOk; partialNegativeOk]), ...
    ["positive_awgn strict waveform row"; ...
     "all required negative trials rejected"; ...
     "all required measured artifact tables populated"; ...
     "no SRS oracle-field violation"; ...
     "resolved SRS resource/configuration valid"; ...
     "no proxy, skipped, or toolbox-missing row"; ...
     "configured SRS bandwidth claim observed"; ...
     "false full-band claim rejected"], ...
    'VariableNames', {'Gate','Pass','Evidence'});
failedGates = string(gateT.Gate(~logical(gateT.Pass)));
failureReason = "";
if ~strictOk
    failureReason = "strict_srs_validation_failed:" + strjoin(failedGates, "|");
end

summary = localSummaryStruct(srsCfg, strictOk, trialT, negativeT, lowSNRT, timingSweepT, multiUET, oracleT);
summary.FailedGates = strjoin(failedGates, "|");

result = struct();
result.RunId = string(opt.RunId);
result.ScenarioName = string(opt.ScenarioName);
result.Config = srsCfg;
result.ConfigHash = string(srsCfg.ConfigHash);
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
result.FailureReason = string(failureReason);
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ToolboxCapabilities = toolboxCapabilities;
result.DetectionSummary = summary;
result.PositiveGrid = baseTx.GridSlots(1).Grid;
result.NoSignalGrid = baseTx.GridSlots(1).Grid .* 0;
result.ArtifactTables = struct( ...
    "srs_config_strict", configT, ...
    "srs_resource_sets", resourceSetT, ...
    "srs_resources", resourceT, ...
    "srs_resource_mapping", sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg).ResourceMappingTable, ...
    "srs_tx_waveform", txWaveformT, ...
    "srs_rx_extraction", extractionT, ...
    "srs_detection_metrics", detectionT, ...
    "srs_channel_estimation", channelT, ...
    "srs_channel_estimation_per_prb", channelPrbT, ...
    "srs_channel_estimation_per_port", channelPortT, ...
    "srs_timing_tracking", timingT, ...
    "srs_coverage", coverageT, ...
    "srs_trigger_events", triggerT, ...
    "srs_trials", trialT, ...
    "srs_negative_trials", negativeT, ...
    "srs_low_snr_sweep", lowSNRT, ...
    "srs_timing_offset_sweep", timingSweepT, ...
    "srs_multi_ue_trials", multiUET, ...
    "srs_oracle_guard", oracleT, ...
    "srs_strict_gate_status", gateT);
if strlength(strtrim(string(opt.ExecutionID))) > 0
    identity = struct("RunID", string(opt.RunId), ...
        "ExecutionID", string(opt.ExecutionID), ...
        "ScenarioID", string(opt.ScenarioName), ...
        "ConfigHash", string(opt.ScenarioConfigHash));
    result.ArtifactTables = ...
        sixgr.runtime.bindInPathArtifactIdentity( ...
        result.ArtifactTables, identity);
    result.ExecutionID = identity.ExecutionID;
    result.ScenarioConfigHash = identity.ConfigHash;
end

if logical(opt.WriteArtifacts)
    result.ArtifactManifest = sixgr.phy.srs.exportStrictSRSArtifacts(char(string(opt.RunFolder)), result);
else
    result.ArtifactManifest = table();
end
end

function [trialId, out] = localRunOneTrial(trialId, cfg, tx, trialType, snrDb, timingOffset, faultMode, negativeExpected, rxCfgOverride)
trialId = trialId + 1;
rx = sixgr.phy.srs.applySRSChannel(tx, cfg, "SNRdB", snrDb, ...
    "TimingOffsetSamples", timingOffset, "FaultMode", faultMode, "Seed", 26000 + trialId);
rxCfg = cfg;
if ~isempty(rxCfgOverride)
    rxCfg = rxCfgOverride;
end
rxRef = sixgr.phy.srs.generateSRSWaveform(rxCfg);
timing = sixgr.phy.srs.estimateSRSDelayTiming(rx, rxRef, rxCfg);
det = sixgr.phy.srs.detectSRSFromULGrid(rx, rxCfg);
ch = sixgr.phy.srs.estimateULChannelFromSRS(det, rxCfg);
score = sixgr.phy.srs.scoreSRSDetection(rxCfg, rx, det, ch, timing, ...
    "TrialId", trialId, "TrialType", trialType, "NegativeExpected", negativeExpected);
trialTable = struct2table(score.TrialRow, "AsArray", true);
extractionTable = det.Extracted.Table;
detectionTable = det.Table;
channelTable = ch.Table;
channelPRBTable = ch.PerPRBTable;
channelPortTable = ch.PerPortTable;
timingTable = timing.Table;
trialTables = {extractionTable, detectionTable, channelTable, channelPRBTable, channelPortTable, timingTable};
for ii = 1:numel(trialTables)
    trialTables{ii}.TrialId = repmat(double(trialId), height(trialTables{ii}), 1);
    trialTables{ii}.TrialType = repmat(string(trialType), height(trialTables{ii}), 1);
end
out = struct();
out.TrialTable = trialTable;
out.ExtractionTable = trialTables{1};
out.DetectionTable = trialTables{2};
out.ChannelTable = trialTables{3};
out.ChannelPRBTable = trialTables{4};
out.ChannelPortTable = trialTables{5};
out.TimingTable = trialTables{6};
out.OracleTable = sixgr.phy.srs.guardNoOracleSRS(cfg.RunId, trialId);
end

function T = localAppend(T, U)
if isempty(T) || width(T) == 0
    T = U;
else
    T = [T; U]; %#ok<AGROW>
end
end

function rxCfg = localReceiverOverride(cfg, mode)
rxCfg = cfg;
switch string(mode)
    case "wrong_sequence_id"
        rxCfg.SequenceId = mod(double(cfg.SequenceId) + 137, 1024);
    case "wrong_resource_mapping"
        rxCfg.SymbolStart = max(0, mod(double(cfg.SymbolStart) + 1, 14 - double(cfg.NumSRSSymbols)));
    case "wrong_comb_cyclic_shift"
        rxCfg.CombOffset = mod(double(cfg.CombOffset) + 1, double(cfg.CombNumber));
        rxCfg.CyclicShift = double(cfg.CyclicShift) + 1;
    case "wrong_port"
        rxCfg.NumSRSPorts = localDifferentLegalSRSPortCount(double(cfg.NumSRSPorts));
        rxCfg.PortSet = 0:(rxCfg.NumSRSPorts - 1);
end
rxCfg = localRefreshSRSConfig(rxCfg);
end

function out = localWrongPortTransmitConfig(cfg)
out = cfg;
out.NumSRSPorts = localDifferentLegalSRSPortCount(double(cfg.NumSRSPorts));
out.PortSet = 0:(out.NumSRSPorts - 1);
out = localRefreshSRSConfig(out);
end

function nPorts = localDifferentLegalSRSPortCount(configuredPorts)
legal = [1 2 4 8];
configuredPorts = round(double(configuredPorts));
if ~(isfinite(configuredPorts) && configuredPorts >= 1)
    configuredPorts = 1;
end
if configuredPorts == 1
    nPorts = 2;
elseif configuredPorts == 2
    nPorts = 4;
elseif configuredPorts == 4
    nPorts = 2;
elseif configuredPorts == 8
    nPorts = 4;
else
    choices = legal(legal ~= configuredPorts);
    nPorts = choices(1);
end
end

function out = localPartialFullClaimConfig(cfg)
out = cfg;
out.CoverageRequirement = "full_carrier";
out.FullCarrierSoundingRequired = true;
out.ExpectedNumRB = double(cfg.NSizeGrid);
out.C_SRS = 0;
out.B_SRS = 0;
out = localRefreshSRSConfig(out);
end

function out = localAperiodicMissingTriggerConfig(cfg)
out = cfg;
out.ResourceType = "aperiodic";
out.DCITriggerReferenceId = "";
out = localRefreshSRSConfig(out);
end

function cfg = localRefreshSRSConfig(cfg)
resourceSet = sixgr.phy.srs.buildSRSResourceSetStrict(cfg);
cfg.ToolboxCarrier = resourceSet.Carrier;
cfg.ToolboxSRS = resourceSet.SRS;
cfg.C_SRS = double(resourceSet.SRS.CSRS);
cfg.B_SRS = double(resourceSet.SRS.BSRS);
cfg.NumRB = double(resourceSet.SRS.NRBPerTransmission);
cfg.ConfigHash = sixgr.phy.srs.hashSRSConfig(cfg);
cfg.StrictValidation = sixgr.phy.srs.validateSRSConfigStrict(cfg);
cfg.ConfigExport = rmfield(cfg, intersect(fieldnames(cfg), ...
    {'ToolboxCarrier','ToolboxSRS','BaseConfig','ConfigExport','StrictValidation'}));
end

function [sweepT, trialT, evidence, trialId] = localLowSNRSweep(cfg, baseTx, trialId)
snrs = double(cfg.LowSNRSweepdB(:).');
rows = repmat(localLowSNRRow(), numel(snrs), 1);
trialT = table();
evidence = localEmptyEvidenceTables();
for ii = 1:numel(snrs)
    [trialId, one] = localRunOneTrial(trialId, cfg, baseTx, "low_snr_sweep", snrs(ii), 0, "normal", false, []);
    tr = one.TrialTable;
    trialT = localAppend(trialT, tr);
    evidence = localAppendEvidence(evidence, one);
    rows(ii) = localLowSNRRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).SweepId = "low_snr_" + string(ii);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).SNRdB = double(snrs(ii));
    rows(ii).NumTrials = 1;
    rows(ii).NumDetected = double(tr.DetectionSuccess);
    rows(ii).NumChannelAvailable = double(tr.SRSChannelEstimateAvailable);
    rows(ii).DetectionProbability = double(tr.DetectionSuccess);
    rows(ii).ChannelAvailabilityProbability = double(tr.SRSChannelEstimateAvailable);
    rows(ii).MeanChannelNMSEdB = double(tr.NMSE_dB);
    rows(ii).MeanWidebandSRSSINRdB = double(tr.WidebandSRSSINR_dB);
    rows(ii).Status = "measured_waveform_sweep";
end
sweepT = struct2table(rows, "AsArray", true);
end

function [sweepT, trialT, evidence, trialId] = localTimingOffsetSweep(cfg, baseTx, trialId)
offsets = double(cfg.TimingOffsetSweepSamples(:).');
rows = repmat(localTimingSweepRow(), numel(offsets), 1);
trialT = table();
evidence = localEmptyEvidenceTables();
for ii = 1:numel(offsets)
    [trialId, one] = localRunOneTrial(trialId, cfg, baseTx, "timing_offset_sweep", max(35, cfg.HighSNRdB), offsets(ii), "normal", false, []);
    tr = one.TrialTable;
    trialT = localAppend(trialT, tr);
    evidence = localAppendEvidence(evidence, one);
    rows(ii) = localTimingSweepRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).SweepId = "timing_offset_" + string(ii);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).InjectedTimingOffsetSamples = double(offsets(ii));
    rows(ii).NumTrials = 1;
    rows(ii).NumTimingAvailable = double(tr.SRSTimingEstimateAvailable);
    rows(ii).MeanEstimatedTimingOffsetSamples = double(tr.EstimatedTimingOffsetSamples);
    rows(ii).MeanTimingErrorSamples = double(tr.TimingErrorSamples);
    rows(ii).MaxAbsTimingErrorSamples = abs(double(tr.TimingErrorSamples));
    rows(ii).WithinToleranceProbability = double(abs(double(tr.TimingErrorSamples)) <= double(cfg.TimingToleranceSamples));
    rows(ii).Status = "measured_waveform_sweep";
end
sweepT = struct2table(rows, "AsArray", true);
end

function evidence = localEmptyEvidenceTables()
evidence = struct("ExtractionTable", table(), "DetectionTable", table(), ...
    "ChannelTable", table(), "ChannelPRBTable", table(), ...
    "ChannelPortTable", table(), "TimingTable", table(), "OracleTable", table());
end

function evidence = localAppendEvidence(evidence, one)
evidence.ExtractionTable = localAppend(evidence.ExtractionTable, one.ExtractionTable);
evidence.DetectionTable = localAppend(evidence.DetectionTable, one.DetectionTable);
evidence.ChannelTable = localAppend(evidence.ChannelTable, one.ChannelTable);
evidence.ChannelPRBTable = localAppend(evidence.ChannelPRBTable, one.ChannelPRBTable);
evidence.ChannelPortTable = localAppend(evidence.ChannelPortTable, one.ChannelPortTable);
evidence.TimingTable = localAppend(evidence.TimingTable, one.TimingTable);
evidence.OracleTable = localAppend(evidence.OracleTable, one.OracleTable);
end

function T = localMultiUETrials(cfg)
orthogonal = sixgr.phy.srs.generateMultiUESRSGrid(cfg, [1 2], ...
    "Mode", "orthogonal", "SNRdB", max(35, double(cfg.HighSNRdB)), ...
    "Seed", double(cfg.Seed) + 8100);
collision = sixgr.phy.srs.generateMultiUESRSGrid(cfg, [1 2], ...
    "Mode", "collision", "SNRdB", max(35, double(cfg.HighSNRdB)), ...
    "Seed", double(cfg.Seed) + 8200);
T = localAppend(orthogonal.TrialTable, collision.TrialTable);
T.TrialId = (1:height(T)).';
end

function T = localCoverageTable(cfg, trialT, detectionT, channelT, timingT)
mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(cfg);
cov = mapping.Coverage;
hopping = sixgr.phy.srs.validateSRSFrequencyHoppingCoverage(cfg);
row = struct();
row.RunId = string(cfg.RunId);
row.ConfigHash = string(cfg.ConfigHash);
row.CoverageRequirement = string(cfg.CoverageRequirement);
row.FullCarrierSoundingRequired = logical(cfg.FullCarrierSoundingRequired);
row.ExpectedNumRB = double(cfg.ExpectedNumRB);
row.OccupiedPRBCount = double(cov.OccupiedPRBCount);
row.CarrierPRBCount = double(cov.CarrierPRBCount);
row.CoveragePercent = double(cov.CoveragePercent);
row.BandwidthCoverageStatus = string(cov.BandwidthCoverageStatus);
row.FullCarrierClaimValid = logical(cov.FullCarrierClaimValid);
row.ConfiguredBandClaimValid = logical(cov.ConfiguredBandClaimValid);
row.PartialBandValid = logical(cov.PartialBandValid);
row.FrequencyHoppingRequested = logical(hopping.FrequencyHoppingRequested);
row.FrequencyHoppingCoverageStatus = string(hopping.Status);
row.TrialRows = double(height(trialT));
row.DetectionRows = double(height(detectionT));
row.ChannelRows = double(height(channelT));
row.TimingRows = double(height(timingT));
row.StrictCoverageOk = row.ConfiguredBandClaimValid && ...
    (~row.FullCarrierSoundingRequired || row.FullCarrierClaimValid) && height(trialT) > 0;
row.Status = string(sixgr.phy.srs.localTernary(row.StrictCoverageOk, ...
    "strict_srs_coverage_complete", "strict_srs_coverage_incomplete"));
T = struct2table(row, "AsArray", true);
end

function T = localConfigTable(cfg)
S = cfg.ConfigExport;
S.StrictValid = logical(cfg.StrictValidation.StrictValid);
S.StrictUnsupportedReason = string(cfg.StrictValidation.StrictUnsupportedReason);
S.ToolboxMissing = logical(cfg.StrictValidation.ToolboxMissing);
S.ImplementationStatus = "strict_srs_waveform_channel_sounding_evidence";
S.TruthStatus = "real_lls_evidence";
T = struct2table(S, "AsArray", true);
end

function T = localResourceSetTable(cfg)
row = struct("RunId", string(cfg.RunId), "ResourceSetId", double(cfg.ResourceSetId), ...
    "ResourceSetUsage", string(cfg.ResourceSetUsage), "ResourceType", string(cfg.ResourceType), ...
    "Periodicity", double(cfg.Periodicity), "Offset", double(cfg.Offset), ...
    "ResourceIds", strjoin(string(cfg.ResourceIds), "|"), ...
    "DCITriggerReferenceId", string(cfg.DCITriggerReferenceId), ...
    "ActivationMACCEReferenceId", string(cfg.ActivationMACCEReferenceId), ...
    "ConfigHash", string(cfg.ConfigHash), "TruthStatus", "real_lls_evidence");
T = struct2table(row, "AsArray", true);
end

function T = localResourceTable(cfg)
row = struct("RunId", string(cfg.RunId), "ResourceSetId", double(cfg.ResourceSetId), ...
    "ResourceId", double(cfg.ResourceId), "NumSRSPorts", double(cfg.NumSRSPorts), ...
    "PortSet", strjoin(string(cfg.PortSet), "|"), "SymbolStart", double(cfg.SymbolStart), ...
    "NumSRSSymbols", double(cfg.NumSRSSymbols), "RepetitionFactor", double(cfg.RepetitionFactor), ...
    "CombNumber", double(cfg.CombNumber), "CombOffset", double(cfg.CombOffset), ...
    "CyclicShift", double(cfg.CyclicShift), "SequenceId", double(cfg.SequenceId), ...
    "GroupOrSequenceHopping", string(cfg.GroupOrSequenceHopping), ...
    "FrequencyPosition", double(cfg.FrequencyPosition), "FrequencyShift", double(cfg.FrequencyShift), ...
    "BHop", double(cfg.BHop), "C_SRS", double(cfg.C_SRS), "B_SRS", double(cfg.B_SRS), ...
    "NumRB", double(cfg.NumRB), "ConfigHash", string(cfg.ConfigHash), ...
    "TruthStatus", "real_lls_evidence");
T = struct2table(row, "AsArray", true);
end

function T = localTxWaveformTable(cfg, tx)
row = struct("RunId", string(cfg.RunId), "UEId", double(cfg.UEId), ...
    "ConfigHash", string(cfg.ConfigHash), "TxResourceIndicesHash", string(tx.TxResourceIndicesHash), ...
    "TxSRSSymbolHash", string(tx.TxSRSSymbolHash), "TxULGridHash", string(tx.TxULGridHash), ...
    "TxWaveformHash", string(tx.TxWaveformHash), "ExpectedRECount", double(tx.ExpectedRECount), ...
    "ExpectedRBCount", double(tx.ExpectedRBCount), ...
    "ExpectedCoverageStatus", string(tx.ExpectedCoverageStatus), ...
    "WaveformSamples", double(size(tx.Waveform, 1)), "NumSlots", double(numel(tx.GridSlots)), ...
    "TruthStatus", "real_lls_evidence");
T = struct2table(row, "AsArray", true);
end

function T = localTriggerTable(cfg)
trigger = sixgr.phy.srs.resolveSRSTrigger(cfg);
row = struct("RunId", string(cfg.RunId), "ConfigHash", string(cfg.ConfigHash), ...
    "ResourceType", string(cfg.ResourceType), "ConfiguredOccasionSlots", strjoin(string(cfg.ExpectedSlotSet), "|"), ...
    "TriggerSource", string(trigger.TriggerSource), ...
    "TriggerReferenceId", string(trigger.TriggerReferenceId), ...
    "ExpectedSlot", double(trigger.ExpectedSlot), "ObservedSlot", double(trigger.ObservedSlot), ...
    "TriggerValid", logical(trigger.TriggerValid), "Status", string(trigger.Status), ...
    "TruthStatus", "real_lls_evidence");
T = struct2table(row, "AsArray", true);
end

function summary = localSummaryStruct(cfg, strictOk, trialT, negativeT, lowSNRT, timingSweepT, multiUET, oracleT)
summary = struct();
summary.RunId = string(cfg.RunId);
summary.scenario = string(cfg.ScenarioName);
summary.implementation_status = "strict_srs_waveform_channel_sounding_validation";
summary.StrictOk = logical(strictOk);
summary.PositiveStrictRows = double(sum(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_awgn"));
summary.NegativeExpectedRows = double(height(negativeT));
summary.LowSNRSweepRows = double(height(lowSNRT));
summary.TimingOffsetSweepRows = double(height(timingSweepT));
summary.MultiUERows = double(height(multiUET));
summary.OracleGuardRows = double(height(oracleT));
summary.OracleGuardViolationCount = double(sum(logical(oracleT.Violation)));
summary.source_csv = "reference_signals/csv/srs_trials.csv";
summary.timestamp = sixgr.util.utcNowISO8601();
end

function caps = localToolboxCapabilities(runId, scenarioName)
names = ["nrCarrierConfig","nrSRSConfig","nrSRS","nrSRSIndices", ...
    "nrOFDMModulate","nrOFDMDemodulate","nrChannelEstimate","nrTDLChannel","nrCDLChannel","awgn"];
caps = struct();
caps.MATLABVersion = string(version);
caps.ToolboxVersion = localToolboxVersion("5G Toolbox");
caps.StrictModeToolboxFallbackAllowed = false;
caps.GeneratedAt = sixgr.util.utcNowISO8601();
caps.ProducerModule = "sixgr.phy.srs.runStrictSRSValidation";
caps.RunId = string(runId);
caps.scenario = string(scenarioName);
for ii = 1:numel(names)
    field = char(names(ii) + "Available");
    caps.(field) = ~isempty(which(char(names(ii))));
end
end

function v = localToolboxVersion(name)
v = "";
items = ver;
for ii = 1:numel(items)
    if strcmpi(items(ii).Name, char(name))
        v = string(items(ii).Version);
        return;
    end
end
end

function row = localLowSNRRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", "SNRdB", NaN, ...
    "NumTrials", NaN, "NumDetected", NaN, "NumChannelAvailable", NaN, ...
    "DetectionProbability", NaN, "ChannelAvailabilityProbability", NaN, ...
    "MeanChannelNMSEdB", NaN, "MeanWidebandSRSSINRdB", NaN, "Status", "");
end

function row = localTimingSweepRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", ...
    "InjectedTimingOffsetSamples", NaN, "NumTrials", NaN, "NumTimingAvailable", NaN, ...
    "MeanEstimatedTimingOffsetSamples", NaN, "MeanTimingErrorSamples", NaN, ...
    "MaxAbsTimingErrorSamples", NaN, "WithinToleranceProbability", NaN, "Status", "");
end

function row = localMultiUERow()
row = struct("RunId", "", "TrialId", NaN, "UEId", NaN, "CollisionGroupId", NaN, ...
    "ResourceId", NaN, "Port", NaN, "RBStart", NaN, "NumRB", NaN, ...
    "CyclicShift", NaN, "CombOffset", NaN, "CollisionInjected", false, ...
    "CollisionDetected", false, "OrthogonalityPass", false, ...
    "ChannelEstimateAvailable", false, "DetectionSuccess", false, ...
    "DetectionMetric", NaN, "NMSE_dB", NaN, "OverlapRECount", NaN, ...
    "SharedSlotWaveformSuperposition", true, "WaveformSource", "", ...
    "Outcome", "", "Status", "", "FailureReason", "");
end
