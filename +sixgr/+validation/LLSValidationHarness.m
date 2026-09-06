function out = LLSValidationHarness(runFolder, scfg, cfg, varargin)
%LLSVALIDATIONHARNESS Build Actual-LLS implementation proof artifacts.

p = inputParser;
p.addParameter("WriteArtifacts", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("RuntimeSummary", struct(), @isstruct);
p.addParameter("ScenarioStatus", struct(), @isstruct);
p.parse(varargin{:});
opt = p.Results;

ctx = localBuildContext(runFolder, scfg, cfg, opt.RuntimeSummary, opt.ScenarioStatus);
registry = localBuildBlockRegistry(ctx);
comparisonT = localBuildDUTReferenceComparison(ctx, registry);
invariantT = localBuildInvariantChecks(ctx);
coverageT = localBuildFunctionCoverage(ctx, registry);
evidenceT = localBuildRealPHYPathEvidence(ctx, registry);
detectorT = localBuildOracleProxyFallbackDetector(ctx, registry, evidenceT, coverageT);
plausibilityT = localBuildGeneratedValuePlausibilityAudit(invariantT);
matrixT = localBuildValidationMatrix(ctx, registry, comparisonT, invariantT, coverageT, evidenceT, detectorT);
phyOutcomeT = localBuildPHYOutcomeSummary(ctx, matrixT);
linkPerfT = localBuildLinkPerformanceSummary(ctx, matrixT);
blockCorrectnessT = localBuildBlockCorrectnessSummary(ctx, matrixT, comparisonT);
refSummaryT = localBuildReferenceComparisonSummary(ctx, comparisonT);
coverageSummaryT = localBuildCoverageSummary(ctx, coverageT, matrixT);
topFindingsT = localBuildTopNumericalFindings(ctx, invariantT, linkPerfT);
summary = localBuildSummary(ctx, matrixT, comparisonT, invariantT, coverageT, detectorT);
noBypassGate = localBuildNoBypassGate(matrixT, detectorT);

out = struct();
out.Context = ctx;
out.Registry = registry;
out.DUTReferenceComparison = comparisonT;
out.NumericalSanityChecks = invariantT;
out.PHYValueInvariantChecks = invariantT;
out.RuntimeFunctionCoverage = coverageT;
out.RealPHYPathEvidence = evidenceT;
out.OracleProxyFallbackDetector = detectorT;
out.GeneratedValuePlausibilityAudit = plausibilityT;
out.ValidationMatrix = matrixT;
out.PHYOutcomeSummary = phyOutcomeT;
out.LinkPerformanceSummary = linkPerfT;
out.BlockCorrectnessSummary = blockCorrectnessT;
out.ReferenceComparisonSummary = refSummaryT;
out.RealImplementationCoverageSummary = coverageSummaryT;
out.TopNumericalFindings = topFindingsT;
out.Summary = summary;
out.NoBypassGate = noBypassGate;
out.ReportArtifacts = struct();

if logical(opt.WriteArtifacts)
    out = localWriteArtifacts(out);
end
end

function ctx = localBuildContext(runFolder, scfg, cfg, runtimeSummary, scenarioStatus)
layout = sixgr.report.resultLayout(runFolder);
ctx = struct();
ctx.RunFolder = string(runFolder);
ctx.Layout = layout;
ctx.ScenarioConfig = scfg;
ctx.InternalConfig = cfg;
ctx.RuntimeSummary = runtimeSummary;
ctx.ScenarioStatus = scenarioStatus;
ctx.ScenarioID = localScenarioText(scfg, cfg, "meta.scenario_id", localScenarioText(scfg, cfg, "scenario_id", "unknown_scenario"));
ctx.RunId = localComposeRunId(runFolder, ctx.ScenarioID);
ctx.CenterFrequencyHz = localScenarioNumber(scfg, cfg, ["frequency.center_frequency_hz", "channel.fc_Hz", "frequency.fc_hz"], NaN);
ctx.BandwidthHz = localScenarioNumber(scfg, cfg, ["frequency.bandwidth_hz", "global_radio_scope.channel_bandwidth_hz", "channel.bandwidth_Hz"], NaN);
ctx.SampleRateHz = localScenarioNumber(scfg, cfg, ["waveform.sample_rate_hz", "global_radio_scope.sample_rate_hz"], NaN);
ctx.SCSkHz = localScenarioNumber(scfg, cfg, ["frame.scs_khz", "phy.numerology.scs_kHz"], NaN);
ctx.GridRB = localScenarioNumber(scfg, cfg, ["frequency.n_size_grid", "resource_grid.num_rbs", "phy.carrier.NSizeGrid"], NaN);
ctx.NumLayers = localScenarioNumber(scfg, cfg, ["mimo.n_layers", "phy.mimo.nLayers"], NaN);
ctx.NumTxAnt = localScenarioNumber(scfg, cfg, ["mimo.n_tx_ant", "phy.mimo.nTxAnt"], NaN);
ctx.NumRxAnt = localScenarioNumber(scfg, cfg, ["mimo.n_rx_ant", "phy.mimo.nRxAnt"], NaN);
ctx.ConfiguredSpeedKmh = localScenarioNumber(scfg, cfg, ["channels.mobility_kmph", "mobility.ue_speed_kmh", "scenario.mobility.speed_kmh"], NaN);
ctx.Tables = struct();
ctx.Paths = struct();

tableSpecs = { ...
    "ScenarioSummary", fullfile(layout.ReportCSVDir, "scenario_summary.csv"); ...
    "RuntimeOperatingMode", fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"); ...
    "ResultStatusSummary", fullfile(layout.ReportCSVDir, "result_status_summary.csv"); ...
    "TruthContractSummary", fullfile(layout.ReportCSVDir, "truth_contract_summary.csv"); ...
    "TruthContractFailures", fullfile(layout.ReportCSVDir, "truth_contract_failures.csv"); ...
    "RuntimeFunctionProfile", fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"); ...
    "RuntimeFunctionCallEdges", fullfile(layout.ReportCSVDir, "runtime_function_call_edges.csv"); ...
    "TimeProfileCalls", fullfile(layout.ReportCSVDir, "time_profile_calls.csv"); ...
    "TimeProfileCoverage", fullfile(layout.ReportCSVDir, "time_profile_coverage.csv"); ...
    "LiveChannelState", fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"); ...
    "LiveStageTrace", fullfile(layout.ReportCSVDir, "live_tx_rx_stage_trace.csv"); ...
    "LiveModulationTrace", fullfile(layout.ReportCSVDir, "live_modulation_demodulation_trace.csv"); ...
    "LiveChannelEstimation", fullfile(layout.ReportCSVDir, "live_channel_estimation_tti.csv"); ...
    "LiveMobility", fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv"); ...
    "LiveMeasurements", fullfile(layout.ReportCSVDir, "live_cell_measurement_trace.csv"); ...
    "LiveUserPerformance", fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"); ...
    "LiveErrorRate", fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv"); ...
    "AntennaRuntimeEvidence", fullfile(layout.ReportCSVDir, "antenna_runtime_evidence.csv"); ...
    "RankLayerTrials", fullfile(layout.BeamformingCSVDir, "rank_layer_trials.csv"); ...
    "BeamManagement", fullfile(layout.BeamformingCSVDir, "probe_beam_management.csv"); ...
    "HARQTimeline", fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"); ...
    "HARQSummary", fullfile(layout.HARQCSVDir, "live_harq_observation_summary.csv"); ...
    "HARQProcessTimeline", fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"); ...
    "DLTrials", fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"); ...
    "ULTrials", fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"); ...
    "PBCHTrials", fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"); ...
    "PDCCHTrials", fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"); ...
    "PUCCHTrials", fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"); ...
    "PRACHTrialsAir", fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"); ...
    "SRSTrialsAir", fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"); ...
    "TRSTrialsAir", fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"); ...
    "CellSearchTrials", fullfile(layout.ControlCSVDir, "cell_search_trials.csv"); ...
    "PBCHRecoveryTrials", fullfile(layout.ControlCSVDir, "pbch_recovery_trials.csv"); ...
    "InitialAccessLifecycle", fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"); ...
    "PDCCHTrialsStrict", fullfile(layout.ControlCSVDir, "pdcch_trials.csv"); ...
    "PDCCHWrongRNTI", fullfile(layout.ControlCSVDir, "pdcch_wrong_rnti_trials.csv"); ...
    "PDCCHNoSignal", fullfile(layout.ControlCSVDir, "pdcch_no_signal_trials.csv"); ...
    "PDCCHCorruption", fullfile(layout.ControlCSVDir, "pdcch_corruption_trials.csv"); ...
    "PRACHTrialsStrict", fullfile(layout.ControlCSVDir, "prach_trials.csv"); ...
    "PRACHNegative", fullfile(layout.ControlCSVDir, "prach_negative_trials.csv"); ...
    "PRACHFalseAlarm", fullfile(layout.ControlCSVDir, "prach_false_alarm_sweep.csv"); ...
    "PRACHMissedDetection", fullfile(layout.ControlCSVDir, "prach_missed_detection_sweep.csv"); ...
    "SIB1Recovery", fullfile(layout.ControlCSVDir, "sib1_recovery_trials.csv"); ...
    "SRSStrictTrials", fullfile(layout.Root, "reference_signals", "csv", "srs_trials.csv"); ...
    "SRSNegative", fullfile(layout.Root, "reference_signals", "csv", "srs_negative_trials.csv"); ...
    "TRSStrictTrials", fullfile(layout.Root, "reference_signals", "csv", "trs_trials.csv"); ...
    "TRSNegative", fullfile(layout.Root, "reference_signals", "csv", "trs_negative_trials.csv"); ...
    "ChannelRFValidation", fullfile(layout.ReportCSVDir, "channel_rf_configured_applied.csv"); ...
    "ChannelRFNegative", fullfile(layout.ReportCSVDir, "channel_rf_negative_trials.csv") ...
    };

for i = 1:size(tableSpecs, 1)
    key = char(tableSpecs{i, 1});
    pathValue = char(tableSpecs{i, 2});
    ctx.Tables.(key) = localReadOptionalTable(pathValue);
    ctx.Paths.(key) = string(localRelativePath(runFolder, pathValue));
end
end

function registry = localBuildBlockRegistry(ctx)
defs = repmat(localEmptyRegistryRow(), 0, 1);

dlIntent = lower(strtrim(localScenarioText(ctx.ScenarioConfig, ctx.InternalConfig, "simulation.link_direction", "both")));
dlEnabled = localHasRows(ctx.Tables.DLTrials) || any(dlIntent == ["both","dl","downlink"]);
ulEnabled = localHasRows(ctx.Tables.ULTrials) || any(dlIntent == ["both","ul","uplink"]);
pdcchEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["control.pdcch_enabled"], false) || ...
    localHasRows(ctx.Tables.PDCCHTrials) || localHasRows(ctx.Tables.PDCCHTrialsStrict);
prachEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["random_access.enabled"], false) || ...
    localHasRows(ctx.Tables.PRACHTrialsAir) || localHasRows(ctx.Tables.PRACHTrialsStrict);
pucchEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["control.pucch_enabled"], false) || ...
    localHasRows(ctx.Tables.PUCCHTrials);
srsEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["reference_signals.srs_enabled"], false) || ...
    localHasRows(ctx.Tables.SRSTrialsAir) || localHasRows(ctx.Tables.SRSStrictTrials);
trsEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["reference_signals.trs_enabled"], false) || ...
    localHasRows(ctx.Tables.TRSTrialsAir) || localHasRows(ctx.Tables.TRSStrictTrials);
pbchEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["reference_signals.pbch_enabled", "reference_signals.ssb_enabled"], false) || ...
    localHasRows(ctx.Tables.PBCHTrials) || localHasRows(ctx.Tables.PBCHRecoveryTrials);
mobilityEnabled = localHasRows(ctx.Tables.LiveMobility) || localHasRows(ctx.Tables.LiveChannelState) || ...
    isfinite(double(ctx.ConfiguredSpeedKmh)) && double(ctx.ConfiguredSpeedKmh) > 0;
channelRFEnabled = localHasRows(ctx.Tables.LiveChannelState) || localHasRows(ctx.Tables.ChannelRFValidation);
mimoEnabled = localHasRows(ctx.Tables.RankLayerTrials) || localHasRows(ctx.Tables.BeamManagement) || ...
    (isfinite(ctx.NumLayers) && ctx.NumLayers > 1) || (isfinite(ctx.NumTxAnt) && isfinite(ctx.NumRxAnt) && (ctx.NumTxAnt > 1 || ctx.NumRxAnt > 1));
harqEnabled = localScenarioBool(ctx.ScenarioConfig, ctx.InternalConfig, ["harq.enabled"], false) || ...
    localHasRows(ctx.Tables.HARQTimeline) || localHasRows(ctx.Tables.HARQProcessTimeline);
kpiEnabled = dlEnabled || ulEnabled || localHasRows(ctx.Tables.LiveUserPerformance) || localHasRows(ctx.Tables.LiveErrorRate);
sib1Enabled = localHasRows(ctx.Tables.SIB1Recovery);

