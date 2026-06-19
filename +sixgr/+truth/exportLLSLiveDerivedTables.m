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
sixgr.util.ensureFolder(layout.ReportCSVDir);
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
artifacts.LinkAdaptationInputPath = fullfile(layout.ReportCSVDir, "live_link_adaptation_input_table.csv");
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
artifacts.ChannelImpulseResponsePath = fullfile(layout.ReportCSVDir, "channel_impulse_response.csv");

channelT = localBuildChannelStatsTable(dlT, ulT, srsT, trsT);
rankT = localBuildRankStatsTable(dlT, ulT);
beamT = localBuildBeamStatsTable(dlT, ulT, runFolder);
csiT = localBuildCSIStatsTable(dlT, ulT);
csirsT = localBuildCSIRSStatsTable(dlT, srsT, trsT);
csirsT = sixgr.truth.canonicalizeLLSLiveSignalChainTable("csirs_stats", csirsT);
linkAdaptationT = localBuildLinkAdaptationInputTable(cfg, dlT, ulT);
harqSummaryT = sixgr.util.structGet(slotTrace, "HARQSummaryTable", table());
harqTimelineT = sixgr.util.structGet(slotTrace, "HARQTimelineTable", table());
if ~(istable(harqSummaryT) && ismember("Direction", string(harqSummaryT.Properties.VariableNames)))
    harqSummaryT = table();
end
if ~(istable(harqTimelineT) && ismember("Direction", string(harqTimelineT.Properties.VariableNames)))
    harqTimelineT = table();
end
if isempty(harqTimelineT)
    [harqSummaryT, harqTimelineT] = localBuildHARQObservationTables(dlT, ulT);
elseif isempty(harqSummaryT)
    harqSummaryT = localBuildHARQObservationSummaryFromTimeline(harqTimelineT);
end
userPerfT = sixgr.util.structGet(slotTrace, "UserPerformanceTable", table());
if ~(istable(userPerfT) && ~isempty(userPerfT))
    userPerfT = localBuildUserPerformanceTable(multiUserDL, multiUserUL, dlT, ulT, harqTimelineT);
end
coverageT = sixgr.util.structGet(slotTrace, "CoverageLayerTable", table());
if ~(istable(coverageT) && ~isempty(coverageT))
    coverageT = localBuildCoverageLayerTable(mobilityArtifacts, userPerfT);
end
coverageT = localEnsureCoverageLayerSINRContract(coverageT);
errorRateT = localBuildErrorRateSummaryTable(dlT, ulT);
trialCombinedT = localCombineDirectionalTrials(dlT, ulT);
antennaConfigT = localBuildAntennaConfigResolvedTable(mobilityArtifacts, slotTrace);
antennaRuntimeT = localBuildAntennaRuntimeEvidenceTable(trialCombinedT);
arrayConsistencyT = localBuildChannelArrayConsistencyTable(trialCombinedT);
todToaT = localBuildTodToaTraceTable(trialCombinedT);
timingPositioningT = localBuildTimingPositioningRuntimeEvidenceTable(trialCombinedT);
channelImpulseT = sixgr.truth.buildChannelImpulseResponseTable(cfg);

sixgr.util.csvWriteTable(artifacts.ChannelEstimationStatsPath, channelT);
sixgr.util.csvWriteTable(artifacts.RankEstimationStatsPath, rankT);
sixgr.util.csvWriteTable(artifacts.BeamSelectionStatsPath, beamT);
sixgr.util.csvWriteTable(artifacts.CSIFeedbackStatsPath, csiT);
sixgr.util.csvWriteTable(artifacts.CSIRSStatsPath, csirsT);
sixgr.util.csvWriteTable(artifacts.LinkAdaptationInputPath, linkAdaptationT);
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
sixgr.util.csvWriteTable(artifacts.ChannelImpulseResponsePath, channelImpulseT);

artifacts.ChannelEstimationStats = channelT;
artifacts.RankEstimationStats = rankT;
artifacts.BeamSelectionStats = beamT;
artifacts.CSIFeedbackStats = csiT;
artifacts.CSIRSStats = csirsT;
artifacts.LinkAdaptationInput = linkAdaptationT;
artifacts.UserPerformance = userPerfT;
artifacts.CoverageLayer = coverageT;
artifacts.ErrorRateSummary = errorRateT;
artifacts.AntennaConfigResolved = antennaConfigT;
artifacts.AntennaRuntimeEvidence = antennaRuntimeT;
artifacts.ChannelArrayConsistency = arrayConsistencyT;
artifacts.TodToaTrace = todToaT;
artifacts.TimingPositioningEvidence = timingPositioningT;
artifacts.ChannelImpulseResponse = channelImpulseT;
artifacts.HARQ = struct( ...
    "SummaryCSV", artifacts.LiveHARQSummaryPath, ...
    "TimelineCSV", artifacts.LiveHARQTimelinePath, ...
    "SummaryTable", harqSummaryT, ...
    "TimelineTable", harqTimelineT);
end

