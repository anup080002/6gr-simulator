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
localCoverageLog("sources_loaded", runFolder);

tables = struct();
tables.table_scenario_topology = localBuildScenarioTopologyTable(src, meta, scfg);
tables.scenario_consistency_check_table = localBuildScenarioConsistencyCheckTable(src, meta, scfg);
tables.topology_density_table = localBuildTopologyDensityTable(src, meta, scfg);
tables.sector_utilization_summary_table = localBuildSectorUtilizationSummaryTable(src, meta);
tables.serving_cell_population_table = localBuildServingCellPopulationTable(src, meta);
tables.table_gnb_cell = localBuildGNBCellTable(src, meta, cfg);
tables.table_channel_summary = localBuildChannelSummaryTable(src, meta, cfg);
tables.table_noise_interference = localBuildNoiseInterferenceTable(src, meta, cfg);
tables.table_link_budget = localBuildLinkBudgetTable(src, meta, cfg);
localCoverageLog("tables_core_topology_channel_built", runFolder);
localCoverageLog("building_live_prb_allocation", runFolder);
tables.live_prb_allocation = localBuildPRBAllocationTable(src, meta);
localCoverageLog("built_live_prb_allocation", runFolder);
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
tables.pucch_table = localBuildRuntimeMirrorTable(src.PUCCHTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/pucch_trials.csv|air_interface/csv/pucch_trials.csv", ...
    "runtime_control_trial_rows", "UL");
tables.pusch_table = localBuildRuntimeMirrorTable(src.ULTrials, meta, ...
    "sixgr.link.runULPUSCHThroughput", "air_interface/csv/ul_pusch_trials.csv", ...
    "runtime_air_interface_trial_rows", "UL");
tables.pdsch_table = localBuildRuntimeMirrorTable(src.DLTrials, meta, ...
    "sixgr.link.runDLPDSCHThroughput", "air_interface/csv/dl_pdsch_trials.csv", ...
    "runtime_air_interface_trial_rows", "DL");
tables.srs_table = localBuildRuntimeMirrorTable(src.SRSTrials, meta, ...
    "sixgr.truth.exportControlPlaneTraces", "control/csv/srs_trials.csv|air_interface/csv/srs_trials.csv", ...
    "runtime_reference_signal_trial_rows", "UL");
tables.csi_rs_table = localBuildRuntimeMirrorTable(src.CSIRSTrials, meta, ...
    "sixgr.link.runDLPDSCHThroughput", "air_interface/csv/csi_rs_trials.csv", ...
    "runtime_reference_signal_trial_rows", "DL");
tables.trs_receiver_tracking_table = localBuildRuntimeMirrorTable(src.ReceiverTrackingTrace, meta, ...
    "sixgr.truth.CoupledTruthRuntime.writeTables", "reports/csv/live_receiver_tracking_trace.csv", ...
    "runtime_receiver_tracking_trace_rows", "DL");
localCoverageLog("tables_control_built", runFolder);
tables.beam_precoder_table = localBuildBeamPrecoderTable(src, meta);
tables.beamforming_analytics_table = localBuildBeamformingAnalyticsTable(tables.beam_precoder_table, meta);
tables.mimo_rank_utilization_table = localBuildMIMORankUtilizationTable(tables.beam_precoder_table, meta);
tables.rank_layer_usage_histogram = localBuildRankLayerUsageHistogram(tables.mimo_rank_utilization_table, meta);
tables.timing_synchronization_table = localBuildTimingSynchronizationTable(src, meta);
tables.doppler_time_variation_plot = localBuildDopplerTimeVariationTable(src, meta);
localCoverageLog("tables_beam_timing_built", runFolder);
localCoverageLog("tables_built", runFolder);

logicalPaths = struct( ...
    "table_scenario_topology", "reports/csv/table_scenario_topology.csv", ...
    "scenario_consistency_check_table", "reports/csv/scenario_consistency_check_table.csv", ...
    "topology_density_table", "reports/csv/topology_density_table.csv", ...
    "sector_utilization_summary_table", "reports/csv/sector_utilization_summary_table.csv", ...
    "serving_cell_population_table", "reports/csv/serving_cell_population_table.csv", ...
    "table_gnb_cell", "reports/csv/table_gnb_cell.csv", ...
    "table_channel_summary", "reports/csv/table_channel_summary.csv", ...
    "table_noise_interference", "reports/csv/table_noise_interference.csv", ...
    "table_link_budget", "reports/csv/table_link_budget.csv", ...
    "doppler_time_variation_plot", "reports/csv/doppler_time_variation_plot.csv", ...
    "table_scheduler_decision", "packet_flow/csv/table_scheduler_decision.csv", ...
    "live_prb_allocation", "packet_flow/csv/live_prb_allocation.csv", ...
    "prb_allocation_heatmap", "reports/csv/prb_allocation_heatmap.csv", ...
    "dl_resource_grid_heatmap", "reports/csv/dl_resource_grid_heatmap.csv", ...
    "ul_resource_grid_heatmap", "reports/csv/ul_resource_grid_heatmap.csv", ...
    "table_dl_transport_block", "reports/csv/table_dl_transport_block.csv", ...
    "table_ul_transport_block", "reports/csv/table_ul_transport_block.csv", ...
    "table_harq_process", "reports/csv/table_harq_process.csv", ...
    "table_cqi_pmi_ri", "reports/csv/table_cqi_pmi_ri.csv", ...
    "table_mcs_tbs_evolution", "reports/csv/table_mcs_tbs_evolution.csv", ...
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
    "timing_synchronization_table", "control/csv/timing_synchronization_table.csv");

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

[registry, unavailable] = localBuildCoverageRegistry(runFolder, meta, src, tables, logicalPaths, heatmapImagePath, energyImagePath);
localCoverageLog("coverage_registry_built", runFolder);
completeness = localBuildOutputCompletenessTable(runFolder, registry, tables, logicalPaths, meta);
instrumentation = localBuildInstrumentationCoverageTable(registry, meta);
apiAudit = localBuildAPIExposureAuditTable(registry, meta);
persistence = localBuildPersistenceAuditTable(runFolder, registry, logicalPaths, meta);
localCoverageLog("coverage_audits_built", runFolder);

localWriteTableArtifacts(runFolder, "reports/csv/output_coverage_registry.csv", registry);
localWriteTableArtifacts(runFolder, "reports/csv/output_completeness_table.csv", completeness);
localWriteTableArtifacts(runFolder, "reports/csv/instrumentation_coverage_table.csv", instrumentation);
localWriteTableArtifacts(runFolder, "reports/csv/api_exposure_audit_table.csv", apiAudit);
localWriteTableArtifacts(runFolder, "reports/csv/persistence_audit_table.csv", persistence);
localWriteTableArtifacts(runFolder, "reports/csv/honest_unavailable_registry.csv", unavailable);
localCoverageLog("coverage_tables_written", runFolder);

inventory = localBuildArtifactInventory(runFolder);
localWriteTableArtifacts(runFolder, "reports/csv/artifact_inventory.csv", inventory);
localCoverageLog("inventory_written", runFolder);

out = struct();
out.Tables = tables;
out.OutputCoverageRegistry = registry;
out.OutputCompletenessTable = completeness;
out.InstrumentationCoverageTable = instrumentation;
out.APIExposureAuditTable = apiAudit;
out.PersistenceAuditTable = persistence;
out.HonestUnavailableRegistry = unavailable;
out.UpdatedArtifactInventory = inventory;
out.ManifestUnavailableEntries = localManifestUnavailableEntries(unavailable);
localCoverageLog("done", runFolder);
end