defs(end+1, 1) = localRegistryRow("MobilityDoppler", "mobility", "3GPP TR 38.901 geometry and Doppler", mobilityEnabled, mobilityEnabled, ...
    ["sixgr.truth.exportLLSLiveMobilityTables"], "reports/csv/runtime_operating_mode.csv", "reports/csv/live_rsrp_serving_trace.csv|reports/csv/live_channel_state_tti.csv", "reports/csv/live_rsrp_serving_trace.csv|reports/csv/live_channel_state_tti.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("ChannelRF", "rf_channel", "3GPP TR 38.901 channel and RF impairment application", channelRFEnabled, channelRFEnabled, ...
    ["sixgr.truth.exportLLSLiveSignalChainTables","sixgr.channel.runStrictChannelRFValidation"], "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv", "reports/csv/live_channel_state_tti.csv", "reports/csv/live_channel_state_tti.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("SSB_PBCH_MIB", "broadcast", "TS 38.211/38.212 SSB/PBCH/MIB", pbchEnabled, pbchEnabled, ...
    ["sixgr.truth.exportControlPlaneTraces"], "control/csv/cell_search_trials.csv|control/csv/pbch_recovery_trials.csv", "air_interface/csv/pbch_trials.csv|control/csv/pbch_recovery_trials.csv", "control/csv/pbch_recovery_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("SIB1", "broadcast", "TS 38.331 SIB1 decode and validation", sib1Enabled, sib1Enabled, ...
    ["sixgr.phy.broadcast.runSIB1StrictMiniAnchor"], "control/csv/pdcch_trials.csv", "control/csv/sib1_recovery_trials.csv", "control/csv/sib1_recovery_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("PRACH", "random_access", "TS 38.211/38.321 PRACH and random access", prachEnabled, prachEnabled, ...
    ["sixgr.phy.ra.runFourStepRA"], "control/csv/prach_trials.csv", "control/csv/prach_trials.csv|control/csv/prach_negative_trials.csv", "control/csv/prach_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("PDCCH", "control", "TS 38.212 DCI/CORESET/search-space processing", pdcchEnabled, pdcchEnabled, ...
    ["sixgr.phy.dl.PDCCH_Tx","sixgr.phy.dl.PDCCH_Rx"], "control/csv/pdcch_trials.csv", "control/csv/pdcch_trials.csv|control/csv/pdcch_wrong_rnti_trials.csv", "control/csv/pdcch_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("PDSCH", "downlink_data", "TS 38.211/38.212 PDSCH and DL-SCH", dlEnabled, dlEnabled, ...
    ["sixgr.phy.dl.PDSCH_Tx","sixgr.phy.dl.PDSCH_Rx"], "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/dl_pdsch_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("PUSCH", "uplink_data", "TS 38.211/38.212 PUSCH and UL-SCH", ulEnabled, ulEnabled, ...
    ["sixgr.phy.ul.PUSCH_Tx","sixgr.phy.ul.PUSCH_Rx"], "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("PUCCH_UCI", "uplink_control", "TS 38.213 PUCCH/UCI feedback", pucchEnabled, pucchEnabled, ...
    ["sixgr.link.runPUCCHWaveformTrial","sixgr.phy.pucch.PUCCHReceiver"], "air_interface/csv/pucch_trials.csv", "air_interface/csv/pucch_trials.csv", "air_interface/csv/pucch_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("SRS", "reference_signal", "TS 38.211 SRS channel sounding", srsEnabled, srsEnabled, ...
    ["sixgr.link.runSRSChannelEstimation","sixgr.phy.srs.estimateULChannelFromSRS"], "reference_signals/csv/srs_trials.csv", "reference_signals/csv/srs_trials.csv|reference_signals/csv/srs_negative_trials.csv", "reference_signals/csv/srs_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("TRS", "reference_signal", "TS 38.211 TRS tracking", trsEnabled, trsEnabled, ...
    ["sixgr.link.runTRSTracking","sixgr.phy.trs.estimateTRSChannel"], "reference_signals/csv/trs_trials.csv", "reference_signals/csv/trs_trials.csv|reference_signals/csv/trs_negative_trials.csv", "reference_signals/csv/trs_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("MIMO", "mimo_beamforming", "TS 38.214 rank/layer/precoder evidence", mimoEnabled, mimoEnabled, ...
    ["sixgr.mimo.executeSpatialComposite", ...
     "sixgr.mimo.resolveRankExecutionPolicy", ...
     "sixgr.phy.dl.resolvePDSCHPrecoding", ...
     "sixgr.pdsch.CodewordLayerMapper", ...
     "sixgr.pdsch.PDSCHPrecoderBundle.apply", ...
     "sixgr.phy.mimo.precoder", ...
     "sixgr.phy.ul.estimateSRSRITPMI"], ...
    "beamforming/csv/rank_layer_trials.csv", "beamforming/csv/rank_layer_trials.csv", "beamforming/csv/rank_layer_trials.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("MAC_HARQ", "mac_harq", "TS 38.321 HARQ timing and process state", harqEnabled, harqEnabled, ...
    ["sixgr.truth.exportLLSHARQDiagnostics"], "harq/csv/live_harq_observation_timeline.csv", "harq/csv/live_harq_observation_timeline.csv", "harq/csv/live_harq_observation_timeline.csv"); %#ok<AGROW>
defs(end+1, 1) = localRegistryRow("KPI", "kpi", "Derived link performance KPIs from raw runtime rows", kpiEnabled, kpiEnabled, ...
    ["sixgr.truth.exportLLSLiveDerivedTables"], "reports/csv/live_error_rate_summary.csv", "reports/csv/live_error_rate_summary.csv|reports/csv/live_user_performance_snapshot.csv", "reports/csv/live_error_rate_summary.csv"); %#ok<AGROW>

registry = struct2table(defs, "AsArray", true);
end

function T = localBuildDUTReferenceComparison(ctx, registry)
rows = repmat(localEmptyComparisonRow(), 0, 1);
configHash = localScalarText(ctx.Tables.ScenarioSummary, "ConfigHash", localScalarText(ctx.Tables.RuntimeOperatingMode, "ConfigHash", ""));

rows = [rows; localMobilityComparisonRows(ctx, configHash)]; %#ok<AGROW>
rows = [rows; localCFOTimingComparisonRows(ctx, configHash)]; %#ok<AGROW>
rows = [rows; localTBSComparisonRows(ctx, "PDSCH", ctx.Tables.DLTrials, configHash)]; %#ok<AGROW>
rows = [rows; localTBSComparisonRows(ctx, "PUSCH", ctx.Tables.ULTrials, configHash)]; %#ok<AGROW>
rows = [rows; localStrictBooleanComparisonRows(ctx, "PDCCH", ctx.Tables.PDCCHWrongRNTI, "wrong_rnti_reject", false, configHash)]; %#ok<AGROW>
rows = [rows; localStrictBooleanComparisonRows(ctx, "PDCCH", ctx.Tables.PDCCHNoSignal, "no_signal_reject", false, configHash)]; %#ok<AGROW>
rows = [rows; localStrictBooleanComparisonRows(ctx, "PRACH", ctx.Tables.PRACHNegative, "negative_trial_expected_fail", false, configHash)]; %#ok<AGROW>
rows = [rows; localStrictBooleanComparisonRows(ctx, "SRS", ctx.Tables.SRSNegative, "negative_trial_expected_fail", false, configHash)]; %#ok<AGROW>
rows = [rows; localStrictBooleanComparisonRows(ctx, "TRS", ctx.Tables.TRSNegative, "negative_trial_expected_fail", false, configHash)]; %#ok<AGROW>
rows = [rows; localPBCHComparisonRows(ctx, configHash)]; %#ok<AGROW>
rows = [rows; localSIB1ComparisonRows(ctx, configHash)]; %#ok<AGROW>