function T = localBuildChannelStatsTable(dlT, ulT, srsT, trsT)
parts = { ...
    localAggregateByDirectionAndSNR(dlT, "DL", ["PostEqSINR_dB","ReceiverHestSINR_dB","DecoderTruthProxySINR_dB","SystemLevelSINR_dB","LargeScaleSINR_dB","NMSE_dB","ChannelGain_dB","ConditionNumber_dB","TimingOffset_samples","EstimatedDopplerHz","PhaseTrackingError_deg"], "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", ["PostEqSINR_dB","ReceiverHestSINR_dB","DecoderTruthProxySINR_dB","SystemLevelSINR_dB","LargeScaleSINR_dB","NMSE_dB","ChannelGain_dB","ConditionNumber_dB","TimingOffset_samples","EstimatedDopplerHz","PhaseTrackingError_deg"], "ul_pusch_trials"), ...
    localAggregateByDirectionAndSNR(srsT, "SRS", ["SINR_dB","CQI","MCSIndex","RankEstimate","EstimatedRI","NMSE_dB","EstimatedDopplerHz","DopplerError_Hz","QCLAccuracy","TrackingFailureProbability"], "srs_trials"), ...
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

function T = localBuildBeamStatsTable(dlT, ulT, runFolder)
if nargin < 3
    runFolder = "";
end
beamMetricFields = ["SelectedBeamIndex","BestBeamIndex","BeamHit","TopKBeamHit","BeamCandidateCount", ...
    "SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB","PMI","CRI"];
rawBeamT = localVertcat({ ...
    localAggregateByDirectionAndSNR(dlT, "DL", beamMetricFields, "dl_pdsch_trials"), ...
    localAggregateByDirectionAndSNR(ulT, "UL", beamMetricFields, "ul_pusch_trials")});
if isempty(rawBeamT)
    [persistedDL, persistedUL] = localReadPersistedDirectionalBeamTrials(runFolder);
    rawBeamT = localVertcat({ ...
        localAggregateByDirectionAndSNR(persistedDL, "DL", beamMetricFields, "air_interface/csv/dl_pdsch_trials.csv"), ...
        localAggregateByDirectionAndSNR(persistedUL, "UL", beamMetricFields, "air_interface/csv/ul_pusch_trials.csv")});
end

parts = { ...
    rawBeamT, ...
    localBuildSSBBeamSweepStats(localReadSSBBeamSweepTable(runFolder)), ...
    localBuildRuntimeBeamArtifactStats(localReadBeamArtifactTable(runFolder, "probe_beam_mimo.csv"), "beamforming/csv/probe_beam_mimo.csv"), ...
    localBuildRuntimeBeamArtifactStats(localReadBeamArtifactTable(runFolder, "beam_precoder_table.csv"), "beamforming/csv/beam_precoder_table.csv"), ...
    localBuildBeamStateTraceStats(localReadBeamArtifactTable(runFolder, "beam_management_state_trace.csv")), ...
    localBuildBeamEventTraceStats(localReadBeamArtifactTable(runFolder, "beam_management_event_trace.csv"))};
T = localVertcat(parts);
if isempty(T)
    T = localEmptySummaryTable();
end
end

function [dlT, ulT] = localReadPersistedDirectionalBeamTrials(runFolder)
dlT = table();
ulT = table();
if strlength(strtrim(string(runFolder))) == 0
    return;
end
layout = sixgr.report.resultLayout(runFolder);
dlT = localReadOptionalDerivedTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
ulT = localReadOptionalDerivedTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
end

function T = localReadSSBBeamSweepTable(runFolder)
T = table();
if strlength(strtrim(string(runFolder))) == 0
    return;
end
layout = sixgr.report.resultLayout(runFolder);
candidates = { ...
    fullfile(layout.BeamformingCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), ...
    fullfile(layout.BeamformingCSVDir, "ssb_beam_sweep.csv"), ...
    fullfile(layout.ControlCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "ssb_pbch_sib1_beam_sweep.csv")};
T = localReadFirstDerivedTable(candidates);
end

function T = localReadBeamArtifactTable(runFolder, fileName)
T = table();
if strlength(strtrim(string(runFolder))) == 0
    return;
end
layout = sixgr.report.resultLayout(runFolder);
candidates = { ...
    fullfile(layout.BeamformingCSVDir, char(fileName)), ...
    fullfile(layout.ReportCSVDir, char(fileName)), ...
    fullfile(layout.ControlCSVDir, char(fileName)), ...
    fullfile(layout.AirInterfaceCSVDir, char(fileName))};
T = localReadFirstDerivedTable(candidates);
end

function T = localReadFirstDerivedTable(candidates)
T = table();
for i = 1:numel(candidates)
    Ti = localReadOptionalDerivedTable(candidates{i});
    if istable(Ti) && ~isempty(Ti)
        T = Ti;
        return;
    end
end
end

function T = localReadOptionalDerivedTable(pathStr)
T = table();
pathStr = char(string(pathStr));
if strlength(string(pathStr)) == 0 || exist(pathStr, "file") ~= 2
    return;
end
try
    T = readtable(pathStr, "VariableNamingRule", "preserve", "TextType", "string");
catch
    try
        T = readtable(pathStr, "VariableNamingRule", "preserve");
    catch
        T = table();
    end
end
if ~(istable(T) && ~isempty(T))
    T = table();
end
end

function T = localBuildSSBBeamSweepStats(ssbT)
if ~(istable(ssbT) && ~isempty(ssbT))
    T = localEmptySummaryTable();
    return;
end
specs = [ ...
    localBeamMetricSpec("P1SSBConfiguredBeamCount", ["ConfiguredSSBBeamCount","SSBLmax"]); ...
    localBeamMetricSpec("P1PBCHDetectionRate", "DetectionSuccess"); ...
    localBeamMetricSpec("P1PBCHCRCPassRate", "BCHCrcPass"); ...
    localBeamMetricSpec("P1MIBDecodeRate", "MIBDecoded"); ...
    localBeamMetricSpec("P1SIB1StrictDecodeRate", "SIB1StrictOk"); ...
    localBeamMetricSpec("P1SSBReceivedPower_dB", "SSBReceivedPower_dB"); ...
    localBeamMetricSpec("P1PBCHDMRSMetric", "PBCHDMRSMetric"); ...
    localBeamMetricSpec("P1PBCHNoiseVar", "PBCHNoiseVar"); ...
    localBeamMetricSpec("P1TimingOffset_samples", "TimingOffset_samples"); ...
    localBeamMetricSpec("P1AcquisitionTime_ms", "AcquisitionTime_ms"); ...
    localBeamMetricSpec("P1ComputeLatency_ms", "ComputeLatency_ms")];
rowsT = localBuildBeamSummaryRows(ssbT, "SSB_DL", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv", specs, ...
    "measured_ssb_pbch_sib1_sweep");

selectedT = localBuildSSBSelectedBeamRows(ssbT);
T = localVertcat({rowsT, selectedT});
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildSSBSelectedBeamRows(ssbT)
T = localEmptySummaryTable();
if ~(istable(ssbT) && ~isempty(ssbT))
    return;
end
score = localBeamNumericColumn(ssbT, ["SSBReceivedPower_dB","PBCHDMRSMetric"]);
beam = localBeamNumericColumn(ssbT, ["BeamIndex","SSBIndex"]);
if ~any(isfinite(score)) || ~any(isfinite(beam))
    return;
end
[snrBin, snrHasFinite] = localBeamSNRBins(ssbT);
if snrHasFinite
    groups = unique(snrBin(isfinite(snrBin)), "stable");
else
    groups = NaN;
end
rows = repmat(localSummaryRowTemplate(), 0, 1);
for i = 1:numel(groups)
    if snrHasFinite
        mask = abs(snrBin - groups(i)) < 1e-9;
        snrValue = double(groups(i));
        qualityAxis = "SNR_dB";
        qualityRole = "measured_ssb_pbch_sib1_sweep";
        qualitySource = "SNR_dB";
    else
        mask = true(height(ssbT), 1);
        snrValue = NaN;
        qualityAxis = "runtime_beam_sample";
        qualityRole = "measured_ssb_pbch_sib1_sweep";
        qualitySource = "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv";
    end
    valid = mask & isfinite(score) & isfinite(beam);
    if ~any(valid)
        continue;
    end
    validIdx = find(valid);
    [~, relIdx] = max(score(valid));
    selectedIdx = validIdx(relIdx);
    selectedBeam = beam(selectedIdx);
    selectedScore = score(selectedIdx);
    rows(end+1, 1) = localMakeSummaryRow("SSB_DL", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv", snrValue, ...
        qualityAxis, qualityRole, qualitySource, "P1SelectedSSBBeamIndex", selectedBeam, selectedBeam, selectedBeam, 1); %#ok<AGROW>
    rows(end+1, 1) = localMakeSummaryRow("SSB_DL", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv", snrValue, ...
        qualityAxis, qualityRole, qualitySource, "P1SelectedSSBBeamScore", selectedScore, selectedScore, selectedScore, 1); %#ok<AGROW>
    rows(end+1, 1) = localMakeSummaryRow("SSB_DL", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv", snrValue, ...
        qualityAxis, qualityRole, qualitySource, "P1SSBSweptBeamCount", double(nnz(valid)), double(nnz(valid)), double(nnz(valid)), 1); %#ok<AGROW>
end
if ~isempty(rows)
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildRuntimeBeamArtifactStats(sourceT, traceSource)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptySummaryTable();
    return;
end
specs = [ ...
    localBeamMetricSpec("P2SelectedBeamIndex", ["SelectedBeamIndex","selected_beam_index"]); ...
    localBeamMetricSpec("P2BestBeamIndex", ["BestBeamIndex","best_beam_index"]); ...
    localBeamMetricSpec("P2BeamHitRate", ["BeamHit","beam_hit"]); ...
    localBeamMetricSpec("P2TopKBeamHitRate", ["TopKBeamHit","top_k_beam_hit"]); ...
    localBeamMetricSpec("P2BeamCandidateCount", ["BeamCandidateCount","beam_candidate_count"]); ...
    localBeamMetricSpec("P2SelectedBeamGain_dB", ["SelectedBeamGain_dB","selected_beam_gain_db"]); ...
    localBeamMetricSpec("P2BestBeamGain_dB", ["BestBeamGain_dB","best_beam_gain_db"]); ...
    localBeamMetricSpec("P2BeamGainGap_dB", ["BeamGainGap_dB","beam_gain_gap_db"]); ...
    localBeamMetricSpec("P2BeamformingAppliedRate", ["BeamformingApplied","beamforming_applied"]); ...
    localBeamMetricSpec("P2PrecodingActiveRate", ["PrecodingActive","precoding_active"]); ...
    localBeamMetricSpec("P2PrecodingNumLayers", ["PrecodingNumLayers","precoding_num_layers"]); ...
    localBeamMetricSpec("P2PrecodingNumPorts", ["PrecodingNumPorts","precoding_num_ports"])];
T = localBuildBeamSummaryRows(sourceT, "", string(traceSource), specs, "measured_runtime_beam_refinement");
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildBeamStateTraceStats(stateT)
if ~(istable(stateT) && ~isempty(stateT))
    T = localEmptySummaryTable();
    return;
end
specs = [ ...
    localBeamMetricSpec("P2BeamDetectedRate", "BeamDetectedFlag"); ...
    localBeamMetricSpec("P2MisalignmentRate", "MisalignmentFlag"); ...
    localBeamMetricSpec("P2BeamFailureRate", "BeamFailureFlag"); ...
    localBeamMetricSpec("P2PredictionSuccessRate", "PredictionSuccessFlag"); ...
    localBeamMetricSpec("P2TrialsSinceLastSwitch", "TrialsSinceLastSwitch")];
T = localBuildBeamSummaryRows(stateT, "", "beamforming/csv/beam_management_state_trace.csv", specs, ...
    "measured_runtime_beam_state_trace");
if isempty(T)
    T = localEmptySummaryTable();
end
end

function T = localBuildBeamEventTraceStats(eventT)
if ~(istable(eventT) && ~isempty(eventT))
    T = localEmptySummaryTable();
    return;
end
specs = [ ...
    localBeamMetricSpec("P2SwitchEventRate", "SwitchEventFlag"); ...
    localBeamMetricSpec("P2FirstHitEventRate", "FirstHitEventFlag"); ...
    localBeamMetricSpec("P2BeamDetectedEventRate", "BeamDetectedEventFlag"); ...
    localBeamMetricSpec("P2MisalignmentEventRate", "MisalignmentEventFlag"); ...
    localBeamMetricSpec("P2FailureEventRate", "FailureEventFlag"); ...
    localBeamMetricSpec("P2SwitchLatencySlots", "SwitchLatencySlots"); ...
    localBeamMetricSpec("P2SwitchLatency_s", "SwitchLatency_s"); ...
    localBeamMetricSpec("P2TrialsToFirstHit", "TrialsToFirstHit")];
T = localBuildBeamSummaryRows(eventT, "", "beamforming/csv/beam_management_event_trace.csv", specs, ...
    "measured_runtime_beam_event_trace");
if isempty(T)
    T = localEmptySummaryTable();
end
end

function spec = localBeamMetricSpec(metric, columns)
spec = struct("Metric", string(metric), "Columns", string(columns(:)).');
end

function T = localBuildBeamSummaryRows(sourceT, defaultDirection, traceSource, specs, qualityRole)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptySummaryTable();
    return;
end
direction = localBeamTextColumn(sourceT, ["Direction","direction"], string(defaultDirection));
if strlength(strtrim(string(defaultDirection))) == 0
    emptyDir = strlength(strtrim(direction)) == 0;
    direction(emptyDir) = "BEAM";
end
[snrBin, snrHasFinite] = localBeamSNRBins(sourceT);
dirList = unique(direction, "stable");
if isempty(dirList)
    dirList = string(defaultDirection);
end
if snrHasFinite
    snrList = unique(snrBin(isfinite(snrBin)), "stable");
else
    snrList = NaN;
end

rows = repmat(localSummaryRowTemplate(), 0, 1);
for d = 1:numel(dirList)
    dirMask = direction == dirList(d);
    for s = 1:numel(snrList)
        if snrHasFinite
            snrMask = abs(snrBin - snrList(s)) < 1e-9;
            snrValue = double(snrList(s));
            qualityAxis = "SNR_dB";
            qualitySource = "SNR_dB";
        else
            snrMask = true(height(sourceT), 1);
            snrValue = NaN;
            qualityAxis = "runtime_beam_sample";
            qualitySource = string(traceSource);
        end
        mask = dirMask & snrMask;
        if ~any(mask)
            continue;
        end
        for k = 1:numel(specs)
            vals = localBeamNumericColumn(sourceT, specs(k).Columns);
            vals = vals(mask);
            vals = vals(isfinite(vals));
            if isempty(vals)
                continue;
            end
            rows(end+1, 1) = localMakeSummaryRow(dirList(d), traceSource, snrValue, qualityAxis, ...
                qualityRole, qualitySource, specs(k).Metric, mean(vals, "omitnan"), ...
                localPercentile(vals, 5), localPercentile(vals, 95), double(numel(vals))); %#ok<AGROW>
        end
    end
end
if isempty(rows)
    T = localEmptySummaryTable();
else
    T = struct2table(rows, "AsArray", true);
end
end

function [snrBin, hasFinite] = localBeamSNRBins(T)
snr = localBeamNumericColumn(T, ["SNR_dB","snr_db"]);
hasFinite = any(isfinite(snr));
snrBin = nan(height(T), 1);
if hasFinite
    finiteMask = isfinite(snr);
    snrBin(finiteMask) = round(snr(finiteMask));
end
end

function values = localBeamNumericColumn(T, names)
values = nan(height(T), 1);
names = string(names(:)).';
firstFound = nan(height(T), 1);
foundAny = false;
for i = 1:numel(names)
    name = localFindTableVariable(T, names(i));
    if strlength(name) == 0
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw) || islogical(raw)
        candidate = double(raw);
    else
        token = lower(strtrim(string(raw)));
        candidate = str2double(token);
        candidate(token == "true" | token == "yes" | token == "pass" | token == "ok") = 1;
        candidate(token == "false" | token == "no" | token == "fail") = 0;
    end
    if ~foundAny
        firstFound = candidate;
        foundAny = true;
    end
    if any(isfinite(candidate))
        values = candidate;
        return;
    end
end
if foundAny
    values = firstFound;
end
end

function values = localBeamTextColumn(T, names, defaultValue)
values = repmat(string(defaultValue), height(T), 1);
name = localFindTableVariable(T, names);
if strlength(name) == 0
    return;
end
values = string(T.(char(name)));
end

function name = localFindTableVariable(T, candidates)
name = "";
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
normVars = lower(regexprep(vars, "[^A-Za-z0-9]", ""));
candidates = string(candidates(:)).';
for i = 1:numel(candidates)
    normCandidate = lower(regexprep(candidates(i), "[^A-Za-z0-9]", ""));
    idx = find(normVars == normCandidate, 1, "first");
    if ~isempty(idx)
        name = vars(idx);
        return;
    end
end
end

function row = localSummaryRowTemplate()
row = struct("Direction","", "TraceSource","", "SNR_dB", NaN, "QualityAxis", "", ...
    "QualityValueRole", "", "QualitySource", "", "Metric", "", "MeanValue", NaN, ...
    "P05Value", NaN, "P95Value", NaN, "SampleCount", NaN);
end

function row = localMakeSummaryRow(direction, traceSource, snrValue, qualityAxis, qualityRole, qualitySource, metric, meanValue, p05Value, p95Value, sampleCount)
row = localSummaryRowTemplate();
row.Direction = string(direction);
row.TraceSource = string(traceSource);
row.SNR_dB = double(snrValue);
row.QualityAxis = string(qualityAxis);
row.QualityValueRole = string(qualityRole);
row.QualitySource = string(qualitySource);
row.Metric = string(metric);
row.MeanValue = double(meanValue);
row.P05Value = double(p05Value);
row.P95Value = double(p95Value);
row.SampleCount = double(sampleCount);
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

function T = localBuildLinkAdaptationInputTable(cfg, dlT, ulT)
parts = {};
if istable(dlT) && ~isempty(dlT)
    parts{end+1} = localDirectionLinkAdaptationRows(dlT, "DL", "air_interface/csv/dl_pdsch_trials.csv", cfg); %#ok<AGROW>
end
if istable(ulT) && ~isempty(ulT)
    parts{end+1} = localDirectionLinkAdaptationRows(ulT, "UL", "air_interface/csv/ul_pusch_trials.csv", cfg); %#ok<AGROW>
end
T = localVertcat(parts);
if isempty(T)
    T = table();
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
        "MeanWidebandCQI", localMeanFirstExisting(srsT, ["WidebandCQI","CQI"]), ...
        "MeanPMI", localMeanFirstExisting(srsT, ["PMI","EstimatedTPMI","TPMI"]), ...
        "MeanCRI", NaN, ...
        "MeanCSIPayloadBitLength", NaN, ...
        "Notes", "UL sounding summary from actual SRS receiver evidence.");
