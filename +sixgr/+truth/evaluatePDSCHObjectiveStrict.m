function result = evaluatePDSCHObjectiveStrict(trialTable, cfg, varargin)
%EVALUATEPDSCHOBJECTIVESTRICT Score DL PDSCH raw BLER/BER objectives.
%   The authority for BLER/BER is the raw DL PDSCH receiver trial table.
%   Summary KPIs, configured SNR, labels, and proxy diagnostics are never
%   used as pass/fail evidence.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SourceTable", "air_interface/csv/dl_pdsch_trials.csv", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});

if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 1 || ~istable(trialTable)
    trialTable = table();
end

runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
strictMode = logical(ip.Results.StrictMode) || logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
sourceTable = string(ip.Results.SourceTable);

[maxBLER, maxBER, minDecodeSuccessRate, requiredMatchRate] = localResolveThresholds(cfg, strictMode);
rowAudit = localBuildRowAudit(trialTable, cfg, strictMode);
failureCodes = strings(0, 1);

trialCount = double(height(rowAudit));
positiveMask = logical(rowAudit.PositiveObjectiveRow);
attemptMask = positiveMask & logical(rowAudit.TBAttempted);
attemptCount = double(nnz(attemptMask));
eligibleMask = attemptMask & logical(rowAudit.StrictReceiverEvidenceOk) & ...
    logical(rowAudit.NoProxyEvidenceOk) & ~logical(rowAudit.SkippedOrUnavailable) & ~logical(rowAudit.Crash);
eligibleCount = double(nnz(eligibleMask));

crcKnown = attemptMask & logical(rowAudit.TBCrcKnown);
crcPass = crcKnown & logical(rowAudit.TBCrcPass);
crcFail = crcKnown & ~logical(rowAudit.TBCrcPass);
tbcPassCount = double(nnz(crcPass));
tbcFailCount = double(nnz(crcFail));
missingCRCCount = double(nnz(attemptMask & ~logical(rowAudit.TBCrcKnown)));

if nnz(crcKnown) > 0
    rawBLER = tbcFailCount / double(nnz(crcKnown));
else
    rawBLER = NaN;
end

bitErrors = double(rowAudit.BitErrors);
bitsCompared = double(rowAudit.BitsCompared);
berRows = attemptMask & isfinite(bitErrors) & isfinite(bitsCompared) & bitsCompared > 0;
totalBitErrors = sum(bitErrors(berRows), "omitnan");
totalBitsCompared = sum(bitsCompared(berRows), "omitnan");
if totalBitsCompared > 0
    rawBERWeighted = totalBitErrors / totalBitsCompared;
    rowBER = bitErrors(berRows) ./ max(bitsCompared(berRows), eps);
    rawBERUnweighted = mean(rowBER, "omitnan");
else
    totalBitErrors = NaN;
    totalBitsCompared = NaN;
    rawBERWeighted = NaN;
    rawBERUnweighted = NaN;
end

if attemptCount > 0
    decodeSuccessRate = tbcPassCount / attemptCount;
else
    decodeSuccessRate = NaN;
end

configuredApplicable = logical(rowAudit.ConfiguredEffectiveCheckApplicable);
configuredDenom = double(nnz(attemptMask & configuredApplicable));
if configuredDenom > 0
    configuredMatchRate = double(nnz(attemptMask & configuredApplicable & logical(rowAudit.ConfiguredEffectiveMatch))) / configuredDenom;
else
    configuredMatchRate = NaN;
end

runClass = localResolveRunClass(cfg, trialTable);
fixedAnchor = any(runClass == ["fixed_lls_anchor", "functional_waveform_validation"]);
adaptiveMode = any(runClass == ["adaptive_system_diagnostic", "hybrid_validation"]);
grantBindingRequired = localRequiresPDCCHGrantBinding(cfg);
mimoReferenceRequired = any(attemptMask & double(rowAudit.EffectiveLayers) > 1) && strictMode;
channelRFReferenceRequired = localRequiresChannelRFReference(cfg) && strictMode;
[objectiveMask, objectiveScope, objectiveSNR_dB] = ...
    localObjectiveEvaluationMask(rowAudit, attemptMask, cfg, adaptiveMode);
objectiveTrialCount = double(nnz(objectiveMask));
[objectiveBLER, objectiveBERWeighted, objectiveDecodeSuccessRate] = ...
    localObjectiveMetrics(rowAudit, objectiveMask);

if strictMode && trialCount == 0
    failureCodes(end+1,1) = "dl_pdsch_raw_trials_missing"; %#ok<AGROW>
end
if strictMode && attemptCount == 0
    failureCodes(end+1,1) = "dl_pdsch_raw_decode_attempt_missing"; %#ok<AGROW>
