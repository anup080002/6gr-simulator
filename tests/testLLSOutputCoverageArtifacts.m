function ok = testLLSOutputCoverageArtifacts()
%TESTLLSOUTPUTCOVERAGEARTIFACTS Guard output registry, PRB, energy, and unavailable metadata.

setup6GRSimToolkit("Verbose", false);
sixgr.db.deactivateArtifactStore();

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
runFolder = fullfile(tmp, "coverage_run");
layout = sixgr.report.resultLayout(runFolder);
localCreateSourceArtifacts(layout);

scfg = struct();
scfg.ScenarioID = "SCN00_BASELINE_CAPACITY";
scfg.ConfigHash = "unit_hash";

cfg = struct();
cfg.run.runTag = "unit_output_coverage";
cfg.frequency.center_frequency_hz = 4.0e9;
cfg.frequency.bandwidth_hz = 100.0e6;
cfg.frequency.n_size_grid = 273;
cfg.energy.txPower_dBm = 23;
cfg.baseStation.noiseFigure_dB = 5;
cfg.baseStation.implementationLoss_dB = 2;
cfg.baseStation.numTxRU = 64;
cfg.baseStation.numRxRU = 64;
cfg.userEquipment.txPower_dBm = 23;
cfg.userEquipment.noiseFigure_dB = 7;
cfg.system.scheduler.type = "PF";
cfg.channel.spatialConsistencyEnable = true;
cfg.channel.updatePeriod_ms = 1;

out = sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg);
assert(isfield(out, "TableSummaries") && istable(out.TableSummaries) && height(out.TableSummaries) > 0, ...
    "Output-coverage exporter must return compact table summaries for MAT-safe post-run packaging.");
assert(isfield(out, "Tables") && isempty(fieldnames(out.Tables)), ...
    "Output-coverage exporter must not retain full runtime tables in its returned struct once canonical CSV artifacts have been written.");

registryPath = fullfile(layout.ReportCSVDir, "output_coverage_registry.csv");
implementationRegisterPath = fullfile(layout.ReportCSVDir, "lls_implementation_register.csv");
unavailablePath = fullfile(layout.ReportCSVDir, "honest_unavailable_registry.csv");
energyPath = fullfile(layout.RFCSVDir, "power_energy_table.csv");
livePowerPath = fullfile(layout.ReportCSVDir, "live_power_runtime_table.csv");
liveRFPath = fullfile(layout.ReportCSVDir, "live_rf_power_table.csv");
liveBBPath = fullfile(layout.ReportCSVDir, "live_bb_power_table.csv");
liveEnergyEffPath = fullfile(layout.ReportCSVDir, "live_energy_efficiency_table.csv");
liveSleepPath = fullfile(layout.ReportCSVDir, "live_sleep_state_table.csv");
powerAnalyticsPath = fullfile(runFolder, "analytics", "csv", "power_analytics.csv");
energyEffAnalyticsPath = fullfile(runFolder, "analytics", "csv", "energy_efficiency_analytics.csv");
runtimePowerAnalyticsPath = fullfile(runFolder, "analytics", "csv", "runtime_power_analytics.csv");
sleepAnalyticsPath = fullfile(runFolder, "analytics", "csv", "sleep_state_analytics.csv");
prbPath = fullfile(layout.PacketFlowCSVDir, "live_prb_allocation.csv");
heatmapPath = fullfile(layout.ReportCSVDir, "prb_allocation_heatmap.csv");
dlHeatmapPath = fullfile(layout.ReportCSVDir, "dl_resource_grid_heatmap.csv");
ulHeatmapPath = fullfile(layout.ReportCSVDir, "ul_resource_grid_heatmap.csv");
topologyDensityPath = fullfile(layout.ReportCSVDir, "topology_density_table.csv");
sectorUtilizationPath = fullfile(layout.ReportCSVDir, "sector_utilization_summary_table.csv");
servingPopulationPath = fullfile(layout.ReportCSVDir, "serving_cell_population_table.csv");
schedulerDecisionPath = fullfile(layout.PacketFlowCSVDir, "table_scheduler_decision.csv");
latencyPath = fullfile(layout.ReportCSVDir, "table_latency.csv");
latencyCDFPath = fullfile(layout.ReportCSVDir, "latency_cdf_plot.csv");
comparePath = fullfile(layout.ReportCSVDir, "compare_run_prerequisites.csv");
issuePath = fullfile(layout.ReportCSVDir, "result_issue_registry.csv");
kpiHealthPath = fullfile(layout.ReportCSVDir, "kpi_health_flags.csv");
anomalyPath = fullfile(layout.ReportCSVDir, "anomaly_window_table.csv");
crossLayerPath = fullfile(layout.ReportCSVDir, "cross_layer_correlation_table.csv");
hotspotPath = fullfile(layout.ReportCSVDir, "hotspot_analytics_table.csv");
controlOverheadPath = fullfile(layout.ReportCSVDir, "control_overhead_analytics_table.csv");
resourceOverheadPath = fullfile(layout.ReportCSVDir, "resource_overhead_analytics_table.csv");
latencyRootCausePath = fullfile(layout.ReportCSVDir, "latency_root_cause_table.csv");
pdcchPath = fullfile(layout.ControlCSVDir, "pdcch_dci_table.csv");
pbchPath = fullfile(layout.ControlCSVDir, "ssb_pbch_table.csv");
prachPath = fullfile(layout.ControlCSVDir, "prach_table.csv");
pucchPath = fullfile(layout.ControlCSVDir, "pucch_table.csv");
pdschPath = fullfile(layout.ControlCSVDir, "pdsch_table.csv");
puschPath = fullfile(layout.ControlCSVDir, "pusch_table.csv");
srsPath = fullfile(layout.ControlCSVDir, "srs_table.csv");
csiRsPath = fullfile(layout.ControlCSVDir, "csi_rs_table.csv");
trsTrackingPath = fullfile(layout.ControlCSVDir, "trs_receiver_tracking_table.csv");
beamPrecoderPath = fullfile(layout.BeamformingCSVDir, "beam_precoder_table.csv");
beamAnalyticsPath = fullfile(layout.BeamformingCSVDir, "beamforming_analytics_table.csv");
mimoRankPath = fullfile(layout.BeamformingCSVDir, "mimo_rank_utilization_table.csv");
rankHistogramPath = fullfile(layout.BeamformingCSVDir, "rank_layer_usage_histogram.csv");
timingPath = fullfile(layout.ControlCSVDir, "timing_synchronization_table.csv");
dopplerPath = fullfile(layout.ReportCSVDir, "doppler_time_variation_plot.csv");
pdschRuntimeEventPath = fullfile(layout.ReportCSVDir, "pdsch_runtime_event_table.csv");
puschRuntimeEventPath = fullfile(layout.ReportCSVDir, "pusch_runtime_event_table.csv");
pdcchPublicPath = fullfile(layout.ReportCSVDir, "pdcch_dci_table.csv");
pucchPublicPath = fullfile(layout.ReportCSVDir, "pucch_uci_table.csv");
prachDetectionPath = fullfile(layout.ReportCSVDir, "prach_detection_table.csv");
srsMeasurementPath = fullfile(layout.ReportCSVDir, "srs_measurement_table.csv");
csiRsRuntimePath = fullfile(layout.ReportCSVDir, "csi_rs_runtime_event_table.csv");
csiReportPath = fullfile(layout.ReportCSVDir, "csi_report_table.csv");
trsPublicPath = fullfile(layout.ReportCSVDir, "trs_receiver_tracking_table.csv");
ssbPbchCellSearchPath = fullfile(layout.ReportCSVDir, "ssb_pbch_cell_search_table.csv");
noiseEvidencePath = fullfile(layout.ReportCSVDir, "noise_variance_evidence_table.csv");
mcsCqiDecisionPath = fullfile(layout.ReportCSVDir, "mcs_cqi_decision_trace_table.csv");
contractPath = fullfile(layout.ReportCSVDir, "lls_output_contract.csv");
metricCatalogPath = fullfile(layout.ReportCSVDir, "metric_definition_catalog.csv");
metricUnitRolePath = fullfile(layout.ReportCSVDir, "metric_unit_role_catalog.csv");
plotManifestPath = fullfile(layout.ReportCSVDir, "plot_manifest.csv");
visualArtifactAuditPath = fullfile(layout.ReportCSVDir, "visual_artifact_audit.csv");
visualArtifactAuditMDPath = fullfile(layout.ReportDir, "visual_artifact_audit.md");
plotRenderStatusPath = fullfile(layout.ReportCSVDir, "plot_render_status.csv");
chartRegistryPath = fullfile(layout.ReportCSVDir, "chart_source_registry.csv");
plotDataQualityPath = fullfile(layout.ReportCSVDir, "plot_data_quality_table.csv");
plotSuppressionPath = fullfile(layout.ReportCSVDir, "plot_suppression_table.csv");
unavailablePlotCardRegistryPath = fullfile(layout.ReportCSVDir, "unavailable_plot_card_registry.csv");
lineagePath = fullfile(layout.ReportCSVDir, "raw_to_derived_lineage.csv");
fieldAvailabilityPath = fullfile(layout.ReportCSVDir, "table_field_availability_matrix.csv");

