function artifacts = exportLLSLiveDerivedTables(cfg, runFolder, rawTrials, multiUser, mobilityArtifacts, slotTrace)
%EXPORTLLSLIVEDERIVEDTABLES Publish live LLS summary tables from raw trials.

if nargin < 4 || ~isstruct(multiUser)
    multiUser = struct();
end
if nargin < 5 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
if nargin < 6 || ~isstruct(slotTrace)
    slotTrace = struct();
end

artifacts = struct();
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.HARQCSVDir);

dlT = sixgr.util.structGet(rawTrials, "DL", table());
ulT = sixgr.util.structGet(rawTrials, "UL", table());
srsT = sixgr.util.structGet(rawTrials, "SRS", table());
trsT = sixgr.util.structGet(rawTrials, "TRS", table());
multiUserDL = sixgr.util.structGet(rawTrials, "MultiUserDL", table());
multiUserUL = sixgr.util.structGet(rawTrials, "MultiUserUL", table());

artifacts.ChannelEstimationStatsPath = fullfile(layout.ReportCSVDir, "live_channel_estimation_stats.csv");
artifacts.RankEstimationStatsPath = fullfile(layout.ReportCSVDir, "live_rank_estimation_stats.csv");
artifacts.BeamSelectionStatsPath = fullfile(layout.ReportCSVDir, "live_beam_selection_stats.csv");
artifacts.CSIFeedbackStatsPath = fullfile(layout.ReportCSVDir, "live_csi_feedback_stats.csv");
artifacts.CSIRSStatsPath = fullfile(layout.ReportCSVDir, "live_csirs_stats.csv");
artifacts.UserPerformancePath = fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv");
artifacts.CoverageLayerPath = fullfile(layout.ReportCSVDir, "live_coverage_layer.csv");
artifacts.ErrorRateSummaryPath = fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv");
artifacts.LiveHARQSummaryPath = fullfile(layout.HARQCSVDir, "live_harq_observation_summary.csv");
artifacts.LiveHARQTimelinePath = fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv");
artifacts.AntennaConfigResolvedPath = fullfile(layout.ReportCSVDir, "antenna_config_resolved.csv");
artifacts.AntennaRuntimeEvidencePath = fullfile(layout.ReportCSVDir, "antenna_runtime_evidence.csv");
artifacts.ChannelArrayConsistencyPath = fullfile(layout.ReportCSVDir, "channel_array_consistency.csv");
artifacts.TodToaTracePath = fullfile(layout.ReportCSVDir, "tod_toa_trace.csv");
artifacts.TimingPositioningEvidencePath = fullfile(layout.ReportCSVDir, "timing_positioning_runtime_evidence.csv");

channelT = localBuildChannelStatsTable(dlT, ulT, srsT, trsT);
rankT = localBuildRankStatsTable(dlT, ulT);
beamT = localBuildBeamStatsTable(dlT, ulT);
csiT = localBuildCSIStatsTable(dlT, ulT);
csirsT = localBuildCSIRSStatsTable(dlT, srsT, trsT);
userPerfT = sixgr.util.structGet(slotTrace, "UserPerformanceTable", table());
if ~(istable(userPerfT) && ~isempty(userPerfT))
    userPerfT = localBuildUserPerformanceTable(multiUserDL, multiUserUL, dlT, ulT);
end
coverageT = sixgr.util.structGet(slotTrace, "CoverageLayerTable", table());
if ~(istable(coverageT) && ~isempty(coverageT))
    coverageT = localBuildCoverageLayerTable(mobilityArtifacts, userPerfT);
end
errorRateT = localBuildErrorRateSummaryTable(dlT, ulT);
harqSummaryT = sixgr.util.structGet(slotTrace, "HARQSummaryTable", table());
harqTimelineT = sixgr.util.structGet(slotTrace, "HARQTimelineTable", table());
if ~(istable(harqSummaryT) && ismember("Direction", string(harqSummaryT.Properties.VariableNames)))
    harqSummaryT = table();
end
if ~(istable(harqTimelineT) && ismember("Direction", string(harqTimelineT.Properties.VariableNames)))
    harqTimelineT = table();
end
if isempty(harqSummaryT) || isempty(harqTimelineT)
    [harqSummaryT, harqTimelineT] = localBuildHARQObservationTables(dlT, ulT);
end
trialCombinedT = localCombineDirectionalTrials(dlT, ulT);
antennaConfigT = localBuildAntennaConfigResolvedTable(mobilityArtifacts, slotTrace);
antennaRuntimeT = localBuildAntennaRuntimeEvidenceTable(trialCombinedT);
arrayConsistencyT = localBuildChannelArrayConsistencyTable(trialCombinedT);
todToaT = localBuildTodToaTraceTable(trialCombinedT);
timingPositioningT = localBuildTimingPositioningRuntimeEvidenceTable(trialCombinedT);

sixgr.util.csvWriteTable(artifacts.ChannelEstimationStatsPath, channelT);
sixgr.util.csvWriteTable(artifacts.RankEstimationStatsPath, rankT);
sixgr.util.csvWriteTable(artifacts.BeamSelectionStatsPath, beamT);
sixgr.util.csvWriteTable(artifacts.CSIFeedbackStatsPath, csiT);
sixgr.util.csvWriteTable(artifacts.CSIRSStatsPath, csirsT);
sixgr.util.csvWriteTable(artifacts.UserPerformancePath, userPerfT);
sixgr.util.csvWriteTable(artifacts.CoverageLayerPath, coverageT);
sixgr.util.csvWriteTable(artifacts.ErrorRateSummaryPath, errorRateT);
sixgr.util.csvWriteTable(artifacts.LiveHARQSummaryPath, harqSummaryT);
sixgr.util.csvWriteTable(artifacts.LiveHARQTimelinePath, harqTimelineT);
sixgr.util.csvWriteTable(artifacts.AntennaConfigResolvedPath, antennaConfigT);
sixgr.util.csvWriteTable(artifacts.AntennaRuntimeEvidencePath, antennaRuntimeT);
sixgr.util.csvWriteTable(artifacts.ChannelArrayConsistencyPath, arrayConsistencyT);
sixgr.util.csvWriteTable(artifacts.TodToaTracePath, todToaT);
sixgr.util.csvWriteTable(artifacts.TimingPositioningEvidencePath, timingPositioningT);

artifacts.ChannelEstimationStats = channelT;
artifacts.RankEstimationStats = rankT;
artifacts.BeamSelectionStats = beamT;
artifacts.CSIFeedbackStats = csiT;
artifacts.CSIRSStats = csirsT;
artifacts.UserPerformance = userPerfT;
artifacts.CoverageLayer = coverageT;
artifacts.ErrorRateSummary = errorRateT;
artifacts.AntennaConfigResolved = antennaConfigT;
artifacts.AntennaRuntimeEvidence = antennaRuntimeT;
artifacts.ChannelArrayConsistency = arrayConsistencyT;
artifacts.TodToaTrace = todToaT;
artifacts.TimingPositioningEvidence = timingPositioningT;
artifacts.HARQ = struct( ...
    "SummaryCSV", artifacts.LiveHARQSummaryPath, ...
    "TimelineCSV", artifacts.LiveHARQTimelinePath, ...
    "SummaryTable", harqSummaryT, ...
    "TimelineTable", harqTimelineT);
end

function T = localBuildChannelStatsTable(dlT, ulT, srsT, trsT)
parts = { ...
    localAggregateByDirectionAndSNR(dlT, "DL", ["ReceiverHestSINR_dB","DecoderTruthProxySINR_dB","SystemLevelSINR_dB","LargeScaleSINR_dB","NMSE_dB","ChannelGain_dB","ConditionNumber_dB","TimingOffset_samples","EstimatedDopplerHz","PhaseTrackingError_deg"], "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", ["ReceiverHestSINR_dB","DecoderTruthProxySINR_dB","SystemLevelSINR_dB","LargeScaleSINR_dB","NMSE_dB","ChannelGain_dB","ConditionNumber_dB","TimingOffset_samples","EstimatedDopplerHz","PhaseTrackingError_deg"], "ul_pusch_trials"), ...
    localAggregateByDirectionAndSNR(srsT, "SRS", ["NMSE_dB","EstimatedDopplerHz","DopplerError_Hz","QCLAccuracy","TrackingFailureProbability"], "srs_trials"), ...
    localAggregateByDirectionAndSNR(trsT, "TRS", ["NMSE_dB","EstimatedDopplerHz","DopplerError_Hz","PhaseTrackingError_deg","QCLAccuracy"], "trs_trials")};
T = localVertcat(parts);
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildRankStatsTable(dlT, ulT)
parts = { ...
    localAggregateByDirectionAndSNR(dlT, "DL", ["RankIndicator","RankEstimate","Layers"], "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", ["RankIndicator","RankEstimate","Layers"], "ul_pusch_trials")};
T = localVertcat(parts);
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildBeamStatsTable(dlT, ulT)
parts = { ...
    localAggregateByDirectionAndSNR(dlT, "DL", ["SelectedBeamIndex","BestBeamIndex","BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB","PMI","CRI"], "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", ["SelectedBeamIndex","BestBeamIndex","BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB","PMI","CRI"], "ul_pusch_trials")};
T = localVertcat(parts);
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildCSIStatsTable(dlT, ulT)
parts = { ...
    localAggregateByDirectionAndSNR(dlT, "DL", ["WidebandCQI","CQIDerivedMCS","CQIDerivedTargetCodeRate","CSIPayloadBitLength","PMI","CRI","RankIndicator"], "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", ["WidebandCQI","CQIDerivedMCS","CQIDerivedTargetCodeRate","CSIPayloadBitLength","PMI","CRI","RankIndicator"], "ul_pusch_trials")};
