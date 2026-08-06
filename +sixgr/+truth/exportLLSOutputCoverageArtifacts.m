function out = exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg)
%EXPORTLLSOUTPUTCOVERAGEARTIFACTS Emit truthful output-coverage artifacts for browser-owned LLS runs.

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.PacketFlowCSVDir);
sixgr.util.ensureFolder(layout.RFCSVDir);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
sixgr.util.ensureFolder(fullfile(runFolder, "analytics", "csv"));

localCoverageLog("start", runFolder);
src = localLoadSourceTables(layout);
meta = localBuildRunMeta(runFolder, scfg, cfg, src);
contract = sixgr.truth.llsOutputContract();
localCoverageLog("sources_loaded", runFolder);

tables = struct();
tables.table_scenario_topology = localBuildScenarioTopologyTable(src, meta, scfg);
tables.scenario_consistency_check_table = localBuildScenarioConsistencyCheckTable(src, meta, scfg);
tables.topology_density_table = localBuildTopologyDensityTable(src, meta, scfg);
tables.sector_utilization_summary_table = localBuildSectorUtilizationSummaryTable(src, meta);
tables.serving_cell_population_table = localBuildServingCellPopulationTable(src, meta);
tables.live_candidate_cell_runtime = localBuildCandidateCellRuntimeTable(src, meta);
tables.neighbor_degree_histogram_data = localBuildNeighborDegreeHistogramData(tables.live_candidate_cell_runtime, meta);
tables.table_gnb_cell = localBuildGNBCellTable(src, meta, cfg);
tables.table_channel_summary = localBuildChannelSummaryTable(src, meta, cfg);
tables.table_noise_interference = localBuildNoiseInterferenceTable(src, meta, cfg);
tables.table_link_budget = localBuildLinkBudgetTable(src, meta, cfg);
localCoverageLog("tables_core_topology_channel_built", runFolder);
localCoverageLog("building_live_prb_allocation", runFolder);
tables.live_prb_allocation = localBuildPRBAllocationTable(src, meta);
localCoverageLog("built_live_prb_allocation", runFolder);
localCoverageLog("building_live_re_allocation_snapshot", runFolder);
tables.live_re_allocation_snapshot = localBuildREAllocationSnapshotTable(src, tables.live_prb_allocation, meta, cfg);
localCoverageLog("built_live_re_allocation_snapshot", runFolder);
localCoverageLog("building_scheduler_decision", runFolder);
tables.table_scheduler_decision = localBuildSchedulerDecisionTable(src, meta);
localCoverageLog("built_scheduler_decision", runFolder);
localCoverageLog("building_prb_allocation_heatmap", runFolder);
tables.prb_allocation_heatmap = localBuildPRBAllocationHeatmapTable(tables.live_prb_allocation, meta);
localCoverageLog("built_prb_allocation_heatmap", runFolder);
localCoverageLog("building_dl_resource_grid_heatmap", runFolder);
tables.dl_resource_grid_heatmap = localBuildDirectionalGridHeatmapTable(tables.live_prb_allocation, "DL", meta);
localCoverageLog("built_dl_resource_grid_heatmap", runFolder);
localCoverageLog("building_ul_resource_grid_heatmap", runFolder);
tables.ul_resource_grid_heatmap = localBuildDirectionalGridHeatmapTable(tables.live_prb_allocation, "UL", meta);
localCoverageLog("built_ul_resource_grid_heatmap", runFolder);
localCoverageLog("building_dl_transport_block", runFolder);
tables.table_dl_transport_block = localBuildTransportBlockTable(src.DLTrials, src.DLGrants, "DL", meta);
localCoverageLog("built_dl_transport_block", runFolder);
localCoverageLog("building_ul_transport_block", runFolder);
tables.table_ul_transport_block = localBuildTransportBlockTable(src.ULTrials, src.ULGrants, "UL", meta);
localCoverageLog("built_ul_transport_block", runFolder);
localCoverageLog("building_harq_process", runFolder);
tables.table_harq_process = localBuildHARQProcessTable(src, meta);
localCoverageLog("built_harq_process", runFolder);
localCoverageLog("building_cqi_pmi_ri", runFolder);
tables.table_cqi_pmi_ri = localBuildCQIPMIRITable(src, meta);
localCoverageLog("built_cqi_pmi_ri", runFolder);
localCoverageLog("building_mcs_tbs_evolution", runFolder);
tables.table_mcs_tbs_evolution = localBuildMCSTBSEvolutionTable(src, meta);
localCoverageLog("built_mcs_tbs_evolution", runFolder);
localCoverageLog("tables_scheduler_transport_built", runFolder);
tables.table_latency = localBuildLatencyTable(src, meta);
tables.latency_cdf_plot = localBuildLatencyCDFTable(tables.table_latency, meta);
tables.latency_root_cause_table = localBuildLatencyRootCauseTable(tables.table_latency, meta);
tables.power_energy_table = localBuildPowerEnergyTable(src, meta, cfg);
tables.live_power_runtime_table = localBuildLivePowerRuntimeTable(src, tables.power_energy_table, meta, cfg);
tables.live_rf_power_table = localBuildLiveRFPowerTable(tables.live_power_runtime_table, meta);
tables.live_bb_power_table = localBuildLiveBBPowerTable(src, meta, cfg);
tables.live_energy_efficiency_table = localBuildLiveEnergyEfficiencyTable(tables.power_energy_table, meta, cfg);
tables.live_sleep_state_table = localBuildLiveSleepStateTable(src, meta, cfg);
tables.power_analytics = localBuildPowerAnalyticsTable(tables.live_power_runtime_table, meta);
tables.energy_efficiency_analytics = localBuildEnergyEfficiencyAnalyticsTable(tables.live_energy_efficiency_table, meta);
tables.runtime_power_analytics = localBuildRuntimePowerAnalyticsTable(tables.live_power_runtime_table, tables.live_bb_power_table, meta);
tables.sleep_state_analytics = localBuildSleepStateAnalyticsTable(tables.live_sleep_state_table, meta);
localCoverageLog("tables_latency_energy_built", runFolder);
tables.root_cause_candidate_table = localBuildRootCauseCandidateTable(src, meta);
tables.cell_edge_analytics_table = localBuildCellEdgeAnalyticsTable(src, meta);
tables.beam_stability_analytics_table = localBuildBeamStabilityAnalyticsTable(src, meta);
tables.energy_root_cause_table = localBuildEnergyRootCauseTable(tables.power_energy_table, meta);
tables.result_issue_registry = localBuildResultIssueRegistry(src, meta, tables);
tables.kpi_health_flags = localBuildKPIHealthFlags(src, meta);
tables.anomaly_window_table = localBuildAnomalyWindowTable(tables.result_issue_registry, meta);
tables.cross_layer_correlation_table = localBuildCrossLayerCorrelationTable(src, meta);
tables.hotspot_analytics_table = localBuildHotspotAnalyticsTable(src, meta);
tables.control_overhead_analytics_table = localBuildControlOverheadAnalyticsTable(src, meta);
tables.resource_overhead_analytics_table = localBuildResourceOverheadAnalyticsTable(tables.live_prb_allocation, meta);
tables.compare_run_prerequisites = localBuildCompareRunPrerequisitesTable(meta);
localCoverageLog("tables_root_cause_built", runFolder);
tables.pdcch_dci_table = localBuildRuntimeMirrorTable(src.PDCCHTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/pdcch_trials.csv|air_interface/csv/pdcch_trials.csv", ...
    "runtime_control_trial_rows", "DL");
tables.ssb_pbch_table = localBuildRuntimeMirrorTable(src.PBCHTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/pbch_trials.csv|air_interface/csv/pbch_trials.csv", ...
    "runtime_control_trial_rows", "DL");
tables.prach_table = localBuildRuntimeMirrorTable(src.PRACHTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/prach_trials.csv|air_interface/csv/prach_trials.csv", ...
    "runtime_control_trial_rows", "UL");
tables.pucch_table = localBuildPUCCHRuntimeTable(src, meta);
tables.pusch_table = localBuildRuntimeMirrorTable(src.ULTrials, meta, ...
    "sixgr.link.runULPUSCHThroughput", "air_interface/csv/ul_pusch_trials.csv", ...
    "runtime_air_interface_trial_rows", "UL");
tables.pdsch_table = localBuildRuntimeMirrorTable(src.DLTrials, meta, ...
    "sixgr.link.runDLPDSCHThroughput", "air_interface/csv/dl_pdsch_trials.csv", ...
    "runtime_air_interface_trial_rows", "DL");
tables.srs_table = localBuildRuntimeMirrorTable(src.SRSTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/srs_trials.csv|air_interface/csv/srs_trials.csv", ...
    "runtime_reference_signal_trial_rows", "UL");
tables.csi_rs_table = localBuildCSIRSRuntimeOrSummaryTable(src, meta);
tables.trs_receiver_tracking_table = localBuildRuntimeMirrorTable(src.ReceiverTrackingTrace, meta, ...
    "sixgr.truth.CoupledTruthRuntime.writeTables", "reports/csv/live_receiver_tracking_trace.csv", ...
    "runtime_receiver_tracking_trace_rows", "DL");
publicTables = sixgr.truth.buildLLSPublicOutputTables(tables, contract, meta);
publicNames = fieldnames(publicTables);
for iPublic = 1:numel(publicNames)
    tables.(publicNames{iPublic}) = publicTables.(publicNames{iPublic});
end
localCoverageLog("tables_control_built", runFolder);
tables.beam_precoder_table = localBuildBeamPrecoderTable(src, meta);
tables.beamforming_analytics_table = localBuildBeamformingAnalyticsTable(tables.beam_precoder_table, meta);
tables.mimo_rank_utilization_table = localBuildMIMORankUtilizationTable(tables.beam_precoder_table, meta);
tables.rank_layer_usage_histogram = localBuildRankLayerUsageHistogram(tables.mimo_rank_utilization_table, meta);
tables.timing_synchronization_table = localBuildTimingSynchronizationTable(src, meta);
tables.doppler_time_variation_plot = localBuildDopplerTimeVariationTable(src, meta);
localCoverageLog("tables_beam_timing_built", runFolder);
tables.mobility_adequacy_report = sixgr.analytics.buildMobilityAdequacyReport(scfg, src.DLTrials, runFolder);
tables.harq_combining_gain = sixgr.analytics.measureHARQCombiningGain(src.DLTrials, runFolder);
sixgr.analytics.buildRuntimeCallGraph(runFolder);
sixgr.truth.buildProvenanceManifest(scfg, runFolder);
sixgr.analytics.buildPhase7ReadinessArtifacts(scfg, runFolder);
tables.runtime_call_graph = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_call_graph.csv"));
tables.phase7_truth_gates = localReadOptionalTable(fullfile(layout.ReportCSVDir, "phase7_truth_gates.csv"));
localCoverageLog("tables_prompt8_adequacy_built", runFolder);
localCoverageLog("tables_built", runFolder);

logicalPaths = struct( ...
    "table_scenario_topology", "reports/csv/table_scenario_topology.csv", ...
    "scenario_consistency_check_table", "reports/csv/scenario_consistency_check_table.csv", ...
    "topology_density_table", "reports/csv/topology_density_table.csv", ...
    "sector_utilization_summary_table", "reports/csv/sector_utilization_summary_table.csv", ...
    "serving_cell_population_table", "reports/csv/serving_cell_population_table.csv", ...
    "live_candidate_cell_runtime", "reports/csv/live_candidate_cell_runtime.csv", ...
    "neighbor_degree_histogram_data", "reports/csv/neighbor_degree_histogram_data.csv", ...
    "table_gnb_cell", "reports/csv/table_gnb_cell.csv", ...
    "table_channel_summary", "reports/csv/table_channel_summary.csv", ...
    "table_noise_interference", "reports/csv/table_noise_interference.csv", ...
    "table_link_budget", "reports/csv/table_link_budget.csv", ...
    "doppler_time_variation_plot", "reports/csv/doppler_time_variation_plot.csv", ...
    "table_scheduler_decision", "packet_flow/csv/table_scheduler_decision.csv", ...
    "live_prb_allocation", "packet_flow/csv/live_prb_allocation.csv", ...
    "live_re_allocation_snapshot", "reports/csv/live_re_allocation_snapshot.csv", ...
    "prb_allocation_heatmap", "reports/csv/prb_allocation_heatmap.csv", ...
    "dl_resource_grid_heatmap", "reports/csv/dl_resource_grid_heatmap.csv", ...
    "ul_resource_grid_heatmap", "reports/csv/ul_resource_grid_heatmap.csv", ...
    "table_dl_transport_block", "reports/csv/table_dl_transport_block.csv", ...
    "table_ul_transport_block", "reports/csv/table_ul_transport_block.csv", ...
    "table_harq_process", "reports/csv/table_harq_process.csv", ...
    "table_cqi_pmi_ri", "reports/csv/table_cqi_pmi_ri.csv", ...
    "table_mcs_tbs_evolution", "reports/csv/table_mcs_tbs_evolution.csv", ...
    "pdsch_runtime_event_table", "reports/csv/pdsch_runtime_event_table.csv", ...
    "pusch_runtime_event_table", "reports/csv/pusch_runtime_event_table.csv", ...
    "pdcch_dci_public_table", "reports/csv/pdcch_dci_table.csv", ...
    "pucch_uci_table", "reports/csv/pucch_uci_table.csv", ...
    "prach_detection_table", "reports/csv/prach_detection_table.csv", ...
    "srs_measurement_table", "reports/csv/srs_measurement_table.csv", ...
    "csi_rs_runtime_event_table", "reports/csv/csi_rs_runtime_event_table.csv", ...
    "csi_report_table", "reports/csv/csi_report_table.csv", ...
    "trs_receiver_tracking_public_table", "reports/csv/trs_receiver_tracking_table.csv", ...
    "ssb_pbch_cell_search_table", "reports/csv/ssb_pbch_cell_search_table.csv", ...
    "noise_variance_evidence_table", "reports/csv/noise_variance_evidence_table.csv", ...
    "mcs_cqi_decision_trace_table", "reports/csv/mcs_cqi_decision_trace_table.csv", ...
    "lls_output_contract", "reports/csv/lls_output_contract.csv", ...
    "metric_definition_catalog", "reports/csv/metric_definition_catalog.csv", ...
    "metric_unit_role_catalog", "reports/csv/metric_unit_role_catalog.csv", ...
    "runtime_issue_registry", "reports/csv/runtime_issue_registry.csv", ...
    "table_latency", "reports/csv/table_latency.csv", ...
    "latency_cdf_plot", "reports/csv/latency_cdf_plot.csv", ...
    "power_energy_table", "rf/csv/power_energy_table.csv", ...
    "live_power_runtime_table", "reports/csv/live_power_runtime_table.csv", ...
    "live_rf_power_table", "reports/csv/live_rf_power_table.csv", ...
    "live_bb_power_table", "reports/csv/live_bb_power_table.csv", ...
    "live_energy_efficiency_table", "reports/csv/live_energy_efficiency_table.csv", ...
    "live_sleep_state_table", "reports/csv/live_sleep_state_table.csv", ...
    "power_analytics", "analytics/csv/power_analytics.csv", ...
    "energy_efficiency_analytics", "analytics/csv/energy_efficiency_analytics.csv", ...
    "runtime_power_analytics", "analytics/csv/runtime_power_analytics.csv", ...
    "sleep_state_analytics", "analytics/csv/sleep_state_analytics.csv", ...
    "root_cause_candidate_table", "reports/csv/root_cause_candidate_table.csv", ...
    "anomaly_window_table", "reports/csv/anomaly_window_table.csv", ...
    "cross_layer_correlation_table", "reports/csv/cross_layer_correlation_table.csv", ...
    "cell_edge_analytics_table", "reports/csv/cell_edge_analytics_table.csv", ...
    "hotspot_analytics_table", "reports/csv/hotspot_analytics_table.csv", ...
    "control_overhead_analytics_table", "reports/csv/control_overhead_analytics_table.csv", ...
    "resource_overhead_analytics_table", "reports/csv/resource_overhead_analytics_table.csv", ...
    "beam_stability_analytics_table", "reports/csv/beam_stability_analytics_table.csv", ...
    "latency_root_cause_table", "reports/csv/latency_root_cause_table.csv", ...
    "energy_root_cause_table", "reports/csv/energy_root_cause_table.csv", ...
    "kpi_health_flags", "reports/csv/kpi_health_flags.csv", ...
    "result_issue_registry", "reports/csv/result_issue_registry.csv", ...
    "compare_run_prerequisites", "reports/csv/compare_run_prerequisites.csv", ...
    "pdcch_dci_table", "control/csv/pdcch_dci_table.csv", ...
    "ssb_pbch_table", "control/csv/ssb_pbch_table.csv", ...
    "prach_table", "control/csv/prach_table.csv", ...
    "pucch_table", "control/csv/pucch_table.csv", ...
    "pusch_table", "control/csv/pusch_table.csv", ...
    "pdsch_table", "control/csv/pdsch_table.csv", ...
    "srs_table", "control/csv/srs_table.csv", ...
    "csi_rs_table", "control/csv/csi_rs_table.csv", ...
    "trs_receiver_tracking_table", "control/csv/trs_receiver_tracking_table.csv", ...
    "beam_precoder_table", "beamforming/csv/beam_precoder_table.csv", ...
    "beamforming_analytics_table", "beamforming/csv/beamforming_analytics_table.csv", ...
    "mimo_rank_utilization_table", "beamforming/csv/mimo_rank_utilization_table.csv", ...
    "rank_layer_usage_histogram", "beamforming/csv/rank_layer_usage_histogram.csv", ...
    "timing_synchronization_table", "control/csv/timing_synchronization_table.csv", ...
    "mobility_adequacy_report", "reports/csv/mobility_adequacy_report.csv", ...
    "harq_combining_gain", "air_interface/csv/harq_combining_gain.csv", ...
    "runtime_call_graph", "reports/csv/runtime_call_graph.csv", ...
    "phase7_truth_gates", "reports/csv/phase7_truth_gates.csv");

names = fieldnames(logicalPaths);
for i = 1:numel(names)
    name = names{i};
    T = tables.(name);
    if istable(T) && ~isempty(T)
        localWriteTableArtifacts(runFolder, logicalPaths.(name), T);
    end
end
localCoverageLog("table_artifacts_written", runFolder);

heatmapImagePath = "";
energyImagePath = "";
if ~isempty(tables.prb_allocation_heatmap)
    localCoverageLog("writing_prb_heatmap", runFolder);
    heatmapImagePath = fullfile(layout.ReportImageDir, "prb_allocation_heatmap.png");
    localWritePRBHeatmapFigure(tables.prb_allocation_heatmap, heatmapImagePath, "reports/image/prb_allocation_heatmap.png");
end
if ~isempty(tables.power_energy_table)
    localCoverageLog("writing_power_energy_figure", runFolder);
    energyImagePath = fullfile(layout.ReportImageDir, "power_energy_cumulative.png");
    localWritePowerEnergyFigure(tables.power_energy_table, energyImagePath, "reports/image/power_energy_cumulative.png");
end
localCoverageLog("figure_artifacts_written", runFolder);

provenanceTables = sixgr.truth.buildLLSReportingProvenanceTables(runFolder, tables, logicalPaths, contract.Outputs, meta);
provenanceTables.visual_artifact_integrity = sixgr.visual.verifyVisualArtifacts(runFolder, provenanceTables.plot_manifest);
provenanceNames = fieldnames(provenanceTables);
for iProv = 1:numel(provenanceNames)
    tables.(provenanceNames{iProv}) = provenanceTables.(provenanceNames{iProv});
end
lateLogicalPaths = struct( ...
    "plot_manifest", "reports/csv/plot_manifest.csv", ...
    "plot_render_status", "reports/csv/plot_render_status.csv", ...
    "chart_source_registry", "reports/csv/chart_source_registry.csv", ...
    "plot_suppression_table", "reports/csv/plot_suppression_table.csv", ...
    "unavailable_plot_card_registry", "reports/csv/unavailable_plot_card_registry.csv", ...
    "plot_data_quality_table", "reports/csv/plot_data_quality_table.csv", ...
    "visual_artifact_integrity", "reports/csv/visual_artifact_integrity.csv", ...
    "raw_to_derived_lineage", "reports/csv/raw_to_derived_lineage.csv", ...
    "table_field_availability_matrix", "reports/csv/table_field_availability_matrix.csv");
lateNames = fieldnames(lateLogicalPaths);
for i = 1:numel(lateNames)
    name = lateNames{i};
    logicalPaths.(name) = lateLogicalPaths.(name);
    T = tables.(name);
    if istable(T)
        localWriteTableArtifacts(runFolder, lateLogicalPaths.(name), T);
    end
end
tables.visual_artifact_audit = localRunVisualArtifactAuditTool(runFolder);
logicalPaths.visual_artifact_audit = "reports/csv/visual_artifact_audit.csv";
if istable(tables.visual_artifact_audit)
    localWriteTableArtifacts(runFolder, logicalPaths.visual_artifact_audit, tables.visual_artifact_audit);
end
tables.visual_artifact_integrity = localMergeVisualArtifactAuditFailures(tables.visual_artifact_integrity, tables.visual_artifact_audit);
localWriteTableArtifacts(runFolder, "reports/csv/visual_artifact_integrity.csv", tables.visual_artifact_integrity);

logicalPaths.lls_implementation_register = "reports/csv/lls_implementation_register.csv";
[registry, unavailable] = localBuildCoverageRegistry(runFolder, meta, src, tables, logicalPaths, heatmapImagePath, energyImagePath);
localCoverageLog("coverage_registry_built", runFolder);
tables.lls_implementation_register = localBuildImplementationRegister(registry, table(), table(), table(), unavailable, meta, logicalPaths);
completeness = localBuildOutputCompletenessTable(runFolder, registry, tables, logicalPaths, meta);
instrumentation = localBuildInstrumentationCoverageTable(registry, meta);
apiAudit = localBuildAPIExposureAuditTable(registry, logicalPaths, tables, meta);
persistence = localBuildPersistenceAuditTable(runFolder, registry, logicalPaths, tables, meta);
implementationRegister = localBuildImplementationRegister(registry, completeness, apiAudit, persistence, unavailable, meta, logicalPaths);
tables.lls_implementation_register = implementationRegister;
localCoverageLog("coverage_audits_built", runFolder);

localWriteTableArtifacts(runFolder, "reports/csv/output_coverage_registry.csv", registry);
localWriteTableArtifacts(runFolder, "reports/csv/lls_implementation_register.csv", implementationRegister);
localWriteTableArtifacts(runFolder, "reports/csv/output_completeness_table.csv", completeness);
localWriteTableArtifacts(runFolder, "reports/csv/instrumentation_coverage_table.csv", instrumentation);
localWriteTableArtifacts(runFolder, "reports/csv/api_exposure_audit_table.csv", apiAudit);
localWriteTableArtifacts(runFolder, "reports/csv/persistence_audit_table.csv", persistence);
localWriteTableArtifacts(runFolder, "reports/csv/honest_unavailable_registry.csv", unavailable);
localCoverageLog("coverage_tables_written", runFolder);

measurementSidecars = sixgr.truth.exportLLSMeasurementSidecars(runFolder);
tables.measurement_sidecar_manifest = measurementSidecars.Manifest;
tables.measurement_output_integrity_audit = measurementSidecars.Audit;
logicalPaths.measurement_sidecar_manifest = "reports/csv/measurement_sidecar_manifest.csv";
logicalPaths.measurement_output_integrity_audit = "reports/csv/measurement_output_integrity_audit.csv";
localCoverageLog("measurement_sidecars_written", runFolder);

localReconcileLiveStageControlAttemptCounts(runFolder);
localCoverageLog("live_stage_control_counts_reconciled", runFolder);

% buildPhase7ReadinessArtifacts runs before the late coverage figures are
% emitted. Refresh publication readiness now so completeness is based on
% the final filesystem, not on the pre-publication scan.
publicationReadiness = sixgr.analytics.evaluatePublicationReadinessGates(cfg, runFolder);
localCoverageLog("publication_readiness_refreshed", runFolder);

inventory = localBuildArtifactInventory(runFolder);
localWriteTableArtifacts(runFolder, "reports/csv/artifact_inventory.csv", inventory);
localCoverageLog("inventory_written", runFolder);

out = struct();
out.Tables = struct();
out.TableSummaries = localBuildTableSummaries(tables, logicalPaths, runFolder);
out.OutputCoverageRegistry = registry;
out.ImplementationRegister = implementationRegister;
out.OutputCompletenessTable = completeness;
out.InstrumentationCoverageTable = instrumentation;
out.APIExposureAuditTable = apiAudit;
out.PersistenceAuditTable = persistence;
out.HonestUnavailableRegistry = unavailable;
out.MeasurementSidecars = measurementSidecars;
out.VisualArtifactIntegrity = tables.visual_artifact_integrity;
out.VisualArtifactIntegrityOk = all(logical(tables.visual_artifact_integrity.IntegrityOk));
out.UpdatedArtifactInventory = inventory;
out.PublicationReadiness = publicationReadiness;
out.ManifestUnavailableEntries = localManifestUnavailableEntries(unavailable);
localCoverageLog("done", runFolder);
end

function src = localLoadSourceTables(layout)
src = struct();
src.Deployment = localReadOptionalTable(fullfile(layout.ReportCSVDir, "deployment_layout_reference.csv"));
src.RuntimeOperatingMode = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
src.ScenarioSummary = localReadOptionalTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
src.SlotTrace = localReadFirstOptionalTable( ...
    fullfile(layout.PacketFlowCSVDir, "slot_trace.csv"), ...
    fullfile(layout.ReportCSVDir, "slot_trace.csv"));
src.DLGrants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"));
src.ULGrants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"));
src.DLTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
src.ULTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
src.PBCHTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "pbch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"));
src.PRACHTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "prach_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"));
src.PDCCHTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"));
src.PUCCHTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "pucch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"));
src.PUCCHGrants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_pucch_grants.csv"));
src.SRSTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "srs_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"));
src.CSIRSTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "csi_rs_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "csi_rs_trials.csv"));
src.TRSTrials = localReadFirstOptionalTable( ...
    fullfile(layout.ControlCSVDir, "trs_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"));
src.ReceiverTrackingState = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_receiver_tracking_state.csv"));
src.ReceiverTrackingTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_receiver_tracking_trace.csv"));
src.LiveMobilityState = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_mobility_state.csv"));
src.LiveMeasurementFilterState = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_measurement_filter_state.csv"));
src.LiveSelectionState = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_selection_state.csv"));
src.CoverageLayer = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_coverage_layer.csv"));
src.LiveCellMeasurementTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_cell_measurement_trace.csv"));
src.UserPerformance = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"));
src.LiveCSIRSStats = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_csirs_stats.csv"));
src.EqualizedConstellations = localReadOptionalTable(fullfile(layout.ReportCSVDir, "equalized_constellations.csv"));
src.ChannelSnapshots = localReadOptionalTable(fullfile(layout.ReportCSVDir, "channel_snapshots.csv"));
src.AntennaConfigResolved = localReadOptionalTable(fullfile(layout.ReportCSVDir, "antenna_config_resolved.csv"));
src.PRACHCorrelationTraces = localReadFirstOptionalTable( ...
    fullfile(layout.ReportCSVDir, "prach_correlation_trace.csv"), ...
    fullfile(layout.ReportCSVDir, "prach_correlation_traces.csv"));
src.LivePDCCHStage = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_pdcch_stage_table.csv"));
src.LiveSSBStage = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_ssb_stage_table.csv"));
src.LiveHARQTimeline = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_harq_timeline.csv"));
src.LiveBeamSelectionTable = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_beam_selection_table.csv"));
src.EnergyTimeline = localReadOptionalTable(fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"));
src.EnergySummary = localReadOptionalTable(fullfile(layout.RFCSVDir, "probe_rf_energy.csv"));
src.HARQTimeline = localReadOptionalTable(fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"));
src.HARQSummary = localReadOptionalTable(fullfile(layout.HARQCSVDir, "live_harq_observation_summary.csv"));
src.BeamPrecoder = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "beam_precoder_table.csv"));
src.SystemCellLoad = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_cell_load.csv"));
src.SystemInterference = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_interference_detail.csv"));
src.SystemHARQ = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_harq_processes.csv"));
src.SystemBeam = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_beam_events.csv"));
src.SystemUE = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_ue_summary.csv"));
src.SystemHandover = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_handover_events.csv"));
src.SystemTimeSeries = localReadOptionalTable(fullfile(layout.SystemCSVDir, "system_time_series.csv"));
src.SystemSectors = localReadOptionalTable(fullfile(layout.SystemDir, "tables", "sectors.csv"));
src.SystemSites = localReadOptionalTable(fullfile(layout.SystemDir, "tables", "sites.csv"));
src.SystemTRPs = localReadOptionalTable(fullfile(layout.SystemDir, "tables", "trps.csv"));
src.SystemUEPositions = localReadOptionalTable(fullfile(layout.SystemDir, "tables", "ues.csv"));
src.SystemKPIs = localReadOptionalTable(fullfile(layout.SystemDir, "tables", "system_kpis.csv"));
if ~(istable(src.SystemSites) && ~isempty(src.SystemSites))
    src.SystemSites = localNormalizeTopologyReportTable(localReadOptionalTable(fullfile(layout.ReportCSVDir, "sites.csv")), "site");
end
if ~(istable(src.SystemSectors) && ~isempty(src.SystemSectors))
    src.SystemSectors = localNormalizeTopologyReportTable(localReadOptionalTable(fullfile(layout.ReportCSVDir, "sectors.csv")), "sector");
end
if ~(istable(src.SystemTRPs) && ~isempty(src.SystemTRPs))
    src.SystemTRPs = localNormalizeTopologyReportTable(localReadOptionalTable(fullfile(layout.ReportCSVDir, "trps.csv")), "trp");
end
if ~(istable(src.SystemUEPositions) && ~isempty(src.SystemUEPositions))
    src.SystemUEPositions = localNormalizeTopologyReportTable(localReadOptionalTable(fullfile(layout.ReportCSVDir, "ues.csv")), "ue");
end
end

function meta = localBuildRunMeta(runFolder, scfg, cfg, src)
storeState = sixgr.db.artifactStore("get_state");
summaryRow = localFirstRow(src.ScenarioSummary);
storedMeta = localReadStoredRunMetadata(runFolder);
meta = struct();
meta.run_id = double(localFirstFinite([ ...
    double(sixgr.util.structGet(storeState, "RunID", NaN)); ...
    double(sixgr.util.structGet(storedMeta, "run_id", NaN)); ...
    double(localParseRunIDFromFolder(runFolder))]));
meta.run_tag = localFirstNonEmptyString( ...
    string(sixgr.util.structGet(cfg, "run.runTag", "")), ...
    string(sixgr.util.structGet(storedMeta, "run_tag", "")));
meta.scenario_id = string(scfg.ScenarioID);
meta.scenario_variant_id = string(localScenarioGet(scfg, "meta.scenario_id", scfg.ScenarioID));
meta.scenario_name = string(localScenarioGet(scfg, "meta.scenario_name", localScenarioGet(scfg, "meta.description", scfg.ScenarioID)));
meta.config_hash = localFirstNonEmptyString(string(scfg.ConfigHash), string(sixgr.util.structGet(storedMeta, "config_hash", "")));
meta.code_commit = localFirstNonEmptyString(localResolveCodeCommit(summaryRow, runFolder), string(sixgr.util.structGet(storedMeta, "code_commit", "")));
meta.seed = double(localFirstFinite([ ...
    double(localScenarioGet(scfg, "simulation.random_seed", localTableValue(summaryRow, "RandomSeed", NaN))); ...
    double(sixgr.util.structGet(storedMeta, "seed", NaN))]));
meta.drop_id = NaN;
meta.run_folder = string(runFolder);
carrierDefaultHz = double(localScenarioStructGet(cfg, {"frequency.center_frequency_hz", "global_radio_scope.carrier_frequency_hz", "radio.center_frequency_hz"}, NaN));
bandwidthDefaultHz = double(localScenarioStructGet(cfg, {"frequency.bandwidth_hz", "global_radio_scope.channel_bandwidth_hz", "radio.bandwidth_hz"}, NaN));
meta.carrier_frequency_hz = double(localScenarioGet(scfg, "global_radio_scope.carrier_frequency_hz", localScenarioGet(scfg, "frequency.center_frequency_hz", carrierDefaultHz)));
meta.bandwidth_hz = double(localScenarioGet(scfg, "global_radio_scope.channel_bandwidth_hz", localScenarioGet(scfg, "frequency.bandwidth_hz", bandwidthDefaultHz)));
meta.scs_hz = 1e3 * double(localTableValue(summaryRow, "SCS_kHz", localScenarioGet(scfg, "frame.scs_khz", NaN)));
numerology = localResolveNumerology(meta.scs_hz / 1e3);
meta.slots_per_frame = double(localTableValue( ...
    summaryRow, "SlotsPerFrame", numerology.SlotsPerFrame));
meta.symbols_per_slot = double(localTableValue( ...
    summaryRow, "SymbolsPerSlot", numerology.SymbolsPerSlot));
localValidateSlotsPerFrame(meta.slots_per_frame, numerology);
if meta.symbols_per_slot ~= double(numerology.SymbolsPerSlot)
    error("sixgr:truth:exportLLSOutputCoverageArtifacts:NumerologyMismatch", ...
        "Persisted SymbolsPerSlot=%g conflicts with the canonical value %g.", ...
        meta.symbols_per_slot, double(numerology.SymbolsPerSlot));
end
meta.tdd_pattern = string(localTableValue(summaryRow, "ConfiguredTDDPattern", localScenarioGet(scfg, "frame_timing.tdd_pattern_name", "")));
meta.controlled_snr_sweep = logical(sixgr.util.structGet(cfg, ...
    "run.snrSweepEnabled", false)) && ...
    lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.noiseOperatingMode", "")))) == "standalone_awgn_snr_argument";
end

function meta = localReadStoredRunMetadata(runFolder)
meta = struct("run_id", NaN, "run_tag", "", "config_hash", "", "code_commit", "", "seed", NaN);
if nargin < 1 || strlength(string(runFolder)) == 0
    return;
end
manifestPath = fullfile(runFolder, "meta", "scenario_manifest.json");
if exist(manifestPath, "file") == 2
    try
        manifest = jsondecode(fileread(manifestPath));
        if isstruct(manifest)
            meta.config_hash = string(sixgr.util.structGet(manifest, "ConfigHash", ""));
            meta.seed = double(sixgr.util.structGet(manifest, "RandomSeed", NaN));
            meta.run_tag = localResolveRunTagFromStoredFolder(string(sixgr.util.structGet(manifest, "RunFolder", "")));
            meta.code_commit = localResolveStoredCodeCommit(manifest);
        end
    catch
    end
end
runtimeSummaryPath = fullfile(runFolder, "meta", "runtime_summary.json");
if exist(runtimeSummaryPath, "file") == 2
    try
        runtimeSummary = jsondecode(fileread(runtimeSummaryPath));
        if isstruct(runtimeSummary)
            if ~(isfinite(meta.seed) && meta.seed > 0)
                meta.seed = double(sixgr.util.structGet(runtimeSummary, "RandomSeed", NaN));
            end
            meta.run_tag = localFirstNonEmptyString(meta.run_tag, ...
                localResolveRunTagFromStoredFolder(string(sixgr.util.structGet(runtimeSummary, "RunFolder", ""))));
            meta.code_commit = localFirstNonEmptyString(meta.code_commit, localResolveStoredCodeCommit(runtimeSummary));
        end
    catch
    end
end
meta.run_id = localParseRunIDFromFolder(runFolder);
end

function runID = localParseRunIDFromFolder(runFolder)
runID = NaN;
token = regexp(char(string(runFolder)), '[\\/]run(\d+)$', 'tokens', 'once');
if ~isempty(token)
    runID = str2double(string(token{1}));
end
end

function runTag = localResolveRunTagFromStoredFolder(pathValue)
runTag = "";
pathValue = string(pathValue);
if strlength(strtrim(pathValue)) == 0
    return;
end
[~, name, ext] = fileparts(char(pathValue));
runTag = string(name) + string(ext);
if strlength(strtrim(runTag)) == 0
    runTag = "";
end
end

function commit = localResolveStoredCodeCommit(T)
commit = "";
if ~isstruct(T)
    return;
end
commit = localFirstNonEmptyString( ...
    string(sixgr.util.structGet(T, "CodeCommit", "")), ...
    string(sixgr.util.structGet(T, "CodeVersion", "")), ...
    string(sixgr.util.structGet(T, "CodeDetail", "")));
if startsWith(lower(strtrim(commit)), "git:")
    commit = extractAfter(commit, 4);
end
hashToken = regexp(char(commit), 'hash=([0-9a-fA-F]+)', 'tokens', 'once');
if ~isempty(hashToken)
    commit = string(hashToken{1});
end
end

function out = localFirstNonEmptyString(varargin)
out = "";
for i = 1:nargin
    value = string(varargin{i});
    value = strip(value);
    mask = strlength(value) > 0 & lower(value) ~= "not_applicable";
    if any(mask)
        out = value(find(mask, 1, "first"));
        return;
    end
end
end

function T = localNormalizeTopologyReportTable(T, kind)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
kind = lower(string(kind));
vars = string(T.Properties.VariableNames);
switch kind
    case "site"
        T = localRenameVarsIfPresent(T, ["SiteID","X_m","Y_m","Z_m","Lat","Lon"], ...
            ["site_id","x_m","y_m","z_m","lat","lon"]);
    case "sector"
        T = localRenameVarsIfPresent(T, ["SiteID","SectorID","Azimuth_deg","X_m","Y_m","Z_m","Lat","Lon"], ...
            ["site_id","sector_id","azimuth_deg","x_m","y_m","z_m","lat","lon"]);
        if ~ismember("trp_id", string(T.Properties.VariableNames))
            if ismember("sector_id", string(T.Properties.VariableNames))
                T.trp_id = double(T.sector_id);
            else
                T.trp_id = nan(height(T), 1);
            end
        end
        if ~ismember("max_tx_power_dbm", string(T.Properties.VariableNames))
            T.max_tx_power_dbm = nan(height(T), 1);
        end
        if ~ismember("array_geometry_id", string(T.Properties.VariableNames))
            T.array_geometry_id = strings(height(T), 1);
        end
    case "trp"
        T = localRenameVarsIfPresent(T, ["TRPID","SiteID","SectorID","Azimuth_deg","TxPower_dBm","X_m","Y_m","Z_m","Lat","Lon"], ...
            ["trp_id","site_id","sector_id","azimuth_deg","max_tx_power_dbm","x_m","y_m","z_m","lat","lon"]);
    case "ue"
        T = localRenameVarsIfPresent(T, ["UEID","X_m","Y_m","Z_m","Lat","Lon","Indoor","Speed_kmh","Heading_deg"], ...
            ["ue_id","x_m","y_m","z_m","lat","lon","indoor","speed_kmh","heading_deg"]);
    otherwise
        return;
end
vars = string(T.Properties.VariableNames);
if ismember("site_id", vars)
    T.site_id = double(T.site_id);
end
if ismember("sector_id", vars)
    T.sector_id = double(T.sector_id);
end
if ismember("trp_id", vars)
    T.trp_id = double(T.trp_id);
end
if ismember("ue_id", vars)
    T.ue_id = double(T.ue_id);
end
end

function T = localRenameVarsIfPresent(T, oldNames, newNames)
oldNames = string(oldNames);
newNames = string(newNames);
present = ismember(oldNames, string(T.Properties.VariableNames));
if any(present)
    T = renamevars(T, cellstr(oldNames(present)), cellstr(newNames(present)));
end
end

function T = localBuildScenarioTopologyTable(src, meta, scfg)
deploymentRow = localFirstRow(src.Deployment);
systemSites = src.SystemSites;
systemSectors = src.SystemSectors;
systemUEs = src.SystemUEPositions;

numSites = localRuntimeCount(systemSites, "site_id", localTableValue(deploymentRow, "NumSites", localScenarioGet(scfg, "deployment_topology.num_sites", NaN)));
sectorsPerSite = localTableValue(deploymentRow, "SectorsPerSite", localScenarioGet(scfg, "deployment_topology.num_sectors_per_site", NaN));
if isnan(double(sectorsPerSite)) && istable(systemSectors) && ~isempty(systemSectors) ...
        && localHasVar(systemSectors, "site_id") && localHasVar(systemSectors, "sector_id")
    sectorsPerSite = numel(unique(double(systemSectors.sector_id(double(systemSectors.site_id) == double(systemSectors.site_id(1))))));
end
totalCells = localRuntimeCount(systemSectors, "trp_id", localTableValue(deploymentRow, "NumCells", localScenarioGet(scfg, "deployment_topology.num_cells", NaN)));
numUEs = localRuntimeCount(systemUEs, "ue_id", localTableValue(deploymentRow, "NumUEs", localScenarioGet(scfg, "deployment_topology.num_ues", NaN)));

row = struct();
row.run_id = meta.run_id;
row.scenario_id = meta.scenario_id;
row.scenario_name = meta.scenario_name;
row.scenario_variant = meta.scenario_variant_id;
row.seed = meta.seed;
row.drop_id = meta.drop_id;
row.topology_type = string(localScenarioGet(scfg, "deployment_topology.layout_type", "hexagonal_wraparound"));
row.num_sites = double(numSites);
row.sectors_per_site = double(sectorsPerSite);
row.total_cells = double(totalCells);
row.num_ues = double(numUEs);
row.inter_site_distance_m = double(localTableValue(deploymentRow, "InterSiteDistance_m", localScenarioGet(scfg, "deployment_topology.inter_site_distance", NaN)));
row.wraparound_enable = logical(localScenarioGet(scfg, "deployment_topology.wraparound_enabled", true));
row.wraparound_rings = double(localScenarioGet(scfg, "deployment_topology.wraparound_rings", NaN));
row.carrier_frequency_hz = meta.carrier_frequency_hz;
row.bandwidth_hz = meta.bandwidth_hz;
row.scs_hz = meta.scs_hz;
row.duplex_mode = string(localTableValue(localFirstRow(src.ScenarioSummary), "ActiveDuplexMode", localScenarioGet(scfg, "global_radio_scope.duplex_mode", "")));
row.tdd_pattern = meta.tdd_pattern;
row.channel_model_family = string(localScenarioGet(scfg, "channel_model.family", localScenarioGet(scfg, "channel_model.scenario_label", "")));
row.deployment_scenario = string(localScenarioGet(scfg, "deployment_topology.cell_type", "UMa"));
row.mobility_profile_name = string(localTableValue(deploymentRow, "MobilityModel", localScenarioGet(scfg, "mobility.trajectory_generator", "")));
row.traffic_mix_name = string(localScenarioGet(scfg, "traffic.model", localScenarioGet(scfg, "traffic_mix_mode", "")));
row.bs_array_profile = string(localScenarioGet(scfg, "base_station.array_profile", localScenarioGet(scfg, "system.bs_array_profile", "")));
row.ue_array_profile = string(localScenarioGet(scfg, "users.array_profile", ""));
row.scheduler_type = string(localScenarioGet(scfg, "system.scheduler.type", localScenarioGet(scfg, "scheduler_type", "")));
row.beam_management_enable = logical(localScenarioGet(scfg, "beam_management.enable", localScenarioGet(scfg, "mimo.beam_management_enable", true)));
row.csi_rs_enable = logical(localScenarioGet(scfg, "reference_signals.csirs_enabled", localScenarioGet(scfg, "csi_acquisition_and_reporting.csi_rs_enable", true)));
row.srs_enable = logical(localScenarioGet(scfg, "reference_signals.srs_enabled", localScenarioGet(scfg, "uplink_reference_signals.srs_enable", true)));
row.harq_enable = logical(localScenarioGet(scfg, "harq.enabled", localScenarioGet(scfg, "scheduler.hard_harq_enable", true)));
row.ai_branch_enable = logical(localScenarioGet(scfg, "ai_ml.enabled", false));
row.energy_logging_enable = logical(localScenarioGet(scfg, "energy_efficiency.energy_logging_enable", false));
row.status_source = string("runtime_populated");
row.population_mode = string("browser_owned_lls");
row.table_population_mode = string("runtime_populated");
T = struct2table(row);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildScenarioTopologyTable", ...
    "reports/csv/deployment_layout_reference.csv", "implemented", "runtime_populated", false, true);
end

function T = localBuildScenarioConsistencyCheckTable(src, meta, scfg)
topology = localFirstRow(localBuildScenarioTopologyTable(src, meta, scfg));
deploymentRow = localFirstRow(src.Deployment);
runtimeModeRow = localFirstRow(src.RuntimeOperatingMode);
scenarioSummaryRow = localFirstRow(src.ScenarioSummary);
expectedNumSites = localTableValue(deploymentRow, "NumSites", ...
    localScenarioGet(scfg, "deployment_topology.num_sites", localTableValue(topology, "num_sites", NaN)));
expectedSectorsPerSite = localTableValue(deploymentRow, "SectorsPerSite", ...
    localScenarioGet(scfg, "deployment_topology.num_sectors_per_site", localTableValue(topology, "sectors_per_site", NaN)));
expectedTotalCells = localTableValue(deploymentRow, "NumCells", ...
    localScenarioGet(scfg, "deployment_topology.num_cells", ...
    localScenarioGet(scfg, "deployment_topology.num_base_stations", localTableValue(topology, "total_cells", NaN))));
expectedNumUEs = localTableValue(deploymentRow, "NumUEs", ...
    localScenarioGet(scfg, "deployment_topology.num_ues", ...
    localScenarioGet(scfg, "users.n_users", localTableValue(topology, "num_ues", NaN))));
expectedCarrierHz = localScenarioGet(scfg, "frequency.center_frequency_hz", localTableValue(topology, "carrier_frequency_hz", NaN));
expectedBandwidthHz = localScenarioGet(scfg, "frequency.bandwidth_hz", localTableValue(topology, "bandwidth_hz", NaN));
expectedSCSHz = localTableValue(runtimeModeRow, "SCS_kHz", NaN);
if isfinite(double(expectedSCSHz))
    expectedSCSHz = 1.0e3 * double(expectedSCSHz);
else
    expectedSCSHz = localScenarioGet(scfg, "global_radio_scope.scs_hz", ...
        1.0e3 * double(localScenarioGet(scfg, "frame.scs_khz", localTableValue(topology, "scs_hz", NaN) / 1.0e3)));
end
expectedWraparound = double(logical(localTableValue(deploymentRow, "WraparoundEnabled", ...
    localScenarioGet(scfg, "deployment_topology.wraparound_enabled", localTableValue(topology, "wraparound_enable", false)))));
expectedDeploymentScenario = string(localScenarioGet(scfg, "deployment_topology.cell_type", localTableValue(topology, "deployment_scenario", "")));
expectedTDDPattern = string(localTableValue(scenarioSummaryRow, "ConfiguredTDDPattern", ...
    localScenarioGet(scfg, "frame.tdd_pattern", ...
    localScenarioGet(scfg, "frame_timing.tdd_pattern", localTableValue(topology, "tdd_pattern", "")))));
checks = {
    "num_sites_exact", expectedNumSites, localTableValue(topology, "num_sites", NaN), "resolved_config";
    "sectors_per_site_exact", expectedSectorsPerSite, localTableValue(topology, "sectors_per_site", NaN), "resolved_config";
    "total_cells_exact", expectedTotalCells, localTableValue(topology, "total_cells", NaN), "resolved_config";
    "num_ues_exact", expectedNumUEs, localTableValue(topology, "num_ues", NaN), "resolved_config";
    "carrier_frequency_hz_exact", expectedCarrierHz, localTableValue(topology, "carrier_frequency_hz", NaN), "resolved_config";
    "bandwidth_hz_exact", expectedBandwidthHz, localTableValue(topology, "bandwidth_hz", NaN), "resolved_config";
    "scs_hz_exact", expectedSCSHz, localTableValue(topology, "scs_hz", NaN), "resolved_config";
    "wraparound_enabled", expectedWraparound, double(localTableValue(topology, "wraparound_enable", false)), "resolved_config";
    "inter_cell_interference_enabled", 1, double(logical(localScenarioGet(scfg, "interference.inter_cell_interference_flag", true))), "resolved_config";
    "deployment_scenario_uma", expectedDeploymentScenario, localTableValue(topology, "deployment_scenario", ""), "resolved_config";
    "tdd_pattern_baseline", expectedTDDPattern, localTableValue(topology, "tdd_pattern", ""), "resolved_config";
};
rows = repmat(struct("CheckName", "", "ExpectedValue", "", "ActualValue", "", ...
    "CheckStatus", "", "ReasonCode", "", "BlockingFlag", false, "Source", ""), size(checks, 1), 1);
for i = 1:size(checks, 1)
    expected = checks{i, 2};
    actual = checks{i, 3};
    ok = localValuesEqual(expected, actual);
    rows(i).CheckName = string(checks{i, 1});
    rows(i).ExpectedValue = string(localScalarToString(expected));
    rows(i).ActualValue = string(localScalarToString(actual));
    rows(i).CheckStatus = string(localTernary(ok, "PASS", "FAIL"));
    rows(i).ReasonCode = string(localTernary(ok, "validated", "mismatch"));
    rows(i).BlockingFlag = true;
    rows(i).Source = string(checks{i, 4});
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildScenarioConsistencyCheckTable", ...
    "reports/csv/table_scenario_topology.csv", "implemented", "runtime_check_table", true, true);
end

function T = localBuildTopologyDensityTable(src, meta, scfg)
deploymentRow = localFirstRow(src.Deployment);
numSites = localRuntimeCount(src.SystemSites, "site_id", localTableValue(deploymentRow, "NumSites", localScenarioGet(scfg, "deployment_topology.num_sites", NaN)));
numSectors = localRuntimeCount(src.SystemSectors, "trp_id", localTableValue(deploymentRow, "NumCells", NaN));
numUEs = localRuntimeCount(src.SystemUEPositions, "ue_id", localTableValue(deploymentRow, "NumUEs", localScenarioGet(scfg, "deployment_topology.num_ues", NaN)));
isdM = double(localTableValue(deploymentRow, "InterSiteDistance_m", localScenarioGet(scfg, "deployment_topology.inter_site_distance", NaN)));
[areaM2, areaSource] = localTopologyAreaM2(src.SystemSites, src.SystemUEPositions, isdM, numSites);
if ~(isfinite(areaM2) && areaM2 > 0 && isfinite(numSites) && isfinite(numUEs))
    T = table();
    return;
end
row = struct();
row.geometry_epoch = 1;
row.site_count = double(numSites);
row.sector_count = double(numSectors);
row.ue_count = double(numUEs);
row.intersite_distance_m = isdM;
row.deployment_area_m2 = areaM2;
row.deployment_area_km2 = areaM2 / 1e6;
row.site_density_per_km2 = double(numSites) / row.deployment_area_km2;
row.sector_density_per_km2 = double(numSectors) / row.deployment_area_km2;
row.ue_density_per_km2 = double(numUEs) / row.deployment_area_km2;
row.density_value_role = "derived";
row.density_value_source = string(areaSource);
row.density_value_definition = "counts divided by runtime topology footprint area";
T = struct2table(row);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildTopologyDensityTable", ...
    "system/tables/sites.csv|system/tables/ues.csv|reports/csv/deployment_layout_reference.csv", ...
    "implemented", "derived_runtime_topology_density", true, true);
end

function T = localBuildSectorUtilizationSummaryTable(src, meta)
cellVals = unique([localColumnAsDouble(src.SystemSectors, "trp_id"); localColumnAsDouble(src.SystemCellLoad, "CellID"); ...
    localColumnAsDouble(src.DLGrants, "CellID"); localColumnAsDouble(src.ULGrants, "CellID")]);
cellVals = cellVals(isfinite(cellVals));
if isempty(cellVals)
    T = table();
    return;
end
rows = repmat(struct("cell_id", NaN, "site_id", NaN, "sector_id", NaN, "active_ues_avg", NaN, ...
    "active_ues_peak", NaN, "dl_load_avg", NaN, "ul_load_avg", NaN, "dl_grant_count", NaN, ...
    "ul_grant_count", NaN, "dl_prb_symbols", NaN, "ul_prb_symbols", NaN, ...
    "utilization_value_source", "", "utilization_value_definition", ""), numel(cellVals), 1);
for i = 1:numel(cellVals)
    cellId = cellVals(i);
    loadMask = localColumnMatches(src.SystemCellLoad, "CellID", cellId);
    sectorMask = localColumnMatches(src.SystemSectors, "trp_id", cellId);
    dlMask = localColumnMatches(src.DLGrants, "CellID", cellId);
    ulMask = localColumnMatches(src.ULGrants, "CellID", cellId);
    rows(i).cell_id = cellId;
    rows(i).site_id = localFirstFinite(localSelectColumn(src.SystemSectors, sectorMask, "site_id"));
    rows(i).sector_id = localFirstFinite(localSelectColumn(src.SystemSectors, sectorMask, "sector_id"));
    rows(i).active_ues_avg = localMeanFromMask(src.SystemCellLoad, loadMask, "ActiveUE_DL", "ActiveUE_UL");
    rows(i).active_ues_peak = localMaxFromMask(src.SystemCellLoad, loadMask, "ActiveUE_DL", "ActiveUE_UL");
    rows(i).dl_load_avg = localMeanFromMask(src.SystemCellLoad, loadMask, "DLLoad");
    rows(i).ul_load_avg = localMeanFromMask(src.SystemCellLoad, loadMask, "ULLoad");
    rows(i).dl_grant_count = sum(dlMask);
    rows(i).ul_grant_count = sum(ulMask);
    rows(i).dl_prb_symbols = localGrantPRBSymbols(src.DLGrants, dlMask);
    rows(i).ul_prb_symbols = localGrantPRBSymbols(src.ULGrants, ulMask);
    rows(i).utilization_value_source = "system/csv/system_cell_load.csv|packet_flow/csv/live_*_scheduler_grants.csv";
    rows(i).utilization_value_definition = "runtime active UE/load counters plus granted PRB-symbol totals per cell";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildSectorUtilizationSummaryTable", ...
    "system/csv/system_cell_load.csv|packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv", ...
    "implemented", "derived_runtime_sector_utilization", true, true);
end

function T = localBuildServingCellPopulationTable(src, meta)
servingCells = unique([ ...
    localColumnAsDouble(src.SystemInterference, "ServingCell"); ...
    localColumnAsDouble(src.CoverageLayer, "ServingCell")], "stable");
servingCells = servingCells(isfinite(servingCells));
if isempty(servingCells)
    T = table();
    return;
end
rows = repmat(struct("cell_id", NaN, "served_ue_count", NaN, "edge_ue_count", NaN, ...
    "mean_dl_sinr_db", NaN, "mean_ul_sinr_db", NaN, "mean_rsrp_dbm", NaN, ...
    "mean_pathloss_db", NaN, "population_value_source", ""), numel(servingCells), 1);
for i = 1:numel(servingCells)
    cellId = servingCells(i);
    mask = localColumnMatches(src.SystemInterference, "ServingCell", cellId);
    ueIDs = unique(localSelectColumn(src.SystemInterference, mask, "UE"));
    ueIDs = ueIDs(isfinite(ueIDs));
    rows(i).cell_id = cellId;
    rows(i).served_ue_count = numel(ueIDs);
    if ~(isfinite(rows(i).served_ue_count) && rows(i).served_ue_count > 0)
        covMask = localColumnMatches(src.CoverageLayer, "ServingCell", cellId);
        covUEs = unique(localSelectColumn(src.CoverageLayer, covMask, "UEID"));
        covUEs = covUEs(isfinite(covUEs));
        rows(i).served_ue_count = double(numel(covUEs));
    end
    rows(i).edge_ue_count = localEdgeUECount(src.SystemInterference, cellId);
    if ~isfinite(rows(i).edge_ue_count)
        rows(i).edge_ue_count = localCoverageEdgeUECount(src.CoverageLayer, cellId);
    end
    rows(i).mean_dl_sinr_db = localMeanFromMask(src.SystemInterference, mask, "SINR_DL_dB");
    if ~isfinite(rows(i).mean_dl_sinr_db)
        rows(i).mean_dl_sinr_db = localCoverageMeanByCell(src.CoverageLayer, cellId, ...
            "PostEqWidebandSINR_dB", "PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "LargeScaleWidebandSINR_dB", "LargeScaleSINR_dB");
    end
    rows(i).mean_ul_sinr_db = localMeanFromMask(src.SystemInterference, mask, "SINR_UL_dB");
    if ~isfinite(rows(i).mean_ul_sinr_db)
        rows(i).mean_ul_sinr_db = localMeanTrialMetricByCell(src.ULTrials, cellId, ...
            ["PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "LargeScaleWidebandSINR_dB", "LargeScaleSINR_dB"]);
    end
    rows(i).mean_rsrp_dbm = localMeanFromMask(src.SystemInterference, mask, "RSRP_dBm");
    if ~isfinite(rows(i).mean_rsrp_dbm)
        rows(i).mean_rsrp_dbm = localCoverageMeanByCell(src.CoverageLayer, cellId, "ServingRSRP_dBm", "RSRP_dBm");
    end
    rows(i).mean_pathloss_db = localMeanFromMask(src.SystemInterference, mask, "Pathloss_dB");
    if ~isfinite(rows(i).mean_pathloss_db)
        rows(i).mean_pathloss_db = localCoverageMeanByCell(src.CoverageLayer, cellId, "Pathloss_dB");
    end
    rows(i).population_value_source = localFirstNonEmptyString( ...
        localTernary(any(mask), "system/csv/system_interference_detail.csv", ""), ...
        localTernary(any(localColumnMatches(src.CoverageLayer, "ServingCell", cellId)), "reports/csv/live_coverage_layer.csv", ""));
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildServingCellPopulationTable", ...
    "system/csv/system_interference_detail.csv|reports/csv/live_coverage_layer.csv|air_interface/csv/ul_pusch_trials.csv", ...
    "implemented", "derived_runtime_serving_cell_population", true, true);
end

function T = localBuildCandidateCellRuntimeTable(src, meta)
if ~(istable(src.LiveCellMeasurementTrace) && ~isempty(src.LiveCellMeasurementTrace))
    T = table();
    return;
end
trace = src.LiveCellMeasurementTrace;
slot = localColumnAsDouble(trace, "Slot");
ueId = localColumnAsDouble(trace, "UEID");
candidateRank = localColumnAsDouble(trace, "CandidateRank");
cellId = localColumnAsDouble(trace, "CellID");
siteId = localColumnAsDouble(trace, "SiteID");
sectorId = localColumnAsDouble(trace, "SectorID");
timeS = localColumnAsDouble(trace, "Time_s");
lat = localColumnAsDouble(trace, "Lat");
lon = localColumnAsDouble(trace, "Lon");
rsrp = localColumnAsDouble(trace, "RSRP_dBm");
rxPower = localColumnAsDouble(trace, "RxPower_dBm");
pathloss = localColumnAsDouble(trace, "Pathloss_dB");
beamIndex = localColumnAsDouble(trace, "BeamIndex");
beamGain = localColumnAsDouble(trace, "BeamGain_dB");
losFlag = localColumnAsDouble(trace, "LOSFlag");
shadow = localColumnAsDouble(trace, "ShadowFading_dB");
o2i = localColumnAsDouble(trace, "O2I_dB");
valid = isfinite(slot) & isfinite(ueId) & isfinite(candidateRank) & isfinite(cellId);
if ~any(valid)
    T = table();
    return;
end
meas = table( ...
    1e3 * timeS(valid), slot(valid), ueId(valid), candidateRank(valid), cellId(valid), ...
    siteId(valid), sectorId(valid), lat(valid), lon(valid), rsrp(valid), rxPower(valid), ...
    pathloss(valid), beamIndex(valid), beamGain(valid), losFlag(valid), shadow(valid), o2i(valid), ...
    'VariableNames', { ...
        'timestamp_sim_ms', 'slot', 'ue_id', 'candidate_rank', 'cell_id', ...
        'site_id', 'sector_id', 'lat', 'lon', 'rsrp_dbm', 'rx_power_dbm', ...
        'pathloss_db', 'beam_id', 'beam_gain_db', 'los_flag', 'shadow_fading_db', 'o2i_db'});
servingState = localBuildServingStateTable(src);
if istable(servingState) && ~isempty(servingState)
    exactState = servingState(servingState.same_slot_match, :);
    exactState = exactState(:, {'ue_id','slot','serving_cell','serving_state_source','coverage_join_quality'});
    exactState = unique(exactState, 'rows', 'stable');
    meas = outerjoin(meas, exactState, 'Keys', {'ue_id', 'slot'}, 'MergeKeys', true, 'Type', 'left');
else
    meas.serving_cell = nan(height(meas), 1);
    meas.serving_state_source = repmat("", height(meas), 1);
    meas.coverage_join_quality = repmat("coverage_join_missing", height(meas), 1);
end
if ~ismember("serving_cell", string(meas.Properties.VariableNames))
    meas.serving_cell = nan(height(meas), 1);
end
if ~ismember("serving_state_source", string(meas.Properties.VariableNames))
    meas.serving_state_source = repmat("", height(meas), 1);
end
if ~ismember("coverage_join_quality", string(meas.Properties.VariableNames))
    meas.coverage_join_quality = repmat("coverage_join_missing", height(meas), 1);
end
missingServing = ~isfinite(meas.serving_cell);
if any(missingServing) && istable(servingState) && ~isempty(servingState)
    for i = reshape(find(missingServing), 1, [])
        fallback = localNearestServingStateRow(servingState, meas.ue_id(i), meas.slot(i));
        if ~isempty(fallback)
            meas.serving_cell(i) = fallback.serving_cell;
            meas.serving_state_source(i) = fallback.serving_state_source;
            meas.coverage_join_quality(i) = fallback.coverage_join_quality;
        end
    end
end
meas.serving_state_source(strlength(strtrim(string(meas.serving_state_source))) == 0) = "serving_state_not_emitted";
meas.coverage_join_quality(~isfinite(meas.serving_cell)) = "coverage_join_missing";
meas.direction = repmat("DL", height(meas), 1);
meas.is_serving_candidate = isfinite(meas.serving_cell) & isfinite(meas.cell_id) & (meas.serving_cell == meas.cell_id);
meas.candidate_relation = repmat("candidate_measurement", height(meas), 1);
meas.candidate_relation(meas.is_serving_candidate) = "serving_candidate";
meas.candidate_relation(~meas.is_serving_candidate & meas.candidate_rank > 1) = "neighbor_candidate";
meas.candidate_relation(~meas.is_serving_candidate & meas.candidate_rank == 1) = "top_rank_nonserving_candidate";
meas.measurement_source = repmat("reports/csv/live_cell_measurement_trace.csv", height(meas), 1);
T = sortrows(meas, {'slot', 'ue_id', 'candidate_rank', 'cell_id'});
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCandidateCellRuntimeTable", ...
    "reports/csv/live_cell_measurement_trace.csv|reports/csv/live_mobility_state.csv|reports/csv/live_selection_state.csv|reports/csv/live_measurement_filter_state.csv|reports/csv/live_coverage_layer.csv", ...
    "implemented", "derived_runtime_candidate_cell_measurements", true, true);
end

function T = localBuildServingStateTable(src)
parts = {};
parts{end+1} = localServingStateFromTable(sixgr.util.structGet(src, "LiveMobilityState", table()), ...
    "reports/csv/live_mobility_state.csv", 1);
parts{end+1} = localServingStateFromTable(sixgr.util.structGet(src, "LiveSelectionState", table()), ...
    "reports/csv/live_selection_state.csv", 2);
parts{end+1} = localServingStateFromTable(sixgr.util.structGet(src, "LiveMeasurementFilterState", table()), ...
    "reports/csv/live_measurement_filter_state.csv", 3);
parts{end+1} = localServingStateFromTable(sixgr.util.structGet(src, "CoverageLayer", table()), ...
    "reports/csv/live_coverage_layer.csv", 4);
parts = parts(~cellfun(@isempty, parts));
if isempty(parts)
    T = table();
    return;
end
T = vertcat(parts{:});
T = sortrows(T, {'serving_state_priority','slot','ue_id'});
[~, keepIdx] = unique(T(:, {'ue_id','slot'}), 'rows', 'stable');
T = T(sort(keepIdx), :);
end

function T = localServingStateFromTable(srcTable, sourcePath, priority)
if ~(istable(srcTable) && ~isempty(srcTable))
    T = table();
    return;
end
ueId = localColumnAsDouble(srcTable, "UEID");
if ~any(isfinite(ueId))
    ueId = localColumnAsDouble(srcTable, "ue_id");
end
slot = localColumnAsDouble(srcTable, "Slot");
if ~any(isfinite(slot))
    slot = localColumnAsDouble(srcTable, "slot");
end
servingCell = localColumnAsDouble(srcTable, "ServingCell");
if ~any(isfinite(servingCell))
    servingCell = localColumnAsDouble(srcTable, "serving_cell");
end
valid = isfinite(ueId) & isfinite(slot) & isfinite(servingCell);
if ~any(valid)
    T = table();
    return;
end
T = table(ueId(valid), slot(valid), servingCell(valid), ...
    repmat(string(sourcePath), sum(valid), 1), ...
    repmat(double(priority), sum(valid), 1), ...
    repmat(true, sum(valid), 1), ...
    repmat("exact_runtime_serving_state_join", sum(valid), 1), ...
    'VariableNames', {'ue_id','slot','serving_cell','serving_state_source','serving_state_priority','same_slot_match','coverage_join_quality'});
T = unique(T, 'rows', 'stable');
end

function row = localNearestServingStateRow(servingState, ueId, slot)
row = table();
if ~(istable(servingState) && ~isempty(servingState) && isfinite(ueId) && isfinite(slot))
    return;
end
mask = isfinite(servingState.ue_id) & isfinite(servingState.slot) & isfinite(servingState.serving_cell) & servingState.ue_id == ueId;
if ~any(mask)
    return;
end
subset = servingState(mask, :);
delta = abs(subset.slot - slot);
[~, order] = sortrows([delta, subset.serving_state_priority], [1 2]); %#ok<ASGLU>
subset = subset(order, :);
row = subset(1, :);
row.same_slot_match = false;
row.coverage_join_quality = "nearest_runtime_serving_state_slot";
end

function T = localBuildNeighborDegreeHistogramData(candidateT, meta)
if ~(istable(candidateT) && ~isempty(candidateT))
    T = table();
    return;
end
servingCell = localColumnAsDouble(candidateT, "serving_cell");
candidateCell = localColumnAsDouble(candidateT, "cell_id");
candidateRank = localColumnAsDouble(candidateT, "candidate_rank");
valid = isfinite(servingCell) & isfinite(candidateCell) & isfinite(candidateRank);
if ~any(valid)
    T = table();
    return;
end
servingCells = unique(servingCell(valid), "stable");
degrees = nan(numel(servingCells), 1);
observationCounts = zeros(numel(servingCells), 1);
for i = 1:numel(servingCells)
    cellId = servingCells(i);
    mask = valid & servingCell == cellId;
    neighborMask = mask & candidateCell ~= cellId & candidateRank > 1;
    degrees(i) = double(numel(unique(candidateCell(neighborMask))));
    observationCounts(i) = double(sum(neighborMask));
end
degreeValues = unique(degrees(isfinite(degrees)), "stable");
if isempty(degreeValues)
    degreeValues = 0;
end
rows = repmat(struct("neighbor_degree", NaN, "cell_count", NaN, "candidate_observation_count", NaN, ...
    "serving_cell_list", ""), numel(degreeValues), 1);
for i = 1:numel(degreeValues)
    degree = degreeValues(i);
    mask = isfinite(degrees) & degrees == degree;
    rows(i).neighbor_degree = degree;
    rows(i).cell_count = double(sum(mask));
    rows(i).candidate_observation_count = double(sum(observationCounts(mask)));
    rows(i).serving_cell_list = strjoin(string(servingCells(mask)).', "|");
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildNeighborDegreeHistogramData", ...
    "reports/csv/live_cell_measurement_trace.csv|reports/csv/live_coverage_layer.csv", ...
    "implemented", "derived_runtime_neighbor_degree_histogram", true, true);
end

function T = localBuildGNBCellTable(src, meta, cfg)
if ~(istable(src.SystemSectors) && ~isempty(src.SystemSectors))
    T = table();
    return;
end
sectorIDs = localColumnAsDouble(src.SystemSectors, "trp_id");
rows = repmat(struct("site_id", NaN, "sector_id", NaN, "cell_id", NaN, "pci", NaN, ...
    "arfcn_or_center_freq", NaN, "bandwidth_hz", NaN, "scs_hz", NaN, "tx_power_dBm", NaN, ...
    "tx_power_eirp_dBm", NaN, "antenna_profile", "", "num_txru", NaN, "num_rxru", NaN, ...
    "active_ues_avg", NaN, "active_ues_peak", NaN, "dl_load_avg", NaN, "ul_load_avg", NaN, ...
    "avg_rsrp_dBm", NaN, "avg_sinr_dB", NaN, "edge_ue_count", NaN, "handover_in_count", NaN, ...
    "handover_out_count", NaN, "beam_failure_count", NaN, "scheduler_type", "", ...
    "energy_state_primary", "", "control_overhead_fraction", NaN, "status_source", ""), height(src.SystemSectors), 1);
for i = 1:height(src.SystemSectors)
    cellId = sectorIDs(i);
    loadMask = localColumnMatches(src.SystemCellLoad, "CellID", cellId);
    intrMask = localColumnMatches(src.SystemInterference, "ServingCell", cellId);
    beamMask = localColumnMatches(src.SystemBeam, "ServingCell", cellId);
    hoInMask = localColumnMatches(src.SystemHandover, "TargetCell", cellId);
    hoOutMask = localColumnMatches(src.SystemHandover, "SourceCell", cellId);

    rows(i).site_id = localTableValue(src.SystemSectors(i, :), "site_id", NaN);
    rows(i).sector_id = localTableValue(src.SystemSectors(i, :), "sector_id", NaN);
    rows(i).cell_id = cellId;
    rows(i).pci = cellId;
    rows(i).arfcn_or_center_freq = meta.carrier_frequency_hz;
    rows(i).bandwidth_hz = meta.bandwidth_hz;
    rows(i).scs_hz = meta.scs_hz;
    rows(i).tx_power_dBm = localTableValue(src.SystemSectors(i, :), "max_tx_power_dbm", sixgr.util.structGet(cfg, "energy.txPower_dBm", NaN));
    rows(i).tx_power_eirp_dBm = NaN;
    rows(i).antenna_profile = string(localTableValue(src.SystemSectors(i, :), "array_geometry_id", ""));
    rows(i).num_txru = double(localScenarioStructGet(cfg, {"system.bsArray.numTxRU", "baseStation.numTxRU"}, NaN));
    rows(i).num_rxru = double(localScenarioStructGet(cfg, {"system.bsArray.numRxRU", "baseStation.numRxRU"}, NaN));
    rows(i).active_ues_avg = localMeanFromMask(src.SystemCellLoad, loadMask, "ActiveUE_DL", "ActiveUE_UL");
    if ~isfinite(rows(i).active_ues_avg)
        rows(i).active_ues_avg = localGrantUniqueUEStat(src.DLGrants, src.ULGrants, cellId, "mean");
    end
    rows(i).active_ues_peak = localMaxFromMask(src.SystemCellLoad, loadMask, "ActiveUE_DL", "ActiveUE_UL");
    if ~isfinite(rows(i).active_ues_peak)
        rows(i).active_ues_peak = localGrantUniqueUEStat(src.DLGrants, src.ULGrants, cellId, "max");
    end
    rows(i).dl_load_avg = localPRBLoadFraction(src.DLGrants, cellId, meta);
    rows(i).ul_load_avg = localPRBLoadFraction(src.ULGrants, cellId, meta);
    rows(i).avg_rsrp_dBm = localMeanFromMask(src.SystemInterference, intrMask, "RSRP_dBm");
    if ~isfinite(rows(i).avg_rsrp_dBm)
        rows(i).avg_rsrp_dBm = localCoverageMeanByCell(src.CoverageLayer, cellId, "ServingRSRP_dBm", "RSRP_dBm");
    end
    rows(i).avg_sinr_dB = localMeanFromMask(src.SystemInterference, intrMask, "SINR_DL_dB", "SINR_UL_dB");
    if ~isfinite(rows(i).avg_sinr_dB)
        rows(i).avg_sinr_dB = localCoverageMeanByCell(src.CoverageLayer, cellId, "PostEqWidebandSINR_dB", "PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "LargeScaleWidebandSINR_dB", "LargeScaleSINR_dB");
    end
    rows(i).edge_ue_count = localEdgeUECount(src.SystemInterference, cellId);
    if ~isfinite(rows(i).edge_ue_count)
        rows(i).edge_ue_count = localCoverageEdgeUECount(src.CoverageLayer, cellId);
    end
    rows(i).handover_in_count = localMaskedCount(src.SystemHandover, hoInMask);
    rows(i).handover_out_count = localMaskedCount(src.SystemHandover, hoOutMask);
    rows(i).beam_failure_count = localMaskedEventCount(src.SystemBeam, beamMask, "EventType", "beam_failure");
    if ~isfinite(rows(i).beam_failure_count)
        rows(i).beam_failure_count = localBeamMismatchCount(src.BeamPrecoder, cellId);
    end
    rows(i).scheduler_type = string(localScenarioStructGet(cfg, {"system.scheduler.type"}, ""));
    rows(i).energy_state_primary = "";
    rows(i).control_overhead_fraction = NaN;
    rows(i).status_source = string(localGNBCellStatusSource(src));
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildGNBCellTable", ...
    localGNBCellStatusSource(src), "implemented", "runtime_aggregated", true, true);
end

function T = localBuildChannelSummaryTable(src, meta, cfg)
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    ueVals = unique(localColumnAsDouble(src.SystemInterference, "UE"));
    channelSourceRef = "system/csv/system_interference_detail.csv";
else
    ueVals = unique([ ...
        localColumnAsDouble(src.CoverageLayer, "UEID"); ...
        localColumnAsDouble(src.DLTrials, "UEID"); ...
        localColumnAsDouble(src.ULTrials, "UEID"); ...
        localColumnAsDouble(src.UserPerformance, "UEIndex")], "stable");
    channelSourceRef = "reports/csv/live_coverage_layer.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
end
ueVals = ueVals(isfinite(ueVals));
if isempty(ueVals)
    T = table();
    return;
end
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "los_flag", NaN, "o2i_flag", NaN, ...
    "pathloss_dB", NaN, "coupling_loss_dB", NaN, "shadow_fading_dB", NaN, ...
    "delay_spread_ns", NaN, "asa_deg", NaN, "asd_deg", NaN, "zsa_deg", NaN, "zsd_deg", NaN, ...
    "doppler_hz", NaN, "k_factor_dB", NaN, "channel_rank_est", NaN, ...
    "spatial_consistency_state", "", "update_period_ms", NaN, "channel_tensor_ref", "", ...
    "source_backend_object", ""), numel(ueVals), 1);
txPower = localTxPowerByCell(src.SystemSectors);
for i = 1:numel(ueVals)
    ue = ueVals(i);
    mask = localColumnMatches(src.SystemInterference, "UE", ue);
    servingCell = localFirstFinite(localSelectColumn(src.SystemInterference, mask, "ServingCell"));
    if ~isfinite(servingCell)
        servingCell = localCoverageCellForUE(src.CoverageLayer, ue);
    end
    if ~isfinite(servingCell)
        servingCell = localTrialCellForUE(src.DLTrials, src.ULTrials, ue);
    end
    servedTx = localMapLookup(txPower, servingCell, NaN);
    speedKmh = localLookupUEValue(src.SystemUE, ue, "Speed_kmh", NaN);
    if ~isfinite(speedKmh)
        speedKmh = localLookupUEValue(src.SystemUEPositions, ue, "speed_kmh", NaN);
    end
    rows(i).ue_id = ue;
    rows(i).cell_id = servingCell;
    rows(i).los_flag = NaN;
    rows(i).o2i_flag = localLookupUEValue(src.SystemUE, ue, "Indoor", NaN);
    if ~isfinite(rows(i).o2i_flag)
        rows(i).o2i_flag = localLookupUEValue(src.SystemUEPositions, ue, "indoor", NaN);
    end
    rows(i).pathloss_dB = localMeanFromMask(src.SystemInterference, mask, "Pathloss_dB");
    if ~isfinite(rows(i).pathloss_dB)
        rows(i).pathloss_dB = localCoverageMetricForUE(src.CoverageLayer, ue, "Pathloss_dB");
    end
    if ~isfinite(rows(i).pathloss_dB)
        rows(i).pathloss_dB = localTrialMetricForUE(src.DLTrials, src.ULTrials, ue, "AppliedPathloss_dB", "AppliedBasePathloss_dB");
    end
    rows(i).coupling_loss_dB = localMeanFromMask(src.SystemInterference, mask, "RxPower_dBm");
    if isfinite(servedTx) && isfinite(rows(i).coupling_loss_dB)
        rows(i).coupling_loss_dB = servedTx - rows(i).coupling_loss_dB;
    else
        servingRSRP = localCoverageMetricForUE(src.CoverageLayer, ue, "ServingRSRP_dBm", "RSRP_dBm");
        if ~(isfinite(servedTx) && isfinite(servingRSRP))
            servingRSRP = localTrialMetricForUE(src.DLTrials, src.ULTrials, ue, "ServingRSRP_dBm");
        end
        if isfinite(servedTx) && isfinite(servingRSRP)
            rows(i).coupling_loss_dB = servedTx - servingRSRP;
        else
            rows(i).coupling_loss_dB = rows(i).pathloss_dB;
        end
    end
    rows(i).shadow_fading_dB = NaN;
    rows(i).delay_spread_ns = NaN;
    rows(i).asa_deg = NaN;
    rows(i).asd_deg = NaN;
    rows(i).zsa_deg = NaN;
    rows(i).zsd_deg = NaN;
    rows(i).doppler_hz = localTrialMetricForUE(src.DLTrials, src.ULTrials, ue, "EstimatedDopplerHz", "DopplerHz", "InjectedDoppler_Hz");
    if ~isfinite(rows(i).doppler_hz)
        rows(i).doppler_hz = localSpeedToDopplerHz(speedKmh, meta.carrier_frequency_hz);
    end
    rows(i).k_factor_dB = NaN;
    rows(i).channel_rank_est = localMeanGrantLayers(src.DLGrants, src.ULGrants, ue, servingCell);
    rows(i).spatial_consistency_state = string(localTernary(logical(localScenarioStructGet(cfg, {"channel.spatialConsistencyEnable"}, false)), "enabled", "disabled"));
    rows(i).update_period_ms = double(localScenarioStructGet(cfg, {"channel.updatePeriod_ms", "channel.largeScaleUpdatePeriod_ms"}, NaN));
    rows(i).channel_tensor_ref = "";
    rows(i).source_backend_object = channelSourceRef;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildChannelSummaryTable", ...
    channelSourceRef, "implemented", "runtime_aggregated", true, true);
end

function T = localBuildNoiseInterferenceTable(src, meta, cfg)
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "serving_cell_id", NaN, "desired_signal_power_dBm", NaN, ...
        "intra_cell_interference_dBm", NaN, "inter_cell_interference_dBm", NaN, "external_interference_dBm", NaN, ...
        "noise_power_dBm", NaN, "thermal_noise_dBm", NaN, "receiver_noise_figure_dB", NaN, ...
        "total_interference_plus_noise_dBm", NaN, "pre_eq_sinr_dB", NaN, "post_eq_sinr_dB", NaN, ...
        "dominant_interferer_cell_id", NaN, "dominant_interferer_share_percent", NaN, ...
        "interference_limited_flag", false, "source_block", "", "direction", ""), 0, 1);
    for i = 1:height(src.SystemInterference)
        base = src.SystemInterference(i, :);
        dlNoise = localTableValue(base, "NoiseDL_dBm", localTableValue(base, "Noise_dBm", NaN));
        dlInterf = localTableValue(base, "InterferencePowerDL_dBm", NaN);
        dlDesired = localTableValue(base, "DesiredPowerDL_dBm", NaN);
        if isfinite(dlDesired)
            rows(end+1, 1) = localNoiseRow(base, "DL", dlDesired, dlInterf, dlNoise, ... %#ok<AGROW>
                double(localScenarioStructGet(cfg, {"receiver.noiseFigure_dB", "baseStation.noiseFigure_dB"}, NaN)));
        end
        ulNoise = localTableValue(base, "NoiseUL_dBm", NaN);
        ulInterf = localTableValue(base, "InterferencePowerUL_dBm", NaN);
        ulDesired = localTableValue(base, "DesiredPowerUL_dBm", NaN);
        if isfinite(ulDesired)
            rows(end+1, 1) = localNoiseRow(base, "UL", ulDesired, ulInterf, ulNoise, ... %#ok<AGROW>
                double(localScenarioStructGet(cfg, {"receiver.noiseFigure_dB", "userEquipment.noiseFigure_dB"}, NaN)));
        end
    end
else
    rows = localBuildNoiseRowsFromTrials(src, meta, cfg);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildNoiseInterferenceTable", ...
    localNoiseInterferenceSourceRef(src), "implemented", "runtime_timeseries", false, true);
end

function T = localBuildLinkBudgetTable(src, meta, cfg)
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    txPowerByCell = localTxPowerByCell(src.SystemSectors);
    rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "direction", "", ...
        "tx_power_dBm", NaN, "tx_antenna_gain_dBi", NaN, "rx_antenna_gain_dBi", NaN, "pathloss_dB", NaN, ...
        "shadowing_dB", NaN, "penetration_loss_dB", NaN, "implementation_loss_dB", NaN, ...
        "rx_power_dBm", NaN, "interference_power_dBm", NaN, "noise_power_dBm", NaN, ...
        "snr_dB", NaN, "sinr_dB", NaN, "margin_dB", NaN, "power_control_command", NaN, ...
        "phr_dB", NaN, "source_chain", ""), 0, 1);
    for i = 1:height(src.SystemInterference)
        base = src.SystemInterference(i, :);
        cellId = localTableValue(base, "ServingCell", NaN);
        txPower = localMapLookup(txPowerByCell, cellId, NaN);
        implLoss = double(localScenarioStructGet(cfg, {"baseStation.implementationLoss_dB", "system.bsImplementationLoss_dB"}, NaN));
        dlDesired = localTableValue(base, "DesiredPowerDL_dBm", NaN);
        if isfinite(dlDesired)
            snr = dlDesired - localTableValue(base, "NoiseDL_dBm", localTableValue(base, "Noise_dBm", NaN));
            rows(end+1, 1) = localLinkBudgetRow(base, "DL", txPower, implLoss, dlDesired, ... %#ok<AGROW>
                localTableValue(base, "InterferencePowerDL_dBm", NaN), ...
                localTableValue(base, "NoiseDL_dBm", localTableValue(base, "Noise_dBm", NaN)), ...
                snr, localTableValue(base, "SINR_DL_dB", NaN));
        end
        ulDesired = localTableValue(base, "DesiredPowerUL_dBm", NaN);
        if isfinite(ulDesired)
            snr = ulDesired - localTableValue(base, "NoiseUL_dBm", NaN);
            rows(end+1, 1) = localLinkBudgetRow(base, "UL", ... %#ok<AGROW>
                double(localScenarioStructGet(cfg, {"userEquipment.txPower_dBm", "energy.txPower_dBm"}, NaN)), ...
                implLoss, ulDesired, localTableValue(base, "InterferencePowerUL_dBm", NaN), ...
                localTableValue(base, "NoiseUL_dBm", NaN), snr, localTableValue(base, "SINR_UL_dB", NaN));
        end
    end
else
    rows = localBuildLinkBudgetRowsFromTrials(src, meta, cfg);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLinkBudgetTable", ...
    localLinkBudgetSourceRef(src), "implemented", "runtime_timeseries", true, true);
end

function T = localBuildPRBAllocationTable(src, meta)
T = [ ...
    localBuildPRBAllocationTableFromGrants(src.DLGrants, "DL", meta, "packet_flow/csv/live_dl_scheduler_grants.csv"); ...
    localBuildPRBAllocationTableFromGrants(src.ULGrants, "UL", meta, "packet_flow/csv/live_ul_scheduler_grants.csv")];
if isempty(T)
    T = table();
    return;
end
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildPRBAllocationTable", ...
    "packet_flow/csv/live_dl_scheduler_grants.csv", "implemented", "runtime_grant_rows", false, true);
end

function T = localBuildPRBAllocationTableFromGrants(grants, direction, meta, sourceRef)
if ~(istable(grants) && ~isempty(grants))
    T = table();
    return;
end
n = height(grants);
tti = localColumnAsDouble(grants, "TTI");
slotsPerFrame = double(meta.slots_per_frame);
frameVal = localFirstAvailableColumnAsDouble(grants, ["Frame", "SFN"]);
slotVal = localFirstAvailableColumnAsDouble(grants, ["Slot"]);
validTTI = (~isfinite(frameVal) | ~isfinite(slotVal)) & isfinite(tti) & isfinite(slotsPerFrame) & slotsPerFrame > 0;
frameVal(validTTI) = floor((tti(validTTI) - 1) ./ slotsPerFrame) + 1;
slotVal(validTTI) = mod(tti(validTTI) - 1, slotsPerFrame) + 1;

directionCol = repmat(string(direction), n, 1);
isRetx = localColumnAsLogical(grants, "IsRetransmission");
occupancyType = repmat("scheduled_allocation", n, 1);
occupancyType(isRetx) = "retransmission";

T = table();
timestampSec = localFirstAvailableColumnAsDouble(grants, ["Time_s"]);
timestampMs = localFirstAvailableColumnAsDouble(grants, ["TimestampSim_ms", "Time_ms"]);
if all(~isfinite(timestampMs)) && any(isfinite(timestampSec))
    timestampMs = 1e3 * timestampSec;
end
T.timestamp_sim_ms = timestampMs;
T.frame = frameVal;
T.slot = slotVal;
T.symbol_start = localColumnAsDouble(grants, "SymbolStart");
T.symbol_len = localColumnAsDouble(grants, "NumSymbols");
T.cell_id = localFirstAvailableColumnAsDouble(grants, ["CellID", "ServingCell", "BaseStationID"]);
T.ue_id = localFirstAvailableColumnAsDouble(grants, ["UE", "UEID", "UEIndex", "RNTI"]);
T.direction = directionCol;
T.bwp_id = localFirstAvailableColumnAsDouble(grants, ["BWPId", "BWPID"]);
T.rb_start = localFirstAvailableColumnAsDouble(grants, ["PRBStart", "PUCCHPRBStart"]);
T.rb_len = localFirstAvailableColumnAsDouble(grants, ["PRBCount", "AllocatedPRBCount", "PUCCHPRBCount"]);
T.num_prbs = localFirstAvailableColumnAsDouble(grants, ["AllocatedPRBCount", "PRBCount", "PUCCHPRBCount"]);
T.beam_id = NaN(n, 1);
T.rank = localFirstAvailableColumnAsDouble(grants, ["NumLayers", "Layers", "Rank"]);
T.layers = localFirstAvailableColumnAsDouble(grants, ["Layers", "NumLayers", "Rank"]);
T.harq_id = localColumnAsDouble(grants, "HarqID");
T.mcs = localColumnAsDouble(grants, "MCSIndex");
T.tbs_bits = localColumnAsDouble(grants, "TBSBits");
T.allocation_reason = localColumnAsText(grants, "GrantReason");
T.occupancy_type = occupancyType;
T.source_artifact_ref = repmat(string(sourceRef), n, 1);
end

function T = localBuildPRBAllocationHeatmapTable(prbTable, meta)
if ~(istable(prbTable) && ~isempty(prbTable))
    T = table();
    return;
end
cellVals = double(prbTable.cell_id(:));
dirVals = string(prbTable.direction(:));
[~, ~, dirIdx] = unique(dirVals);
dirIdx = double(dirIdx(:));
validRows = isfinite(cellVals) & strlength(dirVals) > 0 & isfinite(dirIdx);
groups = unique([cellVals(validRows), dirIdx(validRows)], "rows");
if isempty(groups)
    T = table();
    return;
end
bestScore = -Inf;
bestCell = NaN;
bestDir = "";
for i = 1:size(groups, 1)
    mask = cellVals == groups(i, 1) & dirIdx == groups(i, 2);
    scoreVals = double(prbTable.num_prbs(mask)) .* max(double(prbTable.symbol_len(mask)), 1);
    score = sum(scoreVals(isfinite(scoreVals)));
    if score > bestScore
        bestScore = score;
        bestCell = groups(i, 1);
        bestDir = dirVals(find(mask, 1, "first"));
    end
end
mask = (cellVals == bestCell) & (dirVals == bestDir);
selected = prbTable(mask, :);
rbStart = double(selected.rb_start(:));
rbLen = double(selected.rb_len(:));
frameVals = double(selected.frame(:));
slotVals = double(selected.slot(:));
symLen = double(selected.symbol_len(:));
valid = isfinite(rbStart) & isfinite(rbLen) & rbLen > 0 & isfinite(frameVals) & isfinite(slotVals);
if ~any(valid)
    T = table();
    return;
end
rbStart = rbStart(valid);
rbLen = max(1, floor(rbLen(valid)));
frameVals = frameVals(valid);
slotVals = slotVals(valid);
symLen = symLen(valid);
rowIdx = repelem((1:numel(rbLen)).', rbLen);
if isempty(rowIdx)
    T = table();
    return;
end
rowIdx = rowIdx(:);
offsetCells = arrayfun(@(n) (0:(n-1)).', rbLen, 'UniformOutput', false);
offsets = vertcat(offsetCells{:});
offsets = offsets(:);
nRows = numel(rowIdx);
T = table( ...
    repmat(bestCell, nRows, 1), ...
    localStringColumn(bestDir, nRows), ...
    reshape(frameVals(rowIdx), [], 1), ...
    reshape(slotVals(rowIdx), [], 1), ...
    reshape(rbStart(rowIdx) + offsets, [], 1), ...
    reshape(symLen(rowIdx), [], 1), ...
    reshape(symLen(rowIdx) / max(meta.symbols_per_slot, 1), [], 1), ...
    true(nRows, 1), ...
    localStringColumn("packet_flow/csv/live_prb_allocation.csv", nRows), ...
    'VariableNames', {'cell_id','direction','frame','slot','rb_index','occupancy_count','occupancy_fraction','selected_heatmap_flag','source_artifact_ref'});
key = string(T.cell_id) + "|" + string(T.direction) + "|" + string(T.frame) + "|" + ...
    string(T.slot) + "|" + string(T.rb_index) + "|" + string(T.selected_heatmap_flag) + "|" + ...
    string(T.source_artifact_ref);
[~, firstIdx, keyIdx] = unique(key);
base = T(firstIdx, :);
base.occupancy_count = accumarray(keyIdx, double(T.occupancy_count), [], @sum);
base.occupancy_fraction = accumarray(keyIdx, double(T.occupancy_fraction), [], @sum);
T = base;
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildPRBAllocationHeatmapTable", ...
    "packet_flow/csv/live_prb_allocation.csv", "implemented", "derived_from_prb_rows", true, true);
end

function T = localBuildSchedulerDecisionTable(src, meta)
rows = localEmptySchedulerDecisionRows(0);
rows = [rows; localBuildSchedulerDecisionRowsFromGrants(src.DLGrants, "DL", meta, "packet_flow/csv/live_dl_scheduler_grants.csv")]; %#ok<AGROW>
rows = [rows; localBuildSchedulerDecisionRowsFromGrants(src.ULGrants, "UL", meta, "packet_flow/csv/live_ul_scheduler_grants.csv")]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildSchedulerDecisionTable", ...
    "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv", ...
    "implemented", "selected_grant_runtime_truth", false, true);
end

function rows = localBuildSchedulerDecisionRowsFromGrants(grants, direction, meta, sourceRef)
if ~(istable(grants) && ~isempty(grants))
    rows = localEmptySchedulerDecisionRows(0);
    return;
end
rows = localEmptySchedulerDecisionRows(height(grants));
for i = 1:height(grants)
    row = grants(i, :);
    tti = localNumericTableValue(row, "TTI", NaN);
    [frameVal, slotVal] = localGrantFrameSlotRow(row, tti, meta.slots_per_frame);
    rows(i).timestamp_sim_ms = localGrantTimestampMsRow(row);
    rows(i).frame = frameVal;
    rows(i).slot = slotVal;
    rows(i).scheduler_cycle_id = tti;
    rows(i).decision_id = string(direction) + "_grant_" + string(i);
    rows(i).decision_scope = "selected_grant_only";
    rows(i).candidate_decision_rows_available = false;
    rows(i).decision_truth_status = "selected_grant_runtime_truth";
    rows(i).direction = string(direction);
    rows(i).cell_id = localFirstNumericTableValue(row, ["CellID", "ServingCell", "BaseStationID"], NaN);
    rows(i).ue_id = localFirstNumericTableValue(row, ["UE", "UEID", "UEIndex", "RNTI"], NaN);
    rows(i).grant_reason = localTextTableValue(row, "GrantReason", "");
    rows(i).selected_flag = true;
    rows(i).rejected_flag = false;
    rows(i).prb_start = localNumericTableValue(row, "PRBStart", NaN);
    rows(i).prb_count = localNumericTableValue(row, "PRBCount", NaN);
    rows(i).symbol_start = localNumericTableValue(row, "SymbolStart", NaN);
    rows(i).num_symbols = localNumericTableValue(row, "NumSymbols", NaN);
    rows(i).mcs_index = localNumericTableValue(row, "MCSIndex", NaN);
    rows(i).wideband_cqi = localNormalizeReportedCQIValue(localNumericTableValue(row, "CQIUsed", NaN));
    rows(i).target_code_rate = localNumericTableValue(row, "TargetCodeRate", NaN);
    rows(i).tbs_bits = localNumericTableValue(row, "TBSBits", NaN);
    rows(i).harq_id = localNumericTableValue(row, "HarqID", NaN);
    rows(i).rv = localNumericTableValue(row, "RV", NaN);
    rows(i).ndi = localNumericTableValue(row, "NDI", NaN);
    rows(i).is_retransmission = localLogicalTableValue(row, "IsRetransmission", false);
    rows(i).source_artifact_ref = string(sourceRef);
end
end

function rows = localEmptySchedulerDecisionRows(n)
n = max(0, round(double(n)));
rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, ...
    "scheduler_cycle_id", NaN, "decision_id", "", "decision_scope", "", ...
    "candidate_decision_rows_available", false, "decision_truth_status", "", ...
    "direction", "", "cell_id", NaN, "ue_id", NaN, "grant_reason", "", ...
    "selected_flag", false, "rejected_flag", false, "prb_start", NaN, ...
    "prb_count", NaN, "symbol_start", NaN, "num_symbols", NaN, ...
    "mcs_index", NaN, "wideband_cqi", NaN, "target_code_rate", NaN, ...
    "tbs_bits", NaN, "harq_id", NaN, "rv", NaN, "ndi", NaN, ...
    "is_retransmission", false, "source_artifact_ref", ""), n, 1);
end

function T = localBuildDirectionalGridHeatmapTable(prbTable, direction, meta)
if ~(istable(prbTable) && ~isempty(prbTable))
    T = table();
    return;
end
direction = string(direction);
mask = string(prbTable.direction) == direction;
if ~any(mask)
    T = table();
    return;
end
selected = prbTable(mask, :);
rbStart = double(selected.rb_start(:));
rbLen = double(selected.rb_len(:));
frameVals = double(selected.frame(:));
slotVals = double(selected.slot(:));
cellIds = double(selected.cell_id(:));
symLen = double(selected.symbol_len(:));
valid = isfinite(rbStart) & isfinite(rbLen) & rbLen > 0 & isfinite(frameVals) & isfinite(slotVals) & isfinite(cellIds);
if ~any(valid)
    T = table();
    return;
end
rbStart = rbStart(valid);
rbLen = max(1, floor(rbLen(valid)));
frameVals = frameVals(valid);
slotVals = slotVals(valid);
cellIds = cellIds(valid);
symLen = symLen(valid);
rowIdx = repelem((1:numel(rbLen)).', rbLen);
if isempty(rowIdx)
    T = table();
    return;
end
rowIdx = rowIdx(:);
offsetCells = arrayfun(@(n) (0:(n-1)).', rbLen, 'UniformOutput', false);
offsets = vertcat(offsetCells{:});
offsets = offsets(:);
nRows = numel(rowIdx);
T = table( ...
    reshape(cellIds(rowIdx), [], 1), ...
    localStringColumn(direction, nRows), ...
    reshape(frameVals(rowIdx), [], 1), ...
    reshape(slotVals(rowIdx), [], 1), ...
    reshape(rbStart(rowIdx) + offsets, [], 1), ...
    reshape(symLen(rowIdx), [], 1), ...
    reshape(symLen(rowIdx) / max(meta.symbols_per_slot, 1), [], 1), ...
    localStringColumn("packet_flow/csv/live_prb_allocation.csv", nRows), ...
    'VariableNames', {'cell_id','direction','frame','slot','rb_index','occupancy_count','occupancy_fraction','source_artifact_ref'});
key = string(T.cell_id) + "|" + string(T.direction) + "|" + string(T.frame) + "|" + string(T.slot) + "|" + string(T.rb_index);
[~, firstIdx, keyIdx] = unique(key);
base = T(firstIdx, :);
base.occupancy_count = accumarray(keyIdx, double(T.occupancy_count), [], @sum);
base.occupancy_fraction = accumarray(keyIdx, double(T.occupancy_fraction), [], @sum);
T = base;
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildDirectionalGridHeatmapTable", ...
    "packet_flow/csv/live_prb_allocation.csv", "implemented", "derived_from_prb_rows", true, true);
end

function T = localBuildREAllocationSnapshotTable(src, prbTable, meta, cfg)
parts = {};
part = localBuildRERowsFromPRBAllocation(prbTable);
if istable(part) && ~isempty(part)
    parts{end+1} = part; %#ok<AGROW>
end
part = localBuildSSBComponentRows(src.PBCHTrials, meta, cfg);
if istable(part) && ~isempty(part)
    parts{end+1} = part; %#ok<AGROW>
end
part = localBuildPDCCHCORESETRows(src.PDCCHTrials, cfg);
if istable(part) && ~isempty(part)
    parts{end+1} = part; %#ok<AGROW>
end
trialSpecs = { ...
    src.PDCCHTrials, "DL", "PDCCH", ["PRBStart","RBStart","CORESETRBStart"], ["AllocatedPRBCount","PRBCount","NumRB","CORESETRBCount"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/pdcch_trials.csv"; ...
    src.PUCCHTrials, "UL", "PUCCH", ["PUCCHPRBStart","PRBStart","RBStart"], ["PUCCHPRBCount","AllocatedPRBCount","PRBCount","NumRB"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/pucch_trials.csv"; ...
    src.SRSTrials, "UL", "SRS", ["RBOffset","PRBStart","RBStart"], ["NumRB","AllocatedPRBCount","PRBCount"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/srs_trials.csv"; ...
    src.CSIRSTrials, "DL", "CSI-RS", ["RBOffset","PRBStart","RBStart"], ["NumRB","AllocatedPRBCount","PRBCount"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/csi_rs_trials.csv"; ...
    src.TRSTrials, "DL", "TRS", ["RBOffset","PRBStart","RBStart"], ["NumRB","AllocatedPRBCount","PRBCount"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/trs_trials.csv"; ...
    src.PBCHTrials, "DL", "PBCH", ["PRBStart","RBStart"], ["AllocatedPRBCount","PRBCount","NumRB"], ["SymbolStart"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/pbch_trials.csv"; ...
    src.PRACHTrials, "UL", "PRACH", ["PRBStart","RBStart","FrequencyIndex"], ["AllocatedPRBCount","PRBCount","NumRB"], ["SymbolStart","TimeIndex"], ["NumSymbols","SymbolLength"], ["SymbolLocations"], "control/csv/prach_trials.csv"};
for iSpec = 1:size(trialSpecs, 1)
    part = localBuildRERowsFromTrialAllocation(trialSpecs{iSpec, 1}, trialSpecs{iSpec, 2}, trialSpecs{iSpec, 3}, ...
        trialSpecs{iSpec, 4}, trialSpecs{iSpec, 5}, trialSpecs{iSpec, 6}, trialSpecs{iSpec, 7}, trialSpecs{iSpec, 8}, trialSpecs{iSpec, 9});
    if istable(part) && ~isempty(part)
        parts{end+1} = part; %#ok<AGROW>
    end
end
if isempty(parts)
    T = table();
    return;
end
T = vertcat(parts{:});
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildREAllocationSnapshotTable", ...
    "packet_flow/csv/live_prb_allocation.csv|control/csv/*_trials.csv", "implemented", ...
    "resource_grid_rows_from_runtime_allocation_evidence", true, true);
end

function T = localBuildRERowsFromPRBAllocation(prbTable)
if ~(istable(prbTable) && ~isempty(prbTable))
    T = table();
    return;
end
parts = {};
frameVals = localFirstAvailableColumnAsDouble(prbTable, ["frame", "Frame", "SFN"]);
slotVals = localFirstAvailableColumnAsDouble(prbTable, ["slot", "Slot"]);
symStartVals = localFirstAvailableColumnAsDouble(prbTable, ["symbol_start", "SymbolStart"]);
symLenVals = localFirstAvailableColumnAsDouble(prbTable, ["symbol_len", "NumSymbols", "SymbolLength"]);
rbStartVals = localFirstAvailableColumnAsDouble(prbTable, ["rb_start", "PRBStart", "RBStart"]);
rbLenVals = localFirstAvailableColumnAsDouble(prbTable, ["rb_len", "PRBCount", "AllocatedPRBCount"]);
cellVals = localFirstAvailableColumnAsDouble(prbTable, ["cell_id", "CellID", "ServingCell", "BaseStationID"]);
ueVals = localFirstAvailableColumnAsDouble(prbTable, ["ue_id", "UE", "UEID", "UEIndex", "RNTI"]);
rankVals = localFirstAvailableColumnAsDouble(prbTable, ["rank", "layers", "NumLayers", "Layers", "Rank"]);
dirVals = localColumnAsText(prbTable, "direction");
roleVals = localColumnAsText(prbTable, "occupancy_type");
sourceVals = localColumnAsText(prbTable, "source_artifact_ref");
roleVals(strlength(strtrim(roleVals)) == 0) = "scheduled_allocation";
sourceVals(strlength(strtrim(sourceVals)) == 0) = "packet_flow/csv/live_prb_allocation.csv";
for i = 1:height(prbTable)
    if ~(isfinite(frameVals(i)) && isfinite(slotVals(i)) && isfinite(symStartVals(i)) && isfinite(symLenVals(i)) && ...
            isfinite(rbStartVals(i)) && isfinite(rbLenVals(i)) && symLenVals(i) > 0 && rbLenVals(i) > 0)
        continue;
    end
    symbols = round(symStartVals(i)) + (0:(max(1, round(symLenVals(i))) - 1));
    rbs = round(rbStartVals(i)) + (0:(max(1, round(rbLenVals(i))) - 1));
    channel = "PDSCH";
    if upper(dirVals(i)) == "UL"
        channel = "PUSCH";
    end
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symbols, rbs, dirVals(i), channel, channel, ...
        cellVals(i), ueVals(i), ueVals(i), "grant_allocation_" + string(i), NaN, NaN, rankVals(i), roleVals(i), ...
        "scheduler_grant_prb_symbol_allocation", "OK", sourceVals(i)); %#ok<AGROW>
end
T = localVertcatTables(parts);
end

function T = localBuildRERowsFromTrialAllocation(trials, direction, channel, rbStartFields, rbLenFields, symStartFields, symLenFields, symbolListFields, sourceRef)
if ~(istable(trials) && ~isempty(trials))
    T = table();
    return;
end
parts = {};
rbStartVals = localFirstAvailableColumnAsDouble(trials, rbStartFields);
rbLenVals = localFirstAvailableColumnAsDouble(trials, rbLenFields);
frameVals = localFirstAvailableColumnAsDouble(trials, ["Frame", "SFN"]);
slotVals = localFirstAvailableColumnAsDouble(trials, ["Slot"]);
cellVals = localFirstAvailableColumnAsDouble(trials, ["CellID", "ServingCell", "BaseStationID"]);
ueVals = localFirstAvailableColumnAsDouble(trials, ["UEIndex", "UEID", "UE", "RNTI"]);
rntiVals = localFirstAvailableColumnAsDouble(trials, ["RNTI", "UEID", "UEIndex"]);
portVals = localFirstAvailableColumnAsDouble(trials, ["NumPorts", "NumTxPorts", "NumRxAntennas"]);
layerVals = localFirstAvailableColumnAsDouble(trials, ["Layers", "Rank", "RankIndicator"]);
for i = 1:height(trials)
    if ~(isfinite(frameVals(i)) && isfinite(slotVals(i)) && isfinite(rbStartVals(i)) && isfinite(rbLenVals(i)) && rbLenVals(i) > 0)
        continue;
    end
    symbols = localResolveTrialSymbols(trials(i, :), symStartFields, symLenFields, symbolListFields);
    if isempty(symbols)
        continue;
    end
    rbs = round(rbStartVals(i)) + (0:(max(1, round(rbLenVals(i))) - 1));
    valueStatus = "OK";
    if any(symbols < 0) || any(rbs < 0)
        valueStatus = "REVIEW_REQUIRED";
    end
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symbols, rbs, string(direction), string(channel), string(channel), ...
        cellVals(i), ueVals(i), rntiVals(i), string(channel) + "_trial_" + string(i), NaN, portVals(i), layerVals(i), ...
        "runtime_trial_resource_allocation", "trial_resource_coordinates", valueStatus, string(sourceRef)); %#ok<AGROW>
end
T = localVertcatTables(parts);
end

function T = localBuildSSBComponentRows(pbchTrials, meta, cfg)
if ~(istable(pbchTrials) && ~isempty(pbchTrials))
    T = table();
    return;
end
nRB = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", ...
    sixgr.util.structGet(cfg, "frequency.n_size_grid", NaN)));
if ~(isscalar(nRB) && isfinite(nRB) && nRB >= 20)
    T = table();
    return;
end
parts = {};
frameVals = localFirstAvailableColumnAsDouble(pbchTrials, ["Frame", "SFN"]);
slotVals = localFirstAvailableColumnAsDouble(pbchTrials, ["Slot"]);
cellVals = localFirstAvailableColumnAsDouble(pbchTrials, ["CellID", "ServingCell", "BaseStationID"]);
beamVals = localFirstAvailableColumnAsDouble(pbchTrials, ["SSBIndex", "SSBBeamIndex", "BeamIndex"]);
rbStartVals = localFirstAvailableColumnAsDouble(pbchTrials, ["SSBPRBStart", "PRBStart", "RBStart"]);
symStartVals = localFirstAvailableColumnAsDouble(pbchTrials, ["SSBSymbolStart", "SymbolStart"]);
defaultRBStart = max(0, floor((round(nRB) - 20) / 2));
for i = 1:height(pbchTrials)
    if ~(isfinite(frameVals(i)) && isfinite(slotVals(i)))
        continue;
    end
    rbStart = rbStartVals(i);
    if ~isfinite(rbStart)
        rbStart = defaultRBStart;
    end
    symStart = symStartVals(i);
    if ~isfinite(symStart)
        symStart = 0;
    end
    rbs = round(rbStart) + (0:19);
    allocId = "ssb_occasion_" + string(i);
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symStart + (0:3), rbs, "DL", "SSB", "SSB", ...
        cellVals(i), NaN, NaN, allocId, beamVals(i), 4, NaN, "ssb_block_240_subcarrier_4_symbol_region", ...
        "pbch_runtime_occasion_plus_ts38211_ssb_mapping", "OK", "air_interface/csv/pbch_trials.csv"); %#ok<AGROW>
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symStart, rbs, "DL", "PSS", "SSB", ...
        cellVals(i), NaN, NaN, allocId + "_pss", beamVals(i), 1, NaN, "pss_symbol_region", ...
        "pbch_runtime_occasion_plus_ts38211_ssb_mapping", "OK", "air_interface/csv/pbch_trials.csv"); %#ok<AGROW>
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symStart + 2, rbs, "DL", "SSS", "SSB", ...
        cellVals(i), NaN, NaN, allocId + "_sss", beamVals(i), 1, NaN, "sss_symbol_region", ...
        "pbch_runtime_occasion_plus_ts38211_ssb_mapping", "OK", "air_interface/csv/pbch_trials.csv"); %#ok<AGROW>
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symStart + [1 2 3], rbs, "DL", "PBCH", "SSB", ...
        cellVals(i), NaN, NaN, allocId + "_pbch", beamVals(i), 1, NaN, "pbch_symbol_region", ...
        "pbch_runtime_occasion_plus_ts38211_ssb_mapping", "OK", "air_interface/csv/pbch_trials.csv"); %#ok<AGROW>
end
T = localVertcatTables(parts);
end

function T = localBuildPDCCHCORESETRows(pdcchTrials, cfg)
if ~(istable(pdcchTrials) && ~isempty(pdcchTrials))
    T = table();
    return;
end
try
    ctrlCfg = sixgr.ctrl.ControlChannelConfig(cfg);
    coreset = ctrlCfg.CORESET;
catch
    T = table();
    return;
end
rbList = double(sixgr.util.structGet(coreset, "RBList", []));
if isempty(rbList)
    rbStart = double(sixgr.util.structGet(coreset, "RBStart", NaN));
    numRB = double(sixgr.util.structGet(coreset, "NumRB", NaN));
    if isfinite(rbStart) && isfinite(numRB) && numRB > 0
        rbList = rbStart + (0:(round(numRB)-1));
    end
end
if isempty(rbList)
    T = table();
    return;
end
symStart = double(sixgr.util.structGet(coreset, "StartSymbol", 0));
symLen = double(sixgr.util.structGet(coreset, "DurationSymbols", 1));
symbols = round(symStart) + (0:(max(1, round(symLen)) - 1));
frameVals = localFirstAvailableColumnAsDouble(pdcchTrials, ["Frame", "SFN"]);
slotVals = localFirstAvailableColumnAsDouble(pdcchTrials, ["Slot"]);
cellVals = localFirstAvailableColumnAsDouble(pdcchTrials, ["CellID", "ServingCell", "BaseStationID"]);
ueVals = localFirstAvailableColumnAsDouble(pdcchTrials, ["UEIndex", "UEID", "UE", "RNTI"]);
rntiVals = localFirstAvailableColumnAsDouble(pdcchTrials, ["RNTI", "UEID", "UEIndex"]);
parts = {};
for i = 1:height(pdcchTrials)
    if ~(isfinite(frameVals(i)) && isfinite(slotVals(i)))
        continue;
    end
    parts{end+1} = localBuildRETablePart(frameVals(i), slotVals(i), symbols, rbList, "DL", "PDCCH", "CORESET", ...
        cellVals(i), ueVals(i), rntiVals(i), "pdcch_coreset_runtime_" + string(i), NaN, ...
        numel(double(sixgr.util.structGet(coreset, "DMRSPortSet", 0))), NaN, ...
        "coreset_search_space_occupancy", "pdcch_runtime_trial_plus_coreset_config", "OK", ...
        "air_interface/csv/pdcch_trials.csv"); %#ok<AGROW>
end
T = localVertcatTables(parts);
end

function symbols = localResolveTrialSymbols(row, symStartFields, symLenFields, symbolListFields)
symbols = [];
for f = 1:numel(symbolListFields)
    if ~ismember(symbolListFields(f), string(row.Properties.VariableNames))
        continue;
    end
    raw = localTableValue(row, symbolListFields(f), "");
    symbols = localParseIntegerList(raw);
    if ~isempty(symbols)
        symbols = unique(round(symbols(:).'), "stable");
        return;
    end
end
symStart = localFirstNumericTableValue(row, symStartFields, NaN);
symLen = localFirstNumericTableValue(row, symLenFields, NaN);
if isfinite(symStart) && isfinite(symLen) && symLen > 0
    symbols = round(symStart) + (0:(max(1, round(symLen)) - 1));
end
end

function values = localParseIntegerList(raw)
values = [];
if isnumeric(raw)
    values = double(raw(:).');
    values = values(isfinite(values));
    return;
end
tokens = regexp(char(string(raw)), "-?\d+", "match");
if isempty(tokens)
    return;
end
values = str2double(tokens);
values = values(isfinite(values));
end

function T = localBuildRETablePart(frameVal, slotVal, symbols, rbs, direction, channel, signalFamily, cellId, ueId, rnti, allocationId, portIndex, portCount, layerCount, occupancyRole, evidenceKind, valueStatus, sourceRef)
[rbGrid, symGrid] = ndgrid(double(rbs(:)), double(symbols(:)));
n = numel(rbGrid);
if n == 0
    T = table();
    return;
end
T = table( ...
    repmat(double(frameVal), n, 1), ...
    repmat(double(slotVal), n, 1), ...
    reshape(double(symGrid), [], 1), ...
    reshape(double(rbGrid), [], 1), ...
    reshape(double(rbGrid) * 12, [], 1), ...
    repmat(12, n, 1), ...
    repmat(double(portIndex), n, 1), ...
    repmat(double(portCount), n, 1), ...
    repmat(double(layerCount), n, 1), ...
    localStringColumn(direction, n), ...
    localStringColumn(channel, n), ...
    localStringColumn(signalFamily, n), ...
    repmat(double(cellId), n, 1), ...
    repmat(double(ueId), n, 1), ...
    repmat(double(rnti), n, 1), ...
    localStringColumn(allocationId, n), ...
    localStringColumn(occupancyRole, n), ...
    localStringColumn(evidenceKind, n), ...
    localStringColumn(valueStatus, n), ...
    localStringColumn(sourceRef, n), ...
    'VariableNames', {'frame','slot','symbol_index','rb_index','subcarrier_start','subcarrier_count', ...
    'port_index','port_count','layer_count','direction','channel','signal_family','cell_id','ue_id','rnti', ...
    'allocation_id','occupancy_role','evidence_kind','value_status','source_artifact_ref'});
T.sfn = T.frame;
T.symbol = T.symbol_index;
T.bs_id = T.cell_id;
T.channel_name = T.channel;
T.signal_name = T.signal_family + ":" + T.channel;
T.PRBStart = T.rb_index;
T.PRBCount = ones(height(T), 1);
T.SymbolStart = T.symbol_index;
T.NumSymbols = ones(height(T), 1);
T.occupancy_value = ones(height(T), 1);
T.count = ones(height(T), 1);
T.REStart = T.subcarrier_start;
T.RECount = T.subcarrier_count;
T.re_range = string(T.subcarrier_start) + "-" + string(T.subcarrier_start + T.subcarrier_count - 1);
T.value_role = T.occupancy_role;
T.value_source = T.evidence_kind;
end

function T = localVertcatTables(parts)
if isempty(parts)
    T = table();
    return;
end
keep = false(size(parts));
for i = 1:numel(parts)
    keep(i) = istable(parts{i}) && ~isempty(parts{i});
end
parts = parts(keep);
if isempty(parts)
    T = table();
else
    T = vertcat(parts{:});
end
end

function T = localBuildLatencyTable(src, meta)
rows = localEmptyLatencyRows(0);
rows = [rows; localBuildLatencyRowsFromTrials(src.DLTrials, "DL", "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildLatencyRowsFromTrials(src.ULTrials, "UL", "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
finiteLatency = arrayfun(@(r) isfinite(r.latency_ms), rows);
if ~any(finiteLatency)
    T = table();
    return;
end
T = struct2table(rows(finiteLatency));
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLatencyTable", ...
    "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv", ...
    "implemented", "runtime_latency_components", true, true);
end

function rows = localBuildLatencyRowsFromTrials(trials, direction, sourceRef)
latencyVars = ["ComputeLatency_ms", "DecodeLatency_ms", "ProcedureDelay_ms", "AirInterfaceTTI_ms", "AirInterfaceObservation_ms"];
if ~(istable(trials) && ~isempty(trials)) || ~any(ismember(latencyVars, string(trials.Properties.VariableNames)))
    rows = localEmptyLatencyRows(0);
    return;
end
rows = localEmptyLatencyRows(height(trials));
for i = 1:height(trials)
    row = trials(i, :);
    components = [localNumericTableValue(row, "ComputeLatency_ms", NaN), ...
        localNumericTableValue(row, "DecodeLatency_ms", NaN), ...
        localNumericTableValue(row, "ProcedureDelay_ms", NaN), ...
        localNumericTableValue(row, "AirInterfaceTTI_ms", NaN), ...
        localNumericTableValue(row, "AirInterfaceObservation_ms", NaN)];
    [latencyMs, latencyDefinition] = localNonOverlappingTrialLatency(components);
    rows(i).timestamp_sim_ms = 1e3 * localNumericTableValue(row, "Time_s", NaN);
    rows(i).frame = localNumericTableValue(row, "Frame", NaN);
    rows(i).slot = localNumericTableValue(row, "Slot", NaN);
    rows(i).direction = string(direction);
    rows(i).ue_id = localFirstNumericTableValue(row, ["UEID", "UEIndex", "UE", "RNTI"], NaN);
    rows(i).cell_id = localFirstNumericTableValue(row, ["CellID", "ServingCell"], NaN);
    rows(i).compute_latency_ms = components(1);
    rows(i).decode_latency_ms = components(2);
    rows(i).procedure_delay_ms = components(3);
    rows(i).air_interface_tti_ms = components(4);
    rows(i).air_interface_observation_ms = components(5);
    rows(i).latency_ms = latencyMs;
    rows(i).latency_value_role = "measured";
    rows(i).latency_value_status = localTernary(isfinite(rows(i).latency_ms), "OK", "NOT_AVAILABLE");
    rows(i).latency_value_definition = latencyDefinition;
    rows(i).source_artifact_ref = string(sourceRef);
end
end

function [latencyMs, definition] = localNonOverlappingTrialLatency(components)
computeMs = components(1);
decodeMs = components(2);
procedureMs = components(3);
ttiMs = components(4);
observationMs = components(5);

processingMs = localMaxFinite([computeMs, decodeMs]);
radioMs = localFirstFinitePositive([observationMs, ttiMs]);
procedureExtraMs = NaN;
if isfinite(procedureMs) && procedureMs > 0
    procedureExtraMs = procedureMs;
end

parts = [processingMs, procedureExtraMs, radioMs];
parts = parts(isfinite(parts));
if isempty(parts)
    latencyMs = NaN;
else
    latencyMs = sum(parts);
end
definition = "non-overlapping runtime latency: max(compute,decode aliases) + positive procedure extra + one radio observation/TTI component";
end

function value = localMaxFinite(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function value = localFirstFinitePositive(values)
idx = find(isfinite(values) & values > 0, 1, "first");
if isempty(idx)
    value = NaN;
else
    value = values(idx);
end
end

function rows = localEmptyLatencyRows(n)
n = max(0, round(double(n)));
rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, ...
    "direction", "", "ue_id", NaN, "cell_id", NaN, "compute_latency_ms", NaN, ...
    "decode_latency_ms", NaN, "procedure_delay_ms", NaN, "air_interface_tti_ms", NaN, ...
    "air_interface_observation_ms", NaN, "latency_ms", NaN, "latency_value_role", "", ...
    "latency_value_status", "", "latency_value_definition", "", "source_artifact_ref", ""), n, 1);
end

function T = localBuildLatencyCDFTable(latencyTable, meta)
if ~(istable(latencyTable) && ~isempty(latencyTable) && localHasVar(latencyTable, "latency_ms"))
    T = table();
    return;
end
vals = sort(double(latencyTable.latency_ms(isfinite(double(latencyTable.latency_ms)))));
if isempty(vals)
    T = table();
    return;
end
n = numel(vals);
T = table(vals(:), (1:n)' ./ n, repmat("reports/csv/table_latency.csv", n, 1), ...
    'VariableNames', {'latency_ms','cdf_probability','source_artifact_ref'});
T.latency_value_definition = repmat("empirical CDF from real latency rows", n, 1);
T.truth_status = repmat("real_lls_evidence", n, 1);
T.curve_construction = repmat("empirical_cdf", n, 1);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLatencyCDFTable", ...
    "reports/csv/table_latency.csv", "implemented", "derived_latency_cdf", true, true);
end

function T = localBuildLatencyRootCauseTable(latencyTable, meta)
if ~(istable(latencyTable) && ~isempty(latencyTable) && localHasVar(latencyTable, "latency_ms"))
    T = table();
    return;
end
lat = double(latencyTable.latency_ms);
lat = lat(isfinite(lat));
if isempty(lat)
    T = table();
    return;
end
threshold = localPercentile(lat, 95);
mask = isfinite(double(latencyTable.latency_ms)) & double(latencyTable.latency_ms) >= threshold;
if ~any(mask)
    T = table();
    return;
end
subset = latencyTable(mask, :);
rows = repmat(struct("direction", "", "ue_id", NaN, "cell_id", NaN, "latency_ms", NaN, ...
    "latency_threshold_ms", NaN, "dominant_component", "", "root_cause_reason", "", ...
    "source_artifact_ref", ""), height(subset), 1);
componentFields = ["compute_latency_ms", "decode_latency_ms", "procedure_delay_ms", "air_interface_tti_ms", "air_interface_observation_ms"];
for i = 1:height(subset)
    row = subset(i, :);
    comps = arrayfun(@(name) localNumericTableValue(row, char(name), NaN), componentFields);
    [~, idx] = max(localReplaceNaN(comps, -Inf));
    rows(i).direction = string(localTableValue(row, "direction", ""));
    rows(i).ue_id = localNumericTableValue(row, "ue_id", NaN);
    rows(i).cell_id = localNumericTableValue(row, "cell_id", NaN);
    rows(i).latency_ms = localNumericTableValue(row, "latency_ms", NaN);
    rows(i).latency_threshold_ms = threshold;
    rows(i).dominant_component = componentFields(idx);
    rows(i).root_cause_reason = "highest_observed_latency_window";
    rows(i).source_artifact_ref = "reports/csv/table_latency.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLatencyRootCauseTable", ...
    "reports/csv/table_latency.csv", "implemented", "derived_latency_root_cause", true, true);
end

function T = localBuildTransportBlockTable(trials, grants, direction, meta)
if istable(trials) && ~isempty(trials)
    n = height(trials);
    T = table();
    T.timestamp_sim_ms = localColumnAsDouble(trials, "TimestampSim_ms");
    T.frame = localColumnAsDouble(trials, "Frame");
    T.slot = localColumnAsDouble(trials, "Slot");
    T.cell_id = localColumnAsDouble(trials, "CellID");
    T.ue_id = localFirstAvailableColumnAsDouble(trials, ["UEID", "UEIndex", "UE", "RNTI"]);
    T.harq_id = localColumnAsDouble(trials, "HarqID");
    T.ndi = localColumnAsDouble(trials, "NDI");
    T.rv = localColumnAsDouble(trials, "RV");
    T.tb_id = zeros(n, 1);
    T.mcs = localCoalesceColumnAsDouble(trials, "MCSIndex", "MCS");
    T.mod_order = arrayfun(@localModOrderFromText, localColumnAsText(trials, "Modulation"));
    T.code_rate = localColumnAsDouble(trials, "TargetCodeRate");
    T.tbs_bits = localCoalesceColumnAsDouble(trials, "TBSBits", "BitsCompared");
    T.allocated_prbs = localColumnAsDouble(trials, "AllocatedPRBCount");
    T.allocated_symbols = localColumnAsDouble(trials, "AllocatedSymbolCount");
    T.rank = localColumnAsDouble(trials, "Rank");
    T.layers = localCoalesceColumnAsDouble(trials, "NumLayers", "Layers");
    T.beam_id = localColumnAsDouble(trials, "AppliedBeamIndex");
    T.crc_pass = localColumnAsLogical(trials, "CRCPass");
    T.tb_bler_flag = ~T.crc_pass;
    T.decoder_iterations = localColumnAsDouble(trials, "DecoderIterations");
    T.soft_combining_round = localColumnAsDouble(trials, "HARQRound");
    comparedBits = localColumnAsDouble(trials, "BitsCompared");
    T.goodput_bits = comparedBits .* double(T.crc_pass);
else
    grantRows = localBuildAllocationRows(grants, direction, meta, "");
    if isempty(grantRows)
        T = table();
        return;
    end
    G = struct2table(grantRows);
    T = table();
    T.timestamp_sim_ms = G.timestamp_sim_ms;
    T.frame = G.frame;
    T.slot = G.slot;
    T.cell_id = G.cell_id;
    T.ue_id = G.ue_id;
    T.harq_id = G.harq_id;
    T.ndi = NaN(height(G), 1);
    T.rv = NaN(height(G), 1);
    T.tb_id = zeros(height(G), 1);
    T.mcs = G.mcs;
    T.mod_order = NaN(height(G), 1);
    T.code_rate = NaN(height(G), 1);
    T.tbs_bits = G.tbs_bits;
    T.allocated_prbs = G.num_prbs;
    T.allocated_symbols = G.symbol_len;
    T.rank = G.rank;
    T.layers = G.layers;
    T.beam_id = G.beam_id;
    T.crc_pass = false(height(G), 1);
    T.tb_bler_flag = false(height(G), 1);
    T.decoder_iterations = NaN(height(G), 1);
    T.soft_combining_round = NaN(height(G), 1);
    T.goodput_bits = NaN(height(G), 1);
end
T.direction = repmat(string(direction), height(T), 1);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildTransportBlockTable", ...
    localTernary(direction == "DL", "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"), ...
    "implemented", localTernary(istable(trials) && ~isempty(trials), "runtime_trials", "derived_from_grants"), true, true);
end

function T = localBuildHARQProcessTable(src, meta)
if istable(src.SystemHARQ) && ~isempty(src.SystemHARQ)
    keyCols = [localColumnAsDouble(src.SystemHARQ, "UE"), localColumnAsDouble(src.SystemHARQ, "CellID"), ...
        localStringGroupIndex(localColumnAsText(src.SystemHARQ, "Direction")), localColumnAsDouble(src.SystemHARQ, "HarqID")];
    groups = unique(keyCols, "rows");
    rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "direction", "", "harq_id", NaN, ...
        "ndi", NaN, "rv", NaN, "tx_count", NaN, "first_tx_time", NaN, "last_tx_time", NaN, ...
        "ack_nack_state", "", "final_state", "", "combined_rounds", NaN, "combining_gain_dB", NaN, ...
        "buffer_occupancy_bits", NaN, "timeout_flag", false, "discard_reason", ""), size(groups, 1), 1);
    for i = 1:size(groups, 1)
        mask = keyCols(:, 1) == groups(i, 1) & keyCols(:, 2) == groups(i, 2) & keyCols(:, 3) == groups(i, 3) & keyCols(:, 4) == groups(i, 4);
        subset = src.SystemHARQ(mask, :);
        rows(i).ue_id = groups(i, 1);
        rows(i).cell_id = groups(i, 2);
        rows(i).direction = string(subset.Direction(1));
        rows(i).harq_id = groups(i, 4);
        rows(i).ndi = localTableValue(subset(1, :), "NDI", NaN);
        rows(i).rv = localTableValue(subset(end, :), "RV", NaN);
        rows(i).tx_count = height(subset);
        rows(i).first_tx_time = 1e3 * localTableValue(subset(1, :), "Time_s", NaN);
        rows(i).last_tx_time = 1e3 * localTableValue(subset(end, :), "Time_s", NaN);
        rows(i).ack_nack_state = string(localTableValue(subset(end, :), "Outcome", ""));
        rows(i).final_state = rows(i).ack_nack_state;
        rows(i).combined_rounds = height(subset);
        rows(i).combining_gain_dB = NaN;
        rows(i).buffer_occupancy_bits = NaN;
        rows(i).timeout_flag = false;
        rows(i).discard_reason = "";
    end
else
    rows = localBuildHARQRowsFromTimeline(src, meta);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildHARQProcessTable", ...
    localHARQSourceRef(src), "implemented", "runtime_aggregated", true, true);
end

function T = localBuildCQIPMIRITable(src, meta)
rows = localEmptyCQIPMIRows(0);
rows = [rows; localBuildCQIRowsFromGrants(src.DLGrants, "DL")]; %#ok<AGROW>
rows = [rows; localBuildCQIRowsFromGrants(src.ULGrants, "UL")]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCQIPMIRITable", ...
    "packet_flow/csv/live_dl_scheduler_grants.csv", "implemented", "derived_from_scheduler_grants", true, true);
end

function T = localBuildMCSTBSEvolutionTable(src, meta)
T = [ ...
    localBuildMCSTBSEvolutionFromGrants(src.DLGrants, "DL"); ...
    localBuildMCSTBSEvolutionFromGrants(src.ULGrants, "UL")];
if isempty(T)
    T = table();
    return;
end
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildMCSTBSEvolutionTable", ...
    "packet_flow/csv/live_dl_scheduler_grants.csv", "implemented", "derived_from_scheduler_grants", true, true);
end

function T = localBuildMCSTBSEvolutionFromGrants(grants, direction)
if ~(istable(grants) && ~isempty(grants))
    T = table();
    return;
end
n = height(grants);
isRetx = localColumnAsLogical(grants, "IsRetransmission");
harqState = repmat("new_data", n, 1);
harqState(isRetx) = "retransmission";
T = table();
timestampSec = localFirstAvailableColumnAsDouble(grants, ["Time_s"]);
timestampMs = localFirstAvailableColumnAsDouble(grants, ["TimestampSim_ms", "Time_ms"]);
if all(~isfinite(timestampMs)) && any(isfinite(timestampSec))
    timestampMs = 1e3 * timestampSec;
end
T.timestamp_sim_ms = timestampMs;
T.frame = localFirstAvailableColumnAsDouble(grants, ["Frame", "SFN"]);
T.slot = localFirstAvailableColumnAsDouble(grants, ["Slot"]);
T.ue_id = localFirstAvailableColumnAsDouble(grants, ["UE", "UEID", "UEIndex", "RNTI"]);
T.cell_id = localFirstAvailableColumnAsDouble(grants, ["CellID", "ServingCell", "BaseStationID"]);
T.direction = repmat(string(direction), n, 1);
T.cqi_input = localColumnAsReportedCQI(grants, "CQIUsed");
[cqiSampleCount, cqiDistinctCount, cqiSaturationFraction, cqiDynamicRangeStatus] = ...
    localCQIDynamicRangeDiagnostics(T.cqi_input);
T.cqi_window_sample_count = repmat(cqiSampleCount, n, 1);
T.cqi_distinct_count = repmat(cqiDistinctCount, n, 1);
T.cqi_saturation_fraction = repmat(cqiSaturationFraction, n, 1);
T.cqi_dynamic_range_status = repmat(cqiDynamicRangeStatus, n, 1);
T.ri_input = NaN(n, 1);
T.pmi_input = NaN(n, 1);
T.mcs_selected = localColumnAsDouble(grants, "MCSIndex");
T.cqi_derived_mcs = localCQIDerivedMCSFromGrantTable(grants);
T.raw_cqi_derived_mcs = localFirstAvailableColumnAsDouble(grants, ["RawCQIDerivedMCS"]);
T.link_adaptation_mcs = localFirstAvailableColumnAsDouble(grants, ["LinkAdaptationMCSIndex", "AdaptedMCSIndex"]);
T.cqi_based_mcs = localFirstAvailableColumnAsDouble(grants, ["CQIBasedMCS"]);
T.smoothed_cqi = localFirstAvailableColumnAsDouble(grants, ["SmoothedCQI"]);
T.instantaneous_cqi_mcs = localFirstAvailableColumnAsDouble(grants, ["InstantaneousCQIMCS"]);
T.delta_mcs = localFirstAvailableColumnAsDouble(grants, ["DeltaMCS"]);
T.olla_delta_db = localFirstAvailableColumnAsDouble(grants, ["OLLADeltaDb", "OLLADeltaMCS"]);
T.olla_adjusted_mcs_before_cqi_ceiling = localFirstAvailableColumnAsDouble(grants, ["OLLAAdjustedMCSBeforeCQICeiling"]);
T.olla_base_required_sinr_dB = localFirstAvailableColumnAsDouble(grants, ["OLLABaseRequiredSINR_dB"]);
T.olla_target_required_sinr_dB = localFirstAvailableColumnAsDouble(grants, ["OLLATargetRequiredSINR_dB"]);
T.olla_threshold_source = localColumnAsText(grants, "OLLAThresholdSource");
T.static_delta_mcs = localFirstAvailableColumnAsDouble(grants, ["StaticDeltaMCS"]);
T.mcs_table = localColumnAsText(grants, "MCSTable");
T.cqi_table = localColumnAsText(grants, "CQITable");
T.mcs_selection_source = localColumnAsText(grants, "MCSSelectionSource");
T.mcs_value_status = localColumnAsText(grants, "MCSValueStatus");
T.mcs_index_authority = localColumnAsText(grants, "MCSIndexAuthority");
T.grant_operating_point_source = localColumnAsText(grants, "GrantOperatingPointSource");
T.link_adaptation_decision_reason = localColumnAsText(grants, "LinkAdaptationDecisionReason");
T.mod_order = NaN(n, 1);
T.code_rate = localColumnAsDouble(grants, "TargetCodeRate");
T.tbs_bits = localColumnAsDouble(grants, "TBSBits");
T.harq_id = localFirstAvailableColumnAsDouble(grants, ["HarqID", "HARQProcessId"]);
T.ndi = localFirstAvailableColumnAsDouble(grants, ["NDI", "NewDataIndicator"]);
T.rv = localFirstAvailableColumnAsDouble(grants, ["RV", "RedundancyVersion"]);
T.olla_offset = T.olla_delta_db;
T.harq_state = harqState;
T.scheduler_reason = localColumnAsText(grants, "GrantReason");
T.effective_sinr_dB = localColumnAsDouble(grants, "SINR_dB");
end

function values = localCQIDerivedMCSFromGrantTable(grants)
n = height(grants);
values = NaN(n, 1);
if ~(istable(grants) && n > 0)
    return;
end
for i = 1:n
    row = grants(i, :);
    cqiUsed = localNormalizeReportedCQIValue(localTableValue(row, "CQIUsed", NaN));
    if ~isfinite(cqiUsed)
        continue;
    end
    mcsTable = string(localTableValue(row, "MCSTable", localTableValue(row, "MCS_Table", "qam64_table1")));
    cqiTable = string(localTableValue(row, "CQITable", localTableValue(row, "CQI_Table", "table1")));
    decision = sixgr.link.resolveMCSFromCQI(cqiUsed, char(mcsTable), char(cqiTable));
    if isstruct(decision) && isfield(decision, "Valid") && logical(decision.Valid)
        values(i) = double(decision.MCSIndex);
    end
end
end

function [sampleCount, distinctCount, saturationFraction, status] = localCQIDynamicRangeDiagnostics(cqiValues)
cqi = double(cqiValues(:));
valid = isfinite(cqi) & cqi >= 1 & cqi <= 15;
sampleCount = double(nnz(valid));
if sampleCount == 0
    distinctCount = 0;
    saturationFraction = NaN;
    status = "unavailable_no_valid_cqi";
    return;
end
validCQI = round(cqi(valid));
distinctCount = double(numel(unique(validCQI)));
saturationFraction = double(nnz(validCQI >= 15)) / sampleCount;
if distinctCount <= 1 && saturationFraction >= 0.95 && sampleCount >= 4
    status = "saturated_at_cqi15_window";
elseif distinctCount <= 1 && sampleCount >= 4
    status = "low_dynamic_range_window";
else
    status = "dynamic_range_observed";
end
end

function T = localBuildPowerEnergyTable(src, meta, cfg)
if ~(istable(src.EnergyTimeline) && ~isempty(src.EnergyTimeline))
    T = table();
    return;
end
rows = repmat(struct("timestamp_sim_ms", NaN, "entity_type", "", "entity_id", NaN, "direction", "", ...
    "tx_power_dBm", NaN, "rx_power_est_dBm", NaN, "active_bw_fraction", NaN, "active_rank", NaN, ...
    "active_txru_count", NaN, "scheduled_ues", NaN, "control_monitoring_load", NaN, "state", "", ...
    "power_est_mW_or_W", NaN, "power_estimate_value", NaN, "power_estimate_unit", "", ...
    "power_value_role", "", "power_value_source", "", "power_value_status", "", ...
    "energy_increment_mJ", NaN, "cumulative_energy_J", NaN, ...
    "useful_bits", NaN, "energy_per_bit_nJ", NaN, "energy_value_role", "", ...
    "energy_value_source", "", "energy_value_status", "", "transition_from_state", "", ...
    "transition_to_state", "", "transition_time_us", NaN, "transition_energy_uJ", NaN), height(src.EnergyTimeline), 1);
keyState = containers.Map("KeyType", "char", "ValueType", "any");
keyEnergy = containers.Map("KeyType", "char", "ValueType", "double");
for i = 1:height(src.EnergyTimeline)
    row = src.EnergyTimeline(i, :);
    entityType = string(localTableValue(row, "EntityType", localTableValue(row, "Entity", "")));
    entityType = localNormalizeEntityType(entityType);
    entityId = localResolveEnergyEntityID(row);
    direction = string(localTableValue(row, "Direction", ""));
    key = sprintf("%s|%.0f|%s", char(entityType), double(entityId), char(direction));
    powerW = double(localTableValue(row, "Power_W", NaN));
    energyJ = double(localTableValue(row, "Energy_J", NaN));
    prevState = "";
    if isKey(keyState, key)
        prevState = string(keyState(key));
    end
    keyState(key) = string(localTableValue(row, "State", localTableValue(row, "Domain", "")));
    cumulative = energyJ;
    if isKey(keyEnergy, key)
        cumulative = keyEnergy(key) + energyJ;
    end
    keyEnergy(key) = cumulative;

    rows(i).timestamp_sim_ms = localEnergyTimestampMs(row, meta);
    rows(i).entity_type = entityType;
    rows(i).entity_id = entityId;
    rows(i).direction = direction;
    rows(i).tx_power_dBm = double(localTableValue(row, "TxPower_dBm", NaN));
    rows(i).rx_power_est_dBm = double(localTableValue(row, "RxPowerEst_dBm", NaN));
    rows(i).active_bw_fraction = localEnergyActiveBWFraction(row, meta, cfg);
    rows(i).active_rank = double(localTableValue(row, "ActiveRank", NaN));
    rows(i).active_txru_count = double(localTableValue(row, "ActiveTxRUCount", localTableValue(row, "RFChainCount", NaN)));
    rows(i).scheduled_ues = localScheduledUEsForEnergy(src.SystemCellLoad, row, direction);
    rows(i).control_monitoring_load = double(localTableValue(row, "ControlMonitoringLoad", NaN));
    rows(i).state = string(localTableValue(row, "State", localTableValue(row, "Domain", "")));
    rows(i).power_est_mW_or_W = powerW;
    rows(i).power_estimate_value = powerW;
    rows(i).power_estimate_unit = "W";
    rows(i).power_value_role = "derived";
    rows(i).power_value_source = "rf/csv/energy_timeline_trace.csv:Power_W";
    rows(i).power_value_status = string(localTernary(isfinite(powerW), "OK", "NOT_AVAILABLE"));
    rows(i).energy_increment_mJ = energyJ * 1e3;
    rows(i).cumulative_energy_J = cumulative;
    rows(i).useful_bits = double(localTableValue(row, "SuccessfulBits", NaN));
    rows(i).energy_per_bit_nJ = localEnergyPerBit(energyJ, rows(i).useful_bits);
    rows(i).energy_value_role = "derived";
    rows(i).energy_value_source = "rf/csv/energy_timeline_trace.csv:Energy_J,SuccessfulBits";
    rows(i).energy_value_status = string(localTernary(isfinite(rows(i).energy_per_bit_nJ), "OK", "NOT_AVAILABLE"));
    rows(i).transition_from_state = localTernary(prevState ~= "" && prevState ~= rows(i).state, prevState, "");
    rows(i).transition_to_state = localTernary(prevState ~= "" && prevState ~= rows(i).state, rows(i).state, "");
    rows(i).transition_time_us = localTernary(prevState ~= "" && prevState ~= rows(i).state, double(localTableValue(row, "Duration_s", NaN)) * 1e6, NaN);
    rows(i).transition_energy_uJ = localTernary(prevState ~= "" && prevState ~= rows(i).state, energyJ * 1e6, NaN);
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildPowerEnergyTable", ...
    "rf/csv/energy_timeline_trace.csv", "implemented", "runtime_energy_trace", true, true);
end

function T = localBuildLivePowerRuntimeTable(src, powerEnergyTable, meta, cfg)
if ~(istable(src.EnergyTimeline) && ~isempty(src.EnergyTimeline) && istable(powerEnergyTable) && ~isempty(powerEnergyTable))
    T = table();
    return;
end
n = min(height(src.EnergyTimeline), height(powerEnergyTable));
rows = repmat(localEmptyCanonicalPowerFactRow(), n, 1);
for i = 1:n
    timelineRow = src.EnergyTimeline(i, :);
    energyRow = powerEnergyTable(i, :);
    rows(i) = localFillCanonicalPowerBaseRow(meta, cfg, timelineRow, energyRow, ...
        "entity_total_runtime_power_w", ...
        double(localTableValue(timelineRow, "Power_W", NaN)), ...
        "W", ...
        "Modeled entity runtime power over the observed slot interval from the RF energy timeline.", ...
        "reports_live_power_runtime_table");
    rows(i).artifact_id = "reports/csv/live_power_runtime_table.csv#" + string(i);
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLivePowerRuntimeTable", ...
    "rf/csv/energy_timeline_trace.csv|rf/csv/power_energy_table.csv", "implemented", "runtime_truth_fact", true, true);
end

function T = localBuildLiveRFPowerTable(livePowerRuntimeTable, meta)
if ~(istable(livePowerRuntimeTable) && ~isempty(livePowerRuntimeTable))
    T = table();
    return;
end
T = livePowerRuntimeTable;
T.stage_name = repmat("rf_power_domain", height(T), 1);
T.function_name = repmat("sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveRFPowerTable", height(T), 1);
T.metric_name = repmat("rf_domain_total_power_w", height(T), 1);
T.metric_value = double(T.metric_value);
T.metric_unit = repmat("W", height(T), 1);
T.value_source = repmat("rf/csv/energy_timeline_trace.csv:Power_W", height(T), 1);
T.value_definition = repmat("RF-energy-domain entity total power derived from the runtime energy timeline.", height(T), 1);
T.source_table = repmat("live_power_runtime_table", height(T), 1);
T.source_pk = (1:height(T))';
T.artifact_id = "reports/csv/live_rf_power_table.csv#" + string((1:height(T))');
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveRFPowerTable", ...
    "reports/csv/live_power_runtime_table.csv", "implemented", "runtime_truth_fact", true, true);
end

function T = localBuildLiveBBPowerTable(src, meta, cfg)
if ~(istable(src.EnergyTimeline) && ~isempty(src.EnergyTimeline))
    T = table();
    return;
end
rows = repmat(localEmptyCanonicalPowerFactRow(), 0, 1);
for i = 1:height(src.EnergyTimeline)
    timelineRow = src.EnergyTimeline(i, :);
    duration_s = double(localTableValue(timelineRow, "Duration_s", NaN));
    bbEnergyJ = double(localTableValue(timelineRow, "BBProcessingEnergy_J", NaN));
    if ~(isfinite(duration_s) && duration_s > 0 && isfinite(bbEnergyJ) && bbEnergyJ > 0)
        continue;
    end
    bbPowerW = bbEnergyJ / duration_s;
    stubEnergy = table( ...
        localEnergyTimestampMs(timelineRow, meta), localNormalizeEntityType(string(localTableValue(timelineRow, "EntityType", ""))), ...
        localResolveEnergyEntityID(timelineRow), string(localTableValue(timelineRow, "Direction", "")), bbPowerW, ...
        'VariableNames', {'timestamp_sim_ms','entity_type','entity_id','direction','power_estimate_value'});
    row = localFillCanonicalPowerBaseRow(meta, cfg, timelineRow, stubEnergy, ...
        "digital_baseband_power_w", bbPowerW, "W", ...
        "Digital baseband / TRX-chain processing power derived from BBProcessingEnergy_J over the observed slot interval.", ...
        "reports_live_bb_power_table");
    row.digital_baseband_power_w = bbPowerW;
    row.metric_value = bbPowerW;
    row.value_source = "rf/csv/energy_timeline_trace.csv:BBProcessingEnergy_J,Duration_s";
    row.value_status = localValueStatus(bbPowerW, "NOT_AVAILABLE");
    row.na_reason = localTernary(isfinite(bbPowerW), "", "bb_processing_energy_not_materialized");
    row.artifact_id = "reports/csv/live_bb_power_table.csv#" + string(i);
    rows(end+1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveBBPowerTable", ...
    "rf/csv/energy_timeline_trace.csv", "implemented", "runtime_truth_fact", true, true);
end

function T = localBuildLiveEnergyEfficiencyTable(powerEnergyTable, meta, cfg)
if ~(istable(powerEnergyTable) && ~isempty(powerEnergyTable))
    T = table();
    return;
end
entityType = string(localColumnAsText(powerEnergyTable, "entity_type"));
entityID = localColumnAsDouble(powerEnergyTable, "entity_id");
direction = string(localColumnAsText(powerEnergyTable, "direction"));
entityType(ismissing(entityType)) = "";
direction(ismissing(direction)) = "";
groupIdx = findgroups(categorical(entityType), entityID, categorical(direction));
groupIds = unique(groupIdx(groupIdx > 0));
rows = repmat(localEmptyCanonicalPowerFactRow(), numel(groupIds), 1);
for i = 1:numel(groupIds)
    mask = groupIdx == groupIds(i);
    subset = powerEnergyTable(mask, :);
    groupEntityType = entityType(find(mask, 1, "first"));
    groupEntityID = entityID(find(mask, 1, "first"));
    groupDirection = direction(find(mask, 1, "first"));
    totalEnergyJ = sum(localColumnAsDouble(subset, "energy_increment_mJ"), "omitnan") / 1e3;
    usefulBits = sum(localColumnAsDouble(subset, "useful_bits"), "omitnan");
    energyPerBitJ = localPowerEntityEnergyPerBit(totalEnergyJ, usefulBits);
    effBitsPerJ = localPowerEntityEfficiency(usefulBits, totalEnergyJ);
    row = localEmptyCanonicalPowerFactRow();
    row.direction = groupDirection;
    row.ue_id = localTernary(groupEntityType == "ue", groupEntityID, NaN);
    row.bs_id = localTernary(groupEntityType == "cell", groupEntityID, NaN);
    row.sfn = NaN;
    row.slot = NaN;
    row.symbol = NaN;
    row.run_id = meta.run_id;
    row.trial_id = NaN;
    row.run_uuid = "";
    row.run_tag = meta.run_tag;
    row.scenario_id = meta.scenario_id;
    row.timestamp_utc = "";
    row.data_origin = "canonical_energy_efficiency_aggregation";
    row.status = "OK";
    row.value_role = "aggregated";
    row.value_source = "reports/csv/live_power_runtime_table.csv";
    row.value_status = localValueStatus(energyPerBitJ, "NOT_AVAILABLE");
    row.value_definition = "Entity energy divided by useful successfully delivered bits over the observed runtime.";
    row.finalized_flag = true;
    row.partial_row_flag = false;
    row.fallback_flag = false;
    row.placeholder_flag = false;
    row.config_only_flag = false;
    row.cell_id = row.bs_id;
    row.sector_id = NaN;
    row.site_id = NaN;
    row.trp_id = NaN;
    row.link_id = NaN;
    row.carrier_id = NaN;
    row.bwp_id = NaN;
    row.numerology = localDeriveNumerologyMu(meta.scs_hz / 1e3);
    row.scs_khz = meta.scs_hz / 1e3;
    row.bandwidth_hz = meta.bandwidth_hz;
    row.center_frequency_hz = meta.carrier_frequency_hz;
    row.duplex_mode = "";
    row.beam_id = NaN;
    row.layer_id = NaN;
    row.codeword_id = NaN;
    row.harq_process_id = NaN;
    row.rv = NaN;
    row.channel_name = "energy_efficiency";
    row.signal_name = "runtime_energy";
    row.block_name = "power_energy";
    row.function_name = "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveEnergyEfficiencyTable";
    row.stage_name = "energy_efficiency_runtime_rollup";
    row.metric_name = "entity_energy_per_bit_j";
    row.metric_value = energyPerBitJ;
    row.metric_unit = "J/bit";
    row.artifact_id = "reports/csv/live_energy_efficiency_table.csv#" + string(i);
    row.git_sha = meta.code_commit;
    row.build_id = "";
    row.config_hash = meta.config_hash;
    row.seed = meta.seed;
    row.source_system = "lls_truth_runtime";
    row.source_db = "artifact_filesystem";
    row.source_schema = "reports_csv";
    row.source_table = "live_power_runtime_table";
    row.source_pk = i;
    row.na_reason = localTernary(isfinite(energyPerBitJ), "", "entity_has_no_useful_bits_for_energy_efficiency");
    row.energy_per_bit_j = energyPerBitJ;
    row.joules_per_gb = localPowerJoulesPerGB(energyPerBitJ);
    row.cell_energy_efficiency = localTernary(groupEntityType == "cell", effBitsPerJ, NaN);
    row.ue_energy_efficiency = localTernary(groupEntityType == "ue", effBitsPerJ, NaN);
    row.sleep_state = "";
    row.thermal_state = "";
    row.throttling_flag = NaN;
    rows(i) = row;
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveEnergyEfficiencyTable", ...
    "reports/csv/live_power_runtime_table.csv", "implemented", "runtime_truth_fact", true, true);
end

function T = localBuildLiveSleepStateTable(src, meta, cfg)
if ~(istable(src.EnergyTimeline) && ~isempty(src.EnergyTimeline))
    T = table();
    return;
end
entityType = lower(string(localColumnAsText(src.EnergyTimeline, "EntityType")));
entityID = localColumnAsDouble(src.EnergyTimeline, "EntityID");
direction = string(localColumnAsText(src.EnergyTimeline, "Direction"));
state = string(localColumnAsText(src.EnergyTimeline, "State"));
duration = localColumnAsDouble(src.EnergyTimeline, "Duration_s");
entityType(ismissing(entityType)) = "";
direction(ismissing(direction)) = "";
state(ismissing(state)) = "";
groupIdx = findgroups(categorical(entityType), entityID, categorical(direction), categorical(state));
groupIds = unique(groupIdx(groupIdx > 0));
rows = repmat(localEmptyCanonicalPowerFactRow(), numel(groupIds), 1);
for i = 1:numel(groupIds)
    mask = groupIdx == groupIds(i);
    subset = src.EnergyTimeline(mask, :);
    groupEntityType = entityType(find(mask, 1, "first"));
    groupEntityID = entityID(find(mask, 1, "first"));
    groupDirection = direction(find(mask, 1, "first"));
    groupState = state(find(mask, 1, "first"));
    totalDuration = sum(duration(mask), "omitnan");
    entityMask = entityType == groupEntityType & entityID == groupEntityID & direction == groupDirection;
    entityDuration = sum(duration(entityMask), "omitnan");
    occupancy = localSafeDivide(totalDuration, entityDuration);
    totalEnergyJ = sum(localColumnAsDouble(subset, "Energy_J"), "omitnan");
    row = localEmptyCanonicalPowerFactRow();
    row.direction = groupDirection;
    row.ue_id = localTernary(groupEntityType == "ue", groupEntityID, NaN);
    row.bs_id = localTernary(groupEntityType == "cell", groupEntityID, NaN);
    row.run_id = meta.run_id;
    row.trial_id = NaN;
    row.run_uuid = "";
    row.run_tag = meta.run_tag;
    row.scenario_id = meta.scenario_id;
    row.timestamp_utc = "";
    row.data_origin = "canonical_sleep_state_aggregation";
    row.status = "OK";
    row.value_role = "aggregated";
    row.value_source = "rf/csv/energy_timeline_trace.csv";
    row.value_status = localValueStatus(occupancy, "NOT_AVAILABLE");
    row.value_definition = "Observed runtime state occupancy fraction for the entity and direction over the energy timeline.";
    row.finalized_flag = true;
    row.partial_row_flag = false;
    row.fallback_flag = false;
    row.placeholder_flag = false;
    row.config_only_flag = false;
    row.cell_id = row.bs_id;
    row.numerology = localDeriveNumerologyMu(meta.scs_hz / 1e3);
    row.scs_khz = meta.scs_hz / 1e3;
    row.bandwidth_hz = meta.bandwidth_hz;
    row.center_frequency_hz = meta.carrier_frequency_hz;
    row.channel_name = "sleep_state";
    row.signal_name = "runtime_energy";
    row.block_name = "power_energy";
    row.function_name = "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveSleepStateTable";
    row.stage_name = "sleep_state_rollup";
    row.metric_name = "state_occupancy_fraction";
    row.metric_value = occupancy;
    row.metric_unit = "fraction";
    row.artifact_id = "reports/csv/live_sleep_state_table.csv#" + string(i);
    row.git_sha = meta.code_commit;
    row.build_id = "";
    row.config_hash = meta.config_hash;
    row.seed = meta.seed;
    row.source_system = "lls_truth_runtime";
    row.source_db = "artifact_filesystem";
    row.source_schema = "reports_csv";
    row.source_table = "energy_timeline_trace";
    row.source_pk = i;
    row.na_reason = localTernary(isfinite(occupancy), "", "state_occupancy_not_materialized");
    row.sleep_state = localSleepStateToken(groupState);
    row.energy_per_bit_j = localPowerEntityEnergyPerBit(totalEnergyJ, sum(localColumnAsDouble(subset, "SuccessfulBits"), "omitnan"));
    rows(i) = row;
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLiveSleepStateTable", ...
    "rf/csv/energy_timeline_trace.csv", "implemented", "runtime_truth_fact", true, true);
end

function T = localBuildPowerAnalyticsTable(livePowerRuntimeTable, meta)
T = localBuildCanonicalPowerAggregateAnalytics(livePowerRuntimeTable, meta, "mean_power_w", "mean(metric_value)", "W", @mean);
end

function T = localBuildEnergyEfficiencyAnalyticsTable(liveEnergyEfficiencyTable, meta)
if ~(istable(liveEnergyEfficiencyTable) && ~isempty(liveEnergyEfficiencyTable))
    T = table();
    return;
end
rows = repmat(localEmptyCanonicalPowerAnalyticsRow(), height(liveEnergyEfficiencyTable), 1);
for i = 1:height(liveEnergyEfficiencyTable)
    rows(i) = localCopyFactRowToAnalytics(liveEnergyEfficiencyTable(i, :), ...
        "energy_efficiency_identity", ...
        "identity(live_energy_efficiency_table.metric_value)", ...
        1, ...
        double(~isfinite(localTableValue(liveEnergyEfficiencyTable(i, :), "metric_value", NaN))));
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildEnergyEfficiencyAnalyticsTable", ...
    "reports/csv/live_energy_efficiency_table.csv", "implemented", "derived_from_canonical_reports", true, true);
end

function T = localBuildRuntimePowerAnalyticsTable(livePowerRuntimeTable, liveBBPowerTable, meta)
powerT = localBuildCanonicalPowerAggregateAnalytics(livePowerRuntimeTable, meta, "peak_power_w", "max(metric_value)", "W", @max);
bbT = localBuildCanonicalPowerAggregateAnalytics(liveBBPowerTable, meta, "mean_bb_power_w", "mean(metric_value)", "W", @mean);
if isempty(powerT)
    T = bbT;
elseif isempty(bbT)
    T = powerT;
else
    T = [powerT; bbT]; %#ok<AGROW>
end
if isempty(T)
    return;
end
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRuntimePowerAnalyticsTable", ...
    "reports/csv/live_power_runtime_table.csv|reports/csv/live_bb_power_table.csv", "implemented", "derived_from_canonical_reports", true, true);
end

function T = localBuildSleepStateAnalyticsTable(liveSleepStateTable, meta)
if ~(istable(liveSleepStateTable) && ~isempty(liveSleepStateTable))
    T = table();
    return;
end
rows = repmat(localEmptyCanonicalPowerAnalyticsRow(), height(liveSleepStateTable), 1);
for i = 1:height(liveSleepStateTable)
    rows(i) = localCopyFactRowToAnalytics(liveSleepStateTable(i, :), ...
        "sleep_state_occupancy_fraction", ...
        "sum(duration_s_in_state)/sum(duration_s_for_entity_direction)", ...
        1, ...
        double(~isfinite(localTableValue(liveSleepStateTable(i, :), "metric_value", NaN))));
end
T = struct2table(rows, "AsArray", true);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildSleepStateAnalyticsTable", ...
    "reports/csv/live_sleep_state_table.csv", "implemented", "derived_from_canonical_reports", true, true);
end

function T = localBuildCanonicalPowerAggregateAnalytics(factT, meta, metricName, formula, metricUnit, reducer)
if ~(istable(factT) && ~isempty(factT))
    T = table();
    return;
end
entityType = string(localColumnAsText(factT, "entity_type"));
entityID = localColumnAsDouble(factT, "entity_id");
direction = string(localColumnAsText(factT, "direction"));
entityType(ismissing(entityType)) = "";
direction(ismissing(direction)) = "";
groupIdx = findgroups(categorical(entityType), entityID, categorical(direction));
groupIds = unique(groupIdx(groupIdx > 0));
rows = repmat(localEmptyCanonicalPowerAnalyticsRow(), numel(groupIds), 1);
for i = 1:numel(groupIds)
    mask = groupIdx == groupIds(i);
    subset = factT(mask, :);
    metricVals = localColumnAsDouble(subset, "metric_value");
    validVals = metricVals(isfinite(metricVals));
    if isempty(validVals)
        metricValue = NaN;
    else
        metricValue = reducer(validVals);
    end
    base = subset(1, :);
    row = localCopyFactRowToAnalytics(base, string(metricName), string(formula), numel(validVals), sum(~isfinite(metricVals)));
    row.metric_name = string(metricName);
    row.metric_value = metricValue;
    row.metric_unit = string(metricUnit);
    row.value_role = "aggregated";
    row.value_status = localValueStatus(metricValue, "NOT_AVAILABLE");
    row.value_source = "reports/csv/live_power_runtime_table.csv";
    row.value_definition = "Aggregated canonical power metric derived from live power runtime rows.";
    row.source_table = "live_power_runtime_table";
    row.source_pk = i;
    row.artifact_id = "analytics/csv/" + string(metricName) + "#" + string(i);
    rows(i) = row;
end
T = struct2table(rows, "AsArray", true);
end

function row = localCopyFactRowToAnalytics(baseRow, formulaId, formula, validCount, missingCount)
row = localEmptyCanonicalPowerAnalyticsRow();
names = intersect(string(baseRow.Properties.VariableNames), string(fieldnames(row)), 'stable');
for i = 1:numel(names)
    row.(char(names(i))) = baseRow.(char(names(i)))(1);
end
row.formula_id = string(formulaId);
row.formula = string(formula);
row.valid_sample_count = double(validCount);
row.missing_sample_count = double(missingCount);
row.baseline_run_id = NaN;
row.candidate_run_id = NaN;
end

function row = localFillCanonicalPowerBaseRow(meta, cfg, timelineRow, energyRow, metricName, metricValue, metricUnit, valueDefinition, dataOrigin)
row = localEmptyCanonicalPowerFactRow();
frameVal = double(localTableValue(timelineRow, "Frame", NaN));
slotVal = double(localTableValue(timelineRow, "Slot", NaN));
symbolVal = double(localTableValue(timelineRow, "Symbol", NaN));
entityType = localNormalizeEntityType(string(localTableValue(timelineRow, "EntityType", localTableValue(timelineRow, "Entity", ""))));
entityId = localResolveEnergyEntityID(timelineRow);
direction = string(localTableValue(timelineRow, "Direction", ""));
duration_s = double(localTableValue(timelineRow, "Duration_s", NaN));
bbEnergyJ = double(localTableValue(timelineRow, "BBProcessingEnergy_J", NaN));
bbPowerW = NaN;
if isfinite(duration_s) && duration_s > 0 && isfinite(bbEnergyJ)
    bbPowerW = bbEnergyJ / duration_s;
end
usefulBits = double(localTableValue(timelineRow, "SuccessfulBits", localTableValue(energyRow, "useful_bits", NaN)));
energyPerBitJ = double(localTableValue(energyRow, "energy_per_bit_nJ", NaN));
if isfinite(energyPerBitJ)
    energyPerBitJ = energyPerBitJ * 1e-9;
else
    energyPerBitJ = localPowerEntityEnergyPerBit(double(localTableValue(timelineRow, "Energy_J", NaN)), usefulBits);
end
powerVal = double(metricValue);
row.direction = direction;
row.ue_id = double(localTableValue(timelineRow, "UEID", localTableValue(timelineRow, "RNTI", NaN)));
row.bs_id = double(localTableValue(timelineRow, "BaseStationID", localTableValue(timelineRow, "CellID", NaN)));
row.sfn = localTernary(isfinite(frameVal), mod(max(frameVal - 1, 0), 1024), NaN);
row.slot = slotVal;
row.symbol = symbolVal;
row.run_id = meta.run_id;
row.trial_id = NaN;
row.run_uuid = "";
row.run_tag = meta.run_tag;
row.scenario_id = meta.scenario_id;
row.timestamp_utc = "";
row.data_origin = string(dataOrigin);
row.status = localRowStatusOrDefault(timelineRow, "OK");
row.value_role = "derived";
row.value_source = "rf/csv/energy_timeline_trace.csv";
row.value_status = localValueStatus(powerVal, "NOT_AVAILABLE");
row.value_definition = string(valueDefinition);
row.finalized_flag = true;
row.partial_row_flag = false;
row.fallback_flag = false;
row.placeholder_flag = false;
row.config_only_flag = false;
row.cell_id = double(localTableValue(timelineRow, "CellID", NaN));
row.sector_id = NaN;
row.site_id = NaN;
row.trp_id = NaN;
row.link_id = NaN;
row.carrier_id = NaN;
row.bwp_id = NaN;
row.numerology = localDeriveNumerologyMu(meta.scs_hz / 1e3);
row.scs_khz = meta.scs_hz / 1e3;
row.bandwidth_hz = meta.bandwidth_hz;
row.center_frequency_hz = meta.carrier_frequency_hz;
row.duplex_mode = "";
row.beam_id = NaN;
row.layer_id = double(localTableValue(timelineRow, "ActiveRank", NaN));
row.codeword_id = NaN;
row.harq_process_id = NaN;
row.rv = NaN;
row.channel_name = "power_energy";
row.signal_name = string(localTableValue(timelineRow, "Domain", "runtime_energy"));
row.block_name = "power_energy";
row.function_name = "sixgr.truth.exportLLSOutputCoverageArtifacts";
row.stage_name = string(localTableValue(timelineRow, "State", "runtime_energy"));
row.metric_name = string(metricName);
row.metric_value = powerVal;
row.metric_unit = string(metricUnit);
row.artifact_id = "rf/csv/energy_timeline_trace.csv#" + string(localTableValue(energyRow, "source_pk", NaN));
row.git_sha = meta.code_commit;
row.build_id = "";
row.config_hash = meta.config_hash;
row.seed = meta.seed;
row.source_system = "lls_truth_runtime";
row.source_db = "artifact_filesystem";
row.source_schema = "rf_csv";
row.source_table = "energy_timeline_trace";
row.source_pk = double(localTableValue(energyRow, "source_pk", NaN));
row.na_reason = localNonMaterializedReason(powerVal, bbPowerW);
if upper(direction) == "DL" && entityType == "cell"
    row.dl_tx_power_dbm = double(localTableValue(timelineRow, "TxPower_dBm", NaN));
else
    row.dl_tx_power_dbm = NaN;
end
if upper(direction) == "UL" && entityType == "ue"
    row.ul_tx_power_dbm = double(localTableValue(timelineRow, "TxPower_dBm", NaN));
else
    row.ul_tx_power_dbm = NaN;
end
row.power_control_command = NaN;
row.pa_backoff_db = NaN;
row.rf_chain_power_w = NaN;
row.digital_baseband_power_w = bbPowerW;
row.cpu_power_w = NaN;
row.memory_bandwidth_bytes_s = NaN;
row.memory_utilization = NaN;
row.ComputeLatency_ms = NaN;
row.DecodeLatency_ms = NaN;
row.AirInterfaceTTI_ms = localTernary(isfinite(duration_s), duration_s * 1e3, NaN);
row.AirInterfaceObservation_ms = localTernary(isfinite(duration_s), duration_s * 1e3, NaN);
row.ProcedureDelay_ms = NaN;
row.Latency_ms = NaN;
row.cpu_cycles = NaN;
row.memory_bytes = NaN;
row.queue_depth = NaN;
row.lock_wait_ms = NaN;
row.contention_count = NaN;
row.AreaEfficiencyProxy = NaN;
row.PAPR_dB = NaN;
row.PeakClippingEvents = NaN;
row.energy_per_bit_j = energyPerBitJ;
row.joules_per_gb = localPowerJoulesPerGB(energyPerBitJ);
entityEfficiency = localPowerEntityEfficiency(usefulBits, double(localTableValue(timelineRow, "Energy_J", NaN)));
row.cell_energy_efficiency = localTernary(entityType == "cell", entityEfficiency, NaN);
row.ue_energy_efficiency = localTernary(entityType == "ue", entityEfficiency, NaN);
row.sleep_state = localSleepStateToken(string(localTableValue(timelineRow, "State", "")));
row.thermal_state = "";
row.throttling_flag = NaN;
row.timestamp_sim_ms = localEnergyTimestampMs(timelineRow, meta);
row.frame = frameVal;
row.entity_type = entityType;
row.entity_id = entityId;
row.state = string(localTableValue(timelineRow, "State", ""));
row.duration_s = duration_s;
row.cumulative_energy_j = double(localTableValue(energyRow, "cumulative_energy_J", NaN));
row.successful_bits = usefulBits;
end

function row = localEmptyCanonicalPowerFactRow()
row = struct( ...
    "direction", "", "ue_id", NaN, "bs_id", NaN, "sfn", NaN, "slot", NaN, "symbol", NaN, ...
    "run_id", NaN, "trial_id", NaN, "run_uuid", "", "run_tag", "", "scenario_id", "", "timestamp_utc", "", ...
    "data_origin", "", "status", "", "value_role", "", "value_source", "", "value_status", "", "value_definition", "", ...
    "finalized_flag", false, "partial_row_flag", false, "fallback_flag", false, "placeholder_flag", false, "config_only_flag", false, ...
    "cell_id", NaN, "sector_id", NaN, "site_id", NaN, "trp_id", NaN, "link_id", NaN, "carrier_id", NaN, "bwp_id", NaN, ...
    "numerology", NaN, "scs_khz", NaN, "bandwidth_hz", NaN, "center_frequency_hz", NaN, "duplex_mode", "", ...
    "beam_id", NaN, "layer_id", NaN, "codeword_id", NaN, "harq_process_id", NaN, "rv", NaN, ...
    "channel_name", "", "signal_name", "", "block_name", "", "function_name", "", "stage_name", "", ...
    "metric_name", "", "metric_value", NaN, "metric_unit", "", "artifact_id", "", "git_sha", "", "build_id", "", ...
    "config_hash", "", "seed", NaN, "source_system", "", "source_db", "", "source_schema", "", "source_table", "", ...
    "source_pk", NaN, "na_reason", "", "dl_tx_power_dbm", NaN, "ul_tx_power_dbm", NaN, "power_control_command", NaN, ...
    "pa_backoff_db", NaN, "rf_chain_power_w", NaN, "digital_baseband_power_w", NaN, "cpu_power_w", NaN, ...
    "memory_bandwidth_bytes_s", NaN, "memory_utilization", NaN, "ComputeLatency_ms", NaN, "DecodeLatency_ms", NaN, ...
    "AirInterfaceTTI_ms", NaN, "AirInterfaceObservation_ms", NaN, "ProcedureDelay_ms", NaN, "Latency_ms", NaN, ...
    "cpu_cycles", NaN, "memory_bytes", NaN, "queue_depth", NaN, "lock_wait_ms", NaN, "contention_count", NaN, ...
    "AreaEfficiencyProxy", NaN, "PAPR_dB", NaN, "PeakClippingEvents", NaN, "energy_per_bit_j", NaN, "joules_per_gb", NaN, ...
    "cell_energy_efficiency", NaN, "ue_energy_efficiency", NaN, "sleep_state", "", "thermal_state", "", "throttling_flag", NaN, ...
    "timestamp_sim_ms", NaN, "frame", NaN, "entity_type", "", "entity_id", NaN, "state", "", "duration_s", NaN, ...
    "cumulative_energy_j", NaN, "successful_bits", NaN);
end

function row = localEmptyCanonicalPowerAnalyticsRow()
row = localEmptyCanonicalPowerFactRow();
row.formula_id = "";
row.formula = "";
row.valid_sample_count = NaN;
row.missing_sample_count = NaN;
row.baseline_run_id = NaN;
row.candidate_run_id = NaN;
end

function val = localPowerEntityEnergyPerBit(totalEnergyJ, usefulBits)
if isfinite(totalEnergyJ) && isfinite(usefulBits) && usefulBits > 0
    val = totalEnergyJ / usefulBits;
else
    val = NaN;
end
end

function val = localPowerJoulesPerGB(energyPerBitJ)
if isfinite(energyPerBitJ)
    val = energyPerBitJ * 8e9;
else
    val = NaN;
end
end

function val = localPowerEntityEfficiency(usefulBits, totalEnergyJ)
if isfinite(usefulBits) && isfinite(totalEnergyJ) && totalEnergyJ > 0
    val = usefulBits / totalEnergyJ;
else
    val = NaN;
end
end

function token = localSleepStateToken(state)
state = lower(string(state));
if contains(state, "sleep")
    token = "sleep";
elseif contains(state, "idle")
    token = "idle";
elseif contains(state, "monitor")
    token = "monitor";
elseif strlength(state) == 0
    token = "";
else
    token = "active";
end
end

function status = localRowStatusOrDefault(T, defaultValue)
status = string(localTableValue(T, "Status", defaultValue));
if strlength(status) == 0
    status = string(defaultValue);
end
end

function reason = localNonMaterializedReason(metricValue, bbPowerW)
missing = strings(0, 1);
if ~isfinite(metricValue)
    missing(end+1, 1) = "metric_value_not_materialized"; %#ok<AGROW>
end
if ~isfinite(bbPowerW)
    missing(end+1, 1) = "digital_baseband_component_not_separately_materialized"; %#ok<AGROW>
end
missing(end+1, 1) = "timestamp_utc_not_materialized_in_runtime_energy_trace"; %#ok<AGROW>
reason = strjoin(missing(strlength(missing) > 0), ";");
end

function T = localBuildRootCauseCandidateTable(src, meta)
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "direction", "", "symptom", "", ...
    "severity_score", NaN, "candidate_reason", "", "evidence_metric", "", "evidence_value", NaN, ...
    "source_artifact_ref", ""), 0, 1);
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    for i = 1:height(src.SystemInterference)
        sinr = double(localTableValue(src.SystemInterference(i, :), "SINR_DL_dB", NaN));
        interf = double(localTableValue(src.SystemInterference(i, :), "InterferencePowerDL_dBm", NaN));
        if isfinite(sinr) && sinr < 0
            rows(end+1, 1) = struct( ... %#ok<AGROW>
                "ue_id", localTableValue(src.SystemInterference(i, :), "UE", NaN), ...
                "cell_id", localTableValue(src.SystemInterference(i, :), "ServingCell", NaN), ...
                "direction", "DL", ...
                "symptom", "low_sinr_window", ...
                "severity_score", abs(sinr), ...
                "candidate_reason", localTernary(isfinite(interf), "interference_dominant", "low_sinr_no_interference_breakdown"), ...
                "evidence_metric", "SINR_DL_dB", ...
                "evidence_value", sinr, ...
                "source_artifact_ref", "system/csv/system_interference_detail.csv");
        end
    end
else
    rows = localBuildRootCauseRowsFromCoverageAndUserPerf(src, meta);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = sortrows(T, "severity_score", "descend");
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRootCauseCandidateTable", ...
    localRootCauseSourceRef(src), "implemented", "derived_root_cause_candidates", true, true);
end

function T = localBuildCellEdgeAnalyticsTable(src, meta)
if istable(src.SystemUE) && ~isempty(src.SystemUE)
    mask = localColumnMatchesText(src.SystemUE, "Zone", "edge");
    if ~any(mask)
        T = table();
        return;
    end
    T = src.SystemUE(mask, :);
    renameFrom = intersect({'UE','Throughput_Mbps','MeanSINR_dB','MeanBLER','MeanQueue_bits'}, string(T.Properties.VariableNames), 'stable');
    renameToMap = containers.Map({'UE','Throughput_Mbps','MeanSINR_dB','MeanBLER','MeanQueue_bits'}, ...
        {'ue_id','throughput_mbps','mean_sinr_db','mean_bler','mean_queue_bits'});
    renameTo = strings(numel(renameFrom), 1);
    for i = 1:numel(renameFrom)
        renameTo(i) = string(renameToMap(char(renameFrom(i))));
    end
    if ~isempty(renameFrom)
        T = renamevars(T, cellstr(renameFrom), cellstr(renameTo));
    end
    T = addvars(T, repmat("edge_zone_runtime_summary", height(T), 1), 'NewVariableNames', "analytics_scope");
else
    T = localBuildCellEdgeFromCoverageLayer(src);
    if isempty(T)
        return;
    end
end
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCellEdgeAnalyticsTable", ...
    localCellEdgeSourceRef(src), "implemented", "runtime_summary_slice", true, true);
end

function T = localBuildBeamStabilityAnalyticsTable(src, meta)
if istable(src.SystemBeam) && ~isempty(src.SystemBeam)
    ueVals = unique(localColumnAsDouble(src.SystemBeam, "UE"));
    rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "beam_event_count", NaN, "beam_change_count", NaN, ...
        "max_beam_gain_db", NaN, "mean_beam_gain_delta_db", NaN, "stability_class", "", ...
        "source_artifact_ref", ""), numel(ueVals), 1);
    for i = 1:numel(ueVals)
        ue = ueVals(i);
        mask = localColumnMatches(src.SystemBeam, "UE", ue);
        subset = src.SystemBeam(mask, :);
        gainDelta = localColumnAsDouble(subset, "NewBeamGain_dB") - localColumnAsDouble(subset, "PrevBeamGain_dB");
        gainDelta(~isfinite(gainDelta)) = 0;
        rows(i).ue_id = ue;
        rows(i).cell_id = localTableValue(subset(1, :), "ServingCell", NaN);
        rows(i).beam_event_count = height(subset);
        rows(i).beam_change_count = sum(isfinite(localColumnAsDouble(subset, "PrevBeamIndex")));
        rows(i).max_beam_gain_db = max(localColumnAsDouble(subset, "NewBeamGain_dB"), [], "omitnan");
        rows(i).mean_beam_gain_delta_db = mean(gainDelta, "omitnan");
        rows(i).stability_class = string(localTernary(rows(i).beam_change_count <= 1, "stable", "changing"));
        rows(i).source_artifact_ref = "system/csv/system_beam_events.csv";
    end
else
    rows = localBuildBeamStabilityRowsFromTrials(src);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamStabilityAnalyticsTable", ...
    localBeamStabilitySourceRef(src), "implemented", "runtime_aggregated", true, true);
end

function T = localBuildEnergyRootCauseTable(powerEnergyTable, meta)
if ~(istable(powerEnergyTable) && ~isempty(powerEnergyTable))
    T = table();
    return;
end
entityType = string(localColumnAsText(powerEnergyTable, "entity_type"));
entityID = localColumnAsDouble(powerEnergyTable, "entity_id");
keyStrings = entityType + ":" + string(entityID);
validRows = strlength(entityType) > 0 & isfinite(entityID);
keys = unique(keyStrings(validRows));
if isempty(keys)
    T = table();
    return;
end
rows = repmat(struct("entity_type", "", "entity_id", NaN, "total_energy_j", NaN, ...
    "useful_bits", NaN, "energy_per_bit_nj", NaN, "dominant_state", "", "root_cause_reason", "", ...
    "source_artifact_ref", ""), numel(keys), 1);
for i = 1:numel(keys)
    mask = keyStrings == keys(i);
    subset = powerEnergyTable(mask, :);
    if isempty(subset)
        continue;
    end
    rows(i).entity_type = string(localTableValue(subset(1, :), "entity_type", ""));
    rows(i).entity_id = double(localTableValue(subset(1, :), "entity_id", NaN));
    rows(i).total_energy_j = sum(localColumnAsDouble(subset, "energy_increment_mJ"), "omitnan") / 1e3;
    rows(i).useful_bits = sum(localColumnAsDouble(subset, "useful_bits"), "omitnan");
    rows(i).energy_per_bit_nj = localEnergyPerBit(rows(i).total_energy_j, rows(i).useful_bits);
    states = string(localColumnAsText(subset, "state"));
    if isempty(states)
        rows(i).dominant_state = "";
    else
        rows(i).dominant_state = states(1);
    end
    rows(i).root_cause_reason = string(localTernary(rows(i).useful_bits <= 0, "energy_without_useful_bits", "active_runtime_energy"));
    rows(i).source_artifact_ref = "rf/csv/power_energy_table.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildEnergyRootCauseTable", ...
    "rf/csv/power_energy_table.csv", "implemented", "derived_energy_root_cause", true, true);
end

function T = localBuildAnomalyWindowTable(issueRegistry, meta)
if ~(istable(issueRegistry) && ~isempty(issueRegistry))
    T = table();
    return;
end
rows = repmat(struct("issue_id", "", "severity", "", "issue_category", "", "direction", "", ...
    "ue_id", NaN, "cell_id", NaN, "window_start_ms", NaN, "window_end_ms", NaN, ...
    "anomaly_metric", "", "anomaly_evidence", "", "source_artifact_ref", ""), height(issueRegistry), 1);
for i = 1:height(issueRegistry)
    issueRow = issueRegistry(i, :);
    rows(i).issue_id = string(localTableValue(issueRow, "issue_id", ""));
    rows(i).severity = string(localTableValue(issueRow, "severity", ""));
    rows(i).issue_category = string(localTableValue(issueRow, "issue_category", ""));
    rows(i).direction = string(localTableValue(issueRow, "direction", ""));
    rows(i).ue_id = double(localTableValue(issueRow, "ue_id", NaN));
    rows(i).cell_id = double(localTableValue(issueRow, "cell_id", NaN));
    rows(i).window_start_ms = double(localTableValue(issueRegistry(i, :), "timestamp_sim_ms", NaN));
    rows(i).window_end_ms = rows(i).window_start_ms;
    rows(i).anomaly_metric = string(localTableValue(issueRow, "metric_name", ""));
    rows(i).anomaly_evidence = string(localTableValue(issueRow, "observed_value", ""));
    rows(i).source_artifact_ref = string(localTableValue(issueRow, "evidence_artifact_ref", ""));
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildAnomalyWindowTable", ...
    "reports/csv/result_issue_registry.csv", "implemented", "derived_issue_windows", true, true);
end

function T = localBuildCrossLayerCorrelationTable(src, meta)
rows = repmat(struct("direction", "", "x_metric", "", "y_metric", "", "sample_count", NaN, ...
    "correlation_value", NaN, "correlation_method", "", "source_artifact_ref", ""), 0, 1);
rows = localAppendGrantCorrelation(rows, src.DLGrants, "DL", "SINR_dB", "MCSIndex", "packet_flow/csv/live_dl_scheduler_grants.csv");
rows = localAppendGrantCorrelation(rows, src.ULGrants, "UL", "SINR_dB", "MCSIndex", "packet_flow/csv/live_ul_scheduler_grants.csv");
rows = localAppendGrantCorrelation(rows, src.DLGrants, "DL", "CQIUsed", "MCSIndex", "packet_flow/csv/live_dl_scheduler_grants.csv");
rows = localAppendGrantCorrelation(rows, src.ULGrants, "UL", "CQIUsed", "MCSIndex", "packet_flow/csv/live_ul_scheduler_grants.csv");
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCrossLayerCorrelationTable", ...
    "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv", ...
    "implemented", "derived_cross_layer_correlation", true, true);
end

function T = localBuildHotspotAnalyticsTable(src, meta)
if istable(src.SystemUE) && ~isempty(src.SystemUE)
    zone = localColumnAsText(src.SystemUE, "Zone");
    traffic = localColumnAsText(src.SystemUE, "TrafficClass");
    if all(strlength(zone) == 0) && all(strlength(traffic) == 0)
        T = table();
        return;
    end
    keys = zone + "|" + traffic;
    keys(strlength(keys) == 1) = "all|all";
    [uniqueKeys, ~, keyIdx] = unique(keys);
    rows = repmat(struct("zone", "", "traffic_class", "", "ue_count", NaN, "mean_throughput_mbps", NaN, ...
        "mean_sinr_db", NaN, "mean_bler", NaN, "mean_queue_bits", NaN, "hotspot_reason", "", ...
        "source_artifact_ref", ""), numel(uniqueKeys), 1);
    for i = 1:numel(uniqueKeys)
        mask = keyIdx == i;
        parts = split(uniqueKeys(i), "|");
        rows(i).zone = parts(1);
        rows(i).traffic_class = parts(min(2, numel(parts)));
        rows(i).ue_count = sum(mask);
        rows(i).mean_throughput_mbps = localMeanFromMask(src.SystemUE, mask, "Throughput_Mbps");
        rows(i).mean_sinr_db = localMeanFromMask(src.SystemUE, mask, "MeanSINR_dB");
        rows(i).mean_bler = localMeanFromMask(src.SystemUE, mask, "MeanBLER");
        rows(i).mean_queue_bits = localMeanFromMask(src.SystemUE, mask, "MeanQueue_bits");
        rows(i).hotspot_reason = localTernary(isfinite(rows(i).mean_queue_bits) && rows(i).mean_queue_bits > 0, ...
            "runtime_queue_or_load_observed", "runtime_population_summary");
        rows(i).source_artifact_ref = "system/csv/system_ue_summary.csv";
    end
else
    rows = localBuildHotspotRowsFromCoverageLayer(src);
end
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildHotspotAnalyticsTable", ...
    localHotspotSourceRef(src), "implemented", "derived_runtime_hotspot_summary", true, true);
end

function ref = localGNBCellStatusSource(src)
ref = localJoinSourceRefs( ...
    localTernary(istable(src.SystemSectors) && ~isempty(src.SystemSectors), "system/tables/sectors.csv", "reports/csv/sectors.csv"), ...
    localTernary(istable(src.SystemCellLoad) && ~isempty(src.SystemCellLoad), "system/csv/system_cell_load.csv", "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv|packet_flow/csv/slot_trace.csv"), ...
    localTernary(istable(src.SystemInterference) && ~isempty(src.SystemInterference), "system/csv/system_interference_detail.csv", "reports/csv/live_coverage_layer.csv"), ...
    localTernary(istable(src.SystemBeam) && ~isempty(src.SystemBeam), "system/csv/system_beam_events.csv", "beamforming/csv/beam_precoder_table.csv"));
end

function ref = localNoiseInterferenceSourceRef(src)
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    ref = "system/csv/system_interference_detail.csv";
else
    ref = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv|reports/csv/live_coverage_layer.csv";
end
end

function ref = localLinkBudgetSourceRef(src)
ref = localNoiseInterferenceSourceRef(src);
end

function ref = localHARQSourceRef(src)
if istable(src.SystemHARQ) && ~isempty(src.SystemHARQ)
    ref = "system/csv/system_harq_processes.csv";
else
    ref = "harq/csv/live_harq_observation_timeline.csv|packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv";
end
end

function ref = localRootCauseSourceRef(src)
if istable(src.SystemInterference) && ~isempty(src.SystemInterference)
    ref = "system/csv/system_interference_detail.csv";
else
    ref = "reports/csv/live_coverage_layer.csv|reports/csv/live_user_performance_snapshot.csv";
end
end

function ref = localCellEdgeSourceRef(src)
if istable(src.SystemUE) && ~isempty(src.SystemUE)
    ref = "system/csv/system_ue_summary.csv";
else
    ref = "reports/csv/live_coverage_layer.csv|reports/csv/live_user_performance_snapshot.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
end
end

function ref = localBeamStabilitySourceRef(src)
if istable(src.SystemBeam) && ~isempty(src.SystemBeam)
    ref = "system/csv/system_beam_events.csv";
else
    ref = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
end
end

function ref = localHotspotSourceRef(src)
if istable(src.SystemUE) && ~isempty(src.SystemUE)
    ref = "system/csv/system_ue_summary.csv";
else
    ref = "reports/csv/live_coverage_layer.csv|reports/csv/live_user_performance_snapshot.csv|packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv";
end
end

function ref = localJoinSourceRefs(varargin)
tokens = strings(0, 1);
for i = 1:nargin
    value = string(varargin{i});
    if strlength(strtrim(value)) > 0
        parts = split(value, "|");
        tokens = [tokens; parts(strlength(strtrim(parts)) > 0)]; %#ok<AGROW>
    end
end
tokens = unique(strtrim(tokens), "stable");
tokens = tokens(strlength(tokens) > 0);
ref = strjoin(tokens, "|");
end

function value = localCoverageMeanByCell(T, cellId, varargin)
value = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(cellId))
    return;
end
mask = localColumnMatches(T, "ServingCell", cellId);
for i = 1:numel(varargin)
    value = localMeanFromMask(T, mask, string(varargin{i}));
    if isfinite(value)
        return;
    end
end
end

function value = localMeanTrialMetricByCell(T, cellId, varNames)
value = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(cellId))
    return;
end
cellVals = localFirstAvailableColumnAsDouble(T, ["ServingCell", "CellID", "BaseStationID"]);
mask = isfinite(cellVals) & cellVals == cellId;
for i = 1:numel(varNames)
    vals = localColumnAsDouble(T(mask, :), string(varNames(i)));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = mean(vals, "omitnan");
        return;
    end
end
end

function count = localCoverageEdgeUECount(T, cellId)
count = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(cellId))
    return;
end
mask = localColumnMatches(T, "ServingCell", cellId) & localCoverageIsEdgeMask(T);
ueVals = localColumnAsDouble(T(mask, :), "UEID");
ueVals = unique(ueVals(isfinite(ueVals)));
count = double(numel(ueVals));
end

function mask = localCoverageIsEdgeMask(T)
mask = false(height(T), 1);
if ~(istable(T) && ~isempty(T))
    return;
end
if ismember("CoverageScore", string(T.Properties.VariableNames))
    vals = localColumnAsDouble(T, "CoverageScore");
    mask = isfinite(vals) & vals < 0.75;
elseif ismember("LargeScaleWidebandSINR_dB", string(T.Properties.VariableNames))
    vals = localColumnAsDouble(T, "LargeScaleWidebandSINR_dB");
    mask = isfinite(vals) & vals < 5;
elseif ismember("LargeScaleSINR_dB", string(T.Properties.VariableNames))
    vals = localColumnAsDouble(T, "LargeScaleSINR_dB");
    mask = isfinite(vals) & vals < 5;
end
end

function count = localBeamMismatchCount(T, cellId)
count = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(cellId))
    return;
end
mask = localColumnMatches(T, "cell_id", cellId);
if ~ismember("beam_hit", string(T.Properties.VariableNames))
    count = double(sum(mask));
    return;
end
beamHit = localColumnAsDouble(T(mask, :), "beam_hit");
count = double(sum(isfinite(beamHit) & beamHit < 0.5));
end

function value = localGrantUniqueUEStat(dlGrants, ulGrants, cellId, mode)
mode = lower(string(mode));
counts = [localGrantUniqueCounts(dlGrants, cellId); localGrantUniqueCounts(ulGrants, cellId)];
counts = counts(isfinite(counts));
if isempty(counts)
    value = NaN;
elseif mode == "max"
    value = max(counts);
else
    value = mean(counts, "omitnan");
end
end

function counts = localGrantUniqueCounts(grants, cellId)
counts = nan(0, 1);
if ~(istable(grants) && ~isempty(grants) && isfinite(cellId))
    return;
end
cellVals = localFirstAvailableColumnAsDouble(grants, ["CellID", "ServingCell", "BaseStationID"]);
frameVals = localFirstAvailableColumnAsDouble(grants, ["Frame", "SFN"]);
slotVals = localFirstAvailableColumnAsDouble(grants, ["Slot"]);
ueVals = localFirstAvailableColumnAsDouble(grants, ["UE", "UEID", "UEIndex", "RNTI"]);
mask = isfinite(cellVals) & cellVals == cellId & isfinite(frameVals) & isfinite(slotVals) & isfinite(ueVals);
if ~any(mask)
    return;
end
keys = frameVals(mask) * 1e3 + slotVals(mask);
uniqueKeys = unique(keys, "stable");
counts = nan(numel(uniqueKeys), 1);
for i = 1:numel(uniqueKeys)
    keyMask = mask & (frameVals * 1e3 + slotVals == uniqueKeys(i));
    keyUEs = unique(ueVals(keyMask));
    counts(i) = double(numel(keyUEs(isfinite(keyUEs))));
end
end

function cellId = localCoverageCellForUE(T, ue)
cellId = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(ue))
    return;
end
mask = localColumnMatches(T, "UEID", ue);
cellVals = localColumnAsDouble(T(mask, :), "ServingCell");
cellVals = cellVals(isfinite(cellVals));
if ~isempty(cellVals)
    cellId = cellVals(end);
end
end

function cellId = localTrialCellForUE(dlT, ulT, ue)
cellId = localTrialMetricForUE(dlT, ulT, ue, "ServingCell");
end

function value = localCoverageMetricForUE(T, ue, varargin)
value = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(ue))
    return;
end
mask = localColumnMatches(T, "UEID", ue);
for i = 1:numel(varargin)
    vals = localColumnAsDouble(T(mask, :), string(varargin{i}));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = mean(vals, "omitnan");
        return;
    end
end
end

function value = localTrialMetricForUE(dlT, ulT, ue, varargin)
value = NaN;
parts = {dlT, ulT};
for p = 1:numel(parts)
    T = parts{p};
    if ~(istable(T) && ~isempty(T) && isfinite(ue))
        continue;
    end
    ueVals = localFirstAvailableColumnAsDouble(T, ["UEID", "UEIndex", "RNTI"]);
    mask = isfinite(ueVals) & ueVals == ue;
    for i = 1:numel(varargin)
        vals = localColumnAsDouble(T(mask, :), string(varargin{i}));
        vals = vals(isfinite(vals));
        if ~isempty(vals)
            value = mean(vals, "omitnan");
            return;
        end
    end
end
end

function rows = localBuildNoiseRowsFromTrials(src, meta, cfg)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "serving_cell_id", NaN, "desired_signal_power_dBm", NaN, ...
    "intra_cell_interference_dBm", NaN, "inter_cell_interference_dBm", NaN, "external_interference_dBm", NaN, ...
    "noise_power_dBm", NaN, "thermal_noise_dBm", NaN, "receiver_noise_figure_dB", NaN, ...
    "total_interference_plus_noise_dBm", NaN, "pre_eq_sinr_dB", NaN, "post_eq_sinr_dB", NaN, ...
    "dominant_interferer_cell_id", NaN, "dominant_interferer_share_percent", NaN, ...
    "interference_limited_flag", false, "source_block", "", "direction", ""), 0, 1);
rows = [rows; localNoiseRowsFromTrialTable(src.DLTrials, "DL", meta, double(localScenarioStructGet(cfg, {"receiver.noiseFigure_dB", "baseStation.noiseFigure_dB"}, NaN)))]; %#ok<AGROW>
rows = [rows; localNoiseRowsFromTrialTable(src.ULTrials, "UL", meta, double(localScenarioStructGet(cfg, {"receiver.noiseFigure_dB", "userEquipment.noiseFigure_dB"}, NaN)))]; %#ok<AGROW>
end

function rows = localNoiseRowsFromTrialTable(trials, direction, meta, nfDb)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "serving_cell_id", NaN, "desired_signal_power_dBm", NaN, ...
    "intra_cell_interference_dBm", NaN, "inter_cell_interference_dBm", NaN, "external_interference_dBm", NaN, ...
    "noise_power_dBm", NaN, "thermal_noise_dBm", NaN, "receiver_noise_figure_dB", NaN, ...
    "total_interference_plus_noise_dBm", NaN, "pre_eq_sinr_dB", NaN, "post_eq_sinr_dB", NaN, ...
    "dominant_interferer_cell_id", NaN, "dominant_interferer_share_percent", NaN, ...
    "interference_limited_flag", false, "source_block", "", "direction", ""), 0, 1);
if ~(istable(trials) && ~isempty(trials))
    return;
end
for i = 1:height(trials)
    row = trials(i, :);
    interf = localFirstFinite(double(localTableValue(row, "InterferenceAggregatedRxPower_dBm", NaN)));
    noise = NaN;
    totalIn = localSafeLogPowerSum(interf, noise);
    postEq = localFirstFinite(double(localTableValue(row, "PostEqSINR_dB", ...
        localTableValue(row, "MeasuredTrialSINR_dB", localTableValue(row, "MeasuredSINR_dB", NaN)))));
    preEq = localFirstFinite(double(localTableValue(row, "LargeScaleSINR_dB", NaN)));
    contributorCount = localFirstFinite(double(localTableValue(row, "InterferenceContributorCount", 0)));
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "timestamp_sim_ms", localTrialTimestampMs(row, meta), ...
        "ue_id", localTableValue(row, "UEID", localTableValue(row, "UEIndex", NaN)), ...
        "serving_cell_id", localTableValue(row, "ServingCell", NaN), ...
        "desired_signal_power_dBm", localTableValue(row, "ServingRSRP_dBm", NaN), ...
        "intra_cell_interference_dBm", NaN, ...
        "inter_cell_interference_dBm", interf, ...
        "external_interference_dBm", NaN, ...
        "noise_power_dBm", noise, ...
        "thermal_noise_dBm", NaN, ...
        "receiver_noise_figure_dB", nfDb, ...
        "total_interference_plus_noise_dBm", totalIn, ...
        "pre_eq_sinr_dB", preEq, ...
        "post_eq_sinr_dB", postEq, ...
        "dominant_interferer_cell_id", NaN, ...
        "dominant_interferer_share_percent", NaN, ...
        "interference_limited_flag", logical(isfinite(interf) && ((isfinite(preEq) && isfinite(postEq) && postEq < preEq) || (isfinite(contributorCount) && contributorCount > 0))), ...
        "source_block", "air_interface_trial_row", ...
        "direction", string(direction));
end
end

function rows = localBuildLinkBudgetRowsFromTrials(src, meta, cfg)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "direction", "", ...
    "tx_power_dBm", NaN, "tx_antenna_gain_dBi", NaN, "rx_antenna_gain_dBi", NaN, "pathloss_dB", NaN, ...
    "shadowing_dB", NaN, "penetration_loss_dB", NaN, "implementation_loss_dB", NaN, ...
    "rx_power_dBm", NaN, "interference_power_dBm", NaN, "noise_power_dBm", NaN, ...
    "snr_dB", NaN, "sinr_dB", NaN, "margin_dB", NaN, "power_control_command", NaN, ...
    "phr_dB", NaN, "source_chain", ""), 0, 1);
txPowerByCell = localTxPowerByCell(src.SystemTRPs);
rows = [rows; localLinkBudgetRowsFromTrialTable(src.DLTrials, "DL", meta, cfg, txPowerByCell)]; %#ok<AGROW>
rows = [rows; localLinkBudgetRowsFromTrialTable(src.ULTrials, "UL", meta, cfg, txPowerByCell)]; %#ok<AGROW>
end

function rows = localLinkBudgetRowsFromTrialTable(trials, direction, meta, cfg, txPowerByCell)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "direction", "", ...
    "tx_power_dBm", NaN, "tx_antenna_gain_dBi", NaN, "rx_antenna_gain_dBi", NaN, "pathloss_dB", NaN, ...
    "shadowing_dB", NaN, "penetration_loss_dB", NaN, "implementation_loss_dB", NaN, ...
    "rx_power_dBm", NaN, "interference_power_dBm", NaN, "noise_power_dBm", NaN, ...
    "snr_dB", NaN, "sinr_dB", NaN, "margin_dB", NaN, "power_control_command", NaN, ...
    "phr_dB", NaN, "source_chain", ""), 0, 1);
if ~(istable(trials) && ~isempty(trials))
    return;
end
implLoss = double(localScenarioStructGet(cfg, {"baseStation.implementationLoss_dB", "system.bsImplementationLoss_dB"}, NaN));
for i = 1:height(trials)
    row = trials(i, :);
    cellId = localTableValue(row, "ServingCell", NaN);
    if direction == "DL"
        txPower = localMapLookup(txPowerByCell, cellId, NaN);
    else
        txPower = double(localScenarioStructGet(cfg, {"userEquipment.txPower_dBm", "energy.txPower_dBm"}, NaN));
    end
    pathloss = localFirstFinite(double(localTableValue(row, "AppliedPathloss_dB", localTableValue(row, "AppliedBasePathloss_dB", NaN))));
    rxPower = localFirstFinite(double(localTableValue(row, "ServingRSRP_dBm", NaN)));
    interf = localFirstFinite(double(localTableValue(row, "InterferenceAggregatedRxPower_dBm", NaN)));
    noise = NaN;
    snr = localFirstFinite(double(localTableValue(row, "LargeScaleSINR_dB", NaN)));
    sinr = localFirstFinite(double(localTableValue(row, "PostEqSINR_dB", ...
        localTableValue(row, "MeasuredTrialSINR_dB", localTableValue(row, "MeasuredSINR_dB", NaN)))));
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "timestamp_sim_ms", localTrialTimestampMs(row, meta), ...
        "ue_id", localTableValue(row, "UEID", localTableValue(row, "UEIndex", NaN)), ...
        "cell_id", cellId, ...
        "direction", string(direction), ...
        "tx_power_dBm", txPower, ...
        "tx_antenna_gain_dBi", NaN, ...
        "rx_antenna_gain_dBi", NaN, ...
        "pathloss_dB", pathloss, ...
        "shadowing_dB", NaN, ...
        "penetration_loss_dB", NaN, ...
        "implementation_loss_dB", implLoss, ...
        "rx_power_dBm", rxPower, ...
        "interference_power_dBm", interf, ...
        "noise_power_dBm", noise, ...
        "snr_dB", snr, ...
        "sinr_dB", sinr, ...
        "margin_dB", NaN, ...
        "power_control_command", NaN, ...
        "phr_dB", NaN, ...
        "source_chain", "waveform_trial_runtime_rows");
end
end

function rows = localBuildHARQRowsFromTimeline(src, meta)
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "direction", "", "harq_id", NaN, ...
    "ndi", NaN, "rv", NaN, "tx_count", NaN, "first_tx_time", NaN, "last_tx_time", NaN, ...
    "ack_nack_state", "", "final_state", "", "combined_rounds", NaN, "combining_gain_dB", NaN, ...
    "buffer_occupancy_bits", NaN, "timeout_flag", false, "discard_reason", ""), 0, 1);
T = src.HARQTimeline;
if ~(istable(T) && ~isempty(T))
    return;
end
ueVals = localColumnAsDouble(T, "UEIndex");
harqVals = localColumnAsDouble(T, "HarqID");
dirVals = localColumnAsText(T, "Direction");
keys = string(ueVals) + "|" + dirVals + "|" + string(harqVals);
uniqueKeys = unique(keys(strlength(keys) > 0), "stable");
for i = 1:numel(uniqueKeys)
    mask = keys == uniqueKeys(i);
    subset = T(mask, :);
    ue = localTableValue(subset(1, :), "UEIndex", NaN);
    direction = string(localTableValue(subset(1, :), "Direction", ""));
    slots = localColumnAsDouble(subset, "Slot");
    cellId = localResolveHARQCellFromGrants(src, direction, ue, slots);
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "ue_id", ue, ...
        "cell_id", cellId, ...
        "direction", direction, ...
        "harq_id", localTableValue(subset(1, :), "HarqID", NaN), ...
        "ndi", localTableValue(subset(1, :), "NDI", NaN), ...
        "rv", localTableValue(subset(end, :), "RV", NaN), ...
        "tx_count", height(subset), ...
        "first_tx_time", localSlotFrameToMs(localTableValue(subset(1, :), "Frame", NaN), localTableValue(subset(1, :), "Slot", NaN), meta), ...
        "last_tx_time", localSlotFrameToMs(localTableValue(subset(end, :), "Frame", NaN), localTableValue(subset(end, :), "Slot", NaN), meta), ...
        "ack_nack_state", string(localTableValue(subset(end, :), "Status", "")), ...
        "final_state", string(localTableValue(subset(end, :), "Status", "")), ...
        "combined_rounds", height(subset), ...
        "combining_gain_dB", NaN, ...
        "buffer_occupancy_bits", localQueueBitsForUE(src, ue), ...
        "timeout_flag", false, ...
        "discard_reason", "");
end
end

function rows = localBuildRootCauseRowsFromCoverageAndUserPerf(src, meta)
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "direction", "", "symptom", "", ...
    "severity_score", NaN, "candidate_reason", "", "evidence_metric", "", "evidence_value", NaN, ...
    "source_artifact_ref", ""), 0, 1);
if istable(src.CoverageLayer) && ~isempty(src.CoverageLayer)
    ueVals = unique(localColumnAsDouble(src.CoverageLayer, "UEID"));
    ueVals = ueVals(isfinite(ueVals));
    for i = 1:numel(ueVals)
        ue = ueVals(i);
        largeScale = localCoverageMetricForUE(src.CoverageLayer, ue, "LargeScaleWidebandSINR_dB", "LargeScaleSINR_dB");
        measured = localCoverageMetricForUE(src.CoverageLayer, ue, "PostEqWidebandSINR_dB", "PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB");
        failureRate = localUserPerformanceMetric(src.UserPerformance, ue, "HARQFailureRate");
        harqObs = localUserPerformanceMetric(src.UserPerformance, ue, "HARQObservationCount");
        failureEvidenceReady = isfinite(failureRate) && failureRate >= 0.5 && isfinite(harqObs) && harqObs >= 3;
        if (isfinite(largeScale) && largeScale < 5) || failureEvidenceReady
            controlledSweepHARQ = failureEvidenceReady && ...
                logical(sixgr.util.structGet(meta, ...
                "controlled_snr_sweep", false)) && ...
                ~(isfinite(largeScale) && largeScale < 5);
            rows(end+1, 1) = struct( ... %#ok<AGROW>
                "ue_id", ue, ...
                "cell_id", localCoverageCellForUE(src.CoverageLayer, ue), ...
                "direction", "BIDIR", ...
                "symptom", localTernary(isfinite(largeScale) && largeScale < 5, ...
                "coverage_edge_observed", localTernary(controlledSweepHARQ, ...
                "controlled_snr_sweep_harq_outage_observed", "harq_failure_window")), ...
                "severity_score", max([abs(min(largeScale, 0)), 10 * failureRate], [], "omitnan"), ...
                "candidate_reason", localTernary(isfinite(largeScale) && largeScale < 5, ...
                "coverage_edge_lab_default_threshold", localTernary(controlledSweepHARQ, ...
                "expected_low_snr_operating_points_contribute_to_harq_failure_rate", ...
                "high_harq_failure_rate")), ...
                "evidence_metric", localTernary(isfinite(largeScale) && largeScale < 5, "LargeScaleWidebandSINR_dB", "HARQFailureRate"), ...
                "evidence_value", localTernary(isfinite(largeScale) && largeScale < 5, largeScale, failureRate), ...
                "source_artifact_ref", "reports/csv/live_coverage_layer.csv|reports/csv/live_user_performance_snapshot.csv|harq/csv/live_harq_observation_timeline.csv");
        elseif isfinite(measured) && measured < 0
            rows(end+1, 1) = struct( ... %#ok<AGROW>
                "ue_id", ue, ...
                "cell_id", localCoverageCellForUE(src.CoverageLayer, ue), ...
                "direction", "BIDIR", ...
                "symptom", "low_sinr_window", ...
                "severity_score", abs(measured), ...
                "candidate_reason", "measured_trial_sinr_negative", ...
                "evidence_metric", "MeasuredWidebandSINR_dB", ...
                "evidence_value", measured, ...
                "source_artifact_ref", "reports/csv/live_coverage_layer.csv");
        end
    end
end
end

function T = localBuildCellEdgeFromCoverageLayer(src)
rows = repmat(struct("ue_id", NaN, "throughput_mbps", NaN, "mean_sinr_db", NaN, "mean_bler", NaN, "mean_queue_bits", NaN, "analytics_scope", ""), 0, 1);
if ~(istable(src.CoverageLayer) && ~isempty(src.CoverageLayer))
    T = table();
    return;
end
edgeMask = localCoverageIsEdgeMask(src.CoverageLayer);
ueVals = unique(localColumnAsDouble(src.CoverageLayer(edgeMask, :), "UEID"));
ueVals = ueVals(isfinite(ueVals));
for i = 1:numel(ueVals)
    ue = ueVals(i);
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "ue_id", ue, ...
        "throughput_mbps", localUserPerformanceMetric(src.UserPerformance, ue, "UserThroughput_Mbps"), ...
        "mean_sinr_db", localCoverageMetricForUE(src.CoverageLayer, ue, "PostEqWidebandSINR_dB", "PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "LargeScaleWidebandSINR_dB"), ...
        "mean_bler", localTrialBLERForUE(src, ue), ...
        "mean_queue_bits", localQueueBitsForUE(src, ue), ...
        "analytics_scope", "edge_zone_runtime_summary_from_waveform_coverage");
end
if isempty(rows)
    T = table();
else
    T = struct2table(rows, "AsArray", true);
end
end

function rows = localBuildBeamStabilityRowsFromTrials(src)
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "beam_event_count", NaN, "beam_change_count", NaN, ...
    "max_beam_gain_db", NaN, "mean_beam_gain_delta_db", NaN, "stability_class", "", ...
    "source_artifact_ref", ""), 0, 1);
T = localBuildBeamTrialSubset(src.DLTrials, src.ULTrials);
if ~(istable(T) && ~isempty(T))
    return;
end
ueVals = localColumnAsDouble(T, "UEID");
ueVals = unique(ueVals(isfinite(ueVals)));
for i = 1:numel(ueVals)
    ue = ueVals(i);
    ueCol = localColumnAsDouble(T, "UEID");
    mask = isfinite(ueCol) & ueCol == ue;
    subset = T(mask, :);
    if isempty(subset)
        continue;
    end
    beamIdx = localColumnAsDouble(subset, "SelectedBeamIndex");
    beamIdx = beamIdx(isfinite(beamIdx));
    beamGain = localColumnAsDouble(subset, "SelectedBeamGain_dB");
    beamGain = beamGain(isfinite(beamGain));
    gainDelta = diff(beamGain);
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "ue_id", ue, ...
        "cell_id", localTableValue(subset(1, :), "ServingCell", NaN), ...
        "beam_event_count", height(subset), ...
        "beam_change_count", double(sum(abs(diff(beamIdx)) > 0)), ...
        "max_beam_gain_db", localTernary(isempty(beamGain), NaN, max(beamGain, [], "omitnan")), ...
        "mean_beam_gain_delta_db", localTernary(isempty(gainDelta), NaN, mean(gainDelta, "omitnan")), ...
        "stability_class", string(localTernary(sum(abs(diff(beamIdx)) > 0) <= 1, "stable", "changing")), ...
        "source_artifact_ref", "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv");
end
end

function T = localBuildBeamTrialSubset(dlTrials, ulTrials)
T = table();
for trials = {dlTrials, ulTrials}
    Ti = localNormalizeBeamTrialSubset(trials{1});
    if isempty(T)
        T = Ti;
    elseif ~(istable(Ti) && isempty(Ti))
        T = [T; Ti]; %#ok<AGROW>
    end
end
end

function T = localNormalizeBeamTrialSubset(Tin)
T = table();
if ~(istable(Tin) && ~isempty(Tin))
    return;
end
ueVals = localFirstAvailableColumnAsDouble(Tin, ["UEID", "UEIndex"]);
cellVals = localFirstAvailableColumnAsDouble(Tin, ["ServingCell", "CellID", "BaseStationID"]);
beamIdx = localFirstAvailableColumnAsDouble(Tin, ["SelectedBeamIndex", "AppliedBeamIndex", "BeamIndex"]);
beamGain = localFirstAvailableColumnAsDouble(Tin, ["SelectedBeamGain_dB", "AppliedBeamGain_dB", "BeamGain_dB"]);
valid = isfinite(ueVals) & (isfinite(beamIdx) | isfinite(beamGain));
if ~any(valid)
    return;
end
T = table();
T.UEID = ueVals(valid);
T.ServingCell = cellVals(valid);
T.SelectedBeamIndex = beamIdx(valid);
T.SelectedBeamGain_dB = beamGain(valid);
end

function rows = localBuildHotspotRowsFromCoverageLayer(src)
rows = repmat(struct("zone", "", "traffic_class", "", "ue_count", NaN, "mean_throughput_mbps", NaN, ...
    "mean_sinr_db", NaN, "mean_bler", NaN, "mean_queue_bits", NaN, "hotspot_reason", "", ...
    "source_artifact_ref", ""), 0, 1);
if ~(istable(src.CoverageLayer) && ~isempty(src.CoverageLayer))
    return;
end
ueVals = unique(localColumnAsDouble(src.CoverageLayer, "UEID"));
ueVals = ueVals(isfinite(ueVals));
if isempty(ueVals)
    return;
end
zoneVals = repmat("center", numel(ueVals), 1);
for i = 1:numel(ueVals)
    ueMask = localColumnMatches(src.CoverageLayer, "UEID", ueVals(i));
    zoneVals(i) = localTernary(any(localCoverageIsEdgeMask(src.CoverageLayer(ueMask, :))), "edge", "center");
end
zones = ["center", "edge"];
for zoneIdx = 1:numel(zones)
    zone = zones(zoneIdx);
    zoneMask = zoneVals == zone;
    if ~any(zoneMask)
        continue;
    end
    theseUEs = ueVals(zoneMask);
    throughput = nan(numel(theseUEs), 1);
    sinrVals = nan(numel(theseUEs), 1);
    blerVals = nan(numel(theseUEs), 1);
    queueVals = nan(numel(theseUEs), 1);
    for i = 1:numel(theseUEs)
        throughput(i) = localUserPerformanceMetric(src.UserPerformance, theseUEs(i), "UserThroughput_Mbps");
        sinrVals(i) = localCoverageMetricForUE(src.CoverageLayer, theseUEs(i), "PostEqWidebandSINR_dB", "PostEqSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredTrialSINR_dB", "LargeScaleWidebandSINR_dB");
        blerVals(i) = localTrialBLERForUE(src, theseUEs(i));
        queueVals(i) = localQueueBitsForUE(src, theseUEs(i));
    end
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "zone", zone, ...
        "traffic_class", "full_buffer", ...
        "ue_count", double(numel(theseUEs)), ...
        "mean_throughput_mbps", mean(throughput, "omitnan"), ...
        "mean_sinr_db", mean(sinrVals, "omitnan"), ...
        "mean_bler", mean(blerVals, "omitnan"), ...
        "mean_queue_bits", mean(queueVals, "omitnan"), ...
        "hotspot_reason", localTernary(any(isfinite(queueVals) & queueVals > 0), "runtime_queue_or_load_observed", "runtime_population_summary"), ...
        "source_artifact_ref", "reports/csv/live_coverage_layer.csv|reports/csv/live_user_performance_snapshot.csv");
end
end

function value = localUserPerformanceMetric(T, ue, varName)
value = NaN;
if ~(istable(T) && ~isempty(T) && isfinite(ue) && ismember("UEIndex", string(T.Properties.VariableNames)) && ismember(string(varName), string(T.Properties.VariableNames)))
    return;
end
mask = localColumnMatches(T, "UEIndex", ue);
vals = localColumnAsDouble(T(mask, :), varName);
vals = vals(isfinite(vals));
if ~isempty(vals)
    value = mean(vals, "omitnan");
end
end

function value = localTrialBLERForUE(src, ue)
value = NaN;
parts = {src.DLTrials, src.ULTrials};
vals = nan(0, 1);
for p = 1:numel(parts)
    T = parts{p};
    if ~(istable(T) && ~isempty(T))
        continue;
    end
    ueCol = localFirstAvailableColumnAsDouble(T, ["UEID", "UEIndex"]);
    mask = isfinite(ueCol) & ueCol == ue;
    if any(mask) && ismember("CRCPass", string(T.Properties.VariableNames))
        crc = localColumnAsDouble(T(mask, :), "CRCPass");
        crc = crc(isfinite(crc));
        if ~isempty(crc)
            vals(end+1, 1) = mean(1 - crc, "omitnan"); %#ok<AGROW>
        end
    end
end
if ~isempty(vals)
    value = mean(vals, "omitnan");
end
end

function value = localQueueBitsForUE(src, ue)
value = NaN;
queueBits = nan(0, 1);
for grants = {src.DLGrants, src.ULGrants}
    T = grants{1};
    if ~(istable(T) && ~isempty(T))
        continue;
    end
    ueCol = localFirstAvailableColumnAsDouble(T, ["UE", "UEID", "UEIndex", "RNTI"]);
    mask = isfinite(ueCol) & ueCol == ue;
    before = localColumnAsDouble(T(mask, :), "QueueBytesBefore");
    after = localColumnAsDouble(T(mask, :), "QueueBytesAfter");
    vals = [before(:); after(:)] * 8;
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        queueBits = [queueBits; vals]; %#ok<AGROW>
    end
end
if ~isempty(queueBits)
    value = mean(queueBits, "omitnan");
end
end

function cellId = localResolveHARQCellFromGrants(src, direction, ue, slots)
cellId = NaN;
direction = upper(string(direction));
T = localTernary(direction == "UL", src.ULGrants, src.DLGrants);
if ~(istable(T) && ~isempty(T))
    return;
end
ueCol = localFirstAvailableColumnAsDouble(T, ["UE", "UEID", "UEIndex", "RNTI"]);
slotCol = localFirstAvailableColumnAsDouble(T, ["Slot"]);
mask = isfinite(ueCol) & ueCol == ue;
if nargin >= 4 && ~isempty(slots)
    mask = mask & ismember(slotCol, slots(isfinite(slots)));
end
cellVals = localFirstAvailableColumnAsDouble(T(mask, :), ["CellID", "ServingCell", "BaseStationID"]);
cellVals = cellVals(isfinite(cellVals));
if ~isempty(cellVals)
    cellId = cellVals(1);
end
end

function value = localTrialTimestampMs(row, meta)
value = localTableValue(row, "TimestampSim_ms", NaN);
if isfinite(value)
    return;
end
value = localSlotFrameToMs(localTableValue(row, "Frame", NaN), localTableValue(row, "Slot", NaN), meta);
end

function value = localSlotFrameToMs(frameVal, slotVal, meta)
value = NaN;
if ~(isfinite(frameVal) && isfinite(slotVal) && isfinite(meta.slots_per_frame) && isfinite(meta.scs_hz))
    return;
end
numerology = localResolveNumerology(meta.scs_hz / 1e3);
localValidateSlotsPerFrame(meta.slots_per_frame, numerology);
slotDurationMs = double(numerology.SlotDurationMilliseconds);
value = ((double(frameVal) - 1) * double(meta.slots_per_frame) + (double(slotVal) - 1)) * slotDurationMs;
end

function total = localSafeLogPowerSum(varargin)
vals = nan(0, 1);
for i = 1:nargin
    v = double(varargin{i});
    if isempty(v)
        continue;
    end
    v = v(:);
    v = v(isfinite(v));
    if ~isempty(v)
        vals = [vals; v]; %#ok<AGROW>
    end
end
if isempty(vals)
    total = NaN;
    return;
end
lin = sum(10.^(vals / 10), "omitnan");
if lin > 0
    total = 10 * log10(lin);
else
    total = NaN;
end
end

function Tout = localAppendCompatTable(Ta, Tb)
if ~(istable(Ta) && ~isempty(Ta))
    if istable(Tb)
        Tout = Tb;
    else
        Tout = table();
    end
    return;
end
if ~(istable(Tb) && ~isempty(Tb))
    Tout = Ta;
    return;
end
vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
Ta = localEnsureTableVars(Ta, vars, Tb);
Tb = localEnsureTableVars(Tb, vars, Ta);
Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
end

function T = localEnsureTableVars(T, vars, refT)
for i = 1:numel(vars)
    v = char(vars(i));
    if ~ismember(v, T.Properties.VariableNames)
        T.(v) = localDefaultColumnLike(refT, v, height(T));
    end
end
end

function col = localDefaultColumnLike(refT, varName, nRows)
if istable(refT) && ismember(varName, refT.Properties.VariableNames)
    refVal = refT.(varName);
    if isstring(refVal)
        col = strings(nRows, 1);
        return;
    end
    if iscellstr(refVal) || iscell(refVal)
        col = repmat({''}, nRows, 1);
        return;
    end
    if islogical(refVal)
        col = false(nRows, 1);
        return;
    end
    if isnumeric(refVal)
        col = NaN(nRows, 1);
        return;
    end
end
col = strings(nRows, 1);
end

function T = localBuildControlOverheadAnalyticsTable(src, meta)
controlCounts = [
    localControlRowCount(src.PDCCHTrials), ...
    localControlRowCount(src.PBCHTrials), ...
    localControlRowCount(src.PUCCHTrials), ...
    localControlRowCount(src.PRACHTrials), ...
    localControlRowCount(src.SRSTrials), ...
    localControlRowCount(src.CSIRSTrials), ...
    localControlRowCount(src.TRSTrials)];
families = ["PDCCH", "PBCH", "PUCCH", "PRACH", "SRS", "CSI-RS", "TRS"];
grantCount = localControlRowCount(src.DLGrants) + localControlRowCount(src.ULGrants);
if sum(controlCounts) == 0 && grantCount == 0
    T = table();
    return;
end
rows = repmat(struct("signal_family", "", "control_row_count", NaN, "scheduler_grant_row_count", NaN, ...
    "control_rows_per_grant_row", NaN, "overhead_definition", "", "source_artifact_ref", ""), numel(families), 1);
for i = 1:numel(families)
    rows(i).signal_family = families(i);
    rows(i).control_row_count = controlCounts(i);
    rows(i).scheduler_grant_row_count = grantCount;
    rows(i).control_rows_per_grant_row = localSafeDivide(controlCounts(i), grantCount);
    rows(i).overhead_definition = "trial-row count per scheduler grant row; not RE-level control overhead";
    rows(i).source_artifact_ref = "control/csv/*_trials.csv|packet_flow/csv/live_*_scheduler_grants.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildControlOverheadAnalyticsTable", ...
    "control/csv/*_trials.csv|packet_flow/csv/live_*_scheduler_grants.csv", ...
    "implemented", "derived_control_trial_row_overhead", true, true);
end

function T = localBuildResourceOverheadAnalyticsTable(prbTable, meta)
if ~(istable(prbTable) && ~isempty(prbTable))
    T = table();
    return;
end
dirVals = string(prbTable.direction);
cellVals = double(prbTable.cell_id);
[~, ~, dirIdx] = unique(dirVals);
groups = unique([cellVals, double(dirIdx)], "rows");
groups = groups(isfinite(groups(:, 1)) & isfinite(groups(:, 2)), :);
if isempty(groups)
    T = table();
    return;
end
rows = repmat(struct("cell_id", NaN, "direction", "", "allocated_prb_symbols", NaN, ...
    "observed_slot_count", NaN, "observed_prb_count", NaN, "observed_grid_prb_symbols", NaN, ...
    "resource_fraction_observed", NaN, "resource_definition", "", "source_artifact_ref", ""), size(groups, 1), 1);
for i = 1:size(groups, 1)
    mask = cellVals == groups(i, 1) & dirIdx == groups(i, 2);
    subset = prbTable(mask, :);
    allocated = sum(double(subset.num_prbs) .* max(double(subset.symbol_len), 1), "omitnan");
    slotCount = numel(unique(double(subset.slot(isfinite(double(subset.slot))))));
    observedPRBs = max(double(subset.rb_start) + double(subset.rb_len), [], "omitnan");
    denominator = slotCount * observedPRBs * max(meta.symbols_per_slot, 1);
    rows(i).cell_id = groups(i, 1);
    rows(i).direction = dirVals(find(mask, 1, "first"));
    rows(i).allocated_prb_symbols = allocated;
    rows(i).observed_slot_count = slotCount;
    rows(i).observed_prb_count = observedPRBs;
    rows(i).observed_grid_prb_symbols = denominator;
    rows(i).resource_fraction_observed = localSafeDivide(allocated, denominator);
    rows(i).resource_definition = "allocated PRB-symbols divided by observed PRB span, slot count, and symbols per slot";
    rows(i).source_artifact_ref = "packet_flow/csv/live_prb_allocation.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResourceOverheadAnalyticsTable", ...
    "packet_flow/csv/live_prb_allocation.csv", "implemented", "derived_resource_occupancy", true, true);
end

function T = localBuildKPIHealthFlags(src, meta)
rows = [ ...
    localKPIHealthRow("dl_mcs_index", "link_adaptation", "DL", src.DLTrials, ["MCSIndex","MCS"], ...
        "air_interface/csv/dl_pdsch_trials.csv", ["MCSSelectionSource","AMCMode","MCSValueStatus"]); ...
    localKPIHealthRow("ul_mcs_index", "link_adaptation", "UL", src.ULTrials, ["MCSIndex","MCS"], ...
        "air_interface/csv/ul_pusch_trials.csv", ["MCSSelectionSource","AMCMode","MCSValueStatus"]); ...
    localKPIHealthRow("dl_wideband_cqi", "cqi_feedback", "DL", src.DLTrials, ["WidebandCQI","CQI","CQIUsed"], ...
        "air_interface/csv/dl_pdsch_trials.csv", ["CQISource","SINRSource","MCSValueStatus"]); ...
    localKPIHealthRow("ul_wideband_cqi", "cqi_feedback", "UL", src.ULTrials, ["WidebandCQI","CQI","CQIUsed"], ...
        "air_interface/csv/ul_pusch_trials.csv", ["CQISource","SINRSource","MCSValueStatus"]); ...
    localKPIHealthRow("dl_post_eq_sinr_db", "receiver_measurement", "DL", src.DLTrials, ["PostEqSINR_dB","MeasuredTrialSINR_dB"], ...
        "air_interface/csv/dl_pdsch_trials.csv", ["PostEqSINRSource","MeasuredTrialSINRSource","SINRValueRole"]); ...
    localKPIHealthRow("ul_post_eq_sinr_db", "receiver_measurement", "UL", src.ULTrials, ["PostEqSINR_dB","MeasuredTrialSINR_dB"], ...
        "air_interface/csv/ul_pusch_trials.csv", ["PostEqSINRSource","MeasuredTrialSINRSource","SINRValueRole"]); ...
    localKPIHealthRow("dl_goodput_mbps", "throughput", "DL", src.UserPerformance, ["DLGoodput_Mbps","DL_Goodput_Mbps","UserThroughput_Mbps"], ...
        "reports/csv/live_user_performance_snapshot.csv", ["ValueSource","Source"]); ...
    localKPIHealthRow("ul_goodput_mbps", "throughput", "UL", src.UserPerformance, ["ULGoodput_Mbps","UL_Goodput_Mbps","UserThroughput_Mbps"], ...
        "reports/csv/live_user_performance_snapshot.csv", ["ValueSource","Source"]); ...
    localKPIHealthRow("pucch_trial_rows", "control_runtime", "UL", src.PUCCHTrials, ["DecodeSuccess","CRCPass","UCIContentMatch"], ...
        "control/csv/pucch_trials.csv|air_interface/csv/pucch_trials.csv", ["FailureReason","DecodeStatus"]); ...
    localKPIHealthRow("pusch_trial_rows", "air_interface_runtime", "UL", src.ULTrials, ["CRCPass","TBSBits","MCSIndex"], ...
        "air_interface/csv/ul_pusch_trials.csv", ["FailureReason","MCSSelectionSource"]); ...
    localKPIHealthRow("srs_measurement_rows", "reference_signal_runtime", "UL", src.SRSTrials, ["SRSOccupiedPRBCount","BandwidthFraction","ReceiverHestSINR_dB"], ...
        "control/csv/srs_trials.csv|air_interface/csv/srs_trials.csv", ["CoverageStatus","SINRValueStatus"]); ...
    localKPIHealthRow("pdcch_decode_rows", "control_runtime", "DL", src.PDCCHTrials, ["DecodeSuccess","DetectionAttempted","BlindDecodeCandidateCount"], ...
        "control/csv/pdcch_trials.csv|air_interface/csv/pdcch_trials.csv", ["FailureReason","DecodeStatus"]) ...
    ];

T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildKPIHealthFlags", ...
    "air_interface/csv/*_trials.csv|control/csv/*_trials.csv|reports/csv/live_user_performance_snapshot.csv", ...
    "implemented", "derived_kpi_health_audit", true, true);
end

function row = localKPIHealthRow(kpiName, domain, direction, sourceTable, metricVars, sourceArtifactRef, provenanceVars)
rowCount = 0;
finiteCount = 0;
unavailableCount = 0;
diagnosticCount = 0;
proxyFallbackCount = 0;
distinctFiniteCount = 0;
healthStatus = "missing_runtime_rows";
blocker = "source_table_missing_or_empty";
action = "Ensure the runtime producer writes the source table before accepting this KPI.";

if istable(sourceTable) && ~isempty(sourceTable)
    rowCount = height(sourceTable);
    vals = nan(rowCount, numel(metricVars));
    for i = 1:numel(metricVars)
        vals(:, i) = localColumnAsDouble(sourceTable, metricVars(i));
    end
    finiteMask = any(isfinite(vals), 2);
    finiteCount = sum(finiteMask);
    finiteVals = vals(isfinite(vals));
    if ~isempty(finiteVals)
        distinctFiniteCount = numel(unique(round(double(finiteVals(:)) * 1e6) / 1e6));
    end
    statusText = strings(rowCount, 0);
    for i = 1:numel(provenanceVars)
        if localHasVar(sourceTable, provenanceVars(i))
            statusText(:, end+1) = localColumnAsText(sourceTable, provenanceVars(i)); %#ok<AGROW>
        end
    end
    if size(statusText, 2) > 0
        joined = lower(join(statusText, " ", 2));
    else
        joined = strings(rowCount, 1);
    end
    unavailableCount = sum(contains(joined, "unavailable") | contains(joined, "not_materialized") | contains(joined, "missing"));
    diagnosticCount = sum(contains(joined, "diagnostic"));
    proxyFallbackCount = sum(contains(joined, "proxy") | contains(joined, "fallback") | contains(joined, "bootstrap"));
    if finiteCount == 0
        healthStatus = "no_finite_values";
        blocker = "source_rows_present_without_finite_metric_values";
        action = "Inspect metric field names and producer wiring; do not populate charts from placeholders.";
    elseif proxyFallbackCount > 0 || diagnosticCount > 0
        healthStatus = "review_required";
        blocker = "diagnostic_proxy_fallback_or_bootstrap_provenance_present";
        action = "Keep diagnostic/proxy/bootstrap rows out of conformance KPIs unless explicitly filtered and labeled.";
    elseif unavailableCount > 0
        healthStatus = "review_required";
        blocker = "some_rows_disclose_unavailable_metric_state";
        action = "Review unavailable rows before using aggregate KPI charts.";
    else
        healthStatus = "ok";
        blocker = "";
        action = "KPI has finite runtime source values and no proxy/fallback/unavailable provenance markers.";
    end
end

row = struct( ...
    "kpi_name", string(kpiName), ...
    "domain", string(domain), ...
    "direction", string(direction), ...
    "source_artifact_ref", string(sourceArtifactRef), ...
    "runtime_row_count", double(rowCount), ...
    "finite_sample_count", double(finiteCount), ...
    "unavailable_sample_count", double(unavailableCount), ...
    "diagnostic_sample_count", double(diagnosticCount), ...
    "proxy_fallback_sample_count", double(proxyFallbackCount), ...
    "distinct_finite_value_count", double(distinctFiniteCount), ...
    "health_status", string(healthStatus), ...
    "blocker_reason", string(blocker), ...
    "recommended_action", string(action));
end

function T = localBuildResultIssueRegistry(src, meta, tables)
rows = repmat(struct("issue_id", "", "severity", "", "issue_status", "", "issue_category", "", ...
    "direction", "", "ue_id", NaN, "cell_id", NaN, "block_name", "", "metric_name", "", ...
    "observed_value", "", "expected_or_policy", "", "evidence_artifact_ref", "", ...
    "root_cause_hint", "", "fix_plan", "", "frame", NaN, "slot", NaN, "harq_id", NaN, ...
    "analytics_visible_flag", true), 0, 1);

if istable(tables.root_cause_candidate_table) && ~isempty(tables.root_cause_candidate_table)
    for i = 1:height(tables.root_cause_candidate_table)
        row = tables.root_cause_candidate_table(i, :);
        severityScore = double(localTableValue(row, "severity_score", NaN));
        rows(end+1, 1) = localRootCauseIssueRow(row, i, severityScore); %#ok<AGROW>
    end
end

rows = localAppendMCSIssueRows(rows, src.DLTrials, "DL", "air_interface/csv/dl_pdsch_trials.csv");
rows = localAppendMCSIssueRows(rows, src.DLGrants, "DL", "packet_flow/csv/live_dl_scheduler_grants.csv");
rows = localAppendMCSIssueRows(rows, src.ULTrials, "UL", "air_interface/csv/ul_pusch_trials.csv");
rows = localAppendMCSIssueRows(rows, src.ULGrants, "UL", "packet_flow/csv/live_ul_scheduler_grants.csv");

if istable(src.PUCCHGrants) && ~isempty(src.PUCCHGrants) && ~(istable(src.PUCCHTrials) && ~isempty(src.PUCCHTrials))
    rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "pucch_grants_without_trial_rows", "medium", "PARTIAL", "control_channel_runtime", ...
        "UL", NaN, NaN, "PUCCH", "runtime_trial_rows", string(height(src.PUCCHGrants)), ...
        "Every scheduled PUCCH feedback grant needs a consumed trial row or an explicit unavailable reason", ...
        "packet_flow/csv/live_pucch_grants.csv", ...
        "PUCCH grant stream exists but PUCCH trial stream is empty", ...
        "Connect due-feedback processing to PUCCH trial export, or write an explicit unavailable state with owner and reason.");
end

if istable(tables.energy_root_cause_table) && ~isempty(tables.energy_root_cause_table)
    energyReasons = string(tables.energy_root_cause_table.root_cause_reason);
    missingBits = energyReasons == "energy_without_useful_bits";
    for i = find(missingBits(:).')
        row = tables.energy_root_cause_table(i, :);
        energyPerBit = localNumericTableValue(row, "energy_per_bit_nj", NaN);
        if ~isfinite(energyPerBit)
            continue;
        end
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "energy_without_useful_bits_" + string(i), "medium", "REVIEW_REQUIRED", "power_energy", ...
            string(localTableValue(row, "direction", "")), ...
            NaN, NaN, "power/energy", "energy_per_bit_nj", ...
            string(energyPerBit), ...
            "Energy-per-bit must be blank/NaN when useful-bit lineage is zero or unavailable", ...
            "rf/csv/power_energy_table.csv", ...
            "Energy efficiency value was emitted without useful-bit lineage", ...
            "Leave efficiency metrics blank until successful-bit lineage from MAC/PHY payload counters exists.");
    end
end

if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResultIssueRegistry", ...
    "reports/csv/result_issue_registry.csv", "review_required", "derived_issue_registry", true, true);
end

function row = localRootCauseIssueRow(rootCauseRow, idx, severityScore)
severity = localTernary(isfinite(severityScore) && severityScore >= 6, "high", "medium");
issueStatus = "REVIEW_REQUIRED";
symptom = string(localTableValue(rootCauseRow, "symptom", ""));
direction = string(localTableValue(rootCauseRow, "direction", "DL"));
ueId = double(localTableValue(rootCauseRow, "ue_id", NaN));
cellId = double(localTableValue(rootCauseRow, "cell_id", NaN));
metricName = string(localTableValue(rootCauseRow, "evidence_metric", "SINR"));
observedValue = string(localTableValue(rootCauseRow, "evidence_value", NaN));
evidenceRef = string(localTableValue(rootCauseRow, "source_artifact_ref", "reports/csv/root_cause_candidate_table.csv"));
rootCauseHint = string(localTableValue(rootCauseRow, "candidate_reason", "review_required"));

issueId = "root_cause_review_" + string(idx);
issueCategory = "runtime_root_cause";
blockName = "runtime/diagnostics";
expectedPolicy = "Runtime issue rows must keep symptom-specific evidence and remediation semantics.";
fixPlan = "Inspect the referenced runtime evidence before accepting the current conclusion.";

switch symptom
    case "coverage_edge_observed"
        issueId = "coverage_edge_observed_" + string(idx);
        issueCategory = "coverage_edge";
        blockName = "channel/coverage";
        expectedPolicy = "Coverage-edge rows should be backed by low large-scale or measured SINR and explicit serving-cell evidence.";
        fixPlan = "Inspect pathloss, geometry, beam selection, and serving-cell dominance for this UE/cell.";
    case "harq_failure_window"
        issueId = "harq_failure_window_" + string(idx);
        issueCategory = "link_reliability";
        blockName = "harq/link_adaptation";
        expectedPolicy = "HARQ failure rows should be backed by repeated runtime HARQ observations, not BLER aliases or single-sample noise.";
        fixPlan = "Inspect HARQ timeline, CQI lineage, measured SINR, retransmission budget, and grant MCS for this UE/cell.";
    case "low_sinr_window"
        issueId = "low_sinr_window_" + string(idx);
        issueCategory = "channel_interference";
        blockName = "channel/interference";
        expectedPolicy = "Measured SINR should align with channel/interference truth and scheduler link adaptation.";
        fixPlan = "Inspect channel model, interference contributors, CQI feedback, and grant MCS for this UE/cell.";
    case "controlled_snr_sweep_harq_outage_observed"
        issueId = "controlled_snr_sweep_harq_outage_observed_" + string(idx);
        issueCategory = "controlled_sweep_observation";
        blockName = "harq/link_adaptation";
        severity = "low";
        issueStatus = "informational";
        expectedPolicy = "Low-SNR sweep points may produce HARQ failures; the high-SNR objective point and raw per-point evidence remain mandatory.";
        fixPlan = "No remediation is required when the high-SNR objective and per-point evidence gates pass.";
end

row = localIssueRow(issueId, severity, issueStatus, issueCategory, ...
    direction, ueId, cellId, blockName, metricName, observedValue, expectedPolicy, ...
    evidenceRef, rootCauseHint, fixPlan);
end

function rows = localAppendMCSIssueRows(rows, sourceTable, direction, sourceArtifactRef)
if ~(istable(sourceTable) && ~isempty(sourceTable))
    return;
end
for i = 1:height(sourceTable)
    row = sourceTable(i, :);
    mcs = double(localTableValue(row, "MCSIndex", NaN));
    [cqiDerivedMCS, cqiBasis] = localGrantTimeCQIDerivedMCS(row, sourceArtifactRef);
    [allowedMCS, allowedBasis] = localOLLAAwareMCSBound(row, cqiDerivedMCS, cqiBasis);
    [mcsExceedsAllowed, mcsCompareDetail] = localMCSExceedsAllowedBound(row, mcs, allowedMCS);
    if isfinite(mcs) && isfinite(allowedMCS) && mcsExceedsAllowed && ~localMCSRowIsRetransmission(row)
        ue = double(localTableValue(row, "UEIndex", localTableValue(row, "UEID", localTableValue(row, "UE", localTableValue(row, "RNTI", NaN)))));
        cellID = double(localTableValue(row, "CellID", localTableValue(row, "ServingCell", localTableValue(row, "BaseStationID", NaN))));
        issueRow = localIssueRow( ...
            lower(string(direction)) + "_mcs_above_cqi_" + string(i), ...
            "high", "REVIEW_REQUIRED", "link_adaptation", ...
            string(direction), ue, cellID, "scheduler/link_adaptation", ...
            "MCSIndex", "MCS=" + string(mcs) + ";" + allowedBasis + "=" + string(allowedMCS) + ";" + mcsCompareDetail, ...
            "AMC new-data grants should not exceed the grant-time 38.214 CQI/MCS spectral-efficiency bound without explicit, sourced link-adaptation state", ...
            string(sourceArtifactRef), ...
            "Selected new-data MCS spectral efficiency is higher than sourced grant-time CQI/link-adaptation bound", ...
            "Verify fixed-vs-AMC config, CQI source lineage, and scheduler MCS selection for this row.");
        issueRow.frame = localFirstNumericTableValue(row, ["Frame", "SFN"], NaN);
        issueRow.slot = localFirstNumericTableValue(row, ["Slot"], NaN);
        issueRow.harq_id = localFirstNumericTableValue(row, ["HarqID", "HARQProcessId"], NaN);
        rows(end+1, 1) = issueRow; %#ok<AGROW>
    end
    receiverSinrFields = ["PostEqSINR_dB", "ReceiverHestSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"];
    sinr = NaN;
    sinrField = "";
    for k = 1:numel(receiverSinrFields)
        candidateSinr = localNumericTableValue(row, receiverSinrFields(k), NaN);
        if isfinite(candidateSinr)
            sinr = candidateSinr;
            sinrField = receiverSinrFields(k);
            break;
        end
    end
    crcPass = localAsBoolScalar(localTableValue(row, "CRCPass", localTableValue(row, "Ack", [])), false);
    backedLowSINRSuccess = false;
    if strcmpi(string(direction), "UL") && isfinite(sinr) && sinr < 0 && crcPass
        backedLowSINRSuccess = sixgr.truth.hasStrictULReceiverDecoderEvidence(row);
    end
    if strcmpi(string(direction), "UL") && isfinite(sinr) && sinr < 0 && crcPass && ~backedLowSINRSuccess
        ue = double(localTableValue(row, "UE", localTableValue(row, "UEID", localTableValue(row, "RNTI", NaN))));
        cellID = double(localTableValue(row, "CellID", localTableValue(row, "ServingCell", NaN)));
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "ul_low_sinr_crc_pass_" + string(i), "medium", "REVIEW_REQUIRED", "ul_receiver_semantics", ...
            "UL", ue, cellID, "PUSCH", "CRCPass", sinrField + "=" + string(sinr) + ";CRCPass=true", ...
            "Low-SINR UL successes must be backed by actual receiver/decoder evidence", ...
            string(sourceArtifactRef), ...
            "UL trial reports CRC pass at negative SINR", ...
            "Inspect channel-estimation, equalization, decoder evidence, and SINR definition before treating this as clean success.");
    end
end
end

function [allowedMCS, basis] = localOLLAAwareMCSBound(row, cqiDerivedMCS, cqiBasis)
allowedMCS = double(cqiDerivedMCS);
basis = string(cqiBasis);
if ~isfinite(allowedMCS)
    return;
end
if localUsesMeasuredFeedbackAdaptation(row)
    linkMCS = localFirstNumericTableValue(row, ["LinkAdaptationMCSIndex", "AdaptedMCSIndex"], NaN);
    if isfinite(linkMCS)
        allowedMCS = double(linkMCS);
        basis = "LinkAdaptationMCSIndex";
        return;
    end
    cqiBasedMCS = localNumericTableValue(row, "CQIBasedMCS", NaN);
    if isfinite(cqiBasedMCS)
        ollaAdjustedMCS = localNumericTableValue(row, "OLLAAdjustedMCSBeforeCQICeiling", NaN);
        staticDeltaMCS = localNumericTableValue(row, "StaticDeltaMCS", 0);
        if ~isfinite(staticDeltaMCS), staticDeltaMCS = 0; end
        if isfinite(ollaAdjustedMCS)
            allowedMCS = floor(double(ollaAdjustedMCS) + double(staticDeltaMCS));
            basis = "OLLARequiredSINRAdjustedMCS";
        else
            allowedMCS = floor(double(cqiBasedMCS) + double(staticDeltaMCS));
            basis = "CQIBasedMCSWithoutLegacyOLLADelta";
        end
        return;
    end
end
outerLoopApplied = localAsBoolScalar(localTableValue(row, "OuterLoopApplied", []), false);
ollaAdjustedMCS = localNumericTableValue(row, "OLLAAdjustedMCSBeforeCQICeiling", NaN);
status = lower(strtrim(string(localTableValue(row, "MCSValueStatus", ""))));
explicitFeedback = contains(status, "feedback_adapted") || contains(status, "olla");
if outerLoopApplied && explicitFeedback && isfinite(ollaAdjustedMCS)
    allowedMCS = min(double(allowedMCS), floor(double(ollaAdjustedMCS)));
    basis = basis + "WithOLLARequiredSINRAdjustedMCS";
end
end

function tf = localUsesMeasuredFeedbackAdaptation(row)
tokens = lower(strjoin([ ...
    string(localTableValue(row, "MCSValueStatus", "")), ...
    string(localTableValue(row, "MCSSelectionSource", "")), ...
    string(localTableValue(row, "MCSIndexAuthority", "")), ...
    string(localTableValue(row, "GrantOperatingPointSource", "")), ...
    string(localTableValue(row, "LinkAdaptationDecisionReason", ""))], " "));
tf = contains(tokens, "feedback_adapted") || ...
    contains(tokens, "measured_feedback_adapted") || ...
    contains(tokens, "runtime_link_adaptation_decision");
end

function [tf, detail] = localMCSExceedsAllowedBound(row, selectedMCS, allowedMCS)
tf = false;
detail = "MCSIndexCompare";
if ~(isfinite(selectedMCS) && isfinite(allowedMCS))
    return;
end
mcsTable = string(localTableValue(row, "MCSTable", localTableValue(row, "MCS_Table", "qam64_table1")));
selectedProfile = sixgr.link.resolveMCSProfile(char(mcsTable), selectedMCS);
allowedProfile = sixgr.link.resolveMCSProfile(char(mcsTable), allowedMCS);
if logical(sixgr.util.structGet(selectedProfile, "Valid", false)) && ...
        logical(sixgr.util.structGet(allowedProfile, "Valid", false))
    selectedSE = double(selectedProfile.SpectralEfficiency);
    allowedSE = double(allowedProfile.SpectralEfficiency);
    tf = selectedSE > allowedSE + 1e-9;
    detail = "SelectedSE=" + string(selectedSE) + ";AllowedSE=" + string(allowedSE);
else
    tf = double(selectedMCS) > double(allowedMCS) + 1;
    detail = "FallbackMCSIndexCompare";
end
end

function [cqiDerivedMCS, basis] = localGrantTimeCQIDerivedMCS(row, sourceArtifactRef)
cqiDerivedMCS = NaN;
basis = "GrantTimeCQIDerivedMCS";
sourceArtifactRef = lower(string(sourceArtifactRef));
hasGrantTimeCQI = localHasVar(row, "CQIUsed") && isfinite(localNumericTableValue(row, "CQIUsed", NaN));
if hasGrantTimeCQI
    cqiUsed = localNumericTableValue(row, "CQIUsed", NaN);
    mcsTable = string(localTableValue(row, "MCSTable", localTableValue(row, "MCS_Table", "qam64_table1")));
    cqiTable = string(localTableValue(row, "CQITable", localTableValue(row, "CQI_Table", "table1")));
    sanitizedCQI = sixgr.l2.mac.SchedulerBase.sanitizeCQI(cqiUsed, NaN);
    decision = sixgr.link.resolveMCSFromCQI(sanitizedCQI, char(mcsTable), char(cqiTable));
    if isstruct(decision) && isfield(decision, "Valid") && decision.Valid
        cqiDerivedMCS = double(decision.MCSIndex);
        basis = "CQIUsedDerivedMCS";
    end
    return;
end
if contains(sourceArtifactRef, "air_interface/csv")
    return;
end
cqiDerivedMCS = localNumericTableValue(row, "CQIDerivedMCS", NaN);
if isfinite(cqiDerivedMCS)
    basis = "CQIDerivedMCS";
end
end

function tf = localMCSRowIsRetransmission(row)
tf = localAsBoolScalar(localTableValue(row, "IsRetransmission", []), false);
if tf
    return;
end
reason = lower(string(localTableValue(row, "GrantReason", "")));
harqState = lower(string(localTableValue(row, "harq_state", "")));
txNumber = localFirstNumericTableValue(row, ["HARQTxNumber", "HarqTxNumber", "TxNumber"], NaN);
tf = contains(reason, "retx") || contains(reason, "retrans") || ...
    contains(harqState, "retrans") || (isfinite(txNumber) && txNumber > 1);
end

function row = localIssueRow(issueID, severity, issueStatus, issueCategory, direction, ueID, cellID, blockName, metricName, observedValue, expectedOrPolicy, evidenceArtifactRef, rootCauseHint, fixPlan)
row = struct( ...
    "issue_id", string(issueID), ...
    "severity", string(severity), ...
    "issue_status", string(issueStatus), ...
    "issue_category", string(issueCategory), ...
    "direction", string(direction), ...
    "ue_id", double(ueID), ...
    "cell_id", double(cellID), ...
    "block_name", string(blockName), ...
    "metric_name", string(metricName), ...
    "observed_value", string(observedValue), ...
    "expected_or_policy", string(expectedOrPolicy), ...
    "evidence_artifact_ref", string(evidenceArtifactRef), ...
    "root_cause_hint", string(rootCauseHint), ...
    "fix_plan", string(fixPlan), ...
    "frame", NaN, ...
    "slot", NaN, ...
    "harq_id", NaN, ...
    "analytics_visible_flag", true);
end

function T = localBuildCompareRunPrerequisitesTable(meta)
rows = struct( ...
    "output_name", ["compare_runs_kpi_delta_table"; "compare_run_overlay_plot"; "compare_run_harmonized_alignment"], ...
    "prerequisite_name", ["paired_baseline_and_candidate_runs"; "paired_baseline_and_candidate_runs"; "metric_harmonization_ready"], ...
    "status", ["PREREQUISITE_NOT_SATISFIED"; "PREREQUISITE_NOT_SATISFIED"; "PREREQUISITE_NOT_SATISFIED"], ...
    "required_condition", ["Need comparable run group with baseline + candidate"; "Need comparable run group with baseline + candidate"; "Need aligned metric schemas across comparable runs"], ...
    "observed_value", ["single_run_only"; "single_run_only"; "blocked_by_missing_comparable_group"], ...
    "next_action", ["Launch baseline/candidate pair and assign common compare group"; "Launch baseline/candidate pair and assign common compare group"; "Build comparable-run grouping then harmonize KPI keys"], ...
    "source", ["reports/csv/output_coverage_registry.csv"; "reports/csv/output_coverage_registry.csv"; "reports/csv/output_coverage_registry.csv"]);
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCompareRunPrerequisitesTable", ...
    "reports/csv/output_coverage_registry.csv", "partial", "runtime_prerequisite_not_satisfied", true, true);
end

function T = localBuildRuntimeMirrorTable(sourceTable, meta, producerModule, sourceArtifactRef, statusClassification, directionDefault)
if ~(istable(sourceTable) && ~isempty(sourceTable))
    T = table();
    return;
end
T = sourceTable;
scopeToken = localRuntimeMirrorScopeToken(sourceArtifactRef, directionDefault);
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scopeToken, T);
n = height(T);
T = localAddCanonicalRuntimeAliases(T, directionDefault);
T = localAddMissingVar(T, "runtime_evidence", repmat("persisted_runtime_trial_row", n, 1));
T = localAddMissingVar(T, "runtime_evidence_source", repmat(string(sourceArtifactRef), n, 1));
T = localAddMissingVar(T, "output_family_materialization", repmat("runtime_backed_mirror", n, 1));
T = localFinalizeOutputTable(T, meta, producerModule, sourceArtifactRef, ...
    "implemented", statusClassification, false, true);
end

function scopeToken = localRuntimeMirrorScopeToken(sourceArtifactRef, directionDefault)
sourceArtifactRef = string(sourceArtifactRef);
firstRef = strtrim(sourceArtifactRef);
pipeIdx = strfind(char(firstRef), "|");
if ~isempty(pipeIdx)
    firstRef = extractBefore(firstRef, pipeIdx(1));
end
[~, nameOnly, ~] = fileparts(char(firstRef));
scopeToken = lower(regexprep(string(nameOnly), "[^a-z0-9]+", "_"));
if strlength(strtrim(scopeToken)) == 0
    scopeToken = lower(regexprep(string(directionDefault), "[^a-z0-9]+", "_")) + "_runtime";
end
end

function T = localBuildCSIRSRuntimeOrSummaryTable(src, meta)
if istable(src.CSIRSTrials) && ~isempty(src.CSIRSTrials)
    T = localBuildRuntimeMirrorTable(src.CSIRSTrials, meta, ...
        "sixgr.link.runDLPDSCHThroughput", "air_interface/csv/csi_rs_trials.csv", ...
        "runtime_reference_signal_trial_rows", "DL");
    return;
end
if ~(istable(src.LiveCSIRSStats) && ~isempty(src.LiveCSIRSStats))
    T = table();
    return;
end
stats = src.LiveCSIRSStats;
n = height(stats);
rows = repmat(struct( ...
    "timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, "direction", "", ...
    "cell_id", NaN, "resource_id", NaN, "resource_set_id", NaN, "csirs_type", "", ...
    "num_ports", NaN, "row_number", NaN, "periodicity_slots", NaN, ...
    "trace_source", "", "mean_nmse_dB", NaN, "mean_wideband_cqi", NaN, ...
    "mean_csi_payload_bits", NaN, "notes", "", "source_artifact_ref", ""), n, 1);
for i = 1:n
    row = stats(i, :);
    rows(i).timestamp_sim_ms = NaN;
    rows(i).frame = NaN;
    rows(i).slot = NaN;
    rows(i).direction = string(localTableValue(row, "Direction", "DL"));
    rows(i).cell_id = NaN;
    rows(i).resource_id = NaN;
    rows(i).resource_set_id = NaN;
    rows(i).csirs_type = "aggregate_runtime_summary";
    rows(i).num_ports = NaN;
    rows(i).row_number = NaN;
    rows(i).periodicity_slots = NaN;
    rows(i).trace_source = string(localTableValue(row, "TraceSource", ""));
    rows(i).mean_nmse_dB = double(localTableValue(row, "MeanNMSE_dB", NaN));
    rows(i).mean_wideband_cqi = double(localTableValue(row, "MeanWidebandCQI", NaN));
    rows(i).mean_csi_payload_bits = double(localTableValue(row, "MeanCSIPayloadBitLength", NaN));
    rows(i).notes = string(localTableValue(row, "Notes", ""));
    rows(i).source_artifact_ref = "reports/csv/live_csirs_stats.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSLiveDerivedTables", ...
    "reports/csv/live_csirs_stats.csv", "implemented", "runtime_reference_signal_summary_rows", true, true);
end

function T = localBuildPUCCHRuntimeTable(src, meta)
if istable(src.PUCCHTrials) && ~isempty(src.PUCCHTrials)
    T = localBuildRuntimeMirrorTable(src.PUCCHTrials, meta, ...
        "sixgr.truth.exportControlPlaneTraces", "control/csv/pucch_trials.csv|air_interface/csv/pucch_trials.csv", ...
        "runtime_control_trial_rows", "UL");
    return;
end
if ~(istable(src.PUCCHGrants) && ~isempty(src.PUCCHGrants))
    T = table();
    return;
end
T = src.PUCCHGrants;
n = height(T);
T = localAddCanonicalRuntimeAliases(T, "UL");
T = localAddMissingVar(T, "runtime_evidence", repmat("persisted_runtime_pucch_grant_row", n, 1));
T = localAddMissingVar(T, "runtime_evidence_source", repmat("packet_flow/csv/live_pucch_grants.csv", n, 1));
T = localAddMissingVar(T, "output_family_materialization", repmat("runtime_grant_backed_mirror", n, 1));
T = localAddMissingVar(T, "RequestedFormat", repmat("scheduled_pending_execution", n, 1));
T = localAddMissingVar(T, "ResolvedFormat", repmat("scheduled_pending_execution", n, 1));
T = localAddMissingVar(T, "PUCCHResourceId", localMirrorTextColumn(T, ["PUCCHGrantId"], ""));
T = localAddMissingVar(T, "PUCCHPRBStart", localMirrorNumericColumn(T, ["PUCCHPRBStart"], NaN));
T = localAddMissingVar(T, "PUCCHPRBCount", localMirrorNumericColumn(T, ["PUCCHPRBCount"], NaN));
T = localAddMissingVar(T, "PUCCHSymbolStart", localMirrorNumericColumn(T, ["PUCCHSymbolStart"], NaN));
T = localAddMissingVar(T, "PUCCHNumSymbols", localMirrorNumericColumn(T, ["PUCCHNumSymbols"], NaN));
T = localAddMissingVar(T, "ControlResourceSource", repmat("runtime_pucch_grant_schedule", n, 1));
T = localAddMissingVar(T, "PUCCHDecodeOk", false(n, 1));
T = localAddMissingVar(T, "ControlObservationAvailable", false(n, 1));
T = localAddMissingVar(T, "NAReason", localMirrorTextColumn(T, ["NAReason"], "feedback_due_slot_not_reached_in_this_bounded_run"));
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportControlPlaneTraces", ...
    "packet_flow/csv/live_pucch_grants.csv", "implemented", "runtime_control_grant_rows", false, true);
end

function T = localAddCanonicalRuntimeAliases(T, directionDefault)
n = height(T);
direction = localMirrorTextColumn(T, ["Direction", "SignalDirection"], directionDefault);
frame = localMirrorNumericColumn(T, ["Frame"], NaN);
slot = localMirrorNumericColumn(T, ["Slot"], NaN);
cellId = localMirrorNumericColumn(T, ["CellID", "ServingCell"], NaN);
ueId = localMirrorNumericColumn(T, ["UEID", "UEIndex", "UE"], NaN);
rnti = localMirrorNumericColumn(T, ["RNTI"], NaN);
timestampMs = localMirrorNumericColumn(T, ["TimestampSim_ms", "Time_ms"], NaN);
if all(~isfinite(timestampMs))
    timestampMs = 1e3 * localMirrorNumericColumn(T, ["Time_s"], NaN);
end
if all(~isfinite(ueId)) && any(isfinite(rnti))
    ueId = rnti;
end
T = localAddMissingVar(T, "direction", direction);
T = localAddMissingVar(T, "frame", frame);
T = localAddMissingVar(T, "slot", slot);
T = localAddMissingVar(T, "cell_id", cellId);
T = localAddMissingVar(T, "ue_id", ueId);
T = localAddMissingVar(T, "rnti", rnti);
T = localAddMissingVar(T, "timestamp_sim_ms", timestampMs);
T = localAddMissingVar(T, "runtime_row_index", (1:n).');
end

function values = localMirrorTextColumn(T, varNames, defaultValue)
n = height(T);
values = repmat(string(defaultValue), n, 1);
for i = 1:numel(varNames)
    name = string(varNames(i));
    if localHasVar(T, name)
        values = string(T.(name));
        values = values(:);
        return;
    end
end
end

function values = localMirrorNumericColumn(T, varNames, defaultValue)
n = height(T);
values = repmat(double(defaultValue), n, 1);
for i = 1:numel(varNames)
    name = string(varNames(i));
    if ~localHasVar(T, name)
        continue;
    end
    raw = T.(name);
    try
        values = double(raw);
        values = values(:);
    catch
        values = str2double(string(raw(:)));
    end
    return;
end
end

function values = localMirrorLogicalColumn(T, varNames, defaultValue)
n = height(T);
values = repmat(logical(defaultValue), n, 1);
for i = 1:numel(varNames)
    name = string(varNames(i));
    if ~localHasVar(T, name)
        continue;
    end
    values = localColumnAsLogical(T, name);
    values = values(:);
    return;
end
end

function T = localBuildBeamPrecoderTable(src, meta)
rows = localEmptyBeamPrecoderRows(0);
rows = [rows; localBuildBeamPrecoderRowsFromTrials(src.DLTrials, "DL", "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildBeamPrecoderRowsFromTrials(src.ULTrials, "UL", "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamPrecoderTable", ...
    "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv", ...
    "implemented", "runtime_beam_precoder_trial_rows", false, true);
end

function rows = localBuildBeamPrecoderRowsFromTrials(trials, direction, sourceArtifactRef)
if ~(istable(trials) && ~isempty(trials))
    rows = localEmptyBeamPrecoderRows(0);
    return;
end
rows = localEmptyBeamPrecoderRows(height(trials));
for i = 1:height(trials)
    row = trials(i, :);
    timestampMs = localNumericTableValue(row, "TimestampSim_ms", NaN);
    if ~isfinite(timestampMs)
        timestampMs = 1e3 * localNumericTableValue(row, "Time_s", NaN);
    end
    rows(i).timestamp_sim_ms = timestampMs;
    rows(i).frame = localNumericTableValue(row, "Frame", NaN);
    rows(i).slot = localNumericTableValue(row, "Slot", NaN);
    rows(i).direction = string(direction);
    rows(i).ue_id = localFirstNumericTableValue(row, ["UEID", "UEIndex", "UE", "RNTI"], NaN);
    rows(i).rnti = localNumericTableValue(row, "RNTI", NaN);
    rows(i).cell_id = localFirstNumericTableValue(row, ["CellID", "ServingCell"], NaN);
    rows(i).configured_beam_selection_strategy = localTextTableValue(row, "ConfiguredBeamSelectionStrategy", "");
    rows(i).beam_selection_strategy = localTextTableValue(row, "BeamSelectionStrategy", "");
    rows(i).selected_beam_index = localNumericTableValue(row, "SelectedBeamIndex", NaN);
    rows(i).best_beam_index = localNumericTableValue(row, "BestBeamIndex", NaN);
    rows(i).beam_hit = localNumericTableValue(row, "BeamHit", NaN);
    rows(i).requested_beam_index_set = localTextTableValue(row, "RequestedBeamIndexSet", "");
    rows(i).requested_beam_truth_classification = localTextTableValue(row, "RequestedBeamTruthClassification", "");
    rows(i).precoder_source = localTextTableValue(row, "PrecoderSource", "");
    rows(i).applied_precoder_source = localTextTableValue(row, "AppliedPrecoderSource", "");
    rows(i).requested_precoder_pmi = localNumericTableValue(row, "RequestedPrecoderPMI", NaN);
    rows(i).requested_precoder_pmi_truth_classification = localTextTableValue(row, "RequestedPrecoderPMITruthClassification", "");
    rows(i).applied_precoder_pmi = localNumericTableValue(row, "AppliedPrecoderPMI", NaN);
    rows(i).applied_precoder_pmi_type = localTextTableValue(row, "AppliedPrecoderPMIType", "");
    rows(i).applied_precoder_codebook_mode = localTextTableValue(row, "AppliedPrecoderCodebookMode", "");
    rows(i).requested_vs_applied_precoder_pmi_match_status = localTextTableValue(row, "RequestedVsAppliedPrecoderPMIMatchStatus", "");
    rows(i).beamforming_applied = localLogicalTableValue(row, "BeamformingApplied", false);
    rows(i).applied_beam_index_set = localTextTableValue(row, "AppliedBeamIndexSet", "");
    rows(i).applied_beam_application_source = localTextTableValue(row, "AppliedBeamApplicationSource", "");
    rows(i).applied_beam_truth_classification = localTextTableValue(row, "AppliedBeamTruthClassification", "");
    rows(i).applied_precoder_pmi_application_source = localTextTableValue(row, "AppliedPrecoderPMIApplicationSource", "");
    rows(i).applied_precoder_pmi_truth_classification = localTextTableValue(row, "AppliedPrecoderPMITruthClassification", "");
    rows(i).precoding_mode = localTextTableValue(row, "PrecodingMode", "");
    rows(i).precoding_application_stage = localTextTableValue(row, "PrecodingApplicationStage", "");
    rows(i).precoding_active = localLogicalTableValue(row, "PrecodingActive", false);
    rows(i).explicit_beam_weights_applied = localLogicalTableValue(row, "ExplicitBeamWeightsApplied", false);
    rows(i).transform_precoding_applied = localLogicalTableValue(row, "TransformPrecodingApplied", false);
    rows(i).precoding_num_ports = localNumericTableValue(row, "PrecodingNumPorts", NaN);
    rows(i).precoding_num_layers = localNumericTableValue(row, "PrecodingNumLayers", NaN);
    rows(i).precoding_matrix_rows = localNumericTableValue(row, "PrecodingMatrixRows", NaN);
    rows(i).precoding_matrix_cols = localNumericTableValue(row, "PrecodingMatrixCols", NaN);
    rows(i).qcl_accuracy = localNumericTableValue(row, "QCLAccuracy", NaN);
    rows(i).qcl_type = localFirstStringTableValue(row, ["QCLType", "QCLTypes"], "");
    rows(i).qcl_source_rs = localTextTableValue(row, "QCLSourceRS", "");
    rows(i).qcl_status = localFirstStringTableValue(row, ["QCLStatus"], "");
    if strlength(strtrim(rows(i).qcl_status)) == 0
        rows(i).qcl_status = localTernary(isfinite(rows(i).qcl_accuracy), "runtime_qcl_accuracy_measured", "not_materialized_in_active_truth_path");
    end
    rows(i).tci_state_id = localFirstStringTableValue(row, ["TCIState", "TCIStateID"], "");
    rows(i).unified_tci_state_id = localTextTableValue(row, "UnifiedTCIStateID", "");
    rows(i).tci_validity_timer_slots = localNumericTableValue(row, "TCIValidityTimerSlots", NaN);
    rows(i).tci_status = localFirstStringTableValue(row, ["TCIStatus"], "");
    if strlength(strtrim(rows(i).tci_status)) == 0
        rows(i).tci_status = localTernary(strlength(strtrim(rows(i).tci_state_id)) > 0, "runtime_or_configured_tci_state_present", "not_materialized_in_active_truth_path");
    end
    rows(i).fraunhofer_boundary_m = localNumericTableValue(row, "FraunhoferBoundary_m", NaN);
    rows(i).near_field_focal_point_m = localFirstNumericTableValue(row, ["NearFieldFocalPoint_m", "FocalPoint_m"], NaN);
    rows(i).near_field_status = localFirstStringTableValue(row, ["NearFieldStatus"], "not_materialized_in_active_truth_path");
    rows(i).runtime_evidence = "persisted_air_interface_trial_row";
    rows(i).source_artifact_ref = string(sourceArtifactRef);
end
end

function rows = localEmptyBeamPrecoderRows(n)
n = max(0, round(double(n)));
rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, "direction", "", ...
    "ue_id", NaN, "rnti", NaN, "cell_id", NaN, ...
    "configured_beam_selection_strategy", "", "beam_selection_strategy", "", ...
    "selected_beam_index", NaN, "best_beam_index", NaN, "beam_hit", NaN, ...
    "requested_beam_index_set", "", "requested_beam_truth_classification", "", ...
    "precoder_source", "", "applied_precoder_source", "", "requested_precoder_pmi", NaN, ...
    "requested_precoder_pmi_truth_classification", "", "applied_precoder_pmi", NaN, ...
    "applied_precoder_pmi_type", "", "applied_precoder_codebook_mode", "", ...
    "requested_vs_applied_precoder_pmi_match_status", "", ...
    "beamforming_applied", false, "applied_beam_index_set", "", ...
    "applied_beam_application_source", "", "applied_beam_truth_classification", "", ...
    "applied_precoder_pmi_application_source", "", "applied_precoder_pmi_truth_classification", "", ...
    "precoding_mode", "", "precoding_application_stage", "", "precoding_active", false, ...
    "explicit_beam_weights_applied", false, "transform_precoding_applied", false, ...
    "precoding_num_ports", NaN, "precoding_num_layers", NaN, "precoding_matrix_rows", NaN, ...
    "precoding_matrix_cols", NaN, "qcl_accuracy", NaN, "qcl_type", "", "qcl_source_rs", "", ...
    "qcl_status", "", "tci_state_id", "", "unified_tci_state_id", "", "tci_validity_timer_slots", NaN, ...
    "tci_status", "", "fraunhofer_boundary_m", NaN, "near_field_focal_point_m", NaN, ...
    "near_field_status", "", "runtime_evidence", "", "source_artifact_ref", ""), n, 1);
end

function T = localBuildBeamformingAnalyticsTable(beamPrecoderTable, meta)
if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end
T = sixgr.truth.aggregateBeamPrecoderEvidence(beamPrecoderTable);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamformingAnalyticsTable", ...
    "beamforming/csv/beam_precoder_table.csv", "implemented", "derived_beamforming_analytics", true, true);
end

function T = localBuildMIMORankUtilizationTable(beamPrecoderTable, meta)
if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end
T = sixgr.truth.aggregateMIMORankUtilization(beamPrecoderTable);
if isempty(T)
    T = table();
    return;
end
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildMIMORankUtilizationTable", ...
    "beamforming/csv/beam_precoder_table.csv", "implemented", "derived_mimo_rank_utilization", true, true);
end

function T = localBuildRankLayerUsageHistogram(mimoRankTable, meta)
if ~(istable(mimoRankTable) && ~isempty(mimoRankTable))
    T = table();
    return;
end
T = mimoRankTable(:, intersect(["direction", "cell_id", "rank_or_layer_count", "trial_row_count", "utilization_fraction", "source_artifact_ref"], string(mimoRankTable.Properties.VariableNames), 'stable'));
T.histogram_definition = repmat("rank/layer usage histogram from runtime beam-precoder rows", height(T), 1);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRankLayerUsageHistogram", ...
    "beamforming/csv/mimo_rank_utilization_table.csv", "implemented", "derived_rank_layer_histogram", true, true);
end

function T = localBuildDopplerTimeVariationTable(src, meta)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, ...
    "speed_kmh", NaN, "doppler_hz", NaN, "doppler_value_role", "", ...
    "doppler_value_source", "", "source_artifact_ref", ""), 0, 1);
rows = [rows; localBuildDopplerRowsFromSystemInterference(src, meta)]; %#ok<AGROW>
rows = [rows; localBuildDopplerRowsFromMobilityState(src, meta)]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildDopplerTimeVariationTable", ...
    "system/csv/system_interference_detail.csv|system/csv/system_ue_summary.csv|reports/csv/live_mobility_state.csv", ...
    "implemented", "derived_doppler_time_variation", true, true);
end

function rows = localBuildDopplerRowsFromSystemInterference(src, meta)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, ...
    "speed_kmh", NaN, "doppler_hz", NaN, "doppler_value_role", "", ...
    "doppler_value_source", "", "source_artifact_ref", ""), 0, 1);
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    return;
end
for i = 1:height(src.SystemInterference)
    row = src.SystemInterference(i, :);
    ue = localNumericTableValue(row, "UE", NaN);
    speed = localLookupUEValue(src.SystemUE, ue, "Speed_kmh", NaN);
    doppler = localSpeedToDopplerHz(speed, meta.carrier_frequency_hz);
    if ~isfinite(doppler)
        continue;
    end
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "timestamp_sim_ms", 1e3 * localNumericTableValue(row, "Time_s", NaN), ...
        "ue_id", ue, ...
        "cell_id", localNumericTableValue(row, "ServingCell", NaN), ...
        "speed_kmh", speed, ...
        "doppler_hz", doppler, ...
        "doppler_value_role", "derived", ...
        "doppler_value_source", "system_ue_summary.Speed_kmh plus carrier frequency", ...
        "source_artifact_ref", "system/csv/system_interference_detail.csv|system/csv/system_ue_summary.csv");
end
end

function rows = localBuildDopplerRowsFromMobilityState(src, meta)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, ...
    "speed_kmh", NaN, "doppler_hz", NaN, "doppler_value_role", "", ...
    "doppler_value_source", "", "source_artifact_ref", ""), 0, 1);
if ~(istable(src.LiveMobilityState) && ~isempty(src.LiveMobilityState))
    return;
end
for i = 1:height(src.LiveMobilityState)
    row = src.LiveMobilityState(i, :);
    speed = localNumericTableValue(row, "Speed_kmh", NaN);
    doppler = localNumericTableValue(row, "DopplerHz", NaN);
    if ~isfinite(doppler)
        doppler = localSpeedToDopplerHz(speed, meta.carrier_frequency_hz);
    end
    if ~isfinite(doppler)
        continue;
    end
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "timestamp_sim_ms", 1e3 * localNumericTableValue(row, "Time_s", NaN), ...
        "ue_id", localNumericTableValue(row, "UEID", NaN), ...
        "cell_id", localNumericTableValue(row, "ServingCell", NaN), ...
        "speed_kmh", speed, ...
        "doppler_hz", doppler, ...
        "doppler_value_role", localTernary(isfinite(localNumericTableValue(row, "DopplerHz", NaN)), "observed_runtime_metadata", "derived"), ...
        "doppler_value_source", localTernary(isfinite(localNumericTableValue(row, "DopplerHz", NaN)), ...
            "reports/csv/live_mobility_state.csv:DopplerHz", ...
            "reports/csv/live_mobility_state.csv:Speed_kmh plus carrier frequency"), ...
        "source_artifact_ref", "reports/csv/live_mobility_state.csv");
end
end

function T = localBuildTimingSynchronizationTable(src, meta)
rows = localEmptyTimingSynchronizationRows(0);
rows = [rows; localBuildTimingSynchronizationRowsFromTrials(src.DLTrials, "DL", "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildTimingSynchronizationRowsFromTrials(src.ULTrials, "UL", "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildTimingSynchronizationTable", ...
    "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv", ...
    "implemented", "runtime_cfo_timing_trial_rows", false, true);
end

function rows = localBuildTimingSynchronizationRowsFromTrials(trials, direction, sourceArtifactRef)
if ~(istable(trials) && ~isempty(trials))
    rows = localEmptyTimingSynchronizationRows(0);
    return;
end
if ~any(ismember(["InjectedCFO_Hz", "EstimatedCFO_Hz", "CFOError_Hz", "TimingOffset_samples", ...
        "EstimatedTimingOffset_PreCorrection_samples", "TimingError_samples", "UseIdealTimingSync"], string(trials.Properties.VariableNames)))
    rows = localEmptyTimingSynchronizationRows(0);
    return;
end
rows = localEmptyTimingSynchronizationRows(height(trials));
for i = 1:height(trials)
    row = trials(i, :);
    timestampMs = localNumericTableValue(row, "TimestampSim_ms", NaN);
    if ~isfinite(timestampMs)
        timestampMs = 1e3 * localNumericTableValue(row, "Time_s", NaN);
    end
    estimatedCFO = localNumericTableValue(row, "EstimatedCFO_Hz", NaN);
    cfoError = localNumericTableValue(row, "CFOError_Hz", NaN);
    timingEstimateUsed = localLogicalTableValue(row, "TimingEstimateUsed", false);
    useIdealTimingSync = localLogicalTableValue(row, "UseIdealTimingSync", false);
    timingError = localNumericTableValue(row, "TimingError_samples", NaN);
    rows(i).timestamp_sim_ms = timestampMs;
    rows(i).frame = localNumericTableValue(row, "Frame", NaN);
    rows(i).slot = localNumericTableValue(row, "Slot", NaN);
    rows(i).direction = string(direction);
    rows(i).ue_id = localFirstNumericTableValue(row, ["UEID", "UEIndex", "UE", "RNTI"], NaN);
    rows(i).rnti = localNumericTableValue(row, "RNTI", NaN);
    rows(i).cell_id = localFirstNumericTableValue(row, ["CellID", "ServingCell"], NaN);
    rows(i).injected_cfo_hz = localNumericTableValue(row, "InjectedCFO_Hz", NaN);
    rows(i).estimated_cfo_pre_correction_hz = localNumericTableValue(row, "EstimatedCFO_PreCorrection_Hz", NaN);
    rows(i).residual_cfo_post_correction_hz = localNumericTableValue(row, "ResidualCFO_PostCorrection_Hz", NaN);
    rows(i).estimated_cfo_hz = estimatedCFO;
    rows(i).true_cfo_hz = localNumericTableValue(row, "TrueCFO_Hz", NaN);
    rows(i).cfo_error_hz = cfoError;
    rows(i).cfo_estimate_availability = localTextTableValue(row, "CFOEstimateAvailability", localCFOEstimateAvailability(estimatedCFO));
    rows(i).cfo_error_definition = localTextTableValue(row, "CFOErrorDefinition", localCFOErrorDefinition(estimatedCFO));
    rows(i).cfo_value_status = localTextTableValue(row, "CFOValueStatus", localValueStatus(cfoError, "NOT_AVAILABLE"));
    rows(i).injected_timing_offset_samples = localNumericTableValue(row, "InjectedTimingOffset_samples", NaN);
    rows(i).raw_timing_estimate_samples = localNumericTableValue(row, "RawTimingEstimate_samples", ...
        localNumericTableValue(row, "EstimatedTimingOffset_PreCorrection_samples", NaN));
    rows(i).applied_timing_correction_samples = localNumericTableValue(row, "AppliedTimingCorrection_samples", ...
        localNumericTableValue(row, "TimingOffset_samples", NaN));
    rows(i).estimated_timing_offset_pre_correction_samples = localNumericTableValue(row, "EstimatedTimingOffset_PreCorrection_samples", NaN);
    rows(i).residual_timing_error_post_correction_samples = localNumericTableValue(row, "ResidualTimingError_PostCorrection_samples", NaN);
    rows(i).true_timing_offset_samples = localNumericTableValue(row, "TrueTimingOffset_samples", NaN);
    rows(i).timing_error_samples = timingError;
    rows(i).timing_estimate_used = timingEstimateUsed;
    rows(i).use_ideal_timing_sync = useIdealTimingSync;
    rows(i).timing_estimate_application_policy = localTextTableValue(row, "TimingEstimateApplicationPolicy", "");
    rows(i).timing_estimate_status = localTextTableValue(row, "TimingEstimateStatus", ...
        localTimingEstimateStatus(timingEstimateUsed, useIdealTimingSync));
    rows(i).timing_estimate_was_clipped = localLogicalTableValue(row, "TimingEstimateWasClipped", false);
    rows(i).timing_estimate_availability = localTextTableValue(row, "TimingEstimateAvailability", ...
        localTimingEstimateAvailability(timingEstimateUsed, useIdealTimingSync));
    rows(i).timing_error_definition = localTextTableValue(row, "TimingErrorDefinition", ...
        localTimingErrorDefinition(timingEstimateUsed, useIdealTimingSync));
    rows(i).timing_value_status = localTextTableValue(row, "TimingValueStatus", ...
        localTimingValueStatus(timingError, useIdealTimingSync));
    rows(i).runtime_evidence = "persisted_air_interface_trial_row";
    rows(i).source_artifact_ref = string(sourceArtifactRef);
end
end

function rows = localEmptyTimingSynchronizationRows(n)
n = max(0, round(double(n)));
rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, "direction", "", ...
    "ue_id", NaN, "rnti", NaN, "cell_id", NaN, ...
    "injected_cfo_hz", NaN, "estimated_cfo_pre_correction_hz", NaN, ...
    "residual_cfo_post_correction_hz", NaN, "estimated_cfo_hz", NaN, ...
    "true_cfo_hz", NaN, "cfo_error_hz", NaN, "cfo_estimate_availability", "", ...
    "cfo_error_definition", "", "cfo_value_status", "", ...
    "injected_timing_offset_samples", NaN, "raw_timing_estimate_samples", NaN, "applied_timing_correction_samples", NaN, ...
    "estimated_timing_offset_pre_correction_samples", NaN, ...
    "residual_timing_error_post_correction_samples", NaN, "true_timing_offset_samples", NaN, ...
    "timing_error_samples", NaN, "timing_estimate_used", false, "use_ideal_timing_sync", false, ...
    "timing_estimate_application_policy", "", "timing_estimate_status", "", "timing_estimate_was_clipped", false, ...
    "timing_estimate_availability", "", "timing_error_definition", "", "timing_value_status", "", ...
    "runtime_evidence", "", "source_artifact_ref", ""), n, 1);
end

function val = localCFOEstimateAvailability(estimatedCFO)
if isfinite(double(estimatedCFO))
    val = "available";
else
    val = "missing";
end
end

function val = localCFOErrorDefinition(estimatedCFO)
if isfinite(double(estimatedCFO))
    val = "estimated_minus_true_runtime_cfo";
else
    val = "not_available_without_cfo_estimate";
end
end

function val = localTimingEstimateAvailability(timingEstimateUsed, useIdealTimingSync)
if logical(useIdealTimingSync)
    val = "not_applicable_ideal_timing_sync";
elseif logical(timingEstimateUsed)
    val = "available_receiver_timing_estimate";
else
    val = "missing";
end
end

function val = localTimingEstimateStatus(timingEstimateUsed, useIdealTimingSync)
if logical(useIdealTimingSync)
    val = "ideal_sync_bypass";
elseif logical(timingEstimateUsed)
    val = "available";
else
    val = "missing";
end
end

function val = localTimingErrorDefinition(timingEstimateUsed, useIdealTimingSync)
if logical(useIdealTimingSync)
    val = "not_applicable_ideal_timing_sync";
elseif logical(timingEstimateUsed)
    val = "true_minus_estimated_timing_offset_samples";
else
    val = "not_available_without_timing_estimate";
end
end

function val = localTimingValueStatus(timingError, useIdealTimingSync)
if logical(useIdealTimingSync)
    val = "NOT_APPLICABLE";
else
    val = localValueStatus(timingError, "NOT_AVAILABLE");
end
end

function val = localValueStatus(value, missingStatus)
if isfinite(double(value))
    val = "OK";
else
    val = string(missingStatus);
end
end

function localWriteTableArtifacts(runFolder, logicalPath, T)
csvPath = fullfile(runFolder, logicalPath);
csvTx = sixgr.runtime.RuntimeArtifactTransaction(runFolder, logicalPath, ...
    "ProducerStage", "post_link_table_export", ...
    "ProducerBlock", "exportLLSOutputCoverageArtifacts.localWriteTableArtifacts");
try
    sixgr.util.csvWriteTable(csvPath, T);
    csvValidationStatus = localValidateTableArtifact(csvPath, T);
    csvTx.commit(csvPath, csvValidationStatus);
catch ME
    csvTx.fail(ME);
    rethrow(ME);
end
jsonPath = replace(string(logicalPath), ".csv", ".json");
jsonEnabled = false;
[jsonRequired, jsonReason] = localJSONMirrorPolicy(logicalPath, T);
if jsonRequired && jsonPath ~= string(logicalPath)
    jsonTx = sixgr.runtime.RuntimeArtifactTransaction(runFolder, jsonPath, ...
        "ProducerStage", "post_link_table_export", ...
        "ProducerBlock", "exportLLSOutputCoverageArtifacts.localWriteTableArtifacts");
    try
        jsonAbsPath = fullfile(runFolder, jsonPath);
        sixgr.util.jsonWrite(jsonAbsPath, table2struct(T));
        jsonTx.commit(jsonAbsPath, "json_written");
    catch ME
        jsonTx.fail(ME);
        rethrow(ME);
    end
    jsonEnabled = true;
elseif ~jsonRequired
    localCoverageLog("json_sidecar_suppressed:" + string(logicalPath) + ":" + string(jsonReason), runFolder);
end
policyPath = replace(string(logicalPath), ".csv", ".json_policy.json");
if policyPath ~= string(logicalPath)
    policyTx = sixgr.runtime.RuntimeArtifactTransaction(runFolder, policyPath, ...
        "ProducerStage", "post_link_table_export", ...
        "ProducerBlock", "exportLLSOutputCoverageArtifacts.localWriteTableArtifacts");
    try
        policyAbsPath = fullfile(runFolder, policyPath);
        sixgr.util.jsonWrite(policyAbsPath, struct( ...
            "logical_path", char(string(logicalPath)), ...
            "json_required", logical(jsonRequired), ...
            "json_written", logical(jsonEnabled), ...
            "reason", char(string(localTernary(jsonRequired, "json_required", jsonReason)))));
        policyTx.commit(policyAbsPath, "json_policy_written");
    catch ME
        policyTx.fail(ME);
        rethrow(ME);
    end
end
end

function status = localValidateTableArtifact(csvPath, sourceTable)
if exist(csvPath, "file") ~= 2
    error("sixgr:truth:CoverageArtifactMissing", "Expected CSV artifact was not written: %s", char(string(csvPath)));
end
info = dir(csvPath);
if isempty(info) || info.bytes <= 0
    error("sixgr:truth:CoverageArtifactEmpty", "CSV artifact is empty: %s", char(string(csvPath)));
end
status = "file_exists_nonempty";
if height(sourceTable) <= 200000 && width(sourceTable) <= 256
    readback = readtable(csvPath, "VariableNamingRule", "preserve", ...
        "TextType", "string", "Delimiter", ",");
    if height(readback) ~= height(sourceTable)
        error("sixgr:truth:CoverageArtifactRowMismatch", ...
            "CSV readback row mismatch for %s: expected %d rows, read %d rows.", ...
            char(string(csvPath)), height(sourceTable), height(readback));
    end
    status = "csv_readback_row_count_match";
end
end

function T = localRunVisualArtifactAuditTool(runFolder)
auditCSV = fullfile(runFolder, "reports", "csv", "visual_artifact_audit.csv");
repoRoot = localFindRepoRoot(runFolder);
if strlength(repoRoot) == 0
    repoRoot = localRepoRootFromThisFile();
end
toolPath = fullfile(repoRoot, "tools", "audit_lls_visual_artifacts.py");
if exist(toolPath, "file") ~= 2
    T = localVisualArtifactAuditToolFailure("audit_tool_missing", ...
        "tools/audit_lls_visual_artifacts.py is missing.");
    sixgr.util.csvWriteTable(auditCSV, T);
    localWriteVisualArtifactAuditMarkdown(runFolder, T);
    return;
end
pythonExe = localResolvePythonExecutableForAudit();
cmd = sprintf("%s %s %s", localShellQuote(pythonExe), localShellQuote(toolPath), localShellQuote(runFolder));
[status, outTxt] = system(cmd);
T = localReadOptionalTable(auditCSV);
if istable(T)
    T = localNormalizeVisualArtifactAuditTable(T);
    sixgr.util.csvWriteTable(auditCSV, T);
end
if istable(T) && ~isempty(T)
    return;
end
if status == 0
    T = localVisualArtifactAuditToolFailure("audit_output_missing", ...
        "Visual audit tool exited successfully but did not write visual_artifact_audit.csv.");
else
    T = localVisualArtifactAuditToolFailure("audit_tool_failed_without_csv", ...
        "Visual audit tool failed before writing CSV: " + string(strtrim(outTxt)));
end
sixgr.util.csvWriteTable(auditCSV, T);
localWriteVisualArtifactAuditMarkdown(runFolder, T);
end

function T = localNormalizeVisualArtifactAuditTable(T)
required = ["plot_id","artifact_path","artifact_kind","is_manifest_row","manifest_status","visual_validity", ...
    "source_csv","x_column","y_column","plot_kind","row_count","unique_x_count","unique_y_count","non_nan_y_count", ...
    "nan_only_y","mixed_units","source_mapping_status","curve_construction","truth_status_tokens", ...
    "actual_mime_type","declared_mime_type","extension","sha256","byte_count","audit_ok","failure_code","failure_reason"];
if ~istable(T)
    T = localVisualArtifactAuditToolFailure("audit_table_invalid", "Visual audit tool did not return a table.");
    return;
end
aliases = struct( ...
    "plot_id", "PlotId", ...
    "artifact_path", "ArtifactPath", ...
    "audit_ok", "IntegrityOk", ...
    "failure_code", "FailureCode", ...
    "failure_reason", "FailureReason", ...
    "visual_validity", "VisualValidity", ...
    "manifest_status", "PlotRenderStatus", ...
    "actual_mime_type", "ActualMimeType", ...
    "declared_mime_type", "DeclaredMimeType", ...
    "extension", "Extension", ...
    "sha256", "SHA256", ...
    "byte_count", "ByteCount");
vars = string(T.Properties.VariableNames);
for i = 1:numel(required)
    name = required(i);
    if any(vars == name)
        continue;
    end
    alias = "";
    if isfield(aliases, char(name))
        alias = string(aliases.(char(name)));
    end
    if strlength(alias) > 0 && any(vars == alias)
        T.(name) = T.(alias);
    else
        T.(name) = localDefaultVisualAuditColumn(name, height(T));
    end
    vars = string(T.Properties.VariableNames);
end
if isempty(T)
    T = localVisualArtifactAuditToolSuccess("no_manifest_rows", ...
        "Visual audit completed with no manifest rows to audit.");
    return;
end
T = T(:, required);
end

function col = localDefaultVisualAuditColumn(name, n)
name = string(name);
if any(name == ["is_manifest_row","nan_only_y","mixed_units","audit_ok"])
    col = false(n, 1);
    if name == "audit_ok"
        col = true(n, 1);
    end
elseif any(name == ["row_count","unique_x_count","unique_y_count","non_nan_y_count","byte_count"])
    col = nan(n, 1);
else
    col = strings(n, 1);
end
end

function T = localVisualArtifactAuditToolSuccess(code, reason)
T = localVisualArtifactAuditToolFailure("", "");
T.audit_ok(:) = true;
T.failure_code(:) = string(code);
T.failure_reason(:) = string(reason);
end

function T = localMergeVisualArtifactAuditFailures(visualIntegrity, auditT)
T = visualIntegrity;
failureRows = localVisualIntegrityRowsFromAudit(auditT);
if ~(istable(failureRows) && ~isempty(failureRows))
    return;
end
if ~(istable(T) && ~isempty(T))
    T = failureRows;
    return;
end
missingInT = setdiff(string(failureRows.Properties.VariableNames), string(T.Properties.VariableNames), "stable");
for i = 1:numel(missingInT)
    T.(missingInT(i)) = strings(height(T), 1);
end
missingInFailures = setdiff(string(T.Properties.VariableNames), string(failureRows.Properties.VariableNames), "stable");
for i = 1:numel(missingInFailures)
    name = missingInFailures(i);
    sample = T.(name);
    if islogical(sample)
        failureRows.(name) = false(height(failureRows), 1);
    elseif isnumeric(sample)
        failureRows.(name) = nan(height(failureRows), 1);
    else
        failureRows.(name) = strings(height(failureRows), 1);
    end
end
failureRows = failureRows(:, string(T.Properties.VariableNames));
T = [T; failureRows];
end

function T = localVisualIntegrityRowsFromAudit(auditT)
T = table();
if ~(istable(auditT) && ~isempty(auditT))
    return;
end
vars = string(auditT.Properties.VariableNames);
if ~ismember("audit_ok", vars)
    return;
end
ok = localAuditColumnAsLogical(auditT, "audit_ok", true);
bad = auditT(~ok, :);
if isempty(bad)
    return;
end
n = height(bad);
T = table( ...
    localColumnAsString(bad, "plot_id", n), ...
    localColumnAsString(bad, "artifact_path", n), ...
    true(n, 1), ...
    localColumnAsString(bad, "manifest_status", n), ...
    localColumnAsString(bad, "visual_validity", n), ...
    false(n, 1), ...
    localColumnAsString(bad, "declared_mime_type", n), ...
    localColumnAsString(bad, "actual_mime_type", n), ...
    localColumnAsString(bad, "extension", n), ...
    localColumnAsString(bad, "sha256", n), ...
    localAuditColumnAsDouble(bad, "byte_count", n), ...
    false(n, 1), ...
    localColumnAsString(bad, "failure_code", n), ...
    localColumnAsString(bad, "failure_reason", n), ...
    'VariableNames', ["PlotId","ArtifactPath","IsManifestRow","PlotRenderStatus","VisualValidity","IsUnavailableCard", ...
    "DeclaredMimeType","ActualMimeType","Extension","SHA256","ByteCount","IntegrityOk","FailureCode","FailureReason"]);
end

function T = localVisualArtifactAuditToolFailure(code, reason)
T = table( ...
    "visual_artifact_audit", "", "audit_tool", false, "", "", "", "", "", "", "", "", "", "", false, false, "", "", "", "", "", "", "", 0, false, string(code), string(reason), ...
    'VariableNames', ["plot_id","artifact_path","artifact_kind","is_manifest_row","manifest_status","visual_validity", ...
    "source_csv","x_column","y_column","plot_kind","row_count","unique_x_count","unique_y_count","non_nan_y_count", ...
    "nan_only_y","mixed_units","source_mapping_status","curve_construction","truth_status_tokens", ...
    "actual_mime_type","declared_mime_type","extension","sha256","byte_count","audit_ok","failure_code","failure_reason"]);
end

function repoRoot = localRepoRootFromThisFile()
repoRoot = string(sixgr.utils.getRepoRoot());
if exist(fullfile(repoRoot, ".git"), "dir") ~= 7 && exist(fullfile(repoRoot, "tools", "audit_lls_visual_artifacts.py"), "file") ~= 2
    repoRoot = "";
end
end

function localWriteVisualArtifactAuditMarkdown(runFolder, auditT)
mdPath = fullfile(runFolder, "reports", "visual_artifact_audit.md");
sixgr.util.ensureFolder(fileparts(mdPath));
fid = fopen(mdPath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Visual Artifact Audit\n\n");
fprintf(fid, "- Run folder: `%s`\n", char(string(runFolder)));
if istable(auditT)
    fprintf(fid, "- Audited rows: %d\n", height(auditT));
    ok = localAuditColumnAsLogical(auditT, "audit_ok", true);
    fprintf(fid, "- Strict failures: %d\n\n", sum(~ok));
    if any(~ok)
        bad = auditT(~ok, :);
        fprintf(fid, "| Plot | Artifact | Failure | Reason |\n");
        fprintf(fid, "|---|---|---|---|\n");
        for i = 1:height(bad)
            fprintf(fid, "| %s | %s | %s | %s |\n", ...
                char(localMarkdownEscape(localColumnAsString(bad(i, :), "plot_id", 1))), ...
                char(localMarkdownEscape(localColumnAsString(bad(i, :), "artifact_path", 1))), ...
                char(localMarkdownEscape(localColumnAsString(bad(i, :), "failure_code", 1))), ...
                char(localMarkdownEscape(localColumnAsString(bad(i, :), "failure_reason", 1))));
        end
    end
end
end

function exe = localResolvePythonExecutableForAudit()
exe = "python";
try
    runtime = sixgr.lls6g.config.ensureYAMLRuntime("RequireYAML", false, "ConfigurePyEnv", false);
    candidate = string(sixgr.util.structGet(runtime, "PythonExecutable", ""));
    if strlength(strtrim(candidate)) > 0
        exe = candidate;
    end
catch
end
end

function out = localShellQuote(value)
value = char(string(value));
out = '"' + string(strrep(value, '"', '\"')) + '"';
end

function values = localColumnAsString(T, name, n)
if nargin < 3
    n = height(T);
end
name = string(name);
if istable(T) && ismember(name, string(T.Properties.VariableNames))
    values = string(T.(name));
else
    values = strings(n, 1);
end
values = values(:);
if numel(values) < n
    values(end + 1:n, 1) = "";
elseif numel(values) > n
    values = values(1:n);
end
end

function values = localAuditColumnAsDouble(T, name, n)
if nargin < 3
    n = height(T);
end
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(string(name));
    try
        values = double(raw);
    catch
        values = str2double(string(raw));
    end
else
    values = nan(n, 1);
end
values = values(:);
if numel(values) < n
    values(end + 1:n, 1) = NaN;
elseif numel(values) > n
    values = values(1:n);
end
end

function values = localAuditColumnAsLogical(T, name, defaultValue)
n = height(T);
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(string(name));
    if islogical(raw)
        values = raw(:);
    elseif isnumeric(raw)
        values = raw(:) ~= 0;
    else
        txt = lower(strtrim(string(raw(:))));
        values = ismember(txt, ["1","true","yes","y"]);
    end
else
    values = repmat(logical(defaultValue), n, 1);
end
if numel(values) < n
    values(end + 1:n, 1) = logical(defaultValue);
elseif numel(values) > n
    values = values(1:n);
end
end

function value = localMarkdownEscape(value)
value = replace(string(value), "|", "\|");
value = replace(value, newline, " ");
end

function [jsonRequired, reason] = localJSONMirrorPolicy(logicalPath, T)
jsonRequired = true;
reason = "";
logicalPath = string(logicalPath);
if strlength(logicalPath) == 0 || ~(istable(T) && ~isempty(T))
    return;
end
rowCount = double(height(T));
columnCount = double(width(T));
cellCount = rowCount * max(columnCount, 1);
highCardinalityPaths = [ ...
    "packet_flow/csv/live_prb_allocation.csv", ...
    "packet_flow/csv/table_scheduler_decision.csv", ...
    "reports/csv/prb_allocation_heatmap.csv", ...
    "reports/csv/live_re_allocation_snapshot.csv", ...
    "reports/csv/dl_resource_grid_heatmap.csv", ...
    "reports/csv/ul_resource_grid_heatmap.csv", ...
    "reports/csv/table_mcs_tbs_evolution.csv", ...
    "reports/csv/live_power_runtime_table.csv", ...
    "reports/csv/live_rf_power_table.csv", ...
    "control/csv/timing_synchronization_table.csv"];
if any(logicalPath == highCardinalityPaths)
    jsonRequired = false;
    reason = "json_sidecar_suppressed_due_scale_guard_high_cardinality_runtime_table";
    return;
end
if rowCount >= 2.0e5 || cellCount >= 5.0e6
    jsonRequired = false;
    reason = "json_sidecar_suppressed_due_scale_guard_size_threshold";
end
end

function T = localBuildTableSummaries(tables, logicalPaths, runFolder)
names = fieldnames(tables);
rows = repmat(struct( ...
    "table_name", "", ...
    "logical_path", "", ...
    "row_count", NaN, ...
    "column_count", NaN, ...
    "json_required", false, ...
    "json_policy_reason", "", ...
    "csv_persisted_flag", false, ...
    "json_persisted_flag", false), numel(names), 1);
for i = 1:numel(names)
    name = string(names{i});
    logicalPath = localRegistryLogicalPath(name, logicalPaths);
    Tref = tables.(char(name));
    [jsonRequired, jsonReason] = localJSONMirrorPolicy(logicalPath, Tref);
    rows(i).table_name = name;
    rows(i).logical_path = logicalPath;
    rows(i).row_count = double(localTernary(istable(Tref), height(Tref), NaN));
    rows(i).column_count = double(localTernary(istable(Tref), width(Tref), NaN));
    rows(i).json_required = logical(jsonRequired);
    rows(i).json_policy_reason = string(jsonReason);
    rows(i).csv_persisted_flag = logicalPath ~= "" && exist(fullfile(runFolder, logicalPath), "file") == 2;
    rows(i).json_persisted_flag = logicalPath ~= "" && exist(fullfile(runFolder, replace(logicalPath, ".csv", ".json")), "file") == 2;
end
T = struct2table(rows);
end

function localCoverageLog(stepName, runFolder)
msg = "exportLLSOutputCoverageArtifacts:" + string(stepName) + " runFolder=" + string(runFolder);
eventType = "HEARTBEAT";
status = "progress";
if strcmpi(string(stepName), "start")
    eventType = "STAGE_START";
    status = "started";
elseif strcmpi(string(stepName), "done")
    eventType = "STAGE_END";
    status = "completed";
end
sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent(runFolder, eventType, ...
    "StageName", "exportLLSOutputCoverageArtifacts." + string(stepName), ...
    "FunctionName", "sixgr.truth.exportLLSOutputCoverageArtifacts", ...
    "SourceFile", mfilename("fullpath"), ...
    "Status", status, ...
    "Message", msg, ...
    "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
if sixgr.db.isArtifactStoreActive()
    sixgr.db.appendLogLine("INFO", sixgr.util.utcNowISO8601(), string(msg));
else
    fprintf("%s\n", char(msg));
end
end

function localWritePRBHeatmapFigure(T, filePath, logicalPath)
if ~(istable(T) && ~isempty(T))
    return;
end
slotVals = unique(double(T.slot));
rbVals = unique(double(T.rb_index));
slotVals = sort(slotVals(:));
rbVals = sort(rbVals(:));
M = zeros(numel(rbVals), numel(slotVals));
for i = 1:height(T)
    r = find(rbVals == double(T.rb_index(i)), 1, "first");
    c = find(slotVals == double(T.slot(i)), 1, "first");
    if isempty(r) || isempty(c)
        continue;
    end
    M(r, c) = M(r, c) + double(T.occupancy_count(i));
end
fig = figure("Visible", "off", "Color", "w");
imagesc(slotVals, rbVals, M);
axis xy;
xlabel("Slot");
ylabel("RB Index");
title("PRB Allocation Heatmap");
colorbar;
cleanupFig = onCleanup(@() close(fig)); %#ok<NASGU>
sixgr.util.exportFigureArtifact(fig, filePath, "Resolution", 160, "LogicalPath", logicalPath);
end

function localWritePowerEnergyFigure(T, filePath, logicalPath)
if ~(istable(T) && ~isempty(T))
    return;
end
entityTypeAll = string(localColumnAsText(T, "entity_type"));
mask = entityTypeAll == "cell" | entityTypeAll == "site";
if any(mask)
    T = T(mask, :);
end
entityType = string(localColumnAsText(T, "entity_type"));
entityID = localColumnAsDouble(T, "entity_id");
validKeyRows = ~ismissing(entityType) & strlength(entityType) > 0 & isfinite(entityID);
if ~any(validKeyRows)
    return;
end
T = T(validKeyRows, :);
fig = figure("Visible", "off", "Color", "w");
hold on;
entityType = string(localColumnAsText(T, "entity_type"));
entityID = localColumnAsDouble(T, "entity_id");
keys = unique(entityType + ":" + string(entityID));
for i = 1:numel(keys)
    key = keys(i);
    mask = (entityType + ":" + string(entityID)) == key;
    xAll = localColumnAsDouble(T, "timestamp_sim_ms");
    yAll = localColumnAsDouble(T, "cumulative_energy_J");
    x = double(xAll(mask));
    y = double(yAll(mask));
    keep = isfinite(x) & isfinite(y);
    if ~any(keep)
        continue;
    end
    plot(x(keep), y(keep), "LineWidth", 1.5, "DisplayName", char(key));
end
hold off;
grid on;
xlabel("Timestamp (ms)");
ylabel("Cumulative Energy (J)");
title("Cumulative Energy");
legend("Location", "best");
cleanupFig = onCleanup(@() close(fig)); %#ok<NASGU>
sixgr.util.exportFigureArtifact(fig, filePath, "Resolution", 160, "LogicalPath", logicalPath);
end

function [registry, unavailable] = localBuildCoverageRegistry(runFolder, meta, src, tables, logicalPaths, heatmapImagePath, energyImagePath)
specs = localRequestedOutputSpecs();
rows = repmat(struct("output_name", "", "ui_section", "", "block_module", "", "required_flag", false, ...
    "classification_code", "", "current_status", "", "status_code", "", "fix_now_flag", "no", ...
    "backend_source_exists_flag", false, "persisted_flag", false, "api_exposed_flag", false, ...
    "ui_rendered_flag", false, "export_supported_flag", false, "compare_run_supported_flag", false, ...
    "blocker_reason", "", "target_phase", ""), numel(specs), 1);
uRows = repmat(struct("output_name", "", "classification_code", "", "unavailable_reason", "", ...
    "required_backend_sources", "", "required_capture_point", "", "required_runtime_condition", "", ...
    "next_implementation_step", "", "owner_tag", ""), 0, 1);
for i = 1:numel(specs)
    spec = specs(i);
    [status, classCode, persistedFlag, exportSupported, apiExposedFlag, uiRenderedFlag, blocker] = localResolveSpecStatus(spec, runFolder, tables, logicalPaths, heatmapImagePath, energyImagePath);
    rows(i).output_name = string(spec.output_name);
    rows(i).ui_section = string(spec.ui_section);
    rows(i).block_module = string(spec.block_module);
    rows(i).required_flag = logical(spec.required_flag);
    rows(i).classification_code = string(classCode);
    rows(i).current_status = string(status);
    rows(i).status_code = string(status);
    rows(i).fix_now_flag = string(spec.fix_now_flag);
    rows(i).backend_source_exists_flag = logical(spec.backend_source_exists_flag);
    rows(i).persisted_flag = logical(persistedFlag);
    rows(i).api_exposed_flag = logical(apiExposedFlag);
    rows(i).ui_rendered_flag = logical(uiRenderedFlag);
    rows(i).export_supported_flag = logical(exportSupported);
    rows(i).compare_run_supported_flag = logical(spec.compare_run_supported_flag) && status == "implemented";
    rows(i).blocker_reason = string(blocker);
    rows(i).target_phase = string(spec.target_phase);
    if status ~= "implemented" && localShouldRecordUnavailableRow(spec, status, blocker)
        uRows(end+1, 1) = struct( ... %#ok<AGROW>
            "output_name", string(spec.output_name), ...
            "classification_code", string(classCode), ...
            "unavailable_reason", string(blocker), ...
            "required_backend_sources", string(strjoin(string(spec.required_backend_sources), "|")), ...
            "required_capture_point", string(spec.required_capture_point), ...
            "required_runtime_condition", string(spec.required_runtime_condition), ...
            "next_implementation_step", string(spec.next_implementation_step), ...
            "owner_tag", string(spec.owner_tag));
    end
end
registry = struct2table(rows);
registry = localFinalizeOutputTable(registry, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCoverageRegistry", ...
    "reports/csv/output_coverage_registry.csv", "implemented", "meta_audit", true, true);
unavailable = struct2table(uRows);
if ~isempty(unavailable)
    unavailable = localFinalizeOutputTable(unavailable, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCoverageRegistry", ...
        "reports/csv/honest_unavailable_registry.csv", "implemented", "honest_unavailable_meta", true, true);
end
end

function T = localBuildOutputCompletenessTable(runFolder, registry, tables, logicalPaths, meta)
rows = repmat(struct("output_name", "", "run_id", NaN, "expected_row_count", NaN, "actual_row_count", NaN, ...
    "expected_artifact_count", NaN, "actual_artifact_count", NaN, "completeness_percent", NaN, ...
    "missing_columns", "", "missing_plots", "", "missing_exports", "", "warning_flag", false, ...
    "direct_artifact_status", "", "direct_artifact_rows", NaN, "direct_artifact_columns", NaN, ...
    "direct_artifact_required_columns_present", false, "alternative_evidence_status", "", ...
    "alternative_evidence_artifact", "", "evidence_substitution_allowed", false, ...
    "evidence_substitution_reason", "", "implementation_status", "", "completeness_status", "", ...
    "runtime_evidence_status", "", "plot_render_status", ""), height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    logicalPath = localRegistryLogicalPath(outName, logicalPaths);
    Tref = localRegistryTable(outName, tables);
    actualRows = localArtifactRowCount(runFolder, logicalPath, Tref);
    expectedRows = localExpectedRowCount(outName, Tref, registry.current_status(i));
    directCols = double(localTernary(istable(Tref), width(Tref), 0));
    [jsonRequired, ~] = localJSONMirrorPolicy(logicalPath, Tref);
    jsonPath = replace(logicalPath, ".csv", ".json");
    jsonPresent = logicalPath ~= "" && exist(fullfile(runFolder, jsonPath), "file") == 2;
    altPaths = localAlternativeEvidencePaths(outName);
    altPresent = strings(0, 1);
    for p = 1:numel(altPaths)
        if localArtifactExists(runFolder, altPaths(p))
            altPresent(end + 1, 1) = string(altPaths(p)); %#ok<AGROW>
        end
    end
    plotMissing = "";
    if outName == "prb_allocation_heatmap"
        plotMissing = string(localTernary(exist(fullfile(runFolder, "reports", "image", "prb_allocation_heatmap.png"), "file") ~= 2, "reports/image/prb_allocation_heatmap.png", ""));
    elseif outName == "power_energy_table"
        plotMissing = string(localTernary(exist(fullfile(runFolder, "reports", "image", "power_energy_cumulative.png"), "file") ~= 2, "reports/image/power_energy_cumulative.png", ""));
    end
    actualArtifacts = double(actualRows > 0);
    if logical(actualRows > 0) && (logical(jsonRequired) && logical(jsonPresent) || ~logical(jsonRequired))
        actualArtifacts = actualArtifacts + 1;
    end
    if plotMissing == ""
        actualArtifacts = actualArtifacts + 1;
    end
    expectedArtifacts = 0;
    if logical(actualRows > 0)
        expectedArtifacts = 1 + double(logical(jsonRequired)) + 1;
    end
    rows(i).output_name = outName;
    rows(i).run_id = meta.run_id;
    rows(i).expected_row_count = expectedRows;
    rows(i).actual_row_count = actualRows;
    rows(i).expected_artifact_count = expectedArtifacts;
    rows(i).actual_artifact_count = actualArtifacts;
    rows(i).completeness_percent = localCompleteness(expectedRows, actualRows, expectedArtifacts, actualArtifacts, registry.current_status(i));
    rows(i).missing_columns = "";
    rows(i).missing_plots = plotMissing;
    rows(i).missing_exports = string(localTernary(actualRows > 0 && logicalPath ~= "" && logical(jsonRequired) && ~logical(jsonPresent), jsonPath, ""));
    rows(i).warning_flag = registry.current_status(i) ~= "implemented";
    rows(i).direct_artifact_status = localTernary(logicalPath == "", "not_declared", localTernary(actualRows > 0, "present", localTernary(localArtifactExists(runFolder, logicalPath), "present_zero_rows", "missing")));
    rows(i).direct_artifact_rows = actualRows;
    rows(i).direct_artifact_columns = directCols;
    rows(i).direct_artifact_required_columns_present = actualRows > 0 || registry.current_status(i) ~= "implemented";
    rows(i).alternative_evidence_status = localTernary(isempty(altPaths), "none_registered", localTernary(~isempty(altPresent), "present", "missing"));
    rows(i).alternative_evidence_artifact = strjoin(string(altPresent), "|");
    rows(i).evidence_substitution_allowed = ~isempty(altPaths);
    rows(i).evidence_substitution_reason = localTernary(~isempty(altPaths), "alternative_evidence_contract_registered", "");
    rows(i).implementation_status = string(registry.current_status(i));
    rows(i).completeness_status = localCompletenessStatus(registry.current_status(i), expectedRows, actualRows);
    rows(i).runtime_evidence_status = localTernary(actualRows > 0, "runtime_rows_present", localTernary(~isempty(altPresent), "alternative_evidence_only", "runtime_rows_missing"));
    rows(i).plot_render_status = localTernary(plotMissing == "", "not_applicable_or_rendered", "missing_required_plot");
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildOutputCompletenessTable", ...
    "reports/csv/output_completeness_table.csv", "implemented", "meta_audit", true, true);
end

function T = localBuildImplementationRegister(registry, completeness, apiAudit, persistence, unavailable, meta, logicalPaths)
rows = repmat(struct("output_name", "", "feature_family", "", "block_module", "", "required_flag", false, ...
    "implementation_status", "", "evidence_status", "", "conformance_claim_allowed", false, ...
    "runtime_row_count", NaN, "direct_artifact_status", "", "persisted_flag", false, ...
    "api_exposed_flag", false, "export_supported_flag", false, "ui_rendered_flag", false, ...
    "writer_enabled", false, "json_required", false, "json_enabled", false, ...
    "blocker_reason", "", "unavailable_reason", "", "required_backend_sources", "", ...
    "required_capture_point", "", "required_runtime_condition", "", "next_implementation_step", "", ...
    "owner_tag", "", "source_artifact_ref", "", "audit_source", ""), height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    cRow = localSingleMatchingRow(completeness, "output_name", outName);
    aRow = localSingleMatchingRow(apiAudit, "output_name", outName);
    pRow = localSingleMatchingRow(persistence, "output_name", outName);
    uRow = localSingleMatchingRow(unavailable, "output_name", outName);

    implementationStatus = string(registry.current_status(i));
    runtimeRows = double(localTableValue(cRow, "actual_row_count", NaN));
    persistedFlag = localLogicalTableValue(registry(i, :), "persisted_flag", false);
    apiFlag = localLogicalTableValue(registry(i, :), "api_exposed_flag", false);
    exportFlag = localLogicalTableValue(registry(i, :), "export_supported_flag", false);
    uiFlag = localLogicalTableValue(registry(i, :), "ui_rendered_flag", false);
    blocker = string(localTableValue(registry(i, :), "blocker_reason", ""));
    unavailableReason = string(localTableValue(uRow, "unavailable_reason", ""));
    if strlength(blocker) == 0
        blocker = unavailableReason;
    end

    conformanceAllowed = implementationStatus == "implemented" && ...
        persistedFlag && apiFlag && exportFlag && uiFlag && ...
        (isfinite(runtimeRows) && runtimeRows > 0 || localIsMetaRegisterOutput(outName));
    evidenceStatus = localImplementationEvidenceStatus(implementationStatus, runtimeRows, ...
        persistedFlag, apiFlag, exportFlag, uiFlag, blocker);

    rows(i).output_name = outName;
    rows(i).feature_family = string(registry.ui_section(i));
    rows(i).block_module = string(registry.block_module(i));
    rows(i).required_flag = localLogicalTableValue(registry(i, :), "required_flag", false);
    rows(i).implementation_status = implementationStatus;
    rows(i).evidence_status = evidenceStatus;
    rows(i).conformance_claim_allowed = logical(conformanceAllowed);
    rows(i).runtime_row_count = runtimeRows;
    rows(i).direct_artifact_status = string(localTableValue(cRow, "direct_artifact_status", ""));
    rows(i).persisted_flag = persistedFlag;
    rows(i).api_exposed_flag = apiFlag;
    rows(i).export_supported_flag = exportFlag;
    rows(i).ui_rendered_flag = uiFlag;
    rows(i).writer_enabled = localLogicalTableValue(pRow, "writer_enabled", persistedFlag);
    rows(i).json_required = localLogicalTableValue(pRow, "json_required", false);
    rows(i).json_enabled = localLogicalTableValue(pRow, "json_enabled", false);
    rows(i).blocker_reason = blocker;
    rows(i).unavailable_reason = unavailableReason;
    rows(i).required_backend_sources = string(localFirstNonBlankString( ...
        localTableValue(uRow, "required_backend_sources", ""), localRequiredSourcesForOutput(outName)));
    rows(i).required_capture_point = string(localFirstNonBlankString( ...
        localTableValue(uRow, "required_capture_point", ""), localRequiredCapturePoint(outName)));
    rows(i).required_runtime_condition = string(localRequiredRuntimeCondition(outName));
    rows(i).next_implementation_step = string(localFirstNonBlankString( ...
        localTableValue(uRow, "next_implementation_step", ""), localNextImplementationStep(outName)));
    rows(i).owner_tag = string(localFirstNonBlankString( ...
        localTableValue(uRow, "owner_tag", ""), localOwnerTag(outName)));
    rows(i).source_artifact_ref = string(localFirstNonBlankString( ...
        localTableValue(cRow, "alternative_evidence_artifact", ""), ...
        localTableValue(aRow, "api_route", ""), ...
        localRegistryLogicalPath(outName, logicalPaths)));
    rows(i).audit_source = "output_coverage_registry|output_completeness_table|api_exposure_audit_table|persistence_audit_table|honest_unavailable_registry";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildImplementationRegister", ...
    "reports/csv/lls_implementation_register.csv", "implemented", "machine_readable_implementation_audit", true, true);
end

function row = localSingleMatchingRow(T, keyName, keyValue)
row = table();
if ~(istable(T) && ~isempty(T) && localHasVar(T, keyName))
    return;
end
values = string(T.(keyName));
idx = find(values == string(keyValue), 1, "first");
if ~isempty(idx)
    row = T(idx, :);
end
end

function out = localFirstNonBlankString(varargin)
out = "";
for i = 1:nargin
    candidate = string(varargin{i});
    if isempty(candidate)
        continue;
    end
    candidate = strtrim(candidate(1));
    if strlength(candidate) > 0 && lower(candidate) ~= "nan" && lower(candidate) ~= "<missing>"
        out = candidate;
        return;
    end
end
end

function tf = localIsMetaRegisterOutput(outName)
tf = any(string(outName) == ["output_coverage_registry", "lls_implementation_register", ...
    "output_completeness_table", "instrumentation_coverage_table", "api_exposure_audit_table", ...
    "persistence_audit_table", "honest_unavailable_registry", "lls_output_contract", ...
    "metric_definition_catalog", "metric_unit_role_catalog", "plot_manifest", ...
    "visual_artifact_audit", "plot_render_status", "chart_source_registry", "plot_data_quality_table", ...
    "plot_suppression_table", "unavailable_plot_card_registry", "raw_to_derived_lineage", ...
    "table_field_availability_matrix"]);
end

function status = localImplementationEvidenceStatus(implementationStatus, runtimeRows, persistedFlag, apiFlag, exportFlag, uiFlag, blocker)
implementationStatus = string(implementationStatus);
if implementationStatus == "implemented" && persistedFlag && apiFlag && exportFlag && uiFlag && ...
        (isfinite(runtimeRows) && runtimeRows > 0)
    status = "runtime_evidence_complete";
elseif implementationStatus == "implemented" && persistedFlag && apiFlag && exportFlag && uiFlag
    status = "meta_evidence_complete";
elseif implementationStatus == "blocked"
    status = "blocked_by_runtime_prerequisite";
elseif implementationStatus == "schema_only"
    status = "schema_declared_without_runtime_rows";
elseif strlength(string(blocker)) > 0
    status = "not_conformant:" + string(blocker);
else
    status = "not_conformant:no_runtime_evidence";
end
end

function status = localCompletenessStatus(currentStatus, expectedRows, actualRows)
if string(currentStatus) == "not_applicable"
    status = "not_applicable";
elseif actualRows > 0 && expectedRows > 0
    status = localTernary(actualRows >= expectedRows, "complete", "partial");
elseif actualRows > 0
    status = "present_without_expected_rows";
elseif expectedRows > 0
    status = "missing_required_rows";
elseif string(currentStatus) == "schema_only"
    status = "schema_only";
elseif string(currentStatus) == "blocked"
    status = "blocked";
else
    status = "empty";
end
end

function T = localBuildInstrumentationCoverageTable(registry, meta)
blocks = unique(string(registry.block_module));
rows = repmat(struct("block_id", "", "block_name", "", "event_stream_enabled", false, "table_count", NaN, ...
    "plot_count", NaN, "raw_artifact_count", NaN, "compare_run_support_flag", false, ...
    "anomaly_support_flag", false, "root_cause_support_flag", false), numel(blocks), 1);
for i = 1:numel(blocks)
    block = blocks(i);
    mask = string(registry.block_module) == block;
    rows(i).block_id = matlab.lang.makeValidName(char(block));
    rows(i).block_name = block;
    rows(i).event_stream_enabled = any(logical(registry.backend_source_exists_flag(mask)));
    rows(i).table_count = sum(mask);
    rows(i).plot_count = sum(contains(lower(string(registry.output_name(mask))), "plot") | contains(lower(string(registry.output_name(mask))), "heatmap"));
    rows(i).raw_artifact_count = sum(logical(registry.persisted_flag(mask)));
    rows(i).compare_run_support_flag = any(logical(registry.compare_run_supported_flag(mask)));
    rows(i).anomaly_support_flag = any(contains(lower(string(registry.output_name(mask))), "anomaly"));
    rows(i).root_cause_support_flag = any(contains(lower(string(registry.output_name(mask))), "root_cause"));
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildInstrumentationCoverageTable", ...
    "reports/csv/instrumentation_coverage_table.csv", "implemented", "meta_audit", true, true);
end

function T = localBuildAPIExposureAuditTable(registry, logicalPaths, tables, meta)
rows = table();
rows.output_name = registry.output_name;
rows.backend_source = registry.block_module;
rows.api_route = repmat("/api/run/<run_id>/live", height(registry), 1);
rows.payload_schema_version = repmat("lls_live_v1", height(registry), 1);
rows.response_non_empty_flag = registry.api_exposed_flag & registry.persisted_flag & registry.export_supported_flag;
rows.ui_bind_state = localStringFromMask(registry.current_status == "implemented", "bound", "coverage_badge_or_partial");
rows.exporter_state = repmat("unavailable_or_incomplete_export", height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    logicalPath = localRegistryLogicalPath(outName, logicalPaths);
    Tref = localRegistryTable(outName, tables);
    [jsonRequired, jsonReason] = localJSONMirrorPolicy(logicalPath, Tref);
    if logical(registry.export_supported_flag(i))
        if logical(jsonRequired)
            rows.exporter_state(i) = "csv_json";
        else
            rows.exporter_state(i) = "csv_only_scale_guard:" + string(jsonReason);
        end
    end
end
T = localFinalizeOutputTable(rows, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildAPIExposureAuditTable", ...
    "reports/csv/api_exposure_audit_table.csv", "implemented", "meta_audit", true, true);
end

function T = localBuildPersistenceAuditTable(runFolder, registry, logicalPaths, tables, meta)
rows = repmat(struct("output_name", "", "backend_source_exists_flag", false, "writer_enabled", false, ...
    "parquet_enabled", false, "csv_enabled", false, "json_enabled", false, "json_required", false, ...
    "json_policy_reason", "", "last_nonempty_run_id", NaN, "retention_policy", ""), height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    logicalPath = localRegistryLogicalPath(outName, logicalPaths);
    Tref = localRegistryTable(outName, tables);
    [jsonRequired, jsonReason] = localJSONMirrorPolicy(logicalPath, Tref);
    rows(i).output_name = outName;
    rows(i).backend_source_exists_flag = logical(registry.backend_source_exists_flag(i));
    rows(i).writer_enabled = logical(registry.persisted_flag(i));
    rows(i).parquet_enabled = false;
    rows(i).csv_enabled = logicalPath ~= "" && exist(fullfile(runFolder, logicalPath), "file") == 2;
    rows(i).json_enabled = logicalPath ~= "" && exist(fullfile(runFolder, replace(logicalPath, ".csv", ".json")), "file") == 2;
    rows(i).json_required = logical(jsonRequired);
    rows(i).json_policy_reason = string(jsonReason);
    rows(i).last_nonempty_run_id = localTernary(rows(i).csv_enabled, meta.run_id, NaN);
    if logical(jsonRequired)
        rows(i).retention_policy = "db_backed_canonical_artifact";
    else
        rows(i).retention_policy = "db_backed_canonical_artifact_csv_only_scale_guard";
    end
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildPersistenceAuditTable", ...
    "reports/csv/persistence_audit_table.csv", "implemented", "meta_audit", true, true);
end

function inventory = localBuildArtifactInventory(runFolder)
files = dir(fullfile(runFolder, "**", "*"));
coverageRows = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "lls_output_spec_coverage.csv"));
plotStatusRows = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "plot_render_status.csv"));
metricRows = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "lls_output_metric_rows.csv"));
rows = repmat(localArtifactInventoryRow("", "", NaN, "", "", false, false, false, "", ""), 0, 1);
for i = 1:numel(files)
    if files(i).isdir
        continue;
    end
    rel = localPortablePath(string(erase(fullfile(files(i).folder, files(i).name), string(runFolder) + filesep)));
    [~, ~, ext] = fileparts(files(i).name);
    ext = lower(string(ext));
    semanticState = localInventorySemanticState(rel, coverageRows, metricRows, plotStatusRows);
    artifactClass = localArtifactClassForInventory(rel, ext);
    rows(end+1, 1) = localArtifactInventoryRow(rel, ext, double(files(i).bytes), "present", ... %#ok<AGROW>
        artifactClass, semanticState, any(ext == [".csv" ".json" ".mat" ".yaml" ".yml"]), ...
        any(ext == [".md" ".png" ".jpg" ".jpeg" ".svg" ".html"]), files(i).datenum, "");
end

rows = localAppendUnavailablePlotAliases(rows, plotStatusRows, coverageRows, metricRows);
inventory = struct2table(rows);
if ~isempty(inventory)
    inventory = sortrows(inventory, "RelativePath");
end
end

function row = localArtifactInventoryRow(rel, ext, bytes, artifactState, artifactClass, semanticState, machineReadable, humanReadable, datenumValue, notes)
if nargin < 10
    notes = "";
end
if strlength(string(semanticState)) == 0
    semanticState = "observed";
end
modifiedUTC = "";
if isnumeric(datenumValue) && isfinite(datenumValue)
    modifiedUTC = string(datetime(datenumValue, "ConvertFrom", "datenum", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end
row = struct( ...
    "RelativePath", string(rel), ...
    "Extension", string(ext), ...
    "Bytes", double(bytes), ...
    "ModifiedUTC", modifiedUTC, ...
    "ArtifactState", string(artifactState), ...
    "ArtifactClass", string(artifactClass), ...
    "SemanticState", string(semanticState), ...
    "CountsTowardCoverage", logical(localInventoryStateCountsTowardCoverage(semanticState)), ...
    "MachineReadable", logical(machineReadable), ...
    "HumanReadable", logical(humanReadable), ...
    "SchemaVersion", "v2", ...
    "Notes", string(notes));
end

function rows = localAppendUnavailablePlotAliases(rows, plotStatusRows, coverageRows, metricRows)
if ~(istable(plotStatusRows) && ~isempty(plotStatusRows) && localHasVar(plotStatusRows, "PlotId") && localHasVar(plotStatusRows, "ImagePath"))
    return;
end
isCard = false(height(plotStatusRows), 1);
if localHasVar(plotStatusRows, "IsUnavailableCard")
    isCard = localColumnAsLogical(plotStatusRows, "IsUnavailableCard");
end
status = strings(height(plotStatusRows), 1);
if localHasVar(plotStatusRows, "PlotRenderStatus")
    status = lower(strtrim(string(plotStatusRows.PlotRenderStatus)));
end
mask = isCard | status == "rendered_unavailable_card";
for i = find(mask(:).')
    plotId = strtrim(string(plotStatusRows.PlotId(i)));
    if strlength(plotId) == 0
        continue;
    end
    aliasPath = "reports/image/" + plotId + ".png";
    if any(string({rows.RelativePath}) == aliasPath)
        continue;
    end
    cardPath = localPortablePath(string(plotStatusRows.ImagePath(i)));
    semanticState = localSemanticStateForPlotId(plotId, coverageRows, metricRows);
    rows(end+1, 1) = localArtifactInventoryRow(aliasPath, ".png", 0, "unavailable_card_alias", ... %#ok<AGROW>
        "report_image", semanticState, false, true, NaN, ...
        "logical plot path is represented by unavailable card " + cardPath + "; no normal PNG was written");
end
end

function state = localSemanticStateForPlotId(plotId, coverageRows, metricRows)
metricKey = localPlotIdToMetricKey(plotId);
state = localMetricAvailabilityState(metricKey, coverageRows);
if state == "not_available"
    state = localMetricAvailabilityState(metricKey, metricRows);
end
end

function metricKey = localPlotIdToMetricKey(plotId)
plotId = lower(strtrim(string(plotId)));
switch plotId
    case "ai_confidence_trace"
        metricKey = "ai_confidence_traces";
    case "access_delay_cdf"
        metricKey = "curves_access_delay_cdf";
    otherwise
        metricKey = plotId;
end
end

function state = localInventorySemanticState(relPath, coverageRows, metricRows, plotStatusRows)
relPath = localPortablePath(string(relPath));
state = localInferInventoryStateFromPath(relPath);

stateFromMetricRows = localAvailabilityStateForSource(relPath, metricRows);
if stateFromMetricRows ~= "not_available"
    state = stateFromMetricRows;
end
stateFromCoverage = localAvailabilityStateForSource(relPath, coverageRows);
if stateFromCoverage ~= "not_available"
    state = stateFromCoverage;
end

plotState = localAvailabilityStateForPlotPath(relPath, plotStatusRows, coverageRows, metricRows);
if plotState ~= "not_available"
    state = plotState;
end
end

function state = localAvailabilityStateForPlotPath(relPath, plotStatusRows, coverageRows, metricRows)
state = "not_available";
if ~(istable(plotStatusRows) && ~isempty(plotStatusRows) && localHasVar(plotStatusRows, "ImagePath") && localHasVar(plotStatusRows, "PlotId"))
    return;
end
paths = localPortablePath(string(plotStatusRows.ImagePath));
mask = paths == localPortablePath(relPath);
if ~any(mask)
    return;
end
plotIds = string(plotStatusRows.PlotId(mask));
states = strings(numel(plotIds), 1);
for i = 1:numel(plotIds)
    states(i) = localSemanticStateForPlotId(plotIds(i), coverageRows, metricRows);
end
state = localRollupInventoryState(states);
if state == "not_available" && localHasVar(plotStatusRows, "VisualValidity")
    visualStates = lower(strtrim(string(plotStatusRows.VisualValidity(mask))));
    if any(visualStates == "diagnostic_only")
        state = "diagnostic_only";
    elseif any(visualStates == "unavailable")
        state = "unavailable";
    end
end
end

function state = localAvailabilityStateForSource(relPath, rows)
state = "not_available";
if ~(istable(rows) && ~isempty(rows) && localHasVar(rows, "SourceArtifact") && localHasVar(rows, "Availability"))
    return;
end
sources = localPortablePath(string(rows.SourceArtifact));
mask = strlength(sources) > 0 & sources == localPortablePath(relPath);
if any(mask)
    state = localRollupInventoryState(string(rows.Availability(mask)));
end
end

function state = localMetricAvailabilityState(metricKey, rows)
state = "not_available";
if ~(istable(rows) && ~isempty(rows) && localHasVar(rows, "MetricKey") && localHasVar(rows, "Availability"))
    return;
end
mask = lower(strtrim(string(rows.MetricKey))) == lower(strtrim(string(metricKey)));
if any(mask)
    state = localRollupInventoryState(string(rows.Availability(mask)));
end
end

function state = localInferInventoryStateFromPath(relPath)
relPath = lower(strtrim(localPortablePath(relPath)));
if strlength(relPath) == 0
    state = "not_available";
elseif startsWith(relPath, "reports/") || contains(relPath, "/reports/")
    state = "derived";
elseif startsWith(relPath, "meta/") || contains(relPath, "/meta/")
    state = "config_only";
else
    state = "observed";
end
end

function state = localRollupInventoryState(states)
states = lower(strtrim(string(states(:))));
states = states(strlength(states) > 0);
if isempty(states)
    state = "not_available";
    return;
end
states(states == "available") = "observed";
states(states == "not_enabled") = "disabled";
precedence = ["observed","derived","config_only","disabled","placeholder","diagnostic_only","unavailable","not_supported","not_exercised","not_available"];
for i = 1:numel(precedence)
    if any(states == precedence(i))
        state = precedence(i);
        return;
    end
end
state = "not_available";
end

function tf = localInventoryStateCountsTowardCoverage(state)
state = lower(strtrim(string(state)));
tf = state == "observed" | state == "derived" | state == "real_lls_evidence";
end

function className = localArtifactClassForInventory(rel, ext)
rel = lower(string(rel));
if startsWith(rel, "meta/")
    className = "metadata";
elseif startsWith(rel, "reports/")
    className = "report";
elseif startsWith(rel, "air_interface/")
    className = "air_interface";
elseif startsWith(rel, "control/")
    className = "control";
elseif startsWith(rel, "beamforming/")
    className = "beamforming";
elseif startsWith(rel, "logs/")
    className = "log";
else
    className = "other";
end
if ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".svg"
    className = className + "_image";
elseif ext == ".csv"
    className = className + "_csv";
end
end

function entries = localManifestUnavailableEntries(unavailable)
entries = repmat(struct("OutputName", "", "ArtifactState", "unavailable", "UnavailableReason", "", ...
    "ClassificationCode", "", "RequiredBackendSources", "", "NextImplementationStep", ""), 0, 1);
if ~(istable(unavailable) && ~isempty(unavailable))
    return;
end
for i = 1:height(unavailable)
    entries(end+1, 1) = struct( ... %#ok<AGROW>
        "OutputName", char(string(unavailable.output_name(i))), ...
        "ArtifactState", "unavailable", ...
        "UnavailableReason", char(string(unavailable.unavailable_reason(i))), ...
        "ClassificationCode", char(string(unavailable.classification_code(i))), ...
        "RequiredBackendSources", char(string(unavailable.required_backend_sources(i))), ...
        "NextImplementationStep", char(string(unavailable.next_implementation_step(i))));
end
end

function specs = localRequestedOutputSpecs()
specs = [ ...
    localSpec("output_coverage_registry", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/output_coverage_registry.csv"), ...
    localSpec("lls_implementation_register", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/lls_implementation_register.csv"), ...
    localSpec("output_completeness_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/output_completeness_table.csv"), ...
    localSpec("instrumentation_coverage_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/instrumentation_coverage_table.csv"), ...
    localSpec("api_exposure_audit_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/api_exposure_audit_table.csv"), ...
    localSpec("persistence_audit_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/persistence_audit_table.csv"), ...
    localSpec("honest_unavailable_registry", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/honest_unavailable_registry.csv"), ...
    localSpec("lls_output_contract", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/lls_output_contract.csv"), ...
    localSpec("metric_definition_catalog", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/metric_definition_catalog.csv"), ...
    localSpec("metric_unit_role_catalog", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/metric_unit_role_catalog.csv"), ...
    localSpec("plot_manifest", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/plot_manifest.csv"), ...
    localSpec("visual_artifact_audit", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/visual_artifact_audit.csv"), ...
    localSpec("plot_render_status", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/plot_render_status.csv"), ...
    localSpec("chart_source_registry", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/chart_source_registry.csv"), ...
    localSpec("plot_data_quality_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/plot_data_quality_table.csv"), ...
    localSpec("plot_suppression_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/plot_suppression_table.csv"), ...
    localSpec("unavailable_plot_card_registry", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/unavailable_plot_card_registry.csv"), ...
    localSpec("raw_to_derived_lineage", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/raw_to_derived_lineage.csv"), ...
    localSpec("table_field_availability_matrix", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/table_field_availability_matrix.csv"), ...
    localSpec("kpi_health_flags", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/kpi_health_flags.csv"), ...
    localSpec("result_issue_registry", "root_cause", "cross_layer_issue_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/result_issue_registry.csv"), ...
    localSpec("table_scenario_topology", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/table_scenario_topology.csv"), ...
    localSpec("scenario_consistency_check_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/scenario_consistency_check_table.csv"), ...
    localSpec("topology_density_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/topology_density_table.csv"), ...
    localSpec("sector_utilization_summary_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/sector_utilization_summary_table.csv"), ...
    localSpec("serving_cell_population_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/serving_cell_population_table.csv"), ...
    localSpec("neighbor_degree_histogram_data", "scenario_topology", "scenario_runtime", false, "a", "no", true, false, "phase_now", "reports/csv/neighbor_degree_histogram_data.csv"), ...
    localSpec("topology_parameter_diff_vs_baseline", "scenario_topology", "scenario_runtime", true, "r", "partial", true, true, "phase_compare", ""), ...
    localSpec("scenario_topology_map", "scenario_topology", "scenario_runtime", false, "a", "no", false, false, "phase_backlog", ""), ...
    localSpec("site_sector_schematic", "scenario_topology", "scenario_runtime", false, "a", "no", false, false, "phase_backlog", ""), ...
    localSpec("table_gnb_cell", "cell_analytics", "system_cell_load", true, "c", "partial", true, false, "phase_now", "reports/csv/table_gnb_cell.csv"), ...
    localSpec("table_channel_summary", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_channel_summary.csv"), ...
    localSpec("table_noise_interference", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_noise_interference.csv"), ...
    localSpec("table_link_budget", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_link_budget.csv"), ...
    localSpec("table_scheduler_decision", "scheduler", "system_scheduler", true, "c", "yes", true, false, "phase_now", "packet_flow/csv/table_scheduler_decision.csv"), ...
    localSpec("live_prb_allocation", "scheduler", "system_scheduler", true, "c", "yes", true, false, "phase_now", "packet_flow/csv/live_prb_allocation.csv"), ...
    localSpec("live_re_allocation_snapshot", "scheduler", "grid_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/live_re_allocation_snapshot.csv"), ...
    localSpec("prb_allocation_heatmap", "scheduler", "system_scheduler", true, "c", "yes", true, false, "phase_now", "reports/csv/prb_allocation_heatmap.csv"), ...
    localSpec("table_dl_transport_block", "dl", "dl_trials", true, "c", "partial", true, false, "phase_now", "reports/csv/table_dl_transport_block.csv"), ...
    localSpec("table_ul_transport_block", "ul", "ul_trials", true, "c", "partial", true, false, "phase_now", "reports/csv/table_ul_transport_block.csv"), ...
    localSpec("table_harq_process", "harq", "system_harq", true, "c", "partial", true, false, "phase_now", "reports/csv/table_harq_process.csv"), ...
    localSpec("table_cqi_pmi_ri", "phy_metrics", "scheduler_cqi", true, "c", "partial", true, false, "phase_now", "reports/csv/table_cqi_pmi_ri.csv"), ...
    localSpec("table_mcs_tbs_evolution", "phy_metrics", "scheduler_cqi", true, "c", "partial", true, false, "phase_now", "reports/csv/table_mcs_tbs_evolution.csv"), ...
    localSpec("table_latency", "latency", "packet_latency", true, "c", "yes", true, false, "phase_now", "reports/csv/table_latency.csv"), ...
    localSpec("latency_cdf_plot", "latency", "packet_latency", false, "c", "yes", true, false, "phase_now", "reports/csv/latency_cdf_plot.csv"), ...
    localSpec("live_power_runtime_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "reports/csv/live_power_runtime_table.csv"), ...
    localSpec("live_rf_power_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "reports/csv/live_rf_power_table.csv"), ...
    localSpec("live_bb_power_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "reports/csv/live_bb_power_table.csv"), ...
    localSpec("live_energy_efficiency_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "reports/csv/live_energy_efficiency_table.csv"), ...
    localSpec("live_sleep_state_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "reports/csv/live_sleep_state_table.csv"), ...
    localSpec("power_analytics", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "analytics/csv/power_analytics.csv"), ...
    localSpec("energy_efficiency_analytics", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "analytics/csv/energy_efficiency_analytics.csv"), ...
    localSpec("runtime_power_analytics", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "analytics/csv/runtime_power_analytics.csv"), ...
    localSpec("sleep_state_analytics", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "analytics/csv/sleep_state_analytics.csv"), ...
    localSpec("pdcch_dci_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/pdcch_dci_table.csv"), ...
    localSpec("ssb_pbch_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/ssb_pbch_table.csv"), ...
    localSpec("csi_rs_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/csi_rs_table.csv"), ...
    localSpec("prach_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/prach_table.csv"), ...
    localSpec("pucch_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/pucch_table.csv"), ...
    localSpec("pusch_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/pusch_table.csv"), ...
    localSpec("pdsch_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/pdsch_table.csv"), ...
    localSpec("srs_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/srs_table.csv"), ...
    localSpec("trs_receiver_tracking_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/trs_receiver_tracking_table.csv"), ...
    localSpec("pdcch_dci_public_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/pdcch_dci_table.csv"), ...
    localSpec("ssb_pbch_cell_search_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/ssb_pbch_cell_search_table.csv"), ...
    localSpec("csi_rs_runtime_event_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/csi_rs_runtime_event_table.csv"), ...
    localSpec("prach_detection_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/prach_detection_table.csv"), ...
    localSpec("pucch_uci_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/pucch_uci_table.csv"), ...
    localSpec("srs_measurement_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/srs_measurement_table.csv"), ...
    localSpec("trs_receiver_tracking_public_table", "control", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/trs_receiver_tracking_table.csv"), ...
    localSpec("pdsch_runtime_event_table", "dl", "dl_trials", true, "c", "yes", true, false, "phase_now", "reports/csv/pdsch_runtime_event_table.csv"), ...
    localSpec("pusch_runtime_event_table", "ul", "ul_trials", true, "c", "yes", true, false, "phase_now", "reports/csv/pusch_runtime_event_table.csv"), ...
    localSpec("csi_report_table", "phy_metrics", "scheduler_cqi", true, "c", "yes", true, false, "phase_now", "reports/csv/csi_report_table.csv"), ...
    localSpec("noise_variance_evidence_table", "phy_metrics", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/noise_variance_evidence_table.csv"), ...
    localSpec("mcs_cqi_decision_trace_table", "phy_metrics", "scheduler_cqi", true, "c", "yes", true, false, "phase_now", "reports/csv/mcs_cqi_decision_trace_table.csv"), ...
    localSpec("beam_precoder_table", "beam", "beam_runtime", true, "c", "yes", true, false, "phase_now", "beamforming/csv/beam_precoder_table.csv"), ...
    localSpec("beamforming_analytics_table", "beam", "beam_runtime", true, "c", "yes", true, false, "phase_now", "beamforming/csv/beamforming_analytics_table.csv"), ...
    localSpec("mimo_rank_utilization_table", "beam", "beam_runtime", true, "c", "yes", true, false, "phase_now", "beamforming/csv/mimo_rank_utilization_table.csv"), ...
    localSpec("power_energy_table", "energy", "rf_energy", true, "c", "yes", true, false, "phase_now", "rf/csv/power_energy_table.csv"), ...
    localSpec("timing_synchronization_table", "timing", "timing_runtime", true, "c", "yes", true, false, "phase_now", "control/csv/timing_synchronization_table.csv"), ...
    localSpec("compare_runs_kpi_delta_table", "compare", "compare_runtime", true, "r", "yes", false, true, "phase_compare", "reports/csv/compare_run_prerequisites.csv"), ...
    localSpec("compare_run_overlay_plot", "compare", "compare_runtime", true, "r", "yes", false, true, "phase_compare", "reports/csv/compare_run_prerequisites.csv"), ...
    localSpec("antenna_radiation_pattern_plot", "plots", "antenna_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("beam_pattern_3d_plot", "plots", "beam_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("channel_impulse_response_plot", "plots", "channel_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("power_delay_profile_plot", "plots", "channel_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("doppler_time_variation_plot", "plots", "channel_runtime", false, "c", "yes", true, false, "phase_now", "reports/csv/doppler_time_variation_plot.csv"), ...
    localSpec("cqi_pmi_ri_vs_time_plot", "plots", "scheduler_cqi", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("dl_resource_grid_heatmap", "plots", "grid_runtime", false, "c", "yes", true, false, "phase_now", "reports/csv/dl_resource_grid_heatmap.csv"), ...
    localSpec("ul_resource_grid_heatmap", "plots", "grid_runtime", false, "c", "yes", true, false, "phase_now", "reports/csv/ul_resource_grid_heatmap.csv"), ...
    localSpec("pdcch_cce_occupancy_plot", "plots", "control_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("ssb_burst_beam_plot", "plots", "control_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("csi_rs_resource_map", "plots", "control_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("prach_correlation_peak_plot", "plots", "control_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("pucch_detection_metric_plot", "plots", "control_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("constellation_plot", "plots", "air_interface_runtime", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("evm_distribution_plot", "plots", "air_interface_runtime", false, "a", "partial", false, false, "phase_backlog", ""), ...
    localSpec("harq_timeline_plot", "plots", "system_harq", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("beam_index_vs_time_plot", "plots", "system_beam", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("rank_layer_usage_histogram", "plots", "beam_runtime", false, "c", "yes", true, false, "phase_now", "beamforming/csv/rank_layer_usage_histogram.csv"), ...
    localSpec("interference_waterfall_plot", "plots", "system_interference_detail", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("sector_coverage_footprint_plot", "plots", "geometry_runtime", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("ue_position_scatter_plot", "plots", "geometry_runtime", false, "d", "partial", true, false, "phase_followup", ""), ...
    localSpec("root_cause_candidate_table", "root_cause", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/root_cause_candidate_table.csv"), ...
    localSpec("anomaly_window_table", "root_cause", "cross_layer_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/anomaly_window_table.csv"), ...
    localSpec("cross_layer_correlation_table", "root_cause", "cross_layer_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/cross_layer_correlation_table.csv"), ...
    localSpec("cell_edge_analytics_table", "root_cause", "system_ue_summary", true, "c", "partial", true, false, "phase_now", "reports/csv/cell_edge_analytics_table.csv"), ...
    localSpec("hotspot_analytics_table", "root_cause", "cross_layer_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/hotspot_analytics_table.csv"), ...
    localSpec("control_overhead_analytics_table", "root_cause", "control_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/control_overhead_analytics_table.csv"), ...
    localSpec("resource_overhead_analytics_table", "root_cause", "grid_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/resource_overhead_analytics_table.csv"), ...
    localSpec("beam_stability_analytics_table", "root_cause", "system_beam", true, "c", "partial", true, false, "phase_now", "reports/csv/beam_stability_analytics_table.csv"), ...
    localSpec("latency_root_cause_table", "root_cause", "packet_latency", true, "c", "yes", true, false, "phase_now", "reports/csv/latency_root_cause_table.csv"), ...
    localSpec("energy_root_cause_table", "root_cause", "rf_energy", true, "c", "partial", true, false, "phase_now", "reports/csv/energy_root_cause_table.csv"), ...
    localSpec("output_coverage_dashboard", "dashboard", "coverage_registry", true, "d", "yes", true, false, "phase_now", ""), ...
    localSpec("persistence_audit_dashboard", "dashboard", "coverage_registry", true, "d", "yes", true, false, "phase_now", ""), ...
    localSpec("api_exposure_dashboard", "dashboard", "coverage_registry", true, "d", "yes", true, false, "phase_now", ""), ...
    localSpec("honest_unavailable_dashboard", "dashboard", "coverage_registry", true, "d", "yes", true, false, "phase_now", ""), ...
    localSpec("root_cause_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("cell_edge_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("hotspot_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("control_overhead_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("beam_stability_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("latency_root_cause_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", ""), ...
    localSpec("energy_root_cause_dashboard", "dashboard", "root_cause", true, "d", "partial", true, false, "phase_now", "") ...
];
end

function spec = localSpec(outputName, uiSection, blockModule, requiredFlag, classCode, fixNowFlag, backendExists, compareRunSupported, targetPhase, logicalPath)
spec = struct();
spec.output_name = string(outputName);
spec.ui_section = string(uiSection);
spec.block_module = string(blockModule);
spec.required_flag = logical(requiredFlag);
spec.classification_code = string(classCode);
spec.fix_now_flag = string(fixNowFlag);
spec.backend_source_exists_flag = logical(backendExists);
spec.compare_run_supported_flag = logical(compareRunSupported);
spec.target_phase = string(targetPhase);
spec.logical_path = string(logicalPath);
spec.required_backend_sources = string(localRequiredSourcesForOutput(outputName));
spec.required_capture_point = string(localRequiredCapturePoint(outputName));
spec.required_runtime_condition = string(localRequiredRuntimeCondition(outputName));
spec.next_implementation_step = string(localNextImplementationStep(outputName));
spec.owner_tag = string(localOwnerTag(outputName));
end

function [status, classCode, persistedFlag, exportSupported, apiExposedFlag, uiRenderedFlag, blocker] = localResolveSpecStatus(spec, runFolder, tables, logicalPaths, heatmapImagePath, energyImagePath)
outName = string(spec.output_name);
classCode = string(spec.classification_code);
logicalPath = localRegistryLogicalPath(outName, logicalPaths);
T = localRegistryTable(outName, tables);
persistedFlag = false;
exportSupported = false;
apiExposedFlag = false;
uiRenderedFlag = localOutputUIRendered(spec);
if logicalPath ~= ""
    persistedFlag = localArtifactExists(runFolder, logicalPath);
    exportSupported = localOutputExportSupported(runFolder, logicalPath, T, persistedFlag);
end
hasRuntimeRows = istable(T) && ~isempty(T);
status = "unavailable";
blocker = "backend_source_missing";
if outName == "prb_allocation_heatmap" && heatmapImagePath ~= ""
    persistedFlag = persistedFlag && localArtifactExists(runFolder, "reports/image/prb_allocation_heatmap.png", heatmapImagePath);
    exportSupported = exportSupported && persistedFlag;
end
if outName == "power_energy_table" && energyImagePath ~= ""
    persistedFlag = persistedFlag && localArtifactExists(runFolder, "reports/image/power_energy_cumulative.png", energyImagePath);
    exportSupported = exportSupported && persistedFlag;
end
apiExposedFlag = localOutputAPIExposed(spec, persistedFlag, exportSupported, hasRuntimeRows);
if any(outName == ["output_coverage_registry", "lls_implementation_register", "output_completeness_table", ...
        "instrumentation_coverage_table", "api_exposure_audit_table", "persistence_audit_table", ...
        "honest_unavailable_registry"])
    status = "implemented";
    blocker = "";
    persistedFlag = true;
    exportSupported = true;
    apiExposedFlag = true;
    uiRenderedFlag = true;
    return;
end
if outName == "compare_runs_kpi_delta_table" || outName == "compare_run_overlay_plot"
    status = "blocked";
    blocker = "comparable_run_group_missing";
    return;
end
if outName == "output_coverage_dashboard" || outName == "persistence_audit_dashboard" || outName == "api_exposure_dashboard" || outName == "honest_unavailable_dashboard" ...
        || outName == "root_cause_dashboard" || outName == "cell_edge_dashboard" || outName == "hotspot_dashboard" || outName == "control_overhead_dashboard" ...
        || outName == "beam_stability_dashboard" || outName == "latency_root_cause_dashboard" || outName == "energy_root_cause_dashboard"
    status = "partial";
    apiExposedFlag = true;
    uiRenderedFlag = true;
    blocker = "dashboard_api_visible_but_no_standalone_persisted_export_artifact";
    return;
end
if logical(spec.backend_source_exists_flag) && localOutputSatisfiedByAlternativeEvidence(runFolder, outName)
    status = "partial";
    blocker = "alternative_evidence_present_but_direct_public_artifact_missing";
    apiExposedFlag = true;
    uiRenderedFlag = true;
    return;
end
if hasRuntimeRows
    if ~logical(spec.backend_source_exists_flag)
        status = "partial";
        blocker = "backend_source_contract_not_declared";
    elseif ~persistedFlag
        status = "partial";
        blocker = "persistence_missing";
    elseif ~exportSupported
        status = "partial";
        blocker = "export_missing_or_not_verifiable";
    elseif ~apiExposedFlag
        status = "partial";
        blocker = "api_response_empty_or_not_exposed";
    elseif ~uiRenderedFlag
        status = "partial";
        blocker = "ui_status_badge_not_rendered";
    else
        status = "implemented";
        blocker = "";
    end
    return;
end
if classCode == "c" && localIsStandaloneRuntimeBackedOutput(outName)
    status = "unavailable";
    blocker = localStandaloneRuntimeBlocker(outName, runFolder, spec);
    return;
end
switch classCode
    case "a"
        status = "unavailable";
        blocker = "backend_source_missing";
    case "c"
        status = "partial";
        blocker = "runtime_data_present_but_run_row_count_zero";
    case "d"
        status = "partial";
        blocker = "api_or_ui_binding_pending";
    case "f"
        status = "schema_only";
        blocker = "schema_only_placeholder";
    case "r"
        status = "blocked";
        blocker = "runtime_prerequisite_not_satisfied";
    otherwise
        status = "unavailable";
        blocker = "unclassified_gap";
end
end

function tf = localShouldRecordUnavailableRow(spec, status, blocker)
tf = true;
if string(status) == "implemented"
    tf = false;
    return;
end
if string(blocker) == "comparable_run_group_missing" || string(blocker) == "runtime_prerequisite_not_satisfied"
    tf = false;
    return;
end
if ~logical(spec.required_flag) && string(status) == "blocked"
    tf = false;
end
end

function tf = localOutputSatisfiedByAlternativeEvidence(runFolder, outName)
paths = localAlternativeEvidencePaths(outName);
if isempty(paths)
    tf = false;
    return;
end
tf = false;
for i = 1:numel(paths)
    if localArtifactExists(runFolder, string(paths(i)))
        tf = true;
        return;
    end
end
end

function paths = localAlternativeEvidencePaths(outName)
switch string(outName)
    case {"output_coverage_dashboard"}
        paths = "reports/csv/output_coverage_registry.csv";
    case {"persistence_audit_dashboard"}
        paths = "reports/csv/persistence_audit_table.csv";
    case {"api_exposure_dashboard"}
        paths = "reports/csv/api_exposure_audit_table.csv";
    case {"honest_unavailable_dashboard"}
        paths = "reports/csv/honest_unavailable_registry.csv";
    case {"root_cause_dashboard"}
        paths = "reports/csv/root_cause_candidate_table.csv";
    case {"cell_edge_dashboard"}
        paths = "reports/csv/cell_edge_analytics_table.csv";
    case {"hotspot_dashboard"}
        paths = "reports/csv/hotspot_analytics_table.csv";
    case {"control_overhead_dashboard"}
        paths = "reports/csv/control_overhead_analytics_table.csv";
    case {"beam_stability_dashboard"}
        paths = "reports/csv/beam_stability_analytics_table.csv";
    case {"latency_root_cause_dashboard"}
        paths = "reports/csv/latency_root_cause_table.csv";
    case {"energy_root_cause_dashboard"}
        paths = "reports/csv/energy_root_cause_table.csv";
    case {"pdcch_cce_occupancy_plot"}
        paths = ["reports/csv/contract__dl-control-phy-pdcch__cce-usage-heatmap.csv", ...
            "reports/image/contract__dl-control-phy-pdcch__cce-usage-heatmap.png"];
    case {"ssb_burst_beam_plot"}
        paths = ["reports/csv/contract__ssb-pbch-pss-sss__ssb-index-timeline.csv", ...
            "reports/csv/contract__ssb-pbch-pss-sss__ssb-pbch-occupancy-map.csv"];
    case {"csi_rs_resource_map"}
        paths = ["reports/csv/contract__csi-rs__csi-rs-resource-occupancy.csv", ...
            "reports/csv/live_csirs_resource_table.csv"];
    case {"prach_correlation_peak_plot"}
        paths = ["reports/csv/prach_correlation_trace.csv", ...
            "reports/csv/prach_correlation_traces.csv", ...
            "reports/csv/contract__prach-random-access__peak-value-histogram.csv"];
    case {"pucch_detection_metric_plot"}
        paths = ["packet_flow/csv/live_pucch_grants.csv", ...
            "reports/csv/contract__pucch-f0-f1-f2-f3-f4__dtx-detection-chart.csv"];
    case {"constellation_plot"}
        paths = ["reports/csv/equalized_constellations.csv", ...
            "reports/image/equalized_constellations.png"];
    case {"evm_distribution_plot"}
        paths = ["analytics/csv/contract__constellation-evm-analytics__evm-rms.csv", ...
            "analytics/csv/evm_analytics.csv"];
    case {"harq_timeline_plot"}
        paths = ["reports/csv/live_harq_timeline.csv", ...
            "analytics/csv/contract__harq-analytics__harq-process-timeline.csv"];
    case {"beam_index_vs_time_plot"}
        paths = ["beamforming/csv/beam_precoder_table.csv", ...
            "reports/csv/live_beam_selection_table.csv"];
    case {"interference_waterfall_plot"}
        paths = ["reports/csv/live_channel_state_tti.csv", "reports/csv/table_noise_interference.csv"];
    case {"sector_coverage_footprint_plot"}
        paths = ["reports/csv/live_coverage_layer.csv", "reports/csv/live_sector_table.csv"];
    case {"ue_position_scatter_plot"}
        paths = ["reports/csv/live_ue_table.csv", "reports/csv/live_coverage_layer.csv"];
    case {"scenario_topology_map"}
        paths = ["reports/csv/live_site_table.csv", "reports/csv/live_sector_table.csv", "reports/csv/live_ue_table.csv"];
    case {"site_sector_schematic"}
        paths = ["reports/csv/live_site_table.csv", "reports/csv/live_sector_table.csv"];
    case {"antenna_radiation_pattern_plot"}
        paths = "reports/csv/antenna_config_resolved.csv";
    case {"beam_pattern_3d_plot"}
        paths = ["beamforming/csv/beam_precoder_table.csv", "reports/csv/live_beam_selection_table.csv"];
    case {"channel_impulse_response_plot", "power_delay_profile_plot"}
        paths = ["reports/csv/channel_snapshots.csv", "reports/csv/live_channel_state_tti.csv"];
    case {"cqi_pmi_ri_vs_time_plot"}
        paths = ["reports/csv/live_coverage_layer.csv", ...
            "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"];
    otherwise
        paths = strings(0, 1);
end
paths = string(paths(:));
end

function T = localRegistryTable(outName, tables)
T = table();
if isfield(tables, char(outName))
    T = tables.(char(outName));
end
end

function tf = localOutputUIRendered(spec)
% The coverage dashboard renders every registry row with a status and reason.
% More specific pages/cards may exist, but this keeps the flag tied to the
% browser-visible registry contract instead of treating missing data as a page.
tf = strlength(string(spec.output_name)) > 0;
end

function tf = localOutputAPIExposed(spec, persistedFlag, exportSupported, hasRuntimeRows)
outputName = string(spec.output_name);
if contains(outputName, "dashboard")
    tf = true;
    return;
end
if hasRuntimeRows
    tf = logical(persistedFlag) && logical(exportSupported);
else
    tf = false;
end
end

function tf = localOutputExportSupported(runFolder, logicalPath, T, persistedFlag)
tf = false;
if ~logical(persistedFlag) || string(logicalPath) == ""
    return;
end
logicalPath = string(logicalPath);
if endsWith(lower(logicalPath), ".csv")
    [jsonRequired, ~] = localJSONMirrorPolicy(logicalPath, T);
    if ~logical(jsonRequired)
        tf = true;
    else
        jsonPath = replace(logicalPath, ".csv", ".json");
        tf = localArtifactExists(runFolder, jsonPath);
    end
else
    tf = true;
end
end

function tf = localIsStandaloneRuntimeBackedOutput(outName)
tf = any(string(outName) == ["topology_density_table", "sector_utilization_summary_table", "serving_cell_population_table", ...
    "table_scheduler_decision", "table_latency", "latency_cdf_plot", "latency_root_cause_table", ...
    "beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram", ...
    "live_power_runtime_table", "live_rf_power_table", "live_bb_power_table", "live_energy_efficiency_table", "live_sleep_state_table", ...
    "power_analytics", "energy_efficiency_analytics", "runtime_power_analytics", "sleep_state_analytics", ...
    "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "live_re_allocation_snapshot", "doppler_time_variation_plot", ...
    "anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", ...
    "control_overhead_analytics_table", "resource_overhead_analytics_table", ...
    "pdcch_dci_table", "ssb_pbch_table", "prach_table", "pucch_table", ...
    "pusch_table", "pdsch_table", "srs_table", "trs_receiver_tracking_table", ...
    "csi_rs_table", "beam_precoder_table", "timing_synchronization_table", ...
    "pdsch_runtime_event_table", "pusch_runtime_event_table", "pdcch_dci_public_table", ...
    "pucch_uci_table", "prach_detection_table", "srs_measurement_table", ...
    "csi_rs_runtime_event_table", "csi_report_table", "trs_receiver_tracking_public_table", ...
    "ssb_pbch_cell_search_table", "noise_variance_evidence_table", "mcs_cqi_decision_trace_table"]);
end

function blocker = localStandaloneRuntimeBlocker(outName, runFolder, spec)
sources = split(string(spec.required_backend_sources), "|");
sources = sources(strlength(sources) > 0);
if isempty(sources)
    blocker = "runtime_source_artifact_missing";
    return;
end
existsMask = false(numel(sources), 1);
for i = 1:numel(sources)
    existsMask(i) = exist(fullfile(runFolder, char(sources(i))), "file") == 2;
end
if any(existsMask)
    blocker = "runtime_source_artifact_present_but_no_rows:" + strjoin(sources(existsMask), "|");
else
    blocker = "runtime_source_artifact_missing:" + strjoin(sources, "|");
end
if string(outName) == "beam_precoder_table" && any(existsMask)
    blocker = "runtime_air_interface_trials_present_but_no_beam_precoder_rows";
elseif string(outName) == "timing_synchronization_table" && any(existsMask)
    blocker = "runtime_air_interface_trials_present_but_no_cfo_timing_rows";
end
end

function tf = localArtifactExists(runFolder, logicalPath, absolutePath)
if nargin < 3
    absolutePath = "";
end
tf = false;
logicalPath = string(logicalPath);
if logicalPath == ""
    return;
end
if strlength(string(absolutePath)) > 0 && exist(char(string(absolutePath)), "file") == 2
    tf = true;
    return;
end
if exist(fullfile(runFolder, char(logicalPath)), "file") == 2
    tf = true;
    return;
end
if ~sixgr.db.isArtifactStoreActive()
    return;
end
try
    storeState = sixgr.db.artifactStore("get_state");
    conn = sixgr.util.structGet(storeState, "Connection", []);
    runID = double(sixgr.util.structGet(storeState, "RunID", NaN));
    if isempty(conn) || ~(isfinite(runID) && runID > 0)
        return;
    end
    ps = conn.prepareStatement("SELECT COUNT(*) FROM sim_artifacts WHERE run_id=? AND logical_path=?");
    cleanupPS = onCleanup(@() ps.close()); %#ok<NASGU>
    ps.setLong(1, int64(runID));
    ps.setString(2, char(logicalPath));
    rs = ps.executeQuery();
    cleanupRS = onCleanup(@() rs.close()); %#ok<NASGU>
    if rs.next()
        tf = double(rs.getLong(1)) > 0;
    end
catch
    tf = false;
end
end

function logicalPath = localRegistryLogicalPath(outName, logicalPaths)
logicalPath = "";
if isfield(logicalPaths, char(outName))
    logicalPath = string(logicalPaths.(char(outName)));
end
end

function count = localArtifactRowCount(runFolder, logicalPath, T)
if istable(T) && ~isempty(T)
    count = height(T);
    return;
end
if logicalPath == "" || exist(fullfile(runFolder, logicalPath), "file") ~= 2
    count = 0;
    return;
end
tmp = localReadOptionalTable(fullfile(runFolder, logicalPath));
count = height(tmp);
end

function expected = localExpectedRowCount(outName, T, currentStatus)
if istable(T) && ~isempty(T)
    expected = height(T);
elseif currentStatus == "implemented"
    expected = 1;
elseif currentStatus == "blocked" || currentStatus == "unavailable" || currentStatus == "schema_only"
    expected = 0;
else
    if outName == "table_scenario_topology" || outName == "scenario_consistency_check_table" || outName == "compare_run_prerequisites"
        expected = 1;
    else
        expected = 0;
    end
end
end

function pct = localCompleteness(expectedRows, actualRows, expectedArtifacts, actualArtifacts, currentStatus)
if currentStatus == "implemented" && expectedRows == 0 && actualRows == 0
    pct = 100;
    return;
end
den = max(expectedRows + expectedArtifacts, 1);
num = min(actualRows, expectedRows) + min(actualArtifacts, expectedArtifacts);
pct = 100 * num / den;
end

function val = localRequiredSourcesForOutput(outputName)
switch string(outputName)
    case {"power_energy_table", "energy_root_cause_table", "live_power_runtime_table", "live_rf_power_table", "live_bb_power_table", "live_sleep_state_table"}
        val = "rf/csv/energy_timeline_trace.csv";
    case {"live_energy_efficiency_table"}
        val = "rf/csv/energy_timeline_trace.csv|rf/csv/power_energy_table.csv";
    case {"power_analytics", "energy_efficiency_analytics", "runtime_power_analytics", "sleep_state_analytics"}
        val = "reports/csv/live_power_runtime_table.csv|reports/csv/live_energy_efficiency_table.csv|reports/csv/live_sleep_state_table.csv";
    case {"live_prb_allocation", "live_re_allocation_snapshot", "prb_allocation_heatmap", "table_mcs_tbs_evolution", ...
            "table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", ...
            "resource_overhead_analytics_table"}
        val = "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv";
    case {"table_channel_summary", "table_noise_interference", "table_link_budget", "root_cause_candidate_table", ...
            "doppler_time_variation_plot"}
        val = "system/csv/system_interference_detail.csv|reports/csv/live_mobility_state.csv|reports/csv/live_coverage_layer.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
    case {"table_gnb_cell", "sector_utilization_summary_table"}
        val = "system/tables/sectors.csv|system/csv/system_cell_load.csv";
    case {"topology_density_table"}
        val = "system/tables/sites.csv|system/tables/sectors.csv|system/tables/ues.csv|reports/csv/deployment_layout_reference.csv";
    case {"serving_cell_population_table"}
        val = "system/csv/system_interference_detail.csv|system/csv/system_ue_summary.csv|reports/csv/live_coverage_layer.csv|air_interface/csv/ul_pusch_trials.csv";
    case {"neighbor_degree_histogram_data"}
        val = "reports/csv/live_cell_measurement_trace.csv|reports/csv/live_coverage_layer.csv";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table"}
        val = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
    case {"beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram"}
        val = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
    case {"anomaly_window_table"}
        val = "reports/csv/result_issue_registry.csv";
    case {"cross_layer_correlation_table"}
        val = "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv|system/csv/system_interference_detail.csv";
    case {"hotspot_analytics_table"}
        val = "system/csv/system_ue_summary.csv";
    case {"control_overhead_analytics_table"}
        val = "control/csv/pdcch_trials.csv|control/csv/pucch_trials.csv|control/csv/prach_trials.csv|packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv";
    case {"lls_implementation_register", "lls_output_contract", "metric_definition_catalog", "metric_unit_role_catalog", ...
            "plot_manifest", "visual_artifact_audit", "plot_render_status", "chart_source_registry", ...
            "plot_data_quality_table", "plot_suppression_table", "unavailable_plot_card_registry", ...
            "raw_to_derived_lineage", "table_field_availability_matrix"}
        val = "reports/csv/output_coverage_registry.csv";
    case "pdcch_dci_table"
        val = "control/csv/pdcch_trials.csv|air_interface/csv/pdcch_trials.csv";
    case "ssb_pbch_table"
        val = "control/csv/pbch_trials.csv|air_interface/csv/pbch_trials.csv";
    case "prach_table"
        val = "control/csv/prach_trials.csv|air_interface/csv/prach_trials.csv";
    case "pucch_table"
        val = "control/csv/pucch_trials.csv|air_interface/csv/pucch_trials.csv|packet_flow/csv/live_pucch_grants.csv";
    case "pusch_table"
        val = "air_interface/csv/ul_pusch_trials.csv";
    case "pdsch_table"
        val = "air_interface/csv/dl_pdsch_trials.csv";
    case "srs_table"
        val = "control/csv/srs_trials.csv|air_interface/csv/srs_trials.csv";
    case "trs_receiver_tracking_table"
        val = "reports/csv/live_receiver_tracking_trace.csv";
    case "beam_precoder_table"
        val = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
    case "timing_synchronization_table"
        val = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
    case "csi_rs_table"
        val = "air_interface/csv/csi_rs_trials.csv|reports/csv/live_csirs_stats.csv|reports/csv/live_csirs_resource_table.csv";
    case "pdsch_runtime_event_table"
        val = "air_interface/csv/dl_pdsch_trials.csv";
    case "pusch_runtime_event_table"
        val = "air_interface/csv/ul_pusch_trials.csv";
    case {"pdcch_dci_public_table", "ssb_pbch_cell_search_table", "prach_detection_table", ...
            "pucch_uci_table", "srs_measurement_table", "trs_receiver_tracking_public_table"}
        val = "control/csv/pdcch_trials.csv|control/csv/pbch_trials.csv|control/csv/prach_trials.csv|control/csv/pucch_trials.csv|control/csv/srs_trials.csv|reports/csv/live_receiver_tracking_trace.csv";
    case "csi_rs_runtime_event_table"
        val = "air_interface/csv/csi_rs_trials.csv|reports/csv/live_csirs_stats.csv";
    case {"csi_report_table", "mcs_cqi_decision_trace_table"}
        val = "reports/csv/table_cqi_pmi_ri.csv|reports/csv/table_mcs_tbs_evolution.csv";
    case "noise_variance_evidence_table"
        val = "reports/csv/pdsch_runtime_event_table.csv|reports/csv/pusch_runtime_event_table.csv|reports/csv/pucch_uci_table.csv|reports/csv/srs_measurement_table.csv";
    otherwise
        val = "";
end
end

function val = localRequiredCapturePoint(outputName)
switch string(outputName)
    case {"power_energy_table", "energy_root_cause_table", "live_power_runtime_table", "live_rf_power_table", ...
            "live_bb_power_table", "live_energy_efficiency_table", "live_sleep_state_table", ...
            "power_analytics", "energy_efficiency_analytics", "runtime_power_analytics", "sleep_state_analytics"}
        val = "sixgr.truth.exportLLSEnergyDiagnostics|sixgr.truth.exportLLSOutputCoverageArtifacts";
    case {"live_prb_allocation", "live_re_allocation_snapshot", "prb_allocation_heatmap", "table_mcs_tbs_evolution", ...
            "table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", ...
            "resource_overhead_analytics_table"}
        val = "sixgr.system.SystemLevelRunner.run";
    case {"table_channel_summary", "table_noise_interference", "table_link_budget", "root_cause_candidate_table", ...
            "serving_cell_population_table", "doppler_time_variation_plot"}
        val = "sixgr.system.SystemLevelRunner.interference_detail_export|sixgr.truth.exportLLSLiveMobilityTables|sixgr.truth.exportLLSLiveDerivedTables";
    case {"topology_density_table", "sector_utilization_summary_table"}
        val = "sixgr.system.SystemLevelRunner.topology_and_cell_load_export";
    case {"neighbor_degree_histogram_data"}
        val = "sixgr.truth.exportLLSLiveMobilityTables|sixgr.truth.exportLLSOutputCoverageArtifacts";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table"}
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case {"beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram"}
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case {"anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", "control_overhead_analytics_table"}
        val = "sixgr.truth.exportLLSOutputCoverageArtifacts";
    case {"lls_implementation_register", "lls_output_contract", "metric_definition_catalog", "metric_unit_role_catalog", ...
            "plot_manifest", "visual_artifact_audit", "plot_render_status", "chart_source_registry", ...
            "plot_data_quality_table", "plot_suppression_table", "unavailable_plot_card_registry", ...
            "raw_to_derived_lineage", "table_field_availability_matrix", ...
            "pdsch_runtime_event_table", "pusch_runtime_event_table", "pdcch_dci_public_table", ...
            "pucch_uci_table", "prach_detection_table", "srs_measurement_table", ...
            "csi_rs_runtime_event_table", "csi_report_table", "trs_receiver_tracking_public_table", ...
            "ssb_pbch_cell_search_table", "noise_variance_evidence_table", "mcs_cqi_decision_trace_table"}
        val = "sixgr.truth.exportLLSOutputCoverageArtifacts";
    case {"pdcch_dci_table", "ssb_pbch_table", "prach_table", "pucch_table", "srs_table"}
        val = "sixgr.truth.exportControlPlaneTraces";
    case "trs_receiver_tracking_table"
        val = "sixgr.truth.CoupledTruthRuntime.writeTables";
    case "pdsch_table"
        val = "sixgr.link.runDLPDSCHThroughput";
    case "pusch_table"
        val = "sixgr.link.runULPUSCHThroughput";
    case "beam_precoder_table"
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case "timing_synchronization_table"
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case "csi_rs_table"
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.truth.exportLLSLiveDerivedTables";
    otherwise
        val = "coverage_registry_only";
end
end

function val = localRequiredRuntimeCondition(outputName)
switch string(outputName)
    case {"compare_runs_kpi_delta_table", "compare_run_overlay_plot"}
        val = "paired_baseline_and_candidate_runs";
    case {"power_energy_table", "live_power_runtime_table", "live_rf_power_table", "live_bb_power_table", ...
            "live_energy_efficiency_table", "live_sleep_state_table", ...
            "power_analytics", "energy_efficiency_analytics", "runtime_power_analytics", "sleep_state_analytics"}
        val = "energy_logging_enable";
    case {"live_prb_allocation", "live_re_allocation_snapshot"}
        val = "scheduler_active";
    case {"table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "resource_overhead_analytics_table"}
        val = "scheduler_grants_exported";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table"}
        val = "air_interface_trials_include_real_latency_columns";
    case {"beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram"}
        val = "air_interface_trials_include_runtime_beam_precoder_rows";
    case {"topology_density_table", "sector_utilization_summary_table", "serving_cell_population_table"}
        val = "topology_or_system_summary_artifacts_exported";
    case {"neighbor_degree_histogram_data"}
        val = "live_cell_measurement_trace_and_coverage_layer_exported";
    case "trs_receiver_tracking_table"
        val = "trs_enabled_and_runtime_processed";
    case "csi_rs_table"
        val = "csi_rs_enabled_and_runtime_transmitted_or_observed_or_aggregate_feedback_summary_persisted";
    case {"pdsch_runtime_event_table", "pusch_runtime_event_table"}
        val = "waveform_air_interface_trials_exported";
    case {"pdcch_dci_public_table", "ssb_pbch_cell_search_table", "prach_detection_table", ...
            "pucch_uci_table", "srs_measurement_table", "trs_receiver_tracking_public_table", ...
            "csi_rs_runtime_event_table"}
        val = "control_or_reference_runtime_rows_exported";
    case {"csi_report_table", "mcs_cqi_decision_trace_table"}
        val = "scheduler_feedback_trace_exported";
    case "noise_variance_evidence_table"
        val = "runtime_receiver_public_tables_exported";
    case {"lls_implementation_register", "lls_output_contract", "metric_definition_catalog", "metric_unit_role_catalog", ...
            "plot_manifest", "visual_artifact_audit", "plot_render_status", "chart_source_registry", ...
            "plot_data_quality_table", "plot_suppression_table", "unavailable_plot_card_registry", ...
            "raw_to_derived_lineage", "table_field_availability_matrix"}
        val = "reporting_bundle_or_output_coverage_exported";
    otherwise
        val = "";
end
end

function val = localNextImplementationStep(outputName)
switch string(outputName)
    case {"compare_runs_kpi_delta_table", "compare_run_overlay_plot"}
        val = "persist comparable-run grouping and metric harmonization inputs";
    case {"live_power_runtime_table", "live_rf_power_table", "live_bb_power_table", ...
            "live_energy_efficiency_table", "live_sleep_state_table", ...
            "power_analytics", "energy_efficiency_analytics", "runtime_power_analytics", "sleep_state_analytics"}
        val = "canonical power and energy tables are exported from runtime RF-energy traces; extend with per-beam, thermal, and CPU telemetry when those sources become real.";
    case {"table_scheduler_decision"}
        val = "selected-grant truth is exported; add rejected-candidate rows when scheduler emits candidate telemetry";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table", "latency_root_cause_dashboard"}
        val = "latency summaries use real trial latency components; add queue-to-decode packet lifecycle rows for packet-level CDFs";
    case {"topology_density_table", "sector_utilization_summary_table", "serving_cell_population_table", "neighbor_degree_histogram_data", ...
            "beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram", ...
            "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "doppler_time_variation_plot", ...
            "anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", ...
            "control_overhead_analytics_table", "resource_overhead_analytics_table"}
        val = "runtime-backed derived table is exported; add deeper raw telemetry if the corresponding detailed view remains unavailable";
    case "csi_rs_table"
        val = "run DL waveform CSI-RS mapping/observation and mirror persisted csi_rs_trials rows; when dedicated rows are absent, persist aggregate CSI-RS runtime summaries from live_csirs_stats";
    case {"pdcch_dci_table", "ssb_pbch_table", "prach_table", "pucch_table", "srs_table"}
        val = "run control/reference-signal runtime and mirror persisted trial rows into standalone family table";
    case "trs_receiver_tracking_table"
        val = "run TRS-enabled waveform runtime and mirror persisted receiver tracking trace rows";
    case {"pusch_table", "pdsch_table", "beam_precoder_table"}
        val = "run waveform air-interface trials and mirror persisted active-path rows into standalone family table";
    case "timing_synchronization_table"
        val = "run waveform air-interface trials and persist CFO/timing lineage rows without backfilling missing estimates";
    otherwise
        val = "wire backend capture point or keep honest unavailable badge";
end
end

function val = localOwnerTag(outputName)
if contains(string(outputName), "dashboard")
    val = "browser_dashboard";
elseif contains(string(outputName), "compare")
    val = "compare_runtime";
else
    val = "truth_export";
end
end

function T = localFinalizeOutputTable(T, meta, producerModule, sourceArtifactRef, statusCode, statusClassification, derivedFlag, activeFlag)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
T = localAddMissingVar(T, "run_id", repmat(meta.run_id, n, 1));
T = localAddMissingVar(T, "run_tag", repmat(meta.run_tag, n, 1));
T = localAddMissingVar(T, "scenario_id", repmat(meta.scenario_id, n, 1));
T = localAddMissingVar(T, "scenario_variant_id", repmat(meta.scenario_variant_id, n, 1));
T = localAddMissingVar(T, "config_hash", repmat(meta.config_hash, n, 1));
T = localAddMissingVar(T, "code_commit", repmat(meta.code_commit, n, 1));
T = localAddMissingVar(T, "seed", repmat(meta.seed, n, 1));
T = localAddMissingVar(T, "drop_id", repmat(meta.drop_id, n, 1));
T = localAddMissingVar(T, "timestamp_sim_ms", nan(n, 1));
T = localAddMissingVar(T, "frame", nan(n, 1));
T = localAddMissingVar(T, "slot", nan(n, 1));
T = localAddMissingVar(T, "symbol", nan(n, 1));
T = localAddMissingVar(T, "site_id", nan(n, 1));
T = localAddMissingVar(T, "sector_id", nan(n, 1));
T = localAddMissingVar(T, "cell_id", nan(n, 1));
T = localAddMissingVar(T, "ue_id", nan(n, 1));
T = localAddMissingVar(T, "direction", repmat("", n, 1));
T = localAddMissingVar(T, "bwp_id", nan(n, 1));
T = localAddMissingVar(T, "carrier_id", nan(n, 1));
T = localAddMissingVar(T, "beam_id", nan(n, 1));
T = localAddMissingVar(T, "layer_id", nan(n, 1));
T = localAddMissingVar(T, "stream_id", nan(n, 1));
T = localAddMissingVar(T, "harq_id", nan(n, 1));
T = localAddMissingVar(T, "block_id", repmat("", n, 1));
T = localAddMissingVar(T, "pipeline_id", repmat("", n, 1));
T = localAddMissingVar(T, "producer_module", repmat(string(producerModule), n, 1));
T = localAddMissingVar(T, "status_code", repmat(string(statusCode), n, 1));
T = localAddMissingVar(T, "status_classification", repmat(string(statusClassification), n, 1));
T = localAddMissingVar(T, "source_artifact_ref", repmat(string(sourceArtifactRef), n, 1));
T = localAddMissingVar(T, "source_tensor_ref", repmat("", n, 1));
T = localAddMissingVar(T, "derived_flag", repmat(logical(derivedFlag), n, 1));
T = localAddMissingVar(T, "active_flag", repmat(logical(activeFlag), n, 1));
T = localNormalizeBlankOnlyColumns(T, meta);
end

function T = localAddMissingVar(T, name, values)
varNames = string(T.Properties.VariableNames);
if any(varNames == string(name))
    return;
end
if any(strcmpi(char(string(name)), cellstr(varNames)))
    return;
end
T = addvars(T, values, 'NewVariableNames', name);
end

function T = localNormalizeBlankOnlyColumns(T, meta)
varNames = string(T.Properties.VariableNames);
keepMask = true(1, numel(varNames));
schemaCritical = localSchemaCriticalBlankColumns();
for i = 1:numel(varNames)
    if any(strcmpi(varNames(i), schemaCritical))
        keepMask(i) = true;
        continue;
    end
    values = T.(varNames(i));
    if isnumeric(values)
        keepMask(i) = any(isfinite(double(values)));
        continue;
    end
    if islogical(values)
        keepMask(i) = true;
        continue;
    end
    if ~(isstring(values) || iscell(values) || ischar(values) || iscategorical(values))
        keepMask(i) = true;
        continue;
    end
    asString = string(values);
    if isempty(asString)
        keepMask(i) = false;
        continue;
    end
    trimmed = lower(strtrim(fillmissing(asString, "constant", "")));
    keepMask(i) = any(strlength(trimmed) > 0 & trimmed ~= "nan" & trimmed ~= "<missing>" & trimmed ~= "not_applicable");
end
if any(~keepMask)
    T(:, ~keepMask) = [];
end
end

function names = localSchemaCriticalBlankColumns()
names = ["run_id","run_tag","scenario_id","scenario_variant_id","config_hash","code_commit","seed","drop_id", ...
    "timestamp_sim_ms","frame","slot","symbol","site_id","sector_id","cell_id","ue_id","entity_type","entity_id", ...
    "direction","bwp_id","carrier_id","beam_id","layer_id","stream_id","harq_id","block_id","pipeline_id", ...
    "producer_module","status_code","status_classification","source_artifact_ref","source_tensor_ref", ...
    "derived_flag","active_flag","metric_name","metric_value","metric_unit","value_status","value_source", ...
    "artifact_id","source_table","source_pk"];
end

function commit = localResolveCodeCommit(summaryRow, runFolder)
commit = string(strtrim(string(localTableValue(summaryRow, "CodeCommit", ""))));
if strlength(commit) > 0
    return;
end
repoRoot = localFindRepoRoot(runFolder);
if strlength(repoRoot) == 0
    commit = "";
    return;
end
[status, out] = system(sprintf('git -C "%s" rev-parse HEAD', char(repoRoot)));
if status == 0
    commit = string(strtrim(out));
else
    commit = "";
end
end

function repoRoot = localFindRepoRoot(startPath)
repoRoot = "";
if nargin < 1 || strlength(string(startPath)) == 0
    return;
end
current = string(startPath);
while strlength(current) > 0
    if isfolder(fullfile(current, ".git")) && ...
            isfile(fullfile(current, "setup6GRSimToolkit.m")) && ...
            isfolder(fullfile(current, "+sixgr"))
        repoRoot = current;
        return;
    end
    parent = string(fileparts(current));
    if parent == current
        return;
    end
    current = parent;
end
end

function row = localNoiseRow(base, direction, desired, interference, noise, nf)
row = struct();
row.timestamp_sim_ms = 1e3 * double(localTableValue(base, "Time_s", NaN));
row.ue_id = localTableValue(base, "UE", NaN);
row.serving_cell_id = localTableValue(base, "ServingCell", NaN);
row.desired_signal_power_dBm = desired;
row.intra_cell_interference_dBm = NaN;
row.inter_cell_interference_dBm = interference;
row.external_interference_dBm = NaN;
row.noise_power_dBm = noise;
row.thermal_noise_dBm = localTableValue(base, "Noise_dBm", noise);
row.receiver_noise_figure_dB = nf;
row.total_interference_plus_noise_dBm = localPowerSumdBm(interference, noise);
row.pre_eq_sinr_dB = localTableValue(base, "SINR_" + direction + "_dB", NaN);
row.post_eq_sinr_dB = row.pre_eq_sinr_dB;
row.dominant_interferer_cell_id = NaN;
row.dominant_interferer_share_percent = NaN;
row.interference_limited_flag = isfinite(interference) && isfinite(noise) && interference > noise;
row.source_block = "system_interference_detail";
row.direction = string(direction);
end

function row = localLinkBudgetRow(base, direction, txPower, implLoss, rxPower, interference, noise, snr, sinr)
row = struct();
row.timestamp_sim_ms = 1e3 * double(localTableValue(base, "Time_s", NaN));
row.ue_id = localTableValue(base, "UE", NaN);
row.cell_id = localTableValue(base, "ServingCell", NaN);
row.direction = string(direction);
row.tx_power_dBm = txPower;
row.tx_antenna_gain_dBi = NaN;
row.rx_antenna_gain_dBi = NaN;
row.pathloss_dB = localTableValue(base, "Pathloss_dB", NaN);
row.shadowing_dB = NaN;
row.penetration_loss_dB = NaN;
row.implementation_loss_dB = implLoss;
row.rx_power_dBm = rxPower;
row.interference_power_dBm = interference;
row.noise_power_dBm = noise;
row.snr_dB = snr;
row.sinr_dB = sinr;
row.margin_dB = NaN;
row.power_control_command = NaN;
row.phr_dB = NaN;
row.source_chain = "system_interference_detail";
end

function rows = localBuildAllocationRows(grants, direction, meta, sourceRef)
if ~(istable(grants) && ~isempty(grants))
    rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, "symbol_start", NaN, ...
        "symbol_len", NaN, "cell_id", NaN, "ue_id", NaN, "direction", "", "bwp_id", NaN, ...
        "rb_start", NaN, "rb_len", NaN, "num_prbs", NaN, "beam_id", NaN, "rank", NaN, ...
        "layers", NaN, "harq_id", NaN, "mcs", NaN, "tbs_bits", NaN, "allocation_reason", "", ...
        "occupancy_type", "", "source_artifact_ref", ""), 0, 1);
    return;
end
rows = repmat(struct("timestamp_sim_ms", NaN, "frame", NaN, "slot", NaN, "symbol_start", NaN, ...
    "symbol_len", NaN, "cell_id", NaN, "ue_id", NaN, "direction", "", "bwp_id", NaN, ...
    "rb_start", NaN, "rb_len", NaN, "num_prbs", NaN, "beam_id", NaN, "rank", NaN, ...
    "layers", NaN, "harq_id", NaN, "mcs", NaN, "tbs_bits", NaN, "allocation_reason", "", ...
    "occupancy_type", "", "source_artifact_ref", ""), height(grants), 1);
for i = 1:height(grants)
    tti = localTableValue(grants(i, :), "TTI", NaN);
    [frameVal, slotVal] = localTTIToFrameSlot(tti, meta.slots_per_frame);
    rows(i) = struct( ...
        "timestamp_sim_ms", 1e3 * double(localTableValue(grants(i, :), "Time_s", NaN)), ...
        "frame", frameVal, ...
        "slot", slotVal, ...
        "symbol_start", localTableValue(grants(i, :), "SymbolStart", NaN), ...
        "symbol_len", localTableValue(grants(i, :), "NumSymbols", NaN), ...
        "cell_id", localTableValue(grants(i, :), "CellID", NaN), ...
        "ue_id", localTableValue(grants(i, :), "UE", NaN), ...
        "direction", string(direction), ...
        "bwp_id", localTableValue(grants(i, :), "BWPId", NaN), ...
        "rb_start", localTableValue(grants(i, :), "PRBStart", NaN), ...
        "rb_len", localTableValue(grants(i, :), "PRBCount", NaN), ...
        "num_prbs", localTableValue(grants(i, :), "PRBCount", NaN), ...
        "beam_id", NaN, ...
        "rank", localTableValue(grants(i, :), "NumLayers", NaN), ...
        "layers", localTableValue(grants(i, :), "NumLayers", NaN), ...
        "harq_id", localTableValue(grants(i, :), "HarqID", NaN), ...
        "mcs", localTableValue(grants(i, :), "MCSIndex", NaN), ...
        "tbs_bits", localTableValue(grants(i, :), "TBSBits", NaN), ...
        "allocation_reason", string(localTableValue(grants(i, :), "GrantReason", "")), ...
        "occupancy_type", string(localTernary(logical(localTableValue(grants(i, :), "IsRetransmission", false)), "retransmission", "scheduled_allocation")), ...
        "source_artifact_ref", string(sourceRef));
end
end

function rows = localBuildCQIRowsFromGrants(grants, direction)
if ~(istable(grants) && ~isempty(grants))
    rows = localEmptyCQIPMIRows(0);
    return;
end
rows = localEmptyCQIPMIRows(height(grants));
for i = 1:height(grants)
    rows(i) = struct( ...
        "timestamp_sim_ms", localGrantTimestampMsRow(grants(i, :)), ...
        "ue_id", localFirstNumericTableValue(grants(i, :), ["UE", "UEID", "UEIndex", "RNTI"], NaN), ...
        "cell_id", localFirstNumericTableValue(grants(i, :), ["CellID", "ServingCell", "BaseStationID"], NaN), ...
        "report_id", i, ...
        "report_type", "scheduler_observation", ...
        "wideband_cqi", localNormalizeReportedCQIValue(localTableValue(grants(i, :), "CQIUsed", NaN)), ...
        "subband_cqi_vector_ref", localFirstStringTableValue(grants(i, :), ["SubbandCQIVector", "subband_cqi_vector_ref"], ""), ...
        "pmi", localFirstNumericTableValue(grants(i, :), ["PMI", "RequestedPrecoderPMI"], NaN), ...
        "ri", localFirstNumericTableValue(grants(i, :), ["RIUsed", "Rank", "NumLayers"], NaN), ...
        "rank_selection_policy", localFirstStringTableValue(grants(i, :), ["RankSelectionPolicy"], ""), ...
        "rank_selection_source", localFirstStringTableValue(grants(i, :), ["RankSelectionSource"], ""), ...
        "rank_decision_reason", localFirstStringTableValue(grants(i, :), ["RankDecisionReason"], ""), ...
        "rank_downgrade_applied", logical(localTableValue(grants(i, :), "RankDowngradeApplied", false)), ...
        "max_supported_layers", localFirstNumericTableValue(grants(i, :), ["MaxSupportedLayers"], NaN), ...
        "csi_age_ms", NaN, ...
        "report_size_bits", NaN, ...
        "report_trigger", "grant_selection", ...
        "based_on", "unknown", ...
        "feedback_delay_ms", NaN, ...
        "direction", string(direction));
end
end

function rows = localEmptyCQIPMIRows(n)
n = max(0, round(double(n)));
rows = repmat(struct( ...
    "timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "report_id", NaN, ...
    "report_type", "", "wideband_cqi", NaN, "subband_cqi_vector_ref", "", "pmi", NaN, "ri", NaN, ...
    "rank_selection_policy", "", "rank_selection_source", "", "rank_decision_reason", "", ...
    "rank_downgrade_applied", false, "max_supported_layers", NaN, ...
    "csi_age_ms", NaN, "report_size_bits", NaN, "report_trigger", "", "based_on", "", ...
    "feedback_delay_ms", NaN, "direction", ""), n, 1);
end

function rows = localBuildMCSTBSRowsFromGrants(grants, direction)
if ~(istable(grants) && ~isempty(grants))
    rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "direction", "", ...
        "cqi_input", NaN, "ri_input", NaN, "pmi_input", NaN, "mcs_selected", NaN, "mod_order", NaN, ...
        "code_rate", NaN, "tbs_bits", NaN, "olla_offset", NaN, "harq_state", "", ...
        "scheduler_reason", "", "effective_sinr_dB", NaN), 0, 1);
    return;
end
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "direction", "", ...
    "cqi_input", NaN, "ri_input", NaN, "pmi_input", NaN, "mcs_selected", NaN, "mod_order", NaN, ...
    "code_rate", NaN, "tbs_bits", NaN, "olla_offset", NaN, "harq_state", "", ...
    "scheduler_reason", "", "effective_sinr_dB", NaN), height(grants), 1);
for i = 1:height(grants)
    rows(i) = struct( ...
        "timestamp_sim_ms", localGrantTimestampMsRow(grants(i, :)), ...
        "ue_id", localFirstNumericTableValue(grants(i, :), ["UE", "UEID", "UEIndex", "RNTI"], NaN), ...
        "cell_id", localFirstNumericTableValue(grants(i, :), ["CellID", "ServingCell", "BaseStationID"], NaN), ...
        "direction", string(direction), ...
        "cqi_input", localNormalizeReportedCQIValue(localTableValue(grants(i, :), "CQIUsed", NaN)), ...
        "ri_input", NaN, ...
        "pmi_input", NaN, ...
        "mcs_selected", localTableValue(grants(i, :), "MCSIndex", NaN), ...
        "mod_order", NaN, ...
        "code_rate", localTableValue(grants(i, :), "TargetCodeRate", NaN), ...
        "tbs_bits", localTableValue(grants(i, :), "TBSBits", NaN), ...
        "olla_offset", NaN, ...
        "harq_state", string(localTernary(logical(localTableValue(grants(i, :), "IsRetransmission", false)), "retransmission", "new_data")), ...
        "scheduler_reason", string(localTableValue(grants(i, :), "GrantReason", "")), ...
        "effective_sinr_dB", localTableValue(grants(i, :), "SINR_dB", NaN));
end
end

function [areaM2, areaSource] = localTopologyAreaM2(systemSites, systemUEs, isdM, numSites)
areaM2 = NaN;
areaSource = "unavailable";
tables = {systemSites, systemUEs};
labels = ["sites", "ues"];
for ti = 1:numel(tables)
    T = tables(ti);
    Ti = T{1};
    if ~(istable(Ti) && ~isempty(Ti) && localHasVar(Ti, "x_m") && localHasVar(Ti, "y_m"))
        continue;
    end
    x = localColumnAsDouble(Ti, "x_m");
    y = localColumnAsDouble(Ti, "y_m");
    keep = isfinite(x) & isfinite(y);
    if sum(keep) < 2
        continue;
    end
    width = max(x(keep)) - min(x(keep));
    heightM = max(y(keep)) - min(y(keep));
    if width > 0 && heightM > 0
        areaM2 = width * heightM;
        areaSource = "runtime_xy_extent:" + labels(ti);
        return;
    end
end
if isfinite(isdM) && isdM > 0 && isfinite(numSites) && numSites > 0
    areaM2 = double(numSites) * sqrt(3) / 2 * isdM^2;
    areaSource = "hex_cell_area_from_intersite_distance";
end
end

function total = localGrantPRBSymbols(grants, mask)
total = NaN;
if ~(istable(grants) && ~isempty(grants) && any(mask))
    return;
end
prb = localColumnAsDouble(grants, "PRBCount");
sym = localColumnAsDouble(grants, "NumSymbols");
if all(~isfinite(sym))
    sym = ones(size(prb));
end
vals = prb(mask) .* max(sym(mask), 1);
total = sum(vals(isfinite(vals)));
end

function rows = localAppendGrantCorrelation(rows, grants, direction, xName, yName, sourceRef)
if ~(istable(grants) && ~isempty(grants) && localHasVar(grants, xName) && localHasVar(grants, yName))
    return;
end
x = localColumnAsDouble(grants, xName);
y = localColumnAsDouble(grants, yName);
keep = isfinite(x) & isfinite(y);
if sum(keep) < 2
    return;
end
rows(end+1, 1) = struct( ... %#ok<AGROW>
    "direction", string(direction), ...
    "x_metric", string(xName), ...
    "y_metric", string(yName), ...
    "sample_count", sum(keep), ...
    "correlation_value", localCorrelation(x(keep), y(keep)), ...
    "correlation_method", "pearson_runtime_rows", ...
    "source_artifact_ref", string(sourceRef));
end

function count = localControlRowCount(T)
if istable(T) && ~isempty(T)
    count = height(T);
else
    count = 0;
end
end

function localReconcileLiveStageControlAttemptCounts(runFolder)
runFolder = char(string(runFolder));
statusPaths = [
    string(fullfile(runFolder, "reports", "csv", "live_stage_status.csv"));
    string(fullfile(runFolder, "air_interface", "reports", "csv", "live_stage_status.csv"))];
signals = ["PBCH", "PRACH", "SRS", "TRS"];
for iPath = 1:numel(statusPaths)
    statusPath = statusPaths(iPath);
    if exist(statusPath, "file") ~= 2
        continue;
    end
    T = localReadOptionalTable(statusPath);
    if ~(istable(T) && ~isempty(T))
        continue;
    end
    changed = false;
    for iSig = 1:numel(signals)
        sig = signals(iSig);
        colName = char(sig + "AttemptCount");
        if ~ismember(colName, string(T.Properties.VariableNames))
            T.(colName) = zeros(height(T), 1);
            changed = true;
        end
        observed = localObservedControlAttemptCount(runFolder, sig);
        if observed <= 0
            continue;
        end
        current = double(T.(colName));
        current(~isfinite(current)) = 0;
        updated = max(current, observed);
        if any(abs(updated - current) > 0)
            T.(colName) = updated;
            changed = true;
        end
    end
    if changed
        sixgr.util.csvWriteTable(statusPath, T);
    end
end
end

function count = localObservedControlAttemptCount(runFolder, signalName)
signalName = lower(string(signalName));
fileName = signalName + "_trials.csv";
candidatePaths = [
    string(fullfile(runFolder, "air_interface", "csv", fileName));
    string(fullfile(runFolder, "control", "csv", fileName));
    string(fullfile(runFolder, "reference_signals", "csv", fileName));
    string(fullfile(runFolder, "reports", "csv", fileName))];
count = 0;
for iPath = 1:numel(candidatePaths)
    count = max(count, localCSVDataRowCount(candidatePaths(iPath)));
end
end

function count = localCSVDataRowCount(pathStr)
count = 0;
pathStr = char(string(pathStr));
if exist(pathStr, "file") ~= 2
    return;
end
try
    T = localReadOptionalTable(pathStr);
    if istable(T)
        count = max(count, height(T));
    end
catch
end
if count > 0
    return;
end
fid = fopen(pathStr, "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid));
lineCount = 0;
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    lineCount = lineCount + 1;
end
count = max(lineCount - 1, 0);
end

function out = localSafeDivide(num, den)
num = double(num);
den = double(den);
if isfinite(num) && isfinite(den) && den ~= 0
    out = num / den;
else
    out = NaN;
end
end

function out = localCorrelation(x, y)
x = double(x(:));
y = double(y(:));
keep = isfinite(x) & isfinite(y);
x = x(keep);
y = y(keep);
if numel(x) < 2 || std(x) == 0 || std(y) == 0
    out = NaN;
    return;
end
x = x - mean(x);
y = y - mean(y);
out = sum(x .* y) / sqrt(sum(x .^ 2) * sum(y .^ 2));
end

function vals = localReplaceNaN(vals, replacement)
vals(~isfinite(vals)) = replacement;
end

function p = localPercentile(vals, pct)
vals = sort(double(vals(:)));
vals = vals(isfinite(vals));
if isempty(vals)
    p = NaN;
    return;
end
idx = 1 + (numel(vals) - 1) * double(pct) / 100;
lo = floor(idx);
hi = ceil(idx);
if lo == hi
    p = vals(lo);
else
    frac = idx - lo;
    p = vals(lo) * (1 - frac) + vals(hi) * frac;
end
end

function v = localScenarioGet(scfg, path, defaultValue)
try
    v = scfg.get(path, defaultValue);
catch
    v = defaultValue;
end
end

function v = localScenarioStructGet(cfg, paths, defaultValue)
v = defaultValue;
for i = 1:numel(paths)
    tmp = sixgr.util.structGet(cfg, paths{i}, defaultValue);
    if ~(ischar(tmp) && isempty(tmp)) && ~(isstring(tmp) && all(strlength(tmp) == 0)) && ~(isnumeric(tmp) && all(~isfinite(tmp)))
        v = tmp;
        return;
    end
end
end

function row = localFirstRow(T)
if istable(T) && ~isempty(T)
    row = T(1, :);
else
    row = table();
end
end

function tf = localHasVar(T, varName)
tf = istable(T) && ismember(varName, string(T.Properties.VariableNames));
end

function val = localTableValue(T, varName, defaultValue)
val = defaultValue;
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    return;
end
raw = T.(varName);
if iscell(raw)
    raw = raw{1};
elseif ~isscalar(raw)
    raw = raw(1);
end
if isstring(raw)
    raw = raw(1);
end
val = raw;
end

function [frameVal, slotVal] = localGrantFrameSlotRow(T, tti, slotsPerFrame)
frameVal = localFirstNumericTableValue(T, ["Frame", "SFN"], NaN);
slotVal = localFirstNumericTableValue(T, ["Slot"], NaN);
if (~isfinite(frameVal) || ~isfinite(slotVal)) && isfinite(double(tti)) && isfinite(double(slotsPerFrame)) && double(slotsPerFrame) > 0
    [frameVal, slotVal] = localTTIToFrameSlot(tti, slotsPerFrame);
end
end

function timestampMs = localGrantTimestampMsRow(T)
timestampMs = localFirstNumericTableValue(T, ["TimestampSim_ms", "Time_ms"], NaN);
if ~isfinite(timestampMs)
    timeSec = localFirstNumericTableValue(T, ["Time_s"], NaN);
    if isfinite(timeSec)
        timestampMs = 1e3 * timeSec;
    end
end
end

function val = localNumericTableValue(T, varName, defaultValue)
raw = localTableValue(T, varName, defaultValue);
if ischar(raw) || isstring(raw) || iscategorical(raw)
    val = str2double(string(raw));
else
    try
        val = double(raw);
    catch
        val = str2double(string(raw));
    end
end
if isempty(val)
    val = defaultValue;
else
    val = val(1);
end
if ~isfinite(double(val)) && isfinite(double(defaultValue))
    val = defaultValue;
end
end

function val = localFirstNumericTableValue(T, varNames, defaultValue)
val = defaultValue;
for i = 1:numel(varNames)
    tmp = localNumericTableValue(T, string(varNames(i)), defaultValue);
    if isfinite(double(tmp))
        val = tmp;
        return;
    end
end
end

function val = localFirstStringTableValue(T, varNames, defaultValue)
val = string(defaultValue);
for i = 1:numel(varNames)
    if ~ismember(string(varNames(i)), string(T.Properties.VariableNames))
        continue;
    end
    tmp = localTextTableValue(T, string(varNames(i)), "");
    if strlength(strtrim(tmp)) > 0
        val = tmp;
        return;
    end
end
end

function val = localTextTableValue(T, varName, defaultValue)
raw = localTableValue(T, varName, defaultValue);
if isempty(raw)
    val = string(defaultValue);
elseif ischar(raw)
    val = string(raw);
else
    val = string(raw(1));
end
end

function tf = localLogicalTableValue(T, varName, defaultValue)
raw = localTableValue(T, varName, defaultValue);
if islogical(raw)
    tf = logical(raw(1));
elseif isnumeric(raw)
    raw = double(raw(1));
    tf = isfinite(raw) && raw ~= 0;
else
    if ischar(raw)
        token = lower(strtrim(string(raw)));
    else
        token = lower(strtrim(string(raw(1))));
    end
    tf = token == "1" || token == "true" || token == "yes";
end
end

function arr = localColumnAsDouble(T, varName)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    arr = NaN(height(T), 1);
    return;
end
raw = T.(varName);
try
    arr = double(raw);
catch
    arr = nan(height(T), 1);
    for i = 1:height(T)
        arr(i) = str2double(string(raw(i)));
    end
end
end

function arr = localColumnAsReportedCQI(T, varName)
arr = localColumnAsDouble(T, varName);
if isempty(arr)
    return;
end
arr = double(sixgr.util.normalizeReportedCQI(arr));
end

function value = localNormalizeReportedCQIValue(valueIn)
value = double(sixgr.util.normalizeReportedCQI(valueIn));
end

function arr = localFirstAvailableColumnAsDouble(T, varNames)
arr = NaN(height(T), 1);
for i = 1:numel(varNames)
    name = string(varNames(i));
    if localHasVar(T, name)
        arr = localColumnAsDouble(T, name);
        return;
    end
end
end

function arr = localCoalesceColumnAsDouble(T, primaryVar, fallbackVar)
arr = localColumnAsDouble(T, primaryVar);
fallback = localColumnAsDouble(T, fallbackVar);
mask = ~isfinite(arr);
arr(mask) = fallback(mask);
end

function arr = localColumnAsText(T, varName)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    arr = strings(height(T), 1);
    return;
end
arr = string(T.(varName));
end

function arr = localColumnAsLogical(T, varName)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    arr = false(height(T), 1);
    return;
end
raw = T.(varName);
if islogical(raw)
    arr = logical(raw(:));
    return;
end
if isnumeric(raw)
    raw = double(raw(:));
    arr = isfinite(raw) & raw ~= 0;
    return;
end
arr = strcmpi(strtrim(string(raw(:))), "true") | strcmpi(strtrim(string(raw(:))), "yes") | strcmpi(strtrim(string(raw(:))), "1");
end

function idx = localStringGroupIndex(values)
values = string(values);
if isempty(values)
    idx = zeros(0, 1);
    return;
end
[~, ~, idx] = unique(values);
idx = double(idx(:));
end

function vals = localSelectColumn(T, mask, varName)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    vals = NaN(0, 1);
    return;
end
vals = double(T.(varName)(mask));
end

function mask = localColumnMatches(T, varName, value)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    mask = false(0, 1);
    return;
end
mask = localColumnAsDouble(T, varName) == double(value);
end

function mask = localColumnMatchesText(T, varName, token)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    mask = false(0, 1);
    return;
end
mask = strcmpi(string(T.(varName)), string(token));
end

function out = localRuntimeCount(T, varName, fallbackValue)
if istable(T) && ~isempty(T) && localHasVar(T, varName)
    out = numel(unique(localColumnAsDouble(T, varName)));
else
    out = fallbackValue;
end
end

function out = localMeanFromMask(T, mask, varargin)
out = NaN;
if ~(istable(T) && ~isempty(T) && any(mask))
    return;
end
vals = NaN(sum(mask), 0);
for i = 1:numel(varargin)
    if localHasVar(T, varargin{i})
        vals(:, end+1) = double(T.(varargin{i})(mask)); %#ok<AGROW>
    end
end
if isempty(vals)
    return;
end
out = mean(vals(:), "omitnan");
end

function out = localMaxFromMask(T, mask, varargin)
out = NaN;
if ~(istable(T) && ~isempty(T) && any(mask))
    return;
end
vals = [];
for i = 1:numel(varargin)
    if localHasVar(T, varargin{i})
        vals = [vals; double(T.(varargin{i})(mask))]; %#ok<AGROW>
    end
end
if isempty(vals)
    return;
end
out = max(vals, [], "omitnan");
end

function out = localMaskedCount(T, mask)
if ~(istable(T) && ~isempty(T))
    out = NaN;
    return;
end
out = sum(mask);
end

function out = localMaskedEventCount(T, mask, varName, token)
if ~(istable(T) && ~isempty(T) && localHasVar(T, varName))
    out = NaN;
    return;
end
out = sum(mask & strcmpi(string(T.(varName)), string(token)));
end

function out = localPRBLoadFraction(grants, cellId, meta)
if ~(istable(grants) && ~isempty(grants))
    out = NaN;
    return;
end
mask = localColumnMatches(grants, "CellID", cellId);
if ~any(mask)
    out = 0;
    return;
end
used = double(grants.PRBCount(mask)) .* double(grants.NumSymbols(mask));
if ~isfinite(meta.symbols_per_slot) || meta.symbols_per_slot <= 0
    out = NaN;
    return;
end
gridRBs = max(double(grants.PRBStart(mask) + grants.PRBCount(mask)), [], "omitnan");
den = max(gridRBs * meta.symbols_per_slot * max(sum(mask), 1), 1);
out = sum(used, "omitnan") / den;
end

function out = localEdgeUECount(systemInterference, cellId)
out = NaN;
if ~(istable(systemInterference) && ~isempty(systemInterference))
    return;
end
mask = localColumnMatches(systemInterference, "ServingCell", cellId);
if ~any(mask)
    out = 0;
    return;
end
sinr = localColumnAsDouble(systemInterference(mask, :), "SINR_DL_dB");
out = sum(sinr < 3, "omitnan");
end

function txMap = localTxPowerByCell(systemSectors)
txMap = containers.Map("KeyType", "double", "ValueType", "double");
if ~(istable(systemSectors) && ~isempty(systemSectors) && localHasVar(systemSectors, "trp_id"))
    return;
end
cellIDs = localColumnAsDouble(systemSectors, "trp_id");
txVals = localColumnAsDouble(systemSectors, "max_tx_power_dbm");
for i = 1:numel(cellIDs)
    txMap(cellIDs(i)) = txVals(i);
end
end

function val = localMapLookup(mapObj, key, defaultValue)
if isa(mapObj, "containers.Map") && isKey(mapObj, double(key))
    val = mapObj(double(key));
else
    val = defaultValue;
end
end

function val = localLookupUEValue(T, ue, varName, defaultValue)
val = defaultValue;
if ~(istable(T) && ~isempty(T) && localHasVar(T, "UE") && localHasVar(T, varName))
    return;
end
mask = localColumnMatches(T, "UE", ue);
if any(mask)
    tmp = T.(varName)(find(mask, 1, "first"));
    try
        val = double(tmp);
    catch
        val = tmp;
    end
end
end

function out = localMeanGrantLayers(dlGrants, ulGrants, ue, cellId)
vals = [];
for T = {dlGrants, ulGrants}
    Ti = T{1};
    if ~(istable(Ti) && ~isempty(Ti) && localHasVar(Ti, "UE") && localHasVar(Ti, "CellID") && localHasVar(Ti, "NumLayers"))
        continue;
    end
    mask = localColumnMatches(Ti, "UE", ue) & localColumnMatches(Ti, "CellID", cellId);
    vals = [vals; double(Ti.NumLayers(mask))]; %#ok<AGROW>
end
if isempty(vals)
    out = NaN;
else
    out = mean(vals, "omitnan");
end
end

function dopplerHz = localSpeedToDopplerHz(speedKmh, carrierHz)
dopplerHz = NaN;
speedKmh = double(speedKmh);
carrierHz = double(carrierHz);
if ~(isfinite(speedKmh) && isfinite(carrierHz) && carrierHz > 0)
    return;
end
speedMs = speedKmh / 3.6;
dopplerHz = (speedMs / 299792458.0) * carrierHz;
end

function out = localPowerSumdBm(varargin)
vals = zeros(1, nargin);
count = 0;
for i = 1:nargin
    v = double(varargin{i});
    if isfinite(v)
        count = count + 1;
        vals(count) = 10^(v / 10);
    end
end
if count == 0
    out = NaN;
else
    out = 10 * log10(sum(vals(1:count)));
end
end

function modOrder = localModOrderFromText(token)
tok = upper(strtrim(char(string(token))));
switch tok
    case {"BPSK", "PI/2-BPSK"}
        modOrder = 1;
    case "QPSK"
        modOrder = 2;
    case "16QAM"
        modOrder = 4;
    case "64QAM"
        modOrder = 6;
    case "256QAM"
        modOrder = 8;
    otherwise
        modOrder = NaN;
end
end

function entityType = localNormalizeEntityType(entityType)
entityType = lower(strtrim(string(entityType)));
switch entityType
    case {"gnb", "cell"}
        entityType = "cell";
    case {"site"}
        entityType = "site";
    case {"ue"}
        entityType = "ue";
    otherwise
        entityType = "other";
end
end

function entityId = localResolveEnergyEntityID(row)
entityId = localTableValue(row, "EntityID", NaN);
if isfinite(entityId)
    return;
end
entityType = localNormalizeEntityType(localTableValue(row, "EntityType", localTableValue(row, "Entity", "")));
switch entityType
    case "ue"
        entityId = localTableValue(row, "UEID", localTableValue(row, "RNTI", NaN));
    case "site"
        entityId = localTableValue(row, "BaseStationID", NaN);
    otherwise
        entityId = localTableValue(row, "CellID", localTableValue(row, "BaseStationID", NaN));
end
end

function ms = localEnergyTimestampMs(row, meta)
ms = localTableValue(row, "TimestampSim_ms", NaN);
if isfinite(ms)
    return;
end
frameVal = double(localTableValue(row, "Frame", NaN));
slotVal = double(localTableValue(row, "Slot", NaN));
if isfinite(frameVal) && isfinite(slotVal) && isfinite(meta.slots_per_frame)
    numerology = localResolveNumerology(meta.scs_hz / 1e3);
    localValidateSlotsPerFrame(meta.slots_per_frame, numerology);
    slotDurationMs = double(numerology.SlotDurationMilliseconds);
    ms = ((frameVal - 1) * meta.slots_per_frame + (slotVal - 1)) * slotDurationMs;
else
    ms = NaN;
end
end

function frac = localEnergyActiveBWFraction(row, meta, cfg)
frac = double(localTableValue(row, "ActiveBWFraction", NaN));
if isfinite(frac)
    return;
end
prbCount = double(localTableValue(row, "PRBCount", NaN));
gridRB = double(localScenarioStructGet(cfg, {"frequency.n_size_grid", "resourceGrid.nSizeGrid"}, NaN));
if isfinite(prbCount) && isfinite(gridRB) && gridRB > 0
    frac = prbCount / gridRB;
else
    frac = NaN;
end
end

function out = localScheduledUEsForEnergy(systemCellLoad, row, direction)
out = NaN;
if ~(istable(systemCellLoad) && ~isempty(systemCellLoad) && localHasVar(systemCellLoad, "TTI") && localHasVar(systemCellLoad, "CellID"))
    return;
end
slotVal = double(localTableValue(row, "Slot", NaN));
cellVal = double(localTableValue(row, "CellID", NaN));
if ~(isfinite(slotVal) && isfinite(cellVal))
    return;
end
mask = localColumnMatches(systemCellLoad, "TTI", slotVal) & localColumnMatches(systemCellLoad, "CellID", cellVal);
if ~any(mask)
    return;
end
if direction == "DL"
    out = localMeanFromMask(systemCellLoad, mask, "ActiveUE_DL");
elseif direction == "UL"
    out = localMeanFromMask(systemCellLoad, mask, "ActiveUE_UL");
else
    out = localMeanFromMask(systemCellLoad, mask, "ActiveUE_DL", "ActiveUE_UL");
end
end

function val = localEnergyPerBit(energyJ, usefulBits)
energyJ = double(energyJ);
usefulBits = double(usefulBits);
if ~(isfinite(energyJ) && isfinite(usefulBits) && usefulBits > 0)
    val = NaN;
else
    val = 1e9 * energyJ / usefulBits;
end
end

function [frameVal, slotVal] = localTTIToFrameSlot(tti, slotsPerFrame)
frameVal = NaN;
slotVal = NaN;
tti = double(tti);
slotsPerFrame = double(slotsPerFrame);
if ~(isfinite(tti) && isfinite(slotsPerFrame) && slotsPerFrame > 0)
    return;
end
frameVal = floor((tti - 1) / slotsPerFrame) + 1;
slotVal = mod(tti - 1, slotsPerFrame) + 1;
end

function out = localScalarToString(val)
if isstring(val) || ischar(val)
    out = string(val);
elseif islogical(val)
    out = string(double(val));
elseif isnumeric(val)
    if isscalar(val)
        out = string(val);
    else
        out = strjoin(string(val(:).'), "|");
    end
else
    out = string(val);
end
end

function out = localValuesEqual(a, b)
if isnumeric(a) || islogical(a)
    out = isfinite(double(b)) && abs(double(a) - double(b)) < 1e-6 * max(abs(double(a)), 1);
else
    out = strcmpi(strtrim(char(string(a))), strtrim(char(string(b))));
end
end

function out = localTernary(cond, trueVal, falseVal)
if cond
    out = trueVal;
else
    out = falseVal;
end
end

function values = localStringColumn(value, n)
n = max(0, round(double(n)));
values = strings(n, 1);
if n > 0
    values(:) = string(value);
end
end

function tf = localAsBoolScalar(value, defaultValue)
if nargin < 2
    defaultValue = false;
end
if isempty(value)
    tf = logical(defaultValue);
    return;
end
if islogical(value)
    tf = logical(value(1));
elseif isnumeric(value)
    v = double(value(1));
    tf = isfinite(v) && v ~= 0;
else
    token = lower(strtrim(string(value)));
    if isempty(token) || strlength(token(1)) == 0
        tf = logical(defaultValue);
    else
        tf = any(token(1) == ["1","true","yes","pass","passed","ok"]);
    end
end
end

function out = localPortablePath(pathIn)
out = replace(string(pathIn), "\", "/");
end

function slotsPerFrame = localDeriveSlotsPerFrame(scsKHz)
if ~(isscalar(scsKHz) && isfinite(double(scsKHz)) && double(scsKHz) > 0)
    slotsPerFrame = NaN;
else
    numerology = localResolveNumerology(scsKHz);
    slotsPerFrame = double(numerology.SlotsPerFrame);
end
end

function mu = localDeriveNumerologyMu(scsKHz)
if ~(isscalar(scsKHz) && isfinite(double(scsKHz)) && double(scsKHz) > 0)
    mu = NaN;
    return;
end
numerology = localResolveNumerology(scsKHz);
mu = double(numerology.Mu);
end

function numerology = localResolveNumerology(scsKHz)
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    double(scsKHz), "normal", "generic_waveform_test", "");
end

function localValidateSlotsPerFrame(slotsPerFrame, numerology)
if double(slotsPerFrame) ~= double(numerology.SlotsPerFrame)
    error("sixgr:truth:exportLLSOutputCoverageArtifacts:NumerologyMismatch", ...
        "Persisted SlotsPerFrame=%g conflicts with the canonical value %g for SCS=%g kHz.", ...
        double(slotsPerFrame), double(numerology.SlotsPerFrame), ...
        double(numerology.SubcarrierSpacingKHz));
end
end

function out = localFirstFinite(vals)
vals = double(vals);
vals = vals(isfinite(vals));
if isempty(vals)
    out = NaN;
else
    out = vals(1);
end
end

function strs = localStringFromMask(mask, trueValue, falseValue)
strs = repmat(string(falseValue), numel(mask), 1);
strs(mask) = string(trueValue);
end

function T = localReadOptionalTable(pathStr)
T = table();
if exist(pathStr, "file") ~= 2
    return;
end
try
    opts = detectImportOptions(pathStr, "Delimiter", ",");
    opts.VariableNamingRule = "preserve";
    T = readtable(pathStr, opts);
catch
    T = table();
end
end

function T = localReadFirstOptionalTable(varargin)
T = table();
for i = 1:nargin
    Ti = localReadOptionalTable(varargin{i});
    if istable(Ti) && ~isempty(Ti)
        T = Ti;
        return;
    end
end
end