assert(exist(registryPath, "file") == 2, "Output coverage registry must be persisted.");
assert(exist(implementationRegisterPath, "file") == 2, "LLS implementation register must be persisted.");
assert(exist(unavailablePath, "file") == 2, "Honest unavailable registry must be persisted.");
assert(exist(energyPath, "file") == 2, "Power/energy table must be persisted when energy telemetry exists.");
assert(exist(livePowerPath, "file") == 2, "Canonical live power runtime table must be persisted when energy telemetry exists.");
assert(exist(liveRFPath, "file") == 2, "Canonical live RF power table must be persisted when energy telemetry exists.");
assert(exist(liveBBPath, "file") == 2, "Canonical live BB power table must be persisted when BB energy telemetry exists.");
assert(exist(liveEnergyEffPath, "file") == 2, "Canonical live energy-efficiency table must be persisted from runtime energy rows.");
assert(exist(liveSleepPath, "file") == 2, "Canonical live sleep-state table must be persisted from runtime energy rows.");
assert(exist(powerAnalyticsPath, "file") == 2, "Canonical power analytics table must be persisted from live power rows.");
assert(exist(energyEffAnalyticsPath, "file") == 2, "Canonical energy-efficiency analytics table must be persisted from live energy rows.");
assert(exist(runtimePowerAnalyticsPath, "file") == 2, "Canonical runtime-power analytics table must be persisted from live power rows.");
assert(exist(sleepAnalyticsPath, "file") == 2, "Canonical sleep-state analytics table must be persisted from live sleep-state rows.");
assert(exist(prbPath, "file") == 2, "PRB allocation table must be persisted when scheduler grants exist.");
assert(exist(heatmapPath, "file") == 2, "PRB heatmap table must be persisted when PRB rows exist.");
assert(exist(dlHeatmapPath, "file") == 2, "DL resource-grid heatmap table must be persisted when DL grants exist.");
assert(exist(ulHeatmapPath, "file") == 2, "UL resource-grid heatmap table must be persisted when UL grants exist.");
assert(exist(topologyDensityPath, "file") == 2, "Topology density table must be persisted from runtime topology artifacts.");
assert(exist(sectorUtilizationPath, "file") == 2, "Sector utilization summary must be persisted from runtime load/grant artifacts.");
assert(exist(servingPopulationPath, "file") == 2, "Serving-cell population table must be persisted from runtime serving-cell artifacts.");
assert(exist(schedulerDecisionPath, "file") == 2, "Scheduler decision table must be persisted from runtime grant artifacts.");
assert(exist(latencyPath, "file") == 2, "Latency table must be persisted when runtime latency components exist.");
assert(exist(latencyCDFPath, "file") == 2, "Latency CDF table must be derived from runtime latency rows.");
assert(exist(comparePath, "file") == 2, "Compare-run prerequisite table must be persisted.");
assert(exist(issuePath, "file") == 2, "Result issue registry must be persisted when runtime issue evidence exists.");
assert(exist(kpiHealthPath, "file") == 2, "KPI health flags table must be persisted for reporting integrity.");
assert(exist(anomalyPath, "file") == 2, "Anomaly window table must be derived from issue registry rows.");
assert(exist(crossLayerPath, "file") == 2, "Cross-layer correlation table must be derived from runtime scheduler rows.");
assert(exist(hotspotPath, "file") == 2, "Hotspot analytics table must be derived from runtime UE summary rows.");
assert(exist(controlOverheadPath, "file") == 2, "Control-overhead analytics table must be derived from runtime control rows.");
assert(exist(resourceOverheadPath, "file") == 2, "Resource-overhead analytics table must be derived from runtime PRB rows.");
assert(exist(latencyRootCausePath, "file") == 2, "Latency root-cause table must be derived from runtime latency rows.");
assert(exist(pdcchPath, "file") == 2, "PDCCH/DCI table must be persisted when runtime PDCCH rows exist.");
assert(exist(pbchPath, "file") == 2, "SSB/PBCH table must be persisted when runtime PBCH rows exist.");
assert(exist(prachPath, "file") == 2, "PRACH table must be persisted when runtime PRACH rows exist.");
assert(exist(pucchPath, "file") == 2, "PUCCH table must be persisted when runtime PUCCH rows exist.");
assert(exist(pdschPath, "file") == 2, "PDSCH table must be persisted when runtime DL PDSCH rows exist.");
assert(exist(puschPath, "file") == 2, "PUSCH table must be persisted when runtime UL PUSCH rows exist.");
assert(exist(srsPath, "file") == 2, "SRS table must be persisted when runtime SRS rows exist.");
assert(exist(csiRsPath, "file") == 2, "CSI-RS table must be persisted when runtime CSI-RS rows exist.");
assert(exist(trsTrackingPath, "file") == 2, "TRS receiver tracking table must be persisted when runtime tracking rows exist.");
assert(exist(beamPrecoderPath, "file") == 2, "Beam/precoder table must be persisted when air-interface beam rows exist.");
assert(exist(beamAnalyticsPath, "file") == 2, "Beamforming analytics table must be persisted from runtime beam rows.");
assert(exist(mimoRankPath, "file") == 2, "MIMO rank utilization table must be persisted from runtime precoder rows.");
assert(exist(rankHistogramPath, "file") == 2, "Rank/layer usage histogram table must be persisted from runtime precoder rows.");
assert(exist(timingPath, "file") == 2, "Timing synchronization table must be persisted when runtime CFO/timing rows exist.");
assert(exist(dopplerPath, "file") == 2, "Doppler time variation table must be persisted from runtime channel and UE summary rows.");
assert(exist(pdschRuntimeEventPath, "file") == 2, "Public PDSCH runtime event table must be persisted.");
assert(exist(puschRuntimeEventPath, "file") == 2, "Public PUSCH runtime event table must be persisted.");
assert(exist(pdcchPublicPath, "file") == 2, "Public PDCCH/DCI table must be persisted.");
assert(exist(pucchPublicPath, "file") == 2, "Public PUCCH UCI table must be persisted.");
assert(exist(prachDetectionPath, "file") == 2, "Public PRACH detection table must be persisted.");
assert(exist(srsMeasurementPath, "file") == 2, "Public SRS measurement table must be persisted.");
assert(exist(csiRsRuntimePath, "file") == 2, "Public CSI-RS runtime event table must be persisted.");
assert(exist(csiReportPath, "file") == 2, "Public CSI report table must be persisted.");
assert(exist(trsPublicPath, "file") == 2, "Public TRS receiver tracking table must be persisted.");
assert(exist(ssbPbchCellSearchPath, "file") == 2, "Public SSB/PBCH cell-search table must be persisted.");
assert(exist(noiseEvidencePath, "file") == 2, "Noise-variance evidence table must be persisted.");
assert(exist(mcsCqiDecisionPath, "file") == 2, "MCS/CQI decision trace table must be persisted.");
assert(exist(contractPath, "file") == 2, "LLS output contract CSV must be persisted.");
assert(exist(metricCatalogPath, "file") == 2, "Metric definition catalog must be persisted.");
assert(exist(metricUnitRolePath, "file") == 2, "Metric unit/role catalog must be persisted.");
assert(exist(plotManifestPath, "file") == 2, "Plot manifest must be persisted.");
assert(exist(visualArtifactAuditPath, "file") == 2, "Visual artifact audit CSV must be persisted.");
assert(exist(visualArtifactAuditMDPath, "file") == 2, "Visual artifact audit markdown must be persisted.");
assert(exist(plotRenderStatusPath, "file") == 2, "Plot render-status table must be persisted.");
assert(exist(chartRegistryPath, "file") == 2, "Chart source registry must be persisted.");
assert(exist(plotDataQualityPath, "file") == 2, "Plot data-quality table must be persisted.");
assert(exist(plotSuppressionPath, "file") == 2, "Plot suppression table must be persisted.");
assert(exist(unavailablePlotCardRegistryPath, "file") == 2, "Unavailable plot-card registry must be persisted.");
assert(exist(lineagePath, "file") == 2, "Raw-to-derived lineage table must be persisted.");
assert(exist(fieldAvailabilityPath, "file") == 2, "Table field-availability matrix must be persisted.");

