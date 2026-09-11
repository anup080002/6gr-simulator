function result = runStrictTRSValidation(baseCfg, varargin)
%RUNSTRICTTRSVALIDATION Execute strict waveform-backed TRS validation.

p = inputParser;
p.FunctionName = "sixgr.phy.trs.runStrictTRSValidation";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "trs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "trs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ExecutionID", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioConfigHash", "", @(x) ischar(x) || isstring(x));
addParameter(p, "WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

cfg = sixgr.phy.trs.buildTRSConfigFromScenario(baseCfg, ...
    "RunFolder", opt.RunFolder, "RunId", opt.RunId, "ScenarioName", opt.ScenarioName);
toolboxCapabilities = localToolboxCapabilities();
configT = localConfigTable(cfg);
baseTx = sixgr.phy.trs.generateTRSWaveform(cfg);
trialRows = repmat(localTrialRow(), 0, 1);
oracleT = table();
trialId = 0;
highSNR = max(35, double(cfg.HighSNRdB));

[trialId, tr, detT, timingT, freqT, chT, trackT, oracle, posTx, noSignalTx] = ...
    localRunOneTrial(trialId, cfg, baseTx, "positive_awgn", highSNR, 2, 100, "normal", false, []);
trialRows(end+1, 1) = tr; %#ok<AGROW>
oracleT = [oracleT; oracle]; %#ok<AGROW>
detectionT = detT; timingTrackT = timingT; frequencyTrackT = freqT; channelEstT = chT; trackingT = trackT;

negativeModes = ["no_signal","wrong_scrambling_id","wrong_resource_mapping","corrupted_symbols","missing_resource_subset"];
negativeRows = repmat(localTrialRow(), 0, 1);
for ii = 1:numel(negativeModes)
    mode = negativeModes(ii);
    rxOverride = [];
    faultMode = mode;
    if mode == "wrong_scrambling_id"
        faultMode = "normal";
        rxOverride = localReceiverOverride(cfg, "wrong_scrambling_id");
    elseif mode == "wrong_resource_mapping"
        faultMode = "normal";
        rxOverride = localReceiverOverride(cfg, "wrong_resource_mapping");
    end
    [trialId, tr, detOne, timingOne, freqOne, chOne, trackOne, oracle] = ...
        localRunOneTrial(trialId, cfg, baseTx, mode, highSNR, 2, 100, faultMode, true, rxOverride);
    trialRows(end+1, 1) = tr; %#ok<AGROW>
    negativeRows(end+1, 1) = tr; %#ok<AGROW>
    detectionT = [detectionT; detOne]; timingTrackT = [timingTrackT; timingOne]; %#ok<AGROW>
    frequencyTrackT = [frequencyTrackT; freqOne]; channelEstT = [channelEstT; chOne]; trackingT = [trackingT; trackOne]; %#ok<AGROW>
    oracleT = [oracleT; oracle]; %#ok<AGROW>
end

[lowSNRT, lowTrialT] = localLowSNRSweep(cfg, baseTx, trialId);
trialId = trialId + height(lowTrialT);
trialRows = [trialRows; table2struct(lowTrialT)]; %#ok<AGROW>
[timingSweepT, timingTrialT] = localTimingOffsetSweep(cfg, baseTx, trialId);
trialId = trialId + height(timingTrialT);
trialRows = [trialRows; table2struct(timingTrialT)]; %#ok<AGROW>
[freqSweepT, freqTrialT] = localFrequencyOffsetSweep(cfg, baseTx, trialId);
trialRows = [trialRows; table2struct(freqTrialT)]; %#ok<AGROW>

trialT = struct2table(trialRows, "AsArray", true);
if isempty(negativeRows)
    negativeT = struct2table(repmat(localTrialRow(), 0, 1));
else
    negativeT = struct2table(negativeRows, "AsArray", true);
end
coverageT = localCoverageTable(cfg, trialT, detectionT, timingTrackT, frequencyTrackT, channelEstT);

positiveOk = any(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_awgn");
negativeOk = height(negativeT) >= numel(negativeModes) && all(~logical(negativeT.StrictOk)) && all(logical(negativeT.NegativeExpectedOk));
artifactRowsOk = height(configT) > 0 && height(trialT) > 0 && height(cfgResourceMapping(cfg)) > 0 && ...
    height(detectionT) > 0 && height(timingTrackT) > 0 && height(frequencyTrackT) > 0 && ...
    height(channelEstT) > 0 && height(coverageT) > 0 && height(negativeT) > 0 && ...
    height(lowSNRT) > 0 && height(timingSweepT) > 0 && height(freqSweepT) > 0 && height(oracleT) > 0;
oracleOk = ~any(logical(oracleT.Violation));
configOk = logical(cfg.StrictValidation.StrictValid);
noProxySkip = ~any(logical(trialT.ProxyUsed) | logical(trialT.Skipped) | logical(trialT.ToolboxMissing));
strictOk = positiveOk && negativeOk && artifactRowsOk && oracleOk && configOk && noProxySkip;
summary = localSummaryStruct(cfg, strictOk, trialT, negativeT, lowSNRT, timingSweepT, freqSweepT, oracleT);

result = struct();
result.RunId = string(opt.RunId);
result.ScenarioName = string(opt.ScenarioName);
result.Config = cfg;
result.ConfigHash = string(cfg.ConfigHash);
result.StrictOk = logical(strictOk);
result.Ok = logical(strictOk);
result.FailureReason = string(sixgr.phy.trs.localTernary(strictOk, "", "strict_trs_validation_failed"));
result.ProxyUsed = false;
result.Skipped = false;
result.ToolboxMissing = false;
result.UsedOracleFields = "";
result.ToolboxCapabilities = toolboxCapabilities;
result.DetectionSummary = summary;
result.PositiveGrid = posTx.GridSlots(1).Grid;
result.NoSignalGrid = noSignalTx.GridSlots(1).Grid .* 0;
result.ArtifactTables = struct( ...
    "trs_config_strict", configT, ...
    "trs_trials", trialT, ...
    "trs_resource_mapping", cfgResourceMapping(cfg), ...
    "trs_detection_metrics", detectionT, ...
    "trs_timing_tracking", timingTrackT, ...
    "trs_frequency_tracking", frequencyTrackT, ...
    "trs_channel_estimation", channelEstT, ...
    "trs_coverage", coverageT, ...
    "trs_negative_trials", negativeT, ...
    "trs_low_snr_sweep", lowSNRT, ...
    "trs_timing_offset_sweep", timingSweepT, ...
    "trs_frequency_offset_sweep", freqSweepT, ...
    "trs_oracle_guard", oracleT, ...
    "trs_tracking_summary", trackingT);
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
    result.ArtifactManifest = sixgr.phy.trs.exportStrictTRSArtifacts(char(string(opt.RunFolder)), result);
else
    result.ArtifactManifest = table();
end
end

function [trialId, tr, detT, timingT, freqT, chT, trackT, oracleT, tx, noSignalTx] = localRunOneTrial( ...
    trialId, cfg, tx, trialType, snrDb, timingOffset, cfoHz, faultMode, negativeExpected, rxCfgOverride)
trialId = trialId + 1;
noSignalTx = tx;
rx = sixgr.phy.trs.applyTRSChannel(tx, cfg, "SNRdB", snrDb, ...
    "TimingOffsetSamples", timingOffset, "CFOHz", cfoHz, ...
    "FaultMode", faultMode, "Seed", 18000 + trialId);
rxCfg = cfg;
if ~isempty(rxCfgOverride)
    rxCfg = rxCfgOverride;
end
timing = sixgr.phy.trs.estimateTRSTiming(rx, rxCfg, tx);
det = sixgr.phy.trs.detectTRSResources(rx, rxCfg, tx, "Timing", timing);
if ~logical(det.DetectionSuccess)
    timing.EstimateAvailable = false;
    if istable(timing.Table) && ismember("TRSTimingEstimateAvailable", string(timing.Table.Properties.VariableNames))
        timing.Table.TRSTimingEstimateAvailable(:) = false;
        timing.Table.Status(:) = repmat("timing_estimate_rejected_no_valid_trs_detection", height(timing.Table), 1);
    end
end
freq = sixgr.phy.trs.estimateTRSFrequencyOffset(det, rxCfg, tx, rx);
ch = sixgr.phy.trs.estimateTRSChannel(rx, rxCfg, tx, det);
if faultMode == "normal" && ch.EstimateAvailable
    [referenceGrids, referenceEvidence] = ...
        localStandaloneAWGNReferenceGrids(rx, tx, det, timing, ch);
    ch = sixgr.phy.trs.scoreTRSChannelEstimates( ...
        ch, referenceGrids, referenceEvidence);
end
tracking = sixgr.phy.trs.trackTRSOverTime(det, timing, freq, ch, rxCfg);
score = sixgr.phy.trs.scoreTRSDetection(rxCfg, rx, det, timing, freq, ch, tracking, ...
    "TrialId", trialId, "TrialType", trialType, "NegativeExpected", negativeExpected);
tr = score.TrialRow;
detT = det.Table; detT.TrialId = repmat(double(trialId), height(detT), 1); detT.TrialType = repmat(string(trialType), height(detT), 1);
timingT = timing.Table; timingT.TrialId = repmat(double(trialId), height(timingT), 1); timingT.TrialType = repmat(string(trialType), height(timingT), 1);
freqT = freq.Table; freqT.TrialId = repmat(double(trialId), height(freqT), 1); freqT.TrialType = repmat(string(trialType), height(freqT), 1);
chT = ch.Table; chT.TrialId = repmat(double(trialId), height(chT), 1); chT.TrialType = repmat(string(trialType), height(chT), 1);
trackT = tracking.Table; trackT.TrialId = double(trialId); trackT.TrialType = string(trialType);
oracleT = sixgr.phy.trs.guardNoOracleTRS(cfg.RunId, trialId);
end

function rxCfg = localReceiverOverride(cfg, mode)
rxCfg = cfg;
switch string(mode)
    case "wrong_scrambling_id"
        rxCfg.NID = double(cfg.NID) + 31;
    case "wrong_resource_mapping"
        rxCfg.SymbolLocation = mod(double(cfg.SymbolLocation) + 1, 13);
end
resourceSet = sixgr.phy.trs.buildNZPCSIRSResourceSetForTRS(rxCfg);
rxCfg.ToolboxCarrier = resourceSet.Carrier;
rxCfg.ToolboxCSIRS = resourceSet.CSIRS;
rxCfg.NumCSIRSPorts = double(resourceSet.CSIRS.NumCSIRSPorts);
rxCfg.CDMType = string(resourceSet.CSIRS.CDMType);
rxCfg.Density = string(resourceSet.CSIRS.Density);
rxCfg.ConfigHash = sixgr.phy.trs.hashTRSConfig(rxCfg);
rxCfg.StrictValidation = sixgr.phy.trs.validateTRSConfigStrict(rxCfg);
end

function [sweepT, trialT] = localLowSNRSweep(cfg, baseTx, trialId)
snrs = double(cfg.LowSNRSweepdB(:).');
rows = repmat(localSweepRow(), numel(snrs), 1);
trialRows = repmat(localTrialRow(), 0, 1);
for ii = 1:numel(snrs)
    [trialId, tr] = localRunOneTrial(trialId, cfg, baseTx, "low_snr_sweep", snrs(ii), 0, 0, "normal", false, []); %#ok<ASGLU>
    trialRows(end+1, 1) = tr; %#ok<AGROW>
    rows(ii) = localSweepRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).SweepId = "low_snr_" + string(ii);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).SNRdB = double(snrs(ii));
    rows(ii).NumTrials = 1;
    rows(ii).DetectionProbability = double(tr.DetectionSuccess);
    rows(ii).StrictPassProbability = double(tr.StrictOk);
    rows(ii).MeanDetectionMetric = double(tr.DetectionMetric);
    rows(ii).Status = "measured_waveform_sweep";
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
end

function [sweepT, trialT] = localTimingOffsetSweep(cfg, baseTx, trialId)
offsets = double(cfg.TimingOffsetSweepSamples(:).');
rows = repmat(localTimingSweepRow(), numel(offsets), 1);
trialRows = repmat(localTrialRow(), 0, 1);
for ii = 1:numel(offsets)
    [trialId, tr] = localRunOneTrial(trialId, cfg, baseTx, "timing_offset_sweep", max(35, cfg.HighSNRdB), offsets(ii), 0, "normal", false, []); %#ok<ASGLU>
    trialRows(end+1, 1) = tr; %#ok<AGROW>
    rows(ii) = localTimingSweepRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).SweepId = "timing_offset_" + string(ii);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).InjectedTimingOffset_samples = double(offsets(ii));
    rows(ii).EstimatedTimingOffset_samples = double(tr.EstimatedTimingOffset_samples);
    rows(ii).TimingError_samples = double(tr.TimingError_samples);
    rows(ii).StrictOk = logical(tr.StrictOk);
    rows(ii).Status = "measured_waveform_sweep";
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
end