function src = localLoadSourceTables(layout)
src = struct();
src.Deployment = localReadOptionalTable(fullfile(layout.ReportCSVDir, "deployment_layout_reference.csv"));
src.RuntimeOperatingMode = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
src.ScenarioSummary = localReadOptionalTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
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
src.EnergyTimeline = localReadOptionalTable(fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"));
src.EnergySummary = localReadOptionalTable(fullfile(layout.RFCSVDir, "probe_rf_energy.csv"));
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
end

function meta = localBuildRunMeta(runFolder, scfg, cfg, src)
storeState = sixgr.db.artifactStore("get_state");
summaryRow = localFirstRow(src.ScenarioSummary);
meta = struct();
meta.run_id = double(sixgr.util.structGet(storeState, "RunID", NaN));
meta.run_tag = string(sixgr.util.structGet(cfg, "run.runTag", ""));
meta.scenario_id = string(scfg.ScenarioID);
meta.scenario_variant_id = string(localScenarioGet(scfg, "meta.scenario_id", scfg.ScenarioID));
meta.scenario_name = string(localScenarioGet(scfg, "meta.scenario_name", localScenarioGet(scfg, "meta.description", scfg.ScenarioID)));
meta.config_hash = string(scfg.ConfigHash);
meta.code_commit = string(localTableValue(summaryRow, "CodeCommit", ""));
meta.seed = double(localScenarioGet(scfg, "simulation.random_seed", localTableValue(summaryRow, "RandomSeed", NaN)));
meta.drop_id = NaN;
meta.run_folder = string(runFolder);
carrierDefaultHz = double(localScenarioStructGet(cfg, {"frequency.center_frequency_hz", "global_radio_scope.carrier_frequency_hz", "radio.center_frequency_hz"}, NaN));
bandwidthDefaultHz = double(localScenarioStructGet(cfg, {"frequency.bandwidth_hz", "global_radio_scope.channel_bandwidth_hz", "radio.bandwidth_hz"}, NaN));
meta.carrier_frequency_hz = double(localScenarioGet(scfg, "global_radio_scope.carrier_frequency_hz", localScenarioGet(scfg, "frequency.center_frequency_hz", carrierDefaultHz)));
meta.bandwidth_hz = double(localScenarioGet(scfg, "global_radio_scope.channel_bandwidth_hz", localScenarioGet(scfg, "frequency.bandwidth_hz", bandwidthDefaultHz)));
meta.scs_hz = 1e3 * double(localTableValue(summaryRow, "SCS_kHz", localScenarioGet(scfg, "frame.scs_khz", 30)));
meta.slots_per_frame = double(localTableValue(summaryRow, "SlotsPerFrame", localDeriveSlotsPerFrame(meta.scs_hz / 1e3)));
meta.symbols_per_slot = double(localTableValue(summaryRow, "SymbolsPerSlot", 14));
meta.tdd_pattern = string(localTableValue(summaryRow, "ConfiguredTDDPattern", localScenarioGet(scfg, "frame_timing.tdd_pattern_name", "")));
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
checks = {
    "num_sites_exact", 19, localTableValue(topology, "num_sites", NaN), "deployment_layout_reference";
    "sectors_per_site_exact", 3, localTableValue(topology, "sectors_per_site", NaN), "deployment_layout_reference";
    "total_cells_exact", 57, localTableValue(topology, "total_cells", NaN), "deployment_layout_reference";
    "num_ues_exact", 100, localTableValue(topology, "num_ues", NaN), "deployment_layout_reference";
    "carrier_frequency_hz_exact", 4.0e9, localTableValue(topology, "carrier_frequency_hz", NaN), "resolved_config";
    "bandwidth_hz_exact", 100.0e6, localTableValue(topology, "bandwidth_hz", NaN), "resolved_config";
    "scs_hz_exact", 30.0e3, localTableValue(topology, "scs_hz", NaN), "scenario_summary";
    "wraparound_enabled", 1, double(localTableValue(topology, "wraparound_enable", false)), "resolved_config";
    "inter_cell_interference_enabled", 1, double(logical(localScenarioGet(scfg, "interference.inter_cell_interference_flag", true))), "resolved_config";
    "deployment_scenario_uma", "UMa", localTableValue(topology, "deployment_scenario", ""), "resolved_config";
    "tdd_pattern_baseline", "DDDDU", localTableValue(topology, "tdd_pattern", ""), "scenario_summary";
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
servingCells = unique(localColumnAsDouble(src.SystemInterference, "ServingCell"));
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
    rows(i).edge_ue_count = localEdgeUECount(src.SystemInterference, cellId);
    rows(i).mean_dl_sinr_db = localMeanFromMask(src.SystemInterference, mask, "SINR_DL_dB");
    rows(i).mean_ul_sinr_db = localMeanFromMask(src.SystemInterference, mask, "SINR_UL_dB");
    rows(i).mean_rsrp_dbm = localMeanFromMask(src.SystemInterference, mask, "RSRP_dBm");
    rows(i).mean_pathloss_db = localMeanFromMask(src.SystemInterference, mask, "Pathloss_dB");
    rows(i).population_value_source = "system/csv/system_interference_detail.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildServingCellPopulationTable", ...
    "system/csv/system_interference_detail.csv", "implemented", "derived_runtime_serving_cell_population", true, true);
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
    rows(i).active_ues_peak = localMaxFromMask(src.SystemCellLoad, loadMask, "ActiveUE_DL", "ActiveUE_UL");
    rows(i).dl_load_avg = localPRBLoadFraction(src.DLGrants, cellId, meta);
    rows(i).ul_load_avg = localPRBLoadFraction(src.ULGrants, cellId, meta);
    rows(i).avg_rsrp_dBm = localMeanFromMask(src.SystemInterference, intrMask, "RSRP_dBm");
    rows(i).avg_sinr_dB = localMeanFromMask(src.SystemInterference, intrMask, "SINR_DL_dB", "SINR_UL_dB");
    rows(i).edge_ue_count = localEdgeUECount(src.SystemInterference, cellId);
    rows(i).handover_in_count = localMaskedCount(src.SystemHandover, hoInMask);
    rows(i).handover_out_count = localMaskedCount(src.SystemHandover, hoOutMask);
    rows(i).beam_failure_count = localMaskedEventCount(src.SystemBeam, beamMask, "EventType", "beam_failure");
    rows(i).scheduler_type = string(localScenarioStructGet(cfg, {"system.scheduler.type"}, ""));
    rows(i).energy_state_primary = "";
    rows(i).control_overhead_fraction = NaN;
    rows(i).status_source = string("runtime_aggregated_from_system_level_tables");
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildGNBCellTable", ...
    "system/tables/sectors.csv", "implemented", "runtime_aggregated", true, true);
end

function T = localBuildChannelSummaryTable(src, meta, cfg)
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    T = table();
    return;