registry = readtable(registryPath, "VariableNamingRule", "preserve");
implementationRegister = readtable(implementationRegisterPath, "VariableNamingRule", "preserve");
unavailable = readtable(unavailablePath, "VariableNamingRule", "preserve");
energy = readtable(energyPath, "VariableNamingRule", "preserve");
livePower = readtable(livePowerPath, "VariableNamingRule", "preserve");
liveRF = readtable(liveRFPath, "VariableNamingRule", "preserve");
liveBB = readtable(liveBBPath, "VariableNamingRule", "preserve");
liveEnergyEff = readtable(liveEnergyEffPath, "VariableNamingRule", "preserve");
liveSleep = readtable(liveSleepPath, "VariableNamingRule", "preserve");
powerAnalytics = readtable(powerAnalyticsPath, "VariableNamingRule", "preserve");
energyEffAnalytics = readtable(energyEffAnalyticsPath, "VariableNamingRule", "preserve");
runtimePowerAnalytics = readtable(runtimePowerAnalyticsPath, "VariableNamingRule", "preserve");
sleepAnalytics = readtable(sleepAnalyticsPath, "VariableNamingRule", "preserve");
prb = readtable(prbPath, "VariableNamingRule", "preserve");
heatmap = readtable(heatmapPath, "VariableNamingRule", "preserve");
dlHeatmap = readtable(dlHeatmapPath, "VariableNamingRule", "preserve");
ulHeatmap = readtable(ulHeatmapPath, "VariableNamingRule", "preserve");
topologyDensity = readtable(topologyDensityPath, "VariableNamingRule", "preserve");
sectorUtilization = readtable(sectorUtilizationPath, "VariableNamingRule", "preserve");
servingPopulation = readtable(servingPopulationPath, "VariableNamingRule", "preserve");
schedulerDecision = readtable(schedulerDecisionPath, "VariableNamingRule", "preserve");
latency = readtable(latencyPath, "VariableNamingRule", "preserve");
latencyCDF = readtable(latencyCDFPath, "VariableNamingRule", "preserve");
compare = readtable(comparePath, "VariableNamingRule", "preserve");
issues = readtable(issuePath, "VariableNamingRule", "preserve");
kpiHealth = readtable(kpiHealthPath, "VariableNamingRule", "preserve");
anomaly = readtable(anomalyPath, "VariableNamingRule", "preserve");
crossLayer = readtable(crossLayerPath, "VariableNamingRule", "preserve");
hotspot = readtable(hotspotPath, "VariableNamingRule", "preserve");
controlOverhead = readtable(controlOverheadPath, "VariableNamingRule", "preserve");
resourceOverhead = readtable(resourceOverheadPath, "VariableNamingRule", "preserve");
latencyRootCause = readtable(latencyRootCausePath, "VariableNamingRule", "preserve");
pdcch = readtable(pdcchPath, "VariableNamingRule", "preserve");
pdsch = readtable(pdschPath, "VariableNamingRule", "preserve");
pusch = readtable(puschPath, "VariableNamingRule", "preserve");
csiRs = readtable(csiRsPath, "VariableNamingRule", "preserve");
beamPrecoder = readtable(beamPrecoderPath, "VariableNamingRule", "preserve");
beamAnalytics = readtable(beamAnalyticsPath, "VariableNamingRule", "preserve");
mimoRank = readtable(mimoRankPath, "VariableNamingRule", "preserve");
rankHistogram = readtable(rankHistogramPath, "VariableNamingRule", "preserve");
trsTracking = readtable(trsTrackingPath, "VariableNamingRule", "preserve");
timingSync = readtable(timingPath, "VariableNamingRule", "preserve");
doppler = readtable(dopplerPath, "VariableNamingRule", "preserve");
pdschRuntimeEvent = readtable(pdschRuntimeEventPath, "VariableNamingRule", "preserve");
puschRuntimeEvent = readtable(puschRuntimeEventPath, "VariableNamingRule", "preserve");
pdcchPublic = readtable(pdcchPublicPath, "VariableNamingRule", "preserve");
pucchPublic = readtable(pucchPublicPath, "VariableNamingRule", "preserve");
prachDetection = readtable(prachDetectionPath, "VariableNamingRule", "preserve");
srsMeasurement = readtable(srsMeasurementPath, "VariableNamingRule", "preserve");
csiRsRuntime = readtable(csiRsRuntimePath, "VariableNamingRule", "preserve");
csiReport = readtable(csiReportPath, "VariableNamingRule", "preserve");
trsPublic = readtable(trsPublicPath, "VariableNamingRule", "preserve");
ssbPbchCellSearch = readtable(ssbPbchCellSearchPath, "VariableNamingRule", "preserve");
noiseEvidence = readtable(noiseEvidencePath, "VariableNamingRule", "preserve");
mcsCqiDecision = readtable(mcsCqiDecisionPath, "VariableNamingRule", "preserve");
contract = readtable(contractPath, "VariableNamingRule", "preserve");
metricCatalog = readtable(metricCatalogPath, "VariableNamingRule", "preserve");
metricUnitRole = readtable(metricUnitRolePath, "VariableNamingRule", "preserve");
plotManifest = readtable(plotManifestPath, "VariableNamingRule", "preserve");
visualArtifactAudit = readtable(visualArtifactAuditPath, "VariableNamingRule", "preserve");
plotRenderStatus = readtable(plotRenderStatusPath, "VariableNamingRule", "preserve");
chartRegistry = readtable(chartRegistryPath, "VariableNamingRule", "preserve");
plotDataQuality = readtable(plotDataQualityPath, "VariableNamingRule", "preserve");
plotSuppression = readtable(plotSuppressionPath, "VariableNamingRule", "preserve");
unavailablePlotCards = readtable(unavailablePlotCardRegistryPath, "VariableNamingRule", "preserve");
lineage = readtable(lineagePath, "VariableNamingRule", "preserve");
fieldAvailability = readtable(fieldAvailabilityPath, "VariableNamingRule", "preserve");

assert(height(registry) >= 50, "Registry must cover the requested broad output surface, not a tiny subset.");
localAssertRegistryRow(registry, "power_energy_table", "implemented", "c");
localAssertRegistryRow(registry, "live_power_runtime_table", "implemented", "c");
localAssertRegistryRow(registry, "live_rf_power_table", "implemented", "c");
localAssertRegistryRow(registry, "live_bb_power_table", "implemented", "c");
localAssertRegistryRow(registry, "live_energy_efficiency_table", "implemented", "c");
localAssertRegistryRow(registry, "live_sleep_state_table", "implemented", "c");
localAssertRegistryRow(registry, "power_analytics", "implemented", "c");
localAssertRegistryRow(registry, "energy_efficiency_analytics", "implemented", "c");
localAssertRegistryRow(registry, "runtime_power_analytics", "implemented", "c");
localAssertRegistryRow(registry, "sleep_state_analytics", "implemented", "c");
localAssertRegistryRow(registry, "lls_implementation_register", "implemented", "c");
localAssertRegistryRow(registry, "result_issue_registry", "implemented", "c");
localAssertRegistryRow(registry, "kpi_health_flags", "implemented", "c");
localAssertRegistryRow(registry, "live_prb_allocation", "implemented", "c");
localAssertRegistryRow(registry, "prb_allocation_heatmap", "implemented", "c");
localAssertRegistryRow(registry, "dl_resource_grid_heatmap", "implemented", "c");
localAssertRegistryRow(registry, "ul_resource_grid_heatmap", "implemented", "c");
localAssertRegistryRow(registry, "topology_density_table", "implemented", "c");
localAssertRegistryRow(registry, "sector_utilization_summary_table", "implemented", "c");
localAssertRegistryRow(registry, "serving_cell_population_table", "implemented", "c");
localAssertRegistryRow(registry, "table_scheduler_decision", "implemented", "c");
localAssertRegistryRow(registry, "compare_runs_kpi_delta_table", "blocked", "r");
localAssertRegistryRow(registry, "table_latency", "implemented", "c");
localAssertRegistryRow(registry, "latency_cdf_plot", "implemented", "c");
localAssertRegistryRow(registry, "latency_root_cause_table", "implemented", "c");
localAssertRegistryRow(registry, "output_coverage_dashboard", "partial", "d");
localAssertRegistryRow(registry, "pdcch_dci_table", "implemented", "c");
localAssertRegistryRow(registry, "ssb_pbch_table", "implemented", "c");
localAssertRegistryRow(registry, "prach_table", "implemented", "c");
localAssertRegistryRow(registry, "pucch_table", "implemented", "c");
localAssertRegistryRow(registry, "pdsch_table", "implemented", "c");
localAssertRegistryRow(registry, "pusch_table", "implemented", "c");
localAssertRegistryRow(registry, "srs_table", "implemented", "c");
localAssertRegistryRow(registry, "csi_rs_table", "implemented", "c");
localAssertRegistryRow(registry, "trs_receiver_tracking_table", "implemented", "c");
localAssertRegistryRow(registry, "beam_precoder_table", "implemented", "c");
localAssertRegistryRow(registry, "beamforming_analytics_table", "implemented", "c");
localAssertRegistryRow(registry, "mimo_rank_utilization_table", "implemented", "c");
localAssertRegistryRow(registry, "rank_layer_usage_histogram", "implemented", "c");
localAssertRegistryRow(registry, "timing_synchronization_table", "implemented", "c");
localAssertRegistryRow(registry, "doppler_time_variation_plot", "implemented", "c");
localAssertRegistryRow(registry, "pdsch_runtime_event_table", "implemented", "c");
localAssertRegistryRow(registry, "pusch_runtime_event_table", "implemented", "c");
localAssertRegistryRow(registry, "pdcch_dci_public_table", "implemented", "c");
localAssertRegistryRow(registry, "pucch_uci_table", "implemented", "c");
localAssertRegistryRow(registry, "prach_detection_table", "implemented", "c");
localAssertRegistryRow(registry, "srs_measurement_table", "implemented", "c");
localAssertRegistryRow(registry, "csi_rs_runtime_event_table", "implemented", "c");
localAssertRegistryRow(registry, "csi_report_table", "implemented", "c");
localAssertRegistryRow(registry, "trs_receiver_tracking_public_table", "implemented", "c");
localAssertRegistryRow(registry, "ssb_pbch_cell_search_table", "implemented", "c");
localAssertRegistryRow(registry, "noise_variance_evidence_table", "implemented", "c");
localAssertRegistryRow(registry, "mcs_cqi_decision_trace_table", "implemented", "c");
localAssertRegistryRow(registry, "plot_manifest", "implemented", "c");
localAssertRegistryRow(registry, "visual_artifact_audit", "implemented", "c");
localAssertRegistryRow(registry, "chart_source_registry", "implemented", "c");
localAssertRegistryRow(registry, "raw_to_derived_lineage", "implemented", "c");
localAssertRegistryRow(registry, "table_field_availability_matrix", "implemented", "c");
localAssertRegistryRow(registry, "anomaly_window_table", "implemented", "c");
localAssertRegistryRow(registry, "cross_layer_correlation_table", "implemented", "c");
localAssertRegistryRow(registry, "hotspot_analytics_table", "implemented", "c");
localAssertRegistryRow(registry, "control_overhead_analytics_table", "implemented", "c");
localAssertRegistryRow(registry, "resource_overhead_analytics_table", "implemented", "c");
localAssertRegistryRow(registry, "hotspot_dashboard", "partial", "d");
localAssertRegistryRow(registry, "control_overhead_dashboard", "partial", "d");
localAssertRegistryRow(registry, "latency_root_cause_dashboard", "partial", "d");