T = localVertcat(parts);
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildCSIRSStatsTable(dlT, srsT, trsT)
rows = repmat(struct( ...
    "Direction", "", ...
    "TraceSource", "", ...
    "SNR_dB", NaN, ...
    "MeanNMSE_dB", NaN, ...
    "MeanWidebandCQI", NaN, ...
    "MeanPMI", NaN, ...
    "MeanCRI", NaN, ...
    "MeanCSIPayloadBitLength", NaN, ...
    "Notes", ""), 0, 1);

if istable(dlT) && ~isempty(dlT)
    snrList = unique(double(dlT.SNR_dB), "stable");
    for i = 1:numel(snrList)
        mask = abs(double(dlT.SNR_dB) - snrList(i)) < 1e-9;
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Direction", "DL", ...
            "TraceSource", "shared_dmrs_csirs_path", ...
            "SNR_dB", double(snrList(i)), ...
            "MeanNMSE_dB", localMean(dlT, "NMSE_dB", mask), ...
            "MeanWidebandCQI", localMean(dlT, "WidebandCQI", mask), ...
            "MeanPMI", localMean(dlT, "PMI", mask), ...
            "MeanCRI", localMean(dlT, "CRI", mask), ...
            "MeanCSIPayloadBitLength", localMean(dlT, "CSIPayloadBitLength", mask), ...
            "Notes", "Derived from the actual runtime CSI feedback path. Dedicated CSI-RS runtime events are exported separately when waveform CSI-RS is mapped and observed; this aggregate still uses the shared CSI estimator.");
    end
end
if istable(trsT) && ~isempty(trsT)
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Direction", "DL", ...
        "TraceSource", "tracking_rs_path", ...
        "SNR_dB", localMean(trsT, "SNR_dB"), ...
        "MeanNMSE_dB", localMean(trsT, "NMSE_dB"), ...
        "MeanWidebandCQI", NaN, ...
        "MeanPMI", NaN, ...
        "MeanCRI", NaN, ...
        "MeanCSIPayloadBitLength", NaN, ...
        "Notes", "Tracking-RS summary from actual TRS trials.");
end
if istable(srsT) && ~isempty(srsT)
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Direction", "UL", ...
        "TraceSource", "srs_feedback_path", ...
        "SNR_dB", localMean(srsT, "SNR_dB"), ...
        "MeanNMSE_dB", localMean(srsT, "NMSE_dB"), ...
        "MeanWidebandCQI", NaN, ...
        "MeanPMI", NaN, ...
        "MeanCRI", NaN, ...
        "MeanCSIPayloadBitLength", NaN, ...
        "Notes", "UL sounding summary from actual SRS trials.");
end
if isempty(rows)
    T = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'Direction','TraceSource','SNR_dB','MeanNMSE_dB','MeanWidebandCQI','MeanPMI','MeanCRI','MeanCSIPayloadBitLength','Notes'});
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildUserPerformanceTable(dlSummary, ulSummary, dlRaw, ulRaw)
if nargin < 3
    dlRaw = table();
end
if nargin < 4
    ulRaw = table();
end
if ~(istable(dlSummary) && ~isempty(dlSummary))
    dlSummary = localBuildUserPerformanceSummaryFromRaw(dlRaw, "DL");
end
if ~(istable(ulSummary) && ~isempty(ulSummary))
    ulSummary = localBuildUserPerformanceSummaryFromRaw(ulRaw, "UL");
end
rows = repmat(struct( ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "DL_Throughput_Mbps", NaN, ...
    "UL_Throughput_Mbps", NaN, ...
    "DL_ObservedRowCount", NaN, ...
    "UL_ObservedRowCount", NaN, ...
    "DL_BLER", NaN, ...
    "UL_BLER", NaN, ...
    "DL_FER", NaN, ...
    "UL_FER", NaN, ...
    "DL_MeanReceiverHestSINR_dB", NaN, ...
    "UL_MeanReceiverHestSINR_dB", NaN, ...
    "DL_MeanMeasuredSINR_dB", NaN, ...
    "UL_MeanMeasuredSINR_dB", NaN, ...
    "DL_ZeroThroughputReason", "", ...
    "UL_ZeroThroughputReason", "", ...
    "UserThroughput_Mbps", NaN, ...
    "HARQFailureRate", NaN), 0, 1);
ueList = unique([localColumnVector(dlSummary, "UEIndex"); localColumnVector(ulSummary, "UEIndex")], "stable");
for i = 1:numel(ueList)
    ueIdx = ueList(i);
    row = localEmptyUserPerformanceRow();
    row.UEIndex = ueIdx;
    row.RNTI = localLookup(dlSummary, ueIdx, "RNTI");
    if ~isfinite(row.RNTI)
        row.RNTI = localLookup(ulSummary, ueIdx, "RNTI");
    end
    row.DL_Throughput_Mbps = localLookup(dlSummary, ueIdx, "Throughput_Mbps");
    row.UL_Throughput_Mbps = localLookup(ulSummary, ueIdx, "Throughput_Mbps");
    row.DL_ObservedRowCount = localLookup(dlSummary, ueIdx, "ObservedRowCount");
    row.UL_ObservedRowCount = localLookup(ulSummary, ueIdx, "ObservedRowCount");
    row.DL_BLER = localLookup(dlSummary, ueIdx, "BLER");
    row.UL_BLER = localLookup(ulSummary, ueIdx, "BLER");
    row.DL_FER = localLookup(dlSummary, ueIdx, "FER");
    row.UL_FER = localLookup(ulSummary, ueIdx, "FER");
    row.DL_MeanReceiverHestSINR_dB = localLookup(dlSummary, ueIdx, "MeanReceiverHestSINR_dB");
    row.UL_MeanReceiverHestSINR_dB = localLookup(ulSummary, ueIdx, "MeanReceiverHestSINR_dB");
    row.DL_MeanMeasuredSINR_dB = localLookup(dlSummary, ueIdx, "MeanMeasuredSINR_dB");
    row.UL_MeanMeasuredSINR_dB = localLookup(ulSummary, ueIdx, "MeanMeasuredSINR_dB");
    row.DL_ZeroThroughputReason = localLookupStringOrBlank(dlSummary, ueIdx, "ZeroThroughputReason");
    row.UL_ZeroThroughputReason = localLookupStringOrBlank(ulSummary, ueIdx, "ZeroThroughputReason");
    row.UserThroughput_Mbps = sum([row.DL_Throughput_Mbps row.UL_Throughput_Mbps], "omitnan");
    row.HARQFailureRate = mean([row.DL_BLER row.UL_BLER], "omitnan");
    rows(end+1,1) = row; %#ok<AGROW>
end
if isempty(rows)
    T = struct2table(repmat(localEmptyUserPerformanceRow(), 0, 1));
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildUserPerformanceSummaryFromRaw(sourceT, direction)
direction = upper(string(direction));
if ~(istable(sourceT) && ~isempty(sourceT) && ismember("UEIndex", string(sourceT.Properties.VariableNames)))
    T = table();
    return;
end
sourceT = localEnsureUserSummarySourceVars(sourceT);
ueList = unique(double(sourceT.UEIndex), "stable");
rows = repmat(struct( ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "Direction", "", ...
    "ConfiguredLayers", NaN, ...
    "ConfiguredTxAntennas", NaN, ...
    "ConfiguredRxAntennas", NaN, ...
    "BeamformingApplied", false, ...
    "BeamSelectionStrategy", "", ...
    "BeamIndexSet", "", ...
    "ExecutionModel", "", ...
    "Throughput_Mbps", NaN, ...
    "ObservedRowCount", NaN, ...
    "BLER", NaN, ...
    "FER", NaN, ...
    "BER", NaN, ...
    "PassRate", NaN, ...
    "MeanReceiverHestSINR_dB", NaN, ...
    "MeanMeasuredSINR_dB", NaN, ...
    "MeanChannelGain_dB", NaN, ...
    "ZeroThroughputReason", "", ...
    "SummaryRowValid", false, ...
    "RuntimeDataPresent", false, ...
    "UserHadAnySuccessfulTx", false, ...
    "UserHadAnySuccessfulRx", false, ...
    "PartialSuccess", false, ...
    "AllObservedRowsSuccessful", false, ...
    "SummaryStatus", "", ...
    "Ok", false, ...
    "OkDefinition", "compatibility_alias_of_summary_row_valid"), numel(ueList), 1);
for i = 1:numel(ueList)
    mask = abs(double(sourceT.UEIndex) - ueList(i)) < 1e-9;
    slice = sourceT(mask, :);
    sem = sixgr.truth.deriveUserSummarySemantics(slice);
    rows(i) = struct( ...
        "UEIndex", double(ueList(i)), ...
        "RNTI", double(localLastValue(slice, "RNTI")), ...
        "Direction", char(direction), ...
        "ConfiguredLayers", double(localLastValue(slice, "ConfiguredLayers")), ...
        "ConfiguredTxAntennas", double(localLastValue(slice, "ConfiguredTxAntennas")), ...
        "ConfiguredRxAntennas", double(localLastValue(slice, "ConfiguredRxAntennas")), ...
        "BeamformingApplied", logical(localLastValue(slice, "BeamformingApplied")), ...
        "BeamSelectionStrategy", char(string(localLastValue(slice, "BeamSelectionStrategy"))), ...
        "BeamIndexSet", char(string(localLastValue(slice, "BeamIndexSet"))), ...
        "ExecutionModel", char(string(localLastValue(slice, "ExecutionModel"))), ...
        "Throughput_Mbps", mean(double(slice.Goodput_Mbps), "omitnan"), ...
        "ObservedRowCount", double(height(slice)), ...
        "BLER", mean(1 - double(slice.CRCPass), "omitnan"), ...
        "FER", localFrameErrorRate(slice), ...
        "BER", localRatio(sum(double(slice.BitErrors), "omitnan"), sum(double(slice.BitsCompared), "omitnan")), ...
        "PassRate", double(sem.PassRate), ...
        "MeanReceiverHestSINR_dB", mean(double(slice.ReceiverHestSINR_dB), "omitnan"), ...
        "MeanMeasuredSINR_dB", mean(double(slice.MeasuredSINR_dB), "omitnan"), ...
        "MeanChannelGain_dB", mean(double(slice.ChannelGain_dB), "omitnan"), ...
        "ZeroThroughputReason", char(localResolveZeroThroughputReason(slice)), ...
        "SummaryRowValid", logical(sem.SummaryRowValid), ...
        "RuntimeDataPresent", logical(sem.RuntimeDataPresent), ...
        "UserHadAnySuccessfulTx", logical(sem.UserHadAnySuccessfulTx), ...
        "UserHadAnySuccessfulRx", logical(sem.UserHadAnySuccessfulRx), ...
        "PartialSuccess", logical(sem.PartialSuccess), ...
        "AllObservedRowsSuccessful", logical(sem.AllObservedRowsSuccessful), ...
        "SummaryStatus", char(string(sem.SummaryStatus)), ...
        "Ok", logical(sem.Ok), ...
        "OkDefinition", char(string(sem.OkDefinition)));