end
ueVals = unique(localColumnAsDouble(src.SystemInterference, "UE"));
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
    servedTx = localMapLookup(txPower, servingCell, NaN);
    speedKmh = localLookupUEValue(src.SystemUE, ue, "Speed_kmh", NaN);
    rows(i).ue_id = ue;
    rows(i).cell_id = servingCell;
    rows(i).los_flag = NaN;
    rows(i).o2i_flag = localLookupUEValue(src.SystemUE, ue, "Indoor", NaN);
    rows(i).pathloss_dB = localMeanFromMask(src.SystemInterference, mask, "Pathloss_dB");
    rows(i).coupling_loss_dB = localMeanFromMask(src.SystemInterference, mask, "RxPower_dBm");
    if isfinite(servedTx) && isfinite(rows(i).coupling_loss_dB)
        rows(i).coupling_loss_dB = servedTx - rows(i).coupling_loss_dB;
    else
        rows(i).coupling_loss_dB = NaN;
    end
    rows(i).shadow_fading_dB = NaN;
    rows(i).delay_spread_ns = NaN;
    rows(i).asa_deg = NaN;
    rows(i).asd_deg = NaN;
    rows(i).zsa_deg = NaN;
    rows(i).zsd_deg = NaN;
    rows(i).doppler_hz = localSpeedToDopplerHz(speedKmh, meta.carrier_frequency_hz);
    rows(i).k_factor_dB = NaN;
    rows(i).channel_rank_est = localMeanGrantLayers(src.DLGrants, src.ULGrants, ue, servingCell);
    rows(i).spatial_consistency_state = string(localTernary(logical(localScenarioStructGet(cfg, {"channel.spatialConsistencyEnable"}, false)), "enabled", "disabled"));
    rows(i).update_period_ms = double(localScenarioStructGet(cfg, {"channel.updatePeriod_ms", "channel.largeScaleUpdatePeriod_ms"}, NaN));
    rows(i).channel_tensor_ref = "";
    rows(i).source_backend_object = "system/csv/system_interference_detail.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildChannelSummaryTable", ...
    "system/csv/system_interference_detail.csv", "implemented", "runtime_aggregated", true, true);
end

function T = localBuildNoiseInterferenceTable(src, meta, cfg)
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    T = table();
    return;
end
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
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildNoiseInterferenceTable", ...
    "system/csv/system_interference_detail.csv", "implemented", "runtime_timeseries", false, true);
end

function T = localBuildLinkBudgetTable(src, meta, cfg)
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    T = table();
    return;
end
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
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildLinkBudgetTable", ...
    "system/csv/system_interference_detail.csv", "implemented", "runtime_timeseries", true, true);
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
frameVal = NaN(n, 1);
slotVal = NaN(n, 1);
validTTI = isfinite(tti) & isfinite(slotsPerFrame) & slotsPerFrame > 0;
frameVal(validTTI) = floor((tti(validTTI) - 1) ./ slotsPerFrame) + 1;
slotVal(validTTI) = mod(tti(validTTI) - 1, slotsPerFrame) + 1;

directionCol = repmat(string(direction), n, 1);
isRetx = localColumnAsLogical(grants, "IsRetransmission");
occupancyType = repmat("scheduled_allocation", n, 1);
occupancyType(isRetx) = "retransmission";

T = table();
T.timestamp_sim_ms = 1e3 * localColumnAsDouble(grants, "Time_s");
T.frame = frameVal;
T.slot = slotVal;
T.symbol_start = localColumnAsDouble(grants, "SymbolStart");
T.symbol_len = localColumnAsDouble(grants, "NumSymbols");
T.cell_id = localColumnAsDouble(grants, "CellID");
T.ue_id = localColumnAsDouble(grants, "UE");
T.direction = directionCol;
T.bwp_id = localColumnAsDouble(grants, "BWPId");
T.rb_start = localColumnAsDouble(grants, "PRBStart");
T.rb_len = localColumnAsDouble(grants, "PRBCount");
T.num_prbs = localColumnAsDouble(grants, "PRBCount");
T.beam_id = NaN(n, 1);
T.rank = localColumnAsDouble(grants, "NumLayers");
T.layers = localColumnAsDouble(grants, "NumLayers");
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
offsetCells = arrayfun(@(n) (0:(n-1)).', rbLen, 'UniformOutput', false);
offsets = vertcat(offsetCells{:});
T = table();
T.cell_id = repmat(bestCell, numel(rowIdx), 1);
T.direction = repmat(bestDir, numel(rowIdx), 1);
T.frame = frameVals(rowIdx);
T.slot = slotVals(rowIdx);
T.rb_index = rbStart(rowIdx) + offsets;
T.occupancy_count = symLen(rowIdx);
T.occupancy_fraction = symLen(rowIdx) / max(meta.symbols_per_slot, 1);
T.selected_heatmap_flag = true(numel(rowIdx), 1);
T.source_artifact_ref = repmat("packet_flow/csv/live_prb_allocation.csv", numel(rowIdx), 1);
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
    [frameVal, slotVal] = localTTIToFrameSlot(tti, meta.slots_per_frame);
    rows(i).timestamp_sim_ms = 1e3 * localNumericTableValue(row, "Time_s", NaN);
    rows(i).frame = frameVal;
    rows(i).slot = slotVal;
    rows(i).scheduler_cycle_id = tti;
    rows(i).decision_id = string(direction) + "_grant_" + string(i);
    rows(i).decision_scope = "selected_grant_only";
    rows(i).candidate_decision_rows_available = false;
    rows(i).decision_truth_status = "selected_grant_runtime_truth";
    rows(i).direction = string(direction);
    rows(i).cell_id = localNumericTableValue(row, "CellID", NaN);
    rows(i).ue_id = localNumericTableValue(row, "UE", NaN);
    rows(i).grant_reason = localTextTableValue(row, "GrantReason", "");
    rows(i).selected_flag = true;
    rows(i).rejected_flag = false;
    rows(i).prb_start = localNumericTableValue(row, "PRBStart", NaN);
    rows(i).prb_count = localNumericTableValue(row, "PRBCount", NaN);
    rows(i).symbol_start = localNumericTableValue(row, "SymbolStart", NaN);
    rows(i).num_symbols = localNumericTableValue(row, "NumSymbols", NaN);
    rows(i).mcs_index = localNumericTableValue(row, "MCSIndex", NaN);
    rows(i).wideband_cqi = localNumericTableValue(row, "CQIUsed", NaN);
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
offsetCells = arrayfun(@(n) (0:(n-1)).', rbLen, 'UniformOutput', false);
offsets = vertcat(offsetCells{:});
T = table();
T.cell_id = cellIds(rowIdx);
T.direction = repmat(direction, numel(rowIdx), 1);
T.frame = frameVals(rowIdx);
T.slot = slotVals(rowIdx);
T.rb_index = rbStart(rowIdx) + offsets;
T.occupancy_count = symLen(rowIdx);
T.occupancy_fraction = symLen(rowIdx) / max(meta.symbols_per_slot, 1);
T.source_artifact_ref = repmat("packet_flow/csv/live_prb_allocation.csv", numel(rowIdx), 1);
key = string(T.cell_id) + "|" + string(T.direction) + "|" + string(T.frame) + "|" + string(T.slot) + "|" + string(T.rb_index);
[~, firstIdx, keyIdx] = unique(key);
base = T(firstIdx, :);
base.occupancy_count = accumarray(keyIdx, double(T.occupancy_count), [], @sum);
base.occupancy_fraction = accumarray(keyIdx, double(T.occupancy_fraction), [], @sum);
T = base;
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildDirectionalGridHeatmapTable", ...
    "packet_flow/csv/live_prb_allocation.csv", "implemented", "derived_from_prb_rows", true, true);
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
    finiteComponents = components(isfinite(components));
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
    rows(i).latency_ms = localTernary(~isempty(finiteComponents), sum(finiteComponents), NaN);
    rows(i).latency_value_role = "measured";
    rows(i).latency_value_status = localTernary(isfinite(rows(i).latency_ms), "OK", "NOT_AVAILABLE");
    rows(i).latency_value_definition = "sum of persisted runtime latency components in the air-interface trial row";
    rows(i).source_artifact_ref = string(sourceRef);
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
for i = 1:height(subset)
    comps = [double(subset.compute_latency_ms(i)), double(subset.decode_latency_ms(i)), ...
        double(subset.procedure_delay_ms(i)), double(subset.air_interface_tti_ms(i)), ...
        double(subset.air_interface_observation_ms(i))];
    labels = ["compute_latency_ms", "decode_latency_ms", "procedure_delay_ms", "air_interface_tti_ms", "air_interface_observation_ms"];
    [~, idx] = max(localReplaceNaN(comps, -Inf));
    rows(i).direction = string(subset.direction(i));
    rows(i).ue_id = double(subset.ue_id(i));
    rows(i).cell_id = double(subset.cell_id(i));
    rows(i).latency_ms = double(subset.latency_ms(i));
    rows(i).latency_threshold_ms = threshold;
    rows(i).dominant_component = labels(idx);
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
if ~(istable(src.SystemHARQ) && ~isempty(src.SystemHARQ))
    T = table();
    return;
end
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
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildHARQProcessTable", ...
    "system/csv/system_harq_processes.csv", "implemented", "runtime_aggregated", true, true);