implementedMask = strcmp(string(registry.current_status), "implemented");
strictImplementedEvidence = localAsLogical(registry.backend_source_exists_flag) & ...
    localAsLogical(registry.persisted_flag) & ...
    localAsLogical(registry.api_exposed_flag) & ...
    localAsLogical(registry.export_supported_flag) & ...
    localAsLogical(registry.ui_rendered_flag);
assert(all(strictImplementedEvidence(implementedMask)), ...
    "No output may be marked implemented unless backend, persistence, API, export, and UI evidence are all true.");
dashboardMask = strcmp(string(registry.ui_section), "dashboard") & ~localAsLogical(registry.persisted_flag);
assert(~any(strcmp(string(registry.current_status(dashboardMask)), "implemented")), ...
    "Dashboard-only rows without standalone persisted/exported artifacts must not be marked implemented.");
assert(ismember("status_code", string(registry.Properties.VariableNames)), ...
    "Coverage registry must expose row-level status_code.");
assert(all(strcmp(string(registry.status_code), string(registry.current_status))), ...
    "Coverage registry status_code must reflect each row's current_status, not a blanket export status.");
assert(~isempty(implementationRegister) && height(implementationRegister) == height(registry), ...
    "Implementation register must provide one machine-readable status row for every coverage-registry output.");
assert(all(ismember(["implementation_status","evidence_status","conformance_claim_allowed","runtime_row_count","source_artifact_ref","next_implementation_step"], ...
    string(implementationRegister.Properties.VariableNames))), ...
    "Implementation register must expose status, evidence, source, and next-action columns.");
implementedRegisterMask = strcmp(string(implementationRegister.implementation_status), "implemented");
assert(all(localAsLogical(implementationRegister.conformance_claim_allowed(implementedRegisterMask))), ...
    "Implemented register rows must be claimable only after evidence gates are satisfied.");
nonImplementedRegisterMask = ~strcmp(string(implementationRegister.implementation_status), "implemented");
assert(~any(localAsLogical(implementationRegister.conformance_claim_allowed(nonImplementedRegisterMask))), ...
    "Partial, blocked, unavailable, and schema-only rows must not allow conformance claims.");
assert(any(strcmp(string(implementationRegister.output_name), "csi_rs_table") & ...
    strcmp(string(implementationRegister.implementation_status), "implemented") & ...
    contains(string(implementationRegister.evidence_status), "runtime_evidence_complete")), ...
    "Implementation register must capture runtime evidence for implemented CSI-RS output.");
assert(~isempty(kpiHealth) && all(ismember(["kpi_name","health_status","runtime_row_count","finite_sample_count","proxy_fallback_sample_count","recommended_action"], ...
    string(kpiHealth.Properties.VariableNames))), ...
    "KPI health flags must expose source-row health, finite counts, proxy/fallback counts, and remediation text.");
assert(any(strcmp(string(kpiHealth.kpi_name), "dl_mcs_index") & double(kpiHealth.finite_sample_count) > 0), ...
    "KPI health flags must audit DL MCS values from runtime trial rows.");

assert(~isempty(unavailable), "Unavailable output metadata must exist for backend gaps.");
assert(~any(strcmp(string(unavailable.output_name), "table_latency")), ...
    "Implemented latency output must not remain in the honest unavailable registry when real latency rows exist.");
assert(all(strlength(string(unavailable.unavailable_reason)) > 0), ...
    "Unavailable rows must carry explicit reasons.");

assert(~isempty(energy) && height(energy) > 0, "Power/energy table must contain real rows from energy telemetry.");
assert(~isempty(livePower) && height(livePower) > 0, "Canonical live power runtime table must contain real rows.");
assert(~isempty(liveRF) && height(liveRF) > 0, "Canonical live RF power table must contain real rows.");
assert(~isempty(liveBB) && height(liveBB) > 0, "Canonical live BB power table must contain real rows when BB energy exists.");
assert(~isempty(liveEnergyEff) && height(liveEnergyEff) > 0, "Canonical live energy-efficiency table must contain real rows.");
assert(~isempty(liveSleep) && height(liveSleep) > 0, "Canonical live sleep-state table must contain real rows.");
assert(~isempty(powerAnalytics) && height(powerAnalytics) > 0, "Canonical power analytics table must contain derived rows.");
assert(~isempty(energyEffAnalytics) && height(energyEffAnalytics) > 0, "Canonical energy-efficiency analytics table must contain derived rows.");
assert(~isempty(runtimePowerAnalytics) && height(runtimePowerAnalytics) > 0, "Canonical runtime-power analytics table must contain derived rows.");
assert(~isempty(sleepAnalytics) && height(sleepAnalytics) > 0, "Canonical sleep-state analytics table must contain derived rows.");
assert(all(ismember(["metric_name","metric_value","metric_unit","value_role","value_source","value_status"], string(livePower.Properties.VariableNames))), ...
    "Canonical live power runtime table must expose metric semantics and lineage.");
assert(all(ismember(["formula_id","formula","valid_sample_count","missing_sample_count"], string(powerAnalytics.Properties.VariableNames))), ...
    "Canonical power analytics table must expose formula/sample-count lineage.");
assert(ismember("energy_per_bit_nJ", string(energy.Properties.VariableNames)), ...
    "Power/energy table must expose energy-per-bit.");
for col = ["power_estimate_value","power_estimate_unit","power_value_role","power_value_source","power_value_status","energy_value_role","energy_value_source","energy_value_status"]
    assert(ismember(col, string(energy.Properties.VariableNames)), ...
        "Power/energy table must expose explicit value semantics column %s.", col);
end
assert(all(strcmp(string(energy.power_estimate_unit), "W")), ...
    "Power estimate unit must be explicit and stable.");
assert(all(strcmp(string(energy.power_value_role), "derived")), ...
    "Power value role must be explicit and must not be mislabeled as measured.");
assert(~isempty(prb) && height(prb) > 0, "PRB allocation table must contain rows from scheduler grants.");
assert(all(double(prb.rb_len) > 0), "PRB allocation rows must come from real positive PRB counts.");
assert(~isempty(heatmap) && height(heatmap) >= double(prb.rb_len(1)), ...
    "PRB heatmap must be derived from persisted PRB rows.");