end
if isempty(rows)
    T = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'Direction','TraceSource','SNR_dB','MeanNMSE_dB','MeanWidebandCQI','MeanPMI','MeanCRI','MeanCSIPayloadBitLength','Notes'});
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildUserPerformanceTable(dlSummary, ulSummary, dlRaw, ulRaw, harqTimelineT)
if nargin < 3
    dlRaw = table();
end
if nargin < 4
    ulRaw = table();
end
if nargin < 5
    harqTimelineT = table();
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
    "DL_MeanPostEqSINR_dB", NaN, ...
    "UL_MeanPostEqSINR_dB", NaN, ...
    "DL_MeanReceiverHestSINR_dB", NaN, ...
    "UL_MeanReceiverHestSINR_dB", NaN, ...
    "DL_MeanMeasuredSINR_dB", NaN, ...
    "UL_MeanMeasuredSINR_dB", NaN, ...
    "DL_ZeroThroughputReason", "", ...
    "UL_ZeroThroughputReason", "", ...
    "UserThroughput_Mbps", NaN, ...
    "DL_HARQFailureRate", NaN, ...
    "UL_HARQFailureRate", NaN, ...
    "DL_HARQObservationCount", NaN, ...
    "UL_HARQObservationCount", NaN, ...
    "HARQFailureRate", NaN, ...
    "HARQObservationCount", NaN), 0, 1);
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
    row.DL_MeanPostEqSINR_dB = localLookup(dlSummary, ueIdx, "MeanPostEqSINR_dB");
    row.UL_MeanPostEqSINR_dB = localLookup(ulSummary, ueIdx, "MeanPostEqSINR_dB");
    row.DL_MeanReceiverHestSINR_dB = localLookup(dlSummary, ueIdx, "MeanReceiverHestSINR_dB");
    row.UL_MeanReceiverHestSINR_dB = localLookup(ulSummary, ueIdx, "MeanReceiverHestSINR_dB");
    row.DL_MeanMeasuredSINR_dB = localLookup(dlSummary, ueIdx, "MeanMeasuredSINR_dB");
    row.UL_MeanMeasuredSINR_dB = localLookup(ulSummary, ueIdx, "MeanMeasuredSINR_dB");
    row.DL_ZeroThroughputReason = localLookupStringOrBlank(dlSummary, ueIdx, "ZeroThroughputReason");
    row.UL_ZeroThroughputReason = localLookupStringOrBlank(ulSummary, ueIdx, "ZeroThroughputReason");
    row.UserThroughput_Mbps = sum([row.DL_Throughput_Mbps row.UL_Throughput_Mbps], "omitnan");
    [row.DL_HARQFailureRate, row.DL_HARQObservationCount] = localHARQFailureMetrics(harqTimelineT, ueIdx, "DL");
    [row.UL_HARQFailureRate, row.UL_HARQObservationCount] = localHARQFailureMetrics(harqTimelineT, ueIdx, "UL");
    [row.HARQFailureRate, row.HARQObservationCount] = localCombineDirectionalHARQFailureMetrics( ...
        row.DL_HARQFailureRate, row.DL_HARQObservationCount, ...
        row.UL_HARQFailureRate, row.UL_HARQObservationCount);
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
    "MeanPostEqSINR_dB", NaN, ...
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
        "BeamformingApplied", localLastLogicalValue(slice, "BeamformingApplied", false), ...
        "BeamSelectionStrategy", char(localLastStringValue(slice, "BeamSelectionStrategy", "")), ...
        "BeamIndexSet", char(localLastStringValue(slice, "BeamIndexSet", "")), ...
        "ExecutionModel", char(localLastStringValue(slice, "ExecutionModel", "")), ...
        "Throughput_Mbps", mean(double(slice.Goodput_Mbps), "omitnan"), ...
        "ObservedRowCount", double(height(slice)), ...
        "BLER", mean(1 - double(slice.CRCPass), "omitnan"), ...
        "FER", localFrameErrorRate(slice), ...
        "BER", localRatio(sum(double(slice.BitErrors), "omitnan"), sum(double(slice.BitsCompared), "omitnan")), ...
        "PassRate", double(sem.PassRate), ...
        "MeanPostEqSINR_dB", localMeanOptionalColumn(slice, "PostEqSINR_dB"), ...
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
    "PostEqSINR_dB", NaN, ...
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