end

function T = localBuildCQIPMIRITable(src, meta)
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "report_id", NaN, ...
    "report_type", "", "wideband_cqi", NaN, "subband_cqi_vector_ref", "", "pmi", NaN, "ri", NaN, ...
    "csi_age_ms", NaN, "report_size_bits", NaN, "report_trigger", "", "based_on", "", ...
    "feedback_delay_ms", NaN, "direction", ""), 0, 1);
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
T.timestamp_sim_ms = 1e3 * localColumnAsDouble(grants, "Time_s");
T.ue_id = localColumnAsDouble(grants, "UE");
T.cell_id = localColumnAsDouble(grants, "CellID");
T.direction = repmat(string(direction), n, 1);
T.cqi_input = localColumnAsDouble(grants, "CQIUsed");
T.ri_input = NaN(n, 1);
T.pmi_input = NaN(n, 1);
T.mcs_selected = localColumnAsDouble(grants, "MCSIndex");
T.mod_order = NaN(n, 1);
T.code_rate = localColumnAsDouble(grants, "TargetCodeRate");
T.tbs_bits = localColumnAsDouble(grants, "TBSBits");
T.olla_offset = NaN(n, 1);
T.harq_state = harqState;
T.scheduler_reason = localColumnAsText(grants, "GrantReason");
T.effective_sinr_dB = localColumnAsDouble(grants, "SINR_dB");
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
entityType = string(powerEnergyTable.entity_type(:));
entityID = double(powerEnergyTable.entity_id(:));
direction = string(powerEnergyTable.direction(:));
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
    totalEnergyJ = sum(double(subset.energy_increment_mJ), "omitnan") / 1e3;
    usefulBits = sum(double(subset.useful_bits), "omitnan");
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
    row.numerology = log2(max(meta.scs_hz / 15e3, 1));
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
    row.numerology = log2(max(meta.scs_hz / 15e3, 1));
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
row.numerology = log2(max(meta.scs_hz / 15e3, 1));
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
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    T = table();
    return;
end
rows = repmat(struct("ue_id", NaN, "cell_id", NaN, "direction", "", "symptom", "", ...
    "severity_score", NaN, "candidate_reason", "", "evidence_metric", "", "evidence_value", NaN, ...
    "source_artifact_ref", ""), 0, 1);
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
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = sortrows(T, "severity_score", "descend");
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRootCauseCandidateTable", ...
    "system/csv/system_interference_detail.csv", "implemented", "derived_root_cause_candidates", true, true);
end

function T = localBuildCellEdgeAnalyticsTable(src, meta)
if ~(istable(src.SystemUE) && ~isempty(src.SystemUE))
    T = table();
    return;
end
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
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildCellEdgeAnalyticsTable", ...
    "system/tables/system_ue_summary.csv", "implemented", "runtime_summary_slice", true, true);
end

function T = localBuildBeamStabilityAnalyticsTable(src, meta)
if ~(istable(src.SystemBeam) && ~isempty(src.SystemBeam))
    T = table();
    return;
end
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
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamStabilityAnalyticsTable", ...
    "system/csv/system_beam_events.csv", "implemented", "runtime_aggregated", true, true);
end

function T = localBuildEnergyRootCauseTable(powerEnergyTable, meta)
if ~(istable(powerEnergyTable) && ~isempty(powerEnergyTable))
    T = table();
    return;
end
entityType = string(powerEnergyTable.entity_type(:));
entityID = double(powerEnergyTable.entity_id(:));
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
    rows(i).entity_type = string(subset.entity_type(1));
    rows(i).entity_id = double(subset.entity_id(1));
    rows(i).total_energy_j = sum(double(subset.energy_increment_mJ), "omitnan") / 1e3;
    rows(i).useful_bits = sum(double(subset.useful_bits), "omitnan");
    rows(i).energy_per_bit_nj = localEnergyPerBit(rows(i).total_energy_j, rows(i).useful_bits);
    states = string(subset.state);
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
    rows(i).issue_id = string(issueRegistry.issue_id(i));
    rows(i).severity = string(issueRegistry.severity(i));
    rows(i).issue_category = string(issueRegistry.issue_category(i));
    rows(i).direction = string(issueRegistry.direction(i));
    rows(i).ue_id = double(issueRegistry.ue_id(i));
    rows(i).cell_id = double(issueRegistry.cell_id(i));
    rows(i).window_start_ms = double(localTableValue(issueRegistry(i, :), "timestamp_sim_ms", NaN));
    rows(i).window_end_ms = rows(i).window_start_ms;
    rows(i).anomaly_metric = string(issueRegistry.metric_name(i));
    rows(i).anomaly_evidence = string(issueRegistry.observed_value(i));
    rows(i).source_artifact_ref = string(issueRegistry.evidence_artifact_ref(i));
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
if ~(istable(src.SystemUE) && ~isempty(src.SystemUE))
    T = table();
    return;
end
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
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildHotspotAnalyticsTable", ...
    "system/csv/system_ue_summary.csv", "implemented", "derived_runtime_hotspot_summary", true, true);
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

function T = localBuildResultIssueRegistry(src, meta, tables)
rows = repmat(struct("issue_id", "", "severity", "", "issue_status", "", "issue_category", "", ...
    "direction", "", "ue_id", NaN, "cell_id", NaN, "block_name", "", "metric_name", "", ...
    "observed_value", "", "expected_or_policy", "", "evidence_artifact_ref", "", ...
    "root_cause_hint", "", "fix_plan", "", "analytics_visible_flag", true), 0, 1);