end
if strictMode && eligibleCount < attemptCount
    badEvidence = attemptMask & ~logical(rowAudit.StrictReceiverEvidenceOk);
    if any(badEvidence & (~logical(rowAudit.ChannelEstimateAttempted) | ~logical(rowAudit.ChannelEstimateAvailable)))
        failureCodes(end+1,1) = "dl_pdsch_channel_estimate_missing"; %#ok<AGROW>
    end
    if any(badEvidence & (~logical(rowAudit.EqualizationAttempted) | ~logical(rowAudit.EqualizationAvailable)))
        failureCodes(end+1,1) = "dl_pdsch_equalization_missing"; %#ok<AGROW>
    end
    if any(badEvidence & (~logical(rowAudit.DLSCHDecodeAttempted) | ~logical(rowAudit.DLSCHDecodeAvailable)))
        failureCodes(end+1,1) = "dl_pdsch_dlsch_decode_missing"; %#ok<AGROW>
    end
end
if strictMode && any(attemptMask & ~logical(rowAudit.NoProxyEvidenceOk))
    failureCodes(end+1,1) = "dl_pdsch_proxy_path"; %#ok<AGROW>
end
if strictMode && any(attemptMask & logical(rowAudit.SkippedOrUnavailable))
    failureCodes(end+1,1) = "dl_pdsch_skipped_ok_path"; %#ok<AGROW>
end
if strictMode && missingCRCCount > 0
    failureCodes(end+1,1) = "dl_pdsch_tbc_crc_missing"; %#ok<AGROW>
end
if strictMode && objectiveTrialCount == 0
    failureCodes(end+1,1) = "dl_pdsch_objective_evaluation_trials_missing"; %#ok<AGROW>
end
if strictMode && ~(isfinite(objectiveBLER))
    failureCodes(end+1,1) = "dl_pdsch_raw_bler_missing"; %#ok<AGROW>
elseif isfinite(maxBLER) && isfinite(objectiveBLER) && objectiveBLER > maxBLER + eps
    failureCodes(end+1,1) = "dl_pdsch_bler_objective_failed"; %#ok<AGROW>
end
if strictMode && ~(isfinite(objectiveBERWeighted))
    failureCodes(end+1,1) = "dl_pdsch_raw_ber_missing"; %#ok<AGROW>
elseif isfinite(maxBER) && isfinite(objectiveBERWeighted) && objectiveBERWeighted > maxBER + eps
    failureCodes(end+1,1) = "dl_pdsch_ber_objective_failed"; %#ok<AGROW>
end
if isfinite(minDecodeSuccessRate) && isfinite(objectiveDecodeSuccessRate) && ...
        objectiveDecodeSuccessRate + eps < minDecodeSuccessRate
    failureCodes(end+1,1) = "dl_pdsch_decode_success_objective_failed"; %#ok<AGROW>
end
if fixedAnchor && configuredDenom > 0 && isfinite(configuredMatchRate) && configuredMatchRate + eps < requiredMatchRate
    failureCodes(end+1,1) = "dl_pdsch_configured_effective_mismatch"; %#ok<AGROW>
    if any(attemptMask & configuredApplicable & ~logical(rowAudit.LayerMatch))
        failureCodes(end+1,1) = "dl_pdsch_rank_layer_collapse"; %#ok<AGROW>
    end
    if any(attemptMask & configuredApplicable & (~logical(rowAudit.MCSMatch) | ~logical(rowAudit.ModulationMatch)))
        failureCodes(end+1,1) = "dl_pdsch_mcs_modulation_collapse"; %#ok<AGROW>
    end
end
if adaptiveMode && fixedAnchor
    failureCodes(end+1,1) = "dl_pdsch_adaptive_mode_ambiguous_with_fixed_anchor"; %#ok<AGROW>
end
if grantBindingRequired && any(attemptMask & ~logical(rowAudit.GrantBindingOk))
    failureCodes(end+1,1) = "dl_pdsch_grant_binding_missing"; %#ok<AGROW>
end
if mimoReferenceRequired && any(attemptMask & double(rowAudit.EffectiveLayers) > 1 & ~logical(rowAudit.MIMOEvidenceReferenceOk))
    failureCodes(end+1,1) = "dl_pdsch_mimo_reference_missing"; %#ok<AGROW>
end
if channelRFReferenceRequired && any(attemptMask & ~logical(rowAudit.ChannelRFReferenceOk))
    failureCodes(end+1,1) = "dl_pdsch_channel_rf_reference_missing"; %#ok<AGROW>
end

failureCodes = unique(failureCodes(strlength(failureCodes) > 0), "stable");
objectivePass = isempty(failureCodes);
truthStatus = string("real_lls_evidence");
if trialCount == 0
    truthStatus = "unavailable";
elseif ~objectivePass
    truthStatus = "strict_objective_failed";
end

codeBlockErrors = localNumericColumn(trialTable, ["CodeBlockErrors","CodeBlockErrorCount"], NaN);
codeBlockCount = localNumericColumn(trialTable, ["CodeBlockCount","NumCodeBlocks"], NaN);
decoderFailureCount = double(nnz(attemptMask & (~logical(rowAudit.DLSCHDecodeAttempted) | ~logical(rowAudit.DLSCHDecodeAvailable))));
highSNRPositivePassCount = double(nnz(attemptMask & logical(rowAudit.TBCrcPass) & double(rowAudit.SNR_dB) >= localHighSNRThreshold(cfg)));
outageRowCount = double(nnz(positiveMask & contains(lower(string(rowAudit.ObjectiveRowClass)), ["outage","stress"])));