assert(~isempty(dlHeatmap) && all(strcmpi(string(dlHeatmap.direction), "DL")), ...
    "DL resource-grid heatmap must be filtered to real DL PRB rows.");
assert(~isempty(ulHeatmap) && all(strcmpi(string(ulHeatmap.direction), "UL")), ...
    "UL resource-grid heatmap must be filtered to real UL PRB rows.");
assert(~isempty(topologyDensity) && isfinite(double(topologyDensity.ue_density_per_km2(1))) && ...
    strcmpi(string(topologyDensity.density_value_role(1)), "derived"), ...
    "Topology density table must expose derived density with source semantics.");
assert(~isempty(sectorUtilization) && ismember("dl_prb_symbols", string(sectorUtilization.Properties.VariableNames)), ...
    "Sector utilization summary must carry granted PRB-symbol totals.");
assert(~isempty(servingPopulation) && double(servingPopulation.served_ue_count(1)) > 0, ...
    "Serving-cell population must be derived from runtime serving-cell rows.");
assert(~isempty(schedulerDecision) && all(logical(schedulerDecision.selected_flag)) && ...
    all(~localAsLogical(schedulerDecision.candidate_decision_rows_available)), ...
    "Scheduler decision table must truthfully expose selected grants without pretending rejected candidates exist.");
assert(~isempty(latency) && all(strcmpi(string(latency.latency_value_role), "measured")) && ...
    all(isfinite(double(latency.latency_ms))), ...
    "Latency table must use real persisted latency components, not default or configured values.");
assert(~isempty(latencyCDF) && all(diff(double(latencyCDF.cdf_probability)) >= 0), ...
    "Latency CDF table must be a monotonic empirical CDF from latency rows.");
assert(~isempty(compare) && all(strcmp(string(compare.status), "PREREQUISITE_NOT_SATISFIED")), ...
    "Compare-run outputs must stay prerequisite-gated for a single run.");
assert(~isempty(issues) && any(strcmp(string(issues.issue_category), "channel_interference")), ...
    "Issue registry must list runtime-derived issues for result/analytics views.");
assert(~isempty(anomaly) && height(anomaly) == height(issues), ...
    "Anomaly window table must derive one analytics row per issue registry row.");
assert(~isempty(crossLayer) && any(strcmp(string(crossLayer.x_metric), "SINR_dB")), ...
    "Cross-layer correlation table must include scheduler SINR/MCS evidence when present.");
assert(~isempty(hotspot) && any(strcmp(string(hotspot.zone), "edge")), ...
    "Hotspot analytics must summarize runtime UE population groups.");
assert(~isempty(controlOverhead) && any(strcmp(string(controlOverhead.signal_family), "PDCCH")), ...
    "Control overhead analytics must summarize real control trial row families.");
assert(~isempty(resourceOverhead) && all(isfinite(double(resourceOverhead.resource_fraction_observed))), ...
    "Resource overhead analytics must derive non-placeholder resource fractions from PRB rows.");
assert(~isempty(latencyRootCause) && all(isfinite(double(latencyRootCause.latency_ms))), ...
    "Latency root-cause table must be backed by real latency values.");
assert(all(logical(issues.analytics_visible_flag)), ...
    "Issue registry rows must be marked visible to analytics.");
assert(~isempty(pdcch) && height(pdcch) == 1 && strcmpi(string(pdcch.runtime_evidence(1)), "persisted_runtime_trial_row"), ...
    "PDCCH/DCI standalone table must mirror a persisted runtime trial row, not a schema placeholder.");
assert(~isempty(pdsch) && height(pdsch) == 1 && strcmpi(string(pdsch.output_family_materialization(1)), "runtime_backed_mirror"), ...
    "PDSCH standalone table must be backed by active-path DL trial rows.");
assert(~isempty(pusch) && height(pusch) == 1 && strcmpi(string(pusch.output_family_materialization(1)), "runtime_backed_mirror"), ...
    "PUSCH standalone table must be backed by active-path UL trial rows.");
assert(~isempty(csiRs) && height(csiRs) == 1 && logical(csiRs.Transmitted(1)) && logical(csiRs.Observed(1)) && ...
    strcmpi(string(csiRs.runtime_evidence(1)), "persisted_runtime_trial_row"), ...
    "CSI-RS standalone table must mirror a persisted runtime CSI-RS trial row, not a schema placeholder.");
assert(~isempty(beamPrecoder) && height(beamPrecoder) == 2, ...
    "Beam/precoder table must be materialized from DL and UL runtime trial rows.");
assert(~isempty(pdschRuntimeEvent) && all(ismember(["NoiseVar","NoiseVarStatus","DecodeAttempted","DecodeUsable","SINRValueRole"], string(pdschRuntimeEvent.Properties.VariableNames))), ...
    "Public PDSCH runtime table must expose receiver usability, noise lineage, and SINR role columns.");
assert(~isempty(puschRuntimeEvent) && all(ismember(["AppliedPrecoderPMI","AppliedBeamIndexSet","BeamIndexSetMaterialized","NoiseVarStatus"], string(puschRuntimeEvent.Properties.VariableNames))), ...
    "Public PUSCH runtime table must preserve runtime precoder and noise-variance lineage.");
assert(~isempty(pdcchPublic) && ismember("DCIPayloadBits", string(pdcchPublic.Properties.VariableNames)) && ...
    ~ismember("TBSBits", string(pdcchPublic.Properties.VariableNames)), ...
    "Public PDCCH table must expose DCI payload bits without pretending PDCCH carries transport-block size.");
assert(~isempty(pucchPublic) && all(strcmpi(string(pucchPublic.CRCOutcome), "not_applicable")), ...
    "Public PUCCH UCI table must mark CRC as not applicable when CRC does not apply.");
assert(~isempty(prachDetection) && all(ismember(["TimingOffsetSamplesRaw","TimingOffsetSamplesApplied"], string(prachDetection.Properties.VariableNames))), ...
    "Public PRACH detection table must preserve raw and applied timing offsets separately.");
assert(~isempty(srsMeasurement) && all(ismember(["NoiseVar","NoiseVarSource","NoiseVarStatus","MeasurementUsable"], string(srsMeasurement.Properties.VariableNames))), ...
    "Public SRS measurement table must expose measurement usability and noise lineage.");
assert(~isempty(csiRsRuntime) && all(logical(csiRsRuntime.Observed)) && all(ismember(["MeasurementRSRP_dB","RuntimeMaterializationStatus"], string(csiRsRuntime.Properties.VariableNames))), ...
    "Public CSI-RS runtime table must preserve runtime observation status and measurement columns.");
assert(~isempty(csiReport) && all(ismember(["CQI","CQIDerivedMCS","CalibrationProfile"], string(csiReport.Properties.VariableNames))), ...
    "Public CSI report table must expose CQI-derived MCS lineage.");
assert(~isempty(trsPublic) && all(ismember(["TimingEstimateAvailability","CFOEstimateAvailability","CorrectionLoopStatus"], string(trsPublic.Properties.VariableNames))), ...
    "Public TRS receiver tracking table must expose timing/CFO availability and correction-loop status.");
assert(~isempty(ssbPbchCellSearch) && all(ismember(["PBCHCRC","MIBRecovered","RuntimeEvidenceStatus"], string(ssbPbchCellSearch.Properties.VariableNames))), ...
    "Public SSB/PBCH cell-search table must expose PBCH CRC semantics and runtime evidence state.");
assert(~isempty(noiseEvidence) && ~any(abs(double(noiseEvidence.NoiseVar) - 1e-10) < eps(1e-10)), ...
    "Noise-variance evidence table must never reintroduce the forbidden 1e-10 fallback.");
assert(~isempty(noiseEvidence) && all(ismember(["NoiseVarSource","NoiseVarStatus","SNRConsistencyStatus","ReceiverUsable"], string(noiseEvidence.Properties.VariableNames))), ...
    "Noise-variance evidence table must expose source, status, SNR consistency, and receiver usability.");
assert(~isempty(mcsCqiDecision) && all(ismember(["SelectedMCS","CQIDerivedMCS","MCSMismatchStatus","MCSMismatchReason"], string(mcsCqiDecision.Properties.VariableNames))), ...
    "MCS/CQI decision trace must explain mismatches instead of hiding them.");
assert(~isempty(contract) && any(strcmp(string(contract.OutputId), "pdsch_runtime_event_table")) && ...
    any(strcmp(string(contract.OutputId), "plot_manifest")), ...
    "LLS output contract must register both public tables and plot/provenance outputs.");
assert(~isempty(metricCatalog) && any(strcmp(string(metricCatalog.MetricName), "NoiseVar")) && ...
    any(strcmp(string(metricCatalog.MetricName), "SINR_dB")), ...
    "Metric definition catalog must register core receiver metrics.");
assert(~isempty(metricUnitRole) && any(strcmp(string(metricUnitRole.MetricName), "NoiseVar")), ...
    "Metric unit/role catalog must mirror the metric contract.");