if istable(tables.root_cause_candidate_table) && ~isempty(tables.root_cause_candidate_table)
    for i = 1:height(tables.root_cause_candidate_table)
        row = tables.root_cause_candidate_table(i, :);
        severityScore = double(localTableValue(row, "severity_score", NaN));
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "low_sinr_window_" + string(i), ...
            localTernary(isfinite(severityScore) && severityScore >= 6, "high", "medium"), ...
            "REVIEW_REQUIRED", "channel_interference", ...
            string(localTableValue(row, "direction", "DL")), ...
            double(localTableValue(row, "ue_id", NaN)), ...
            double(localTableValue(row, "cell_id", NaN)), ...
            "channel/interference", string(localTableValue(row, "evidence_metric", "SINR")), ...
            string(localTableValue(row, "evidence_value", NaN)), ...
            "SINR should align with channel/interference truth and scheduler link adaptation", ...
            string(localTableValue(row, "source_artifact_ref", "system/csv/system_interference_detail.csv")), ...
            string(localTableValue(row, "candidate_reason", "low_sinr_window")), ...
            "Inspect channel model, interference contributors, CQI feedback, and grant MCS for this UE/cell.");
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
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "energy_without_useful_bits_" + string(i), "medium", "REVIEW_REQUIRED", "power_energy", ...
            string(localTableValue(row, "direction", "")), ...
            NaN, NaN, "power/energy", "energy_per_bit_nj", ...
            string(localTableValue(row, "total_energy_j", NaN)), ...
            "Energy-per-bit requires nonzero useful bits; otherwise keep the metric unavailable/review", ...
            "rf/csv/power_energy_table.csv", ...
            "Energy accumulated without useful-bit lineage", ...
            "Verify successful-bit lineage from MAC/PHY payload counters before reporting efficiency KPIs.");
    end
end

resultOk = localTableValue(localFirstRow(src.ScenarioSummary), "ResultOk", []);
requiredFailures = double(localTableValue(localFirstRow(src.ScenarioSummary), "RequiredFailureCount", NaN));
if ~isempty(resultOk) && ~localAsBoolScalar(resultOk, true)
    rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "run_result_not_ok", "critical", "CRASHED", "run_status", ...
        "", NaN, NaN, "run", "ResultOk", string(resultOk), ...
        "ResultOk may be true only when required cases truthfully pass", ...
        "reports/csv/scenario_summary.csv", ...
        "Scenario summary reports ResultOk=false", ...
        "Inspect required case failures, logs, and runtime truth-contract rows before accepting analytics.");
elseif isfinite(requiredFailures) && requiredFailures > 0
    rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "required_failures_present", "critical", "CRASHED", "run_status", ...
        "", NaN, NaN, "run", "RequiredFailureCount", string(requiredFailures), ...
        "RequiredFailureCount must be zero for a clean run", ...
        "reports/csv/scenario_summary.csv", ...
        "Required case failures were recorded", ...
        "Open the failed case table and fix the failing runtime path rather than masking result_ok.");
end

if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResultIssueRegistry", ...
    "reports/csv/result_issue_registry.csv", "review_required", "derived_issue_registry", true, true);
end

function rows = localAppendMCSIssueRows(rows, sourceTable, direction, sourceArtifactRef)
if ~(istable(sourceTable) && ~isempty(sourceTable))
    return;
end
for i = 1:height(sourceTable)
    row = sourceTable(i, :);
    mcs = double(localTableValue(row, "MCSIndex", NaN));
    cqiDerivedMCS = double(localTableValue(row, "CQIDerivedMCS", NaN));
    if ~isfinite(cqiDerivedMCS)
        cqiUsed = double(localTableValue(row, "CQIUsed", localTableValue(row, "WidebandCQI", NaN)));
        if isfinite(cqiUsed)
            mcsTable = string(localTableValue(row, "MCSTable", localTableValue(row, "MCS_Table", "qam64_table1")));
            cqiTable = string(localTableValue(row, "CQITable", localTableValue(row, "CQI_Table", "table1")));
            decision = sixgr.link.resolveMCSFromCQI(max(1, round(cqiUsed)), char(mcsTable), char(cqiTable));
            if isstruct(decision) && isfield(decision, "Valid") && decision.Valid
                cqiDerivedMCS = double(decision.MCSIndex);
            end
        end
    end
    if isfinite(mcs) && isfinite(cqiDerivedMCS) && mcs > cqiDerivedMCS + 1
        ue = double(localTableValue(row, "UE", localTableValue(row, "UEID", localTableValue(row, "RNTI", NaN))));
        cellID = double(localTableValue(row, "CellID", localTableValue(row, "ServingCell", NaN)));
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            lower(string(direction)) + "_mcs_above_cqi_" + string(i), ...
            "high", "REVIEW_REQUIRED", "link_adaptation", ...
            string(direction), ue, cellID, "scheduler/link_adaptation", ...
            "MCSIndex", "MCS=" + string(mcs) + ";CQIDerivedMCS=" + string(cqiDerivedMCS), ...
            "AMC mode should not exceed CQI-derived MCS without explicit, sourced override", ...
            string(sourceArtifactRef), ...
            "Selected MCS is higher than CQI-derived MCS", ...
            "Verify fixed-vs-AMC config, CQI source lineage, and scheduler MCS selection for this row.");
    end
    sinr = double(localTableValue(row, "MeasuredSINR_dB", localTableValue(row, "SINR_dB", NaN)));
    crcPass = localAsBoolScalar(localTableValue(row, "CRCPass", localTableValue(row, "Ack", [])), false);
    if strcmpi(string(direction), "UL") && isfinite(sinr) && sinr < 0 && crcPass
        ue = double(localTableValue(row, "UE", localTableValue(row, "UEID", localTableValue(row, "RNTI", NaN))));
        cellID = double(localTableValue(row, "CellID", localTableValue(row, "ServingCell", NaN)));
        rows(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "ul_low_sinr_crc_pass_" + string(i), "medium", "REVIEW_REQUIRED", "ul_receiver_semantics", ...
            "UL", ue, cellID, "PUSCH", "CRCPass", "SINR=" + string(sinr) + ";CRCPass=true", ...
            "Low-SINR UL successes must be backed by actual receiver/decoder evidence", ...
            string(sourceArtifactRef), ...
            "UL trial reports CRC pass at negative SINR", ...
            "Inspect channel-estimation, equalization, decoder evidence, and SINR definition before treating this as clean success.");
    end
end
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
n = height(T);
T = localAddCanonicalRuntimeAliases(T, directionDefault);
T = localAddMissingVar(T, "runtime_evidence", repmat("persisted_runtime_trial_row", n, 1));
T = localAddMissingVar(T, "runtime_evidence_source", repmat(string(sourceArtifactRef), n, 1));
T = localAddMissingVar(T, "output_family_materialization", repmat("runtime_backed_mirror", n, 1));
T = localFinalizeOutputTable(T, meta, producerModule, sourceArtifactRef, ...
    "implemented", statusClassification, false, true);
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
    "precoding_matrix_cols", NaN, "runtime_evidence", "", "source_artifact_ref", ""), n, 1);
end

function T = localBuildBeamformingAnalyticsTable(beamPrecoderTable, meta)
if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end
keys = string(beamPrecoderTable.direction) + "|" + string(beamPrecoderTable.cell_id) + "|" + string(beamPrecoderTable.ue_id);
[uniqueKeys, ~, keyIdx] = unique(keys);
rows = repmat(struct("direction", "", "cell_id", NaN, "ue_id", NaN, "trial_row_count", NaN, ...
    "beamforming_applied_count", NaN, "runtime_applied_beam_rows", NaN, ...
    "runtime_applied_pmi_rows", NaN, "beam_hit_rate", NaN, "mean_precoding_ports", NaN, ...
    "mean_precoding_layers", NaN, "analytics_value_source", ""), numel(uniqueKeys), 1);