summary = table( ...
    runId, scenarioName, "DL", "sixgr.truth.evaluatePDSCHObjectiveStrict", strictMode, ...
    trialCount, double(nnz(positiveMask)), attemptCount, double(nnz(attemptMask & ~logical(rowAudit.IsRetransmission))), ...
    double(nnz(attemptMask & logical(rowAudit.IsRetransmission))), eligibleCount, ...
    tbcPassCount, tbcFailCount, missingCRCCount, rawBLER, rawBLER, NaN, ...
    totalBitErrors, totalBitsCompared, rawBERWeighted, rawBERUnweighted, ...
    sum(codeBlockErrors(isfinite(codeBlockErrors)), "omitnan"), sum(codeBlockCount(isfinite(codeBlockCount)), "omitnan"), ...
    decoderFailureCount, highSNRPositivePassCount, outageRowCount, ...
    objectiveScope, objectiveSNR_dB, objectiveTrialCount, ...
    objectiveBLER, objectiveBERWeighted, objectiveDecodeSuccessRate, ...
    maxBLER, maxBER, minDecodeSuccessRate, decodeSuccessRate, requiredMatchRate, configuredMatchRate, ...
    runClass, fixedAnchor, adaptiveMode, grantBindingRequired, mimoReferenceRequired, channelRFReferenceRequired, ...
    objectivePass, objectivePass, objectivePass, truthStatus, strjoin(failureCodes, "|"), sourceTable, ...
    'VariableNames', {'RunId','ScenarioName','Direction','ProducerModule','StrictMode', ...
    'TrialCount','PositiveTrialCount','TBAttemptCount','NewDataTBAttemptCount','RetransmissionAttemptCount','ObjectiveEligibleRowCount', ...
    'TBCrcPassCount','TBCrcFailCount','MissingTBCrcCount','RawBLER','RawNewDataBLER','RawFinalDeliveryBLER', ...
    'BitErrors','BitsCompared','RawBERWeighted','RawBERUnweighted', ...
    'CodeBlockErrorCount','CodeBlockCount','DecoderFailureCount','HighSNRPositivePassCount','OutageRowCount', ...
    'ObjectiveEvaluationScope','ObjectiveEvaluationSNR_dB','ObjectiveTrialCount', ...
    'ObjectiveBLER','ObjectiveBERWeighted','ObjectiveDecodeSuccessRate', ...
    'RawBLERObjectiveThreshold','RawBERObjectiveThreshold','RequiredDecodeSuccessRate','DecodeSuccessRate','RequiredConfiguredMatchRate','ConfiguredEffectiveMatchRate', ...
    'RunClass','FixedAnchorMode','AdaptiveMode','GrantBindingRequired','MIMOReferenceRequired','ChannelRFReferenceRequired', ...
    'ObjectivePass','ScenarioObjectiveOk','ResultOk','TruthStatus','FailureReason','SourceTable'});

failures = localBuildFailureTable(runId, scenarioName, failureCodes, summary);

result = struct();
result.ObjectivePass = objectivePass;
result.ScenarioObjectiveOk = objectivePass;
result.ResultOk = objectivePass;
result.Summary = summary;
result.RowAudit = rowAudit;
result.Failures = failures;
result.FailureCodes = failureCodes;
end

function rowAudit = localBuildRowAudit(T, cfg, strictMode)
n = height(T);
if n == 0
    rowAudit = localEmptyRowAudit();
    return;
end

direction = upper(strtrim(string(localColumn(T, "Direction", repmat("DL", n, 1)))));
status = string(localColumn(T, "Status", repmat("", n, 1)));
notes = string(localColumn(T, "Notes", repmat("", n, 1)));
truthStatus = string(localColumn(T, "TruthStatus", repmat("", n, 1)));
sourceText = lower(status + " " + notes + " " + truthStatus + " " + ...
    string(localColumn(T, "PostEqSINRSource", repmat("", n, 1))) + " " + ...
    string(localColumn(T, "MeasuredTrialSINRSource", repmat("", n, 1))));

negative = localBoolColumn(T, ["ExpectedNegative","NegativeExpected","FaultInjectionExpected"], false) | ...
    contains(lower(status), ["negative_expected","expected_negative"]) | ...
    contains(lower(notes), ["negative_expected","fault_injection","wrong_","corrupt"]);
positive = direction == "DL" & ~negative;
crash = localBoolColumn(T, "Crash", false) | contains(lower(status), "crash");
skipped = localBoolColumn(T, ["Skipped","Skip","Unavailable"], false) | ...
    contains(lower(status + " " + notes + " " + truthStatus), ["skip","skipped","unavailable","unsupported"]);
proxy = contains(sourceText, ["proxy","fallback","synthetic","summary","configured_snr","reference_snr","oracle","perfect"]);