assert(~isempty(plotManifest) && any(strcmp(string(plotManifest.PlotId), "power_energy_cumulative") & logical(plotManifest.CountsAsRealPlot)), ...
    "Plot manifest must mark real rendered plots explicitly.");
assert(~isempty(plotManifest) && ismember("VisualValidity", string(plotManifest.Properties.VariableNames)) && ...
    all(ismember(string(plotManifest.VisualValidity), ["real_lls_evidence","diagnostic_only","unavailable","invalid_stale"])), ...
    "Plot manifest must expose strict visual validity for every plot.");
assert(~isempty(visualArtifactAudit) && all(ismember(["plot_id","artifact_path","audit_ok","failure_code","failure_reason"], string(visualArtifactAudit.Properties.VariableNames))), ...
    "Visual artifact audit must expose strict audit status and failure details.");
assert(~isempty(plotManifest) && all(strlength(string(plotManifest.SourceCSV)) > 0), ...
    "Every plot-manifest row must carry direct source CSV provenance.");
assert(~isempty(plotRenderStatus) && any(strcmp(string(plotRenderStatus.PlotRenderStatus), "rendered_real_plot")), ...
    "Plot render-status table must distinguish real rendered plots from suppressed or unavailable entries.");
assert(~isempty(plotRenderStatus) && ismember("VisualValidity", string(plotRenderStatus.Properties.VariableNames)), ...
    "Plot render-status table must carry visual validity.");
chartRegistryNames = lower(string(chartRegistry.Properties.VariableNames));
assert(~isempty(chartRegistry) && numel(chartRegistryNames) >= 4, ...
    "Chart source registry must exist as a structured nonempty provenance table.");
assert(~isempty(plotDataQuality) && all(ismember(["RowCount","UniqueXCount","UniqueYCount","NonNaNYCount","CountsAsRealPlot","VisualValidity"], string(plotDataQuality.Properties.VariableNames))), ...
    "Plot data-quality table must expose row-count and validity statistics.");
assert(~isempty(plotSuppression) && any(strcmp(string(plotSuppression.PlotRenderStatus), "suppressed")), ...
    "Plot suppression table must capture suppressed plots instead of silently counting them as rendered.");
if ~isempty(unavailablePlotCards)
    assert(all(ismember(string(unavailablePlotCards.PlotId), string(plotManifest.PlotId(logical(plotManifest.IsUnavailableCard))))), ...
        "Unavailable plot-card registry must contain only plot IDs that the manifest marked as unavailable cards.");
end
assert(~isempty(lineage) && any(strcmp(string(lineage.OutputId), "pdsch_runtime_event_table")) && any(strcmp(string(lineage.DerivationStatus), "derived")), ...
    "Lineage table must describe derived public outputs from runtime-backed sources.");
assert(~isempty(fieldAvailability) && any(strcmp(string(fieldAvailability.OutputId), "pdsch_runtime_event_table") & strcmp(string(fieldAvailability.AvailabilityStatus), "present_with_values")), ...
    "Field-availability matrix must record required public-table fields with real values.");
assert(~isempty(beamAnalytics) && any(double(beamAnalytics.runtime_applied_pmi_rows) > 0), ...
    "Beamforming analytics must summarize runtime applied PMI evidence.");
assert(~isempty(mimoRank) && all(isfinite(double(mimoRank.rank_or_layer_count))), ...
    "MIMO rank utilization must be derived from runtime precoding layer counts.");
assert(~isempty(rankHistogram) && any(strcmp(string(rankHistogram.histogram_definition), "rank/layer usage histogram from runtime beam-precoder rows")), ...
    "Rank/layer histogram must retain its runtime source definition.");
assert(~isempty(doppler) && all(strcmpi(string(doppler.doppler_value_role), "derived")) && all(isfinite(double(doppler.doppler_hz))), ...
    "Doppler table must be derived from runtime UE speed and carrier frequency, not fabricated.");
assert(~isempty(trsTracking) && height(trsTracking) == 1 && ...
    strcmpi(string(trsTracking.TRSReceiverIntegrationStatus(1)), "integrated_shared_tracking_object"), ...
    "TRS receiver tracking table must mirror real persisted receiver tracking rows.");
ulBeamRows = strcmpi(string(beamPrecoder.direction), "UL");
assert(any(ulBeamRows & strcmpi(string(beamPrecoder.applied_precoder_pmi_truth_classification), "applied_runtime_value") & ...
    isfinite(double(beamPrecoder.applied_precoder_pmi))), ...
    "Beam/precoder table must preserve runtime-applied UL PUSCH TPMI evidence.");
assert(~isempty(timingSync) && height(timingSync) == 2, ...
    "Timing synchronization table must be materialized from DL and UL runtime trial rows.");
assert(all(ismember(["raw_timing_estimate_samples","applied_timing_correction_samples", ...
    "timing_estimate_application_policy","timing_estimate_status","timing_estimate_was_clipped"], ...
    string(timingSync.Properties.VariableNames))), ...
    "Timing synchronization table must expose raw timing truth and applied-correction policy columns.");
assert(any(strcmpi(string(timingSync.cfo_estimate_availability), "missing") & ~isfinite(double(timingSync.cfo_error_hz))), ...
    "Timing synchronization table must not backfill CFO error when no CFO estimate exists.");
assert(any(strcmpi(string(timingSync.timing_value_status), "NOT_APPLICABLE") & logical(timingSync.use_ideal_timing_sync)), ...
    "Timing synchronization table must represent ideal timing sync as not applicable rather than a fake estimate.");
assert(any(strcmpi(string(timingSync.timing_estimate_status), "ideal_sync_bypass") & logical(timingSync.use_ideal_timing_sync)), ...
    "Timing synchronization table must label ideal-sync rows explicitly.");
assert(any(strcmpi(string(timingSync.timing_estimate_application_policy), "signed_waveform_shift_negative_padding_positive_crop_supported")), ...
    "Timing synchronization table must preserve waveform receiver timing-application policy.");
assert(~any(strcmp(string(unavailable.output_name), "pdcch_dci_table")), ...
    "Implemented runtime-backed PDCCH/DCI output must not remain in the honest unavailable registry.");
assert(~any(strcmp(string(unavailable.output_name), "csi_rs_table")), ...
    "Implemented runtime-backed CSI-RS output must not remain in the honest unavailable registry.");
assert(~isempty(out.ManifestUnavailableEntries), "Manifest unavailable entries must be returned for run manifest export.");

runFolderNoCSIRS = fullfile(tmp, "coverage_run_no_csirs");
layoutNoCSIRS = sixgr.report.resultLayout(runFolderNoCSIRS);
localCreateSourceArtifacts(layoutNoCSIRS);
delete(fullfile(layoutNoCSIRS.AirInterfaceCSVDir, "csi_rs_trials.csv"));
sixgr.truth.exportLLSOutputCoverageArtifacts(runFolderNoCSIRS, scfg, cfg);
registryNoCSIRS = readtable(fullfile(layoutNoCSIRS.ReportCSVDir, "output_coverage_registry.csv"), "VariableNamingRule", "preserve");
unavailableNoCSIRS = readtable(fullfile(layoutNoCSIRS.ReportCSVDir, "honest_unavailable_registry.csv"), "VariableNamingRule", "preserve");
localAssertRegistryRow(registryNoCSIRS, "csi_rs_table", "unavailable", "c");
assert(exist(fullfile(layoutNoCSIRS.ControlCSVDir, "csi_rs_table.csv"), "file") ~= 2, ...
    "CSI-RS standalone table must not be fabricated when no runtime CSI-RS trial stream exists.");
assert(any(strcmp(string(unavailableNoCSIRS.output_name), "csi_rs_table") & contains(string(unavailableNoCSIRS.unavailable_reason), "runtime_source_artifact_missing")), ...
    "Missing CSI-RS runtime stream must be reported as an explicit missing runtime source, not schema-only success.");

ok = true;
end

function localCreateSourceArtifacts(layout)
dirs = {layout.ReportCSVDir, layout.PacketFlowCSVDir, layout.RFCSVDir, layout.SystemCSVDir, ...
    layout.AirInterfaceCSVDir, layout.ControlCSVDir, layout.BeamformingCSVDir, fullfile(layout.SystemDir, "tables")};
for i = 1:numel(dirs)
    if exist(dirs{i}, "dir") ~= 7
        mkdir(dirs{i});
    end
end

localWrite(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), table( ...
    "dummy_commit", 30, 10, 14, "DDDDU", "TDD", 1234, ...
    'VariableNames', {'CodeCommit','SCS_kHz','SlotsPerFrame','SymbolsPerSlot','ConfiguredTDDPattern','ActiveDuplexMode','RandomSeed'}));