if isempty(rows)
    T = struct2table(repmat(localEmptyComparisonRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end

enabledBlocks = string(registry.BlockId(logical(registry.FeatureEnabled)));
presentBlocks = unique(string(T.BlockId));
missingBlocks = setdiff(enabledBlocks, presentBlocks, "stable");
for i = 1:numel(missingBlocks)
    row = localEmptyComparisonRow();
    row.RunId = ctx.RunId;
    row.BlockId = missingBlocks(i);
    row.Subsystem = localRegistryValue(registry, missingBlocks(i), "Subsystem", "");
    row.ReferenceOutputName = "reference_unavailable";
    row.ComparisonType = "unavailable";
    row.ReferenceSource = "reference_path_unavailable";
    row.Pass = false;
    row.ReferenceAvailable = false;
    row.FailureReason = "reference_path_unavailable";
    T(end+1, :) = struct2table(row, "AsArray", true); %#ok<AGROW>
end
end

function T = localBuildInvariantChecks(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
const = sixgr.validation.GoldenVectorFactory("constants");

rows = [rows; localGridInvariantRows(ctx)]; %#ok<AGROW>
rows = [rows; localMobilityInvariantRows(ctx, const)]; %#ok<AGROW>
rows = [rows; localLLRInvariantRows(ctx, const)]; %#ok<AGROW>
rows = [rows; localSINRInvariantRows(ctx)]; %#ok<AGROW>
rows = [rows; localTimingInvariantRows(ctx, const)]; %#ok<AGROW>
rows = [rows; localCFOInvariantRows(ctx, const)]; %#ok<AGROW>
rows = [rows; localDecoderInvariantRows(ctx)]; %#ok<AGROW>
rows = [rows; localMIMOInvariantRows(ctx)]; %#ok<AGROW>
rows = [rows; localHARQInvariantRows(ctx)]; %#ok<AGROW>
rows = [rows; localReferenceSignalInvariantRows(ctx)]; %#ok<AGROW>

if isempty(rows)
    T = struct2table(repmat(localEmptyInvariantRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildFunctionCoverage(ctx, registry)
rows = repmat(localEmptyCoverageRow(), 0, 1);
defs = table2struct(registry);
for i = 1:numel(defs)
    functionsExpected = string(defs(i).ExpectedFunctions);
    for j = 1:numel(functionsExpected)
        row = localEmptyCoverageRow();
        row.RunId = ctx.RunId;
        row.FunctionName = functionsExpected(j);
        row.FilePath = localExpectedFunctionFile(functionsExpected(j));
        row.Subsystem = string(defs(i).Subsystem);
        row.ExpectedForScenario = logical(defs(i).FeatureEnabled);
        [row.ActuallyCalled, row.CallCount, row.TotalTimeSeconds, row.SelfTimeSeconds] = ...
            localFunctionCallEvidence(ctx, functionsExpected(j), defs(i).BlockId);
        row.InputArtifactSeen = localArtifactsExist(ctx.RunFolder, defs(i).InputArtifact);
        row.OutputArtifactSeen = localArtifactsExist(ctx.RunFolder, defs(i).OutputArtifact);
        row.EvidenceRowsProduced = localBlockEvidenceRowCount(ctx, defs(i).BlockId);
        row.RequiredEvidenceProduced = row.EvidenceRowsProduced > 0 && row.OutputArtifactSeen;
        [row.Bypassed, row.ProxyUsed, row.FallbackUsed, row.Skipped] = ...
            localDetectorFlagsForBlock(ctx, defs(i).BlockId);
        row.ImplementationCoveragePass = ~row.ExpectedForScenario || ...
            (row.ActuallyCalled && row.RequiredEvidenceProduced && ~row.Bypassed && ~row.ProxyUsed && ~row.FallbackUsed && ~row.Skipped);
        row.BlocksResultOk = row.ImplementationCoveragePass;
        if row.ExpectedForScenario && ~row.ImplementationCoveragePass
            row.IssueIdIfFailed = localCoverageIssueId(row);
            row.FailureReason = localCoverageFailureReason(row);
        end
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildRealPHYPathEvidence(ctx, registry)
rows = repmat(localEmptyEvidenceRow(), 0, 1);
defs = table2struct(registry);
evidenceTypes = ["waveform","grid","bit","decoder","channel","timing","frequency"];
for i = 1:numel(defs)
    flags = localEvidenceFlags(ctx, defs(i).BlockId);
    sources = localEvidenceSources(ctx, defs(i).BlockId);
    counts = localEvidenceCounts(ctx, defs(i).BlockId);
    for j = 1:numel(evidenceTypes)
        ev = evidenceTypes(j);
        row = localEmptyEvidenceRow();
        row.RunId = ctx.RunId;
        row.BlockId = string(defs(i).BlockId);
        row.EvidenceType = ev;
        row.EvidencePresent = logical(flags.(char(matlab.lang.makeValidName(ev))));
        row.SourceArtifact = string(sources.(char(matlab.lang.makeValidName(ev))));
        row.EvidenceRows = double(counts.(char(matlab.lang.makeValidName(ev))));
        row.Notes = string(defs(i).OutputArtifact);
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildOracleProxyFallbackDetector(ctx, registry, evidenceT, coverageT)
rows = repmat(localEmptyDetectorRow(), 0, 1);
defs = table2struct(registry);
for i = 1:numel(defs)
    blockId = string(defs(i).BlockId);
    row = localEmptyDetectorRow();
    row.RunId = ctx.RunId;
    row.BlockId = blockId;
    row.OracleUsed = localBlockUsesOracle(ctx, blockId);
    row.ProxyUsed = localBlockUsesProxy(ctx, blockId);
    row.FallbackUsed = localBlockUsesFallback(ctx, blockId);
    row.Skipped = localBlockSkipped(ctx, blockId);
    row.Bypassed = localBlockBypassed(blockId, coverageT, evidenceT, logical(defs(i).FeatureEnabled));
    row.LabelOnlyEvidence = localBlockLabelOnly(ctx, blockId, evidenceT, logical(defs(i).FeatureEnabled));
    row.DetectionSource = string(defs(i).OutputArtifact);
    row.FailureReason = localDetectorFailureReason(row);
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildGeneratedValuePlausibilityAudit(invariantT)
if ~(istable(invariantT) && ~isempty(invariantT))
    T = table();
    return;
end
T = invariantT(:, intersect(["RunId","CheckId","Subsystem","MetricName","ObservedValue","ExpectedMin","ExpectedMax","ExpectedValue","Tolerance","Pass","Severity","FailureReason","RecommendedFix"], string(invariantT.Properties.VariableNames), "stable"));
end

function T = localBuildValidationMatrix(ctx, registry, comparisonT, invariantT, coverageT, evidenceT, detectorT)
rows = repmat(localEmptyMatrixRow(), 0, 1);
defs = table2struct(registry);
for i = 1:numel(defs)
    blockId = string(defs(i).BlockId);
    comp = comparisonT(string(comparisonT.BlockId) == blockId, :);
    inv = invariantT(string(invariantT.Subsystem) == string(defs(i).Subsystem), :);
    cov = coverageT(string(coverageT.Subsystem) == string(defs(i).Subsystem), :);
    det = detectorT(string(detectorT.BlockId) == blockId, :);
    ev = evidenceT(string(evidenceT.BlockId) == blockId, :);

    row = localEmptyMatrixRow();
    row.RunId = ctx.RunId;
    row.ScenarioName = ctx.ScenarioID;
    row.BlockId = blockId;
    row.Subsystem = string(defs(i).Subsystem);
    row.SpecReference = string(defs(i).SpecReference);
    row.FeatureEnabled = logical(defs(i).FeatureEnabled);
    row.MandatoryForScenario = logical(defs(i).MandatoryForScenario);
    row.DUTFunctionExpected = strjoin(cellstr(string(defs(i).ExpectedFunctions)), " | ");
    row.DUTFunctionActuallyCalled = any(localTableLogical(cov, "ActuallyCalled"));
    row.DUTCallCount = sum(localNumericColumn(cov, "CallCount"));
    row.DUTRuntimeSeconds = sum(localNumericColumn(cov, "TotalTimeSeconds"));
    row.DUTInputArtifact = string(defs(i).InputArtifact);
    row.DUTOutputArtifact = string(defs(i).OutputArtifact);
    row.ReferenceAvailable = any(localTableLogical(comp, "ReferenceAvailable"));
    row.ReferenceFunction = strjoin(unique(cellstr(string(comp.ReferenceSource))), " | ");
    row.ReferenceArtifact = strjoin(unique(cellstr(string(comp.ReferenceArtifactPath))), " | ");
    row.DUTReferenceCompared = height(comp) > 0 && any(string(comp.ReferenceOutputName) ~= "reference_unavailable");
    row.ComparisonMetric = strjoin(unique(cellstr(string(comp.ComparisonType))), " | ");
    row.Tolerance = localDelimitedSummary(comp, ["ToleranceAbs","ToleranceRel"]);
    row.Delta = localDelimitedSummary(comp, ["DeltaAbs","DeltaRel"]);
    row.NumericalSanityPass = isempty(inv) || all(localTableLogical(inv, "Pass"));
    row.NegativeTestPass = localBlockNegativeTestPass(ctx, blockId);
    row.OracleUsed = localScalarLogical(det, "OracleUsed", false);
    row.ProxyUsed = localScalarLogical(det, "ProxyUsed", false);
    row.FallbackUsed = localScalarLogical(det, "FallbackUsed", false);
    row.Skipped = localScalarLogical(det, "Skipped", false);
    row.Bypassed = localScalarLogical(det, "Bypassed", false);
    row.LabelOnlyEvidence = localScalarLogical(det, "LabelOnlyEvidence", false);
    row.WaveformEvidencePresent = localEvidenceTypePresent(ev, "waveform");
    row.GridEvidencePresent = localEvidenceTypePresent(ev, "grid");
    row.BitEvidencePresent = localEvidenceTypePresent(ev, "bit");
    row.DecoderEvidencePresent = localEvidenceTypePresent(ev, "decoder");
    row.ChannelEvidencePresent = localEvidenceTypePresent(ev, "channel");
    row.TimingEvidencePresent = localEvidenceTypePresent(ev, "timing");
    row.FrequencyEvidencePresent = localEvidenceTypePresent(ev, "frequency");
    row.ImplementationPass = localImplementationPass(row, comp);
    row.BlocksResultOk = row.ImplementationPass;
    [row.IssueIdIfFailed, row.FailureReason, row.RecommendedFix] = localBlockFailureSummary(row, comp, inv);
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildPHYOutcomeSummary(ctx, matrixT)
rows = repmat(localEmptyPHYOutcomeRow(), 0, 1);
for i = 1:height(matrixT)
    row = localEmptyPHYOutcomeRow();
    row.RunId = ctx.RunId;
    row.Subsystem = string(matrixT.Subsystem(i));
    row.Feature = string(matrixT.BlockId(i));
    row.Enabled = logical(matrixT.FeatureEnabled(i));
    row.ImplementedForScenario = logical(matrixT.ImplementationPass(i));
    row.ActualRuntimePathUsed = logical(matrixT.DUTFunctionActuallyCalled(i));
    row.ReferenceCompared = logical(matrixT.DUTReferenceCompared(i));
    row.NumericalValuesPlausible = logical(matrixT.NumericalSanityPass(i));
    row.NegativeTestsPassed = logical(matrixT.NegativeTestPass(i));
    row.DecoderOutputsPresent = logical(matrixT.DecoderEvidencePresent(i));
    row.ChannelEstimationOutputsPresent = logical(matrixT.ChannelEvidencePresent(i));
    row.FunctionCoveragePass = logical(matrixT.DUTFunctionActuallyCalled(i));
    row.BypassDetected = logical(matrixT.Bypassed(i));
    row.OverallBlockPass = logical(matrixT.ImplementationPass(i));
    row.BlocksResultOk = logical(matrixT.BlocksResultOk(i));
    row.IssueIds = string(matrixT.IssueIdIfFailed(i));
    row.FailureReason = string(matrixT.FailureReason(i));
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildLinkPerformanceSummary(ctx, matrixT)
rows = repmat(localEmptyLinkPerformanceRow(), 0, 1);
for direction = ["DL","UL"]
    trialT = localDirectionTrials(ctx, direction);
    if isempty(trialT)
        continue;
    end
    ueList = localUniqueValues(trialT, "UEID");
    if isempty(ueList)
        ueList = NaN;
    end
    for i = 1:numel(ueList)
        subset = localFilterByNumeric(trialT, "UEID", ueList(i));
        mobility = localFilterByNumeric(ctx.Tables.LiveMobility, "UEID", ueList(i));
        row = localEmptyLinkPerformanceRow();
        row.RunId = ctx.RunId;
        row.Direction = direction;
        row.UEId = ueList(i);
        row.DistanceStart_m = localFirstNumeric(mobility, "PropagationDistance_m", NaN);
        row.DistanceEnd_m = localLastNumeric(mobility, "PropagationDistance_m", row.DistanceStart_m);
        if ~isfinite(row.DistanceStart_m)
            row.DistanceStart_m = localFirstNumeric(subset, "PropagationDistance_m", NaN);
            row.DistanceEnd_m = localLastNumeric(subset, "PropagationDistance_m", row.DistanceStart_m);
        end
        row.Speed_kmh = localFirstNumeric(mobility, "Speed_kmh", ctx.ConfiguredSpeedKmh);
        row.DopplerHz = localMeanNumeric(subset, "DopplerHz");
        row.MeanSINRdB = localMeanNumeric(subset, "PostEqSINR_dB");
        row.MinSINRdB = localMinNumeric(subset, "PostEqSINR_dB");
        row.MaxSINRdB = localMaxNumeric(subset, "PostEqSINR_dB");
        row.MeanMCS = localMeanNumeric(subset, "MCS");
        row.MinMCS = localMinNumeric(subset, "MCS");
        row.MaxMCS = localMaxNumeric(subset, "MCS");
        row.MeanLayers = localMeanNumeric(subset, "Layers");
        row.MaxLayers = localMaxNumeric(subset, "Layers");
        row.RawBLER = localBLER(subset);
        row.RawBER = localBER(subset);
        row.ThroughputMbps = localMeanNumeric(subset, "Throughput_Mbps");
        row.GoodputMbps = localMeanNumericFallback(subset, ["Goodput_Mbps","OfferedThroughput_Mbps"]);
        row.HARQRetxRate = localHARQRetxRate(ctx, direction, ueList(i));
        row.PacketLossRate = localPacketLossRate(subset);
        row.LatencyMeanMs = localMeanNumericFallback(subset, ["Latency_ms","DecodeLatency_ms"]);
        row.OutcomePass = localDirectionBlockPass(matrixT, direction);
        row.FailureReason = localDirectionFailureReason(matrixT, direction);
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildBlockCorrectnessSummary(ctx, matrixT, comparisonT)
rows = repmat(localEmptyBlockCorrectnessRow(), 0, 1);
for i = 1:height(matrixT)
    comp = comparisonT(string(comparisonT.BlockId) == string(matrixT.BlockId(i)), :);
    row = localEmptyBlockCorrectnessRow();
    row.RunId = ctx.RunId;
    row.BlockId = string(matrixT.BlockId(i));
    row.Subsystem = string(matrixT.Subsystem(i));
    row.DUTCalled = logical(matrixT.DUTFunctionActuallyCalled(i));
    row.ReferenceAvailable = logical(matrixT.ReferenceAvailable(i));
    row.DUTReferencePass = ~isempty(comp) && all(localTableLogical(comp, "Pass"));
    row.InvariantPass = logical(matrixT.NumericalSanityPass(i));
    row.NegativePass = logical(matrixT.NegativeTestPass(i));
    row.EvidenceComplete = localEvidenceComplete(matrixT(i, :));
    row.ImplementationPass = logical(matrixT.ImplementationPass(i));
    row.ResultContribution = localResultContribution(matrixT(i, :));
    row.FailureReason = string(matrixT.FailureReason(i));
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildReferenceComparisonSummary(ctx, comparisonT)
rows = repmat(localEmptyReferenceSummaryRow(), 0, 1);
for blockId = unique(string(comparisonT.BlockId)).'
    if strlength(blockId) == 0
        continue;
    end
    comp = comparisonT(string(comparisonT.BlockId) == blockId, :);
    row = localEmptyReferenceSummaryRow();
    row.RunId = ctx.RunId;
    row.BlockId = blockId;
    row.ReferenceAvailable = any(localTableLogical(comp, "ReferenceAvailable"));
    row.ComparisonCount = height(comp);
    row.PassCount = sum(localTableLogical(comp, "Pass"));
    row.FailCount = sum(~localTableLogical(comp, "Pass"));
    row.DUTReferencePass = row.FailCount == 0 && row.PassCount > 0;
    row.ReferenceSources = strjoin(unique(cellstr(string(comp.ReferenceSource))), " | ");
    row.MaxAbsDelta = localMaxNumeric(comp, "DeltaAbs");
    row.FailureReason = strjoin(unique(cellstr(string(comp.FailureReason(strlength(strtrim(string(comp.FailureReason))) > 0)))), " | ");
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildCoverageSummary(ctx, coverageT, matrixT)
rows = repmat(localEmptyCoverageSummaryRow(), 0, 1);
for subsystem = unique(string(coverageT.Subsystem)).'
    if strlength(subsystem) == 0
        continue;
    end
    cov = coverageT(string(coverageT.Subsystem) == subsystem, :);
    mat = matrixT(string(matrixT.Subsystem) == subsystem, :);
    row = localEmptyCoverageSummaryRow();
    row.RunId = ctx.RunId;
    row.Subsystem = subsystem;
    row.ExpectedFunctions = height(cov);
    row.ActuallyCalledFunctions = sum(localTableLogical(cov, "ActuallyCalled"));
    row.CoveragePass = all(localTableLogical(cov, "ImplementationCoveragePass"));
    row.BypassDetected = any(localTableLogical(mat, "Bypassed"));
    row.ProxyDetected = any(localTableLogical(mat, "ProxyUsed"));
    row.FallbackDetected = any(localTableLogical(mat, "FallbackUsed"));
    row.FailureReason = strjoin(unique(cellstr(string(cov.FailureReason(strlength(strtrim(string(cov.FailureReason))) > 0)))), " | ");
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildTopNumericalFindings(ctx, invariantT, linkPerfT)
rows = repmat(localEmptyFindingRow(), 0, 1);
for direction = ["DL","UL"]
    perf = linkPerfT(string(linkPerfT.Direction) == direction, :);
    if isempty(perf)
        continue;
    end
    rows(end+1, 1) = localFindingRow("BLER_" + direction, localMeanNumeric(perf, "RawBLER"), "", "ratio", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>
    rows(end+1, 1) = localFindingRow("BER_" + direction, localMeanNumeric(perf, "RawBER"), "", "ratio", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>
    rows(end+1, 1) = localFindingRow("SINR_" + direction, localMeanNumeric(perf, "MeanSINRdB"), "", "dB", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>
    rows(end+1, 1) = localFindingRow("Throughput_" + direction, localMeanNumeric(perf, "ThroughputMbps"), "", "Mbps", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>
    rows(end+1, 1) = localFindingRow("Goodput_" + direction, localMeanNumeric(perf, "GoodputMbps"), "", "Mbps", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>
end
rows(end+1, 1) = localFindingRow("LLRMedianAbs", localMedianColumn(ctx.Tables.LiveStageTrace, "LLRMeanAbs"), "", "abs", "reports/csv/live_tx_rx_stage_trace.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("ResidualCFOMeanAbs", localResidualCFOMean(ctx.Tables.LiveChannelState), "", "Hz", "reports/csv/live_channel_state_tti.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("TimingErrorMeanAbs", localMeanAbsColumn(ctx.Tables.LiveChannelState, "TimingError_samples"), "", "samples", "reports/csv/live_channel_state_tti.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("DopplerMeanAbs", localMeanAbsColumn(ctx.Tables.LiveChannelState, "DopplerHz"), "", "Hz", "reports/csv/live_channel_state_tti.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("NMSEMean", localMeanNumericFallback(ctx.Tables.SRSStrictTrials, ["NMSE_dB"]), "", "dB", "reference_signals/csv/srs_trials.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("NMSEMeanTRS", localMeanNumericFallback(ctx.Tables.TRSStrictTrials, ["NMSE_dB"]), "", "dB", "reference_signals/csv/trs_trials.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("MaxLayers", max([localMaxNumeric(ctx.Tables.DLTrials, "Layers"), localMaxNumeric(ctx.Tables.ULTrials, "Layers")]), "", "count", "air_interface/csv/dl_pdsch_trials.csv"); %#ok<AGROW>
rows(end+1, 1) = localFindingRow("HARQRetxRate", localMeanNumeric(linkPerfT, "HARQRetxRate"), "", "ratio", "reports/csv/lls_link_performance_summary.csv"); %#ok<AGROW>

T = struct2table(rows, "AsArray", true);
T = T(isfinite(localNumericColumn(T, "Value")), :);
if isempty(T)
    T = struct2table(repmat(localEmptyFindingRow(), 0, 1), "AsArray", true);
else
    T = T(1:min(height(T), 16), :);
end
end

function summary = localBuildSummary(ctx, matrixT, comparisonT, invariantT, coverageT, detectorT)
enabledMask = localTableLogical(matrixT, "FeatureEnabled");
passMask = localTableLogical(matrixT, "ImplementationPass");
calledMask = localTableLogical(coverageT, "ActuallyCalled");
summary = struct();
summary.RunId = ctx.RunId;
summary.EnabledBlockCount = sum(enabledMask);
summary.PassingBlockCount = sum(passMask(enabledMask));
summary.ReferenceComparedBlockCount = numel(unique(string(comparisonT.BlockId(localTableLogical(comparisonT, "Pass") | localTableLogical(comparisonT, "ReferenceAvailable")))));
summary.NumericalSanityFailureCount = sum(~localTableLogical(invariantT, "Pass"));
summary.ReferenceUnavailableBlocks = string(matrixT.BlockId(enabledMask & ~localTableLogical(matrixT, "ReferenceAvailable")));
summary.FunctionNotCalled = string(coverageT.FunctionName(localTableLogical(coverageT, "ExpectedForScenario") & ~calledMask));
summary.BypassedBlocks = string(detectorT.BlockId(localTableLogical(detectorT, "Bypassed")));
summary.LabelOnlyBlocks = string(detectorT.BlockId(localTableLogical(detectorT, "LabelOnlyEvidence")));
summary.ProxyBlocks = string(detectorT.BlockId(localTableLogical(detectorT, "ProxyUsed")));
summary.FallbackBlocks = string(detectorT.BlockId(localTableLogical(detectorT, "FallbackUsed")));
summary.ActualLLSVerdict = localVerdict(summary, matrixT);
summary.VerdictSentence = localVerdictSentence(summary);
end

function T = localBuildNoBypassGate(matrixT, detectorT)
rows = repmat(struct("BlockId", "", "BypassDetected", false, "ProxyUsed", false, "FallbackUsed", false, "LabelOnlyEvidence", false, "GatePass", false, "FailureReason", ""), 0, 1);
for i = 1:height(matrixT)
    det = detectorT(string(detectorT.BlockId) == string(matrixT.BlockId(i)), :);
    row = rowsTemplate();
    row.BlockId = string(matrixT.BlockId(i));
    row.BypassDetected = localScalarLogical(det, "Bypassed", false);
    row.ProxyUsed = localScalarLogical(det, "ProxyUsed", false);
    row.FallbackUsed = localScalarLogical(det, "FallbackUsed", false);
    row.LabelOnlyEvidence = localScalarLogical(det, "LabelOnlyEvidence", false);
    row.GatePass = ~(row.BypassDetected || row.ProxyUsed || row.FallbackUsed || row.LabelOnlyEvidence);
    row.FailureReason = localDetectorFailureReason(det);
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function row = rowsTemplate()
row = struct("BlockId", "", "BypassDetected", false, "ProxyUsed", false, "FallbackUsed", false, "LabelOnlyEvidence", false, "GatePass", false, "FailureReason", "");
end

function out = localWriteArtifacts(out)
layout = out.Context.Layout;
jsonDir = fullfile(layout.ReportDir, "json");
mdDir = fullfile(layout.ReportDir, "md");
htmlDir = fullfile(layout.ReportDir, "html");
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(mdDir);
sixgr.util.ensureFolder(htmlDir);

art = struct();
art.ValidationMatrixCSV = fullfile(layout.ReportCSVDir, "phy_block_validation_matrix.csv");
art.DUTReferenceComparisonCSV = fullfile(layout.ReportCSVDir, "dut_reference_comparison.csv");
art.InvariantChecksCSV = fullfile(layout.ReportCSVDir, "phy_value_invariant_checks.csv");
art.FunctionCoverageCSV = fullfile(layout.ReportCSVDir, "implementation_function_coverage.csv");
art.RealPHYPathEvidenceCSV = fullfile(layout.ReportCSVDir, "real_phy_path_evidence.csv");
art.DetectorCSV = fullfile(layout.ReportCSVDir, "oracle_proxy_fallback_detector.csv");
art.PlausibilityCSV = fullfile(layout.ReportCSVDir, "generated_value_plausibility_audit.csv");
art.PHYOutcomeCSV = fullfile(layout.ReportCSVDir, "lls_phy_outcome_summary.csv");
art.LinkPerformanceCSV = fullfile(layout.ReportCSVDir, "lls_link_performance_summary.csv");
art.BlockCorrectnessCSV = fullfile(layout.ReportCSVDir, "lls_block_correctness_summary.csv");
art.ReferenceComparisonSummaryCSV = fullfile(layout.ReportCSVDir, "lls_reference_comparison_summary.csv");
art.ImplementationCoverageSummaryCSV = fullfile(layout.ReportCSVDir, "lls_real_implementation_coverage_summary.csv");

sixgr.util.csvWriteTable(art.ValidationMatrixCSV, out.ValidationMatrix);
sixgr.util.csvWriteTable(art.DUTReferenceComparisonCSV, out.DUTReferenceComparison);
sixgr.util.csvWriteTable(art.InvariantChecksCSV, out.PHYValueInvariantChecks);
sixgr.util.csvWriteTable(art.FunctionCoverageCSV, out.RuntimeFunctionCoverage);
sixgr.util.csvWriteTable(art.RealPHYPathEvidenceCSV, out.RealPHYPathEvidence);
sixgr.util.csvWriteTable(art.DetectorCSV, out.OracleProxyFallbackDetector);
sixgr.util.csvWriteTable(art.PlausibilityCSV, out.GeneratedValuePlausibilityAudit);
sixgr.util.csvWriteTable(art.PHYOutcomeCSV, out.PHYOutcomeSummary);
sixgr.util.csvWriteTable(art.LinkPerformanceCSV, out.LinkPerformanceSummary);
sixgr.util.csvWriteTable(art.BlockCorrectnessCSV, out.BlockCorrectnessSummary);
sixgr.util.csvWriteTable(art.ReferenceComparisonSummaryCSV, out.ReferenceComparisonSummary);
sixgr.util.csvWriteTable(art.ImplementationCoverageSummaryCSV, out.RealImplementationCoverageSummary);

art.ReportArtifacts = sixgr.validation.writeImplementationValidationReport(out.Context.RunFolder, out);
out.ReportArtifacts = art;
end

function rows = localMobilityComparisonRows(ctx, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
T = ctx.Tables.LiveChannelState;
if isempty(T)
    T = ctx.Tables.LiveMobility;
end
if isempty(T)
    return;
end
repIdx = localRepresentativeRowIndices(T, 12);
for idx = repIdx(:).'
    speedKmh = localConfigOrTableSpeed(ctx, T, idx);
    dopplerHz = localTableNumber(T, idx, "DopplerHz", NaN);
    if isfinite(dopplerHz) && isfinite(speedKmh) && isfinite(ctx.CenterFrequencyHz)
        refDoppler = sixgr.validation.ReferencePathAnalytical("doppler_hz", ctx.CenterFrequencyHz, speedKmh, "kmh");
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, "MobilityDoppler", "mobility", idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "DopplerHz", "analytical_fc_v_over_c", dopplerHz, refDoppler, ...
            abs(dopplerHz - refDoppler), localRelativeError(dopplerHz, refDoppler), 25.0, 0.10, "analytical_scalar", "analytical_fc_v_over_c", ...
            localRelativePath(ctx.RunFolder, ctx.Paths.LiveChannelState), "", "");
    end
    distanceM = localTableNumber(T, idx, "PropagationDistance_m", NaN);
    delayS = localTableNumber(T, idx, "GeometricPropagationDelay_s", NaN);
    if isfinite(distanceM) && isfinite(delayS)
        refDistance = sixgr.validation.ReferencePathAnalytical("distance_m", delayS);
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, "MobilityDoppler", "mobility", idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "PropagationDistance_m", "distance_from_delay", distanceM, refDistance, ...
            abs(distanceM - refDistance), localRelativeError(distanceM, refDistance), 5.0, 0.05, "analytical_scalar", "analytical_distance_from_delay", ...
            localRelativePath(ctx.RunFolder, ctx.Paths.LiveChannelState), "", "");
    end
end
end

function rows = localCFOTimingComparisonRows(ctx, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
T = ctx.Tables.LiveChannelState;
if isempty(T)
    return;
end
repIdx = localRepresentativeRowIndices(T, 12);
for idx = repIdx(:).'
    injected = localTableNumber(T, idx, "InjectedCFO_Hz", NaN);
    estimated = localTableNumber(T, idx, "EstimatedCFO_Hz", NaN);
    if isfinite(injected) && isfinite(estimated)
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, "ChannelRF", "rf_channel", idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "EstimatedCFO_Hz", "injected_cfo_hz", estimated, injected, abs(estimated - injected), localRelativeError(estimated, injected), ...
            200.0, 0.40, "impairment_replay", "analytical_injected_cfo", localRelativePath(ctx.RunFolder, ctx.Paths.LiveChannelState), "", "");
    end
    distanceM = localTableNumber(T, idx, "PropagationDistance_m", NaN);
    timingError = localTableNumber(T, idx, "TimingError_samples", NaN);
    if isfinite(distanceM) && isfinite(timingError)
        expectedDelay = sixgr.validation.ReferencePathAnalytical("propagation_delay_s", distanceM);
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, "ChannelRF", "rf_channel", idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "GeometricPropagationDelay_s", "distance_over_c", localTableNumber(T, idx, "GeometricPropagationDelay_s", NaN), expectedDelay, ...
            abs(localTableNumber(T, idx, "GeometricPropagationDelay_s", NaN) - expectedDelay), ...
            localRelativeError(localTableNumber(T, idx, "GeometricPropagationDelay_s", NaN), expectedDelay), ...
            2e-7, 0.10, "analytical_scalar", "distance_over_c", localRelativePath(ctx.RunFolder, ctx.Paths.LiveChannelState), "", "");
    end
end
end

function rows = localTBSComparisonRows(ctx, blockId, T, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
if isempty(T)
    return;
end
repIdx = localRepresentativeRowIndices(T, 16);
subsystem = localTernary(blockId == "PDSCH", "downlink_data", "uplink_data");
for idx = repIdx(:).'
    tbBits = localTableNumber(T, idx, "TBSize_bits", NaN);
    prb = localFirstFiniteNumber([localTableNumber(T, idx, "TBSInputNPRB", NaN), ...
        localTableNumber(T, idx, "AllocatedPRBCount", NaN)]);
    layers = localFirstFiniteNumber([localTableNumber(T, idx, "TBSInputNumLayers", NaN), ...
        localTableNumber(T, idx, "Layers", 1)]);
    modulation = localTableText(T, idx, "TBSInputModulation", "");
    if strlength(strtrim(string(modulation))) == 0
        modulation = localTableText(T, idx, "Modulation", "");
    end
    targetCodeRate = localFirstFiniteNumber([localTableNumber(T, idx, "TBSInputTargetCodeRate", NaN), ...
        localTableNumber(T, idx, "TargetCodeRate", NaN)]);
    xOverhead = localFirstFiniteNumber([localTableNumber(T, idx, "TBSInputXOverhead", NaN), ...
        localTableNumber(T, idx, "XOverhead", 0)]);
    if ~isfinite(xOverhead)
        xOverhead = 0;
    end
    nRePerPrb = localReferenceNREPerPRB(T, idx);
    exactInputsAvailable = isfinite(prb) && prb > 0 && isfinite(layers) && layers > 0 && ...
        strlength(strtrim(string(modulation))) > 0 && ...
        isfinite(targetCodeRate) && targetCodeRate > 0 && targetCodeRate < 1 && ...
        isfinite(xOverhead) && isfinite(nRePerPrb) && nRePerPrb > 0;
    if ~exactInputsAvailable
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, blockId, subsystem, idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "TBSize_bits", "nrTBS_exact_production_inputs", tbBits, NaN, NaN, NaN, ...
            0, 0, "exact_tbs_inputs_required", "reference_path_unavailable", ...
            localRelativePath(ctx.RunFolder, localDirectionPath(blockId)), "", ...
            "exact_tbs_production_inputs_missing");
        continue;
    end
    ref = sixgr.validation.ReferencePath5GToolbox("tbs_bits", modulation, layers, prb, nRePerPrb, targetCodeRate, xOverhead, NaN);
    if ref.Available && isfinite(tbBits)
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, blockId, subsystem, idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "TBSize_bits", "nrTBS", tbBits, ref.Value, abs(tbBits - ref.Value), localRelativeError(tbBits, ref.Value), ...
            0, 0, "toolbox_tbs_exact", "nrTBS", ...
            localRelativePath(ctx.RunFolder, localDirectionPath(blockId)), "", "");
    else
        rows(end+1, 1) = localComparisonRecord(ctx.RunId, blockId, subsystem, idx, ... %#ok<AGROW>
            localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
            "TBSize_bits", "nrTBS_exact_production_inputs", tbBits, NaN, NaN, NaN, ...
            0, 0, "toolbox_tbs_exact", "reference_path_unavailable", ...
            localRelativePath(ctx.RunFolder, localDirectionPath(blockId)), "", ...
            "nrTBS_reference_unavailable_or_dut_tbs_missing");
    end
end
end

function nRePerPrb = localReferenceNREPerPRB(T, idx)
% Strict TBS validation accepts only the value captured at transmitter/grant
% construction.  DataRECount/PRB is not equivalent when RS, UCI, reserved
% RE, rate matching, or nonuniform allocation masks are present.
nRePerPrb = localTableNumber(T, idx, "TBSInputNREPerPRB", NaN);
if ~(isfinite(nRePerPrb) && nRePerPrb > 0)
    nRePerPrb = NaN;
end
end

function value = localFirstFiniteNumber(values)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = NaN;
else
    value = values(idx);
end
end

function rows = localStrictBooleanComparisonRows(ctx, blockId, T, metricName, expectedValue, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
if isempty(T)
    return;
end
valueField = "StrictOk";
if ~ismember(valueField, string(T.Properties.VariableNames))
    return;
end
repIdx = localRepresentativeRowIndices(T, 8);
for idx = repIdx(:).'
    actual = localTableLogicalValue(T, idx, valueField, false);
    rows(end+1, 1) = localComparisonRecord(ctx.RunId, blockId, localBlockSubsystem(blockId), idx, ... %#ok<AGROW>
        localTableNumber(T, idx, "UEID", NaN), localTableNumber(T, idx, "Slot", NaN), configHash, "", ...
        valueField, metricName, double(actual), double(expectedValue), abs(double(actual) - double(expectedValue)), ...
        abs(double(actual) - double(expectedValue)), 0, 0, "expected_boolean", "golden_negative_vector", "", "", "");
end
end

function rows = localPBCHComparisonRows(ctx, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
T = ctx.Tables.PBCHRecoveryTrials;
if isempty(T)
    return;
end
if ~ismember("CRCPass", string(T.Properties.VariableNames))
    return;
end
idx = 1;
actual = localTableLogicalValue(T, idx, "CRCPass", false);
rows(end+1, 1) = localComparisonRecord(ctx.RunId, "SSB_PBCH_MIB", "broadcast", idx, NaN, ... %#ok<AGROW>
    localTableNumber(T, idx, "Slot", NaN), configHash, "", "PBCH_CRCPass", "transmitted_payload_crc", ...
    double(actual), 1, abs(double(actual) - 1), abs(double(actual) - 1), 0, 0, "crc_boolean", "tx_rx_crc_match", ...
    "control/csv/pbch_recovery_trials.csv", "", "");
end

function rows = localSIB1ComparisonRows(ctx, configHash)
rows = repmat(localEmptyComparisonRow(), 0, 1);
T = ctx.Tables.SIB1Recovery;
if isempty(T)
    return;
end
hashFields = ["PayloadHashRx","PayloadHashTx","SIB1PayloadHashRx","SIB1PayloadHashTx"];
rxHash = localTableTextFirstPresent(T, 1, hashFields(contains(hashFields, "Rx")), "");
txHash = localTableTextFirstPresent(T, 1, hashFields(contains(hashFields, "Tx")), "");
if strlength(rxHash) == 0 || strlength(txHash) == 0
    return;
end
pass = rxHash == txHash;
rows(end+1, 1) = localComparisonRecord(ctx.RunId, "SIB1", "broadcast", 1, NaN, ... %#ok<AGROW>
    localTableNumber(T, 1, "Slot", NaN), configHash, "", "SIB1PayloadHashRx", "SIB1PayloadHashTx", ...
    double(pass), 1, double(~pass), double(~pass), 0, 0, "payload_hash_match", "sib1_payload_hash", ...
    "control/csv/sib1_recovery_trials.csv", "", localTernary(pass, "", "sib1_payload_hash_mismatch"));
end

function rows = localGridInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
profiles = sixgr.validation.GoldenVectorFactory("grid_profiles");
mask = abs(double(profiles.BandwidthHz) - double(ctx.BandwidthHz)) < 1 & ...
    abs(double(profiles.SCSkHz) - double(ctx.SCSkHz)) < 1e-9;
if ~any(mask)
    return;
end
profile = profiles(find(mask, 1, "first"), :);
checks = { ...
    "frequency.n_size_grid", double(ctx.GridRB), double(profile.NSizeGrid), "GRID-01"; ...
    "waveform.sample_rate_hz", double(ctx.SampleRateHz), double(profile.SampleRateHz), "GRID-01" ...
    };
for i = 1:size(checks, 1)
    observed = checks{i, 2};
    expected = checks{i, 3};
    row = localInvariantRecord(ctx.RunId, checks{i, 4}, "radio", string(checks{i, 1}), NaN, NaN, NaN, ...
        observed, expected, expected, expected, 0, abs(observed - expected) < 1e-9, "critical", ...
        localTernary(abs(observed - expected) < 1e-9, "", "configured_grid_tuple_conflict"), ...
        "Align bandwidth, SCS, NSizeGrid, and sample rate to one authoritative NR tuple.");
    rows(end+1, 1) = row; %#ok<AGROW>
end
end

function rows = localMobilityInvariantRows(ctx, const)
rows = repmat(localEmptyInvariantRow(), 0, 1);
T = ctx.Tables.LiveMobility;
if isempty(T)
    return;
end
speed = localMeanNumeric(T, "Speed_kmh");
if isfinite(speed)
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "MOB-01", "mobility", "Speed_kmh", NaN, NaN, NaN, speed, ... %#ok<AGROW>
        max(0, speed - 5), speed + 5, speed, 5, true, "medium", "", "Observed mobility speed is runtime-backed.");
end
if isfinite(ctx.CenterFrequencyHz) && isfinite(speed)
    refDoppler = sixgr.validation.ReferencePathAnalytical("doppler_hz", ctx.CenterFrequencyHz, speed, "kmh");
    observed = localMeanAbsColumn(ctx.Tables.LiveChannelState, "DopplerHz");
    if isfinite(observed)
        ok = abs(observed - refDoppler) <= max(25.0, 0.15 * abs(refDoppler));
        rows(end+1, 1) = localInvariantRecord(ctx.RunId, "MOB-02", "mobility", "DopplerHz", NaN, NaN, NaN, observed, ... %#ok<AGROW>
            refDoppler - 25.0, refDoppler + 25.0, refDoppler, 25.0, ok, "high", ...
            localTernary(ok, "", "doppler_outside_analytical_tolerance"), "Keep Doppler derived from geometry and carrier frequency.");
    end
end
if isfinite(localFirstNumeric(ctx.Tables.LiveChannelState, "PropagationDistance_m", NaN))
    firstDistance = localFirstNumeric(ctx.Tables.LiveChannelState, "PropagationDistance_m", NaN);
    lastDistance = localLastNumeric(ctx.Tables.LiveChannelState, "PropagationDistance_m", NaN);
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "MOB-03", "mobility", "UE_Distance_First_m", NaN, NaN, NaN, firstDistance, 0, inf, firstDistance, 0, firstDistance >= 0, "medium", "", "Distance trace is present."); %#ok<AGROW>
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "MOB-04", "mobility", "UE_Distance_Last_m", NaN, NaN, NaN, lastDistance, 0, inf, lastDistance, 0, lastDistance >= 0, "medium", "", "Distance trace is present."); %#ok<AGROW>
end
end

function rows = localLLRInvariantRows(ctx, const)
rows = repmat(localEmptyInvariantRow(), 0, 1);
for direction = ["DL","UL"]
    T = localDirectionTrials(ctx, direction);
    if isempty(T) || ~ismember("LLRMeanAbs", string(T.Properties.VariableNames))
        continue;
    end
    snr = localNumericColumn(T, "AppliedAWGNSNR_dB");
    llr = localNumericColumn(T, "LLRMeanAbs");
    mask = isfinite(snr) & snr > const.HighSNRThreshold_dB & isfinite(llr);
    if ~any(mask)
        continue;
    end
    observed = median(llr(mask), "omitnan");
    ok = observed >= const.MinimumHighSNRLLRMeanAbs;
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "LLR-01", localBlockSubsystem(localTernary(direction == "DL", "PDSCH", "PUSCH")), ... %#ok<AGROW>
        "LLRMeanAbs", NaN, NaN, NaN, observed, const.MinimumHighSNRLLRMeanAbs, inf, const.MinimumHighSNRLLRMeanAbs, 0, ok, "critical", ...
        localTernary(ok, "", "high_snr_llr_near_zero"), "Use measured decoder/equalizer LLRs rather than pinned or empty values.");
end
end

function rows = localSINRInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
T = ctx.Tables.ULTrials;
if localHasRows(T)
    sinrVals = localNumericColumn(T, "PostEqSINR_dB");
    sinrVals = sinrVals(isfinite(sinrVals));
    if numel(sinrVals) >= 3
        stdVal = std(sinrVals, 0, "omitnan");
        ok = stdVal > 1e-6;
        rows(end+1, 1) = localInvariantRecord(ctx.RunId, "SINR-01", "uplink_data", "PUSCH_PostEqSINR_std", NaN, NaN, NaN, stdVal, ... %#ok<AGROW>
            1e-6, inf, NaN, 0, ok, "high", localTernary(ok, "", "pusch_sinr_pinned_constant"), ...
            "Expose measured post-equalization SINR that changes with mobility and channel state.");
    end
end
end

function rows = localTimingInvariantRows(ctx, const)
rows = repmat(localEmptyInvariantRow(), 0, 1);
T = ctx.Tables.LiveChannelState;
if isempty(T)
    return;
end
distance = localMaxNumeric(T, "PropagationDistance_m");
delay = localMaxNumeric(T, "GeometricPropagationDelay_s");
if isfinite(distance) && isfinite(delay)
    expected = sixgr.validation.ReferencePathAnalytical("propagation_delay_s", distance);
    ok = abs(delay - expected) <= max(2e-7, 0.15 * abs(expected));
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "TIM-01", "rf_channel", "PropagationDelay_s", NaN, NaN, NaN, delay, ... %#ok<AGROW>
        expected - 2e-7, expected + 2e-7, expected, 2e-7, ok, "high", localTernary(ok, "", "distance_delay_mismatch"), ...
        "Keep propagation delay consistent with geometry and the speed of light.");
end
end

function rows = localCFOInvariantRows(ctx, const)
rows = repmat(localEmptyInvariantRow(), 0, 1);
T = ctx.Tables.LiveChannelState;
if isempty(T)
    return;
end
injected = localMeanNumeric(T, "InjectedCFO_Hz");
estimated = localMeanNumeric(T, "EstimatedCFO_Hz");
if isfinite(injected) && isfinite(estimated) && abs(injected) > 0
    residual = abs(injected - estimated);
    ok = residual <= max(const.DefaultLateResidualCFOTarget_Hz, 0.40 * abs(injected));
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "CFO-01", "rf_channel", "ResidualCFO_Hz", NaN, NaN, NaN, residual, ... %#ok<AGROW>
        0, max(const.DefaultLateResidualCFOTarget_Hz, 0.40 * abs(injected)), 0, const.DefaultLateResidualCFOTarget_Hz, ok, "high", ...
        localTernary(ok, "", "cfo_residual_too_large"), "Improve impairment correction or tracking-loop convergence.");
end
end

function rows = localDecoderInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
for direction = ["DL","UL"]
    T = localDirectionTrials(ctx, direction);
    if isempty(T)
        continue;
    end
    if ~ismember("CRCPass", string(T.Properties.VariableNames))
        continue;
    end
    pass = localOptionalLogicalColumn(T, "CRCPass", false(height(T), 1));
    evidence = localOptionalLogicalColumn(T, localTernary(direction == "DL", "DLSCHDecodeAvailable", "ULSCHDecodeAvailable"), false(height(T), 1));
    bad = pass & ~evidence;
    if any(bad)
        rows(end+1, 1) = localInvariantRecord(ctx.RunId, "DEC-01", localBlockSubsystem(localTernary(direction == "DL", "PDSCH", "PUSCH")), ... %#ok<AGROW>
            "CRCPass_without_decoder_evidence", NaN, NaN, NaN, sum(double(bad)), 0, 0, 0, 0, false, "critical", ...
            "crc_pass_without_decoder_evidence", "Require decoder evidence rows whenever CRC passes.");
    end
end
end

function rows = localMIMOInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
if ~(isfinite(ctx.NumLayers) && ctx.NumLayers > 1)
    return;
end
maxLayers = max([localMaxNumeric(ctx.Tables.DLTrials, "Layers"), localMaxNumeric(ctx.Tables.ULTrials, "Layers")]);
ok = isfinite(maxLayers) && maxLayers >= 2;
rows(end+1, 1) = localInvariantRecord(ctx.RunId, "MIMO-01", "mimo_beamforming", "MaxLayers", NaN, NaN, NaN, maxLayers, ... %#ok<AGROW>
    2, inf, 2, 0, ok, "high", localTernary(ok, "", "configured_multi_layer_never_materialized"), ...
    "Publish transmitted/effective layer evidence instead of nominal antenna counts.");
end

function rows = localHARQInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
T = ctx.Tables.HARQTimeline;
if isempty(T)
    T = ctx.Tables.HARQProcessTimeline;
end
if isempty(T)
    return;
end
retx = localOptionalLogicalColumn(T, "RetxFlag", false(height(T), 1));
delivered = localOptionalLogicalColumn(T, "DeliveredFlag", false(height(T), 1));
if any(retx & delivered)
    rows(end+1, 1) = localInvariantRecord(ctx.RunId, "HARQ-01", "mac_harq", "HARQRetxDeliveredRows", NaN, NaN, NaN, ... %#ok<AGROW>
        sum(double(retx & delivered)), 0, inf, NaN, 0, true, "medium", "", "HARQ timeline exposes retransmission delivery state.");
end
end

function rows = localReferenceSignalInvariantRows(ctx)
rows = repmat(localEmptyInvariantRow(), 0, 1);
for blockId = ["SRS","TRS"]
    T = localTernary(blockId == "SRS", ctx.Tables.SRSStrictTrials, ctx.Tables.TRSStrictTrials);
    if isempty(T)
        continue;
    end
    if ismember("NMSE_dB", string(T.Properties.VariableNames))
        nmse = localMeanNumeric(T, "NMSE_dB");
        ok = isfinite(nmse);
        rows(end+1, 1) = localInvariantRecord(ctx.RunId, blockId + "-01", "reference_signal", blockId + "_NMSE_dB", NaN, NaN, NaN, ... %#ok<AGROW>
            nmse, -inf, inf, nmse, 0, ok, "medium", localTernary(ok, "", "nonfinite_nmse"), "Reference-signal channel-estimation metrics must be finite.");
    end
end
end

function out = localWriteArtifactPath(blockId)
switch string(blockId)
    case "PDSCH"
        out = "air_interface/csv/dl_pdsch_trials.csv";
    case "PUSCH"
        out = "air_interface/csv/ul_pusch_trials.csv";
    otherwise
        out = "";
end
end

function issueId = localCoverageIssueId(row)
ids = sixgr.validation.GoldenVectorFactory("issue_ids");
if row.ProxyUsed
    issueId = string(ids.ProxyDetected);
elseif row.FallbackUsed
    issueId = string(ids.FallbackDetected);
elseif row.Bypassed
    issueId = string(ids.FunctionNotCalled);
elseif row.Skipped
    issueId = "SKIP-001";
else
    issueId = string(ids.FunctionNotCalled);
end
end

function reason = localCoverageFailureReason(row)
if row.ProxyUsed
    reason = "proxy_used";
elseif row.FallbackUsed
    reason = "fallback_used";
elseif row.Bypassed
    reason = "expected_function_not_called_but_block_has_rows";
elseif row.Skipped
    reason = "function_skipped";
elseif ~row.ActuallyCalled
    reason = "expected_function_not_called";
elseif ~row.RequiredEvidenceProduced
    reason = "called_without_required_evidence";
else
    reason = "";
end
end

function tf = localImplementationPass(row, comp)
if ~row.FeatureEnabled
    tf = false;
    return;
end
refPass = ~isempty(comp) && all(localTableLogical(comp, "Pass")) && any(localTableLogical(comp, "ReferenceAvailable"));
tf = row.DUTFunctionActuallyCalled && ...
    row.WaveformEvidencePresent + row.GridEvidencePresent + row.BitEvidencePresent + row.DecoderEvidencePresent + row.ChannelEvidencePresent > 0 && ...
    ~row.ProxyUsed && ~row.FallbackUsed && ~row.Skipped && ~row.Bypassed && ~row.LabelOnlyEvidence && ...
    row.NumericalSanityPass && row.NegativeTestPass && refPass;
end

function [issueId, failureReason, recommendedFix] = localBlockFailureSummary(row, comp, inv)
ids = sixgr.validation.GoldenVectorFactory("issue_ids");
issueId = "";
failureReason = "";
recommendedFix = "";
if ~row.FeatureEnabled
    return;
end
if row.ImplementationPass
    return;
end
if row.LabelOnlyEvidence
    issueId = string(ids.LabelOnlySuccess);
    failureReason = "pass_row_has_no_real_lls_implementation_evidence";
    recommendedFix = "Point the pass claim at runtime waveform, grid, decoder, and reference-comparison artifacts.";
elseif ~row.DUTFunctionActuallyCalled
    issueId = string(ids.FunctionNotCalled);
    failureReason = "expected_runtime_function_not_called";
    recommendedFix = "Route the enabled feature through the real DUT function path and publish runtime call evidence.";
elseif row.ProxyUsed
    issueId = string(ids.ProxyDetected);
    failureReason = "proxy_used_in_success_path";
    recommendedFix = "Disable proxy/approximation contributions in the strict implementation verdict path.";
elseif row.FallbackUsed
    issueId = string(ids.FallbackDetected);
    failureReason = "fallback_used_in_success_path";
    recommendedFix = "Fail closed or keep fallback rows in explicitly marked debug artifacts only.";
elseif ~row.ReferenceAvailable
    issueId = string(ids.ReferenceUnavailable);
    failureReason = "reference_path_unavailable";
    recommendedFix = "Add an analytical or 5G Toolbox reference path for this enabled block.";
elseif ~row.NegativeTestPass
    issueId = string(ids.NegativeMissing);
    failureReason = "negative_test_missing_or_failed";
    recommendedFix = "Add negative/fault vectors and require them to fail for the correct reason.";
elseif ~row.NumericalSanityPass && ~isempty(inv)
    issueId = string(inv.CheckId(find(~localTableLogical(inv, "Pass"), 1, "first")));
    failureReason = string(inv.FailureReason(find(~localTableLogical(inv, "Pass"), 1, "first")));
    recommendedFix = string(inv.RecommendedFix(find(~localTableLogical(inv, "Pass"), 1, "first")));
elseif ~isempty(comp)
    failed = comp(~localTableLogical(comp, "Pass"), :);
    if ~isempty(failed)
        issueId = "REF-FAIL";
        failureReason = string(failed.FailureReason(1));
        recommendedFix = "Bring DUT outputs within the declared reference tolerance or mark the block incomplete.";
    end
end
if strlength(issueId) == 0
    issueId = "REALPHY-FAIL";
    failureReason = "implementation_evidence_incomplete";
    recommendedFix = "Fill the missing waveform, grid, bit, decoder, channel, timing, and frequency evidence required by the enabled feature.";
end
end

function tf = localBlockNegativeTestPass(ctx, blockId)
switch string(blockId)
    case "PRACH"
        tf = localStrictNegativePass(ctx.Tables.PRACHNegative);
    case "PDCCH"
        tf = localStrictNegativePass(ctx.Tables.PDCCHWrongRNTI) && localStrictNegativePass(ctx.Tables.PDCCHNoSignal);
    case "SRS"
        tf = localStrictNegativePass(ctx.Tables.SRSNegative);
    case "TRS"
        tf = localStrictNegativePass(ctx.Tables.TRSNegative);
    case "PDSCH"
        tf = localDataBlockEvidencePass(ctx.Tables.DLTrials, "DLSCHDecodeAvailable");
    case "PUSCH"
        tf = localDataBlockEvidencePass(ctx.Tables.ULTrials, "ULSCHDecodeAvailable");
    otherwise
        tf = true;
end
end

function tf = localStrictNegativePass(T)
if isempty(T)
    tf = false;
    return;
end
neg = localOptionalLogicalColumn(T, "NegativeExpectedOk", false(height(T), 1));
strict = localOptionalLogicalColumn(T, "StrictOk", false(height(T), 1));
tf = all(~strict) && all(neg);
end

function tf = localDataBlockEvidencePass(T, decoderField)
if isempty(T)
    tf = false;
    return;
end
decode = localOptionalLogicalColumn(T, decoderField, false(height(T), 1));
crc = localOptionalLogicalColumn(T, "CRCPass", false(height(T), 1));
tf = any(decode) && any(crc);
end

function tf = localDirectionBlockPass(matrixT, direction)
if direction == "DL"
    blockIds = ["PDSCH","PDCCH","PRACH"];
else
    blockIds = ["PUSCH","PUCCH_UCI","MAC_HARQ"];
end
mask = ismember(string(matrixT.BlockId), blockIds);
tf = any(mask) && all(localTableLogical(matrixT(mask, :), "ImplementationPass"));
end

function out = localDirectionFailureReason(matrixT, direction)
if direction == "DL"
    blockIds = ["PDSCH","PDCCH","PRACH"];
else
    blockIds = ["PUSCH","PUCCH_UCI","MAC_HARQ"];
end
mask = ismember(string(matrixT.BlockId), blockIds) & ~localTableLogical(matrixT, "ImplementationPass");
reasons = string(matrixT.FailureReason(mask));
reasons = reasons(strlength(strtrim(reasons)) > 0);
out = strjoin(unique(cellstr(reasons)), " | ");
end

function out = localResultContribution(rowT)
if localEvidenceComplete(rowT) && logical(rowT.ImplementationPass)
    out = "actual_waveform_runtime_pass";
elseif logical(rowT.LabelOnlyEvidence)
    out = "label_only_failure";
elseif logical(rowT.ProxyUsed) || logical(rowT.FallbackUsed)
    out = "proxy_or_fallback_failure";
else
    out = "incomplete_runtime_evidence";
end
end

function tf = localEvidenceComplete(rowT)
tf = logical(rowT.WaveformEvidencePresent | rowT.GridEvidencePresent) && ...
    logical(rowT.BitEvidencePresent | rowT.DecoderEvidencePresent) && ...
    logical(rowT.ChannelEvidencePresent);
end

function verdict = localVerdict(summary, matrixT)
enabledMask = localTableLogical(matrixT, "FeatureEnabled");
if summary.EnabledBlockCount == 0
    verdict = "failed evidence run";
elseif all(localTableLogical(matrixT(enabledMask, :), "ImplementationPass"))
    verdict = "full actual LLS";
elseif any(ismember(string(matrixT.BlockId(localTableLogical(matrixT, "ImplementationPass"))), ["PDSCH","PUSCH"]))
    verdict = "partial actual LLS";
elseif any(localTableLogical(matrixT, "LabelOnlyEvidence") | localTableLogical(matrixT, "ProxyUsed") | localTableLogical(matrixT, "FallbackUsed"))
    verdict = "label/proxy simulator";
else
    verdict = "failed evidence run";
end
end

function sentence = localVerdictSentence(summary)
switch string(summary.ActualLLSVerdict)
    case "full actual LLS"
        sentence = "Actual end-to-end LLS implementation evidence is complete for the enabled feature set.";
    case "partial actual LLS"
        sentence = "Partial NR LLS implementation: data-channel path executed, but full access/control/feedback stack incomplete.";
    case "label/proxy simulator"
        sentence = "Not an actual end-to-end LLS implementation for the enabled feature set.";
    otherwise
        sentence = "The evidence run did not produce enough real runtime proof to classify the simulator as an actual LLS implementation.";
end
end

function subsystem = localBlockSubsystem(blockId)
switch string(blockId)
    case "MobilityDoppler"
        subsystem = "mobility";
    case "ChannelRF"
        subsystem = "rf_channel";
    case {"SSB_PBCH_MIB","SIB1"}
        subsystem = "broadcast";
    case "PRACH"
        subsystem = "random_access";
    case "PDCCH"
        subsystem = "control";
    case "PDSCH"
        subsystem = "downlink_data";
    case "PUSCH"
        subsystem = "uplink_data";
    case "PUCCH_UCI"
        subsystem = "uplink_control";
    case {"SRS","TRS"}
        subsystem = "reference_signal";
    case "MIMO"
        subsystem = "mimo_beamforming";
    case "MAC_HARQ"
        subsystem = "mac_harq";
    case "KPI"
        subsystem = "kpi";
    otherwise
        subsystem = lower(string(blockId));
end
end

function out = localDirectionPath(blockId)
if string(blockId) == "PDSCH"
    out = "air_interface/csv/dl_pdsch_trials.csv";
else
    out = "air_interface/csv/ul_pusch_trials.csv";
end
end

function tf = localBlockUsesOracle(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
tf = localAnyLogicalColumn(T, "OracleUsed") || ...
    localAnyNonEmptyStringColumn(T, "UsedOracleFields") || ...
    localAnyAffirmativeOracleDisclosure(T, ["Notes","FailureReason"]);
end

function tf = localBlockUsesProxy(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
tf = localAnyLogicalColumn(T, "ProxyUsed") || ...
    localAnyStringColumnContains(T, ["ApproximationMode","Notes","TruthStatus"], ["proxy","fast_proxy","logistic","lut"]);
if ~tf && blockId == "ChannelRF"
    tf = localAnyLogicalColumn(ctx.Tables.RuntimeOperatingMode, "ProxyPHYActive");
end
end

function tf = localBlockUsesFallback(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
tf = localAnyLogicalColumn(T, "FallbackUsed") || localAnyLogicalColumn(T, "FallbackFlag") || ...
    localAnyStringColumnContains(T, ["Notes","FailureReason"], "fallback");
if ~tf && blockId == "ChannelRF"
    tf = localAnyLogicalColumn(ctx.Tables.RuntimeOperatingMode, "FallbackUsed");
end
end

function tf = localBlockSkipped(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
tf = localAnyLogicalColumn(T, "Skipped") || localAnyStringColumnContains(T, ["RowLifecycleState","Status"], "skip");
end

function tf = localBlockBypassed(blockId, coverageT, evidenceT, featureEnabled)
cov = coverageT(string(coverageT.Subsystem) == string(localBlockSubsystem(blockId)), :);
ev = evidenceT(string(evidenceT.BlockId) == string(blockId), :);
tf = featureEnabled && ~any(localTableLogical(cov, "ActuallyCalled")) && any(localTableLogical(ev, "EvidencePresent"));
end

function tf = localBlockLabelOnly(ctx, blockId, evidenceT, featureEnabled)
ev = evidenceT(string(evidenceT.BlockId) == string(blockId), :);
hasRealEvidence = any(localTableLogical(ev, "EvidencePresent"));
resultOk = localScalarLogical(ctx.Tables.ScenarioSummary, "ResultOk", localScalarLogical(ctx.Tables.TruthContractSummary, "RuntimeTruthContractOk", false));
tf = featureEnabled && resultOk && ~hasRealEvidence;
end

function reason = localDetectorFailureReason(det)
if istable(det)
    if isempty(det)
        reason = "";
        return;
    end
    det = table2struct(det(1, :));
end
reasonParts = strings(0, 1);
if logical(det.ProxyUsed)
    reasonParts(end+1, 1) = "proxy_used"; %#ok<AGROW>
end
if logical(det.FallbackUsed)
    reasonParts(end+1, 1) = "fallback_used"; %#ok<AGROW>
end
if logical(det.Skipped)
    reasonParts(end+1, 1) = "skipped"; %#ok<AGROW>
end
if logical(det.Bypassed)
    reasonParts(end+1, 1) = "bypassed"; %#ok<AGROW>
end
if logical(det.LabelOnlyEvidence)
    reasonParts(end+1, 1) = "label_only_evidence"; %#ok<AGROW>
end
reason = strjoin(reasonParts, "|");
end

function [bypassed, proxyUsed, fallbackUsed, skipped] = localDetectorFlagsForBlock(ctx, blockId)
proxyUsed = localBlockUsesProxy(ctx, blockId);
fallbackUsed = localBlockUsesFallback(ctx, blockId);
skipped = localBlockSkipped(ctx, blockId);
bypassed = false;
end

function [called, callCount, totalTime, selfTime] = localFunctionCallEvidence(ctx, functionName, blockId)
called = false;
callCount = 0;
totalTime = NaN;
selfTime = NaN;
profileT = ctx.Tables.RuntimeFunctionProfile;
if localHasRows(profileT)
    nameMask = localFunctionMatchMask(profileT, functionName, ["FunctionName","CompleteName","FileName"]);
    if any(nameMask)
        called = true;
        [callCount, totalTime, selfTime] = localSummarizeProfileEvidence(profileT(nameMask, :));
        return;
    end
end
edgeT = ctx.Tables.RuntimeFunctionCallEdges;
if localHasRows(edgeT)
    nameMask = localFunctionMatchMask(edgeT, functionName, ["CalleeFunctionName","CalleeCompleteName"]);
    if any(nameMask)
        called = true;
        callCount = localSummedCount(edgeT(nameMask, :), "NumCalls");
        totalTime = localSummedTime(edgeT(nameMask, :), "TotalTime_s");
        selfTime = NaN;
        return;
    end
end
timeCoverageT = ctx.Tables.TimeProfileCoverage;
if localHasRows(timeCoverageT)
    nameMask = localFunctionMatchMask(timeCoverageT, functionName, "FunctionName");
    if any(nameMask)
        executedMask = nameMask;
        if ismember("CoverageStatus", string(timeCoverageT.Properties.VariableNames))
            executedMask = executedMask & lower(strtrim(string(timeCoverageT.CoverageStatus))) == "executed";
        end
        if any(executedMask)
            called = true;
            callCount = localSummedCount(timeCoverageT(executedMask, :), "ExecutedCallCount");
            totalTime = NaN;
            selfTime = NaN;
            return;
        end
    end
end
timeCallsT = ctx.Tables.TimeProfileCalls;
if localHasRows(timeCallsT)
    nameMask = localFunctionMatchMask(timeCallsT, functionName, "FunctionName");
    if any(nameMask)
        executedMask = nameMask;
        if ismember("Status", string(timeCallsT.Properties.VariableNames))
            executedMask = executedMask & lower(strtrim(string(timeCallsT.Status))) == "executed";
        end
        if any(executedMask)
            called = true;
            callCount = double(nnz(executedMask));
            totalTime = localSummedTime(timeCallsT(executedMask, :), "Elapsed_s");
            selfTime = NaN;
            return;
        end
    end
end
edgeT = ctx.Tables.RuntimeFunctionCallEdges;
if localHasRows(edgeT)
    % A direct callee match is strongest; a caller match still proves the
    % function executed even when MATLAB attributes child work separately.
    nameMask = localFunctionMatchMask(edgeT, functionName, ["CallerFunctionName","CallerCompleteName"]);
    if any(nameMask)
        called = true;
        callCount = localSummedCount(edgeT(nameMask, :), "NumCalls");
        totalTime = localSummedTime(edgeT(nameMask, :), "TotalTime_s");
        selfTime = NaN;
        return;
    end
end
stageT = ctx.Tables.LiveStageTrace;
switch string(functionName)
    case {"sixgr.phy.dl.PDSCH_Tx","sixgr.phy.dl.PDSCH_Rx","sixgr.phy.ul.PUSCH_Tx","sixgr.phy.ul.PUSCH_Rx"}
        field = localTernary(contains(functionName, "_Tx"), "TxChainKernel", "RxChainKernel");
        if localHasRows(stageT) && ismember(field, string(stageT.Properties.VariableNames))
            mask = string(stageT.(field)) == string(functionName);
            called = any(mask);
            callCount = sum(double(mask));
            return;
        end
end
primary = localBlockPrimaryTable(ctx, blockId);
if localFunctionRequiresExplicitCallEvidence(functionName)
    called = false;
    callCount = 0;
    return;
end
called = localHasRows(primary);
callCount = height(primary);
end

function [callCount, totalTime, selfTime] = localSummarizeProfileEvidence(T)
callCount = localSummedCount(T, "NumCalls");
totalTime = localSummedTime(T, "TotalTime_s");
selfTime = localSummedTime(T, "SelfTimeApprox_s");
end

function count = localSummedCount(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    count = double(height(T));
else
    count = sum(vals);
end
end

function seconds = localSummedTime(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    seconds = NaN;
else
    seconds = sum(vals);
end
end

function mask = localFunctionMatchMask(T, functionName, columnNames)
mask = false(height(T), 1);
if ~(istable(T) && ~isempty(T))
    return;
end
tokens = localFunctionSearchTokens(functionName);
columnNames = string(columnNames);
vars = string(T.Properties.VariableNames);
for i = 1:numel(columnNames)
    if ~ismember(columnNames(i), vars)
        continue;
    end
    txt = lower(strtrim(string(T.(char(columnNames(i))))));
    for j = 1:numel(tokens)
        mask = mask | contains(txt, tokens(j));
    end
end
end

function tokens = localFunctionSearchTokens(functionName)
name = lower(strtrim(string(functionName)));
parts = split(name, ".");
leaf = parts(end);
tokens = [name; leaf; leaf + ".m"; replace(name, ".", "/") + ".m"; replace(name, ".", "\") + ".m"];
if numel(parts) > 1
    pkgParts = "+" + parts(1:end-1);
    plusSlash = strjoin(pkgParts, "/") + "/" + leaf + ".m";
    plusBackslash = strjoin(pkgParts, "\") + "\" + leaf + ".m";
    tokens = [tokens; plusSlash; plusBackslash]; %#ok<AGROW>
end
tokens = unique(tokens(strlength(tokens) > 0), "stable");
end

function tf = localFunctionRequiresExplicitCallEvidence(functionName)
% A primary result row proves that some producer wrote evidence; it does
% not prove that a particular PHY/link/spatial implementation executed.
% These packages therefore require profiler or call-edge evidence and may
% never fall back to "artifact exists, therefore implementation ran".
strictPrefixes = [ ...
    "sixgr.phy."; ...
    "sixgr.channel."; ...
    "sixgr.mimo."; ...
    "sixgr.pdsch."; ...
    "sixgr.pusch."; ...
    "sixgr.link."; ...
    "sixgr.rach."; ...
    "sixgr.truth.exportControlPlaneTraces" ...
    ];
name = lower(strtrim(string(functionName)));
tf = false;
for i = 1:numel(strictPrefixes)
    if startsWith(name, lower(strictPrefixes(i)))
        tf = true;
        return;
    end
end
end

function count = localBlockEvidenceRowCount(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
count = double(height(T));
end

function T = localBlockPrimaryTable(ctx, blockId)
switch string(blockId)
    case "MobilityDoppler"
        T = localFirstNonEmpty({ctx.Tables.LiveChannelState, ctx.Tables.LiveMobility});
    case "ChannelRF"
        T = localFirstNonEmpty({ctx.Tables.LiveChannelState, ctx.Tables.ChannelRFValidation});
    case "SSB_PBCH_MIB"
        T = localFirstNonEmpty({ctx.Tables.PBCHRecoveryTrials, ctx.Tables.PBCHTrials});
    case "SIB1"
        T = ctx.Tables.SIB1Recovery;
    case "PRACH"
        T = localFirstNonEmpty({ctx.Tables.PRACHTrialsStrict, ctx.Tables.PRACHTrialsAir});
    case "PDCCH"
        T = localFirstNonEmpty({ctx.Tables.PDCCHTrialsStrict, ctx.Tables.PDCCHTrials});
    case "PDSCH"
        T = ctx.Tables.DLTrials;
    case "PUSCH"
        T = ctx.Tables.ULTrials;
    case "PUCCH_UCI"
        T = ctx.Tables.PUCCHTrials;
    case "SRS"
        T = localFirstNonEmpty({ctx.Tables.SRSStrictTrials, ctx.Tables.SRSTrialsAir});
    case "TRS"
        T = localFirstNonEmpty({ctx.Tables.TRSStrictTrials, ctx.Tables.TRSTrialsAir});
    case "MIMO"
        T = localFirstNonEmpty({ctx.Tables.RankLayerTrials, ctx.Tables.BeamManagement});
    case "MAC_HARQ"
        T = localFirstNonEmpty({ctx.Tables.HARQTimeline, ctx.Tables.HARQProcessTimeline});
    case "KPI"
        T = localFirstNonEmpty({ctx.Tables.LiveUserPerformance, ctx.Tables.LiveErrorRate});
    otherwise
        T = table();
end
end

function flags = localEvidenceFlags(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
flags = struct("waveform", false, "grid", false, "bit", false, "decoder", false, "channel", false, "timing", false, "frequency", false);
if isempty(T)
    return;
end
flags.waveform = localHasRows(T) && any(ismember(["TruthStatus","RuntimeEvidenceStatus","PrimaryTruthValueStatus"], string(T.Properties.VariableNames)));
flags.grid = any(ismember(["AllocatedPRBCount","PRBStart","DataRECount","SRSOccupiedPRBCount"], string(T.Properties.VariableNames)));
flags.bit = any(ismember(["TBSize_bits","BitsCompared","BitErrors","PayloadHashRx"], string(T.Properties.VariableNames)));
flags.decoder = any(ismember(["CRCPass","DLSCHDecodeAvailable","ULSCHDecodeAvailable","DecodeUsable"], string(T.Properties.VariableNames)));
flags.channel = any(ismember(["ChannelEstimateAvailable","NMSE_dB","Pathloss_dB","PropagationDistance_m"], string(T.Properties.VariableNames)));
flags.timing = any(ismember(["TimingError_samples","TimingOffset_samples","GeometricPropagationDelay_s"], string(T.Properties.VariableNames)));
flags.frequency = any(ismember(["DopplerHz","InjectedCFO_Hz","EstimatedCFO_Hz"], string(T.Properties.VariableNames)));
end

function sources = localEvidenceSources(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId); %#ok<NASGU>
sources = struct( ...
    "waveform", localEvidenceSource(blockId, "waveform"), ...
    "grid", localEvidenceSource(blockId, "grid"), ...
    "bit", localEvidenceSource(blockId, "bit"), ...
    "decoder", localEvidenceSource(blockId, "decoder"), ...
    "channel", localEvidenceSource(blockId, "channel"), ...
    "timing", localEvidenceSource(blockId, "timing"), ...
    "frequency", localEvidenceSource(blockId, "frequency"));
end

function counts = localEvidenceCounts(ctx, blockId)
T = localBlockPrimaryTable(ctx, blockId);
count = double(height(T));
counts = struct("waveform", count, "grid", count, "bit", count, "decoder", count, "channel", count, "timing", count, "frequency", count);
end

function out = localEvidenceSource(blockId, evidenceType)
switch string(blockId)
    case "PDSCH"
        out = "air_interface/csv/dl_pdsch_trials.csv";
    case "PUSCH"
        out = "air_interface/csv/ul_pusch_trials.csv";
    case "PDCCH"
        out = "control/csv/pdcch_trials.csv";
    case "PRACH"
        out = "control/csv/prach_trials.csv";
    case "SRS"
        out = "reference_signals/csv/srs_trials.csv";
    case "TRS"
        out = "reference_signals/csv/trs_trials.csv";
    case "ChannelRF"
        out = "reports/csv/live_channel_state_tti.csv";
    case "MobilityDoppler"
        out = localTernary(evidenceType == "channel", "reports/csv/live_channel_state_tti.csv", "reports/csv/live_rsrp_serving_trace.csv");
    case "MAC_HARQ"
        out = "harq/csv/live_harq_observation_timeline.csv";
    case "KPI"
        out = "reports/csv/live_error_rate_summary.csv";
    otherwise
        out = "";
end
end

function tf = localEvidenceTypePresent(ev, evidenceType)
if isempty(ev)
    tf = false;
    return;
end
mask = string(ev.EvidenceType) == string(evidenceType);
tf = any(localTableLogical(ev(mask, :), "EvidencePresent"));
end

function T = localDirectionTrials(ctx, direction)
if string(direction) == "DL"
    T = ctx.Tables.DLTrials;
else
    T = ctx.Tables.ULTrials;
end
end

function value = localConfigOrTableSpeed(ctx, T, idx)
value = localTableNumber(T, idx, "Speed_kmh", NaN);
if ~isfinite(value)
    value = ctx.ConfiguredSpeedKmh;
end
end

function out = localComposeRunId(runFolder, scenarioId)
[~, leafName] = fileparts(char(string(runFolder)));
out = string(scenarioId) + "__" + string(leafName);
end

function out = localScenarioText(scfg, cfg, key, defaultValue)
out = string(defaultValue);
parts = string(key);
for i = 1:numel(parts)
    try
        if isobject(scfg) && ismethod(scfg, "get")
            val = scfg.get(char(parts(i)), []);
        else
            val = [];
        end
    catch
        val = [];
    end
    if isempty(val) && isstruct(scfg)
        val = sixgr.util.structGet(scfg, char(parts(i)), []);
    end
    if ~isempty(val)
        out = string(val);
        return;
    end
    val = sixgr.util.structGet(cfg, char(parts(i)), []);
    if ~isempty(val)
        out = string(val);
        return;
    end
end
end

function out = localScenarioNumber(scfg, cfg, keys, defaultValue)
out = double(defaultValue);
for i = 1:numel(keys)
    key = char(string(keys(i)));
    val = [];
    try
        if isobject(scfg) && ismethod(scfg, "get")
            val = scfg.get(key, []);
        end
    catch
        val = [];
    end
    if isempty(val) && isstruct(scfg)
        val = sixgr.util.structGet(scfg, key, []);
    end
    if isempty(val)
        val = sixgr.util.structGet(cfg, key, []);
    end
    if isempty(val)
        continue;
    end
    try
        out = double(val);
    catch
        out = str2double(string(val));
    end
    if isfinite(out)
        return;
    end
end
out = double(defaultValue);
end

function out = localScenarioBool(scfg, cfg, keys, defaultValue)
out = logical(defaultValue);
for i = 1:numel(keys)
    key = char(string(keys(i)));
    val = [];
    try
        if isobject(scfg) && ismethod(scfg, "get")
            val = scfg.get(key, []);
        end
    catch
        val = [];
    end
    if isempty(val) && isstruct(scfg)
        val = sixgr.util.structGet(scfg, key, []);
    end
    if isempty(val)
        val = sixgr.util.structGet(cfg, key, []);
    end
    if isempty(val)
        continue;
    end
    try
        out = logical(val);
    catch
        out = any(lower(strtrim(string(val))) == ["1","true","yes","on","pass"]);
    end
    return;
end
end

function T = localReadOptionalTable(pathValue)
T = table();
if exist(pathValue, "file") ~= 2
    return;
end
try
    T = readtable(pathValue, "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function tf = localHasRows(T)
tf = istable(T) && ~isempty(T);
end

function out = localRelativePath(runFolder, pathValue)
runFolder = string(runFolder);
pathValue = string(pathValue);
pathNorm = replace(pathValue, "\", "/");
rootNorm = replace(runFolder, "\", "/");
if startsWith(lower(pathNorm), lower(rootNorm + "/"))
    out = extractAfter(pathNorm, strlength(rootNorm) + 1);
else
    out = pathNorm;
end
end

function out = localRegistryValue(registry, blockId, fieldName, defaultValue)
mask = string(registry.BlockId) == string(blockId);
if ~any(mask)
    out = defaultValue;
    return;
end
out = registry.(fieldName)(find(mask, 1, "first"));
end

function row = localEmptyRegistryRow()
row = struct("BlockId", "", "Subsystem", "", "SpecReference", "", "FeatureEnabled", false, ...
    "MandatoryForScenario", false, "ExpectedFunctions", strings(0, 1), "InputArtifact", "", "OutputArtifact", "", "PrimaryArtifact", "");
end

function row = localRegistryRow(blockId, subsystem, specReference, enabled, mandatory, expectedFunctions, inputArtifact, outputArtifact, primaryArtifact)
row = localEmptyRegistryRow();
row.BlockId = string(blockId);
row.Subsystem = string(subsystem);
row.SpecReference = string(specReference);
row.FeatureEnabled = logical(enabled);
row.MandatoryForScenario = logical(mandatory);
row.ExpectedFunctions = string(expectedFunctions(:));
row.InputArtifact = string(inputArtifact);
row.OutputArtifact = string(outputArtifact);
row.PrimaryArtifact = string(primaryArtifact);
end

function row = localEmptyComparisonRow()
row = struct("RunId", "", "BlockId", "", "Subsystem", "", "TrialId", NaN, "UEId", NaN, "Slot", NaN, ...
    "InputConfigHash", "", "InputSignalHash", "", "DUTOutputName", "", "ReferenceOutputName", "", ...
    "DUTValue", NaN, "ReferenceValue", NaN, "DeltaAbs", NaN, "DeltaRel", NaN, ...
    "ToleranceAbs", NaN, "ToleranceRel", NaN, "ComparisonType", "", "Pass", false, ...
    "ReferenceSource", "", "ReferenceAvailable", false, "DUTArtifactPath", "", "ReferenceArtifactPath", "", "FailureReason", "");
end

function row = localComparisonRecord(runId, blockId, subsystem, trialId, ueId, slot, configHash, signalHash, dutName, refName, dutValue, refValue, deltaAbs, deltaRel, tolAbs, tolRel, cmpType, refSource, dutArtifact, refArtifact, failureReason)
row = localEmptyComparisonRow();
row.RunId = string(runId);
row.BlockId = string(blockId);
row.Subsystem = string(subsystem);
row.TrialId = double(trialId);
row.UEId = double(ueId);
row.Slot = double(slot);
row.InputConfigHash = string(configHash);
row.InputSignalHash = string(signalHash);
row.DUTOutputName = string(dutName);
row.ReferenceOutputName = string(refName);
row.DUTValue = double(dutValue);
row.ReferenceValue = double(refValue);
row.DeltaAbs = double(deltaAbs);
row.DeltaRel = double(deltaRel);
row.ToleranceAbs = double(tolAbs);
row.ToleranceRel = double(tolRel);
row.ComparisonType = string(cmpType);
row.Pass = isfinite(row.DeltaAbs) && row.DeltaAbs <= row.ToleranceAbs + eps || ...
    isfinite(row.DeltaRel) && row.DeltaRel <= row.ToleranceRel + eps;
row.ReferenceSource = string(refSource);
row.ReferenceAvailable = string(refSource) ~= "reference_path_unavailable";
row.DUTArtifactPath = string(dutArtifact);
row.ReferenceArtifactPath = string(refArtifact);
row.FailureReason = string(localTernary(row.Pass, failureReason, localTernary(strlength(strtrim(string(failureReason))) > 0, failureReason, "dut_reference_mismatch")));
end

function row = localEmptyInvariantRow()
row = struct("RunId", "", "CheckId", "", "Subsystem", "", "MetricName", "", "TrialId", NaN, "UEId", NaN, "Slot", NaN, ...
    "ObservedValue", NaN, "ExpectedMin", NaN, "ExpectedMax", NaN, "ExpectedValue", NaN, "Tolerance", NaN, ...
    "Pass", false, "Severity", "", "BlocksResultOk", false, "FailureReason", "", "RecommendedFix", "");
end

function row = localInvariantRecord(runId, checkId, subsystem, metricName, trialId, ueId, slot, observed, minExpected, maxExpected, expected, tolerance, pass, severity, failureReason, recommendedFix)
row = localEmptyInvariantRow();
row.RunId = string(runId);
row.CheckId = string(checkId);
row.Subsystem = string(subsystem);
row.MetricName = string(metricName);
row.TrialId = double(trialId);
row.UEId = double(ueId);
row.Slot = double(slot);
row.ObservedValue = double(observed);
row.ExpectedMin = double(minExpected);
row.ExpectedMax = double(maxExpected);
row.ExpectedValue = double(expected);
row.Tolerance = double(tolerance);
row.Pass = logical(pass);
row.Severity = string(severity);
row.BlocksResultOk = logical(pass);
row.FailureReason = string(failureReason);
row.RecommendedFix = string(recommendedFix);
end

function row = localEmptyCoverageRow()
row = struct("RunId", "", "FunctionName", "", "FilePath", "", "Subsystem", "", "ExpectedForScenario", false, ...
    "ActuallyCalled", false, "CallCount", 0, "TotalTimeSeconds", NaN, "SelfTimeSeconds", NaN, ...
    "InputArtifactSeen", false, "OutputArtifactSeen", false, "EvidenceRowsProduced", 0, "RequiredEvidenceProduced", false, ...
    "Bypassed", false, "ProxyUsed", false, "FallbackUsed", false, "Skipped", false, ...
    "ImplementationCoveragePass", false, "BlocksResultOk", false, "IssueIdIfFailed", "", "FailureReason", "");
end

function row = localEmptyEvidenceRow()
row = struct("RunId", "", "BlockId", "", "EvidenceType", "", "EvidencePresent", false, "SourceArtifact", "", "EvidenceRows", 0, "Notes", "");
end

function row = localEmptyDetectorRow()
row = struct("RunId", "", "BlockId", "", "OracleUsed", false, "ProxyUsed", false, "FallbackUsed", false, ...
    "Skipped", false, "Bypassed", false, "LabelOnlyEvidence", false, "DetectionSource", "", "FailureReason", "");
end

function row = localEmptyMatrixRow()
row = struct("RunId", "", "ScenarioName", "", "BlockId", "", "Subsystem", "", "SpecReference", "", ...
    "FeatureEnabled", false, "MandatoryForScenario", false, "DUTFunctionExpected", "", "DUTFunctionActuallyCalled", false, ...
    "DUTCallCount", 0, "DUTRuntimeSeconds", NaN, "DUTInputArtifact", "", "DUTOutputArtifact", "", ...
    "ReferenceAvailable", false, "ReferenceFunction", "", "ReferenceArtifact", "", "DUTReferenceCompared", false, ...
    "ComparisonMetric", "", "Tolerance", "", "Delta", "", "NumericalSanityPass", false, "NegativeTestPass", false, ...
    "OracleUsed", false, "ProxyUsed", false, "FallbackUsed", false, "Skipped", false, "Bypassed", false, "LabelOnlyEvidence", false, ...
    "WaveformEvidencePresent", false, "GridEvidencePresent", false, "BitEvidencePresent", false, "DecoderEvidencePresent", false, ...
    "ChannelEvidencePresent", false, "TimingEvidencePresent", false, "FrequencyEvidencePresent", false, ...
    "ImplementationPass", false, "BlocksResultOk", false, "IssueIdIfFailed", "", "FailureReason", "", "RecommendedFix", "");
end

function row = localEmptyPHYOutcomeRow()
row = struct("RunId", "", "Subsystem", "", "Feature", "", "Enabled", false, "ImplementedForScenario", false, ...
    "ActualRuntimePathUsed", false, "ReferenceCompared", false, "NumericalValuesPlausible", false, "NegativeTestsPassed", false, ...
    "DecoderOutputsPresent", false, "ChannelEstimationOutputsPresent", false, "FunctionCoveragePass", false, "BypassDetected", false, ...
    "OverallBlockPass", false, "BlocksResultOk", false, "IssueIds", "", "FailureReason", "");
end

function row = localEmptyLinkPerformanceRow()
row = struct("RunId", "", "Direction", "", "UEId", NaN, "DistanceStart_m", NaN, "DistanceEnd_m", NaN, ...
    "Speed_kmh", NaN, "DopplerHz", NaN, "MeanSINRdB", NaN, "MinSINRdB", NaN, "MaxSINRdB", NaN, ...
    "MeanMCS", NaN, "MinMCS", NaN, "MaxMCS", NaN, "MeanLayers", NaN, "MaxLayers", NaN, "RawBLER", NaN, ...
    "RawBER", NaN, "ThroughputMbps", NaN, "GoodputMbps", NaN, "HARQRetxRate", NaN, "PacketLossRate", NaN, ...
    "LatencyMeanMs", NaN, "OutcomePass", false, "FailureReason", "");
end

function row = localEmptyBlockCorrectnessRow()
row = struct("RunId", "", "BlockId", "", "Subsystem", "", "DUTCalled", false, "ReferenceAvailable", false, ...
    "DUTReferencePass", false, "InvariantPass", false, "NegativePass", false, "EvidenceComplete", false, ...
    "ImplementationPass", false, "ResultContribution", "", "FailureReason", "");
end

function row = localEmptyReferenceSummaryRow()
row = struct("RunId", "", "BlockId", "", "ReferenceAvailable", false, "ComparisonCount", 0, "PassCount", 0, ...
    "FailCount", 0, "DUTReferencePass", false, "ReferenceSources", "", "MaxAbsDelta", NaN, "FailureReason", "");
end

function row = localEmptyCoverageSummaryRow()
row = struct("RunId", "", "Subsystem", "", "ExpectedFunctions", 0, "ActuallyCalledFunctions", 0, ...
    "CoveragePass", false, "BypassDetected", false, "ProxyDetected", false, "FallbackDetected", false, "FailureReason", "");
end

function row = localEmptyFindingRow()
row = struct("MetricName", "", "Value", NaN, "DisplayValue", "", "Units", "", "SourceArtifact", "");
end

function row = localFindingRow(metricName, value, displayValue, units, sourceArtifact)
row = localEmptyFindingRow();
row.MetricName = string(metricName);
row.Value = double(value);
if strlength(strtrim(string(displayValue))) == 0
    if isfinite(double(value))
        row.DisplayValue = string(num2str(double(value), "%.6g"));
    else
        row.DisplayValue = "NaN";
    end
else
    row.DisplayValue = string(displayValue);
end
row.Units = string(units);
row.SourceArtifact = string(sourceArtifact);
end

function out = localExpectedFunctionFile(functionName)
out = replace(string(functionName), ".", "/") + ".m";
end

function out = localDelimitedSummary(T, names)
parts = strings(0, 1);
for i = 1:numel(names)
    vals = localNumericColumn(T, names(i));
    vals = vals(isfinite(vals));
    if isempty(vals)
        continue;
    end
    parts(end+1, 1) = string(names(i)) + "=" + string(num2str(max(vals), "%.6g")); %#ok<AGROW>
end
out = strjoin(parts, " | ");
end

function out = localScalarText(T, name, defaultValue)
out = string(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
out = string(T.(name)(1));
end

function out = localScalarLogical(T, name, defaultValue)
out = logical(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
out = localTableLogicalValue(T, 1, name, defaultValue);
end

function values = localTableLogical(T, name)
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    values = false(height(T), 1);
    return;
end
values = localOptionalLogicalColumn(T, name, false(height(T), 1));
end

function values = localNumericColumn(T, name)
values = [];
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = T.(name);
try
    values = double(raw);
catch
    values = str2double(string(raw));
end
values = values(:);
end

function values = localOptionalLogicalColumn(T, name, defaultValue)
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    values = defaultValue;
    return;
end
raw = T.(name);
if islogical(raw)
    values = raw;
elseif isnumeric(raw)
    num = double(raw);
    values = isfinite(num) & num ~= 0;
else
    txt = lower(strtrim(string(raw)));
    values = ismember(txt, ["1","true","yes","on","pass"]);
end
values = values(:);
end

function tf = localAnyLogicalColumn(T, name)
tf = false;
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
vals = localOptionalLogicalColumn(T, name, false(height(T), 1));
tf = any(vals);
end

function tf = localAnyStringColumnContains(T, names, patterns)
tf = false;
if ~(istable(T) && ~isempty(T))
    return;
end
names = string(names);
patterns = string(patterns);
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    txt = lower(string(T.(char(names(i)))));
    for j = 1:numel(patterns)
        if any(contains(txt, lower(patterns(j))))
            tf = true;
            return;
        end
    end
end
end

function tf = localAnyNonEmptyStringColumn(T, name)
tf = false;
if ~(istable(T) && ~isempty(T) && ...
        ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
values = lower(strtrim(string(T.(char(name)))));
missing = ismissing(values) | values == "" | ...
    ismember(values, ["none","n/a","na","not_applicable","not applicable","[]"]);
tf = any(~missing);
end

function tf = localAnyAffirmativeOracleDisclosure(T, names)
% Free-text provenance may explicitly state that an oracle was not used.
% Treat only affirmative disclosures as oracle use; structured OracleUsed
% and UsedOracleFields columns remain the primary fail-closed authorities.
tf = false;
if ~(istable(T) && ~isempty(T))
    return;
end
affirmativePatterns = [ ...
    "oracle_used", "oracle used", "used oracle", "oracle-assisted", ...
    "oracle assisted", "oracle=true", "oracle = true", "oracle: true", ...
    "receiver oracle", "geometry oracle"];
negativePatterns = [ ...
    "oracle-free", "oracle free", "oracle_free", "without oracle", ...
    "no oracle", "oracle=false", "oracle = false", "oracle: false", ...
    "oracle not used", "not use oracle"];
names = string(names);
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    values = lower(string(T.(char(names(i)))));
    for rowIdx = 1:numel(values)
        value = values(rowIdx);
        if ismissing(value) || value == ""
            continue;
        end
        for j = 1:numel(negativePatterns)
            value = replace(value, negativePatterns(j), "");
        end
        if any(contains(value, affirmativePatterns))
            tf = true;
            return;
        end
    end
end
end

function value = localTableNumber(T, idx, name, defaultValue)
value = double(defaultValue);
if ~(istable(T) && height(T) >= idx && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
try
    value = double(T.(name)(idx));
catch
    value = str2double(string(T.(name)(idx)));
end
end

function value = localTableText(T, idx, name, defaultValue)
value = string(defaultValue);
if ~(istable(T) && height(T) >= idx && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
value = string(T.(name)(idx));
end

function value = localTableTextFirstPresent(T, idx, names, defaultValue)
value = string(defaultValue);
for i = 1:numel(names)
    if ismember(string(names(i)), string(T.Properties.VariableNames))
        value = string(T.(char(names(i)))(idx));
        return;
    end
end
end

function value = localTableLogicalValue(T, idx, name, defaultValue)
value = logical(defaultValue);
if ~(istable(T) && height(T) >= idx && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
try
    value = logical(T.(name)(idx));
catch
    value = any(lower(strtrim(string(T.(name)(idx)))) == ["1","true","yes","on","pass"]);
end
end

function idx = localRepresentativeRowIndices(T, maxRows)
idx = [];
if isempty(T)
    return;
end
n = height(T);
if n <= maxRows
    idx = (1:n).';
    return;
end
idx = unique(round(linspace(1, n, maxRows))).';
end

function out = localFirstNonEmpty(tables)
out = table();
for i = 1:numel(tables)
    if localHasRows(tables{i})
        out = tables{i};
        return;
    end
end
end

function out = localRelativeError(a, b)
den = max(abs(double(b)), 1e-12);
out = abs(double(a) - double(b)) ./ den;
end

function out = localMeanNumeric(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = mean(vals, "omitnan");
end
end

function out = localMeanNumericFallback(T, names)
out = NaN;
for i = 1:numel(names)
    out = localMeanNumeric(T, names(i));
    if isfinite(out)
        return;
    end
end
end

function out = localMedianColumn(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = median(vals, "omitnan");
end
end

function out = localMeanAbsColumn(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = mean(abs(vals), "omitnan");
end
end

function out = localResidualCFOMean(T)
inj = localNumericColumn(T, "InjectedCFO_Hz");
est = localNumericColumn(T, "EstimatedCFO_Hz");
mask = isfinite(inj) & isfinite(est);
if ~any(mask)
    out = NaN;
else
    out = mean(abs(inj(mask) - est(mask)), "omitnan");
end
end

function out = localMinNumeric(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = min(vals);
end
end

function out = localMaxNumeric(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = max(vals);
end
end

function out = localFirstNumeric(T, name, defaultValue)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = defaultValue;
else
    out = vals(1);
end
end

function out = localLastNumeric(T, name, defaultValue)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
if isempty(vals)
    out = defaultValue;
else
    out = vals(end);
end
end

function out = localBLER(T)
crc = localOptionalLogicalColumn(T, "CRCPass", false(height(T), 1));
if isempty(crc)
    out = NaN;
else
    out = 1 - mean(double(crc), "omitnan");
end
end

function out = localBER(T)
bitErr = localNumericColumn(T, "BitErrors");
bits = localNumericColumn(T, "BitsCompared");
mask = isfinite(bitErr) & isfinite(bits) & bits > 0;
if ~any(mask)
    out = NaN;
else
    out = sum(bitErr(mask), "omitnan") ./ sum(bits(mask), "omitnan");
end
end

function out = localPacketLossRate(T)
crc = localOptionalLogicalColumn(T, "CRCPass", false(height(T), 1));
if isempty(crc)
    out = NaN;
else
    out = 1 - mean(double(crc), "omitnan");
end
end

function out = localHARQRetxRate(ctx, direction, ueId)
T = ctx.Tables.HARQTimeline;
if isempty(T)
    T = ctx.Tables.HARQProcessTimeline;
end
if isempty(T)
    out = NaN;
    return;
end
if isfinite(ueId) && ismember("UEID", string(T.Properties.VariableNames))
    T = localFilterByNumeric(T, "UEID", ueId);
end
if ismember("Direction", string(T.Properties.VariableNames))
    T = T(string(T.Direction) == string(direction), :);
end
retx = localOptionalLogicalColumn(T, "RetxFlag", false(height(T), 1));
if isempty(retx)
    out = NaN;
else
    out = mean(double(retx), "omitnan");
end
end

function T = localFilterByNumeric(T, name, value)
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)) && isfinite(value))
    return;
end
vals = localNumericColumn(T, name);
mask = isfinite(vals) & abs(vals - value) < 1e-9;
T = T(mask, :);
end

function out = localUniqueValues(T, name)
vals = localNumericColumn(T, name);
vals = vals(isfinite(vals));
out = unique(vals, "stable");
end

function out = localArtifactsExist(runFolder, artifactList)
parts = split(string(artifactList), "|");
parts = strtrim(parts);
parts = parts(strlength(parts) > 0);
if isempty(parts)
    out = false;
    return;
end
tf = false(size(parts));
for i = 1:numel(parts)
    tf(i) = exist(fullfile(char(string(runFolder)), char(parts(i))), "file") == 2;
end
out = any(tf);
end

function out = localTernary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