tbSize = localNumericColumn(T, ["TBSize_bits","TBS","TBSBits","TransportBlockSize"], NaN);
decodeAttempted = localBoolColumn(T, ["DLSCHDecodeAttempted","DecodeAttempted"], false);
tbAttempted = positive & (tbSize > 0 | decodeAttempted);

[crcKnown, crcPass] = localCRCColumn(T);
bitsCompared = localNumericColumn(T, ["BitsCompared","BitCount"], NaN);
bitErrors = localNumericColumn(T, ["BitErrors","BitErrorCount"], NaN);

strictReceiver = localBoolColumn(T, "StrictReceiverEvidenceOk", false);
if ~ismember("StrictReceiverEvidenceOk", string(T.Properties.VariableNames))
    strictReceiver = localStrictReceiverFromColumns(T);
end

chanAttempt = localBoolColumn(T, "ChannelEstimateAttempted", false);
chanAvail = localBoolColumn(T, "ChannelEstimateAvailable", false);
resAttempt = localBoolColumn(T, "ResourceExtractionAttempted", false);
resAvail = localBoolColumn(T, "ResourceExtractionAvailable", false);
eqAttempt = localBoolColumn(T, "EqualizationAttempted", false);
eqAvail = localBoolColumn(T, "EqualizationAvailable", false);
dlschAttempt = localBoolColumn(T, ["DLSCHDecodeAttempted","DecodeAttempted"], false);
dlschAvail = localBoolColumn(T, "DLSCHDecodeAvailable", localBoolColumn(T, "DecodeUsable", false));
llrAvail = localBoolColumn(T, "LLRAvailable", false);
llrFinite = localBoolColumn(T, "LLRFinite", false);
postEqAvailable = localBoolColumn(T, "PostEqSINRAvailable", false);
postEqReceiverDerived = localBoolColumn(T, "PostEqSINRReceiverDerived", false);
sinrStatus = string(localColumn(T, "SINRValidationStatus", repmat("", n, 1)));
sinrReason = string(localColumn(T, "SINRValidationReason", repmat("", n, 1)));

snr = localNumericColumn(T, ["SNR_dB","ConfiguredSNR_dB"], NaN);
mcs = localNumericColumn(T, ["MCS","MCSIndex","EffectiveMCSIndex"], NaN);
modulation = upper(strtrim(string(localColumn(T, ["Modulation","EffectiveModulation"], repmat("", n, 1)))));
layers = localNumericColumn(T, ["Layers","EffectiveLayers"], NaN);
rank = localNumericColumn(T, ["EffectiveRank","RankEstimate"], layers);
cfgMCS = localConfiguredNumericColumn(T, cfg, ["ConfiguredMCSIndex","ConfiguredMCS","ScenarioMCSObjective"], ...
    ["phy.pdsch.mcsIndex","pdsch6gr.MCSIndex","validation.dl_pdsch.mcs_index"]);
cfgMod = localConfiguredStringColumn(T, cfg, ["ConfiguredModulation","ScenarioModulationObjective"], ...
    ["phy.pdsch.modulation","pdsch6gr.Modulation","validation.dl_pdsch.modulation"]);
cfgLayers = localConfiguredNumericColumn(T, cfg, ["ConfiguredLayers","ConfiguredNumLayers","ScenarioLayerObjective"], ...
    ["phy.pdsch.numLayers","phy.pdsch.nLayers","pdsch6gr.NumLayers","validation.dl_pdsch.num_layers"]);
cfgRank = localConfiguredNumericColumn(T, cfg, ["ConfiguredRank","ScenarioRankObjective"], ...
    ["phy.pdsch.rank","mimo.rank","validation.dl_pdsch.rank"]);
cfgRank(~isfinite(cfgRank)) = cfgLayers(~isfinite(cfgRank));

mcsApplicable = isfinite(cfgMCS);
modApplicable = strlength(cfgMod) > 0;
layerApplicable = isfinite(cfgLayers);
rankApplicable = isfinite(cfgRank);
mcsMatch = ~mcsApplicable | (isfinite(mcs) & round(mcs) == round(cfgMCS));
modMatch = ~modApplicable | (upper(modulation) == upper(strtrim(cfgMod)));
layerMatch = ~layerApplicable | (isfinite(layers) & round(layers) == round(cfgLayers));
rankMatch = ~rankApplicable | (isfinite(rank) & round(rank) == round(cfgRank));
configuredApplicable = mcsApplicable | modApplicable | layerApplicable | rankApplicable;
configuredMatch = mcsMatch & modMatch & layerMatch & rankMatch;

grantBindingRequired = sixgr.control.isPDCCHGrantBindingRequired(cfg, "DL");
grantBindingOk = localBoolColumn(T, ["PDCCHGrantBindingOk","GrantBindingOk"], false);
mimoId = strtrim(string(localColumn(T, ["MIMOTrialId","RankLayerEvidenceId","PrecoderEvidenceId"], repmat("", n, 1))));
mimoRuntimeColumns = isfinite(localNumericColumn(T, "PrecodingNumLayers", NaN)) | ...
    isfinite(localNumericColumn(T, "PrecodingNumPorts", NaN)) | ...
    strlength(strtrim(string(localColumn(T, "AppliedPrecoderPMIType", repmat("", n, 1))))) > 0;