function [sweepT, trialT] = localFrequencyOffsetSweep(cfg, baseTx, trialId)
offsets = double(cfg.FrequencyOffsetSweepHz(:).');
rows = repmat(localFrequencySweepRow(), numel(offsets), 1);
trialRows = repmat(localTrialRow(), 0, 1);
for ii = 1:numel(offsets)
    [trialId, tr] = localRunOneTrial(trialId, cfg, baseTx, "frequency_offset_sweep", max(35, cfg.HighSNRdB), 0, offsets(ii), "normal", false, []); %#ok<ASGLU>
    trialRows(end+1, 1) = tr; %#ok<AGROW>
    rows(ii) = localFrequencySweepRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).SweepId = "frequency_offset_" + string(ii);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).InjectedCFO_Hz = double(offsets(ii));
    rows(ii).EstimatedCFO_Hz = double(tr.EstimatedCFO_Hz);
    rows(ii).FrequencyError_Hz = double(tr.FrequencyError_Hz);
    rows(ii).StrictOk = logical(tr.StrictOk);
    rows(ii).Status = "measured_waveform_sweep";
end
sweepT = struct2table(rows, "AsArray", true);
trialT = struct2table(trialRows, "AsArray", true);
end

function T = cfgResourceMapping(cfg)
T = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg).ResourceMappingTable;
end