function value = localLastValue(T, name, defaultValue)
if nargin < 3
    defaultValue = NaN;
end
value = defaultValue;
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

function value = localLastLogicalValue(T, name, defaultValue)
if nargin < 3
    defaultValue = false;
end
value = logical(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
col = T.(name);
if islogical(col)
    value = logical(col(end));
    return;
end
if isnumeric(col)
    raw = double(col(end));
    if isfinite(raw)
        value = raw ~= 0;
    end
    return;
end
raw = lower(strtrim(string(col(end))));
if ismember(raw, ["true","1","yes","y","on","enabled","applied"])
    value = true;
elseif ismember(raw, ["false","0","no","n","off","disabled","not_applied",""])
    value = false;
end
end

function value = localLastStringValue(T, name, defaultValue)
if nargin < 3
    defaultValue = "";
end
value = string(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
col = T.(name);
if iscell(col)
    raw = string(col{end});
else
    raw = string(col(end));
end
if isempty(raw) || ismissing(raw) || strlength(strtrim(raw)) == 0
    return;
end
value = raw;
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

function T = localEnsureCoverageLayerSINRContract(T)
if ~istable(T)
    T = table();
end
n = height(T);
if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames))
    T.PostEqSINR_dB = nan(n, 1);
end
if ~ismember("PostEqWidebandSINR_dB", string(T.Properties.VariableNames))
    T.PostEqWidebandSINR_dB = double(T.PostEqSINR_dB);
end
if ~ismember("ReceiverHestSINR_dB", string(T.Properties.VariableNames))
    T.ReceiverHestSINR_dB = nan(n, 1);
end
if ~ismember("ReceiverHestWidebandSINR_dB", string(T.Properties.VariableNames))
    T.ReceiverHestWidebandSINR_dB = double(T.ReceiverHestSINR_dB);