mimoReferenceOk = strlength(mimoId) > 0 | (layers <= 1) | mimoRuntimeColumns;
channelId = strtrim(string(localColumn(T, ["ChannelRealizationId","RFImpairmentChainId","DownstreamChannelReferenceId"], repmat("", n, 1))));
channelMode = strtrim(string(localColumn(T, "ChannelComplianceMode", repmat("", n, 1))));
channelSource = strtrim(string(localColumn(T, ["AppliedLargeScaleGainSource","PathlossModelSource"], repmat("", n, 1))));
channelReferenceOk = strlength(channelId) > 0 | strlength(channelMode) > 0 | strlength(channelSource) > 0;

rowFailure = strings(n, 1);
for i = 1:n
    reasons = strings(0, 1);
    if positive(i) && tbAttempted(i)
        if ~strictReceiver(i), reasons(end+1,1) = "strict_receiver_evidence_incomplete"; end %#ok<AGROW>
        if ~chanAttempt(i) || ~chanAvail(i), reasons(end+1,1) = "channel_estimate_missing"; end %#ok<AGROW>
        if ~eqAttempt(i) || ~eqAvail(i), reasons(end+1,1) = "equalization_missing"; end %#ok<AGROW>
        if ~dlschAttempt(i) || ~dlschAvail(i), reasons(end+1,1) = "dlsch_decode_missing"; end %#ok<AGROW>
        if proxy(i), reasons(end+1,1) = "proxy_or_fallback_marker"; end %#ok<AGROW>
        if skipped(i), reasons(end+1,1) = "skipped_or_unavailable"; end %#ok<AGROW>
        if ~crcKnown(i), reasons(end+1,1) = "tbc_crc_missing"; end %#ok<AGROW>
        if bitsCompared(i) <= 0 || ~isfinite(bitsCompared(i)), reasons(end+1,1) = "ber_denominator_missing"; end %#ok<AGROW>
        if configuredApplicable(i) && ~configuredMatch(i), reasons(end+1,1) = "configured_effective_mismatch"; end %#ok<AGROW>
        if grantBindingRequired && ~grantBindingOk(i), reasons(end+1,1) = "pdcch_grant_binding_failed"; end %#ok<AGROW>
    end
    rowFailure(i) = strjoin(unique(reasons, "stable"), "|");
end

objectiveRowPass = positive & tbAttempted & strictReceiver & ~proxy & ~skipped & ~crash & crcKnown & ...
    isfinite(bitsCompared) & bitsCompared > 0 & configuredMatch & ...
    (~grantBindingRequired | grantBindingOk);
objectiveClass = repmat("positive_runtime_trial", n, 1);
objectiveClass(negative) = "negative_or_fault_trial_excluded";
objectiveClass(~positive & ~negative) = "non_dl_or_not_applicable";

rowAudit = table( ...
    (1:n)', positive, tbAttempted, objectiveRowPass, strictReceiver, ...
    chanAttempt, chanAvail, resAttempt, resAvail, eqAttempt, eqAvail, dlschAttempt, dlschAvail, ...
    llrAvail, llrFinite, postEqAvailable, postEqReceiverDerived, ...
    double(localNumericColumn(T, ["PostEqSINRWidebanddB","PostEqSINR_dB","MeasuredTrialSINR_dB"], NaN)), ...
    sinrStatus, sinrReason, localBoolColumn(T, "ConfiguredSNRLikeSourceRejected", false), ...
    crcKnown, crcPass, bitErrors, bitsCompared, snr, ...
    mcs, modulation, layers, rank, cfgMCS, cfgMod, cfgLayers, cfgRank, ...
    configuredApplicable, configuredMatch, mcsMatch, modMatch, layerMatch, rankMatch, ...
    proxy, skipped, crash, localBoolColumn(T, ["HARQIsRetransmission","IsRetransmission"], false), ...
    grantBindingOk, mimoReferenceOk, channelReferenceOk, objectiveClass, rowFailure, ...
    'VariableNames', {'TrialRow','PositiveObjectiveRow','TBAttempted','ObjectiveRowPass','StrictReceiverEvidenceOk', ...
    'ChannelEstimateAttempted','ChannelEstimateAvailable','ResourceExtractionAttempted','ResourceExtractionAvailable', ...
    'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
    'LLRAvailable','LLRFinite','PostEqSINRAvailable','PostEqSINRReceiverDerived','PostEqSINRWidebanddB', ...
    'SINRValidationStatus','SINRValidationReason','ConfiguredSNRLikeSourceRejected', ...
    'TBCrcKnown','TBCrcPass','BitErrors','BitsCompared','SNR_dB', ...
    'EffectiveMCSIndex','EffectiveModulation','EffectiveLayers','EffectiveRank','ConfiguredMCSIndex','ConfiguredModulation','ConfiguredLayers','ConfiguredRank', ...
    'ConfiguredEffectiveCheckApplicable','ConfiguredEffectiveMatch','MCSMatch','ModulationMatch','LayerMatch','RankMatch', ...
    'NoProxyEvidenceOk','SkippedOrUnavailable','Crash','IsRetransmission', ...
    'GrantBindingOk','MIMOEvidenceReferenceOk','ChannelRFReferenceOk','ObjectiveRowClass','RowFailureReason'});