localWrite(fullfile(layout.ReportCSVDir, "deployment_layout_reference.csv"), table( ...
    19, 3, 57, 100, 600, "random_waypoint", ...
    'VariableNames', {'NumSites','SectorsPerSite','NumCells','NumUEs','InterSiteDistance_m','MobilityModel'}));
localWrite(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"), table( ...
    "DL", "slot_coupled_truth", "full_per_link_channel_waveform_sum", ...
    'VariableNames', {'Direction','ExecutionModel','InterferenceMode'}));

siteID = repelem((1:19)', 3);
sectorID = repmat((1:3)', 19, 1);
trpID = (1:57)';
sectorTable = table(siteID, sectorID, trpID, repmat(46, 57, 1), repmat("physical_192AE_64TXRU_profile", 57, 1), zeros(57, 1), ...
    'VariableNames', {'site_id','sector_id','trp_id','max_tx_power_dbm','array_geometry_id','boresight_deg'});
localWrite(fullfile(layout.SystemDir, "tables", "sectors.csv"), sectorTable);
localWrite(fullfile(layout.SystemDir, "tables", "sites.csv"), table((1:19)', zeros(19, 1), zeros(19, 1), repmat(46, 19, 1), ...
    'VariableNames', {'site_id','x_m','y_m','max_tx_power_dbm'}));
localWrite(fullfile(layout.SystemDir, "tables", "ues.csv"), table((1:100)', zeros(100, 1), zeros(100, 1), ...
    'VariableNames', {'ue_id','x_m','y_m'}));

localWrite(fullfile(layout.SystemCSVDir, "system_cell_load.csv"), table( ...
    [1; 2], [1; 1], [1; 2], [1; 0], [0.40; 0.55], [0.10; 0.20], ...
    'VariableNames', {'TTI','CellID','ActiveUE_DL','ActiveUE_UL','DLLoad','ULLoad'}));
localWrite(fullfile(layout.SystemCSVDir, "system_interference_detail.csv"), table( ...
    [1; 2], [1; 1], [1; 1], [0.001; 0.002], [100; 120], [-70; -72], [-95; -95], ...
    [-70; -72], [-88; -87], [-95; -95], [-78; -79], [-92; -91], [-96; -96], [10; -2], [6; 4], [-82; -84], ...
    'VariableNames', {'UE','ServingCell','CellID','Time_s','Pathloss_dB','RxPower_dBm','Noise_dBm', ...
    'DesiredPowerDL_dBm','InterferencePowerDL_dBm','NoiseDL_dBm','DesiredPowerUL_dBm','InterferencePowerUL_dBm','NoiseUL_dBm','SINR_DL_dB','SINR_UL_dB','RSRP_dBm'}));
localWrite(fullfile(layout.SystemCSVDir, "system_harq_processes.csv"), table( ...
    [1; 2], [0.001; 0.002], ["DL"; "DL"], [1; 1], [1; 1], [3; 3], [0; 0], [true; true], [false; true], ["ACK"; "ACK"], [4096; 4096], [10; 10], [8; 8], [0.1; 0.05], ...
    'VariableNames', {'TTI','Time_s','Direction','CellID','UE','HarqID','RV','NDI','IsRetransmission','Outcome','TBSBits','MCSIndex','CQIUsed','BLER'}));
localWrite(fullfile(layout.SystemCSVDir, "system_beam_events.csv"), table( ...
    [1; 2], [1; 1], [1; 2], [2; 3], [0; 1], [2.5; 3.0], ["beam_update"; "beam_update"], ...
    'VariableNames', {'UE','ServingCell','PrevBeamIndex','NewBeamIndex','PrevBeamGain_dB','NewBeamGain_dB','EventType'}));
localWrite(fullfile(layout.SystemCSVDir, "system_ue_summary.csv"), table( ...
    [1; 2], ["edge"; "center"], ["EMBB"; "XR"], [false; true], [3; 30], [100; 200], [12; 24], [10; 4], [0.1; 0.2], [1024; 2048], ...
    'VariableNames', {'UE','Zone','TrafficClass','Indoor','Speed_kmh','MeanServingDistance_m','Throughput_Mbps','MeanSINR_dB','MeanBLER','MeanQueue_bits'}));

grant = table([1; 2], [0.001; 0.002], ["DL"; "DL"], [1; 1], [1; 2], [0; 10], [8; 6], [2; 2], [12; 12], ...
    [4096; 2048], [8; 6], [10; 8], [1; 1], [0.5; 0.4], [12; 8], [0.1; 0.2], [true; false], [3; 4], [0; 1], [true; true], [false; true], ["pf"; "pf"], ...
    'VariableNames', {'TTI','Time_s','Direction','CellID','UE','PRBStart','PRBCount','SymbolStart','NumSymbols', ...
    'TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate','SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','GrantReason'});
localWrite(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), grant);
ulGrant = grant(1, :);
ulGrant.Direction = "UL";
ulGrant.PRBStart = 30;
ulGrant.PRBCount = 4;
localWrite(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), ulGrant);

dlTrial = table("DL", 0.001, 1, 1, 1, 320, 4096, true, 8, 10, 1, "QPSK", ...
    "fixed", "fixed", 2, 3, true, "2", "applied_runtime_value", 4, 4, "applied_runtime_value", ...
    "dl_precoder_runtime", "dl_precoder_runtime", "codebook", "waveform_precoder", true, true, false, false, 8, 1, 8, 1, ...
    'VariableNames', {'Direction','Time_s','Frame','Slot','CellID','RNTI','BitsCompared','CRCPass','MCSIndex','CQIUsed','NumLayers','Modulation', ...
    'ConfiguredBeamSelectionStrategy','BeamSelectionStrategy','SelectedBeamIndex','BestBeamIndex','BeamHit','AppliedBeamIndexSet','AppliedBeamTruthClassification', ...
    'RequestedPrecoderPMI','AppliedPrecoderPMI','AppliedPrecoderPMITruthClassification','PrecoderSource','AppliedPrecoderSource','PrecodingMode', ...
    'PrecodingApplicationStage','PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied','BeamformingApplied','PrecodingNumPorts','PrecodingNumLayers', ...
    'PrecodingMatrixRows','PrecodingMatrixCols'});
ulTrial = table("UL", 0.001, 1, 1, 1, 320, 2048, true, 6, 8, 1, "QPSK", ...
    "fixed", "fixed", 2, 3, true, "2", "requested_reference", 0, 0, "applied_runtime_value", ...
    "ul_pusch_native_codebook_tpmi", "ul_pusch_native_codebook_tpmi", "ul_codebook_tpmi", ...
    "nrPUSCH_native_codebook_precoding_during_modulation", true, false, false, true, 1, 1, 1, 1, ...
    'VariableNames', {'Direction','Time_s','Frame','Slot','CellID','RNTI','BitsCompared','CRCPass','MCSIndex','CQIUsed','NumLayers','Modulation', ...
    'ConfiguredBeamSelectionStrategy','BeamSelectionStrategy','SelectedBeamIndex','BestBeamIndex','BeamHit','RequestedBeamIndexSet','RequestedBeamTruthClassification', ...
    'RequestedPrecoderPMI','AppliedPrecoderPMI','AppliedPrecoderPMITruthClassification','PrecoderSource','AppliedPrecoderSource','PrecodingMode', ...
    'PrecodingApplicationStage','PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied','BeamformingApplied','PrecodingNumPorts','PrecodingNumLayers', ...
    'PrecodingMatrixRows','PrecodingMatrixCols'});
ulTrial.AppliedPrecoderPMIType = "pusch_codebook";
ulTrial.AppliedPrecoderCodebookMode = "codebook1_ng1n4n1";
ulTrial.AppliedBeamIndexSet = "1";
ulTrial.AppliedBeamTruthClassification = "applied_runtime_value";
ulTrial.AppliedBeamApplicationSource = "ul_pusch_native_codebook_tpmi_port_support";
ulTrial.AppliedPrecoderPMIApplicationSource = "ul_pusch_native_codebook_tpmi";
ulTrial.RequestedVsAppliedPrecoderPMIMatchStatus = "requested_matches_runtime_applied";
dlTrial = localAddTimingLineage(dlTrial, 25, NaN, NaN, NaN, 25, NaN, 0, NaN, NaN, 0, NaN, false, true, ...
    "missing", "not_available_without_cfo_estimate", "NOT_AVAILABLE", ...
    "not_applicable_ideal_timing_sync", "not_applicable_ideal_timing_sync", "NOT_APPLICABLE");
ulTrial = localAddTimingLineage(ulTrial, 25, 20, 5, 20, 25, 5, 2, 1, 1, 2, 1, true, false, ...
    "available", "estimated_minus_true_runtime_cfo", "OK", ...
    "available_receiver_timing_estimate", "true_minus_estimated_timing_offset_samples", "OK");