for i = 1:numel(uniqueKeys)
    mask = keyIdx == i;
    subset = beamPrecoderTable(mask, :);
    beamTruth = string(subset.applied_beam_truth_classification);
    pmiTruth = string(subset.applied_precoder_pmi_truth_classification);
    hit = double(subset.beam_hit);
    rows(i).direction = string(subset.direction(1));
    rows(i).cell_id = double(subset.cell_id(1));
    rows(i).ue_id = double(subset.ue_id(1));
    rows(i).trial_row_count = height(subset);
    rows(i).beamforming_applied_count = sum(logical(subset.beamforming_applied));
    rows(i).runtime_applied_beam_rows = sum(beamTruth == "applied_runtime_value");
    rows(i).runtime_applied_pmi_rows = sum(pmiTruth == "applied_runtime_value");
    rows(i).beam_hit_rate = mean(hit(isfinite(hit)), "omitnan");
    rows(i).mean_precoding_ports = mean(double(subset.precoding_num_ports), "omitnan");
    rows(i).mean_precoding_layers = mean(double(subset.precoding_num_layers), "omitnan");
    rows(i).analytics_value_source = "beamforming/csv/beam_precoder_table.csv";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamformingAnalyticsTable", ...
    "beamforming/csv/beam_precoder_table.csv", "implemented", "derived_beamforming_analytics", true, true);
end

function T = localBuildMIMORankUtilizationTable(beamPrecoderTable, meta)
if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end
rankVals = double(beamPrecoderTable.precoding_num_layers);
dirVals = string(beamPrecoderTable.direction);
cellVals = double(beamPrecoderTable.cell_id);
[~, ~, dirIdx] = unique(dirVals);
groups = unique([double(dirIdx), cellVals, rankVals], "rows");
groups = groups(isfinite(groups(:, 1)) & isfinite(groups(:, 2)) & isfinite(groups(:, 3)), :);
if isempty(groups)
    T = table();
    return;
end
rows = repmat(struct("direction", "", "cell_id", NaN, "rank_or_layer_count", NaN, ...
    "trial_row_count", NaN, "utilization_fraction", NaN, "source_artifact_ref", ""), size(groups, 1), 1);
for i = 1:size(groups, 1)
    mask = dirIdx == groups(i, 1) & cellVals == groups(i, 2) & rankVals == groups(i, 3);
    dirMask = dirIdx == groups(i, 1) & cellVals == groups(i, 2);
    rows(i).direction = dirVals(find(mask, 1, "first"));
    rows(i).cell_id = groups(i, 2);
    rows(i).rank_or_layer_count = groups(i, 3);
    rows(i).trial_row_count = sum(mask);
    rows(i).utilization_fraction = localSafeDivide(sum(mask), sum(dirMask));
    rows(i).source_artifact_ref = "beamforming/csv/beam_precoder_table.csv";
end
T = struct2table(rows);
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
if ~(istable(src.SystemInterference) && ~isempty(src.SystemInterference))
    T = table();
    return;
end
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, ...
    "speed_kmh", NaN, "doppler_hz", NaN, "doppler_value_role", "", ...
    "doppler_value_source", "", "source_artifact_ref", ""), 0, 1);
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
if isempty(rows)
    T = table();
    return;
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildDopplerTimeVariationTable", ...
    "system/csv/system_interference_detail.csv|system/csv/system_ue_summary.csv", ...
    "implemented", "derived_doppler_time_variation", true, true);
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
    rows(i).estimated_timing_offset_pre_correction_samples = localNumericTableValue(row, "EstimatedTimingOffset_PreCorrection_samples", NaN);
    rows(i).residual_timing_error_post_correction_samples = localNumericTableValue(row, "ResidualTimingError_PostCorrection_samples", NaN);
    rows(i).true_timing_offset_samples = localNumericTableValue(row, "TrueTimingOffset_samples", NaN);
    rows(i).timing_error_samples = timingError;
    rows(i).timing_estimate_used = timingEstimateUsed;
    rows(i).use_ideal_timing_sync = useIdealTimingSync;
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
    "injected_timing_offset_samples", NaN, "estimated_timing_offset_pre_correction_samples", NaN, ...
    "residual_timing_error_post_correction_samples", NaN, "true_timing_offset_samples", NaN, ...
    "timing_error_samples", NaN, "timing_estimate_used", false, "use_ideal_timing_sync", false, ...
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
sixgr.util.csvWriteTable(csvPath, T);
jsonPath = replace(string(logicalPath), ".csv", ".json");
if jsonPath ~= string(logicalPath)
    sixgr.util.jsonWrite(fullfile(runFolder, jsonPath), table2struct(T));
end
end

function localCoverageLog(stepName, runFolder)
msg = "exportLLSOutputCoverageArtifacts:" + string(stepName) + " runFolder=" + string(runFolder);
if sixgr.db.isArtifactStoreActive()
    sixgr.db.appendRunLog("INFO", char(msg));
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
sixgr.util.ensureDir(filePath);
saveas(fig, filePath);
close(fig);
sixgr.db.captureFileArtifact(filePath, "figure", "image/png", false, logicalPath);
end

function localWritePowerEnergyFigure(T, filePath, logicalPath)
if ~(istable(T) && ~isempty(T))
    return;
end
mask = string(T.entity_type) == "cell" | string(T.entity_type) == "site";
if any(mask)
    T = T(mask, :);
end
entityType = string(T.entity_type(:));
entityID = double(T.entity_id(:));
validKeyRows = ~ismissing(entityType) & strlength(entityType) > 0 & isfinite(entityID);
if ~any(validKeyRows)
    return;
end
T = T(validKeyRows, :);
fig = figure("Visible", "off", "Color", "w");
hold on;
entityType = string(T.entity_type(:));
entityID = double(T.entity_id(:));
keys = unique(entityType + ":" + string(entityID));
for i = 1:numel(keys)
    key = keys(i);
    mask = (entityType + ":" + string(entityID)) == key;
    x = double(T.timestamp_sim_ms(mask));
    y = double(T.cumulative_energy_J(mask));
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
sixgr.util.ensureDir(filePath);
saveas(fig, filePath);
close(fig);
sixgr.db.captureFileArtifact(filePath, "figure", "image/png", false, logicalPath);
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
    if status ~= "implemented"
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
    "missing_columns", "", "missing_plots", "", "missing_exports", "", "warning_flag", false), height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    logicalPath = localRegistryLogicalPath(outName, logicalPaths);
    Tref = localRegistryTable(outName, tables);
    actualRows = localArtifactRowCount(runFolder, logicalPath, Tref);
    expectedRows = localExpectedRowCount(outName, Tref, registry.current_status(i));
    plotMissing = "";
    if outName == "prb_allocation_heatmap"
        plotMissing = string(localTernary(exist(fullfile(runFolder, "reports", "image", "prb_allocation_heatmap.png"), "file") ~= 2, "reports/image/prb_allocation_heatmap.png", ""));
    elseif outName == "power_energy_table"
        plotMissing = string(localTernary(exist(fullfile(runFolder, "reports", "image", "power_energy_cumulative.png"), "file") ~= 2, "reports/image/power_energy_cumulative.png", ""));
    end
    actualArtifacts = double(actualRows > 0);
    if plotMissing == ""
        actualArtifacts = actualArtifacts + 1;
    end
    expectedArtifacts = double(localTernary(logical(actualRows > 0), 2, 0));
    rows(i).output_name = outName;
    rows(i).run_id = meta.run_id;
    rows(i).expected_row_count = expectedRows;
    rows(i).actual_row_count = actualRows;
    rows(i).expected_artifact_count = expectedArtifacts;
    rows(i).actual_artifact_count = actualArtifacts;
    rows(i).completeness_percent = localCompleteness(expectedRows, actualRows, expectedArtifacts, actualArtifacts, registry.current_status(i));
    rows(i).missing_columns = "";
    rows(i).missing_plots = plotMissing;
    rows(i).missing_exports = string(localTernary(actualRows > 0 && logicalPath ~= "" && exist(fullfile(runFolder, replace(logicalPath, ".csv", ".json")), "file") ~= 2, replace(logicalPath, ".csv", ".json"), ""));
    rows(i).warning_flag = registry.current_status(i) ~= "implemented";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildOutputCompletenessTable", ...
    "reports/csv/output_completeness_table.csv", "implemented", "meta_audit", true, true);
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