function T = localCoverageTable(cfg, trialT, detectionT, timingT, freqT, chT)
row = struct();
row.RunId = string(cfg.RunId);
row.ConfigHash = string(cfg.ConfigHash);
row.TrialRows = double(height(trialT));
row.PositiveStrictRows = double(sum(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_awgn"));
row.NegativeRows = double(sum(contains(string(trialT.TrialType), ["no_signal","wrong","corrupted","missing"])));
row.DetectionRows = double(height(detectionT));
row.TimingRows = double(height(timingT));
row.FrequencyRows = double(height(freqT));
row.ChannelRows = double(height(chT));
row.AllDetectionAttempted = all(logical(detectionT.DetectionAttempted));
row.AllTimingAttempted = all(logical(timingT.TimingTrackingAttempted));
row.AllFrequencyAttempted = all(logical(freqT.FrequencyTrackingAttempted));
row.AllChannelAttempted = all(logical(chT.ChannelEstimationAttempted));
row.StrictCoverageOk = row.TrialRows > 0 && row.DetectionRows > 0 && row.TimingRows > 0 && row.FrequencyRows > 0 && row.ChannelRows > 0 && ...
    row.AllDetectionAttempted && row.AllTimingAttempted && row.AllFrequencyAttempted && row.AllChannelAttempted;
row.Status = string(sixgr.phy.trs.localTernary(row.StrictCoverageOk, "strict_trs_coverage_complete", "strict_trs_coverage_incomplete"));
T = struct2table(row, "AsArray", true);
end

function T = localConfigTable(cfg)
S = cfg.ConfigExport;
S.StrictValid = logical(cfg.StrictValidation.StrictValid);
S.StrictUnsupportedReason = string(cfg.StrictValidation.StrictUnsupportedReason);
S.ToolboxMissing = logical(cfg.StrictValidation.ToolboxMissing);
S.ImplementationStatus = "strict_trs_nzp_csirs_tracking_evidence";
S.TruthStatus = "real_lls_evidence";
T = struct2table(S, "AsArray", true);
end

function summary = localSummaryStruct(cfg, strictOk, trialT, negativeT, lowSNRT, timingSweepT, freqSweepT, oracleT)
summary = struct();
summary.RunId = string(cfg.RunId);
summary.scenario = string(cfg.ScenarioName);
summary.implementation_status = "strict_trs_waveform_tracking_validation";
summary.StrictOk = logical(strictOk);
summary.PositiveStrictRows = double(sum(logical(trialT.StrictOk) & string(trialT.TrialType) == "positive_awgn"));
summary.NegativeExpectedRows = double(height(negativeT));
summary.LowSNRSweepRows = double(height(lowSNRT));
summary.TimingOffsetSweepRows = double(height(timingSweepT));
summary.FrequencyOffsetSweepRows = double(height(freqSweepT));
summary.OracleGuardRows = double(height(oracleT));
summary.OracleGuardViolationCount = double(sum(logical(oracleT.Violation)));
summary.source_csv = "reference_signals/csv/trs_trials.csv";
summary.timestamp = sixgr.util.utcNowISO8601();
end

function caps = localToolboxCapabilities()
names = ["nrCarrierConfig","nrCSIRSConfig","nrCSIRS","nrCSIRSIndices", ...
    "nrOFDMModulate","nrOFDMDemodulate","nrTimingEstimate","nrChannelEstimate"];
caps = struct();
caps.implementation_status = "strict_trs_toolbox_capability_report";
for ii = 1:numel(names)
    caps.(char(names(ii))) = ~isempty(which(char(names(ii))));
end
end

function row = localTrialRow()
row = struct("RunId", "", "ScenarioName", "", "TrialId", NaN, "TrialType", "", ...
    "CellId", NaN, "UEId", NaN, "ConfigHash", "", "Frame", NaN, "Slot", NaN, ...
    "CSIRSRowNumber", NaN, "NumCSIRSPorts", NaN, ...
    "DetectionAttempted", false, "DetectionSuccess", false, "DetectionMetric", NaN, ...
    "ResourceCoverageRatio", NaN, "TimingTrackingAttempted", false, ...
    "TRSTimingEstimateAvailable", false, "EstimatedTimingOffset_samples", NaN, ...
    "InjectedTimingOffset_samples", NaN, "TimingError_samples", NaN, ...
    "FrequencyTrackingAttempted", false, "TRSCFOEstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "EstimatedOscillatorCFO_Hz", NaN, "EstimatedCommonFrequency_Hz", NaN, ...
    "PhysicalDoppler_Hz", NaN, "FrequencyEstimateDomain", "", ...
    "FrequencyUnambiguousHalfRange_Hz", NaN, ...
    "InjectedCFO_Hz", NaN, "FrequencyError_Hz", NaN, ...
    "ChannelEstimationAttempted", false, "TRSChannelEstimateAvailable", false, ...
    "NMSE_dB", NaN, "PhaseTrackingError_deg", NaN, "QCLAccuracy", NaN, ...
    "QCLMeasurementStatus", "", ...
    "AppliedAWGNSNR_dB", NaN, "NoiseVariance", NaN, "ChannelModel", "", ...
    "ProxyUsed", false, "Skipped", false, "ToolboxMissing", false, ...
    "UsedOracleFields", "", "TrackingEstimateSource", "", "StrictOk", false, ...
    "TrackingRuntimeEvidenceUsable", false, ...
    "NegativeExpectedOk", false, "Status", "", "FailureReason", "", "TruthStatus", "");
end

function [grids, evidence] = localStandaloneAWGNReferenceGrids(rx, tx, det, timing, ch)
% Independent scoring reference for the deterministic standalone AWGN
% fixture.  The noiseless waveform is retained before AWGN and is never an
% input to timing, detection, frequency, or practical channel estimation.
assert(isfield(rx,"NoiselessWaveform") && ~isempty(rx.NoiselessWaveform), ...
    'sixgr:phy:trs:MissingStandaloneChannelReference');
grids=cell(numel(det.SlotDetections),1);
evidence=grids;
for k=1:numel(grids)
    d=det.SlotDetections(k);
    est=double(timing.Table.EstimatedTimingOffset_samples(k));
    [wave,~]=sixgr.phy.trs.extractTRSReceiveWindow( ...
        rx.NoiselessWaveform,tx,k,est,tx.SlotResources(k));
    referenceRxGrid=sixgr.phy.waveform.ofdmDemodulate( ...
        tx.SlotResources(k).Carrier,wave);
    estimate=ch.ChannelEstimates{k};
    K=size(estimate,1); L=size(estimate,2); R=size(estimate,3);
    indices=double(d.ReferenceIndices(:));
    symbols=d.ReferenceSymbols(:);
    [subcarrier,symbolIndex,port]=ind2sub([K L 1],indices);
    reference=complex(zeros(size(estimate),'like',estimate));
    for r=1:R
        atRx=sub2ind([K L R],subcarrier,symbolIndex,repmat(r,size(subcarrier)));
        atRef=sub2ind([K L R 1],subcarrier,symbolIndex,repmat(r,size(subcarrier)),port);
        reference(atRef)=referenceRxGrid(atRx)./symbols;
    end
    grids{k}=reference;
    evidence{k}=struct( ...
        'Source',"standalone_awgn_known_noiseless_effective_response", ...
        'ReferencePlane',"receiver_grid_after_same_timing_window_before_AWGN", ...
        'RFImpairmentsIncluded',true,'ReceiverEstimatorInput',false, ...
        'GainOrPhaseFitted',false,'AdditionalChannelExecutions',0);
end
end

function row = localSweepRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", "SNRdB", NaN, ...
    "NumTrials", NaN, "DetectionProbability", NaN, "StrictPassProbability", NaN, ...
    "MeanDetectionMetric", NaN, "Status", "");
end

function row = localTimingSweepRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", ...
    "InjectedTimingOffset_samples", NaN, "EstimatedTimingOffset_samples", NaN, ...
    "TimingError_samples", NaN, "StrictOk", false, "Status", "");
end

function row = localFrequencySweepRow()
row = struct("RunId", "", "SweepId", "", "ConfigHash", "", ...
    "InjectedCFO_Hz", NaN, "EstimatedCFO_Hz", NaN, "FrequencyError_Hz", NaN, ...
    "StrictOk", false, "Status", "");
end