end
if ~ismember("DecoderTruthProxySINR_dB", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINR_dB = nan(n, 1);
end
if ~ismember("DecoderTruthProxyWidebandSINR_dB", string(T.Properties.VariableNames))
    T.DecoderTruthProxyWidebandSINR_dB = double(T.DecoderTruthProxySINR_dB);
end
decoderWideband = double(T.DecoderTruthProxyWidebandSINR_dB);
decoderTrial = double(T.DecoderTruthProxySINR_dB);
quarantineDecoder = isfinite(decoderWideband) | isfinite(decoderTrial);
if any(quarantineDecoder)
    decoderWideband(quarantineDecoder) = NaN;
    decoderTrial(quarantineDecoder) = NaN;
    T.DecoderTruthProxyWidebandSINR_dB = decoderWideband;
    T.DecoderTruthProxySINR_dB = decoderTrial;
end
if ~ismember("MeasuredTrialSINR_dB", string(T.Properties.VariableNames))
    T.MeasuredTrialSINR_dB = nan(n, 1);
end
if ~ismember("MeasuredWidebandSINR_dB", string(T.Properties.VariableNames))
    T.MeasuredWidebandSINR_dB = double(T.MeasuredTrialSINR_dB);
end
if ~ismember("WidebandSINRSource", string(T.Properties.VariableNames))
    T.WidebandSINRSource = strings(n, 1);
end
if ~ismember("WidebandSINRValueRole", string(T.Properties.VariableNames))
    T.WidebandSINRValueRole = strings(n, 1);
end
if ~ismember("WidebandSINRValueStatus", string(T.Properties.VariableNames))
    T.WidebandSINRValueStatus = strings(n, 1);
end

postEqWideband = double(T.PostEqWidebandSINR_dB);
postEqAlias = double(T.PostEqSINR_dB);
fillPostEq = ~isfinite(postEqWideband) & isfinite(postEqAlias);
if any(fillPostEq)
    postEqWideband(fillPostEq) = postEqAlias(fillPostEq);
    T.PostEqWidebandSINR_dB = postEqWideband;
end
measuredWideband = double(T.MeasuredWidebandSINR_dB);
trialMeasured = double(T.MeasuredTrialSINR_dB);
fillMeasured = ~isfinite(measuredWideband) & isfinite(trialMeasured);
measuredWideband(fillMeasured) = trialMeasured(fillMeasured);
fillMeasured = ~isfinite(measuredWideband) & isfinite(postEqWideband);
measuredWideband(fillMeasured) = postEqWideband(fillMeasured);
T.MeasuredWidebandSINR_dB = measuredWideband;

widebandSource = strtrim(string(T.WidebandSINRSource));
widebandRole = strtrim(string(T.WidebandSINRValueRole));
widebandStatus = strtrim(string(T.WidebandSINRValueStatus));

measuredMask = isfinite(postEqWideband) | isfinite(measuredWideband);
if any(measuredMask)
    widebandSource(measuredMask) = "post_equalization_sinr_from_equalizer_channel_estimate";
    widebandRole(measuredMask) = "measured_post_equalization_scheduling_input";
    widebandStatus(measuredMask) = "available_post_equalization_measurement";
end

receiverOnlyMask = ~measuredMask & isfinite(double(T.ReceiverHestWidebandSINR_dB));
if any(receiverOnlyMask)
    receiverSourcePromoted = strcmp(widebandSource(receiverOnlyMask), "receiver_hest_reference_signal_measurement") | ...
        strlength(widebandSource(receiverOnlyMask)) == 0;
    receiverIdx = find(receiverOnlyMask);
    replaceIdx = receiverIdx(receiverSourcePromoted);
    widebandSource(replaceIdx) = "receiver_hest_diagnostic_not_scheduling_input";
    widebandRole(replaceIdx) = "diagnostic_estimate_not_scheduling_input";
    widebandStatus(replaceIdx) = "available_receiver_hest_diagnostic";
end

blankMask = strlength(widebandStatus) == 0;
widebandStatus(blankMask) = "unavailable";
T.WidebandSINRSource = widebandSource;
T.WidebandSINRValueRole = widebandRole;
T.WidebandSINRValueStatus = widebandStatus;
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
        "EstimatedWidebandSINR_dB", NaN, "SystemLevelWidebandSINR_dB", NaN, "PostEqWidebandSINR_dB", NaN, ...
        "ReceiverHestWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, ...
        "MeasuredWidebandSINR_dB", NaN, "LargeScaleWidebandSINR_dB", NaN, ...
        "SystemLevelSINR_dB", NaN, "SystemLevelSINRSource", "", "SystemLevelSINRValueRole", "", "SystemLevelSINRValueStatus", "", ...
        "PostEqSINR_dB", NaN, "PostEqSINRSource", "", "PostEqSINRValueStatus", "", ...
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
    coverageT.ConfiguredSNRSource = repmat("configured_operating_point_metadata", height(coverageT), 1);
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
if ~ismember("PostEqSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.PostEqSINR_dB = nan(height(coverageT), 1);
end
if ~ismember("PostEqWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.PostEqWidebandSINR_dB = double(coverageT.PostEqSINR_dB);
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
        coverageT.MeasuredWidebandSINR_dB = double(coverageT.PostEqSINR_dB);
    end
end
measuredCoverage = double(coverageT.MeasuredWidebandSINR_dB);
postEqCoverage = double(coverageT.PostEqSINR_dB);
fillCoverageMeasured = ~isfinite(measuredCoverage) & isfinite(postEqCoverage);
if any(fillCoverageMeasured)
    measuredCoverage(fillCoverageMeasured) = postEqCoverage(fillCoverageMeasured);
    coverageT.MeasuredWidebandSINR_dB = measuredCoverage;
end
if ~ismember("EstimatedWidebandSINR_dB", string(coverageT.Properties.VariableNames))
    coverageT.EstimatedWidebandSINR_dB = double(coverageT.PostEqSINR_dB);
else
    estimatedCoverage = double(coverageT.EstimatedWidebandSINR_dB);
    fillCoverageEstimated = ~isfinite(estimatedCoverage) & isfinite(postEqCoverage);
    if any(fillCoverageEstimated)
        estimatedCoverage(fillCoverageEstimated) = postEqCoverage(fillCoverageEstimated);
        coverageT.EstimatedWidebandSINR_dB = estimatedCoverage;
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
    coverageT.MeasuredTrialSINR_dB = nan(height(coverageT), 1);
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
    coverageT.RSRPSource = repmat("large_scale_per_reference_re_power", height(coverageT), 1);
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
postEqWideband = double(coverageT.PostEqWidebandSINR_dB);
measuredWideband = double(coverageT.MeasuredWidebandSINR_dB);
systemWideband = double(coverageT.SystemLevelWidebandSINR_dB);
largeScaleWideband = double(coverageT.LargeScaleWidebandSINR_dB);
receiverWideband = double(coverageT.ReceiverHestWidebandSINR_dB);
measuredWidebandMask = isfinite(postEqWideband) | isfinite(measuredWideband);
systemWidebandMask = ~measuredWidebandMask & isfinite(systemWideband);
largeScaleWidebandMask = ~measuredWidebandMask & ~systemWidebandMask & isfinite(largeScaleWideband);
receiverDiagnosticMask = ~measuredWidebandMask & ~systemWidebandMask & ~largeScaleWidebandMask & isfinite(receiverWideband);
widebandRole(strlength(widebandRole) == 0 & measuredWidebandMask) = "measured_post_equalization_scheduling_input";
widebandRole(strlength(widebandRole) == 0 & systemWidebandMask) = "runtime_state_derived";
widebandRole(strlength(widebandRole) == 0 & largeScaleWidebandMask) = "derived_preview";
widebandRole(strlength(widebandRole) == 0 & receiverDiagnosticMask) = "diagnostic_estimate_not_scheduling_input";
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
fillMask = blankOrUnavailableSource & measuredWidebandMask;
widebandSource(fillMask) = "post_equalization_sinr_from_equalizer_channel_estimate";
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & systemWidebandMask & strlength(systemSource) > 0;
widebandSource(fillMask) = systemSource(fillMask);
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & largeScaleWidebandMask & strlength(largeScaleSource) > 0;
widebandSource(fillMask) = largeScaleSource(fillMask);
blankOrUnavailableSource = strlength(widebandSource) == 0 | contains(lower(widebandSource), "unavailable");
fillMask = blankOrUnavailableSource & receiverDiagnosticMask & strlength(receiverSource) > 0;
widebandSource(fillMask) = "receiver_hest_diagnostic_not_scheduling_input";
coverageT.WidebandSINRSource = widebandSource;
widebandStatus = strtrim(string(coverageT.WidebandSINRValueStatus));
widebandStatus(strlength(widebandStatus) == 0 & measuredWidebandMask) = "available_post_equalization_measurement";
widebandStatus(strlength(widebandStatus) == 0 & systemWidebandMask) = "available_system_level_estimate";
widebandStatus(strlength(widebandStatus) == 0 & largeScaleWidebandMask) = "available_large_scale_preview";
widebandStatus(strlength(widebandStatus) == 0 & receiverDiagnosticMask) = "available_receiver_hest_diagnostic";
widebandStatus(strlength(widebandStatus) == 0) = "unavailable";
coverageT.WidebandSINRValueStatus = widebandStatus;
if ~ismember("InterferenceMode", string(coverageT.Properties.VariableNames))
    coverageT.InterferenceMode = repmat("unpublished_mode_label_missing", height(coverageT), 1);
end
if ~ismember("ServingRSRPSource", string(coverageT.Properties.VariableNames))
    coverageT.ServingRSRPSource = repmat("large_scale_per_reference_re_power", height(coverageT), 1);
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

function summaryT = localBuildHARQObservationSummaryFromTimeline(timelineT)
if ~(istable(timelineT) && ~isempty(timelineT) && ismember("Direction", string(timelineT.Properties.VariableNames)))
    summaryT = localEmptyHARQObservationSummaryTable();
    return;
end
rows = repmat(struct( ...
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
dirs = unique(string(timelineT.Direction), "stable");
for i = 1:numel(dirs)
    mask = string(timelineT.Direction) == dirs(i);
    slice = timelineT(mask, :);
    if isempty(slice)
        continue;
    end
    ackCol = localTimelineAckColumn(slice);
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "Direction", string(dirs(i)), ...
        "TraceSource", localDominantTimelineTraceSource(slice), ...
        "SNR_dB", localMeanOptionalColumn(slice, "SNR_dB"), ...
        "FramesObserved", double(height(slice)), ...
        "CRCPassRate", mean(ackCol, "omitnan"), ...
        "CRCFailRate", mean(1 - ackCol, "omitnan"), ...
        "CrashRate", localMeanOptionalColumn(slice, "Crash"), ...
        "MeanGoodput_Mbps", localMeanOptionalColumn(slice, "Goodput_Mbps"), ...
        "MeanReceiverHestSINR_dB", localMeanOptionalColumn(slice, "ReceiverHestSINR_dB"), ...
        "MeanDecoderTruthProxySINR_dB", localMeanOptionalColumn(slice, "DecoderTruthProxySINR_dB"), ...
        "MeanMeasuredSINR_dB", localMeanOptionalColumn(slice, "MeasuredSINR_dB"), ...
        "MeanWidebandCQI", localMeanOptionalColumn(slice, "WidebandCQI"), ...
        "MeanCQIDerivedMCS", localMeanOptionalColumn(slice, "CQIDerivedMCS"), ...
        "Notes", "Live HARQ observation summary derived from the provided runtime HARQ timeline.");
end
if isempty(rows)
    summaryT = localEmptyHARQObservationSummaryTable();
else
    summaryT = struct2table(rows);
end
end

function source = localDominantTimelineTraceSource(T)
source = "runtime_harq_timeline";
if ~(istable(T) && ismember("TraceSource", string(T.Properties.VariableNames)))
    return;
end
vals = string(T.TraceSource);
vals = strtrim(vals(:));
vals = vals(strlength(vals) > 0);
if isempty(vals)
    return;
end
[uVals, ~, idx] = unique(vals, "stable");
counts = accumarray(idx, 1);
[~, bestIdx] = max(counts);
source = uVals(bestIdx);
end

function ackCol = localTimelineAckColumn(T)
ackCol = localOptionalNumericColumn(T, "CombinedDecodeOK", NaN);
if any(isfinite(ackCol))
    return;
end
ackCol = localOptionalNumericColumn(T, "CRCPass", NaN);
end

function value = localMeanOptionalColumn(T, name)
vals = localOptionalNumericColumn(T, name, NaN);
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = mean(vals, "omitnan");
end
end

function T = localDirectionLinkAdaptationRows(sourceT, direction, traceSource, cfg)
if nargin < 4
    cfg = struct();
end
sourceT = localEnsureLinkAdaptationSourceVars(sourceT, cfg, direction);
if ismember("IsWarmupFrame", string(sourceT.Properties.VariableNames))
    warmMask = logical(sourceT.IsWarmupFrame);
    if any(~warmMask)
        sourceT = sourceT(~warmMask, :);
    end
end
vars = {'Direction','TraceSource','Slot','Frame','UEIndex','RNTI','ServingCell', ...
    'ConfiguredSNR_dB','AppliedAWGNSNR_dB','PostEqSINR_dB','MeasuredTrialSINR_dB','MeasuredWidebandSINR_dB', ...
    'EstimatedWidebandSINR_dB','LargeScaleSINR_dB','LargeScaleWidebandSINR_dB', ...
    'ReceiverHestSINR_dB','DecoderTruthProxySINR_dB','WidebandCQI','CQIValueSource','CQIValueStatus','CQIDerivedMCS', ...
    'CQIDerivedModulation','CQIDerivedTargetCodeRate','MCSIndex','Modulation','TargetCodeRate', ...
    'PMI','CRI','RankIndicator','ValueRole','ValueSource','ValueStatus','Notes'};
rows = cell(height(sourceT), numel(vars));
for i = 1:height(sourceT)
    row = sourceT(i, :);
    rows{i,1} = string(direction);
    rows{i,2} = string(traceSource);
    rows{i,3} = double(localLastValue(row, "Slot"));
    rows{i,4} = double(localLastValue(row, "Frame"));
    rows{i,5} = double(localLastValue(row, "UEIndex"));
    rows{i,6} = double(localLastValue(row, "RNTI"));
    rows{i,7} = double(localLastValue(row, "BaseStationID", localLastValue(row, "ServingCell")));
    rows{i,8} = double(localLastValue(row, "ConfiguredSNR_dB"));
    rows{i,9} = double(localLastValue(row, "AppliedAWGNSNR_dB"));
    postEq = localLastValue(row, "PostEqSINR_dB");
    estimated = double(localLastValue(row, "EstimatedWidebandSINR_dB", postEq));
    if isfinite(double(postEq))
        estimated = double(postEq);
    end
    rows{i,10} = double(postEq);
    rows{i,11} = double(localLastValue(row, "MeasuredTrialSINR_dB", postEq));
    rows{i,12} = double(localLastValue(row, "MeasuredWidebandSINR_dB", localLastValue(row, "MeasuredTrialSINR_dB", postEq)));
    rows{i,13} = double(estimated);
    rows{i,14} = double(localLastValue(row, "LargeScaleSINR_dB"));
    rows{i,15} = double(localLastValue(row, "LargeScaleWidebandSINR_dB", localLastValue(row, "LargeScaleSINR_dB")));
    rows{i,16} = double(localLastValue(row, "ReceiverHestSINR_dB"));
    rows{i,17} = double(localLastValue(row, "DecoderTruthProxySINR_dB"));
    rows{i,18} = double(localLastValue(row, "WidebandCQI"));
    rows{i,19} = string(localLastValue(row, "CQIValueSource", ""));
    rows{i,20} = string(localLastValue(row, "CQIValueStatus", ""));
    rows{i,21} = double(localLastValue(row, "CQIDerivedMCS"));
    rows{i,22} = string(localLastValue(row, "CQIDerivedModulation"));
    rows{i,23} = double(localLastValue(row, "CQIDerivedTargetCodeRate"));
    rows{i,24} = double(localLastValue(row, "MCSIndex", localLastValue(row, "CQIDerivedMCS")));
    rows{i,25} = string(localLastValue(row, "Modulation", localLastValue(row, "CQIDerivedModulation")));
    rows{i,26} = double(localLastValue(row, "TargetCodeRate", localLastValue(row, "CQIDerivedTargetCodeRate")));
    rows{i,27} = double(localLastValue(row, "PMI"));
    rows{i,28} = double(localLastValue(row, "CRI"));
    rows{i,29} = double(localLastValue(row, "RankIndicator", localLastValue(row, "RI")));
    rows{i,30} = string(localLastValue(row, "SINRValueRole", "post_equalization_sinr_required"));
    rows{i,31} = string(localLastValue(row, "SINRSource", "post_equalization_sinr_from_equalizer_channel_estimate"));
    rows{i,32} = string(localLastValue(row, "Status", ""));
    rows{i,33} = string(localLastValue(row, "Notes", ""));
end
T = cell2table(rows, 'VariableNames', vars);
numericVars = ["Slot","Frame","UEIndex","RNTI","ServingCell","ConfiguredSNR_dB","AppliedAWGNSNR_dB", ...
    "PostEqSINR_dB","MeasuredTrialSINR_dB","MeasuredWidebandSINR_dB","EstimatedWidebandSINR_dB","LargeScaleSINR_dB", ...
    "LargeScaleWidebandSINR_dB","ReceiverHestSINR_dB","DecoderTruthProxySINR_dB","WidebandCQI", ...
    "CQIDerivedMCS","CQIDerivedTargetCodeRate","MCSIndex","TargetCodeRate","PMI","CRI","RankIndicator"];
for i = 1:numel(numericVars)
    name = char(numericVars(i));
    T.(name) = double(T.(name));
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

function T = localEnsureLinkAdaptationSourceVars(T, cfg, direction)
if nargin < 2
    cfg = struct();
end
if nargin < 3 || strlength(string(direction)) == 0
    direction = "DL";
end
vars = string(T.Properties.VariableNames);
if ~ismember("PostEqSINR_dB", vars)
    T.PostEqSINR_dB = nan(height(T), 1);
end
postEq = double(T.PostEqSINR_dB);
if ~ismember("MeasuredWidebandSINR_dB", string(T.Properties.VariableNames))
    if ismember("MeasuredTrialSINR_dB", string(T.Properties.VariableNames))
        T.MeasuredWidebandSINR_dB = double(T.MeasuredTrialSINR_dB);
    else
        T.MeasuredWidebandSINR_dB = postEq;
    end
end
measuredWideband = double(T.MeasuredWidebandSINR_dB);
fillMeasured = ~isfinite(measuredWideband) & isfinite(postEq);
if any(fillMeasured)
    measuredWideband(fillMeasured) = postEq(fillMeasured);
    T.MeasuredWidebandSINR_dB = measuredWideband;
end
if ~ismember("EstimatedWidebandSINR_dB", string(T.Properties.VariableNames))
    T.EstimatedWidebandSINR_dB = postEq;
else
    estimatedWideband = double(T.EstimatedWidebandSINR_dB);
    fillEstimated = ~isfinite(estimatedWideband) & isfinite(postEq);
    if any(fillEstimated)
        estimatedWideband(fillEstimated) = postEq(fillEstimated);
        T.EstimatedWidebandSINR_dB = estimatedWideband;
    end
end
if ~ismember("LargeScaleWidebandSINR_dB", string(T.Properties.VariableNames)) && ismember("LargeScaleSINR_dB", string(T.Properties.VariableNames))
    T.LargeScaleWidebandSINR_dB = double(T.LargeScaleSINR_dB);
end
if ~ismember("ConfiguredSNR_dB", string(T.Properties.VariableNames)) && ismember("SNR_dB", string(T.Properties.VariableNames))
    T.ConfiguredSNR_dB = double(T.SNR_dB);
end
if ~ismember("ServingCell", string(T.Properties.VariableNames)) && ismember("BaseStationID", string(T.Properties.VariableNames))
    T.ServingCell = double(T.BaseStationID);
end
T = localBackfillWidebandCQIFromMeasuredEvidence(T, cfg, direction);
T = localBackfillCQIDerivedAMC(T, cfg, direction);
names = string(T.Properties.VariableNames);
if ismember("Direction", names)
    ulMask = upper(string(T.Direction)) == "UL";
    precodingMode = lower(string(localOptionalTextColumn(T, "PrecodingMode", "")));
    appliedSource = lower(string(localOptionalTextColumn(T, "AppliedPrecoderSource", localOptionalTextColumn(T, "PrecoderSource", ""))));
    nonCodebookMask = ulMask & ( ...
        precodingMode == "direct_mapping_no_explicit_beam_weights" | ...
        precodingMode == "transform_precoding" | ...
        appliedSource == "ul_direct_mapping_no_explicit_beam_weights" | ...
        appliedSource == "ul_pusch_transform_precoding");
    for field = ["PMI", "CRI", "ConfiguredCRI"]
        if ismember(field, names)
            T.(char(field))(nonCodebookMask) = NaN;
        end
    end
    for field = ["PMIType", "PMICodebookMode"]
        if ismember(field, names)
            vals = string(T.(char(field)));
            vals(nonCodebookMask) = "";
            T.(char(field)) = vals;
        end
    end
end
end

function T = localBackfillWidebandCQIFromMeasuredEvidence(T, cfg, direction)
n = height(T);
vars = string(T.Properties.VariableNames);
if ~ismember("WidebandCQI", vars)
    T.WidebandCQI = nan(n, 1);
    vars = string(T.Properties.VariableNames);
end
if ~ismember("CQIValueSource", vars)
    T.CQIValueSource = repmat("", n, 1);
    vars = string(T.Properties.VariableNames);
end
if ~ismember("CQIValueStatus", vars)
    T.CQIValueStatus = repmat("", n, 1);
    vars = string(T.Properties.VariableNames);
end

widebandCQI = localOptionalNumericColumn(T, "WidebandCQI", NaN);
cqiSource = string(T.CQIValueSource);
cqiStatus = string(T.CQIValueStatus);
if ismember("CQI", vars)
    rawCQI = localOptionalNumericColumn(T, "CQI", NaN);
    fillMask = ~isfinite(widebandCQI) & isfinite(rawCQI);
    if any(fillMask)
        widebandCQI(fillMask) = double(sixgr.util.normalizeReportedCQI(rawCQI(fillMask)));
        cqiSource(fillMask) = "raw_trial_cqi";
        cqiStatus(fillMask) = "reported_by_receiver_path";
    end
end

[sinrEvidence, sinrSource] = localMeasuredCQISINREvidence(T);
fillIdx = find(~isfinite(widebandCQI) & isfinite(sinrEvidence));
for k = 1:numel(fillIdx)
    idx = fillIdx(k);
    feedback = sixgr.link.resolveWidebandCQI( ...
        struct("WidebandSINR_dB", double(sinrEvidence(idx)), ...
        "SINRSource", char(sinrSource(idx)), ...
        "SINRValueRole", "measured_post_equalization_scheduling_input", ...
        "SINRValueStatus", "OK"), cfg, direction);
    widebandCQI(idx) = double(sixgr.util.normalizeReportedCQI( ...
        sixgr.util.structGet(feedback, "WidebandCQI", NaN)));
    cqiSource(idx) = "derived_from_" + sinrSource(idx);
    cqiStatus(idx) = "legacy_row_backfill_from_measured_receiver_evidence";
end

T.WidebandCQI = widebandCQI;
T.CQIValueSource = cqiSource;
T.CQIValueStatus = cqiStatus;
end

function [sinrEvidence, sinrSource] = localMeasuredCQISINREvidence(T)
n = height(T);
sinrEvidence = nan(n, 1);
sinrSource = repmat("", n, 1);
evidenceFields = [ ...
    "PostEqSINR_dB", ...
    "MeasuredWidebandSINR_dB", ...
    "MeasuredTrialSINR_dB", ...
    "SINR_dB"];
for i = 1:numel(evidenceFields)
    fieldName = evidenceFields(i);
    if ~ismember(fieldName, string(T.Properties.VariableNames))
        continue;
    end
    candidate = localOptionalNumericColumn(T, fieldName, NaN);
    mask = ~isfinite(sinrEvidence) & isfinite(candidate);
    if any(mask)
        sinrEvidence(mask) = candidate(mask);
        sinrSource(mask) = fieldName;
    end
end
end

function T = localBackfillCQIDerivedAMC(T, cfg, direction)
n = height(T);
vars = string(T.Properties.VariableNames);
if ~ismember("CQIDerivedMCS", vars)
    T.CQIDerivedMCS = nan(n, 1);
    vars = string(T.Properties.VariableNames);
end
if ~ismember("CQIDerivedModulation", vars)
    T.CQIDerivedModulation = repmat("", n, 1);
    vars = string(T.Properties.VariableNames);
end
if ~ismember("CQIDerivedTargetCodeRate", vars)
    T.CQIDerivedTargetCodeRate = nan(n, 1);
end
cqi = localOptionalNumericColumn(T, "WidebandCQI", NaN);
mcs = localOptionalNumericColumn(T, "CQIDerivedMCS", NaN);
modulation = string(T.CQIDerivedModulation);
targetCodeRate = localOptionalNumericColumn(T, "CQIDerivedTargetCodeRate", NaN);
idxList = find(isfinite(cqi) & ( ...
    ~isfinite(mcs) | strlength(strtrim(modulation)) == 0 | ~isfinite(targetCodeRate)));
for k = 1:numel(idxList)
    idx = idxList(k);
    [modStr, tcr, mcsIdx] = sixgr.link.amcFromCQI(cqi(idx), "", NaN, cfg, direction);
    if ~isfinite(mcs(idx)) && isfinite(mcsIdx)
        mcs(idx) = double(mcsIdx);
    end
    if strlength(strtrim(modulation(idx))) == 0
        modulation(idx) = string(modStr);
    end
    if ~isfinite(targetCodeRate(idx)) && isfinite(tcr)
        targetCodeRate(idx) = double(tcr);
    end
end
T.CQIDerivedMCS = mcs;
T.CQIDerivedModulation = modulation;
T.CQIDerivedTargetCodeRate = targetCodeRate;
end

function col = localOptionalNumericColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(char(name));
    if isnumeric(raw) || islogical(raw)
        col = double(raw);
    else
        col = str2double(string(raw));
    end
else
    col = repmat(double(defaultValue), height(T), 1);
end
end

function col = localOptionalTextColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    col = string(T.(char(name)));
else
    col = repmat(string(defaultValue), height(T), 1);
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
axis = localMeasuredQualityAxis(sourceT);
snrList = unique(axis.Bin_dB, "stable");
rows = repmat(struct("Direction","", "TraceSource","", "SNR_dB", NaN, "QualityAxis", "", "QualityValueRole", "", "QualitySource", "", ...
    "Metric", "", "MeanValue", NaN, "P05Value", NaN, "P95Value", NaN, "SampleCount", NaN), 0, 1);
for s = 1:numel(snrList)
    mask = abs(axis.Bin_dB - snrList(s)) < 1e-9;
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
            "QualityAxis", string(axis.AxisName), ...
            "QualityValueRole", string(axis.ValueRole), ...
            "QualitySource", string(axis.Source), ...
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

function axis = localMeasuredQualityAxis(T)
n = height(T);
axisName = "unavailable_measured_quality";
valueRole = "measured_receiver_quality_unavailable";
source = "";
values = nan(n, 1);
preferred = [ ...
    "PostEqSINR_dB", ...
    "MeasuredWidebandSINR_dB", ...
    "MeasuredTrialSINR_dB", ...
    "SINR_dB"];
roles = [ ...
    "measured_post_equalization_scheduling_input", ...
    "measured_wideband_sinr", ...
    "measured_post_equalization_trial_sinr", ...
    "measured_post_equalization_runtime_sinr"];
vars = string(T.Properties.VariableNames);
for i = 1:numel(preferred)
    name = preferred(i);
    if ~ismember(name, vars)
        continue;
    end
    candidate = double(T.(char(name)));
    if any(isfinite(candidate))
        values = candidate;
        axisName = name;
        valueRole = roles(i);
        source = name;
        break;
    end
end
if all(~isfinite(values))
    values = nan(n, 1);
end
% Use 1 dB bins so single-SNR scenario runs still produce a measured-quality
% distribution without pretending they are configured SNR sweep campaigns.
binValues = nan(n, 1);
finiteMask = isfinite(values);
binValues(finiteMask) = round(values(finiteMask));
axis = struct("Bin_dB", binValues, "AxisName", axisName, "ValueRole", valueRole, "Source", source);
end

function T = localEmptySummaryTable()
T = table( ...
    strings(0,1), strings(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Direction','TraceSource','SNR_dB','QualityAxis','QualityValueRole','QualitySource','Metric','MeanValue','P05Value','P95Value','SampleCount'});
end

function T = localCombineDirectionalTrials(dlT, ulT)
parts = {dlT, ulT};
parts = parts(cellfun(@(x) istable(x) && ~isempty(x), parts));
if isempty(parts)
    T = table();
elseif numel(parts) == 1
    T = parts{1};
else
    % DL and UL truth tables can legitimately diverge in optional telemetry
    % columns late in a run. For live-derived evidence tables we need a
    % union-aligned concat, not a hard failure after the waveform run has
    % already completed successfully.
    allVars = strings(1, 0);
    for i = 1:numel(parts)
        partVars = string(parts{i}.Properties.VariableNames);
        allVars = [allVars, setdiff(partVars, allVars, "stable")]; %#ok<AGROW>
    end
    for vi = 1:numel(allVars)
        varName = allVars(vi);
        prototype = localFirstDirectionalPrototype(parts, varName);
        for pi = 1:numel(parts)
            partVars = string(parts{pi}.Properties.VariableNames);
            if ismember(varName, partVars)
                parts{pi}.(char(varName)) = localCoerceDirectionalColumnForCombine(parts{pi}.(char(varName)), prototype, height(parts{pi}));
            else
                parts{pi}.(char(varName)) = localDirectionalDefaultColumnForCombine(prototype, height(parts{pi}));
            end
        end
    end
    for pi = 1:numel(parts)
        parts{pi} = parts{pi}(:, cellstr(allVars));
    end
    T = vertcat(parts{:});
end
end

function prototype = localFirstDirectionalPrototype(parts, varName)
prototype = [];
for i = 1:numel(parts)
    vars = string(parts{i}.Properties.VariableNames);
    if ismember(varName, vars)
        prototype = parts{i}.(char(varName));
        return;
    end
end
end

function col = localCoerceDirectionalColumnForCombine(col, prototype, nRows)
if nargin < 3
    nRows = size(col, 1);
end
if isdatetime(prototype)
    if ~isdatetime(col)
        col = localDirectionalDefaultColumnForCombine(prototype, nRows);
    end
    return;
end
if isduration(prototype)
    if ~isduration(col)
        col = localDirectionalDefaultColumnForCombine(prototype, nRows);
    end
    return;
end
if isnumeric(prototype) || islogical(prototype)
    if isnumeric(col) || islogical(col)
        col = double(col);
    else
        col = str2double(localDirectionalStringifyColumn(col));
    end
    return;
end
col = localDirectionalStringifyColumn(col);
end

function col = localDirectionalDefaultColumnForCombine(prototype, nRows)
if nargin < 2
    nRows = 0;
end
if isdatetime(prototype)
    dims = size(prototype);
    dims(1) = nRows;
    col = NaT(dims);
    return;
end
if isduration(prototype)
    dims = size(prototype);
    dims(1) = nRows;
    col = seconds(nan(dims));
    return;
end
if isnumeric(prototype) || islogical(prototype) || isempty(prototype)
    dims = size(prototype);
    if isempty(dims)
        dims = [nRows, 1];
    else
        dims(1) = nRows;
    end
    if numel(dims) == 1
        dims = [dims, 1];
    end
    col = nan(dims);
    return;
end
col = strings(nRows, 1);
end

function col = localDirectionalStringifyColumn(col)
if isstring(col)
    return;
end
if iscategorical(col)
    col = string(col);
    return;
end
if ischar(col)
    col = string(cellstr(col));
    return;
end
if iscell(col)
    nRows = size(col, 1);
    out = strings(nRows, 1);
    for i = 1:nRows
        out(i) = localDirectionalScalarToString(col{i});
    end
    col = out;
    return;
end
if isnumeric(col) || islogical(col)
    col = string(col);
    return;
end
try
    col = string(col);
catch
    col = strings(size(col, 1), 1);
end
end

function token = localDirectionalScalarToString(value)
if isstring(value)
    if isscalar(value)
        token = value;
    else
        token = strjoin(value(:).', "|");
    end
    return;
end
if ischar(value)
    token = string(value);
    return;
end
if isnumeric(value) || islogical(value)
    if isempty(value)
        token = "";
    elseif isscalar(value)
        token = string(value);
    else
        token = string(mat2str(value));
    end
    return;
end
if iscategorical(value)
    token = string(value);
    return;
end
try
    token = string(value);
catch
    token = "";
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

function value = localMeanFirstExisting(T, names, mask)
if nargin < 3
    mask = [];
end
value = NaN;
names = string(names);
for i = 1:numel(names)
    candidate = localMean(T, names(i), mask);
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
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
    "DL_HARQFailureRate", NaN, ...
    "UL_HARQFailureRate", NaN, ...
    "DL_HARQObservationCount", NaN, ...
    "UL_HARQObservationCount", NaN, ...
    "HARQFailureRate", NaN, ...
    "HARQObservationCount", NaN);
end

function [failureRate, observationCount] = localHARQFailureMetrics(harqTimelineT, ueIdx, direction)
failureRate = NaN;
observationCount = NaN;
if ~(istable(harqTimelineT) && ~isempty(harqTimelineT) && ...
        all(ismember(["UEIndex","CombinedDecodeOK"], string(harqTimelineT.Properties.VariableNames))))
    return;
end
mask = abs(double(harqTimelineT.UEIndex) - double(ueIdx)) < 1e-9;
if ismember("Direction", string(harqTimelineT.Properties.VariableNames)) && strlength(strtrim(string(direction))) > 0
    mask = mask & upper(strtrim(string(harqTimelineT.Direction))) == upper(strtrim(string(direction)));
end
if ~any(mask)
    return;
end
vals = double(harqTimelineT.CombinedDecodeOK(mask));
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
observationCount = double(numel(vals));
failureRate = mean(1 - vals, "omitnan");
end

function [failureRate, observationCount] = localCombineDirectionalHARQFailureMetrics(dlRate, dlCount, ulRate, ulCount)
failureRate = NaN;
observationCount = NaN;
counts = [double(dlCount) double(ulCount)];
rates = [double(dlRate) double(ulRate)];
valid = isfinite(counts) & counts > 0 & isfinite(rates);
if ~any(valid)
    return;
end
observationCount = sum(counts(valid), "omitnan");
failureRate = sum(rates(valid) .* counts(valid), "omitnan") / max(observationCount, 1);
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