function T = localBuildAPIExposureAuditTable(registry, meta)
rows = table();
rows.output_name = registry.output_name;
rows.backend_source = registry.block_module;
rows.api_route = repmat("/api/run/<run_id>/live", height(registry), 1);
rows.payload_schema_version = repmat("lls_live_v1", height(registry), 1);
rows.response_non_empty_flag = registry.api_exposed_flag & registry.persisted_flag & registry.export_supported_flag;
rows.ui_bind_state = localStringFromMask(registry.current_status == "implemented", "bound", "coverage_badge_or_partial");
rows.exporter_state = localStringFromMask(registry.export_supported_flag, "csv_json", "unavailable_or_incomplete_export");
T = localFinalizeOutputTable(rows, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildAPIExposureAuditTable", ...
    "reports/csv/api_exposure_audit_table.csv", "implemented", "meta_audit", true, true);
end

function T = localBuildPersistenceAuditTable(runFolder, registry, logicalPaths, meta)
rows = repmat(struct("output_name", "", "backend_source_exists_flag", false, "writer_enabled", false, ...
    "parquet_enabled", false, "csv_enabled", false, "json_enabled", false, "last_nonempty_run_id", NaN, ...
    "retention_policy", ""), height(registry), 1);
for i = 1:height(registry)
    outName = string(registry.output_name(i));
    logicalPath = localRegistryLogicalPath(outName, logicalPaths);
    rows(i).output_name = outName;
    rows(i).backend_source_exists_flag = logical(registry.backend_source_exists_flag(i));
    rows(i).writer_enabled = logical(registry.persisted_flag(i));
    rows(i).parquet_enabled = false;
    rows(i).csv_enabled = logicalPath ~= "" && exist(fullfile(runFolder, logicalPath), "file") == 2;
    rows(i).json_enabled = logicalPath ~= "" && exist(fullfile(runFolder, replace(logicalPath, ".csv", ".json")), "file") == 2;
    rows(i).last_nonempty_run_id = localTernary(rows(i).csv_enabled, meta.run_id, NaN);
    rows(i).retention_policy = "db_backed_canonical_artifact";
end
T = struct2table(rows);
T = localFinalizeOutputTable(T, meta, "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildPersistenceAuditTable", ...
    "reports/csv/persistence_audit_table.csv", "implemented", "meta_audit", true, true);
end

function inventory = localBuildArtifactInventory(runFolder)
files = dir(fullfile(runFolder, "**", "*"));
rows = repmat(struct("RelativePath", "", "Extension", "", "Bytes", NaN, "ArtifactState", "", "SchemaVersion", "v1"), 0, 1);
for i = 1:numel(files)
    if files(i).isdir
        continue;
    end
    rel = localPortablePath(string(erase(fullfile(files(i).folder, files(i).name), string(runFolder) + filesep)));
    [~, ~, ext] = fileparts(files(i).name);
    rows(end+1, 1) = struct("RelativePath", rel, "Extension", string(ext), ... %#ok<AGROW>
        "Bytes", double(files(i).bytes), "ArtifactState", "present", "SchemaVersion", "v1");