rowAudit.NoProxyEvidenceOk = ~rowAudit.NoProxyEvidenceOk;
if ~strictMode
    rowAudit.ObjectiveRowPass = positive & tbAttempted;
end
end

function [mask, scope, snr_dB] = localObjectiveEvaluationMask(rowAudit, attemptMask, cfg, adaptiveMode)
mask = logical(attemptMask);
scope = "all_positive_decode_attempts";
snr_dB = NaN;
sweepEnabled = logical(sixgr.util.structGet(cfg, "run.snrSweepEnabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "sweeps_and_matrix.snr_sweep.enabled", false));
if ~(logical(adaptiveMode) && sweepEnabled)
    return;
end

snrValues = double(rowAudit.SNR_dB);
available = snrValues(mask & isfinite(snrValues));
if isempty(available)
    mask(:) = false;
    scope = "highest_configured_snr_bin_unavailable";
    return;
end
snr_dB = max(available);
tolerance = max(1e-9, 32 * eps(max(1, abs(snr_dB))));
mask = mask & isfinite(snrValues) & abs(snrValues - snr_dB) <= tolerance;
scope = "highest_configured_snr_bin";
end

function [bler, ber, decodeSuccessRate] = localObjectiveMetrics(rowAudit, mask)
crcKnown = logical(mask) & logical(rowAudit.TBCrcKnown);
if any(crcKnown)
    bler = nnz(crcKnown & ~logical(rowAudit.TBCrcPass)) / nnz(crcKnown);
else
    bler = NaN;
end

bitErrors = double(rowAudit.BitErrors);
bitsCompared = double(rowAudit.BitsCompared);
berMask = logical(mask) & isfinite(bitErrors) & ...
    isfinite(bitsCompared) & bitsCompared > 0;
if any(berMask)
    ber = sum(bitErrors(berMask), "omitnan") / ...
        sum(bitsCompared(berMask), "omitnan");
else
    ber = NaN;
end

if any(mask)
    decodeSuccessRate = nnz(logical(mask) & logical(rowAudit.TBCrcKnown) & ...
        logical(rowAudit.TBCrcPass)) / nnz(mask);
else
    decodeSuccessRate = NaN;
end
end

function T = localEmptyRowAudit()
T = table('Size', [0, 49], ...
    'VariableTypes', {'double','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','double','string','string','logical','logical','logical','double','double','double','double','string','double','double','double','string','double','double','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','logical','string','string'}, ...
    'VariableNames', {'TrialRow','PositiveObjectiveRow','TBAttempted','ObjectiveRowPass','StrictReceiverEvidenceOk', ...
    'ChannelEstimateAttempted','ChannelEstimateAvailable','ResourceExtractionAttempted','ResourceExtractionAvailable', ...
    'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
    'LLRAvailable','LLRFinite','PostEqSINRAvailable','PostEqSINRReceiverDerived','PostEqSINRWidebanddB', ...
    'SINRValidationStatus','SINRValidationReason','ConfiguredSNRLikeSourceRejected', ...
    'TBCrcKnown','TBCrcPass','BitErrors','BitsCompared','SNR_dB', ...
    'EffectiveMCSIndex','EffectiveModulation','EffectiveLayers','EffectiveRank','ConfiguredMCSIndex','ConfiguredModulation','ConfiguredLayers','ConfiguredRank', ...
    'ConfiguredEffectiveCheckApplicable','ConfiguredEffectiveMatch','MCSMatch','ModulationMatch','LayerMatch','RankMatch', ...
    'NoProxyEvidenceOk','SkippedOrUnavailable','Crash','IsRetransmission', ...
    'GrantBindingOk','MIMOEvidenceReferenceOk','ChannelRFReferenceOk','ObjectiveRowClass','RowFailureReason'});
end

function failures = localBuildFailureTable(runId, scenarioName, codes, summary)
if isempty(codes)
    failures = table('Size', [0, 8], ...
        'VariableTypes', {'string','string','double','string','string','string','double','string'}, ...
        'VariableNames', {'RunId','ScenarioName','FailureIndex','FailureCode','FailureCategory','FailureSeverity','RequiredFailureCountContribution','FailureDefinition'});
    return;
end
n = numel(codes);
failures = table( ...
    repmat(runId, n, 1), repmat(scenarioName, n, 1), (1:n)', codes(:), ...
    repmat("dl_pdsch_objective", n, 1), repmat("high", n, 1), ones(n, 1), ...
    strings(n, 1), ...
    'VariableNames', {'RunId','ScenarioName','FailureIndex','FailureCode','FailureCategory','FailureSeverity','RequiredFailureCountContribution','FailureDefinition'});
for i = 1:n
    failures.FailureDefinition(i) = localFailureDefinition(codes(i), summary);
end
end

function text = localFailureDefinition(code, summary)
switch string(code)
    case "dl_pdsch_bler_objective_failed"
        text = "Objective-scope raw decoder BLER exceeded threshold: raw=" + string(summary.ObjectiveBLER(1)) + ...
            ", threshold=" + string(summary.RawBLERObjectiveThreshold(1));
    case "dl_pdsch_ber_objective_failed"
        text = "Objective-scope weighted raw decoder BER exceeded threshold: raw=" + string(summary.ObjectiveBERWeighted(1)) + ...
            ", threshold=" + string(summary.RawBERObjectiveThreshold(1));
    case "dl_pdsch_configured_effective_mismatch"
        text = "Fixed-anchor configured MCS/modulation/layers/rank did not match effective raw PDSCH rows.";
    otherwise
        text = string(code);
end
end

function [maxBLER, maxBER, minDecode, requiredMatch] = localResolveThresholds(cfg, strictMode)
maxBLER = localFirstFinite( ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.max_bler", NaN), ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.maxBLER", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.objective.maxBLER", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.maxBLER", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", NaN), ...
    sixgr.util.structGet(cfg, "pdsch6gr.ObjectiveMaxBLER", NaN));
maxBER = localFirstFinite( ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.max_ber", NaN), ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.maxBER", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.objective.maxBER", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.maxBER", NaN), ...
    sixgr.util.structGet(cfg, "pdsch6gr.ObjectiveMaxBER", NaN));
requiredMatch = localFirstFinite( ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.required_configured_match_rate", NaN), ...
    sixgr.util.structGet(cfg, "scenario.required_configured_match_rate", NaN), ...
    sixgr.util.structGet(cfg, "validation.required_configured_match_rate", NaN));
if ~isfinite(requiredMatch)
    requiredMatch = 0.999;
end
if ~isfinite(maxBLER) && strictMode
    maxBLER = 0.10;
end
if ~isfinite(maxBER) && strictMode
    maxBER = 1e-3;
end
minDecode = localFirstFinite( ...
    sixgr.util.structGet(cfg, "validation.dl_pdsch.min_decode_success_rate", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.objective.minDecodeSuccessRate", NaN));
if ~isfinite(minDecode) && isfinite(maxBLER)
    minDecode = max(0, min(1, 1 - maxBLER));
end
end

function tf = localStrictReceiverFromColumns(T)
tf = localBoolColumn(T, "ChannelEstimateAttempted", false) & ...
    localBoolColumn(T, "ChannelEstimateAvailable", false) & ...
    localBoolColumn(T, "ResourceExtractionAttempted", false) & ...
    localBoolColumn(T, "ResourceExtractionAvailable", false) & ...
    localBoolColumn(T, "EqualizationAttempted", false) & ...
    localBoolColumn(T, "EqualizationAvailable", false) & ...
    localBoolColumn(T, ["DLSCHDecodeAttempted","DecodeAttempted"], false) & ...
    localBoolColumn(T, ["DLSCHDecodeAvailable","DecodeUsable"], false) & ...
    localBoolColumn(T, "LLRAvailable", false) & ...
    localBoolColumn(T, "LLRFinite", false) & ...
    localBoolColumn(T, "PostEqSINRAvailable", false) & ...
    localBoolColumn(T, "PostEqSINRReceiverDerived", false);
end

function [known, pass] = localCRCColumn(T)
n = height(T);
known = false(n, 1);
pass = false(n, 1);
names = string(T.Properties.VariableNames);
candidate = "";
for c = ["TBCrcPass","TBCRCPass","CRCPass","CRCOK"]
    if any(names == c)
        candidate = c;
        break;
    end
end
if strlength(candidate) == 0
    return;
end
raw = T.(char(candidate));
if islogical(raw)
    known = true(n, 1);
    pass = logical(raw);
elseif isnumeric(raw)
    values = double(raw);
    known = isfinite(values);
    pass = values ~= 0;
elseif isstring(raw) || iscellstr(raw) || ischar(raw)
    values = lower(strtrim(string(raw)));
    known = strlength(values) > 0 & ~ismissing(values);
    pass = any(values == ["true","1","ok","pass","passed"], 2);
end
end

function values = localColumn(T, names, defaultValue)
if ischar(names) || (isstring(names) && isscalar(names))
    names = string(names);
end
tableNames = string(T.Properties.VariableNames);
for name = string(names(:))'
    if any(tableNames == name)
        values = T.(char(name));
        return;
    end
end
if nargin < 3
    defaultValue = NaN;
end
if isstring(defaultValue) && numel(defaultValue) == height(T)
    values = reshape(defaultValue, height(T), 1);
elseif ischar(defaultValue) || (isstring(defaultValue) && isscalar(defaultValue))
    values = repmat(string(defaultValue), height(T), 1);
elseif islogical(defaultValue) && numel(defaultValue) == height(T)
    values = reshape(logical(defaultValue), height(T), 1);
elseif isnumeric(defaultValue) && numel(defaultValue) == height(T)
    values = reshape(double(defaultValue), height(T), 1);
elseif islogical(defaultValue)
    values = repmat(logical(defaultValue), height(T), 1);
else
    values = repmat(double(defaultValue), height(T), 1);
end
end

function values = localNumericColumn(T, names, defaultValue)
raw = localColumn(T, names, defaultValue);
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end

function values = localBoolColumn(T, names, defaultValue)
raw = localColumn(T, names, defaultValue);
if islogical(raw)
    values = logical(raw(:));
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    s = lower(strtrim(string(raw(:))));
    values = any(s == ["true","1","yes","ok","pass","passed"], 2);
end
end

function values = localConfiguredNumericColumn(T, cfg, columns, cfgPaths)
values = localNumericColumn(T, columns, NaN);
if any(isfinite(values))
    return;
end
v = NaN;
for p = cfgPaths
    raw = sixgr.util.structGet(cfg, p, NaN);
    if isnumeric(raw) || islogical(raw)
        candidate = double(raw);
    else
        candidate = str2double(string(raw));
    end
    candidate = candidate(:);
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        v = candidate(1);
        break;
    end
end
values = repmat(v, height(T), 1);
end

function values = localConfiguredStringColumn(T, cfg, columns, cfgPaths)
values = string(localColumn(T, columns, repmat("", height(T), 1)));
if any(strlength(strtrim(values)) > 0)
    return;
end
v = "";
for p = cfgPaths
    v = string(sixgr.util.structGet(cfg, p, ""));
    if strlength(strtrim(v)) > 0
        break;
    end
end
values = repmat(v, height(T), 1);
end

function value = localFirstFinite(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function runClass = localResolveRunClass(cfg, T)
runClass = localNormalizeRunClassToken(sixgr.util.structGet(cfg, "validation.RunClass", ...
    sixgr.util.structGet(cfg, "validation.run_class", "")));
if strlength(runClass) > 0
    return;
end
if istable(T) && height(T) > 0 && ismember("RunClass", string(T.Properties.VariableNames))
    runClass = localNormalizeRunClassToken(string(T.RunClass(1)));
    if strlength(runClass) > 0
        return;
    end
end

mode = lower(strtrim(string([ ...
    localScalarString(sixgr.util.structGet(cfg, "link_adaptation.fixed_or_amc", "")), ...
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "")), ...
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", "")), ...
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", "")), ...
    localScalarString(sixgr.util.structGet(cfg, "validation.dl_pdsch.mode", "")) ...
    ])));
mode = mode(strlength(mode) > 0);
adaptiveTokens = ["amc","adaptive","dynamic","dynamic_link_adaptation","cqi","cqi_driven", ...
    "baseline","actual_bler_based","effective_sinr_driven"];
fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"];
adaptiveMode = any(ismember(mode, adaptiveTokens));
fixedMode = any(ismember(mode, fixedTokens)) && ~adaptiveMode;
fixedCampaignEnabled = logical(sixgr.util.structGet(cfg, "validation.fixed_link_campaign.enabled", false));
rankFixed = any(ismember(lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", "")))), fixedTokens));
layersFixed = isfinite(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN))));
modulationFixed = strlength(strtrim(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "")))) > 0;