dlTrial = localAddLatencyLineage(dlTrial, 0.20, 0.05, 0.50, 0.25, 0.10);
ulTrial = localAddLatencyLineage(ulTrial, 0.30, 0.10, 0.60, 0.25, 0.15);
localWrite(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dlTrial);
localWrite(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ulTrial);

localWrite(fullfile(layout.ControlCSVDir, "pbch_trials.csv"), localControlTrial("PBCH", "PASS", 1, 1, 1, 320));
localWrite(fullfile(layout.ControlCSVDir, "prach_trials.csv"), localControlTrial("PRACH", "PASS", 1, 1, 1, 320));
localWrite(fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), localControlTrial("PDCCH", "PASS", 1, 1, 1, 320));
localWrite(fullfile(layout.ControlCSVDir, "pucch_trials.csv"), localControlTrial("PUCCH", "PASS", 1, 1, 1, 320));
localWrite(fullfile(layout.ControlCSVDir, "srs_trials.csv"), localControlTrial("SRS", "PASS", 1, 1, 1, 320));
localWrite(fullfile(layout.AirInterfaceCSVDir, "csi_rs_trials.csv"), table( ...
    "DL", "CSI-RS", 18, 1, 1, 1, 0.001, 1, 0, 1, 320, 0, 0, "nzp", 2, 3, "one", "on", ...
    "0", "0", 0, 52, 208, true, true, true, true, "csi_feedback_reference_power_measurement", -72.5, ...
    "received_csirs_reference_signal_power", "observed_after_ofdm_demodulation", "runtime_grid_mapped", "", ...
    "sixgr.phy.dl.PDSCH_Rx:csirs_runtime_observation", true, ...
    'VariableNames', {'Direction','SignalFamily','SNR_dB','SFN','Frame','Slot','Time_s','CellID','BWPID','UEIndex','RNTI', ...
    'ResourceID','ResourceSetID','CSIRSType','NumPorts','RowNumber','Density','Periodicity','SymbolLocations','SubcarrierLocations', ...
    'RBOffset','NumRB','NRE','Scheduled','Transmitted','Observed','Consumed','Consumer','MeasurementRSRP_dB','MeasurementSource', ...
    'UpdateOutcome','RuntimeMaterializationStatus','RuntimeBlocker','RuntimeEvidenceSource','RuntimeEventObserved'}));
localWrite(fullfile(layout.ReportCSVDir, "live_receiver_tracking_trace.csv"), table( ...
    1, "TRS", true, "shared_receiver_tracking_state", "integrated_shared_tracking_object", "", ...
    "not_initialized", "valid", 0.004, 1, "updated_from_trs_runtime_observation", ...
    "fresh_trs_runtime_observation", "doppler_estimate_updated_from_trs", "not_updated_timing_estimate_unavailable", ...
    false, NaN, false, NaN, "trs_reference_waveform_estimator", 1, 5, 28, -18, ...
    'VariableNames', {'ServingCell','SourceSignal','TRSProcessed','TRSReceiverConsumerType','TRSReceiverIntegrationStatus','TRSReceiverIntegrationBlocker', ...
    'TRSTrackingStateBefore','TRSTrackingStateAfter','TRSTrackingUpdateTime_s','TRSAssociatedCell','TRSUpdateOutcome', ...
    'TRSChannelTrackingFreshnessState','TRSFrequencyTrackingState','TRSTimingTrackingState', ...
    'TRSTimingEstimateAvailable','TRSTimingEstimate_samples','TRSCFOEstimateAvailable','TRSEstimatedCFO_Hz', ...
    'TRSRuntimeEvidenceSource','Frame','Slot','EstimatedDopplerHz','NMSE_dB'}));

localWrite(fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"), table( ...
    ["ue"; "cell"], [1; 1], ["DL"; "DL"], [0; 0], [1; 2], [0.001; 0.001], [0.2; 1.5], [0.0002; 0.0015], [4096; 4096], [8; 8], [8; 64], ...
    [0; 0.00035], [0.03; NaN], [-80; -70], ["active_rx"; "active_full_bw"], [1; 1], [1; 1], ...
    'VariableNames', {'EntityType','EntityID','Direction','Frame','Slot','Duration_s','Power_W','Energy_J','SuccessfulBits','PRBCount','RFChainCount', ...
    'BBProcessingEnergy_J','TxPower_dBm','RxPowerEst_dBm','State','UEID','CellID'}));
end

function T = localControlTrial(signalFamily, status, frame, slot, ueIndex, rnti)
T = table(string(signalFamily), string(status), double(frame), double(slot), double(ueIndex), double(rnti), ...
    strcmpi(string(status), "PASS"), "runtime_control_trial", ...
    'VariableNames', {'SignalFamily','Status','Frame','Slot','UEIndex','RNTI','DecodeSuccess','RuntimeMaterializationStatus'});
end

function T = localAddTimingLineage(T, injectedCFO, estimatedCFOPre, residualCFOPost, estimatedCFO, trueCFO, cfoError, ...
    injectedTiming, estimatedTimingPre, residualTimingPost, trueTiming, timingError, timingEstimateUsed, useIdealTimingSync, ...
    cfoAvailability, cfoDefinition, cfoStatus, timingAvailability, timingDefinition, timingStatus)
T.InjectedCFO_Hz = injectedCFO;
T.EstimatedCFO_PreCorrection_Hz = estimatedCFOPre;
T.ResidualCFO_PostCorrection_Hz = residualCFOPost;
T.EstimatedCFO_Hz = estimatedCFO;
T.TrueCFO_Hz = trueCFO;
T.CFOError_Hz = cfoError;
T.InjectedTimingOffset_samples = injectedTiming;
T.RawTimingEstimate_samples = estimatedTimingPre;
T.AppliedTimingCorrection_samples = estimatedTimingPre;
T.EstimatedTimingOffset_PreCorrection_samples = estimatedTimingPre;
T.ResidualTimingError_PostCorrection_samples = residualTimingPost;
T.TrueTimingOffset_samples = trueTiming;
T.TimingError_samples = timingError;
T.TimingEstimateUsed = timingEstimateUsed;
T.UseIdealTimingSync = useIdealTimingSync;
T.TimingEstimateApplicationPolicy = string(ternaryTimingPolicy(timingEstimateUsed, useIdealTimingSync));
T.TimingEstimateStatus = string(ternaryTimingStatus(timingEstimateUsed, useIdealTimingSync));
T.TimingEstimateWasClipped = false;
T.CFOEstimateAvailability = string(cfoAvailability);
T.CFOErrorDefinition = string(cfoDefinition);
T.CFOValueStatus = string(cfoStatus);
T.TimingEstimateAvailability = string(timingAvailability);
T.TimingErrorDefinition = string(timingDefinition);
T.TimingValueStatus = string(timingStatus);
end

function value = ternaryTimingPolicy(timingEstimateUsed, useIdealTimingSync)
if logical(useIdealTimingSync)
    value = "timing_estimation_bypassed_no_runtime_correction";
elseif logical(timingEstimateUsed)
    value = "signed_waveform_shift_negative_padding_positive_crop_supported";
else
    value = "timing_estimate_unavailable_no_runtime_correction";
end
end

function value = ternaryTimingStatus(timingEstimateUsed, useIdealTimingSync)
if logical(useIdealTimingSync)
    value = "ideal_sync_bypass";
elseif logical(timingEstimateUsed)
    value = "available";
else
    value = "missing";
end
end

function T = localAddLatencyLineage(T, computeLatencyMs, decodeLatencyMs, procedureDelayMs, airInterfaceTTIMs, airInterfaceObservationMs)
T.ComputeLatency_ms = computeLatencyMs;
T.DecodeLatency_ms = decodeLatencyMs;
T.ProcedureDelay_ms = procedureDelayMs;
T.AirInterfaceTTI_ms = airInterfaceTTIMs;
T.AirInterfaceObservation_ms = airInterfaceObservationMs;
end

function localWrite(pathStr, T)
[folder, ~, ~] = fileparts(pathStr);
if exist(folder, "dir") ~= 7
    mkdir(folder);
end
writetable(T, pathStr);
end

function localAssertRegistryRow(T, name, status, classCode)
mask = strcmp(string(T.output_name), string(name));
assert(any(mask), "Registry missing output %s.", name);
idx = find(mask, 1, "first");
assert(strcmp(string(T.current_status(idx)), string(status)), ...
    "Registry row %s expected status %s but saw %s.", name, status, string(T.current_status(idx)));
assert(strcmp(string(T.classification_code(idx)), string(classCode)), ...
    "Registry row %s expected classification %s but saw %s.", name, classCode, string(T.classification_code(idx)));
end

function out = localAsLogical(values)
if islogical(values)
    out = values;
elseif isnumeric(values)
    out = values ~= 0;
else
    txt = lower(strtrim(string(values)));
    out = txt == "1" | txt == "true" | txt == "yes";
end
end