end
T = struct2table(rows, "AsArray", true);
end

function T = localEnsureUserSummarySourceVars(T)
defaults = struct( ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "ConfiguredLayers", NaN, ...
    "ConfiguredTxAntennas", NaN, ...
    "ConfiguredRxAntennas", NaN, ...
    "BeamformingApplied", false, ...
    "BeamSelectionStrategy", "", ...
    "BeamIndexSet", "", ...
    "ExecutionModel", "", ...
    "Goodput_Mbps", NaN, ...
    "CRCPass", NaN, ...
    "Crash", NaN, ...
    "BitErrors", NaN, ...
    "BitsCompared", NaN, ...
    "Status", "", ...
    "ReceiverHestSINR_dB", NaN, ...
    "MeasuredSINR_dB", NaN, ...
    "ChannelGain_dB", NaN);
    names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if ismember(string(name), string(T.Properties.VariableNames))
        continue;
    end
    value = defaults.(name);
    if islogical(value)
        T.(name) = false(height(T), 1);
    elseif isstring(value) || ischar(value)
        T.(name) = strings(height(T), 1);
    else
        T.(name) = nan(height(T), 1);
    end
end
end

function value = localLastValue(T, name)
value = NaN;
if ~(istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
col = T.(name);
if isstring(col)
    value = string(col(end));
elseif islogical(col)
    value = logical(col(end));
else
    value = double(col(end));
end
end

function ratio = localRatio(num, den)
if ~(isfinite(num) && isfinite(den) && den > 0)
    ratio = NaN;
    else
        ratio = double(num) / double(den);
end
end

function T = localBuildErrorRateSummaryTable(dlT, ulT)
rows = repmat(struct( ...
    "Scope", "", ...
    "ScopeDefinition", "", ...
    "Direction", "", ...
    "UEID", NaN, ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "ObservedFrames", NaN, ...
    "ErroredFrames", NaN, ...
    "FER", NaN, ...
    "BLER", NaN, ...
    "BER", NaN, ...
    "FERDefinition", "", ...
    "TraceSource", "", ...
    "Notes", ""), 0, 1);
for pair = [struct("Direction","DL","Table",dlT); struct("Direction","UL","Table",ulT)].'
    sourceT = pair.Table;
    if ~(istable(sourceT) && ~isempty(sourceT))
        continue;
    end
    sourceT = localEnsureUserSummarySourceVars(sourceT);
    rows = [rows; localBuildErrorRateRowsForScope(sourceT, string(pair.Direction), NaN, "run")]; %#ok<AGROW>
    ueList = unique(double(sourceT.UEIndex), "stable");
    ueList = ueList(isfinite(ueList));
    for ui = 1:numel(ueList)
        rows = [rows; localBuildErrorRateRowsForScope(sourceT(abs(double(sourceT.UEIndex) - ueList(ui)) < 1e-9, :), string(pair.Direction), ueList(ui), "ue")]; %#ok<AGROW>
    end
end
if isempty(rows)
    T = struct2table(repmat(struct( ...
        "Scope", "", "ScopeDefinition", "", "Direction", "", "UEID", NaN, "UEIndex", NaN, "RNTI", NaN, ...
        "ObservedFrames", NaN, "ErroredFrames", NaN, "FER", NaN, "BLER", NaN, "BER", NaN, ...
        "FERDefinition", "", ...
        "TraceSource", "", "Notes", ""), 0, 1));
else
    T = struct2table(rows, "AsArray", true);
end
end

function rows = localBuildErrorRateRowsForScope(sourceT, direction, ueIdx, scopeName)
rows = repmat(struct( ...
    "Scope", "", ...
    "ScopeDefinition", "", ...
    "Direction", "", ...
    "UEID", NaN, ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "ObservedFrames", NaN, ...
    "ErroredFrames", NaN, ...
    "FER", NaN, ...
    "BLER", NaN, ...
    "BER", NaN, ...
    "FERDefinition", "", ...
    "TraceSource", "", ...
    "Notes", ""), 0, 1);
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
frames = [];
if ismember("Frame", string(sourceT.Properties.VariableNames))
    frames = unique(double(sourceT.Frame), "stable");
    frames = frames(isfinite(frames));
end
frameFailCount = NaN;
if ~isempty(frames)
    frameFailMask = false(numel(frames), 1);
    for fi = 1:numel(frames)
        frameSlice = sourceT(abs(double(sourceT.Frame) - frames(fi)) < 1e-9, :);
        crcVals = double(frameSlice.CRCPass);
        statusVals = upper(strtrim(string(frameSlice.Status)));
        crashVals = double(frameSlice.Crash);
        frameFailMask(fi) = any(isfinite(crashVals) & crashVals ~= 0) || ...
            any(statusVals == "FAIL" | statusVals == "CRASH") || any(crcVals == 0);
    end
    frameFailCount = sum(frameFailMask);
end
[ueIdentity, rntiIdentity, scopeDefinition, scopeNotes] = localResolveFERScopeIdentity(sourceT, ueIdx, scopeName);
row = struct( ...
    "Scope", char(string(scopeName)), ...
    "ScopeDefinition", char(scopeDefinition), ...
    "Direction", char(direction), ...
    "UEID", double(ueIdentity), ...
    "UEIndex", double(ueIdentity), ...
    "RNTI", double(rntiIdentity), ...
    "ObservedFrames", double(numel(frames)), ...
    "ErroredFrames", double(frameFailCount), ...
    "FER", localRatio(double(frameFailCount), double(numel(frames))), ...
    "BLER", mean(1 - double(sourceT.CRCPass), "omitnan"), ...
    "BER", localRatio(sum(double(sourceT.BitErrors), "omitnan"), sum(double(sourceT.BitsCompared), "omitnan")), ...
    "FERDefinition", "frame_fails_if_any_executed_transport_block_fails_crc_or_crashes", ...
    "TraceSource", char(string(lower(direction) + "_frame_grouped_raw_link_trials")), ...
    "Notes", char(scopeNotes));
rows = row;
end

function [ueIdentity, rntiIdentity, scopeDefinition, notes] = localResolveFERScopeIdentity(sourceT, ueIdx, scopeName)
scopeName = lower(strtrim(char(string(scopeName))));
baseNotes = "FER is derived from actual raw trial outcomes by marking a frame as failed when any executed transport block in that direction/scope fails CRC or crashes.";
switch scopeName
    case "run"
        ueIdentity = NaN;
        rntiIdentity = NaN;
        scopeDefinition = "all_ues_in_direction_aggregated_per_frame_no_ue_identity";
        notes = baseNotes + " Run scope aggregates all executed UEs in the direction and intentionally leaves UE identity blank.";
    otherwise
        ueIdentity = double(ueIdx);
        if ~(isfinite(ueIdentity) && isscalar(ueIdentity))
            ueIdentity = double(localLastValue(sourceT, "UEIndex"));
        end
        rntiIdentity = double(localLastValue(sourceT, "RNTI"));
        scopeDefinition = "single_ue_in_direction_aggregated_per_frame";
        notes = baseNotes + " UE scope aggregates only the selected UE in the direction and may carry UE identity.";
end
end

function fer = localFrameErrorRate(sourceT)
fer = NaN;
if ~(istable(sourceT) && ~isempty(sourceT) && ismember("Frame", string(sourceT.Properties.VariableNames)))
    return;
end
frames = unique(double(sourceT.Frame), "stable");
frames = frames(isfinite(frames));
if isempty(frames)
    return;
end
frameFailCount = 0;
for fi = 1:numel(frames)
    frameSlice = sourceT(abs(double(sourceT.Frame) - frames(fi)) < 1e-9, :);
    crcVals = double(frameSlice.CRCPass);
    statusVals = upper(strtrim(string(frameSlice.Status)));
    crashVals = double(frameSlice.Crash);
    if any(isfinite(crashVals) & crashVals ~= 0) || any(statusVals == "FAIL" | statusVals == "CRASH") || any(crcVals == 0)
        frameFailCount = frameFailCount + 1;
    end
end
fer = localRatio(double(frameFailCount), double(numel(frames)));
end

function T = localBuildCoverageLayerTable(mobilityArtifacts, userPerfT)
coverageT = sixgr.util.structGet(mobilityArtifacts, "CoverageLayerTable", table());
if ~(istable(coverageT) && ~isempty(coverageT))
    coverageT = sixgr.util.structGet(mobilityArtifacts, "CoverageSnapshotTable", table());
end
if ~(istable(coverageT) && ~isempty(coverageT))
    coverageT = struct2table(repmat(struct( ...
        "UEID", NaN, "Slot", NaN, "Time_s", NaN, "Lat", NaN, "Lon", NaN, ...
        "ServingCell", NaN, "ServingSite", NaN, "ServingSector", NaN, ...
        "ConfiguredSNR_dB", NaN, "ConfiguredSNRSource", "", "ServingRSRP_dBm", NaN, "RSRP_dBm", NaN, ...
        "EstimatedWidebandSINR_dB", NaN, "SystemLevelWidebandSINR_dB", NaN, ...
        "ReceiverHestWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, ...
        "MeasuredWidebandSINR_dB", NaN, "LargeScaleWidebandSINR_dB", NaN, ...
        "SystemLevelSINR_dB", NaN, "SystemLevelSINRSource", "", "SystemLevelSINRValueRole", "", "SystemLevelSINRValueStatus", "", ...
        "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
        "ReceiverHestSINRValueStatus", "", "DecoderTruthProxySINRValueStatus", "", ...
        "MeasuredTrialSINR_dB", NaN, "MeasuredTrialSINRSource", "", "MeasuredTrialSINRValueStatus", "", ...
        "LargeScaleSINR_dB", NaN, "CSI_RSRP_dB", NaN, "AppliedLargeScaleGain_dB", NaN, ...
        "RSRPSource", "", "WidebandSINRSource", "", "WidebandSINRValueRole", "", "WidebandSINRValueStatus", "", ...
        "InterferenceMode", "", "ServingRSRPSource", "", "CSI_RSRPSource", "", ...
        "WidebandCQI", NaN, "CQIDerivedModulation", "", "CQIDerivedMCS", NaN, "CQIDerivedTargetCodeRate", NaN, "Pathloss_dB", NaN), 0, 1));
end
if ~ismember("ConfiguredSNR_dB", string(coverageT.Properties.VariableNames))
    if ismember("SNR_dB", string(coverageT.Properties.VariableNames))
        coverageT.ConfiguredSNR_dB = double(coverageT.SNR_dB);
    else
        coverageT.ConfiguredSNR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("ConfiguredSNRSource", string(coverageT.Properties.VariableNames))
    coverageT.ConfiguredSNRSource = repmat("configured_runtime_operating_point_reference", height(coverageT), 1);
end
if ~ismember("ServingRSRP_dBm", string(coverageT.Properties.VariableNames))
    if ismember("RSRP_dBm", string(coverageT.Properties.VariableNames))
        coverageT.ServingRSRP_dBm = double(coverageT.RSRP_dBm);
    else
        coverageT.ServingRSRP_dBm = nan(height(coverageT), 1);
    end
end
if ~ismember("SystemLevelWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    if ismember("SystemLevelSINR_dB", string(coverageT.Properties.VariableNames))
        coverageT.SystemLevelWidebandSINR_dB = double(coverageT.SystemLevelSINR_dB);
    else
        coverageT.SystemLevelWidebandSINR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("SystemLevelSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.SystemLevelSINR_dB = double(coverageT.SystemLevelWidebandSINR_dB);
end
if ~ismember("SystemLevelSINRSource", string(coverageT.Properties.VariableNames))
    coverageT.SystemLevelSINRSource = strings(height(coverageT), 1);
end
if ~ismember("SystemLevelSINRValueRole", string(coverageT.Properties.VariableNames))
    coverageT.SystemLevelSINRValueRole = strings(height(coverageT), 1);
end
if ~ismember("SystemLevelSINRValueStatus", string(coverageT.Properties.VariableNames))
    coverageT.SystemLevelSINRValueStatus = strings(height(coverageT), 1);
end
if ~ismember("ReceiverHestWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    if ismember("ReceiverHestSINR_dB", string(coverageT.Properties.VariableNames))
        coverageT.ReceiverHestWidebandSINR_dB = double(coverageT.ReceiverHestSINR_dB);
    else
        coverageT.ReceiverHestWidebandSINR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("DecoderTruthProxyWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    if ismember("DecoderTruthProxySINR_dB", string(coverageT.Properties.VariableNames))
        coverageT.DecoderTruthProxyWidebandSINR_dB = double(coverageT.DecoderTruthProxySINR_dB);
    else
        coverageT.DecoderTruthProxyWidebandSINR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("MeasuredWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    if ismember("MeasuredTrialSINR_dB", string(coverageT.Properties.VariableNames))
        coverageT.MeasuredWidebandSINR_dB = double(coverageT.MeasuredTrialSINR_dB);
    else
        coverageT.MeasuredWidebandSINR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("ReceiverHestSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.ReceiverHestSINR_dB = double(coverageT.ReceiverHestWidebandSINR_dB);
end
if ~ismember("ReceiverHestSINRSource", string(coverageT.Properties.VariableNames))
    coverageT.ReceiverHestSINRSource = strings(height(coverageT), 1);
end
if ~ismember("ReceiverHestSINRValueStatus", string(coverageT.Properties.VariableNames))
    coverageT.ReceiverHestSINRValueStatus = strings(height(coverageT), 1);
end
if ~ismember("DecoderTruthProxySINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.DecoderTruthProxySINR_dB = double(coverageT.DecoderTruthProxyWidebandSINR_dB);
end
if ~ismember("DecoderTruthProxySINRSource", string(coverageT.Properties.VariableNames))
    coverageT.DecoderTruthProxySINRSource = strings(height(coverageT), 1);
end
if ~ismember("DecoderTruthProxySINRValueStatus", string(coverageT.Properties.VariableNames))
    coverageT.DecoderTruthProxySINRValueStatus = strings(height(coverageT), 1);
end
if ~ismember("MeasuredTrialSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.MeasuredTrialSINR_dB = double(coverageT.MeasuredWidebandSINR_dB);
end
if ~ismember("MeasuredTrialSINRSource", string(coverageT.Properties.VariableNames))
    coverageT.MeasuredTrialSINRSource = strings(height(coverageT), 1);
end
if ~ismember("MeasuredTrialSINRValueStatus", string(coverageT.Properties.VariableNames))
    coverageT.MeasuredTrialSINRValueStatus = strings(height(coverageT), 1);
end
if ~ismember("LargeScaleWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    if ismember("LargeScaleSINR_dB", string(coverageT.Properties.VariableNames))
        coverageT.LargeScaleWidebandSINR_dB = double(coverageT.LargeScaleSINR_dB);
    else
        coverageT.LargeScaleWidebandSINR_dB = nan(height(coverageT), 1);
    end
end
if ~ismember("LargeScaleSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.LargeScaleSINR_dB = double(coverageT.LargeScaleWidebandSINR_dB);
end
if ~ismember("CSI_RSRP_dB", string(coverageT.Properties.VariableNames))
    coverageT.CSI_RSRP_dB = nan(height(coverageT), 1);
end
if ~ismember("AppliedLargeScaleGain_dB", string(coverageT.Properties.VariableNames))
    coverageT.AppliedLargeScaleGain_dB = nan(height(coverageT), 1);
end
if ~ismember("RSRPSource", string(coverageT.Properties.VariableNames))
    coverageT.RSRPSource = repmat("large_scale_serving_reference_signal", height(coverageT), 1);
end
if ~ismember("WidebandSINRSource", string(coverageT.Properties.VariableNames))
    coverageT.WidebandSINRSource = strings(height(coverageT), 1);
end
if ~ismember("WidebandSINRValueRole", string(coverageT.Properties.VariableNames))
    coverageT.WidebandSINRValueRole = strings(height(coverageT), 1);
end
if ~ismember("WidebandSINRValueStatus", string(coverageT.Properties.VariableNames))
    coverageT.WidebandSINRValueStatus = strings(height(coverageT), 1);
end
widebandRole = strtrim(string(coverageT.WidebandSINRValueRole));
widebandRole(strlength(widebandRole) == 0 & isfinite(double(coverageT.ReceiverHestWidebandSINR_dB))) = "estimated";
widebandRole(strlength(widebandRole) == 0 & ~isfinite(double(coverageT.ReceiverHestWidebandSINR_dB)) & isfinite(double(coverageT.SystemLevelWidebandSINR_dB))) = "runtime_state_derived";
widebandRole(strlength(widebandRole) == 0 & ~isfinite(double(coverageT.ReceiverHestWidebandSINR_dB)) & ~isfinite(double(coverageT.SystemLevelWidebandSINR_dB)) & isfinite(double(coverageT.LargeScaleWidebandSINR_dB))) = "derived_preview";
coverageT.WidebandSINRValueRole = widebandRole;
if height(coverageT) == 0
    widebandSource = strings(0, 1);
    receiverSource = strings(0, 1);
    systemSource = strings(0, 1);
    largeScaleSource = strings(0, 1);
else
    widebandSource = strtrim(string(coverageT.WidebandSINRSource));
    receiverSource = strtrim(string(coverageT.ReceiverHestSINRSource));
    systemSource = strtrim(string(coverageT.SystemLevelSINRSource));
    largeScaleSource = strings(height(coverageT), 1);
    if ismember("LargeScaleSINRSource", string(coverageT.Properties.VariableNames))
        largeScaleSource = strtrim(string(coverageT.LargeScaleSINRSource));
    end
end
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & isfinite(double(coverageT.ReceiverHestWidebandSINR_dB)) & strlength(receiverSource) > 0;
widebandSource(fillMask) = receiverSource(fillMask);
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & isfinite(double(coverageT.SystemLevelWidebandSINR_dB)) & strlength(systemSource) > 0;
widebandSource(fillMask) = systemSource(fillMask);
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & isfinite(double(coverageT.LargeScaleWidebandSINR_dB)) & strlength(largeScaleSource) > 0;
widebandSource(fillMask) = largeScaleSource(fillMask);
coverageT.WidebandSINRSource = widebandSource;
widebandStatus = strtrim(string(coverageT.WidebandSINRValueStatus));
widebandStatus(strlength(widebandStatus) == 0 & isfinite(double(coverageT.ReceiverHestWidebandSINR_dB))) = "available_receiver_hest";
widebandStatus(strlength(widebandStatus) == 0 & ~isfinite(double(coverageT.ReceiverHestWidebandSINR_dB)) & isfinite(double(coverageT.SystemLevelWidebandSINR_dB))) = "available_system_level_estimate";
widebandStatus(strlength(widebandStatus) == 0 & ~isfinite(double(coverageT.ReceiverHestWidebandSINR_dB)) & ~isfinite(double(coverageT.SystemLevelWidebandSINR_dB)) & isfinite(double(coverageT.LargeScaleWidebandSINR_dB))) = "available_large_scale_preview";
widebandStatus(strlength(widebandStatus) == 0) = "unavailable";
coverageT.WidebandSINRValueStatus = widebandStatus;
if ~ismember("InterferenceMode", string(coverageT.Properties.VariableNames))
    coverageT.InterferenceMode = repmat("unpublished_mode_label_missing", height(coverageT), 1);
end
if ~ismember("ServingRSRPSource", string(coverageT.Properties.VariableNames))
    coverageT.ServingRSRPSource = repmat("large_scale_serving_reference_signal", height(coverageT), 1);
end
if ~ismember("CSI_RSRPSource", string(coverageT.Properties.VariableNames))
    coverageT.CSI_RSRPSource = strings(height(coverageT), 1);
end
if ~(istable(userPerfT) && ~isempty(userPerfT))
    T = coverageT;
    if ~ismember("UserThroughput_Mbps", string(T.Properties.VariableNames))
        T.UserThroughput_Mbps = nan(height(T), 1);
    end
    if ~ismember("HARQFailureRate", string(T.Properties.VariableNames))
        T.HARQFailureRate = nan(height(T), 1);
    end
    if ~ismember("CellThroughput_Mbps", string(T.Properties.VariableNames))
        T.CellThroughput_Mbps = nan(height(T), 1);
    end
    return;
end

T = coverageT;
if ~ismember("UserThroughput_Mbps", string(T.Properties.VariableNames))
    T.UserThroughput_Mbps = nan(height(T), 1);
end
if ~ismember("HARQFailureRate", string(T.Properties.VariableNames))
    T.HARQFailureRate = nan(height(T), 1);
end
if ~ismember("CellThroughput_Mbps", string(T.Properties.VariableNames))
    T.CellThroughput_Mbps = nan(height(T), 1);
end
T.UserThroughput_Mbps = nan(height(T), 1);
T.HARQFailureRate = nan(height(T), 1);
T.CellThroughput_Mbps = nan(height(T), 1);
for i = 1:height(T)
    ueIdx = double(T.UEID(i));
    perfMask = abs(double(userPerfT.UEIndex) - ueIdx) < 1e-9;
    if any(perfMask)
        T.UserThroughput_Mbps(i) = double(userPerfT.UserThroughput_Mbps(find(perfMask, 1, "last")));
        T.HARQFailureRate(i) = double(userPerfT.HARQFailureRate(find(perfMask, 1, "last")));
    end
end
cellList = unique(double(T.ServingCell), "stable");
for i = 1:numel(cellList)
    mask = abs(double(T.ServingCell) - cellList(i)) < 1e-9;
    T.CellThroughput_Mbps(mask) = sum(double(T.UserThroughput_Mbps(mask)), "omitnan");
end
end

function [summaryT, timelineT] = localBuildHARQObservationTables(dlT, ulT)
timelineVars = {'Direction','TraceSource','SNR_dB','Frame','Slot','CRCPass','Status','Crash', ...
    'GoodBits','OfferedBits','Goodput_Mbps','ReceiverHestSINR_dB','DecoderTruthProxySINR_dB','WidebandCQI','CQIDerivedMCS', ...
    'CQIDerivedModulation','CQIDerivedTargetCodeRate','PMI','CRI','RankIndicator','Notes'};
timelineTypes = {'string','string','double','double','double','double','string','double', ...
    'double','double','double','double','double','double','double','string','double','double','double','double','string'};
timelineT = table('Size', [0, numel(timelineVars)], 'VariableTypes', timelineTypes, 'VariableNames', timelineVars);

summaryRows = repmat(struct( ...
    "Direction", "", ...
    "TraceSource", "", ...
    "SNR_dB", NaN, ...
    "FramesObserved", NaN, ...
    "CRCPassRate", NaN, ...
    "CRCFailRate", NaN, ...
    "CrashRate", NaN, ...
    "MeanGoodput_Mbps", NaN, ...
    "MeanReceiverHestSINR_dB", NaN, ...
    "MeanDecoderTruthProxySINR_dB", NaN, ...
    "MeanMeasuredSINR_dB", NaN, ...
    "MeanWidebandCQI", NaN, ...
    "MeanCQIDerivedMCS", NaN, ...
    "Notes", ""), 0, 1);

pairList = [ ...
    struct("Direction", "DL", "Table", dlT); ...
    struct("Direction", "UL", "Table", ulT)];
for pairIdx = 1:numel(pairList)
    pair = pairList(pairIdx);
    sourceT = pair.Table;
    if ~(istable(sourceT) && ~isempty(sourceT))
        continue;
    end
    sourceT = localEnsureHARQSourceVars(sourceT);
    snrList = unique(double(sourceT.SNR_dB), "stable");
    for s = 1:numel(snrList)
        mask = abs(double(sourceT.SNR_dB) - snrList(s)) < 1e-9;
        slice = sourceT(mask, :);
        if isempty(slice)
            continue;
        end
        summaryRows(end+1,1) = struct( ... %#ok<AGROW>
            "Direction", string(pair.Direction), ...
            "TraceSource", string(lower(pair.Direction) + "_raw_link_trials"), ...
            "SNR_dB", double(snrList(s)), ...
            "FramesObserved", double(height(slice)), ...
            "CRCPassRate", mean(double(slice.CRCPass), "omitnan"), ...
            "CRCFailRate", mean(1 - double(slice.CRCPass), "omitnan"), ...
            "CrashRate", mean(double(slice.Crash), "omitnan"), ...
            "MeanGoodput_Mbps", mean(double(slice.Goodput_Mbps), "omitnan"), ...
            "MeanReceiverHestSINR_dB", mean(double(slice.ReceiverHestSINR_dB), "omitnan"), ...
            "MeanDecoderTruthProxySINR_dB", mean(double(slice.DecoderTruthProxySINR_dB), "omitnan"), ...
            "MeanMeasuredSINR_dB", mean(double(slice.MeasuredSINR_dB), "omitnan"), ...
            "MeanWidebandCQI", mean(double(slice.WidebandCQI), "omitnan"), ...
            "MeanCQIDerivedMCS", mean(double(slice.CQIDerivedMCS), "omitnan"), ...
            "Notes", "Live HARQ observation summary derived directly from actual DL/UL raw trial outcomes. Full retransmission-process diagnostics may arrive later.");

        timelineSlice = table( ...
            repmat(string(pair.Direction), height(slice), 1), ...
            repmat(string(lower(pair.Direction) + "_raw_link_trials"), height(slice), 1), ...
            double(slice.SNR_dB), ...
            double(slice.Frame), ...
            double(slice.Slot), ...
            double(slice.CRCPass), ...
            string(slice.Status), ...
            double(slice.Crash), ...
            double(slice.GoodBits), ...
            double(slice.OfferedBits), ...
            double(slice.Goodput_Mbps), ...
            double(slice.ReceiverHestSINR_dB), ...
            double(slice.DecoderTruthProxySINR_dB), ...
            double(slice.WidebandCQI), ...
            double(slice.CQIDerivedMCS), ...
            string(slice.CQIDerivedModulation), ...
            double(slice.CQIDerivedTargetCodeRate), ...
            double(slice.PMI), ...
            double(slice.CRI), ...
            double(slice.RankIndicator), ...
            repmat("Actual frame-level DL/UL decode outcome for live HARQ visibility.", height(slice), 1), ...
            'VariableNames', timelineVars);
        timelineT = [timelineT; timelineSlice]; %#ok<AGROW>
    end
end

if isempty(summaryRows)
    summaryT = localEmptyHARQObservationSummaryTable();
else
    summaryT = struct2table(summaryRows);
end
end

function T = localEnsureHARQSourceVars(T)
if ismember("ConfiguredSNR_dB", string(T.Properties.VariableNames)) && ~ismember("SNR_dB", string(T.Properties.VariableNames))
    T.SNR_dB = double(T.ConfiguredSNR_dB);
end
if ismember("MeasuredTrialSINR_dB", string(T.Properties.VariableNames)) && ~ismember("MeasuredSINR_dB", string(T.Properties.VariableNames))
    T.MeasuredSINR_dB = double(T.MeasuredTrialSINR_dB);
end
if ~ismember("DecoderTruthProxySINR_dB", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINR_dB = nan(height(T), 1);
end
    required = struct( ...
    "CRCPass", NaN, ...
    "Status", "", ...
    "Crash", NaN, ...
    "GoodBits", NaN, ...
    "OfferedBits", NaN, ...
    "Goodput_Mbps", NaN, ...
    "ReceiverHestSINR_dB", NaN, ...
    "DecoderTruthProxySINR_dB", NaN, ...
    "MeasuredSINR_dB", NaN, ...
    "WidebandCQI", NaN, ...
    "CQIDerivedMCS", NaN, ...
    "CQIDerivedModulation", "", ...
    "CQIDerivedTargetCodeRate", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "RankIndicator", NaN);
vars = string(T.Properties.VariableNames);
names = fieldnames(required);
for i = 1:numel(names)
    name = names{i};
    if ismember(string(name), vars)
        continue;
    end
    value = required.(name);
    if isstring(value) || ischar(value)
        T.(name) = repmat(string(value), height(T), 1);
    else
        T.(name) = repmat(double(value), height(T), 1);
    end
end
end

function T = localEmptyHARQObservationSummaryTable()
T = struct2table(repmat(struct( ...
    "Direction", "", ...
    "TraceSource", "", ...
    "SNR_dB", NaN, ...
    "FramesObserved", NaN, ...
    "CRCPassRate", NaN, ...
    "CRCFailRate", NaN, ...
    "CrashRate", NaN, ...
    "MeanGoodput_Mbps", NaN, ...
    "MeanReceiverHestSINR_dB", NaN, ...
    "MeanDecoderTruthProxySINR_dB", NaN, ...
    "MeanMeasuredSINR_dB", NaN, ...
    "MeanWidebandCQI", NaN, ...
    "MeanCQIDerivedMCS", NaN, ...
    "Notes", ""), 0, 1));
end

function T = localAggregateByDirectionAndSNR(sourceT, direction, fields, traceSource)
fields = string(fields(:)).';
if ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptySummaryTable();
    return;
end
if ~ismember("SNR_dB", string(sourceT.Properties.VariableNames))
    sourceT.SNR_dB = nan(height(sourceT), 1);
end
snrList = unique(double(sourceT.SNR_dB), "stable");
rows = repmat(struct("Direction","", "TraceSource","", "SNR_dB", NaN, "Metric", "", "MeanValue", NaN, "P05Value", NaN, "P95Value", NaN, "SampleCount", NaN), 0, 1);
for s = 1:numel(snrList)
    mask = abs(double(sourceT.SNR_dB) - snrList(s)) < 1e-9;
    for f = 1:numel(fields)
        metric = fields(f);
        if ~ismember(metric, string(sourceT.Properties.VariableNames))
            continue;
        end
        vals = double(sourceT{mask, char(metric)});
        vals = vals(isfinite(vals));
        if isempty(vals)
            continue;
        end
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Direction", string(direction), ...
            "TraceSource", string(traceSource), ...
            "SNR_dB", double(snrList(s)), ...
            "Metric", string(metric), ...
            "MeanValue", mean(vals, "omitnan"), ...
            "P05Value", localPercentile(vals, 5), ...
            "P95Value", localPercentile(vals, 95), ...
            "SampleCount", double(numel(vals)));
    end
end
if isempty(rows)
    T = localEmptySummaryTable();
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localEmptySummaryTable()
T = table( ...
    strings(0,1), strings(0,1), zeros(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Direction','TraceSource','SNR_dB','Metric','MeanValue','P05Value','P95Value','SampleCount'});
end

function T = localCombineDirectionalTrials(dlT, ulT)
parts = {dlT, ulT};
parts = parts(cellfun(@(x) istable(x) && ~isempty(x), parts));
if isempty(parts)
    T = table();
elseif numel(parts) == 1
    T = parts{1};
else
    T = vertcat(parts{:});
end
end

function T = localBuildAntennaConfigResolvedTable(mobilityArtifacts, slotTrace)
T = sixgr.util.structGet(mobilityArtifacts, "AntennaConfigResolvedTable", table());
if ~(istable(T) && ~isempty(T))
    T = sixgr.util.structGet(slotTrace, "AntennaConfigResolvedTable", table());
end
T = localEnsureEvidenceTable(T, { ...
    'NodeType','NodeIndex','BaseStationID','UEIndex','ArrayType','ArrayClass','ElementClass', ...
    'NumRows','NumCols','NumPolarizations','NumElements','SpacingH_lambda','SpacingV_lambda', ...
    'Polarization','Azimuth_deg','Heading_deg','Tilt_deg','PositionX_m','PositionY_m','PositionZ_m', ...
    'NumPorts','AntennaConfigSource','RuntimeObjectSource','HasPhasedArrayObject'});
if isempty(T)
    T = localProjectEvidenceTable(table(), { ...
        'NodeType','NodeIndex','BaseStationID','UEIndex','ArrayType','ArrayClass','ElementClass', ...
        'NumRows','NumCols','NumPolarizations','NumElements','SpacingH_lambda','SpacingV_lambda', ...
        'Polarization','Azimuth_deg','Heading_deg','Tilt_deg','PositionX_m','PositionY_m','PositionZ_m', ...
        'NumPorts','AntennaConfigSource','RuntimeObjectSource','HasPhasedArrayObject'});
end
T.SameFlowEvidenceSource = repmat("CoupledTruthRuntime.initialize:AntennaArrayFactory.build", height(T), 1);
end

function T = localBuildAntennaRuntimeEvidenceTable(trialT)
fields = { ...
    'Direction','UEIndex','RNTI','BaseStationID','Frame','Slot','GrantContextId', ...
    'BSAntennaArrayClass','BSAntennaElementClass','BSAntennaArrayType','BSAntennaRows','BSAntennaCols','BSAntennaElements','BSAntennaSpacingH_lambda','BSAntennaSpacingV_lambda','BSAntennaPolarization','BSAntennaAzimuth_deg','BSAntennaNumPorts','BSAntennaHasPhasedArrayObject', ...
    'UEAntennaArrayClass','UEAntennaElementClass','UEAntennaArrayType','UEAntennaRows','UEAntennaCols','UEAntennaElements','UEAntennaSpacingH_lambda','UEAntennaSpacingV_lambda','UEAntennaPolarization','UEAntennaHeading_deg','UEAntennaNumPorts','UEAntennaHasPhasedArrayObject', ...
    'ConfiguredBeamSelectionStrategy','PMI','CRI','RankIndicator','BeamformingApplied','PrecodingActive','ExplicitBeamWeightsApplied', ...
    'AppliedBeamIndexSet','AppliedBeamValueRole','AppliedBeamValueStatus','AppliedBeamNAReason','AppliedPrecoderPMI','AppliedPrecoderValueRole','AppliedPrecoderValueStatus','AppliedPrecoderNAReason','ExplicitPrecoderReplayStatus','ExplicitPrecoderReplayBlocker','AppliedPrecoderPMIType','AppliedPrecoderCodebookMode', ...
    'AntennaConfigSource','RuntimeAntennaObjectSource','AntennaRuntimeObjectCreated','AntennaRuntimeObjectValueRole','AntennaRuntimeObjectValueStatus','AntennaRuntimeObjectNAReason','ChannelArrayModel','ChannelObjectSource','ChannelObjectClass','ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker','ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping','ChannelArrayValueRole','ChannelArrayValueStatus', ...
    'ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions','InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker','InterferenceChannelArrayValueRole','InterferenceChannelArrayValueStatus', ...
    'InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions','RuntimeTraceSource','AntennaEvidenceSource','SameFlowEvidenceSource'};
T = localProjectEvidenceTable(trialT, fields);
if isempty(T)
    return;
end
T.UEID = double(T.UEIndex);
T = movevars(T, 'UEID', 'After', 'Direction');
end

function T = localBuildChannelArrayConsistencyTable(trialT)
rows = repmat(struct( ...
    "Direction", "", ...
    "ObservedRows", NaN, ...
    "ChannelArrayModel", "", ...
    "ConfiguredTxAntennaPorts", NaN, ...
    "ConfiguredRxAntennaPorts", NaN, ...
        "ObservedNumTxPorts", NaN, ...
        "ObservedNumRxAntennas", NaN, ...
        "ObservedPrecodingNumPorts", NaN, ...
        "TxPortConsistencyRate", NaN, ...
        "RxPortConsistencyRate", NaN, ...
        "PrecodingPortConsistencyRate", NaN, ...
        "ChannelObjectSource", "", ...
        "ChannelObjectClass", "", ...
        "ChannelArrayHandlingStatus", "", ...
        "ChannelArrayHandlingBlocker", "", ...
        "ChannelGeometryCouplingLevel", "", ...
        "GeometryAdapterType", "", ...
        "GeometryAdapterSource", "", ...
        "GeometryAdapterLimitation", "", ...
        "GeometryAdapterPortMapping", "", ...
        "ChannelArrayValueStatus", "", ...
        "ChannelUsesCountOnlyAntennaModel", false, ...
        "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
        "InterferenceChannelObjectSource", "", ...
        "InterferenceChannelObjectClass", "", ...
        "InterferenceChannelArrayHandlingStatus", "", ...
        "InterferenceChannelArrayHandlingBlocker", "", ...
        "InterferenceChannelArrayValueStatus", "", ...
        "InterferenceUsesSameRuntimeAntennaAssumptions", false, ...
        "InterferencePathUsesSameArrayAssumptions", false, ...
        "AntennaEvidenceSource", "", ...
        "SameFlowEvidenceSource", "", ...
        "Notes", ""), 0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    T = struct2table(rows, "AsArray", true);
    return;
end
    trialT = localEnsureEvidenceTable(trialT, {'Direction','BSAntennaNumPorts','UEAntennaNumPorts','NumTxPorts','NumRxAntennas','PrecodingNumPorts','ChannelArrayModel','ChannelObjectSource','ChannelObjectClass','ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker','ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping','ChannelArrayValueStatus','ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions','InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker','InterferenceChannelArrayValueStatus','InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions','AntennaEvidenceSource','SameFlowEvidenceSource'});
dirList = unique(string(trialT.Direction), "stable");
for di = 1:numel(dirList)
    dir = dirList(di);
    mask = strcmpi(string(trialT.Direction), dir);
    slice = trialT(mask, :);
    if isempty(slice)
        continue;
    end
    if strcmpi(char(dir), "DL")
        cfgTx = double(slice.BSAntennaNumPorts);
        cfgRx = double(slice.UEAntennaNumPorts);
    else
        cfgTx = double(slice.UEAntennaNumPorts);
        cfgRx = double(slice.BSAntennaNumPorts);
    end
    obsTx = double(slice.NumTxPorts);
    obsRx = double(slice.NumRxAntennas);
    obsPrec = double(slice.PrecodingNumPorts);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Direction", char(dir), ...
        "ObservedRows", double(height(slice)), ...
        "ChannelArrayModel", char(localLastToken(slice, "ChannelArrayModel")), ...
        "ConfiguredTxAntennaPorts", localMeanValue(cfgTx), ...
        "ConfiguredRxAntennaPorts", localMeanValue(cfgRx), ...
        "ObservedNumTxPorts", localMeanValue(obsTx), ...
        "ObservedNumRxAntennas", localMeanValue(obsRx), ...
        "ObservedPrecodingNumPorts", localMeanValue(obsPrec), ...
        "TxPortConsistencyRate", localConsistencyRate(obsTx, cfgTx), ...
        "RxPortConsistencyRate", localConsistencyRate(obsRx, cfgRx), ...
        "PrecodingPortConsistencyRate", localConsistencyRate(obsPrec, cfgTx), ...
        "ChannelObjectSource", char(localLastToken(slice, "ChannelObjectSource")), ...
        "ChannelObjectClass", char(localLastToken(slice, "ChannelObjectClass")), ...
        "ChannelArrayHandlingStatus", char(localLastToken(slice, "ChannelArrayHandlingStatus")), ...
        "ChannelArrayHandlingBlocker", char(localLastToken(slice, "ChannelArrayHandlingBlocker")), ...
        "ChannelGeometryCouplingLevel", char(localLastToken(slice, "ChannelGeometryCouplingLevel")), ...
        "GeometryAdapterType", char(localLastToken(slice, "GeometryAdapterType")), ...
        "GeometryAdapterSource", char(localLastToken(slice, "GeometryAdapterSource")), ...
        "GeometryAdapterLimitation", char(localLastToken(slice, "GeometryAdapterLimitation")), ...
        "GeometryAdapterPortMapping", char(localLastToken(slice, "GeometryAdapterPortMapping")), ...
        "ChannelArrayValueStatus", char(localLastToken(slice, "ChannelArrayValueStatus")), ...
        "ChannelUsesCountOnlyAntennaModel", logical(any(logical(slice.ChannelUsesCountOnlyAntennaModel))), ...
        "ChannelUsesSameRuntimeAntennaAssumptions", logical(any(logical(slice.ChannelUsesSameRuntimeAntennaAssumptions))), ...
        "InterferenceChannelObjectSource", char(localLastToken(slice, "InterferenceChannelObjectSource")), ...
        "InterferenceChannelObjectClass", char(localLastToken(slice, "InterferenceChannelObjectClass")), ...
        "InterferenceChannelArrayHandlingStatus", char(localLastToken(slice, "InterferenceChannelArrayHandlingStatus")), ...
        "InterferenceChannelArrayHandlingBlocker", char(localLastToken(slice, "InterferenceChannelArrayHandlingBlocker")), ...
        "InterferenceChannelArrayValueStatus", char(localLastToken(slice, "InterferenceChannelArrayValueStatus")), ...
        "InterferenceUsesSameRuntimeAntennaAssumptions", logical(any(logical(slice.InterferenceUsesSameRuntimeAntennaAssumptions))), ...
        "InterferencePathUsesSameArrayAssumptions", logical(any(logical(slice.InterferencePathUsesSameArrayAssumptions))), ...
        "AntennaEvidenceSource", char(localLastToken(slice, "AntennaEvidenceSource")), ...
        "SameFlowEvidenceSource", char(localLastToken(slice, "SameFlowEvidenceSource")), ...
        "Notes", char(localChannelArrayConsistencyNote(dir, slice)));
end
if isempty(rows)
    T = struct2table(repmat(struct( ...
        "Direction", "", "ObservedRows", NaN, "ChannelArrayModel", "", ...
        "ConfiguredTxAntennaPorts", NaN, "ConfiguredRxAntennaPorts", NaN, ...
        "ObservedNumTxPorts", NaN, "ObservedNumRxAntennas", NaN, "ObservedPrecodingNumPorts", NaN, ...
        "TxPortConsistencyRate", NaN, "RxPortConsistencyRate", NaN, "PrecodingPortConsistencyRate", NaN, ...
        "ChannelObjectSource", "", "ChannelObjectClass", "", "ChannelArrayHandlingStatus", "", "ChannelArrayHandlingBlocker", "", "ChannelGeometryCouplingLevel", "", "GeometryAdapterType", "", "GeometryAdapterSource", "", "GeometryAdapterLimitation", "", "GeometryAdapterPortMapping", "", "ChannelArrayValueStatus", "", ...
        "ChannelUsesCountOnlyAntennaModel", false, "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
        "InterferenceChannelObjectSource", "", "InterferenceChannelObjectClass", "", "InterferenceChannelArrayHandlingStatus", "", "InterferenceChannelArrayHandlingBlocker", "", "InterferenceChannelArrayValueStatus", "", ...
        "InterferenceUsesSameRuntimeAntennaAssumptions", false, "InterferencePathUsesSameArrayAssumptions", false, ...
        "AntennaEvidenceSource", "", "SameFlowEvidenceSource", "", "Notes", ""), 0, 1));
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildTodToaTraceTable(trialT)
fields = { ...
    'Direction','UEIndex','RNTI','BaseStationID','Frame','Slot','GrantContextId', ...
    'PropagationDistance_m','GeometricPropagationDelay_s','DominantPathDelay_s','ChannelFilterDelay_s','PropagationDelay_s', ...
    'ToD_s','ToA_s','ToAEstimate_s','TimingEstimateUsed','ChannelArrayModel','ChannelUsesCountOnlyAntennaModel', ...
    'ToDSource','ToASource','ToAEstimateSource','ChannelDelaySource','AntennaGeometrySource','RuntimeTraceSource','SameFlowEvidenceSource'};
T = localProjectEvidenceTable(trialT, fields);
if isempty(T)
    return;
end
T.ToAEstimateError_s = double(T.ToAEstimate_s) - double(T.ToA_s);
end

function T = localBuildTimingPositioningRuntimeEvidenceTable(trialT)
rows = repmat(struct( ...
    "Direction", "", ...
    "ObservedRows", NaN, ...
    "FiniteToDCount", NaN, ...
    "FiniteToACount", NaN, ...
    "FiniteToAEstimateCount", NaN, ...
    "TimingEstimateUsedCount", NaN, ...
    "MeanPropagationDistance_m", NaN, ...
    "MeanPropagationDelay_s", NaN, ...
    "MeanToAEstimateError_s", NaN, ...
    "ToDSourceSet", "", ...
    "ToASourceSet", "", ...
    "ChannelDelaySourceSet", "", ...
    "AntennaGeometrySourceSet", "", ...
    "RuntimeTraceSourceSet", "", ...
    "SameFlowEvidenceSourceSet", "", ...
    "Notes", ""), 0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    T = struct2table(rows, "AsArray", true);
    return;
end
trialT = localEnsureEvidenceTable(trialT, {'Direction','ToD_s','ToA_s','ToAEstimate_s','TimingEstimateUsed','PropagationDistance_m','PropagationDelay_s','ToDSource','ToASource','ChannelDelaySource','AntennaGeometrySource','RuntimeTraceSource','SameFlowEvidenceSource'});
dirList = unique(string(trialT.Direction), "stable");
for di = 1:numel(dirList)
    dir = dirList(di);
    slice = trialT(strcmpi(string(trialT.Direction), dir), :);
    if isempty(slice)
        continue;
    end
    toaErr = double(slice.ToAEstimate_s) - double(slice.ToA_s);
    toaErr = toaErr(isfinite(toaErr));
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Direction", char(dir), ...
        "ObservedRows", double(height(slice)), ...
        "FiniteToDCount", double(sum(isfinite(double(slice.ToD_s)))), ...
        "FiniteToACount", double(sum(isfinite(double(slice.ToA_s)))), ...
        "FiniteToAEstimateCount", double(sum(isfinite(double(slice.ToAEstimate_s)))), ...
        "TimingEstimateUsedCount", double(sum(logical(slice.TimingEstimateUsed))), ...
        "MeanPropagationDistance_m", localMeanValue(double(slice.PropagationDistance_m)), ...
        "MeanPropagationDelay_s", localMeanValue(double(slice.PropagationDelay_s)), ...
        "MeanToAEstimateError_s", localMeanValue(toaErr), ...
        "ToDSourceSet", char(localTokenSet(slice, "ToDSource")), ...
        "ToASourceSet", char(localTokenSet(slice, "ToASource")), ...
        "ChannelDelaySourceSet", char(localTokenSet(slice, "ChannelDelaySource")), ...
        "AntennaGeometrySourceSet", char(localTokenSet(slice, "AntennaGeometrySource")), ...
        "RuntimeTraceSourceSet", char(localTokenSet(slice, "RuntimeTraceSource")), ...
        "SameFlowEvidenceSourceSet", char(localTokenSet(slice, "SameFlowEvidenceSource")), ...
        "Notes", "ToD is the active slot-start runtime reference. ToA is derived in the active DL/UL trial path from runtime geometry plus channel-path delay; ToAEstimate comes from receiver timing estimation when available.");
end
if isempty(rows)
    T = struct2table(repmat(struct( ...
        "Direction", "", "ObservedRows", NaN, "FiniteToDCount", NaN, "FiniteToACount", NaN, ...
        "FiniteToAEstimateCount", NaN, "TimingEstimateUsedCount", NaN, "MeanPropagationDistance_m", NaN, ...
        "MeanPropagationDelay_s", NaN, "MeanToAEstimateError_s", NaN, "ToDSourceSet", "", "ToASourceSet", "", ...
        "ChannelDelaySourceSet", "", "AntennaGeometrySourceSet", "", "RuntimeTraceSourceSet", "", "SameFlowEvidenceSourceSet", "", "Notes", ""), 0, 1));
    return;
end
T = struct2table(rows, "AsArray", true);
end

function T = localVertcat(parts)
parts = parts(cellfun(@(x) istable(x) && ~isempty(x), parts));
if isempty(parts)
    T = table();
else
    T = vertcat(parts{:});
end
end

function value = localMean(T, name, mask)
if nargin < 3 || isempty(mask)
    mask = true(height(T), 1);
end
value = NaN;
if ~(istable(T) && ismember(name, string(T.Properties.VariableNames)))
    return;
end
vals = double(T{mask, name});
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
value = mean(vals, "omitnan");
end

function values = localColumnVector(T, name)
if ~(istable(T) && ismember(name, string(T.Properties.VariableNames)))
    values = zeros(0,1);
    return;
end
values = double(T.(name));
values = values(isfinite(values));
end

function value = localLookup(T, ueIdx, name)
value = NaN;
if ~(istable(T) && ~isempty(T) && all(ismember(["UEIndex", name], string(T.Properties.VariableNames))))
    return;
end
mask = abs(double(T.UEIndex) - double(ueIdx)) < 1e-9;
if ~any(mask)
    return;
end
col = T.(char(name));
vals = col(mask);
if iscell(vals)
    if isempty(vals)
        return;
    end
    value = vals{end};
    return;
end
if isstring(vals)
    if isempty(vals)
        value = "";
    else
        value = vals(end);
    end
    return;
end
if ischar(vals)
    value = string(vals);
    return;
end
if islogical(vals)
    if isempty(vals)
        return;
    end
    value = logical(vals(end));
    return;
end
vals = double(vals);
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
value = vals(end);
end

function value = localLookupStringOrBlank(T, ueIdx, name)
value = "";
rawValue = localLookup(T, ueIdx, name);
txt = string(rawValue);
if isempty(txt) || all(ismissing(txt))
    return;
end
txt = txt(~ismissing(txt));
if isempty(txt)
    return;
end
value = char(txt(end));
end

function row = localEmptyUserPerformanceRow()
row = struct( ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "DL_Throughput_Mbps", NaN, ...
    "UL_Throughput_Mbps", NaN, ...
    "DL_ObservedRowCount", NaN, ...
    "UL_ObservedRowCount", NaN, ...
    "DL_BLER", NaN, ...
    "UL_BLER", NaN, ...
    "DL_FER", NaN, ...
    "UL_FER", NaN, ...
    "DL_MeanMeasuredSINR_dB", NaN, ...
    "UL_MeanMeasuredSINR_dB", NaN, ...
    "DL_ZeroThroughputReason", "", ...
    "UL_ZeroThroughputReason", "", ...
    "UserThroughput_Mbps", NaN, ...
    "HARQFailureRate", NaN);
end

function reason = localResolveZeroThroughputReason(slice)
reason = "";
if ~(istable(slice) && ~isempty(slice))
    reason = "no_runtime_rows";
    return;
end
goodput = mean(double(slice.Goodput_Mbps), "omitnan");
if isfinite(goodput) && goodput > 0
    return;
end
status = upper(strtrim(string(slice.Status)));
if all(status == "CRASH")
    reason = "all_trials_crashed";
    return;
end
crc = double(slice.CRCPass);
if any(isfinite(crc)) && mean(1 - crc, "omitnan") >= 0.99
    reason = "all_executed_transport_blocks_failed_crc";
    return;
end
if ~any(isfinite(crc))
    reason = "no_crc_outcome_available";
    return;
end
reason = "zero_goodput_runtime_observed";
end

function value = localPercentile(vals, pct)
value = NaN;
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
vals = sort(vals);
if numel(vals) == 1
    value = vals;
    return;
end
pos = 1 + (numel(vals) - 1) * (double(pct) / 100);
idxLo = max(1, floor(pos));
idxHi = min(numel(vals), ceil(pos));
if idxLo == idxHi
    value = vals(idxLo);
    return;
end
alpha = pos - idxLo;
value = vals(idxLo) + alpha * (vals(idxHi) - vals(idxLo));
end

function T = localProjectEvidenceTable(sourceT, fields)
fields = string(fields(:)).';
T = localEnsureEvidenceTable(sourceT, fields);
if ~(istable(T) && ~isempty(T))
    T = table();
    for i = 1:numel(fields)
        T.(char(fields(i))) = localEvidenceDefaultColumn(0, fields(i));
    end
    return;
end
T = T(:, cellstr(fields));
end

function T = localEnsureEvidenceTable(T, fields)
fields = string(fields(:)).';
if ~(istable(T) && ~isempty(T))
    T = table();
    for i = 1:numel(fields)
        T.(char(fields(i))) = localEvidenceDefaultColumn(0, fields(i));
    end
    return;
end
vars = string(T.Properties.VariableNames);
for i = 1:numel(fields)
    field = fields(i);
    if ~ismember(field, vars)
        T.(char(field)) = localEvidenceDefaultColumn(height(T), field);
    end
end
end

function col = localEvidenceDefaultColumn(nRows, fieldName)
name = lower(char(string(fieldName)));
if any(strcmp(name, ["direction","grantcontextid","nodetype","arraytype","arrayclass","elementclass","polarization","antennaconfigsource","runtimeobjectsource","sameflowevidencesource","bsantennaarrayclass","bsantennaelementclass","bsantennaarraytype","bsantennapolarization","ueantennaarrayclass","ueantennaelementclass","ueantennaarraytype","ueantennapolarization","runtimeantennaobjectsource","antennaruntimeobjectvaluerole","antennaruntimeobjectvaluestatus","antennaruntimeobjectnareason","channelarraymodel","channelobjectsource","channelobjectclass","channelarrayhandlingstatus","channelarrayhandlingblocker","channelarrayvaluerole","channelarrayvaluestatus","interferencechannelobjectsource","interferencechannelobjectclass","interferencechannelarrayhandlingstatus","interferencechannelarrayhandlingblocker","interferencechannelarrayvaluerole","interferencechannelarrayvaluestatus","todsource","toasource","toaestimatesource","channeldelaysource","antennageometrysource","runtimetracesource","antennaevidencesource"]))
    col = strings(nRows, 1);
elseif any(strcmp(name, ["bsantennahasphasedarrayobject","ueantennahasphasedarrayobject","antennaruntimeobjectcreated","channelusescountonlyantennamodel","channelusessameruntimeantennaassumptions","interferenceusessameruntimeantennaassumptions","interferencepathusessamearrayassumptions","timingestimateused"]))
    col = false(nRows, 1);
else
    col = nan(nRows, 1);
end
end

function value = localLastToken(T, name)
value = "";
if ~(istable(T) && ~isempty(T) && ismember(name, string(T.Properties.VariableNames)))
    return;
end
col = string(T.(name));
col = strtrim(col);
col = col(strlength(col) > 0);
if isempty(col)
    return;
end
value = col(end);
end

function token = localTokenSet(T, name)
token = "";
if ~(istable(T) && ~isempty(T) && ismember(name, string(T.Properties.VariableNames)))
    return;
end
vals = string(T.(name));
vals = strtrim(vals);
vals = vals(strlength(vals) > 0);
if isempty(vals)
    return;
end
token = strjoin(unique(vals, "stable"), "|");
end

function value = localMeanValue(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = mean(vals, "omitnan");
end
end

function rate = localConsistencyRate(lhs, rhs)
lhs = double(lhs(:));
rhs = double(rhs(:));
mask = isfinite(lhs) & isfinite(rhs);
if ~any(mask)
    rate = NaN;
    return;
end
rate = mean(abs(lhs(mask) - rhs(mask)) < 1e-9, "omitnan");
end

function note = localChannelArrayConsistencyNote(direction, slice)
status = strtrim(string(localLastToken(slice, "ChannelArrayHandlingStatus")));
blocker = strtrim(string(localLastToken(slice, "ChannelArrayHandlingBlocker")));
if status == "count_only_spatial_dims_no_runtime_geometry"
    note = string(direction) + " uses a count-only fading channel object: runtime BS/UE antenna objects still feed beam/precoding context, but the active nrTDLChannel consumes only antenna counts.";
elseif status == "adapted_geometry_backed_reduced_representation"
    adapter = strtrim(string(localLastToken(slice, "GeometryAdapterType")));
    note = string(direction) + " uses a runtime-geometry-backed reduced TDL representation: the active nrTDLChannel consumes custom Tx/Rx spatial correlation matrices derived from runtime array geometry, not full runtime array objects.";
    if strlength(adapter) > 0
        note = note + " Adapter: " + adapter + ".";
    end
elseif status == "config_array_shape_no_runtime_object_pose"
    note = string(direction) + " uses a config-resolved CDL array-shape channel: the fading channel consumes array shape from config, not the runtime antenna objects or their pose.";
elseif status == "runtime_array_shape_spacing_orientation_coupled"
    note = string(direction) + " uses a runtime-resolved CDL array channel: the active nrCDLChannel consumes BS/UE runtime array shape, spacing, polarization count, and orientation metadata.";
elseif status == "no_fading_channel_object"
    note = string(direction) + " uses the AWGN/no-fading shortcut, so no channel object consumed BS/UE array geometry.";
else
    note = string(direction) + " channel-array handling status: " + status + ".";
end
if strlength(blocker) > 0
    note = note + " Blocker: " + blocker + ".";
end
end