end
inventory = struct2table(rows);
if ~isempty(inventory)
    inventory = sortrows(inventory, "RelativePath");
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
    localSpec("output_completeness_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/output_completeness_table.csv"), ...
    localSpec("instrumentation_coverage_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/instrumentation_coverage_table.csv"), ...
    localSpec("api_exposure_audit_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/api_exposure_audit_table.csv"), ...
    localSpec("persistence_audit_table", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/persistence_audit_table.csv"), ...
    localSpec("honest_unavailable_registry", "coverage", "coverage_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/honest_unavailable_registry.csv"), ...
    localSpec("result_issue_registry", "root_cause", "cross_layer_issue_registry", true, "c", "yes", true, false, "phase_now", "reports/csv/result_issue_registry.csv"), ...
    localSpec("table_scenario_topology", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/table_scenario_topology.csv"), ...
    localSpec("scenario_consistency_check_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/scenario_consistency_check_table.csv"), ...
    localSpec("topology_density_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/topology_density_table.csv"), ...
    localSpec("sector_utilization_summary_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/sector_utilization_summary_table.csv"), ...
    localSpec("serving_cell_population_table", "scenario_topology", "scenario_runtime", true, "c", "yes", true, false, "phase_now", "reports/csv/serving_cell_population_table.csv"), ...
    localSpec("neighbor_degree_histogram_data", "scenario_topology", "scenario_runtime", false, "a", "no", false, false, "phase_backlog", ""), ...
    localSpec("topology_parameter_diff_vs_baseline", "scenario_topology", "scenario_runtime", true, "r", "partial", true, true, "phase_compare", ""), ...
    localSpec("scenario_topology_map", "scenario_topology", "scenario_runtime", false, "a", "no", false, false, "phase_backlog", ""), ...
    localSpec("site_sector_schematic", "scenario_topology", "scenario_runtime", false, "a", "no", false, false, "phase_backlog", ""), ...
    localSpec("table_gnb_cell", "cell_analytics", "system_cell_load", true, "c", "partial", true, false, "phase_now", "reports/csv/table_gnb_cell.csv"), ...
    localSpec("table_channel_summary", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_channel_summary.csv"), ...
    localSpec("table_noise_interference", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_noise_interference.csv"), ...
    localSpec("table_link_budget", "channel", "system_interference_detail", true, "c", "partial", true, false, "phase_now", "reports/csv/table_link_budget.csv"), ...
    localSpec("table_scheduler_decision", "scheduler", "system_scheduler", true, "c", "yes", true, false, "phase_now", "packet_flow/csv/table_scheduler_decision.csv"), ...
    localSpec("live_prb_allocation", "scheduler", "system_scheduler", true, "c", "yes", true, false, "phase_now", "packet_flow/csv/live_prb_allocation.csv"), ...
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
    exportSupported = localOutputExportSupported(runFolder, logicalPath, persistedFlag);
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
if any(outName == ["output_coverage_registry", "output_completeness_table", "instrumentation_coverage_table", ...
        "api_exposure_audit_table", "persistence_audit_table", "honest_unavailable_registry"])
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

function tf = localOutputExportSupported(runFolder, logicalPath, persistedFlag)
tf = false;
if ~logical(persistedFlag) || string(logicalPath) == ""
    return;
end
logicalPath = string(logicalPath);
if endsWith(lower(logicalPath), ".csv")
    jsonPath = replace(logicalPath, ".csv", ".json");
    tf = localArtifactExists(runFolder, jsonPath);
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
    "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "doppler_time_variation_plot", ...
    "anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", ...
    "control_overhead_analytics_table", "resource_overhead_analytics_table", ...
    "pdcch_dci_table", "ssb_pbch_table", "prach_table", "pucch_table", ...
    "pusch_table", "pdsch_table", "srs_table", "trs_receiver_tracking_table", ...
    "csi_rs_table", "beam_precoder_table", "timing_synchronization_table"]);
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
    case {"live_prb_allocation", "prb_allocation_heatmap", "table_mcs_tbs_evolution", ...
            "table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", ...
            "resource_overhead_analytics_table"}
        val = "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv";
    case {"table_channel_summary", "table_noise_interference", "table_link_budget", "root_cause_candidate_table", ...
            "doppler_time_variation_plot"}
        val = "system/csv/system_interference_detail.csv";
    case {"table_gnb_cell", "sector_utilization_summary_table"}
        val = "system/tables/sectors.csv|system/csv/system_cell_load.csv";
    case {"topology_density_table"}
        val = "system/tables/sites.csv|system/tables/sectors.csv|system/tables/ues.csv|reports/csv/deployment_layout_reference.csv";
    case {"serving_cell_population_table"}
        val = "system/csv/system_interference_detail.csv|system/csv/system_ue_summary.csv";
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
    case "pdcch_dci_table"
        val = "control/csv/pdcch_trials.csv|air_interface/csv/pdcch_trials.csv";
    case "ssb_pbch_table"
        val = "control/csv/pbch_trials.csv|air_interface/csv/pbch_trials.csv";
    case "prach_table"
        val = "control/csv/prach_trials.csv|air_interface/csv/prach_trials.csv";
    case "pucch_table"
        val = "control/csv/pucch_trials.csv|air_interface/csv/pucch_trials.csv";
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
        val = "air_interface/csv/csi_rs_trials.csv";
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
    case {"live_prb_allocation", "prb_allocation_heatmap", "table_mcs_tbs_evolution", ...
            "table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", ...
            "resource_overhead_analytics_table"}
        val = "sixgr.system.SystemLevelRunner.run";
    case {"table_channel_summary", "table_noise_interference", "table_link_budget", "root_cause_candidate_table", ...
            "serving_cell_population_table", "doppler_time_variation_plot"}
        val = "sixgr.system.SystemLevelRunner.interference_detail_export";
    case {"topology_density_table", "sector_utilization_summary_table"}
        val = "sixgr.system.SystemLevelRunner.topology_and_cell_load_export";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table"}
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case {"beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram"}
        val = "sixgr.link.runDLPDSCHThroughput|sixgr.link.runULPUSCHThroughput";
    case {"anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", "control_overhead_analytics_table"}
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
        val = "sixgr.link.runDLPDSCHThroughput";
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
    case "live_prb_allocation"
        val = "scheduler_active";
    case {"table_scheduler_decision", "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "resource_overhead_analytics_table"}
        val = "scheduler_grants_exported";
    case {"table_latency", "latency_cdf_plot", "latency_root_cause_table"}
        val = "air_interface_trials_include_real_latency_columns";
    case {"beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram"}
        val = "air_interface_trials_include_runtime_beam_precoder_rows";
    case {"topology_density_table", "sector_utilization_summary_table", "serving_cell_population_table"}
        val = "topology_or_system_summary_artifacts_exported";
    case "trs_receiver_tracking_table"
        val = "trs_enabled_and_runtime_processed";
    case "csi_rs_table"
        val = "csi_rs_enabled_and_runtime_transmitted_or_observed";
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
    case {"topology_density_table", "sector_utilization_summary_table", "serving_cell_population_table", ...
            "beamforming_analytics_table", "mimo_rank_utilization_table", "rank_layer_usage_histogram", ...
            "dl_resource_grid_heatmap", "ul_resource_grid_heatmap", "doppler_time_variation_plot", ...
            "anomaly_window_table", "cross_layer_correlation_table", "hotspot_analytics_table", ...
            "control_overhead_analytics_table", "resource_overhead_analytics_table"}
        val = "runtime-backed derived table is exported; add deeper raw telemetry if the corresponding detailed view remains unavailable";
    case "csi_rs_table"
        val = "run DL waveform CSI-RS mapping/observation and mirror persisted csi_rs_trials rows";
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
end

function T = localAddMissingVar(T, name, values)
if ~ismember(name, string(T.Properties.VariableNames))
    T = addvars(T, values, 'NewVariableNames', name);
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
    rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "report_id", NaN, ...
        "report_type", "", "wideband_cqi", NaN, "subband_cqi_vector_ref", "", "pmi", NaN, "ri", NaN, ...
        "csi_age_ms", NaN, "report_size_bits", NaN, "report_trigger", "", "based_on", "", ...
        "feedback_delay_ms", NaN, "direction", ""), 0, 1);
    return;
end
rows = repmat(struct("timestamp_sim_ms", NaN, "ue_id", NaN, "cell_id", NaN, "report_id", NaN, ...
    "report_type", "", "wideband_cqi", NaN, "subband_cqi_vector_ref", "", "pmi", NaN, "ri", NaN, ...
    "csi_age_ms", NaN, "report_size_bits", NaN, "report_trigger", "", "based_on", "", ...
    "feedback_delay_ms", NaN, "direction", ""), height(grants), 1);
for i = 1:height(grants)
    rows(i) = struct( ...
        "timestamp_sim_ms", 1e3 * double(localTableValue(grants(i, :), "Time_s", NaN)), ...
        "ue_id", localTableValue(grants(i, :), "UE", NaN), ...
        "cell_id", localTableValue(grants(i, :), "CellID", NaN), ...
        "report_id", i, ...
        "report_type", "scheduler_observation", ...
        "wideband_cqi", localTableValue(grants(i, :), "CQIUsed", NaN), ...
        "subband_cqi_vector_ref", "", ...
        "pmi", NaN, ...
        "ri", NaN, ...
        "csi_age_ms", NaN, ...
        "report_size_bits", NaN, ...
        "report_trigger", "grant_selection", ...
        "based_on", "unknown", ...
        "feedback_delay_ms", NaN, ...
        "direction", string(direction));
end
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
        "timestamp_sim_ms", 1e3 * double(localTableValue(grants(i, :), "Time_s", NaN)), ...
        "ue_id", localTableValue(grants(i, :), "UE", NaN), ...
        "cell_id", localTableValue(grants(i, :), "CellID", NaN), ...
        "direction", string(direction), ...
        "cqi_input", localTableValue(grants(i, :), "CQIUsed", NaN), ...
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
    mu = round(log2((meta.scs_hz / 1e3) / 15));
    slotDurationMs = 1 / 2^mu;
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
mu = round(log2(double(scsKHz) / 15));
if ~(isfinite(mu) && mu >= 0)
    slotsPerFrame = NaN;
else
    slotsPerFrame = 10 * 2^mu;
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