if fixedCampaignEnabled && adaptiveMode
    runClass = "hybrid_validation";
elseif fixedMode && rankFixed && layersFixed && modulationFixed
    runClass = "fixed_lls_anchor";
else
    runClass = "adaptive_system_diagnostic";
end
end

function runClass = localNormalizeRunClassToken(raw)
token = lower(strtrim(string(raw)));
if any(token == ["fixed_lls_anchor", "functional_waveform_validation", ...
        "adaptive_system_diagnostic", "hybrid_validation"])
    runClass = token;
else
    runClass = "";
end
end

function value = localScalarString(raw)
value = "";
if isempty(raw)
    return;
end
vals = string(raw(:));
if ~isempty(vals)
    value = vals(1);
end
end

function tf = localRequiresPDCCHGrantBinding(cfg)
tf = sixgr.control.isPDCCHGrantBindingRequired(cfg, "DL");
end

function tf = localRequiresChannelRFReference(cfg)
if logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false))
    tf = false;
    return;
end
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
fading = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.fading.model", ""))));
rfEnabled = logical(sixgr.util.structGet(cfg, "rf.enabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.rfImpairments.enabled", false));
tf = rfEnabled || (~ismember(model, ["", "AWGN", "NONE", "OFF"]) || ...
    (strlength(fading) > 0 && ~ismember(fading, ["AWGN","NONE","OFF"])));
end

function v = localHighSNRThreshold(cfg)
v = double(sixgr.util.structGet(cfg, "validation.dl_pdsch.high_snr_threshold_db", 20));
if ~(isscalar(v) && isfinite(v))
    v = 20;
end
end
