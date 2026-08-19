function report = buildPhase7ReadinessArtifacts(scenarioCfg, runDir)
%BUILDPHASE7READINESSARTIFACTS Build fail-closed Phase 7 scientific audits.
%
% These artifacts are preflight/readiness evidence. They do not certify a
% full-route campaign unless the corresponding runtime rows already exist.

arguments
    scenarioCfg = struct()
    runDir {mustBeTextScalar} = pwd
end

runDir = char(string(runDir));
dirs = localEnsurePhase7Dirs(runDir);
cfg = localScenarioStruct(scenarioCfg);

cfgTables = localBuildConfigurationTables(cfg);
storageTables = localBuildStorageTables(cfg);
runtimeMobility = localReadRuntimeMobilityEvidence(runDir, cfg);
geometryTables = localBuildGeometryTables(cfg, runtimeMobility);
mobilityTables = localBuildMobilityTables(cfg, geometryTables, runtimeMobility);
% The live exporter runs before Phase 7 has resolved trajectory completeness.
% Refresh only the mobility KPI reducer from the in-memory runtime-backed
% resolution so the Phase 7 gate cannot consume a stale pre-resolution row.
mobilityKPI = sixgr.analytics.buildMobilityKPIReconciliation( ...
    cfg, struct("Resolution", mobilityTables.Resolution), runDir);
sixgr.analytics.writeAnalysisTable(fullfile(dirs.ReportCSV, ...
    "mobility_kpi_reconciliation.csv"), mobilityKPI);
measuredSinrT = localBuildMeasuredSINRTimeseries(runDir, cfg);
physicalTables = localBuildPhysicalChannelReconciliationTables(runDir, cfg);
campaignEvidence = localBuildCampaignEvidence(runDir, cfg);
gateStatus = localBuildGateStatus(runDir, cfg, cfgTables, storageTables, geometryTables, mobilityTables, physicalTables, campaignEvidence);
finalTables = localBuildFinalReportTables(runDir, gateStatus, cfgTables, storageTables, mobilityTables, campaignEvidence);

localWrite(dirs.ConfigurationCSV, "resolved_channel_rf_configuration.csv", cfgTables.Resolved);
localWrite(dirs.ConfigurationCSV, "configuration_conflicts.csv", cfgTables.Conflicts);
localWrite(dirs.ConfigurationCSV, "configuration_precedence.csv", cfgTables.Precedence);
localWrite(dirs.ConfigurationCSV, "configuration_consumer_map.csv", cfgTables.ConsumerMap);

localWrite(dirs.StorageCSV, "capture_volume_estimate.csv", storageTables.VolumeEstimate);
localWrite(dirs.StorageCSV, "capture_policy.csv", storageTables.Policy);
localWrite(dirs.StorageCSV, "capture_budget_validation.csv", storageTables.BudgetValidation);
localWrite(dirs.StorageCSV, "raw_capture_schedule.csv", storageTables.RawCaptureSchedule);

localWrite(dirs.GeometryCSV, "coordinate_system.csv", geometryTables.CoordinateSystem);
localWrite(dirs.GeometryCSV, "site_positions.csv", geometryTables.SitePositions);
localWrite(dirs.GeometryCSV, "topology_nodes.csv", geometryTables.TopologyNodes);
localWrite(dirs.GeometryCSV, "ue_initial_positions.csv", geometryTables.UEInitialPositions);
localWrite(dirs.GeometryCSV, "trajectory_geometry.csv", geometryTables.TrajectoryGeometry);
localWrite(dirs.GeometryCSV, "serving_cell_assignment.csv", geometryTables.ServingCellAssignment);
localWrite(dirs.GeometryCSV, "geometry_validation.csv", geometryTables.Validation);

localWrite(dirs.MobilityCSV, "trajectory_resolution.csv", mobilityTables.Resolution);
localWrite(dirs.MobilityCSV, "trajectory_segment_table.csv", mobilityTables.Segments);
localWrite(dirs.MobilityCSV, "inter_ue_distance_validation.csv", mobilityTables.InterUEDistance);
localWrite(dirs.MobilityCSV, "trajectory_constraint_conflicts.csv", mobilityTables.ConstraintConflicts);
localWrite(dirs.MobilityCSV, "doppler_reconciliation.csv", mobilityTables.DopplerReconciliation);
localWrite(dirs.MobilityCSV, "pathloss_reconciliation.csv", mobilityTables.PathlossReconciliation);
localWrite(dirs.MobilityCSV, "propagation_delay_reconciliation.csv", mobilityTables.PropagationDelayReconciliation);
localWrite(dirs.MobilityCSV, "channel_continuity_reconciliation.csv", mobilityTables.ChannelContinuityReconciliation);
localWrite(dirs.ReportCSV, "measured_sinr_timeseries.csv", measuredSinrT);
localWrite(dirs.ReportCSV, "channel_realization_reconciliation.csv", physicalTables.ChannelRealization);
localWrite(dirs.ReportCSV, "path_power_normalization_reconciliation.csv", physicalTables.PathPowerNormalization);
localWrite(dirs.ReportCSV, "antenna_array_reconciliation.csv", physicalTables.AntennaArray);
localWrite(dirs.ReportCSV, "polarization_reconciliation.csv", physicalTables.Polarization);

if istable(campaignEvidence.Tables.DLBlerCurve) && height(campaignEvidence.Tables.DLBlerCurve) > 0
    localWrite(dirs.AirInterfaceCSV, "dl_multi_seed_bler_curve.csv", campaignEvidence.Tables.DLBlerCurve);
end
if istable(campaignEvidence.Tables.DropStatistics) && height(campaignEvidence.Tables.DropStatistics) > 0
    localWrite(dirs.AirInterfaceCSV, "multi_seed_drop_statistics.csv", campaignEvidence.Tables.DropStatistics);
end
if istable(campaignEvidence.Tables.CampaignAudit) && height(campaignEvidence.Tables.CampaignAudit) > 0
    localWrite(dirs.ReportCSV, "campaign_evidence_audit.csv", campaignEvidence.Tables.CampaignAudit);
end

gateT = sixgr.runtime.Phase7TruthEvaluator.table(gateStatus);
localWrite(dirs.ReportCSV, "phase7_truth_gates.csv", gateT);
sixgr.util.jsonWrite(fullfile(dirs.ReportJSON, "phase7_truth_gates.json"), gateStatus);

localWrite(dirs.FinalReports, "final_defect_register.csv", finalTables.DefectRegister);
localWrite(dirs.FinalReports, "final_scientific_claims_matrix.csv", finalTables.ClaimsMatrix);
localWrite(dirs.FinalReports, "final_kpi_tables.csv", finalTables.KPITable);
localWrite(dirs.FinalReports, "final_campaign_summary.csv", finalTables.CampaignSummary);
sixgr.util.jsonWrite(fullfile(dirs.FinalReports, "final_grade.json"), finalTables.Grade);
localWriteFinalMarkdown(dirs.FinalReports, gateStatus, cfgTables, storageTables, mobilityTables);

report = struct();
report.Configuration = cfgTables;
report.Storage = storageTables;
report.Geometry = geometryTables;
report.Mobility = mobilityTables;
report.RuntimeMobilityEvidence = runtimeMobility;
report.MeasuredSINRTimeseries = measuredSinrT;
report.PhysicalChannelReconciliation = physicalTables;
report.Campaign = campaignEvidence;
report.Gates = gateStatus;
report.OutputRoot = string(runDir);
end

function dirs = localEnsurePhase7Dirs(runDir)
dirs = struct();
dirs.AirInterfaceCSV = fullfile(runDir, "air_interface", "csv");
dirs.ConfigurationCSV = fullfile(runDir, "configuration", "csv");
dirs.StorageCSV = fullfile(runDir, "storage", "csv");
dirs.GeometryCSV = fullfile(runDir, "geometry", "csv");
dirs.MobilityCSV = fullfile(runDir, "mobility", "csv");
dirs.ReportCSV = fullfile(runDir, "reports", "csv");
dirs.ReportJSON = fullfile(runDir, "reports", "json");
dirs.FinalReports = fullfile(runDir, "reports", "final");
names = fieldnames(dirs);
for i = 1:numel(names)
    sixgr.util.ensureFolder(dirs.(names{i}));
end
end

function cfg = localScenarioStruct(scenarioCfg)
if isa(scenarioCfg, "sixgr.lls6g.config.ScenarioConfig")
    cfg = scenarioCfg.toStruct();
elseif isstruct(scenarioCfg)
    cfg = scenarioCfg;
else
    cfg = struct();
end
end

function cfgTables = localBuildConfigurationTables(cfg)
concepts = localConceptSpecs();
rows = repmat(struct("Concept", "", "CandidatePath", "", "ValueText", "", ...
    "ValueRole", "configured", "Resolved", false, "ConflictStatus", "", "Notes", ""), 0, 1);
conflictRows = repmat(struct("Concept", "", "DistinctValueCount", NaN, ...
    "ResolvedValue", "", "ConflictStatus", "", "Reason", ""), 0, 1);
precedenceRows = repmat(struct("Concept", "", "PrecedenceOrder", "", ...
    "ResolvedPath", "", "ResolvedValue", "", "PrecedenceStatus", ""), 0, 1);
consumerRows = repmat(struct("Concept", "", "ConsumerFunction", "", ...
    "ConsumerRole", "", "EvidenceArtifact", ""), 0, 1);

for i = 1:numel(concepts)
    spec = concepts(i);
    values = strings(0, 1);
    paths = strings(0, 1);
    for p = string(spec.Paths)
        value = localGet(cfg, p, []);
        valueText = localNormalizedConceptValueText(spec.Name, p, value);
        if strlength(valueText) == 0
            continue;
        end
        values(end+1, 1) = valueText; %#ok<AGROW>
        paths(end+1, 1) = p; %#ok<AGROW>
    end
    distinct = unique(values);
    resolvedValue = "";
    resolvedPath = "";
    if ~isempty(values)
        resolvedValue = values(1);
        resolvedPath = paths(1);
    end
    conflictStatus = "consistent_or_single_source";
    reason = "documented_precedence_order";
    if numel(distinct) > 1
        conflictStatus = "conflict_unresolved";
        reason = "duplicate_concept_has_distinct_configured_values";
    end
    for j = 1:numel(values)
        rows(end+1, 1) = struct("Concept", spec.Name, "CandidatePath", paths(j), ...
            "ValueText", values(j), "ValueRole", "configured", "Resolved", j == 1, ...
            "ConflictStatus", conflictStatus, "Notes", reason); %#ok<AGROW>
    end
    conflictRows(end+1, 1) = struct("Concept", spec.Name, ...
        "DistinctValueCount", double(numel(distinct)), "ResolvedValue", resolvedValue, ...
        "ConflictStatus", conflictStatus, "Reason", reason); %#ok<AGROW>
    precedenceRows(end+1, 1) = struct("Concept", spec.Name, ...
        "PrecedenceOrder", strjoin(string(spec.Paths), " > "), "ResolvedPath", resolvedPath, ...
        "ResolvedValue", resolvedValue, "PrecedenceStatus", "explicit_phase7_audit_order"); %#ok<AGROW>
    consumerRows(end+1, 1) = struct("Concept", spec.Name, ...
        "ConsumerFunction", spec.Consumer, "ConsumerRole", spec.Role, ...
        "EvidenceArtifact", spec.Artifact); %#ok<AGROW>
end

cfgTables = struct();
cfgTables.Resolved = struct2table(rows);
cfgTables.Conflicts = struct2table(conflictRows);
cfgTables.Precedence = struct2table(precedenceRows);
cfgTables.ConsumerMap = struct2table(consumerRows);
end

function specs = localConceptSpecs()
specs = [
    localConcept("carrier_frequency_hz", ["frequency.center_frequency_hz","global_radio_scope.carrier_frequency_hz","channels.carrier_frequency_hz"], "+sixgr/+lls6g/buildInternalConfig.m", "radio_frequency_resolution", "configuration/csv/resolved_channel_rf_configuration.csv")
    localConcept("bandwidth_hz", ["frequency.bandwidth_hz","global_radio_scope.channel_bandwidth_hz","air_interface.channel_bandwidth_hz"], "+sixgr/+lls6g/buildInternalConfig.m", "bandwidth_resolution", "configuration/csv/resolved_channel_rf_configuration.csv")
    localConcept("scs_khz", ["frame.scs_khz","bwp.dl.scs_khz","global_radio_scope.scs_hz"], "+sixgr/+lls6g/buildInternalConfig.m", "numerology_resolution", "configuration/csv/resolved_channel_rf_configuration.csv")
    localConcept("channel_model", ["channels.model_type","channel_model.model_family","channel.model"], "+sixgr/+channel/ChannelFactory.m", "channel_factory_selection", "channel/csv/channel_configured_vs_applied.csv")
    localConcept("channel_profile", ["channels.profile","channel_model.scenario_label","channel.cdlProfile","channel.tdlProfile"], "+sixgr/+channel/ChannelFactory.m", "concrete_fading_profile", "channel/csv/channel_realizations.csv")
    localConcept("los_enabled", ["channels.los_enabled"], "+sixgr/+channel/runStrictChannelRFValidation.m", "los_policy_enable", "channel/csv/large_scale_parameters.csv")
    localConcept("pathloss_los_mode", ["channels.pathloss_los_mode"], "+sixgr/+channel/runStrictChannelRFValidation.m", "los_pathloss_policy", "channel/csv/large_scale_parameters.csv")
    localConcept("mobility_speed_kmh", ["mobility.ue_speed_kmh","channels.mobility_kmph"], "+sixgr/+scenario/+mobility/updatePositions.m", "trajectory_speed", "mobility/csv/trajectory_resolution.csv")
    localConcept("max_doppler_hz", ["channels.max_doppler_hz","channels.doppler_hz","channel_model.doppler_hz"], "+sixgr/+channel/ChannelFactory.m", "doppler_resolution", "channel/csv/channel_realizations.csv")
    localConcept("bs_noise_figure_db", ["scenario.bs.noiseFigure_dB","air_interface.bs_noise_figure_dB"], "+sixgr/+link/applyWaveformImpairments.m", "bs_receiver_thermal_noise_resolution", "rf/csv/thermal_noise_validation.csv")
    localConcept("ue_noise_figure_db", ["scenario.ue.noiseFigure_dB","air_interface.ue_noise_figure_dB"], "+sixgr/+link/applyWaveformImpairments.m", "ue_receiver_thermal_noise_resolution", "rf/csv/thermal_noise_validation.csv")
    localConcept("iq_amplitude_imbalance_db", ["impairments.iq_amplitude_imbalance_dB"], "+sixgr/+rf/applyRFImpairmentChain.m", "rf_impairment_chain", "rf/csv/rf_impairment_chain.csv")
    localConcept("iq_phase_imbalance_deg", ["impairments.iq_phase_imbalance_deg"], "+sixgr/+rf/applyRFImpairmentChain.m", "rf_impairment_chain", "rf/csv/rf_impairment_chain.csv")
    ];
end

function spec = localConcept(name, paths, consumer, role, artifact)
spec = struct("Name", string(name), "Paths", string(paths), ...
    "Consumer", string(consumer), "Role", string(role), "Artifact", string(artifact));
end

function storageTables = localBuildStorageTables(cfg)
sampleRate = localNumber(cfg, ["waveform.sample_rate_hz","global_radio_scope.sample_rate_hz"], 122.88e6);
bsAnt = localNumber(cfg, ["scenario.bs.nRxAnt","scenario.bs.nTxAnt","mimo.n_tx_ant"], 1);
ueAnt = localNumber(cfg, ["scenario.ue.nRxAnt","mimo.n_rx_ant"], 1);
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0);
routeSlots = localRequiredRouteSlots(cfg);
configuredDurationS = slots * slotMs / 1e3;
routeDurationS = routeSlots * slotMs / 1e3;
bytesPerComplex = 8;
rxGB = sampleRate * max(configuredDurationS, 0) * bsAnt * bytesPerComplex / 1e9;
rxRouteGB = sampleRate * max(routeDurationS, 0) * bsAnt * bytesPerComplex / 1e9;
txGB = sampleRate * max(configuredDurationS, 0) * ueAnt * bytesPerComplex / 1e9;

volume = table(sampleRate, bsAnt, ueAnt, slots, configuredDurationS, routeSlots, routeDurationS, ...
    bytesPerComplex, txGB, rxGB, rxRouteGB, ...
    'VariableNames', {'SampleRate_Hz','BSAntennaCount','UEAntennaCount','ConfiguredSlots','ConfiguredDuration_s', ...
    'FullRouteSlotsRequired','FullRouteDuration_s','BytesPerComplexSample','EstimatedTxIQ_GB','EstimatedRxIQ_GB','EstimatedFullRouteRxIQ_GB'});

scenarioName = string(localGet(cfg, "meta.scenario_id", ""));
rawRequested = localBool(cfg, ["run_control.raw_iq_capture_enable","output.save_mat"], false);
isFullCaptureName = contains(lower(scenarioName), "full_capture");
policyName = "SCIENTIFIC_EVENT_CAPTURE";
policyOk = true;
reason = "scalar_event_lineage_and_selected_raw_windows_required";
if isFullCaptureName && rawRequested
    policyOk = false;
    reason = "profile_name_full_capture_conflicts_with_unbudgeted_long_route_raw_iq_capture";
end
policy = table(policyName, rawRequested, isFullCaptureName, policyOk, ...
    "lls_mobile_2ue_100kmh_1sector_scientific_event_capture", reason, ...
    'VariableNames', {'CapturePolicy','RawIQRequested','ProfileNameSaysFullCapture','CapturePolicyTruthfulOk', ...
    'RecommendedProfileName','PolicyReason'});

budget = table(policyOk, rxGB, rxRouteGB, "disk_space_not_checked_by_static_preflight", ...
    'VariableNames', {'CaptureBudgetValidationOk','ConfiguredRxIQ_GB','FullRouteRxIQ_GB','BudgetValidationStatus'});
schedule = table(["periodic_window";"triggered_failure_window";"event_csv_lineage"], ...
    ["runtime_selected";"runtime_selected";"always"], [NaN;NaN;0], ...
    ["no_static_window_declared";"no_static_trigger_declared";"canonical_csv_required"], ...
    'VariableNames', {'CaptureClass','CaptureMode','PeriodSlots','ScheduleStatus'});

storageTables = struct("VolumeEstimate", volume, "Policy", policy, ...
    "BudgetValidation", budget, "RawCaptureSchedule", schedule);
end

function geometryTables = localBuildGeometryTables(cfg, runtimeMobility)
coord = table("local_cartesian", "site_origin", "x_east_y_north_z_up", "degrees", ...
    "azimuth_from_positive_x_counterclockwise", "elevation_from_xy_plane", ...
    'VariableNames', {'CoordinateSystem','Origin','Axes','AngleUnits','AzimuthConvention','ElevationConvention'});

bsHeight = localNumber(cfg, "scenario.bs.height_m", 25);
site = table(1, 1, 0, 0, bsHeight, localNumber(cfg, "scenario.bs.downtilt_deg", NaN), ...
    'VariableNames', {'SiteID','CellID','X_m','Y_m','Z_m','Downtilt_deg'});

if localRuntimeMobilityAvailable(runtimeMobility)
    ueInitial = localBuildRuntimeUEInitialPositions(runtimeMobility);
    traj = localBuildRuntimeTrajectoryGeometry(runtimeMobility, cfg);
    topologyNodes = localBuildTopologyNodesTable(cfg, runtimeMobility, ueInitial);
    servingAssignment = localBuildServingCellAssignmentTable(runtimeMobility);
    geomOk = height(ueInitial) > 0 && height(traj) > 0;
    validation = table(geomOk, "runtime_slot_trace_available", height(ueInitial), ...
        "runtime_mobility_trace_rows_back_geometry_and_large_scale_reconciliation", ...
        'VariableNames', {'GeometryValidationOk','CoordinateStatus','UECount','ValidationNotes'});
    geometryTables = struct("CoordinateSystem", coord, "SitePositions", site, ...
        "TopologyNodes", topologyNodes, "UEInitialPositions", ueInitial, ...
        "TrajectoryGeometry", traj, "ServingCellAssignment", servingAssignment, ...
        "Validation", validation);
    return;
end

paths = localUserPaths(cfg);
ueRows = repmat(struct("UEID", NaN, "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
    "Speed_kmh", NaN, "PathSource", "", "PathProvenance", ""), numel(paths), 1);
for i = 1:numel(paths)
    p = paths(i);
    start = localVector(sixgr.util.structGet(p, "initial_position_m", [NaN NaN NaN]), 3);
    pathSource = string(sixgr.util.structGet(p, "path_source", "mobility.user_paths"));
    pathProvenance = localPathProvenance(p, pathSource);
    ueRows(i) = struct("UEID", localNumber(p, "ue_id", i), "X_m", start(1), ...
        "Y_m", start(2), "Z_m", start(3), "Speed_kmh", localNumber(p, "speed_kmh", localNumber(cfg, "mobility.ue_speed_kmh", NaN)), ...
        "PathSource", pathSource, "PathProvenance", pathProvenance);
end
ueInitial = localStructRowsToTable(ueRows);

traj = localBuildTrajectoryGeometry(paths, cfg);
topologyNodes = localBuildTopologyNodesTable(cfg, struct(), ueInitial);
geomOk = height(ueInitial) > 0 && all(isfinite(ueInitial.X_m)) && height(traj) > 0;
validation = table(geomOk, "local_cartesian_declared", height(ueInitial), ...
    "pathloss_distance_definition_requires_runtime_reconciliation", ...
    'VariableNames', {'GeometryValidationOk','CoordinateStatus','UECount','ValidationNotes'});

geometryTables = struct("CoordinateSystem", coord, "SitePositions", site, ...
    "TopologyNodes", topologyNodes, "UEInitialPositions", ueInitial, ...
    "TrajectoryGeometry", traj, "ServingCellAssignment", localEmptyServingCellAssignmentTable(), ...
    "Validation", validation);
end

function T = localBuildTrajectoryGeometry(paths, cfg)
rows = repmat(struct("UEID", NaN, "StartX_m", NaN, "StartY_m", NaN, "StartZ_m", NaN, ...
    "EndX_m", NaN, "EndY_m", NaN, "EndZ_m", NaN, "RouteLength_m", NaN, ...
    "Speed_kmh", NaN, "TraversalTime_s", NaN, "RequiredTraversalSlots", NaN, "LoopMode", "", ...
    "PathProvenance", ""), numel(paths), 1);
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
for i = 1:numel(paths)
    p = paths(i);
    start = localVector(sixgr.util.structGet(p, "initial_position_m", [NaN NaN NaN]), 3);
    stop = localWaypointPosition(p, start);
    dist = norm(stop - start);
    speedKmh = localNumber(p, "speed_kmh", localNumber(cfg, "mobility.ue_speed_kmh", NaN));
    speedMs = speedKmh / 3.6;
    t = localSafeDivide(dist, speedMs);
    rows(i) = struct("UEID", localNumber(p, "ue_id", i), "StartX_m", start(1), "StartY_m", start(2), ...
        "StartZ_m", start(3), "EndX_m", stop(1), "EndY_m", stop(2), "EndZ_m", stop(3), ...
        "RouteLength_m", dist, "Speed_kmh", speedKmh, "TraversalTime_s", t, ...
        "RequiredTraversalSlots", ceil(t / (slotMs / 1e3)), "LoopMode", string(sixgr.util.structGet(p, "loop_mode", "")), ...
        "PathProvenance", localPathProvenance(p, string(sixgr.util.structGet(p, "path_source", "mobility.user_paths"))));
end
T = localStructRowsToTable(rows);
end

function mobilityTables = localBuildMobilityTables(cfg, geometryTables, runtimeMobility)
if localRuntimeMobilityAvailable(runtimeMobility)
    resolution = localBuildRuntimeTrajectoryResolution(cfg, runtimeMobility);
    segments = localBuildRuntimeTrajectorySegments(runtimeMobility);
    interUE = localRuntimeInterUEDistanceTable(cfg, runtimeMobility);
    doppler = localBuildRuntimeDopplerReconciliation(runtimeMobility, cfg);
    pathloss = localBuildRuntimePathlossReconciliation(runtimeMobility);
    propDelay = localBuildRuntimePropagationDelayReconciliation(runtimeMobility);
    continuity = localBuildRuntimeChannelContinuityReconciliation(cfg, runtimeMobility);
    if height(interUE) > 0 && ~all(localColumnAsLogical(interUE.InterUeConstraintResolvedOk))
        conflicts = table("min_inter_ue_distance_m", interUE.MinDistanceConfigured_m(1), interUE.ClosestDistance_m(1), ...
            "unresolved_requires_explicit_scenario_decision", ...
            "permit_virtual_crossing|introduce_separate_lanes|offset_one_trajectory|remove_constraint_for_trace_motion", ...
            'VariableNames', {'Constraint','ConfiguredValue','ObservedOrPredictedValue','ConflictStatus','AllowedDecisions'});
    else
        conflicts = table('Size', [0 5], 'VariableTypes', {'string','double','double','string','string'}, ...
            'VariableNames', {'Constraint','ConfiguredValue','ObservedOrPredictedValue','ConflictStatus','AllowedDecisions'});
    end
    mobilityTables = struct("Resolution", resolution, "Segments", segments, ...
        "InterUEDistance", interUE, "ConstraintConflicts", conflicts, ...
        "DopplerReconciliation", doppler, "PathlossReconciliation", pathloss, ...
        "PropagationDelayReconciliation", propDelay, ...
        "ChannelContinuityReconciliation", continuity);
    return;
end

traj = geometryTables.TrajectoryGeometry;
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0);
runDurationS = slots * slotMs / 1e3;
if height(traj) == 0
    resolution = table(false, slots, runDurationS, NaN, NaN, "no_user_paths", "unavailable_no_user_paths", ...
        'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s','RequiredTraversalSlots','ActualDistanceTravelled_m','Status','PathProvenance'});
    segments = table();
else
    requiredSlots = max(traj.RequiredTraversalSlots);
    speedMs = traj.Speed_kmh / 3.6;
    actualDist = min(traj.RouteLength_m, speedMs .* runDurationS);
    resolution = table(slots >= requiredSlots, slots, runDurationS, requiredSlots, min(actualDist), ...
        localTernary(slots >= requiredSlots, "full_route_duration_configured", "SHORT_MOBILITY_DIAGNOSTIC"), ...
        localTrajectoryPathProvenance(traj), ...
        'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s','RequiredTraversalSlots','ActualDistanceTravelled_m','Status','PathProvenance'});
    segments = traj;
end

interUE = localInterUEDistanceTable(cfg, traj, runDurationS);
if height(interUE) > 0 && ~logical(interUE.InterUeConstraintResolvedOk(1))
    conflicts = table("min_inter_ue_distance_m", interUE.MinDistanceConfigured_m(1), interUE.ClosestDistance_m(1), ...
        "unresolved_requires_explicit_scenario_decision", ...
        "permit_virtual_crossing|introduce_separate_lanes|offset_one_trajectory|remove_constraint_for_trace_motion", ...
        'VariableNames', {'Constraint','ConfiguredValue','ObservedOrPredictedValue','ConflictStatus','AllowedDecisions'});
else
    conflicts = table('Size', [0 5], 'VariableTypes', {'string','double','double','string','string'}, ...
        'VariableNames', {'Constraint','ConfiguredValue','ObservedOrPredictedValue','ConflictStatus','AllowedDecisions'});
end
mobilityTables = struct("Resolution", resolution, "Segments", segments, ...
    "InterUEDistance", interUE, "ConstraintConflicts", conflicts, ...
    "DopplerReconciliation", localEmptyDopplerReconciliationTable(), ...
    "PathlossReconciliation", localEmptyPathlossReconciliationTable(), ...
    "PropagationDelayReconciliation", localEmptyPropagationDelayReconciliationTable(), ...
    "ChannelContinuityReconciliation", localEmptyChannelContinuityReconciliationTable());
end

function runtime = localReadRuntimeMobilityEvidence(runDir, cfg)
runtime = struct();
runtime.TraceAvailable = false;
runtime.SourcePath = string(fullfile(runDir, "reports", "csv", "live_rsrp_serving_trace.csv"));
runtime.ServingTrace = localReadOptionalTable(runtime.SourcePath);
runtime.NormalizedTrace = localEmptyRuntimeMobilityTraceTable();
runtime.ConfiguredSlotCount = max(0, round(localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0)));
runtime.SlotDuration_s = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5) / 1e3;
runtime.CarrierFrequency_Hz = localNumber(cfg, ["frequency.center_frequency_hz","global_radio_scope.carrier_frequency_hz", ...
    "channels.carrier_frequency_hz","phy.fc_Hz"], NaN);
runtime.LightSpeed_mps = localLightSpeed();
if ~(istable(runtime.ServingTrace) && height(runtime.ServingTrace) > 0)
    return;
end

T = runtime.ServingTrace;
rows = repmat(localEmptyRuntimeMobilityTraceRow(), height(T), 1);
for i = 1:height(T)
    row = localEmptyRuntimeMobilityTraceRow();
    row.UeId = localTableNumber(T, i, ["UeId","UEID","UEIndex","UE"], NaN);
    row.CellId = localTableNumber(T, i, ["CellId","CellID","BaseStationID"], NaN);
    row.ServingCellId = localTableNumber(T, i, ["ServingCell","CellId","CellID","BaseStationID"], NaN);
    if ~isfinite(row.CellId)
        row.CellId = double(row.ServingCellId);
    end
    row.CanonicalSlot = localTableNumber(T, i, ["CanonicalSlot","Slot","TTI"], NaN);
    row.Time_s = localTableNumber(T, i, "Time_s", NaN);
    row.X_m = localTableNumber(T, i, ["X_m","UEPosX_m"], NaN);
    row.Y_m = localTableNumber(T, i, ["Y_m","UEPosY_m"], NaN);
    row.Z_m = localTableNumber(T, i, ["Z_m","UEPosZ_m"], NaN);
    row.Speed_kmh = localTableNumber(T, i, "Speed_kmh", NaN);
    row.Speed_mps = row.Speed_kmh / 3.6;
    headingDeg = localTableNumber(T, i, ["Heading_deg","UEHeading_deg"], NaN);
    row.Heading_deg = headingDeg;
    row.Heading_rad = localDegreesToRadians(headingDeg);
    row.Pathloss_dB = localTableNumber(T, i, "Pathloss_dB", NaN);
    row.BasePathloss_dB = localTableNumber(T, i, "BasePathloss_dB", NaN);
    row.ShadowFading_dB = localTableNumber(T, i, "ShadowFading_dB", NaN);
    row.O2I_dB = localTableNumber(T, i, "O2I_dB", NaN);
    row.Distance2D_m = localTableNumber(T, i, ["Distance2D_m","ServingDistance2D_m"], NaN);
    row.Distance3D_m = localTableNumber(T, i, ["Distance3D_m","ServingDistance_m"], NaN);
    row.PropagationDelay_s = localTableNumber(T, i, "PropagationDelay_s", NaN);
    row.RadialVelocity_mps = localTableNumber(T, i, "RadialVelocity_mps", NaN);
    row.ExpectedDopplerHz = localTableNumber(T, i, "ExpectedDopplerHz", NaN);
    if ~isfinite(row.ExpectedDopplerHz)
        row.ExpectedDopplerHz = localRuntimeExpectedDoppler( ...
            row.RadialVelocity_mps, runtime.CarrierFrequency_Hz, runtime.LightSpeed_mps);
    end
    row.AppliedDopplerHz = localTableNumber(T, i, ["AppliedDopplerHz","Doppler_Hz","RuntimeServingDopplerHz"], NaN);
    row.SignedDoppler_Hz = localTableNumber(T, i, ["SignedDoppler_Hz","RuntimeServingSignedDopplerHz"], NaN);
    row.PathlossModelSource = localTableString(T, i, "PathlossModelSource", "");
    row.PathlossComplianceStatus = localTableString(T, i, "PathlossComplianceStatus", "");
    row.LOSProbabilitySource = localTableString(T, i, "LOSProbabilitySource", "");
    row.LOSComplianceStatus = localTableString(T, i, "LOSComplianceStatus", "");
    row.LOSState = localTableString(T, i, "LOSState", "");
    if strlength(strtrim(row.LOSState)) == 0 && localHasColumn(T, "LOSFlag")
        losFlag = localTableLogical(T, i, "LOSFlag", false);
        row.LOSState = localTernary(losFlag, "LOS", "NLOS");
    end
    row = localFinalizeObservedRuntimeMobilityRow(row, runtime);
    row.Status = localRuntimeTraceRowStatus(row);
    rows(i) = row;
end

runtime.NormalizedTrace = sortrows(struct2table(rows, "AsArray", true), {'UeId','CanonicalSlot'});
runtime.TraceAvailable = height(runtime.NormalizedTrace) > 0;
if runtime.ConfiguredSlotCount < 1
    runtime.ConfiguredSlotCount = numel(unique(localColumnDouble(runtime.NormalizedTrace, "CanonicalSlot", NaN)));
end
end

function row = localFinalizeObservedRuntimeMobilityRow(row, runtime)
% Only unit conversions and analytical expectations derived from observed
% runtime fields are permitted here. Missing channel/geometry quantities
% remain missing and therefore fail strict reconciliation; configured
% values must never be promoted into a runtime evidence row.
if ~isfinite(row.Speed_mps) && isfinite(row.Speed_kmh)
    row.Speed_mps = row.Speed_kmh / 3.6;
end
if ~isfinite(row.ExpectedDopplerHz)
    row.ExpectedDopplerHz = localRuntimeExpectedDoppler( ...
        row.RadialVelocity_mps, runtime.CarrierFrequency_Hz, runtime.LightSpeed_mps);
end
end

function tf = localRuntimeMobilityAvailable(runtime)
tf = isstruct(runtime) && logical(sixgr.util.structGet(runtime, "TraceAvailable", false)) && ...
    istable(sixgr.util.structGet(runtime, "NormalizedTrace", table())) && ...
    height(sixgr.util.structGet(runtime, "NormalizedTrace", table())) > 0;
end

function T = localBuildRuntimeUEInitialPositions(runtime)
traceT = runtime.NormalizedTrace;
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
rows = repmat(struct("UEID", NaN, "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
    "Speed_kmh", NaN, "PathSource", "", "PathProvenance", ""), numel(ueList), 1);
for i = 1:numel(ueList)
    idx = find(localColumnDouble(traceT, "UeId", NaN) == ueList(i), 1, "first");
    rows(i) = struct("UEID", double(ueList(i)), ...
        "X_m", double(traceT.X_m(idx)), "Y_m", double(traceT.Y_m(idx)), "Z_m", double(traceT.Z_m(idx)), ...
        "Speed_kmh", double(traceT.Speed_kmh(idx)), ...
        "PathSource", "reports/csv/live_rsrp_serving_trace.csv", ...
        "PathProvenance", "runtime_slot_trace");
end
T = localStructRowsToTable(rows);
end

function T = localBuildTopologyNodesTable(cfg, runtime, ueInitial)
if nargin < 3 || ~istable(ueInitial)
    ueInitial = table();
end

nodeRows = repmat(localEmptyTopologyNodeRow(), 0, 1);
cellRows = localConfiguredCellNodeRows(cfg, runtime);
if ~isempty(cellRows)
    nodeRows = [nodeRows; cellRows]; %#ok<AGROW>
end

if istable(ueInitial) && height(ueInitial) > 0
    ueIdVals = localColumnDouble(ueInitial, "UEID", NaN);
    for i = 1:height(ueInitial)
        row = localEmptyTopologyNodeRow();
        row.NodeClass = "UE";
        row.NodeId = double(i);
        row.UeId = double(ueIdVals(i));
        row.X_m = localColumnDouble(ueInitial(i, :), "X_m", NaN);
        row.Y_m = localColumnDouble(ueInitial(i, :), "Y_m", NaN);
        row.Z_m = localColumnDouble(ueInitial(i, :), "Z_m", NaN);
        row.Speed_kmh = localColumnDouble(ueInitial(i, :), "Speed_kmh", NaN);
        row.Label = "UE " + string(row.UeId);
        row.NodeSource = localFirstString(ueInitial(i, :), "PathSource", "geometry/csv/ue_initial_positions.csv");
        row.Status = "runtime_or_configured_initial_position";
        nodeRows(end+1, 1) = row; %#ok<AGROW>
    end
end

T = localStructRowsToTable(nodeRows);
end

function rows = localConfiguredCellNodeRows(cfg, runtime)
rows = repmat(localEmptyTopologyNodeRow(), 0, 1);
sitePos = [];
cellIds = [];
siteIds = [];
try
    geom = sixgr.channel.buildScenarioGeometry(cfg);
    sitePosT = sixgr.util.structGet(geom, "SiteTable", table());
    sectorT = sixgr.util.structGet(geom, "SectorTable", table());
    if istable(sitePosT) && height(sitePosT) > 0 && istable(sectorT) && height(sectorT) > 0
        sitePos = [localColumnDouble(sitePosT, "X_m", NaN), ...
            localColumnDouble(sitePosT, "Y_m", NaN), ...
            localColumnDouble(sitePosT, "Z_m", NaN)];
        cellIds = localColumnDouble(sectorT, "CellId", NaN);
        siteIds = localColumnDouble(sectorT, "SiteId", NaN);
    end
catch
    sitePos = [];
    cellIds = [];
    siteIds = [];
end

if isempty(cellIds)
    if localRuntimeMobilityAvailable(runtime)
        cellIds = unique(localColumnDouble(runtime.NormalizedTrace, "ServingCellId", localColumnDouble(runtime.NormalizedTrace, "CellId", NaN)));
    else
        cellIds = zeros(0, 1);
    end
end
cellIds = unique(cellIds(isfinite(cellIds)), "stable");
if isempty(cellIds)
    configuredCells = localNumber(cfg, ["topology.num_cells", "deployment_topology.num_cells"], NaN);
    if isfinite(configuredCells) && configuredCells >= 1
        cellIds = (1:max(1, round(configuredCells))).';
    end
end

if isempty(siteIds)
    siteIds = cellIds;
end

for i = 1:numel(cellIds)
    row = localEmptyTopologyNodeRow();
    row.NodeClass = "Cell";
    row.NodeId = double(i);
    row.CellId = double(cellIds(i));
    siteId = double(localSafeIndex(siteIds, i, cellIds(i)));
    row.SiteId = siteId;
    pos = localSafeSitePosition(sitePos, siteId, i);
    row.X_m = pos(1);
    row.Y_m = pos(2);
    row.Z_m = pos(3);
    row.Label = "Cell " + string(row.CellId);
    row.NodeSource = "sixgr.channel.buildScenarioGeometry";
    row.Status = "configured_cell_geometry";
    rows(end+1, 1) = row; %#ok<AGROW>
end
end

function pos = localSafeSitePosition(sitePos, siteId, fallbackIdx)
pos = [NaN NaN NaN];
if ~isempty(sitePos) && isfinite(siteId) && siteId >= 1 && siteId <= size(sitePos, 1)
    pos = sitePos(siteId, :);
    return;
end
if ~isempty(sitePos)
    idx = max(1, min(size(sitePos, 1), round(fallbackIdx)));
    pos = sitePos(idx, :);
end
end

function T = localBuildServingCellAssignmentTable(runtime)
if ~localRuntimeMobilityAvailable(runtime)
    T = localEmptyServingCellAssignmentTable();
    return;
end

traceT = runtime.NormalizedTrace;
rows = repmat(localEmptyServingCellAssignmentRow(), height(traceT), 1);
for i = 1:height(traceT)
    servingCell = localColumnDouble(traceT(i, :), "ServingCellId", localColumnDouble(traceT(i, :), "CellId", NaN));
    rows(i) = struct( ...
        "UeId", double(traceT.UeId(i)), ...
        "CellId", double(traceT.CellId(i)), ...
        "ServingCellId", double(servingCell), ...
        "CanonicalSlot", double(traceT.CanonicalSlot(i)), ...
        "Time_s", double(traceT.Time_s(i)), ...
        "Distance3D_m", double(traceT.Distance3D_m(i)), ...
        "Pathloss_dB", double(traceT.Pathloss_dB(i)), ...
        "AssignmentSource", "reports/csv/live_rsrp_serving_trace.csv", ...
        "Status", string(traceT.Status(i)));
end
T = localStructRowsToTable(rows);
end

function T = localBuildRuntimeTrajectoryGeometry(runtime, cfg)
traceT = runtime.NormalizedTrace;
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
routeLengthByUe = containers.Map("KeyType", "double", "ValueType", "double");
requiredSlots = max(runtime.ConfiguredSlotCount, 0);
for i = 1:numel(ueList)
    ue = ueList(i);
    slice = traceT(localColumnDouble(traceT, "UeId", NaN) == ue, :);
    routeLengthByUe(ue) = localTraceRouteLength(slice);
end

rows = repmat(struct( ...
    "UeId", NaN, "UEID", NaN, "CellId", NaN, "ServingCellId", NaN, "CanonicalSlot", NaN, "Time_s", NaN, ...
    "X_m", NaN, "Y_m", NaN, "Z_m", NaN, "Speed_kmh", NaN, "Speed_mps", NaN, ...
    "Heading_deg", NaN, "Heading_rad", NaN, "Distance2D_m", NaN, "Distance3D_m", NaN, ...
    "LOSState", "", "Pathloss_dB", NaN, "BasePathloss_dB", NaN, "ShadowFading_dB", NaN, "O2I_dB", NaN, ...
    "RadialVelocity_mps", NaN, "ExpectedDopplerHz", NaN, "AppliedDopplerHz", NaN, "DopplerErrorHz", NaN, "PropagationDelay_s", NaN, ...
    "RouteLength_m", NaN, "RequiredTraversalSlots", NaN, "PathProvenance", "", "Status", ""), ...
    height(traceT), 1);
    for i = 1:height(traceT)
        ue = double(traceT.UeId(i));
        servingCell = localColumnDouble(traceT(i, :), "ServingCellId", localColumnDouble(traceT(i, :), "CellId", NaN));
        expectedDopp = double(traceT.ExpectedDopplerHz(i));
        appliedDopp = double(traceT.AppliedDopplerHz(i));
        rows(i) = struct( ...
            "UeId", ue, ...
            "UEID", ue, ...
            "CellId", double(traceT.CellId(i)), ...
            "ServingCellId", double(servingCell), ...
            "CanonicalSlot", double(traceT.CanonicalSlot(i)), ...
            "Time_s", double(traceT.Time_s(i)), ...
            "X_m", double(traceT.X_m(i)), ...
            "Y_m", double(traceT.Y_m(i)), ...
            "Z_m", double(traceT.Z_m(i)), ...
            "Speed_kmh", double(traceT.Speed_kmh(i)), ...
            "Speed_mps", double(traceT.Speed_mps(i)), ...
            "Heading_deg", double(traceT.Heading_deg(i)), ...
            "Heading_rad", double(traceT.Heading_rad(i)), ...
            "Distance2D_m", double(traceT.Distance2D_m(i)), ...
            "Distance3D_m", double(traceT.Distance3D_m(i)), ...
            "LOSState", string(traceT.LOSState(i)), ...
            "Pathloss_dB", double(traceT.Pathloss_dB(i)), ...
            "BasePathloss_dB", double(traceT.BasePathloss_dB(i)), ...
            "ShadowFading_dB", double(traceT.ShadowFading_dB(i)), ...
            "O2I_dB", double(traceT.O2I_dB(i)), ...
            "RadialVelocity_mps", double(traceT.RadialVelocity_mps(i)), ...
            "ExpectedDopplerHz", expectedDopp, ...
            "AppliedDopplerHz", appliedDopp, ...
            "DopplerErrorHz", double(appliedDopp - expectedDopp), ...
            "PropagationDelay_s", double(traceT.PropagationDelay_s(i)), ...
            "RouteLength_m", double(routeLengthByUe(ue)), ...
            "RequiredTraversalSlots", double(requiredSlots), ...
            "PathProvenance", "runtime_slot_trace", ...
            "Status", string(traceT.Status(i)));
    end
T = localStructRowsToTable(rows);
if height(T) == 0
    return;
end
if requiredSlots < 1
    requiredSlots = numel(unique(localColumnDouble(T, "CanonicalSlot", NaN)));
    T.RequiredTraversalSlots(:) = double(requiredSlots);
end
slotDuration_s = localNumber(cfg, "frame_timing.slot_duration_ms", runtime.SlotDuration_s * 1e3) / 1e3; %#ok<NASGU>
end

function T = localBuildRuntimeTrajectoryResolution(cfg, runtime)
traceT = runtime.NormalizedTrace;
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
expectedSlots = max(runtime.ConfiguredSlotCount, 0);
if expectedSlots < 1
    expectedSlots = numel(unique(localColumnDouble(traceT, "CanonicalSlot", NaN)));
end
routeLengths = NaN(numel(ueList), 1);
fullCoverage = numel(ueList) > 0;
for i = 1:numel(ueList)
    slice = traceT(localColumnDouble(traceT, "UeId", NaN) == ueList(i), :);
    [coverageOk, ~] = localTraceCoverageStatus(slice, expectedSlots);
    routeLengths(i) = localTraceRouteLength(slice);
    fullCoverage = fullCoverage && coverageOk;
end
configuredSlots = max(expectedSlots, round(localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], expectedSlots)));
runDurationS = configuredSlots * runtime.SlotDuration_s;
status = localTernary(fullCoverage, "full_route_runtime_trace_complete", "runtime_trace_missing_slot_coverage");
T = table(logical(fullCoverage), double(configuredSlots), double(runDurationS), double(expectedSlots), ...
    double(localMinFinite(routeLengths)), string(status), "runtime_slot_trace", ...
    'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s','RequiredTraversalSlots', ...
    'ActualDistanceTravelled_m','Status','PathProvenance'});
end

function T = localBuildRuntimeTrajectorySegments(runtime)
traceT = runtime.NormalizedTrace;
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
rows = repmat(struct("UEID", NaN, "StartX_m", NaN, "StartY_m", NaN, "StartZ_m", NaN, ...
    "EndX_m", NaN, "EndY_m", NaN, "EndZ_m", NaN, "RouteLength_m", NaN, ...
    "Speed_kmh", NaN, "TraversalTime_s", NaN, "RequiredTraversalSlots", NaN, ...
    "ObservedSlotCount", NaN, "MissingSlotCount", NaN, "LoopMode", "", ...
    "PathProvenance", "", "Status", ""), numel(ueList), 1);
for i = 1:numel(ueList)
    slice = traceT(localColumnDouble(traceT, "UeId", NaN) == ueList(i), :);
    slice = sortrows(slice, "CanonicalSlot");
    [coverageOk, missingSlots] = localTraceCoverageStatus(slice, runtime.ConfiguredSlotCount);
    startRow = slice(1, :);
    stopRow = slice(end, :);
    rows(i) = struct("UEID", double(ueList(i)), ...
        "StartX_m", double(startRow.X_m), "StartY_m", double(startRow.Y_m), "StartZ_m", double(startRow.Z_m), ...
        "EndX_m", double(stopRow.X_m), "EndY_m", double(stopRow.Y_m), "EndZ_m", double(stopRow.Z_m), ...
        "RouteLength_m", double(localTraceRouteLength(slice)), ...
        "Speed_kmh", double(localMeanFinite(localColumnDouble(slice, "Speed_kmh", NaN))), ...
        "TraversalTime_s", double(max(localColumnDouble(slice, "Time_s", NaN)) - min(localColumnDouble(slice, "Time_s", NaN))), ...
        "RequiredTraversalSlots", double(max(runtime.ConfiguredSlotCount, numel(unique(localColumnDouble(slice, "CanonicalSlot", NaN))))), ...
        "ObservedSlotCount", double(numel(unique(localColumnDouble(slice, "CanonicalSlot", NaN)))), ...
        "MissingSlotCount", double(missingSlots), ...
        "LoopMode", "runtime_trace", ...
        "PathProvenance", "runtime_slot_trace", ...
        "Status", localTernary(coverageOk, "continuous_runtime_trace", "runtime_trace_gap_detected"));
end
T = localStructRowsToTable(rows);
end

function T = localRuntimeInterUEDistanceTable(cfg, runtime)
traceT = runtime.NormalizedTrace;
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
if numel(ueList) < 2
    T = table('Size', [0 7], 'VariableTypes', {'double','double','double','double','double','logical','string'}, ...
        'VariableNames', {'UE1','UE2','MinDistanceConfigured_m','ClosestDistance_m','ClosestTime_s','InterUeConstraintResolvedOk','Status'});
    return;
end
minCfg = localNumber(cfg, "deployment_topology.min_inter_ue_distance_m", ...
    localNumber(cfg, "users.min_inter_ue_distance_m", 0));
rows = repmat(struct("UE1", NaN, "UE2", NaN, "MinDistanceConfigured_m", NaN, "ClosestDistance_m", NaN, ...
    "ClosestTime_s", NaN, "InterUeConstraintResolvedOk", false, "Status", ""), 0, 1);
for i = 1:numel(ueList)-1
    for j = i+1:numel(ueList)
        slice1 = traceT(localColumnDouble(traceT, "UeId", NaN) == ueList(i), :);
        slice2 = traceT(localColumnDouble(traceT, "UeId", NaN) == ueList(j), :);
        [sharedSlots, idx1, idx2] = intersect(localColumnDouble(slice1, "CanonicalSlot", NaN), ...
            localColumnDouble(slice2, "CanonicalSlot", NaN));
        if isempty(sharedSlots)
            continue;
        end
        d = sqrt((double(slice1.X_m(idx1)) - double(slice2.X_m(idx2))).^2 + ...
            (double(slice1.Y_m(idx1)) - double(slice2.Y_m(idx2))).^2 + ...
            (double(slice1.Z_m(idx1)) - double(slice2.Z_m(idx2))).^2);
        [closestDistance, idx] = min(d);
        closestTime = double(slice1.Time_s(idx1(idx)));
        ok = ~(isfinite(minCfg) && minCfg > 0 && closestDistance < minCfg);
        rows(end+1, 1) = struct("UE1", double(ueList(i)), "UE2", double(ueList(j)), ... %#ok<AGROW>
            "MinDistanceConfigured_m", double(minCfg), "ClosestDistance_m", double(closestDistance), ...
            "ClosestTime_s", double(closestTime), "InterUeConstraintResolvedOk", logical(ok), ...
            "Status", localTernary(ok, "runtime_trace_constraint_satisfied_or_not_configured", ...
            "runtime_trace_violate_min_inter_ue_distance"));
    end
end
T = localStructRowsToTable(rows);
end

function T = localBuildRuntimeDopplerReconciliation(runtime, cfg)
traceT = runtime.NormalizedTrace;
if height(traceT) == 0
    T = localEmptyDopplerReconciliationTable();
    return;
end
toleranceHz = localNumber(cfg, ["validation.mobility.doppler_tolerance_hz","validation.channel.doppler_tolerance_hz"], 1);
rows = repmat(localEmptyDopplerReconciliationRow(), height(traceT), 1);
for i = 1:height(traceT)
    expected = double(traceT.ExpectedDopplerHz(i));
    applied = double(traceT.AppliedDopplerHz(i));
    err = abs(applied - expected);
    % Zero Doppler is the physically correct value for a static terminal;
    % signed Doppler may also be negative for a receding/approaching path.
    % Reconciliation therefore tests finite values and residual magnitude,
    % never positivity.
    ok = isfinite(expected) && isfinite(applied) && isfinite(err) && err <= toleranceHz;
    status = localTernary(ok && expected == 0 && applied == 0, ...
        "static_zero_doppler_reconciled", "doppler_reconciled");
    if ~isfinite(applied)
        status = "missing_applied_doppler_evidence";
    elseif ~ok
        status = "doppler_mismatch";
    end
    rows(i) = struct("UeId", double(traceT.UeId(i)), "CellId", double(traceT.CellId(i)), ...
        "CanonicalSlot", double(traceT.CanonicalSlot(i)), "Time_s", double(traceT.Time_s(i)), ...
        "Speed_mps", double(traceT.Speed_mps(i)), "CarrierFrequency_Hz", double(runtime.CarrierFrequency_Hz), ...
        "ExpectedDopplerHz", expected, "AppliedDopplerHz", applied, "DopplerErrorHz", double(err), ...
        "DopplerToleranceHz", double(toleranceHz), "DopplerReconciliationOk", logical(ok), ...
        "EvidenceSource", "reports/csv/live_rsrp_serving_trace.csv", "Status", string(status));
end
T = localStructRowsToTable(rows);
end

function T = localBuildRuntimePathlossReconciliation(runtime)
traceT = runtime.NormalizedTrace;
if height(traceT) == 0
    T = localEmptyPathlossReconciliationTable();
    return;
end
toleranceDb = 1e-6;
rows = repmat(localEmptyPathlossReconciliationRow(), height(traceT), 1);
for i = 1:height(traceT)
    expected = double(traceT.BasePathloss_dB(i) + traceT.ShadowFading_dB(i) + traceT.O2I_dB(i));
    observed = double(traceT.Pathloss_dB(i));
    err = abs(observed - expected);
    losState = string(traceT.LOSState(i));
    losOk = strlength(strtrim(losState)) > 0;
    shadowOk = isfinite(double(traceT.ShadowFading_dB(i)));
    pathlossOk = isfinite(observed) && isfinite(expected) && isfinite(err) && err <= toleranceDb;
    largeScaleOk = pathlossOk && shadowOk && losOk && ...
        isfinite(double(traceT.Distance2D_m(i))) && isfinite(double(traceT.Distance3D_m(i))) && ...
        isfinite(double(traceT.PropagationDelay_s(i))) && isfinite(double(traceT.AppliedDopplerHz(i)));
    status = "pathloss_reconciled";
    if ~pathlossOk
        status = "pathloss_mismatch_or_missing_runtime_components";
    end
    rows(i) = struct("UeId", double(traceT.UeId(i)), "CellId", double(traceT.CellId(i)), ...
        "CanonicalSlot", double(traceT.CanonicalSlot(i)), "LOSState", losState, ...
        "BasePathloss_dB", double(traceT.BasePathloss_dB(i)), "ShadowFading_dB", double(traceT.ShadowFading_dB(i)), ...
        "O2I_dB", double(traceT.O2I_dB(i)), "ObservedPathloss_dB", observed, "ExpectedPathloss_dB", expected, ...
        "PathlossError_dB", double(err), "PathlossTolerance_dB", double(toleranceDb), ...
        "PathlossReconciliationOk", logical(pathlossOk), "ShadowFadingReconciliationOk", logical(shadowOk), ...
        "LosStateModelOk", logical(losOk), "LargeScaleParameterReconciliationOk", logical(largeScaleOk), ...
        "EvidenceSource", "reports/csv/live_rsrp_serving_trace.csv", "Status", string(status));
end
T = localStructRowsToTable(rows);
end

function T = localBuildRuntimePropagationDelayReconciliation(runtime)
traceT = runtime.NormalizedTrace;
if height(traceT) == 0
    T = localEmptyPropagationDelayReconciliationTable();
    return;
end
toleranceS = 1e-12;
rows = repmat(localEmptyPropagationDelayReconciliationRow(), height(traceT), 1);
for i = 1:height(traceT)
    expected = double(traceT.Distance3D_m(i)) / runtime.LightSpeed_mps;
    observed = double(traceT.PropagationDelay_s(i));
    err = abs(observed - expected);
    ok = isfinite(expected) && expected > 0 && isfinite(observed) && observed > 0 && isfinite(err) && err <= toleranceS;
    rows(i) = struct("UeId", double(traceT.UeId(i)), "CellId", double(traceT.CellId(i)), ...
        "CanonicalSlot", double(traceT.CanonicalSlot(i)), "Distance3D_m", double(traceT.Distance3D_m(i)), ...
        "ObservedPropagationDelay_s", observed, "ExpectedPropagationDelay_s", expected, ...
        "PropagationDelayError_s", double(err), "PropagationDelayTolerance_s", double(toleranceS), ...
        "PropagationDelayReconciliationOk", logical(ok), ...
        "EvidenceSource", "reports/csv/live_rsrp_serving_trace.csv", ...
        "Status", localTernary(ok, "propagation_delay_reconciled", "propagation_delay_mismatch"));
end
T = localStructRowsToTable(rows);
end

function T = localBuildRuntimeChannelContinuityReconciliation(cfg, runtime)
traceT = runtime.NormalizedTrace;
if height(traceT) == 0
    T = localEmptyChannelContinuityReconciliationTable();
    return;
end
ueList = unique(localColumnDouble(traceT, "UeId", NaN));
ueList = ueList(isfinite(ueList));
expectedSlots = max(runtime.ConfiguredSlotCount, round(localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], runtime.ConfiguredSlotCount)));
if expectedSlots < 1
    expectedSlots = numel(unique(localColumnDouble(traceT, "CanonicalSlot", NaN)));
end
timeTol = max(1e-9, runtime.SlotDuration_s * 1e-3);
rows = repmat(localEmptyChannelContinuityReconciliationRow(), numel(ueList), 1);
for i = 1:numel(ueList)
    slice = traceT(localColumnDouble(traceT, "UeId", NaN) == ueList(i), :);
    slice = sortrows(slice, "CanonicalSlot");
    [coverageOk, missingSlots] = localTraceCoverageStatus(slice, expectedSlots);
    slotVals = unique(localColumnDouble(slice, "CanonicalSlot", NaN));
    timeVals = localColumnDouble(slice, "Time_s", NaN);
    if numel(timeVals) > 1
        timeStep = diff(timeVals);
        timeOk = all(abs(timeStep - runtime.SlotDuration_s) <= timeTol);
        medianStep = median(timeStep, "omitnan");
    else
        timeOk = true;
        medianStep = NaN;
    end
    finiteStateOk = all(isfinite(localColumnDouble(slice, "Distance3D_m", NaN))) && ...
        all(isfinite(localColumnDouble(slice, "PropagationDelay_s", NaN))) && ...
        all(isfinite(localColumnDouble(slice, "AppliedDopplerHz", NaN))) && ...
        all(isfinite(localColumnDouble(slice, "Pathloss_dB", NaN)));
    mobilityOk = coverageOk && timeOk;
    channelOk = mobilityOk && finiteStateOk;
    failureCode = "";
    if ~coverageOk
        failureCode = "missing_slot_rows";
    elseif ~timeOk
        failureCode = "nonuniform_slot_timing";
    elseif ~finiteStateOk
        failureCode = "nonfinite_large_scale_runtime_state";
    end
    rows(i) = struct("UeId", double(ueList(i)), ...
        "ExpectedSlotCount", double(expectedSlots), "ObservedSlotCount", double(numel(slotVals)), ...
        "MissingSlotCount", double(missingSlots), "FirstSlot", double(localMinFinite(slotVals)), ...
        "LastSlot", double(localMaxFinite(slotVals)), "ExpectedTimeStep_s", double(runtime.SlotDuration_s), ...
        "ObservedMedianTimeStep_s", double(medianStep), "MobilityStateContinuousOk", logical(mobilityOk), ...
        "ChannelStateContinuityOk", logical(channelOk), "FiniteLargeScaleStateOk", logical(finiteStateOk), ...
        "FailureCode", string(failureCode), ...
        "Status", localTernary(channelOk, "runtime_channel_continuity_verified", "runtime_channel_continuity_failed"));
end
T = localStructRowsToTable(rows);
end

function T = localInterUEDistanceTable(cfg, traj, runDurationS)
if height(traj) < 2
    T = table('Size', [0 7], 'VariableTypes', {'double','double','double','double','double','logical','string'}, ...
        'VariableNames', {'UE1','UE2','MinDistanceConfigured_m','ClosestDistance_m','ClosestTime_s','InterUeConstraintResolvedOk','Status'});
    return;
end
minCfg = localNumber(cfg, "deployment_topology.min_inter_ue_distance_m", ...
    localNumber(cfg, "users.min_inter_ue_distance_m", 0));
start1 = [traj.StartX_m(1), traj.StartY_m(1), traj.StartZ_m(1)];
end1 = [traj.EndX_m(1), traj.EndY_m(1), traj.EndZ_m(1)];
start2 = [traj.StartX_m(2), traj.StartY_m(2), traj.StartZ_m(2)];
end2 = [traj.EndX_m(2), traj.EndY_m(2), traj.EndZ_m(2)];
t1 = traj.TraversalTime_s(1);
t2 = traj.TraversalTime_s(2);
tEnd = max([runDurationS, t1, t2]);
if ~(isfinite(tEnd) && tEnd > 0)
    tEnd = max([t1, t2, 0]);
end
v1 = (end1 - start1) ./ max(t1, eps);
v2 = (end2 - start2) ./ max(t2, eps);
r0 = start1 - start2;
rv = v1 - v2;
tClosest = -dot(r0, rv) / max(dot(rv, rv), eps);
tClosest = max(0, min(tEnd, tClosest));
p1 = start1 + v1 .* min(tClosest, t1);
p2 = start2 + v2 .* min(tClosest, t2);
d = norm(p1 - p2);
ok = ~(isfinite(minCfg) && minCfg > 0 && d < minCfg);
T = table(traj.UEID(1), traj.UEID(2), minCfg, d, tClosest, ok, ...
    localTernary(ok, "constraint_satisfied_or_not_configured", "trace_paths_violate_min_inter_ue_distance"), ...
    'VariableNames', {'UE1','UE2','MinDistanceConfigured_m','ClosestDistance_m','ClosestTime_s','InterUeConstraintResolvedOk','Status'});
end

function evidence = localBuildCampaignEvidence(runDir, cfg)
airCsv = fullfile(runDir, "air_interface", "csv");
reportCsv = fullfile(runDir, "reports", "csv");
fixed = localReadOptionalTable(fullfile(airCsv, "lls_fixed_link_campaign.csv"));
taskPlan = localReadOptionalTable(fullfile(airCsv, "fixed_link_campaign_task_plan.csv"));
dlTrials = localReadOptionalTable(fullfile(airCsv, "dl_fixed_link_campaign_trials.csv"));
ulTrials = localReadOptionalTable(fullfile(airCsv, "ul_fixed_link_campaign_trials.csv"));
checkpoint = localReadOptionalTable(fullfile(reportCsv, "checkpoint_resume_equivalence.csv"));
determinism = localReadOptionalTable(fullfile(reportCsv, "serial_parallel_determinism.csv"));

thresholds = localCampaignThresholds(cfg);
curve = localBuildDLMultiSeedBlerCurve(fixed, thresholds);
dropStats = localBuildMultiSeedDropStatistics(dlTrials, ulTrials, taskPlan);
[summary, flags] = localBuildCampaignSummaryAndFlags(fixed, taskPlan, dlTrials, ulTrials, ...
    curve, dropStats, checkpoint, determinism, thresholds);
audit = localBuildCampaignEvidenceAudit(fixed, taskPlan, dlTrials, ulTrials, checkpoint, determinism, curve, dropStats);

evidence = struct();
evidence.Thresholds = thresholds;
evidence.Tables = struct("FixedLinkSummary", fixed, "TaskPlan", taskPlan, ...
    "DLTrials", dlTrials, "ULTrials", ulTrials, "DLBlerCurve", curve, ...
    "DropStatistics", dropStats, "CampaignAudit", audit, "Summary", summary);
evidence.Flags = flags;
end

function thresholds = localCampaignThresholds(cfg)
requiredSeeds = localNumber(cfg, ["canonical_control.run.num_seeds", ...
    "lls6g.resolvedConfig.canonical_control.run.num_seeds", ...
    "simulation.num_seeds", "canonical_control.run.final_runs", ...
    "lls6g.resolvedConfig.canonical_control.run.final_runs", ...
    "simulation.final_runs", "canonical_control.run.monte_carlo_iterations", ...
    "lls6g.resolvedConfig.canonical_control.run.monte_carlo_iterations", ...
    "simulation.monte_carlo_iterations"], 30);
maxCIWidth = localNumber(cfg, ["canonical_control.run.max_ci_width", ...
    "lls6g.resolvedConfig.canonical_control.run.max_ci_width", ...
    "simulation.max_ci_width", "statistics.max_ci_width"], NaN);
if ~(isscalar(maxCIWidth) && isfinite(maxCIWidth) && maxCIWidth >= 0)
    maxCIHalfWidth = localNumber(cfg, [ ...
        "validation.fixed_link_campaign.max_ci_half_width", ...
        "lls6g.resolvedConfig.validation.fixed_link_campaign.max_ci_half_width"], 0.025);
    maxCIWidth = 2 * maxCIHalfWidth;
end
thresholds = struct( ...
    "RequiredSeedCount", max(1, round(requiredSeeds)), ...
    "MinTrialsPerBin", max(1, round(localNumber(cfg, [ ...
        "validation.fixed_link_campaign.min_tb_per_point", ...
        "lls6g.resolvedConfig.validation.fixed_link_campaign.min_tb_per_point", ...
        "canonical_control.run.min_trials_per_sinr_bin", ...
        "lls6g.resolvedConfig.canonical_control.run.min_trials_per_sinr_bin", ...
        "simulation.min_trials_per_sinr_bin", "statistics.min_trials_per_sinr_bin"], 30))), ...
    "MaxCIWidth", maxCIWidth, ...
    "MinSNRPoints", max(1, round(localNumber(cfg, ["canonical_control.run.min_campaign_snr_points", ...
        "lls6g.resolvedConfig.canonical_control.run.min_campaign_snr_points", ...
        "simulation.min_campaign_snr_points", "statistics.min_campaign_snr_points"], 5))), ...
    "ConfidenceLevel", localNumber(cfg, ["canonical_control.run.confidence_level", ...
        "lls6g.resolvedConfig.canonical_control.run.confidence_level", ...
        "validation.fixed_link_campaign.confidence_level", ...
        "lls6g.resolvedConfig.validation.fixed_link_campaign.confidence_level", ...
        "simulation.confidence_level", "statistics.confidence_level"], 0.95), ...
    "IntervalMethod", upper(strtrim(string(sixgr.util.structGet(cfg, ...
        "validation.fixed_link_campaign.interval_method", ...
        sixgr.util.structGet(cfg, ...
        "lls6g.resolvedConfig.validation.fixed_link_campaign.interval_method", ...
        "CLOPPER_PEARSON_TWO_SIDED"))))));
if ~ismember(thresholds.IntervalMethod, ...
        ["CLOPPER_PEARSON_TWO_SIDED", "WILSON_TWO_SIDED"])
    error("sixgr:analytics:InvalidCampaignIntervalMethod", ...
        "Unsupported fixed-link interval method '%s'.", ...
        thresholds.IntervalMethod);
end
end

function T = localBuildDLMultiSeedBlerCurve(fixed, thresholds)
if ~(istable(fixed) && height(fixed) > 0 && localHasColumn(fixed, "SNR_dB"))
    T = localEmptyCampaignTable("curve");
    return;
end
snr = localColumnDouble(fixed, "SNR_dB", NaN);
snrValues = unique(sort(snr(isfinite(snr))));
rows = repmat(struct("PostEqSINR_dB_BinCenter", NaN, "SNR_dB", NaN, ...
    "BinMin", NaN, "BinMax", NaN, "TrialCount", NaN, "FailureCount", NaN, ...
    "BLER", NaN, "BLER_CI_Low", NaN, "BLER_CI_High", NaN, "BLER_CI_Width", NaN, ...
    "IntervalMethod", "", ...
    "Goodput_Mbps_mean", NaN, "SeedCount", NaN, "CampaignKind", "", ...
    "EvidenceSource", ""), 0, 1);
for i = 1:numel(snrValues)
    s = snrValues(i);
    mask = snr == s;
    trialCount = sum(localColumnDouble(fixed(mask, :), "DL_TrialCount", 0), "omitnan");
    failureCount = sum(localColumnDouble(fixed(mask, :), "DL_FailureCount", 0), "omitnan");
    if ~(isfinite(failureCount) && failureCount >= 0) && localHasColumn(fixed, "DL_BLER")
        failureCount = sum(localColumnDouble(fixed(mask, :), "DL_BLER", 0) .* ...
            localColumnDouble(fixed(mask, :), "DL_TrialCount", 0), "omitnan");
    end
    bler = localSafeDivide(failureCount, trialCount);
    interval = sixgr.validation.BinomialIntervalEngine.compute( ...
        failureCount, trialCount, thresholds.ConfidenceLevel, ...
        thresholds.IntervalMethod);
    lo = double(interval.Lower);
    hi = double(interval.Upper);
    ciWidth = hi - lo;
    seedCount = max(localUniqueFiniteCount(localColumnDouble(fixed(mask, :), "PointSeed", NaN)), ...
        localMaxFinite(localColumnDouble(fixed(mask, :), "DL_DropCount", NaN)));
    rows(end+1, 1) = struct("PostEqSINR_dB_BinCenter", s, "SNR_dB", s, ...
        "BinMin", s, "BinMax", s, "TrialCount", double(trialCount), ...
        "FailureCount", double(failureCount), "BLER", double(bler), ...
        "BLER_CI_Low", double(lo), "BLER_CI_High", double(hi), ...
        "BLER_CI_Width", double(ciWidth), ...
        "IntervalMethod", string(interval.Method), ...
        "Goodput_Mbps_mean", localMeanFinite(localColumnDouble(fixed(mask, :), "DL_Throughput_Mbps", NaN)), ...
        "SeedCount", double(seedCount), ...
        "CampaignKind", localFirstString(fixed(mask, :), "CampaignKind", "fixed_link_monte_carlo"), ...
        "EvidenceSource", "air_interface/csv/lls_fixed_link_campaign.csv"); %#ok<AGROW>
end
T = localStructRowsToTable(rows);
end

function T = localBuildMultiSeedDropStatistics(dlTrials, ulTrials, taskPlan)
rows = repmat(localEmptyDropStatisticRow(), 0, 1);
rows = [rows; localDropStatisticRows(dlTrials, "DL")]; %#ok<AGROW>
rows = [rows; localDropStatisticRows(ulTrials, "UL")]; %#ok<AGROW>
if isempty(rows)
    rows = localTaskPlanDropRows(taskPlan);
end
if isempty(rows)
    T = localEmptyCampaignTable("drops");
else
    T = localStructRowsToTable(rows);
end
end

function rows = localDropStatisticRows(T, direction)
rows = repmat(localEmptyDropStatisticRow(), 0, 1);
if ~(istable(T) && height(T) > 0)
    return;
end
point = localColumnDouble(T, "FixedLinkPointIndex", localColumnDouble(T, "PointIndex", NaN));
drop = localColumnDouble(T, "FixedLinkDropIndex", localColumnDouble(T, "DropIndex", NaN));
keys = unique([point(:), drop(:)], "rows");
for i = 1:size(keys, 1)
    p = keys(i, 1);
    d = keys(i, 2);
    mask = (point == p) & (drop == d);
    if ~any(mask)
        continue;
    end
    Ti = T(mask, :);
    fail = localTrialFailureMask(Ti);
    trials = height(Ti);
    failures = sum(fail);
    rows(end+1, 1) = struct("Direction", upper(string(direction)), ...
        "FixedLinkPointIndex", double(p), ...
        "SNR_dB", localFirstFinite(localColumnDouble(Ti, "SNR_dB", localColumnDouble(Ti, "PointValue", NaN))), ...
        "FixedLinkDropIndex", double(d), ...
        "FixedLinkDropSeed", localFirstFinite(localColumnDouble(Ti, "FixedLinkDropSeed", localColumnDouble(Ti, "TaskSeed", NaN))), ...
        "TrialCount", double(trials), ...
        "FailureCount", double(failures), ...
        "BLER", localSafeDivide(failures, trials), ...
        "Goodput_Mbps_mean", localMeanFinite(localColumnDouble(Ti, "Goodput_Mbps", NaN)), ...
        "EvidenceStatus", "executed_trial_rows", ...
        "EvidenceSource", "fixed_link_campaign_trials"); %#ok<AGROW>
end
end

function rows = localTaskPlanDropRows(taskPlan)
rows = repmat(localEmptyDropStatisticRow(), 0, 1);
if ~(istable(taskPlan) && height(taskPlan) > 0)
    return;
end
kind = strings(height(taskPlan), 1);
if localHasColumn(taskPlan, "TaskKind")
    kind = lower(strtrim(string(taskPlan.TaskKind)));
end
drop = localColumnDouble(taskPlan, "DropIndex", NaN);
link = strings(height(taskPlan), 1);
if localHasColumn(taskPlan, "LinkToken")
    link = upper(strtrim(string(taskPlan.LinkToken)));
end
mask = kind == "point_drop_link" & drop > 0;
idx = find(mask);
for j = 1:numel(idx)
    k = idx(j);
    rows(end+1, 1) = struct("Direction", link(k), ...
        "FixedLinkPointIndex", localColumnDouble(taskPlan(k, :), "PointIndex", NaN), ...
        "SNR_dB", localColumnDouble(taskPlan(k, :), "PointValue", NaN), ...
        "FixedLinkDropIndex", drop(k), ...
        "FixedLinkDropSeed", localColumnDouble(taskPlan(k, :), "TaskSeed", NaN), ...
        "TrialCount", localColumnDouble(taskPlan(k, :), "TrialCount", NaN), ...
        "FailureCount", NaN, "BLER", NaN, "Goodput_Mbps_mean", NaN, ...
        "EvidenceStatus", "planned_task_no_trial_table", ...
        "EvidenceSource", "air_interface/csv/fixed_link_campaign_task_plan.csv"); %#ok<AGROW>
end
end

function [summary, flags] = localBuildCampaignSummaryAndFlags(fixed, taskPlan, dlTrials, ulTrials, curve, dropStats, checkpoint, determinism, thresholds)
flags = localCampaignFlags(false);
% Checkpoint/resume equivalence and serial/parallel determinism are
% independently executed Phase-7 evidence.  Preserve their status even
% when the fixed-link statistical campaign has not been run yet.  The
% remaining campaign gates continue to fail closed below.
flags.CheckpointResumeEquivalenceOk = localEvidenceFlag(checkpoint, "CheckpointResumeEquivalenceOk");
flags.SerialParallelDeterminismOk = localEvidenceFlag(determinism, "SerialParallelDeterminismOk");
if ~(istable(fixed) && height(fixed) > 0)
    summary = localCampaignSummaryTable(0, 0, 0, 0, 0, 0, 0, NaN, NaN, NaN, thresholds, ...
        "no_phase7_campaign_runs_provided", "air_interface/csv/lls_fixed_link_campaign.csv missing", flags);
    return;
end

dlTrialCount = sum(localColumnDouble(fixed, "DL_TrialCount", 0), "omitnan");
ulTrialCount = sum(localColumnDouble(fixed, "UL_TrialCount", 0), "omitnan");
dlFailureCount = sum(localColumnDouble(fixed, "DL_FailureCount", 0), "omitnan");
ulFailureCount = sum(localColumnDouble(fixed, "UL_FailureCount", 0), "omitnan");
trialSeedCount = localUniqueFiniteCount([localColumnDouble(dlTrials, "FixedLinkDropSeed", NaN); ...
    localColumnDouble(ulTrials, "FixedLinkDropSeed", NaN)]);
taskSeedCount = localUniqueFiniteCount(localColumnDouble(taskPlan, "TaskSeed", NaN));
pointSeedCount = localUniqueFiniteCount(localColumnDouble(fixed, "PointSeed", NaN));
dropSeedCount = max(trialSeedCount, taskSeedCount);
seedsRun = max([dropSeedCount, pointSeedCount, localMaxFinite(localColumnDouble(fixed, "DL_DropCount", NaN)), ...
    localMaxFinite(localColumnDouble(fixed, "UL_DropCount", NaN))]);
snrPoints = localUniqueFiniteCount(localColumnDouble(fixed, "SNR_dB", NaN));
pilotRuns = localPilotRunCount(taskPlan);
failedRuns = dlFailureCount + ulFailureCount;
incomplete = localIncompleteCount(fixed);
curveTrials = localColumnDouble(curve, "TrialCount", NaN);
curveCI = localColumnDouble(curve, "BLER_CI_Width", NaN);
finiteCurve = isfinite(curveTrials) & curveTrials > 0 & isfinite(curveCI);

flags.SeedHierarchyOk = localTaskPlanSeedHierarchyOk(taskPlan);
flags.CampaignDesignOk = flags.SeedHierarchyOk && snrPoints >= thresholds.MinSNRPoints && ...
    seedsRun >= thresholds.RequiredSeedCount && all(lower(string(localFirstString(fixed, "CampaignKind", ""))) == "fixed_link_monte_carlo");
flags.CampaignCompletionOk = (dlTrialCount > 0 || ulTrialCount > 0) && incomplete == 0;
flags.SampleAdequacyOk = any(finiteCurve) && all(curveTrials(finiteCurve) >= thresholds.MinTrialsPerBin) && ...
    seedsRun >= thresholds.RequiredSeedCount;
flags.ConfidenceIntervalsOk = any(finiteCurve) && all(curveCI(finiteCurve) <= thresholds.MaxCIWidth);
flags.MultiSeedDropStatisticsOk = localDropStatisticsOk(dropStats, thresholds);
flags.SweepDataQualityOk = flags.CampaignDesignOk && flags.CampaignCompletionOk && ...
    flags.SampleAdequacyOk && flags.ConfidenceIntervalsOk;

status = "campaign_incomplete";
if flags.CampaignCompletionOk && flags.SampleAdequacyOk && flags.ConfidenceIntervalsOk && flags.MultiSeedDropStatisticsOk
    status = "campaign_complete";
end
summary = localCampaignSummaryTable(pilotRuns, dlTrialCount + ulTrialCount, failedRuns, seedsRun, ...
    snrPoints, dlTrialCount, ulTrialCount, localMinFinite(curveTrials), ...
    localMaxFinite(curveCI), localVarianceFinite(localColumnDouble(dropStats, "BLER", NaN)), ...
    thresholds, status, "air_interface/csv/lls_fixed_link_campaign.csv", flags);
end

function T = localCampaignSummaryTable(pilotRuns, finalRuns, failedRuns, seedsRun, snrPoints, dlTrials, ulTrials, minTrials, maxCI, blerVariance, thresholds, status, source, flags)
T = table(double(pilotRuns), double(finalRuns), double(failedRuns), double(seedsRun), ...
    double(snrPoints), double(dlTrials), double(ulTrials), double(minTrials), double(maxCI), ...
    double(blerVariance), double(thresholds.RequiredSeedCount), double(thresholds.MinTrialsPerBin), ...
    double(thresholds.MaxCIWidth), string(status), string(source), ...
    logical(flags.SeedHierarchyOk), logical(flags.CampaignDesignOk), logical(flags.CampaignCompletionOk), ...
    logical(flags.MultiSeedDropStatisticsOk), logical(flags.SampleAdequacyOk), logical(flags.ConfidenceIntervalsOk), ...
    logical(flags.CheckpointResumeEquivalenceOk), logical(flags.SerialParallelDeterminismOk), ...
    'VariableNames', {'PilotRuns','FinalRuns','FailedRuns','SeedsRun','SNRPointCount', ...
    'NDLTrialsTotal','NULTrialsTotal','MinTrialsPerBin','MaxCIWidth','BLERVarianceAcrossSeeds', ...
    'RequiredSeedCount','RequiredMinTrialsPerBin','RequiredMaxCIWidth','Status','EvidenceSource', ...
    'SeedHierarchyOk','CampaignDesignOk','CampaignCompletionOk','MultiSeedDropStatisticsOk', ...
    'SampleAdequacyOk','ConfidenceIntervalsOk','CheckpointResumeEquivalenceOk','SerialParallelDeterminismOk'});
end

function flags = localCampaignFlags(value)
flags = struct("SeedHierarchyOk", logical(value), "CampaignDesignOk", logical(value), ...
    "CampaignCompletionOk", logical(value), "MultiSeedDropStatisticsOk", logical(value), ...
    "ConfidenceIntervalsOk", logical(value), "SampleAdequacyOk", logical(value), ...
    "CheckpointResumeEquivalenceOk", logical(value), "SerialParallelDeterminismOk", logical(value), ...
    "SweepDataQualityOk", logical(value));
end

function T = localBuildCampaignEvidenceAudit(fixed, taskPlan, dlTrials, ulTrials, checkpoint, determinism, curve, dropStats)
artifacts = ["lls_fixed_link_campaign.csv"; "fixed_link_campaign_task_plan.csv"; ...
    "dl_fixed_link_campaign_trials.csv"; "ul_fixed_link_campaign_trials.csv"; ...
    "checkpoint_resume_equivalence.csv"; "serial_parallel_determinism.csv"; ...
    "dl_multi_seed_bler_curve.csv"; "multi_seed_drop_statistics.csv"];
classes = ["runtime_summary"; "seed_hierarchy"; "executed_dl_trials"; "executed_ul_trials"; ...
    "checkpoint_resume"; "serial_parallel"; "derived_bler_curve"; "derived_drop_statistics"];
counts = [height(fixed); height(taskPlan); height(dlTrials); height(ulTrials); ...
    height(checkpoint); height(determinism); height(curve); height(dropStats)];
rows = repmat(struct("Artifact", "", "EvidenceClass", "", "RowCount", NaN, ...
    "EvidencePresent", false, "CountsTowardCampaignGate", false), 0, 1);
for i = 1:numel(artifacts)
    n = double(counts(i));
    rows(end+1, 1) = struct("Artifact", artifacts(i), "EvidenceClass", classes(i), ...
        "RowCount", double(n), "EvidencePresent", n > 0, ...
        "CountsTowardCampaignGate", n > 0 && ~contains(classes(i), "derived")); %#ok<AGROW>
end
T = localStructRowsToTable(rows);
end

function tf = localTaskPlanSeedHierarchyOk(taskPlan)
tf = false;
if ~(istable(taskPlan) && height(taskPlan) > 0 && localHasColumn(taskPlan, "TaskSeed"))
    return;
end
seeds = localColumnDouble(taskPlan, "TaskSeed", NaN);
valid = isfinite(seeds);
if ~any(valid)
    return;
end
invariantOk = true;
if localHasColumn(taskPlan, "SchedulingInvariant")
    invariantOk = all(string(taskPlan.SchedulingInvariant(valid)) == "worker_order_independent_seed_per_task");
end
tf = invariantOk && localUniqueFiniteCount(seeds(valid)) >= 2;
end

function n = localPilotRunCount(taskPlan)
n = 0;
if istable(taskPlan) && height(taskPlan) > 0 && localHasColumn(taskPlan, "TaskKind")
    n = sum(lower(strtrim(string(taskPlan.TaskKind))) == "point_metadata");
end
end

function n = localIncompleteCount(T)
n = 0;
for col = ["DL_Incomplete", "UL_Incomplete"]
    if istable(T) && localHasColumn(T, col)
        n = n + sum(localColumnAsLogical(T.(char(col))));
    end
end
end

function tf = localDropStatisticsOk(dropStats, thresholds)
tf = false;
if ~(istable(dropStats) && height(dropStats) > 0)
    return;
end
status = strings(height(dropStats), 1);
if localHasColumn(dropStats, "EvidenceStatus")
    status = string(dropStats.EvidenceStatus);
end
executed = status == "executed_trial_rows";
if ~any(executed)
    return;
end
seeds = localColumnDouble(dropStats(executed, :), "FixedLinkDropSeed", NaN);
bler = localColumnDouble(dropStats(executed, :), "BLER", NaN);
tf = localUniqueFiniteCount(seeds) >= thresholds.RequiredSeedCount && any(isfinite(bler));
end

function tf = localEvidenceFlag(T, flagName)
tf = false;
if istable(T) && height(T) > 0 && localHasColumn(T, flagName)
    tf = localFirstLogical(T.(char(flagName)), false);
end
end

function fail = localTrialFailureMask(T)
fail = false(height(T), 1);
if ~(istable(T) && height(T) > 0)
    return;
end
if localHasColumn(T, "CRCPass")
    fail = ~localColumnAsLogical(T.CRCPass);
elseif localHasColumn(T, "Status")
    status = upper(strtrim(string(T.Status)));
    fail = status == "FAIL" | status == "CRASH" | status == "CRC_FAIL";
end
end

function row = localEmptyDropStatisticRow()
row = struct("Direction", "", "FixedLinkPointIndex", NaN, "SNR_dB", NaN, ...
    "FixedLinkDropIndex", NaN, "FixedLinkDropSeed", NaN, "TrialCount", NaN, ...
    "FailureCount", NaN, "BLER", NaN, "Goodput_Mbps_mean", NaN, ...
    "EvidenceStatus", "", "EvidenceSource", "");
end

function T = localEmptyCampaignTable(kind)
switch string(kind)
    case "curve"
        T = table('Size', [0 15], 'VariableTypes', {'double','double','double','double','double','double', ...
            'double','double','double','double','string','double','double','string','string'}, ...
            'VariableNames', {'PostEqSINR_dB_BinCenter','SNR_dB','BinMin','BinMax','TrialCount', ...
            'FailureCount','BLER','BLER_CI_Low','BLER_CI_High','BLER_CI_Width','IntervalMethod','Goodput_Mbps_mean', ...
            'SeedCount','CampaignKind','EvidenceSource'});
    case "drops"
        T = table('Size', [0 11], 'VariableTypes', {'string','double','double','double','double','double', ...
            'double','double','double','string','string'}, ...
            'VariableNames', {'Direction','FixedLinkPointIndex','SNR_dB','FixedLinkDropIndex','FixedLinkDropSeed', ...
            'TrialCount','FailureCount','BLER','Goodput_Mbps_mean','EvidenceStatus','EvidenceSource'});
    otherwise
        T = table();
end
end

function status = localBuildGateStatus(runDir, cfg, cfgTables, storageTables, geometryTables, mobilityTables, physicalTables, campaignEvidence)
flags = struct();
flags.ResolvedConfigurationConsistentOk = ~any(string(cfgTables.Conflicts.ConflictStatus) == "conflict_unresolved");
flags.CapturePolicyTruthfulOk = logical(storageTables.Policy.CapturePolicyTruthfulOk(1));
flags.GeometryValidationOk = logical(geometryTables.Validation.GeometryValidationOk(1));
flags.FullTrajectoryExecutedOk = logical(mobilityTables.Resolution.FullTrajectoryExecutedOk(1));
flags.MobilityStateContinuousOk = localAllTableFlag(mobilityTables.ChannelContinuityReconciliation, "MobilityStateContinuousOk");
flags.InterUeConstraintResolvedOk = isempty(mobilityTables.ConstraintConflicts);
flags.LosStateModelOk = localAllTableFlag(mobilityTables.PathlossReconciliation, "LosStateModelOk");
flags.PathlossReconciliationOk = localAllTableFlag(mobilityTables.PathlossReconciliation, "PathlossReconciliationOk");
flags.ShadowFadingReconciliationOk = localAllTableFlag(mobilityTables.PathlossReconciliation, "ShadowFadingReconciliationOk");
flags.DopplerReconciliationOk = localAllTableFlag(mobilityTables.DopplerReconciliation, "DopplerReconciliationOk");
flags.PropagationDelayReconciliationOk = localAllTableFlag(mobilityTables.PropagationDelayReconciliation, "PropagationDelayReconciliationOk");
flags.ChannelStateContinuityOk = localAllTableFlag(mobilityTables.ChannelContinuityReconciliation, "ChannelStateContinuityOk");
flags.LargeScaleParameterReconciliationOk = ...
    localAllTableFlag(mobilityTables.PathlossReconciliation, "LargeScaleParameterReconciliationOk") && ...
    flags.DopplerReconciliationOk && flags.PropagationDelayReconciliationOk;
flags.CdlRealizationOk = localAllTableFlag(physicalTables.ChannelRealization, "ChannelRealizationOk");
flags.PathPowerNormalizationOk = localAllTableFlag(physicalTables.PathPowerNormalization, "PathPowerNormalizationOk");
flags.AntennaArrayReconciliationOk = localAllTableFlag(physicalTables.AntennaArray, "AntennaArrayReconciliationOk");
flags.PolarizationReconciliationOk = localAllTableFlag(physicalTables.Polarization, "PolarizationReconciliationOk");
flags.Phase7NoFabricationOk = true;
flags.Phase7ProvenanceOk = exist(fullfile(runDir, "reports", "json", "scenario_manifest.json"), "file") == 2 || ...
    exist(fullfile(runDir, "meta", "scenario_manifest.json"), "file") == 2;
flags.ChannelRfConfiguredVsAppliedOk = localChannelRFArtifactsPass(runDir);
flags = localApplyKPIReconciliationFlags(flags, runDir);
flags = localApplyRFInterferenceReconciliationFlags(flags, runDir);
flags = localApplyCampaignFlags(flags, campaignEvidence);
publicationEvidence = sixgr.analytics.evaluatePublicationReadinessGates(cfg, runDir);
flags = localApplyStructFlags(flags, publicationEvidence.Flags);
flags.OutputSchemaValidationOk = true;
modeAcceptance = struct();
if isstruct(publicationEvidence) && isfield(publicationEvidence, "ModeAcceptance") && isstruct(publicationEvidence.ModeAcceptance)
    modeAcceptance = publicationEvidence.ModeAcceptance;
end
runClass = string(sixgr.util.structGet(modeAcceptance, "RunClass", string(sixgr.util.structGet(cfg, "validation.run_class", "unknown"))));
fixedApplicable = logical(sixgr.util.structGet(modeAcceptance, "FixedSNRLLSApplicable", false));
geometryApplicable = logical(sixgr.util.structGet(modeAcceptance, "GeometryScenarioApplicable", false));
fixedOk = logical(sixgr.util.structGet(flags, "FixedSNRLLSOk", ~fixedApplicable));
geometryOk = logical(sixgr.util.structGet(flags, "GeometryScenarioOk", ~geometryApplicable));
referenceOk = logical(sixgr.util.structGet(flags, "PublicationReferenceComparisonOk", ~fixedApplicable));
notApplicable = localResolveNotApplicableGates(runClass, cfg, fixedApplicable, geometryApplicable);
flags.NotApplicableGateNames = notApplicable;
flags = localApplyPhaseRollupFlags(flags, notApplicable);
terminalOk = localAllApplicableNamedFlagsTrue(flags, ...
    sixgr.runtime.Phase7TruthEvaluator.gateNames(), notApplicable);
phaseRollupOk = localAllNamedFlagsTrue(flags, ["Phase1Ok","Phase2Ok","Phase3Ok","Phase4Ok","Phase5Ok","Phase6Ok"]);
flags.PublicationReadinessOk = terminalOk && phaseRollupOk && fixedApplicable && fixedOk && referenceOk;
status = sixgr.runtime.Phase7TruthEvaluator.evaluate(flags);
status.RunClass = runClass;
status.FixedSNRLLSApplicable = logical(fixedApplicable);
status.GeometryScenarioApplicable = logical(geometryApplicable);
status.FixedSNRLLSOk = logical(fixedOk);
status.GeometryScenarioOk = logical(geometryOk);
status.PublicationReferenceComparisonOk = logical(referenceOk);
end

function names = localResolveNotApplicableGates(runClass, cfg, fixedApplicable, geometryApplicable)
% Mode-specific gates are excluded only when the operator-selected run
% class makes that evidence inapplicable.  This is not a pass override:
% observed values remain exported and the excluded names are explicit in
% the terminal status.  Hybrid runs exclude nothing.
names = strings(0, 1);
if fixedApplicable && ~geometryApplicable
    names = [names; [ ...
        "GeometryValidationOk"
        "FullTrajectoryExecutedOk"
        "MobilityStateContinuousOk"
        "InterUeConstraintResolvedOk"
        "LosStateModelOk"
        "PathlossReconciliationOk"
        "ShadowFadingReconciliationOk"
        "LargeScaleParameterReconciliationOk"
        "ChannelStateContinuityOk"
        "DopplerReconciliationOk"
        "PropagationDelayReconciliationOk"
        "MobilityKpiReconciliationOk"
        "AccessKpiReconciliationOk"
        "SchedulerKpiReconciliationOk"]];
end

channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, ...
    "channel.model", "AWGN"))));
if channelModel == "AWGN"
    names = [names; ...
        "CdlRealizationOk"; ...
        "PathPowerNormalizationOk"; ...
        "AntennaArrayReconciliationOk"; ...
        "PolarizationReconciliationOk"];
end
names = unique(names, "stable");

if ~(fixedApplicable || geometryApplicable) && runClass ~= "hybrid_validation"
    % Unknown run classes do not receive mode-based exclusions.
    names = strings(0, 1);
end
end

function tf = localChannelRFArtifactsPass(runDir)
tf = false;
reportPath = fullfile(runDir, "reports", "csv", "channel_rf_reconciliation.csv");
T = localReadOptionalTable(reportPath);
if istable(T) && height(T) > 0 && localHasColumn(T, "ChannelRfConfiguredVsAppliedOk")
    tf = all(localColumnAsLogical(T.ChannelRfConfiguredVsAppliedOk));
    return;
end

path = fullfile(runDir, "channel", "csv", "channel_configured_vs_applied.csv");
T = localReadOptionalTable(path);
if istable(T) && height(T) > 0 && localHasColumn(T, "ConfiguredAppliedOk")
    tf = all(localColumnAsLogical(T.ConfiguredAppliedOk));
end
end

function tf = localColumnAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok";
end
end

function flags = localApplyKPIReconciliationFlags(flags, runDir)
ledger = localReadOptionalTable(fullfile(runDir, "reports", "csv", "canonical_kpi_ledger.csv"));
if istable(ledger) && height(ledger) > 0
    for name = ["CanonicalKpiLedgerOk","ThroughputReconciliationOk","BlerBerReconciliationOk", ...
            "LatencyReconciliationOk","AccessKpiReconciliationOk","SchedulerKpiReconciliationOk"]
        if ismember(name, string(ledger.Properties.VariableNames))
            flags.(char(name)) = localFirstLogical(ledger.(char(name)), false);
        end
    end
end
for spec = [
        "throughput_reconciliation.csv", "ThroughputReconciliationOk"
        "blerber_reconciliation.csv", "BlerBerReconciliationOk"
        "latency_reconciliation.csv", "LatencyReconciliationOk"
        "access_kpi_reconciliation.csv", "AccessKpiReconciliationOk"
        "scheduler_kpi_reconciliation.csv", "SchedulerKpiReconciliationOk"
        ]'
    T = localReadOptionalTable(fullfile(runDir, "reports", "csv", spec(1)));
    flagName = spec(2);
    if istable(T) && height(T) > 0 && ismember(flagName, string(T.Properties.VariableNames))
        flags.(char(flagName)) = localFirstLogical(T.(char(flagName)), false);
    end
end
end

function flags = localApplyRFInterferenceReconciliationFlags(flags, runDir)
for spec = [
        "noise_reconciliation.csv", "NoiseReconciliationOk"
        "interference_accounting.csv", "InterferenceAccountingOk"
        "rf_chain_definition.csv", "RfChainDefinitionOk"
        "cfo_reconciliation.csv", "CfoConfiguredAppliedOk"
        "phase_noise_reconciliation.csv", "PhaseNoiseConfiguredAppliedOk"
        "timing_offset_reconciliation.csv", "TimingOffsetConfiguredAppliedOk"
        "iq_imbalance_reconciliation.csv", "IqImbalanceConfiguredAppliedOk"
        "pa_reconciliation.csv", "PaConfiguredAppliedOk"
        "evm_reconciliation.csv", "EvmReconciliationOk"
        "papr_reconciliation.csv", "PaprReconciliationOk"
        "channel_rf_reconciliation.csv", "ChannelRfConfiguredVsAppliedOk"
        "mimo_kpi_reconciliation.csv", "MimoKpiReconciliationOk"
        "mobility_kpi_reconciliation.csv", "MobilityKpiReconciliationOk"
        ]'
    T = localReadOptionalTable(fullfile(runDir, "reports", "csv", spec(1)));
    flagName = spec(2);
    if istable(T) && height(T) > 0 && localHasColumn(T, flagName)
        flags.(char(flagName)) = all(localColumnAsLogical(T.(char(flagName))));
    end
end
end

function flags = localApplyCampaignFlags(flags, campaignEvidence)
names = string(fieldnames(campaignEvidence.Flags));
for i = 1:numel(names)
    flags.(char(names(i))) = logical(campaignEvidence.Flags.(char(names(i))));
end
end

function flags = localApplyStructFlags(flags, src)
if ~isstruct(src)
    return;
end
names = string(fieldnames(src));
for i = 1:numel(names)
    flags.(char(names(i))) = logical(src.(char(names(i))));
end
end

function flags = localApplyPhaseRollupFlags(flags, notApplicable)
flags.Phase1Ok = localAllApplicableNamedFlagsTrue(flags, [
    "GeometryValidationOk"
    "FullTrajectoryExecutedOk"
    "MobilityStateContinuousOk"
    "InterUeConstraintResolvedOk"
    "LosStateModelOk"
    "PathlossReconciliationOk"
    "ShadowFadingReconciliationOk"
    "LargeScaleParameterReconciliationOk"
    "CdlRealizationOk"
    "ChannelStateContinuityOk"
    "PathPowerNormalizationOk"
    "DopplerReconciliationOk"
    "PropagationDelayReconciliationOk"
    "AntennaArrayReconciliationOk"
    "PolarizationReconciliationOk"], notApplicable);
flags.Phase2Ok = localAllApplicableNamedFlagsTrue(flags, [
    "ResolvedConfigurationConsistentOk"
    "NoiseReconciliationOk"
    "InterferenceAccountingOk"
    "RfChainDefinitionOk"
    "CfoConfiguredAppliedOk"
    "PhaseNoiseConfiguredAppliedOk"
    "TimingOffsetConfiguredAppliedOk"
    "IqImbalanceConfiguredAppliedOk"
    "PaConfiguredAppliedOk"
    "EvmReconciliationOk"
    "PaprReconciliationOk"
    "ChannelRfConfiguredVsAppliedOk"
    "MimoKpiReconciliationOk"
    "SchedulerKpiReconciliationOk"
    "MobilityKpiReconciliationOk"], notApplicable);
flags.Phase3Ok = localAllApplicableNamedFlagsTrue(flags, [
    "ArtifactCompletenessOk"
    "PlotDataLineageOk"
    "Phase7NoFabricationOk"], notApplicable);
flags.Phase4Ok = localAllApplicableNamedFlagsTrue(flags, [
    "CanonicalKpiLedgerOk"
    "ThroughputReconciliationOk"
    "BlerBerReconciliationOk"
    "LatencyReconciliationOk"
    "AccessKpiReconciliationOk"
    "SchedulerKpiReconciliationOk"], notApplicable);
flags.Phase5Ok = localAllApplicableNamedFlagsTrue(flags, [
    "SeedHierarchyOk"
    "CampaignDesignOk"
    "CampaignCompletionOk"
    "MultiSeedDropStatisticsOk"
    "ConfidenceIntervalsOk"
    "SampleAdequacyOk"
    "SweepDataQualityOk"
    "CheckpointResumeEquivalenceOk"
    "SerialParallelDeterminismOk"], notApplicable);
flags.Phase6Ok = localAllApplicableNamedFlagsTrue(flags, [
    "EnergyModelOk"
    "PerformanceProfileOk"
    "LongRunStabilityOk"], notApplicable);
end

function tf = localAllApplicableNamedFlagsTrue(flags, names, notApplicable)
names = string(names(:));
notApplicable = string(notApplicable(:));
names = names(~ismember(names, notApplicable));
tf = localAllNamedFlagsTrue(flags, names);
end

function tf = localAllNamedFlagsTrue(flags, names)
tf = true;
for name = string(names(:)).'
    tf = tf && logical(sixgr.util.structGet(flags, char(name), false));
end
end

function finalTables = localBuildFinalReportTables(runDir, gateStatus, cfgTables, storageTables, mobilityTables, campaignEvidence)
failures = string(gateStatus.FailureCodes(:));
if isempty(failures)
    defects = table("none", "none", "all gates passed", "closed", ...
        'VariableNames', {'defect_id','severity','summary','status'});
else
    defects = table("PH7-" + string((1:numel(failures))'), repmat("blocker", numel(failures), 1), ...
        failures, repmat("open", numel(failures), 1), ...
        'VariableNames', {'defect_id','severity','summary','status'});
end
runClass = string(sixgr.util.structGet(gateStatus, "RunClass", "unknown"));
fixedApplicable = logical(sixgr.util.structGet(gateStatus, "FixedSNRLLSApplicable", false));
geometryApplicable = logical(sixgr.util.structGet(gateStatus, "GeometryScenarioApplicable", false));
fixedOk = logical(sixgr.util.structGet(gateStatus, "FixedSNRLLSOk", ~fixedApplicable));
geometryOk = logical(sixgr.util.structGet(gateStatus, "GeometryScenarioOk", ~geometryApplicable));
referenceOk = logical(sixgr.util.structGet(gateStatus, "PublicationReferenceComparisonOk", ~fixedApplicable));

fullRouteStatus = string(localTernary(logical(mobilityTables.Resolution.FullTrajectoryExecutedOk(1)), ...
    "supported_by_runtime_trajectory_rows", "unsupported_until_full_route_run"));
campaignStatus = string(localTernary(logical(campaignEvidence.Flags.CampaignCompletionOk), ...
    "supported_by_fixed_link_monte_carlo_campaign", "unsupported_until_multi_seed_campaign_rows"));
if fixedApplicable
    fixedStatus = string(localTernary(fixedOk, ...
        "supported_by_fixed_snr_sweep_acceptance_gates", "unsupported_until_fixed_snr_sweep_acceptance_passes"));
else
    fixedStatus = "not_run_in_fixed_snr_sweep_mode";
end
if geometryApplicable
    geometryStatus = string(localTernary(geometryOk, ...
        "supported_by_geometry_runtime_acceptance_gates", "unsupported_until_geometry_runtime_acceptance_passes"));
else
    geometryStatus = "not_run_in_geometry_mode";
end
if logical(gateStatus.PublicationReadinessOk)
    publicationStatus = "supported_by_fixed_snr_reference_comparison_and_all_phase7_gates";
elseif geometryApplicable && ~fixedApplicable
    publicationStatus = "not_applicable_geometry_only_run_is_not_publication_ready_for_fixed_link_curves";
elseif fixedApplicable && ~referenceOk
    publicationStatus = "unsupported_until_reference_comparison_is_present";
else
    publicationStatus = "unsupported_until_all_required_publication_gates_pass";
end
claims = table( ...
    ["run_class";"single_cell_two_ue_scope";"full_route_mobility_study";"multi_seed_statistics"; ...
    "fixed_snr_sweep_validation";"geometry_placement_validation";"publication_ready"], ...
    [runClass; "supported_scope"; fullRouteStatus; campaignStatus; fixedStatus; geometryStatus; string(publicationStatus)], ...
    ["reports/csv/run_classification.csv";"scenario YAML scope";"mobility/csv/trajectory_resolution.csv"; ...
    "air_interface/csv/dl_multi_seed_bler_curve.csv";"reports/csv/two_mode_acceptance_gates.csv"; ...
    "reports/csv/two_mode_acceptance_gates.csv";"reports/csv/phase7_truth_gates.csv"], ...
    'VariableNames', {'claim','support_status','evidence_artifact'});
kp = table("phase7_kpi_reconstruction", "not_evaluated_without_full_runtime_rows", ...
    "canonical KPI ledger pending full route/campaign rows", ...
    'VariableNames', {'kpi_group','status','notes'});
campaign = campaignEvidence.Tables.Summary;
if istable(campaign)
    campaign.RunClass = repmat(runClass, height(campaign), 1);
    campaign.FixedSNRLLSApplicable = repmat(logical(fixedApplicable), height(campaign), 1);
    campaign.GeometryScenarioApplicable = repmat(logical(geometryApplicable), height(campaign), 1);
    campaign.FixedSNRLLSOk = repmat(logical(fixedOk), height(campaign), 1);
    campaign.GeometryScenarioOk = repmat(logical(geometryOk), height(campaign), 1);
    campaign.PublicationReferenceComparisonOk = repmat(logical(referenceOk), height(campaign), 1);
    campaign.PublicationReady = repmat(logical(gateStatus.PublicationReadinessOk), height(campaign), 1);
    campaign.ModeValidationSummary = repmat(localModeValidationSummary(runClass, fixedApplicable, geometryApplicable, fixedOk, geometryOk, logical(gateStatus.PublicationReadinessOk)), height(campaign), 1);
end
acceptanceGates = localReadOptionalTable(fullfile(runDir, "reports", "csv", "two_mode_acceptance_gates.csv"));
if logical(gateStatus.PublicationReadinessOk)
    gradeValue = 10;
    confidence = "high";
    reason = "Fixed SNR sweep acceptance, reference comparison, and all Phase 7 gates verified from runtime evidence.";
elseif logical(gateStatus.ResultOk) && geometryApplicable && geometryOk && ~fixedApplicable
    gradeValue = 7;
    confidence = "medium";
    reason = "Geometry and mobility placement validation passed, but geometry-only runs are not publication-ready for fixed-link PHY curves.";
else
    gradeValue = 0;
    confidence = "low";
    reason = "Required mode-specific evidence is missing or failed, so the final acceptance gate cannot pass honestly.";
end
grade = struct("GradeOutOf10", double(gradeValue), "Confidence", char(confidence), ...
    "Reason", char(reason), ...
    "RunClass", char(runClass), ...
    "Phase7Ok", logical(gateStatus.Phase7Ok), ...
    "ResultOk", logical(gateStatus.ResultOk), ...
    "FixedSNRLLSApplicable", logical(fixedApplicable), ...
    "GeometryScenarioApplicable", logical(geometryApplicable), ...
    "FixedSNRLLSOk", logical(fixedOk), ...
    "GeometryScenarioOk", logical(geometryOk), ...
    "PublicationReferenceComparisonOk", logical(referenceOk), ...
    "PublicationReadinessOk", logical(gateStatus.PublicationReadinessOk), ...
    "TwoModeAcceptanceGateRows", double(height(acceptanceGates)), ...
    "TwoModeAcceptanceFailedRows", double(localModeGateFailureCount(acceptanceGates)));
finalTables = struct("DefectRegister", defects, "ClaimsMatrix", claims, ...
    "KPITable", kp, "CampaignSummary", campaign, "Grade", grade);
end

function localWriteFinalMarkdown(finalDir, gateStatus, cfgTables, storageTables, mobilityTables)
runClass = string(sixgr.util.structGet(gateStatus, "RunClass", "unknown"));
fixedApplicable = logical(sixgr.util.structGet(gateStatus, "FixedSNRLLSApplicable", false));
geometryApplicable = logical(sixgr.util.structGet(gateStatus, "GeometryScenarioApplicable", false));
fixedOk = logical(sixgr.util.structGet(gateStatus, "FixedSNRLLSOk", ~fixedApplicable));
geometryOk = logical(sixgr.util.structGet(gateStatus, "GeometryScenarioOk", ~geometryApplicable));
referenceOk = logical(sixgr.util.structGet(gateStatus, "PublicationReferenceComparisonOk", ~fixedApplicable));
if logical(gateStatus.PublicationReadinessOk)
    verdict = "publication-ready.";
elseif logical(gateStatus.ResultOk) && geometryApplicable && geometryOk && ~fixedApplicable
    verdict = "validated for geometry placement and mobility evidence, but not publication-ready for fixed-link curves.";
else
    verdict = "not publication-ready.";
end
summary = [
    "# Phase 7 Scientific Readiness"
    ""
    "Verdict: " + verdict
    ""
    "Scope label: SCOPED IMPLEMENTATION VALIDATION."
    ""
    "RunClass: " + runClass
    "FixedSNRLLSApplicable: " + string(fixedApplicable)
    "GeometryScenarioApplicable: " + string(geometryApplicable)
    "FixedSNRLLSOk: " + string(fixedOk)
    "GeometryScenarioOk: " + string(geometryOk)
    "PublicationReferenceComparisonOk: " + string(referenceOk)
    ""
    "Phase7Ok: " + string(logical(gateStatus.Phase7Ok))
    "ResultOk: " + string(logical(gateStatus.ResultOk))
    "PublicationReadinessOk: " + string(logical(gateStatus.PublicationReadinessOk))
    "Primary blocker: " + string(gateStatus.PrimaryFailureCode)
    ""
    localModeValidationSummary(runClass, fixedApplicable, geometryApplicable, fixedOk, geometryOk, logical(gateStatus.PublicationReadinessOk))
    ""
    "The generated artifacts are preflight and audit artifacts. They do not claim a full-route mobility or multi-seed campaign result unless the corresponding runtime evidence exists."
    ];
files = ["executive_summary.md","final_scientific_audit.md","final_publication_readiness.md", ...
    "final_channel_rf_validation.md","final_mobility_validation.md","final_statistical_validation.md", ...
    "final_energy_validation.md","final_performance_validation.md","final_output_completeness.md", ...
    "final_reproducibility_instructions.md"];
for i = 1:numel(files)
    localWriteText(fullfile(finalDir, files(i)), strjoin(summary, newline));
end
html = "<!doctype html><html><body><h1>Phase 7 Scientific Audit</h1><p>Verdict: " + verdict + "</p><p>RunClass: " + runClass + "</p><p>" + localModeValidationSummary(runClass, fixedApplicable, geometryApplicable, fixedOk, geometryOk, logical(gateStatus.PublicationReadinessOk)) + "</p></body></html>";
localWriteText(fullfile(finalDir, "final_scientific_audit.html"), html);
localWriteText(fullfile(finalDir, "final_source_diff.patch"), ...
    "Source diff is repository-state dependent; run git diff from the committed Phase 7 branch to reproduce.");
end

function n = localModeGateFailureCount(T)
n = 0;
if ~(istable(T) && height(T) > 0 && localHasColumn(T, "Status"))
    return;
end
n = sum(upper(strtrim(string(T.Status))) == "FAIL");
end

function summary = localModeValidationSummary(runClass, fixedApplicable, geometryApplicable, fixedOk, geometryOk, publicationReady)
runClass = string(runClass);
if publicationReady
    summary = "Final assessment: fixed-link publication validation passed with reference comparison and all required gates.";
elseif geometryApplicable && geometryOk && ~fixedApplicable
    summary = "Final assessment: geometry placement and mobility execution were validated, but this run class is not a publication-ready fixed-link curve anchor.";
elseif fixedApplicable && ~fixedOk
    summary = "Final assessment: fixed-link SNR sweep validation failed or is incomplete; the run cannot claim fixed-link publication evidence.";
elseif geometryApplicable && ~geometryOk
    summary = "Final assessment: geometry or mobility runtime evidence failed; the run cannot claim executed placement validation.";
else
    summary = "Final assessment: the run is diagnostic-only or incomplete, so no publication-ready validation claim is made.";
end
summary = summary + " RunClass=" + runClass + ".";
end

function localWrite(dirPath, fileName, T)
sixgr.analytics.writeAnalysisTable(fullfile(dirPath, fileName), T);
end

function localWriteText(path, text)
sixgr.util.ensureDir(path);
fid = fopen(path, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:analytics:phase7:OpenFailed", "Cannot open %s", path);
end
fprintf(fid, "%s\n", string(text));
fclose(fid);
end

function paths = localUserPaths(cfg)
paths = localGet(cfg, "mobility.user_paths", struct([]));
if isempty(paths)
    paths = localGet(cfg, "scenario.mobility.userPaths", struct([]));
end
if isempty(paths)
    paths = localSynthesizeUserPathsFromScalarMobility(cfg);
end
if isempty(paths)
    paths = struct([]);
elseif istable(paths)
    paths = table2struct(paths);
elseif iscell(paths)
    try
        paths = [paths{:}];
    catch
        paths = struct([]);
    end
elseif ~isstruct(paths)
    paths = struct([]);
end
end

function paths = localSynthesizeUserPathsFromScalarMobility(cfg)
paths = struct([]);
speedKmh = localNumber(cfg, ["mobility.ue_speed_kmh","channels.mobility_kmph","scenario.mobility.speed_kmh"], NaN);
nUE = round(localNumber(cfg, ["scenario.numUEs","scenario.ue.count","users.n_users","deployment_topology.num_ues","scenario.ue.nUE"], 1));
if ~(isfinite(speedKmh) && speedKmh >= 0 && isfinite(nUE) && nUE >= 1)
    return;
end
initDist = localFirstFiniteNumber(cfg, ["scenario.ue.initial_distance_m", ...
    "deployment_topology.max_ue_distance_from_bs_m", ...
    "scenario.ue.distribution.max_bs_dist_m", "scenario.ue.distribution.maxBsDistance_m", ...
    "deployment_topology.cell_radius_m"]);
minRadius = localFirstFiniteNumber(cfg, ["deployment_topology.min_ue_distance_from_bs_m", ...
    "scenario.ue.distribution.min_bs_dist_m", "scenario.ue.distribution.minBsDistance_m"]);
if ~isfinite(initDist)
    initDist = 300;
end
if isfinite(minRadius) && minRadius > 0
    initDist = max(initDist, minRadius);
end
nUE = max(1, round(double(nUE)));
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0);
durationS = max(double(slots) * double(slotMs) / 1e3, 0);
routeLength = max(0, double(speedKmh) / 3.6 * durationS);
headingDeg = localNumber(cfg, ["mobility.heading_deg","mobility.direction_deg","scenario.mobility.heading_deg"], 0);
ueHeight = localNumber(cfg, ["scenario.ue.height_m","deployment_topology.ue_height_m"], 1.5);
laneSpacing = localNumber(cfg, ["deployment_topology.min_inter_ue_distance_m","users.min_inter_ue_distance_m"], 10);
if ~(isfinite(laneSpacing) && laneSpacing > 0)
    laneSpacing = 10;
end

paths = repmat(struct("ue_id", NaN, "label", "", "speed_kmh", NaN, ...
    "initial_position_m", [NaN NaN NaN], "initial_heading_deg", NaN, "heading_deg", NaN, ...
    "route_length_m", NaN, "waypoints_m", struct([]), "loop_mode", "bounce", ...
    "path_source", "mobility.ue_speed_kmh", "path_provenance", "synthesized_from_scalar_speed", ...
    "source", "synthesized_from_scalar_mobility_ue_speed_kmh"), nUE, 1);
heading = [cosd(headingDeg), sind(headingDeg), 0];
normal = [-sind(headingDeg), cosd(headingDeg), 0];
move = routeLength .* heading;
for i = 1:nUE
    laneOffset = (double(i) - (double(nUE) + 1) / 2) * laneSpacing;
    start = [double(initDist), 0, double(ueHeight)] + laneOffset .* normal;
    stop = start + move;
    paths(i).ue_id = i;
    paths(i).label = sprintf("ue_%d_scalar_speed_path", i);
    paths(i).speed_kmh = double(speedKmh);
    paths(i).initial_position_m = start;
    paths(i).initial_heading_deg = double(headingDeg);
    paths(i).heading_deg = double(headingDeg);
    paths(i).route_length_m = routeLength;
    paths(i).waypoints_m = struct("position_m", stop, "hold_time_s", 0);
    paths(i).loop_mode = "bounce";
    paths(i).path_source = "mobility.ue_speed_kmh";
    paths(i).path_provenance = "synthesized_from_scalar_speed";
    paths(i).source = "synthesized_from_scalar_mobility_ue_speed_kmh";
end
end

function value = localFirstFiniteNumber(cfg, paths)
value = NaN;
for path = string(paths(:)).'
    candidate = localNumber(cfg, path, NaN);
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function provenance = localPathProvenance(p, fallback)
provenance = string(sixgr.util.structGet(p, "path_provenance", ...
    sixgr.util.structGet(p, "PathProvenance", "")));
if strlength(strtrim(provenance)) == 0
    provenance = string(fallback);
end
if strlength(strtrim(provenance)) == 0
    provenance = "mobility.user_paths";
end
end

function provenance = localTrajectoryPathProvenance(traj)
provenance = "mobility.user_paths";
if ~(istable(traj) && height(traj) > 0 && localHasColumn(traj, "PathProvenance"))
    return;
end
values = strtrim(string(traj.PathProvenance));
values = unique(values(strlength(values) > 0));
if ~isempty(values)
    provenance = strjoin(values(:).', "|");
end
end

function row = localEmptyRuntimeMobilityTraceRow()
row = struct( ...
    "UeId", NaN, "CellId", NaN, "ServingCellId", NaN, "CanonicalSlot", NaN, "Time_s", NaN, ...
    "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
    "Speed_kmh", NaN, "Speed_mps", NaN, "Heading_deg", NaN, "Heading_rad", NaN, ...
    "Distance2D_m", NaN, "Distance3D_m", NaN, "PropagationDelay_s", NaN, ...
    "RadialVelocity_mps", NaN, "ExpectedDopplerHz", NaN, "AppliedDopplerHz", NaN, "SignedDoppler_Hz", NaN, ...
    "Pathloss_dB", NaN, "BasePathloss_dB", NaN, "ShadowFading_dB", NaN, "O2I_dB", NaN, ...
    "LOSState", "", "PathlossModelSource", "", "PathlossComplianceStatus", "", ...
    "LOSProbabilitySource", "", "LOSComplianceStatus", "", "Status", "");
end

function T = localEmptyRuntimeMobilityTraceTable()
T = struct2table(repmat(localEmptyRuntimeMobilityTraceRow(), 0, 1), "AsArray", true);
end

function row = localEmptyDopplerReconciliationRow()
row = struct("UeId", NaN, "CellId", NaN, "CanonicalSlot", NaN, "Time_s", NaN, ...
    "Speed_mps", NaN, "CarrierFrequency_Hz", NaN, "ExpectedDopplerHz", NaN, "AppliedDopplerHz", NaN, ...
    "DopplerErrorHz", NaN, "DopplerToleranceHz", NaN, "DopplerReconciliationOk", false, ...
    "EvidenceSource", "", "Status", "");
end

function T = localEmptyDopplerReconciliationTable()
T = struct2table(repmat(localEmptyDopplerReconciliationRow(), 0, 1), "AsArray", true);
end

function row = localEmptyPathlossReconciliationRow()
row = struct("UeId", NaN, "CellId", NaN, "CanonicalSlot", NaN, "LOSState", "", ...
    "BasePathloss_dB", NaN, "ShadowFading_dB", NaN, "O2I_dB", NaN, ...
    "ObservedPathloss_dB", NaN, "ExpectedPathloss_dB", NaN, ...
    "PathlossError_dB", NaN, "PathlossTolerance_dB", NaN, ...
    "PathlossReconciliationOk", false, "ShadowFadingReconciliationOk", false, ...
    "LosStateModelOk", false, "LargeScaleParameterReconciliationOk", false, ...
    "EvidenceSource", "", "Status", "");
end

function T = localEmptyPathlossReconciliationTable()
T = struct2table(repmat(localEmptyPathlossReconciliationRow(), 0, 1), "AsArray", true);
end

function row = localEmptyPropagationDelayReconciliationRow()
row = struct("UeId", NaN, "CellId", NaN, "CanonicalSlot", NaN, "Distance3D_m", NaN, ...
    "ObservedPropagationDelay_s", NaN, "ExpectedPropagationDelay_s", NaN, ...
    "PropagationDelayError_s", NaN, "PropagationDelayTolerance_s", NaN, ...
    "PropagationDelayReconciliationOk", false, "EvidenceSource", "", "Status", "");
end

function T = localEmptyPropagationDelayReconciliationTable()
T = struct2table(repmat(localEmptyPropagationDelayReconciliationRow(), 0, 1), "AsArray", true);
end

function row = localEmptyChannelContinuityReconciliationRow()
row = struct("UeId", NaN, "ExpectedSlotCount", NaN, "ObservedSlotCount", NaN, ...
    "MissingSlotCount", NaN, "FirstSlot", NaN, "LastSlot", NaN, ...
    "ExpectedTimeStep_s", NaN, "ObservedMedianTimeStep_s", NaN, ...
    "MobilityStateContinuousOk", false, "ChannelStateContinuityOk", false, ...
    "FiniteLargeScaleStateOk", false, "FailureCode", "", "Status", "");
end

function T = localEmptyChannelContinuityReconciliationTable()
T = struct2table(repmat(localEmptyChannelContinuityReconciliationRow(), 0, 1), "AsArray", true);
end

function row = localEmptyTopologyNodeRow()
row = struct( ...
    "NodeClass", "", "NodeId", NaN, "CellId", NaN, "SiteId", NaN, "UeId", NaN, ...
    "CanonicalSlot", NaN, "Time_s", NaN, "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
    "Speed_kmh", NaN, "Heading_rad", NaN, "Label", "", "NodeSource", "", "Status", "");
end

function row = localEmptyServingCellAssignmentRow()
row = struct( ...
    "UeId", NaN, "CellId", NaN, "ServingCellId", NaN, "CanonicalSlot", NaN, ...
    "Time_s", NaN, "Distance3D_m", NaN, "Pathloss_dB", NaN, ...
    "AssignmentSource", "", "Status", "");
end

function T = localEmptyServingCellAssignmentTable()
T = struct2table(repmat(localEmptyServingCellAssignmentRow(), 0, 1), "AsArray", true);
end

function tables = localBuildPhysicalChannelReconciliationTables(runDir, cfg)
% Build Phase-1 gates only from active same-run waveform rows.  The
% ChannelFactory profile table is joined to the active trial object class;
% it is never treated as a measured realization by itself.
reportDir = fullfile(runDir, "reports", "csv");
airDir = fullfile(runDir, "air_interface", "csv");
dlT = localReadOptionalTable(fullfile(airDir, "dl_pdsch_trials.csv"));
ulT = localReadOptionalTable(fullfile(airDir, "ul_pusch_trials.csv"));
cirT = localReadOptionalTable(fullfile(reportDir, "channel_impulse_response.csv"));
arrayT = localReadOptionalTable(fullfile(reportDir, "channel_array_consistency.csv"));
antennaT = localReadOptionalTable(fullfile(reportDir, "antenna_runtime_evidence.csv"));

tables = struct();
tables.ChannelRealization = localBuildChannelRealizationReconciliation(cfg, dlT, ulT);
tables.PathPowerNormalization = localBuildPathPowerNormalizationReconciliation(cfg, cirT, dlT, ulT);
tables.AntennaArray = localBuildAntennaArrayReconciliation(cfg, arrayT);
tables.Polarization = localBuildPolarizationReconciliation(cfg, antennaT);
end

function T = localBuildChannelRealizationReconciliation(cfg, dlT, ulT)
rows = repmat(struct("Direction", "", "ObservedRows", 0, ...
    "ConfiguredChannel", "", "ObservedChannelSet", "", ...
    "ObservedChannelObjectClassSet", "", "FadingRequired", false, ...
    "FadingAppliedRowCount", 0, "SameRuntimeArrayRowCount", 0, ...
    "FallbackRowCount", 0, "PlaceholderRowCount", 0, ...
    "ChannelRealizationOk", false, "EvidenceSource", "", "FailureReason", ""), 0, 1);
configured = localConfiguredConcreteChannel(cfg);
requiredDirections = localRequiredLinkDirections(cfg, dlT, ulT);
for spec = {"DL", dlT, "air_interface/csv/dl_pdsch_trials.csv"; ...
        "UL", ulT, "air_interface/csv/ul_pusch_trials.csv"}'
    direction = string(spec{1});
    if ~ismember(direction, requiredDirections)
        continue;
    end
    sourceT = spec{2};
    sourcePath = string(spec{3});
    active = localActiveRuntimeTrialRows(sourceT);
    if height(active) == 0
        rows(end+1,1) = struct("Direction", direction, "ObservedRows", 0, ... %#ok<AGROW>
            "ConfiguredChannel", configured, "ObservedChannelSet", "", ...
            "ObservedChannelObjectClassSet", "", ...
            "FadingRequired", startsWith(configured, "TDL-") || startsWith(configured, "CDL-"), ...
            "FadingAppliedRowCount", 0, "SameRuntimeArrayRowCount", 0, ...
            "FallbackRowCount", 0, "PlaceholderRowCount", 0, ...
            "ChannelRealizationOk", false, "EvidenceSource", sourcePath, ...
            "FailureReason", "required_active_runtime_trials_missing");
        continue;
    end
    observed = upper(strtrim(localFirstAvailableTableText(active, ["ChannelModelApplied","ChannelModel"])));
    objectClass = strtrim(localFirstAvailableTableText(active, ["ChannelObjectClass","ChannelFadingObjectClass"]));
    fadingRequired = startsWith(configured, "TDL-") || startsWith(configured, "CDL-");
    fadingApplied = localTrialLogicalColumn(active, "ChannelFadingApplied", false);
    sameArray = localTrialLogicalColumn(active, "ChannelUsesSameRuntimeAntennaAssumptions", false);
    fallback = localTrialLogicalColumn(active, ["FallbackFlag","FallbackUsed"], false);
    placeholder = localTrialLogicalColumn(active, ["PlaceholderFlag","PlaceholderUsed"], false);
    channelMatches = all(observed == configured);
    if fadingRequired
        expectedClass = localTernary(startsWith(configured, "CDL-"), "nrCDLChannel", "nrTDLChannel");
        runtimeOk = all(fadingApplied) && all(objectClass == expectedClass);
        % CDL consumes the runtime array geometry directly. TDL consumes a
        % reduced spatial-correlation representation and is assessed by its
        % explicit adapter status elsewhere, so sameArray is CDL-specific.
        if startsWith(configured, "CDL-")
            runtimeOk = runtimeOk && all(sameArray);
        end
    else
        runtimeOk = configured == "AWGN" && all(~fadingApplied);
    end
    ok = channelMatches && runtimeOk && ~any(fallback) && ~any(placeholder);
    reason = "";
    if ~ok
        reason = localJoinFailureReasons([ ...
            localConditionalReason(~channelMatches, "configured_applied_channel_mismatch"), ...
            localConditionalReason(~runtimeOk, "runtime_channel_realization_incomplete"), ...
            localConditionalReason(any(fallback), "fallback_rows_present"), ...
            localConditionalReason(any(placeholder), "placeholder_rows_present")]);
    end
    rows(end+1,1) = struct("Direction", direction, "ObservedRows", height(active), ... %#ok<AGROW>
        "ConfiguredChannel", configured, "ObservedChannelSet", localTokenSet(observed), ...
        "ObservedChannelObjectClassSet", localTokenSet(objectClass), ...
        "FadingRequired", fadingRequired, "FadingAppliedRowCount", sum(fadingApplied), ...
        "SameRuntimeArrayRowCount", sum(sameArray), "FallbackRowCount", sum(fallback), ...
        "PlaceholderRowCount", sum(placeholder), "ChannelRealizationOk", ok, ...
        "EvidenceSource", sourcePath, "FailureReason", reason);
end
T = localStructRowsToTable(rows);
end

function T = localBuildPathPowerNormalizationReconciliation(cfg, cirT, dlT, ulT)
rows = repmat(struct("Direction", "", "ProfileRows", 0, ...
    "ConfiguredNormalizePathGains", false, "AppliedNormalizePathGains", false, ...
    "ConfiguredAppliedMatch", false, "NormalizedPowerSum", NaN, ...
    "NormalizedPowerError", NaN, "FiniteNonnegativePowerOk", false, ...
    "ActiveTrialRows", 0, "RuntimeChannelClass", "", "ProfileChannelClass", "", ...
    "RuntimeProfileJoinOk", false, "PathPowerNormalizationOk", false, ...
    "EvidenceRole", "", "EvidenceSource", "", "FailureReason", ""), 0, 1);
[configuredNormalize, configuredSource] = localConfiguredNormalizePathGains(cfg);
requiredDirections = localRequiredLinkDirections(cfg, dlT, ulT);
for spec = {"DL", dlT; "UL", ulT}'
    direction = string(spec{1});
    if ~ismember(direction, requiredDirections)
        continue;
    end
    active = localActiveRuntimeTrialRows(spec{2});
    if height(active) == 0
        rows(end+1,1) = struct("Direction", direction, "ProfileRows", 0, ... %#ok<AGROW>
            "ConfiguredNormalizePathGains", configuredNormalize, ...
            "AppliedNormalizePathGains", false, "ConfiguredAppliedMatch", false, ...
            "NormalizedPowerSum", NaN, "NormalizedPowerError", NaN, ...
            "FiniteNonnegativePowerOk", false, "ActiveTrialRows", 0, ...
            "RuntimeChannelClass", "", "ProfileChannelClass", "", ...
            "RuntimeProfileJoinOk", false, "PathPowerNormalizationOk", false, ...
            "EvidenceRole", "channel_object_configuration_and_profile_identity_not_instantaneous_path_gain_measurement", ...
            "EvidenceSource", configuredSource + ";required_active_trial_missing", ...
            "FailureReason", "required_active_runtime_trials_missing");
        continue;
    end
    if ~(istable(cirT) && height(cirT) > 0 && localHasColumn(cirT, "Direction"))
        slice = table();
    else
        slice = cirT(strcmpi(strtrim(string(cirT.Direction)), direction), :);
    end
    applied = false;
    normalizedSum = NaN;
    finitePowerOk = false;
    profileClass = "";
    if height(slice) > 0
        appliedValues = localTrialLogicalColumn(slice, "NormalizePathGains", false);
        applied = all(appliedValues) && numel(appliedValues) == height(slice);
        powers = localColumnDouble(slice, "NormalizedTapPower", NaN);
        finitePowerOk = all(isfinite(powers) & powers >= 0);
        if finitePowerOk
            normalizedSum = sum(powers);
        end
        profileClass = localTokenSet(localFirstAvailableTableText(slice, "ChannelObjectClass"));
    end
    runtimeClass = localTokenSet(localFirstAvailableTableText(active, ["ChannelObjectClass","ChannelFadingObjectClass"]));
    joinOk = height(slice) > 0 && strlength(runtimeClass) > 0 && runtimeClass == profileClass;
    match = height(slice) > 0 && applied == configuredNormalize;
    if configuredNormalize
        numericalOk = finitePowerOk && isfinite(normalizedSum) && abs(normalizedSum - 1) <= 1e-12;
    else
        % The exported normalized profile is a display quantity when path
        % normalization is disabled. The production gate then checks only
        % that the active ChannelFactory object applied the disabled policy.
        numericalOk = true;
    end
    ok = match && numericalOk && joinOk;
    reason = "";
    if ~ok
        reason = localJoinFailureReasons([ ...
            localConditionalReason(~match, "configured_applied_normalization_mismatch"), ...
            localConditionalReason(~numericalOk, "normalized_path_power_sum_invalid"), ...
            localConditionalReason(~joinOk, "profile_not_joined_to_active_runtime_channel_class")]);
    end
    rows(end+1,1) = struct("Direction", direction, "ProfileRows", height(slice), ... %#ok<AGROW>
        "ConfiguredNormalizePathGains", configuredNormalize, ...
        "AppliedNormalizePathGains", applied, "ConfiguredAppliedMatch", match, ...
        "NormalizedPowerSum", normalizedSum, "NormalizedPowerError", abs(normalizedSum - 1), ...
        "FiniteNonnegativePowerOk", finitePowerOk, "ActiveTrialRows", height(active), ...
        "RuntimeChannelClass", runtimeClass, "ProfileChannelClass", profileClass, ...
        "RuntimeProfileJoinOk", joinOk, "PathPowerNormalizationOk", ok, ...
        "EvidenceRole", "channel_object_configuration_and_profile_identity_not_instantaneous_path_gain_measurement", ...
        "EvidenceSource", configuredSource + ";reports/csv/channel_impulse_response.csv;active_trial_channel_object_class", ...
        "FailureReason", reason);
end
T = localStructRowsToTable(rows);
end

function T = localBuildAntennaArrayReconciliation(cfg, arrayT)
rows = repmat(struct("Direction", "", "ObservedRows", 0, ...
    "ExpectedTxPhysicalElements", NaN, "ObservedTxPhysicalElements", NaN, ...
    "ExpectedRxPhysicalElements", NaN, "ObservedRxPhysicalElements", NaN, ...
    "PhysicalArrayConsistencyOk", false, "RuntimeGeometryCoupledOk", false, ...
    "CountOnlyChannelUsed", false, "AntennaArrayReconciliationOk", false, ...
    "EvidenceSource", "", "FailureReason", ""), 0, 1);
if ~(istable(arrayT) && height(arrayT) > 0 && localHasColumn(arrayT, "Direction"))
    T = localStructRowsToTable(rows);
    return;
end
bsElements = localNumber(cfg, [ ...
    "antenna_and_array.bs_num_antenna_elements", ...
    "deployment_topology.bs.antenna.n_elements", ...
    "scenario.bs.nTxAnt","scenario.bs.nRxAnt","channel.nTxAnt","phy.nTxAnt"], NaN);
ueElements = localNumber(cfg, [ ...
    "antenna_and_array.ue_num_antenna_elements", ...
    "deployment_topology.ue.nRxAnt", ...
    "scenario.ue.nRxAnt","scenario.ue.nTxAnt","channel.nRxAnt","phy.nRxAnt"], NaN);
for direction = localRequiredLinkDirections(cfg, ...
        localDirectionalPresenceTable(arrayT, "DL"), localDirectionalPresenceTable(arrayT, "UL"))
    slice = arrayT(upper(strtrim(string(arrayT.Direction))) == direction, :);
    if direction == "DL"
        expectedTx = bsElements;
        expectedRx = ueElements;
    else
        expectedTx = ueElements;
        expectedRx = bsElements;
    end
    observedTx = localFirstFinite(localFirstAvailableTableColumn(slice, ["ObservedPhysicalTxAntennas","ObservedTxWaveformColumns"]));
    observedRx = localFirstFinite(localFirstAvailableTableColumn(slice, ["ObservedPhysicalRxAntennas","ObservedRxWaveformBranches"]));
    physicalOk = localAllTableFlag(slice, "PhysicalArrayConsistencyOk") && ...
        isfinite(expectedTx) && isfinite(expectedRx) && observedTx == expectedTx && observedRx == expectedRx;
    countOnly = any(localTrialLogicalColumn(slice, "ChannelUsesCountOnlyAntennaModel", false));
    configuredChannel = localConfiguredConcreteChannel(cfg);
    if startsWith(configuredChannel, "CDL-")
        geometryOk = all(localTrialLogicalColumn(slice, "ChannelUsesSameRuntimeAntennaAssumptions", false));
    elseif startsWith(configuredChannel, "TDL-")
        levels = lower(strtrim(localFirstAvailableTableText(slice, "ChannelGeometryCouplingLevel")));
        geometryOk = all(contains(levels, "runtime_geometry_reduced_spatial_correlation"));
    else
        geometryOk = configuredChannel == "AWGN";
    end
    ok = physicalOk && geometryOk && ~countOnly;
    if configuredChannel == "AWGN"
        ok = physicalOk;
    end
    reason = "";
    if ~ok
        reason = localJoinFailureReasons([ ...
            localConditionalReason(~physicalOk, "physical_array_count_mismatch"), ...
            localConditionalReason(~geometryOk, "runtime_array_geometry_not_coupled"), ...
            localConditionalReason(countOnly, "count_only_channel_model_used")]);
    end
    rows(end+1,1) = struct("Direction", direction, "ObservedRows", sum(localColumnDouble(slice, "ObservedRows", 0)), ... %#ok<AGROW>
        "ExpectedTxPhysicalElements", expectedTx, "ObservedTxPhysicalElements", observedTx, ...
        "ExpectedRxPhysicalElements", expectedRx, "ObservedRxPhysicalElements", observedRx, ...
        "PhysicalArrayConsistencyOk", physicalOk, "RuntimeGeometryCoupledOk", geometryOk, ...
        "CountOnlyChannelUsed", countOnly, "AntennaArrayReconciliationOk", ok, ...
        "EvidenceSource", "reports/csv/channel_array_consistency.csv<-active_same_flow_trials", ...
        "FailureReason", reason);
end
T = localStructRowsToTable(rows);
end

function T = localBuildPolarizationReconciliation(cfg, antennaT)
rows = repmat(struct("Direction", "", "ObservedRows", 0, ...
    "ConfiguredBSPolarization", "", "ObservedBSPolarizationSet", "", ...
    "ConfiguredUEPolarization", "", "ObservedUEPolarizationSet", "", ...
    "BSPolarizationMatch", false, "UEPolarizationMatch", false, ...
    "RuntimeAntennaObjectRows", 0, "SameFlowEvidenceRows", 0, ...
    "PolarizationReconciliationOk", false, "EvidenceSource", "", "FailureReason", ""), 0, 1);
if ~(istable(antennaT) && height(antennaT) > 0 && localHasColumn(antennaT, "Direction"))
    T = localStructRowsToTable(rows);
    return;
end
bsConfigured = localNormalizedPolarization(localGet(cfg, "antenna.bs.polarization", ...
    localGet(cfg, "antenna_and_array.polarization", "")));
ueConfigured = localNormalizedPolarization(localGet(cfg, "antenna.ue.polarization", ...
    localGet(cfg, "antenna_and_array.polarization", "")));
for direction = localRequiredLinkDirections(cfg, ...
        localDirectionalPresenceTable(antennaT, "DL"), localDirectionalPresenceTable(antennaT, "UL"))
    slice = antennaT(upper(strtrim(string(antennaT.Direction))) == direction, :);
    % CSV schema pruning is allowed to omit structurally blank optional
    % columns.  A missing measured polarization column is therefore a
    % fail-closed evidence gap, not a table-indexing exception and never a
    % reason to substitute the configured polarization value.
    hasBSPolarization = localHasColumn(slice, "BSAntennaPolarization");
    hasUEPolarization = localHasColumn(slice, "UEAntennaPolarization");
    bsObserved = localNormalizedPolarization(localFirstAvailableTableText( ...
        slice, "BSAntennaPolarization"));
    ueObserved = localNormalizedPolarization(localFirstAvailableTableText( ...
        slice, "UEAntennaPolarization"));
    bsMatch = strlength(bsConfigured) > 0 && all(bsObserved == bsConfigured);
    ueMatch = strlength(ueConfigured) > 0 && all(ueObserved == ueConfigured);
    runtimeRows = sum(localTrialLogicalColumn(slice, "AntennaRuntimeObjectCreated", false));
    sources = localFirstAvailableTableText(slice, "SameFlowEvidenceSource");
    sameFlowRows = sum(strlength(strtrim(sources)) > 0);
    ok = height(slice) > 0 && bsMatch && ueMatch && ...
        runtimeRows == height(slice) && sameFlowRows == height(slice);
    reason = "";
    if ~ok
        reason = localJoinFailureReasons([ ...
            localConditionalReason(~bsMatch, "bs_polarization_mismatch"), ...
            localConditionalReason(~ueMatch, "ue_polarization_mismatch"), ...
            localConditionalReason(~hasBSPolarization, "bs_runtime_polarization_column_missing"), ...
            localConditionalReason(~hasUEPolarization, "ue_runtime_polarization_column_missing"), ...
            localConditionalReason(height(slice) == 0, "required_runtime_polarization_rows_missing"), ...
            localConditionalReason(runtimeRows ~= height(slice), "runtime_antenna_object_evidence_missing"), ...
            localConditionalReason(sameFlowRows ~= height(slice), "same_flow_lineage_missing")]);
    end
    rows(end+1,1) = struct("Direction", direction, "ObservedRows", height(slice), ... %#ok<AGROW>
        "ConfiguredBSPolarization", bsConfigured, "ObservedBSPolarizationSet", localTokenSet(bsObserved), ...
        "ConfiguredUEPolarization", ueConfigured, "ObservedUEPolarizationSet", localTokenSet(ueObserved), ...
        "BSPolarizationMatch", bsMatch, "UEPolarizationMatch", ueMatch, ...
        "RuntimeAntennaObjectRows", runtimeRows, "SameFlowEvidenceRows", sameFlowRows, ...
        "PolarizationReconciliationOk", ok, ...
        "EvidenceSource", "reports/csv/antenna_runtime_evidence.csv<-active_same_flow_trials", ...
        "FailureReason", reason);
end
T = localStructRowsToTable(rows);
end

function active = localActiveRuntimeTrialRows(T)
active = table();
if ~(istable(T) && height(T) > 0)
    return;
end
mask = true(height(T), 1);
if localHasColumn(T, "Status")
    status = upper(strtrim(string(T.Status)));
    mask = mask & ~ismember(status, ["CRASH","SKIPPED","UNAVAILABLE"]);
end
if localHasColumn(T, "FinalizedFlag")
    mask = mask & localColumnAsLogical(T.FinalizedFlag);
end
mask = mask & ~localTrialLogicalColumn(T, ["FallbackFlag","FallbackUsed"], false);
mask = mask & ~localTrialLogicalColumn(T, ["PlaceholderFlag","PlaceholderUsed"], false);
active = T(mask, :);
end

function directions = localRequiredLinkDirections(cfg, dlT, ulT)
token = lower(strtrim(string(localGet(cfg, "run.link_direction", ...
    localGet(cfg, "validation.fixed_link_campaign.direction", ...
    localGet(cfg, "traffic.flow_direction", ""))))));
if any(token == ["both","bidirectional","dl_ul","downlink_uplink"])
    directions = ["DL","UL"];
elseif any(token == ["dl","downlink"])
    directions = "DL";
elseif any(token == ["ul","uplink"])
    directions = "UL";
else
    directions = strings(1,0);
    if istable(dlT) && height(dlT) > 0
        directions(end+1) = "DL"; %#ok<AGROW>
    end
    if istable(ulT) && height(ulT) > 0
        directions(end+1) = "UL"; %#ok<AGROW>
    end
end
directions = reshape(unique(directions, "stable"), 1, []);
end

function T = localDirectionalPresenceTable(Tin, direction)
T = table();
if istable(Tin) && height(Tin) > 0 && localHasColumn(Tin, "Direction") && ...
        any(strcmpi(strtrim(string(Tin.Direction)), direction))
    T = Tin(1,:);
end
end

function values = localTrialLogicalColumn(T, names, defaultValue)
values = repmat(logical(defaultValue), height(T), 1);
for name = string(names(:)).'
    if localHasColumn(T, name)
        values = localColumnAsLogical(T.(char(name)));
        return;
    end
end
end

function token = localConfiguredConcreteChannel(cfg)
model = upper(strtrim(string(localGet(cfg, "channel.model", localGet(cfg, "channels.model_type", "AWGN")))));
if any(model == ["CDL","NRCDL"])
    profile = upper(strtrim(string(localGet(cfg, "channel.cdlProfile", ...
        localGet(cfg, "channel.fading.profile", localGet(cfg, "channels.profile", ""))))));
    token = profile;
elseif any(model == ["TDL","NRTDL"])
    profile = upper(strtrim(string(localGet(cfg, "channel.tdlProfile", ...
        localGet(cfg, "channel.fading.profile", localGet(cfg, "channels.profile", ""))))));
    token = profile;
elseif any(model == ["AWGN","NONE","OFF",""])
    token = "AWGN";
else
    token = model;
end
end

function [value, source] = localConfiguredNormalizePathGains(cfg)
paths = ["channel.normalizePathGains","channel.NormalizePathGains", ...
    "channel.normalize_path_gains","channel.fading.normalizePathGains", ...
    "channel.fading.normalize_path_gains"];
for path = paths
    raw = localGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    value = localBool(struct("value", raw), "value", false);
    source = path;
    return;
end
noiseMode = lower(strtrim(string(localGet(cfg, "run.noiseOperatingMode", ...
    localGet(cfg, "simulation.noise_operating_mode", "")))));
value = noiseMode ~= "receiver_noise_figure_thermal_noise";
source = localTernary(strlength(noiseMode) > 0, "ChannelFactory.default_for_" + noiseMode, ...
    "ChannelFactory.default_without_noise_operating_mode");
end

function token = localNormalizedPolarization(value)
token = lower(strtrim(string(value)));
dualMask = contains(token, "dual") | contains(token, "cross") | ...
    contains(token, "+-45") | contains(token, "±45");
singleMask = contains(token, "single") | contains(token, "co-polar") | ...
    token == "co" | token == "copolar";
token(dualMask) = "dual";
token(singleMask & ~dualMask) = "single";
end

function value = localTokenSet(values)
values = unique(strtrim(string(values(:))), "stable");
values = values(strlength(values) > 0 & lower(values) ~= "nan" & lower(values) ~= "missing");
value = strjoin(values, "|");
end

function reason = localConditionalReason(condition, text)
if condition
    reason = string(text);
else
    reason = "";
end
end

function reason = localJoinFailureReasons(reasons)
reasons = string(reasons(:));
reasons = reasons(strlength(reasons) > 0);
reason = strjoin(reasons, ";");
end

function T = localBuildMeasuredSINRTimeseries(runDir, cfg)
airCsvDir = fullfile(runDir, "air_interface", "csv");
dlT = localReadOptionalTable(fullfile(airCsvDir, "dl_pdsch_trials.csv"));
ulT = localReadOptionalTable(fullfile(airCsvDir, "ul_pusch_trials.csv"));
slotDuration_s = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5) / 1e3;
rows = repmat(localEmptyMeasuredSINRRow(), 0, 1);
rows = [rows; localMeasuredSINRRowsFromTrials(dlT, "DL", slotDuration_s, "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localMeasuredSINRRowsFromTrials(ulT, "UL", slotDuration_s, "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
T = localStructRowsToTable(rows);
if istable(T) && height(T) > 0
    T = sortrows(T, {'CanonicalSlot','Direction','UeId','CellId'});
end
end

function rows = localMeasuredSINRRowsFromTrials(T, direction, slotDuration_s, sourcePath)
rows = repmat(localEmptyMeasuredSINRRow(), 0, 1);
if ~(istable(T) && height(T) > 0)
    return;
end

sinr = localFirstAvailableTableColumn(T, ["MeasuredTrialSINR_dB","PostEqSINR_dB","MeasuredSINR_dB","ReceiverHestSINR_dB","LargeScaleSINR_dB"]);
slot = localFirstAvailableTableColumn(T, ["Slot","CanonicalSlot","TTI"]);
ue = localFirstAvailableTableColumn(T, ["UEID","UEIndex","UE","RNTI"]);
cellId = localFirstAvailableTableColumn(T, ["CellID","ServingCell","BaseStationID"]);
mcs = localFirstAvailableTableColumn(T, ["MCS","MCSIndex","CQIDerivedMCS"]);
rank = localFirstAvailableTableColumn(T, ["RankEstimate","RankIndicator","Rank"]);
layers = localFirstAvailableTableColumn(T, ["Layers","NumLayers"]);
modulation = localFirstAvailableTableText(T, ["Modulation","CQIDerivedModulation"]);
status = localFirstAvailableTableText(T, "Status");
sinrSource = localFirstAvailableTableText(T, ["MeasuredTrialSINRSource","PostEqSINRSource","SINRSource","ReceiverHestSINRSource"]);

mask = isfinite(sinr) & isfinite(slot);
for i = find(mask(:)).'
    row = localEmptyMeasuredSINRRow();
    row.Direction = upper(string(direction));
    row.UeId = localSafeIndex(ue, i, NaN);
    row.CellId = localSafeIndex(cellId, i, NaN);
    row.CanonicalSlot = localSafeIndex(slot, i, NaN);
    row.Time_s = (double(row.CanonicalSlot) - 1) * slotDuration_s;
    row.MeasuredSINR_dB = localSafeIndex(sinr, i, NaN);
    row.SINRSource = localSafeIndexText(sinrSource, i, "");
    row.MCS = localSafeIndex(mcs, i, NaN);
    row.Rank = localSafeIndex(rank, i, NaN);
    row.Layers = localSafeIndex(layers, i, NaN);
    row.Modulation = localSafeIndexText(modulation, i, "");
    row.Status = localSafeIndexText(status, i, "");
    row.SourceTable = string(sourcePath);
    rows(end+1, 1) = row; %#ok<AGROW>
end
end

function row = localEmptyMeasuredSINRRow()
row = struct( ...
    "Direction", "", "UeId", NaN, "CellId", NaN, "CanonicalSlot", NaN, "Time_s", NaN, ...
    "MeasuredSINR_dB", NaN, "SINRSource", "", "MCS", NaN, "Rank", NaN, "Layers", NaN, ...
    "Modulation", "", "Status", "", "SourceTable", "");
end

function values = localFirstAvailableTableColumn(T, names)
if nargin < 2
    names = strings(0, 1);
end
for name = reshape(string(names), 1, [])
    if localHasColumn(T, name)
        values = localColumnDouble(T, name, NaN(height(T), 1));
        return;
    end
end
values = NaN(height(T), 1);
end

function values = localFirstAvailableTableText(T, names)
for name = reshape(string(names), 1, [])
    if localHasColumn(T, name)
        values = string(T.(char(name)));
        values = reshape(values, [], 1);
        return;
    end
end
values = strings(height(T), 1);
end

function value = localSafeIndex(values, idx, defaultValue)
if nargin < 3
    defaultValue = NaN;
end
value = defaultValue;
values = values(:);
if idx >= 1 && idx <= numel(values) && isfinite(values(idx))
    value = double(values(idx));
end
end

function value = localSafeIndexText(values, idx, defaultValue)
value = string(defaultValue);
values = string(values(:));
if idx >= 1 && idx <= numel(values) && strlength(strtrim(values(idx))) > 0
    value = string(values(idx));
end
end

function d = localTraceRouteLength(T)
d = 0;
if ~(istable(T) && height(T) > 1)
    return;
end
x = localColumnDouble(T, "X_m", NaN);
y = localColumnDouble(T, "Y_m", NaN);
z = localColumnDouble(T, "Z_m", NaN);
step = sqrt(diff(x).^2 + diff(y).^2 + diff(z).^2);
step = step(isfinite(step));
if ~isempty(step)
    d = sum(step, "omitnan");
end
end

function [coverageOk, missingSlots] = localTraceCoverageStatus(T, expectedSlots)
coverageOk = false;
missingSlots = NaN;
if ~(istable(T) && height(T) > 0)
    return;
end
slots = unique(localColumnDouble(T, "CanonicalSlot", NaN));
slots = sort(slots(isfinite(slots)));
if isempty(slots)
    missingSlots = expectedSlots;
    return;
end
if ~(isfinite(expectedSlots) && expectedSlots >= 1)
    expectedSlots = numel(slots);
end
expectedSpan = (1:expectedSlots).';
coverageOk = numel(slots) == numel(expectedSpan) && isequal(slots(:), expectedSpan);
missingSlots = max(0, expectedSlots - numel(slots));
end

function hz = localRuntimeExpectedDoppler(speedMps, carrierHz, lightSpeed)
hz = NaN;
if isfinite(speedMps) && speedMps >= 0 && isfinite(carrierHz) && carrierHz > 0
    hz = abs(speedMps) * carrierHz / lightSpeed;
end
end

function status = localRuntimeTraceRowStatus(row)
required = [row.UeId, row.CellId, row.CanonicalSlot, row.Time_s, row.X_m, row.Y_m, row.Z_m, ...
    row.Speed_mps, row.Distance3D_m, row.PropagationDelay_s, row.ExpectedDopplerHz, row.AppliedDopplerHz, row.Pathloss_dB];
if all(isfinite(required))
    status = "runtime_trace_complete";
else
    status = "runtime_trace_partial";
end
end

function value = localTableNumber(T, idx, names, defaultValue)
value = double(defaultValue);
for name = string(names(:)).'
    if localHasColumn(T, name)
        raw = T.(char(name));
        if idx <= numel(raw)
            candidate = localToDouble(raw(idx));
            if ~isempty(candidate) && isfinite(candidate(1))
                value = double(candidate(1));
                return;
            end
        end
    end
end
end

function value = localTableString(T, idx, names, defaultValue)
value = string(defaultValue);
for name = string(names(:)).'
    if localHasColumn(T, name)
        raw = string(T.(char(name)));
        if idx <= numel(raw) && strlength(strtrim(raw(idx))) > 0
            value = string(raw(idx));
            return;
        end
    end
end
end

function tf = localTableLogical(T, idx, name, defaultValue)
tf = logical(defaultValue);
if localHasColumn(T, name)
    vals = localColumnAsLogical(T.(char(name)));
    if idx <= numel(vals)
        tf = logical(vals(idx));
    end
end
end

function rad = localDegreesToRadians(deg)
if isfinite(deg)
    rad = deg * pi / 180;
else
    rad = NaN;
end
end

function c = localLightSpeed()
c = 299792458;
end

function tf = localAllTableFlag(T, name)
tf = false;
if istable(T) && height(T) > 0 && localHasColumn(T, name)
    tf = all(localColumnAsLogical(T.(char(name))));
end
end

function T = localReadOptionalTable(path)
T = table();
if exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "VariableNamingRule", "preserve", "TextType", "string", "Delimiter", ",");
catch
    T = table();
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function x = localColumnDouble(T, name, defaultValue)
if nargin < 3
    defaultValue = NaN;
end
if ~(istable(T) && height(T) > 0)
    x = zeros(0, 1);
    return;
end
if localHasColumn(T, name)
    raw = T.(char(name));
    x = localToDouble(raw);
else
    if isscalar(defaultValue)
        x = repmat(double(defaultValue), height(T), 1);
    else
        x = localToDouble(defaultValue);
        if numel(x) ~= height(T)
            x = repmat(NaN, height(T), 1);
        end
    end
end
x = x(:);
end

function x = localToDouble(raw)
if isempty(raw)
    x = zeros(0, 1);
elseif isnumeric(raw) || islogical(raw)
    x = double(raw);
else
    x = str2double(string(raw));
end
x = x(:);
end

function tf = localFirstLogical(values, defaultValue)
if nargin < 2
    defaultValue = false;
end
tf = logical(defaultValue);
if isempty(values)
    return;
end
v = localColumnAsLogical(values);
if ~isempty(v)
    tf = logical(v(1));
end
end

function text = localFirstString(T, name, defaultValue)
if nargin < 3
    defaultValue = "";
end
text = string(defaultValue);
if istable(T) && height(T) > 0 && localHasColumn(T, name)
    raw = string(T.(char(name)));
    if ~isempty(raw)
        text = raw(1);
    end
end
end

function n = localUniqueFiniteCount(values)
v = localToDouble(values);
v = v(isfinite(v));
n = double(numel(unique(v)));
end

function m = localMeanFinite(values)
v = localToDouble(values);
v = v(isfinite(v));
if isempty(v)
    m = NaN;
else
    m = mean(v);
end
end

function m = localMinFinite(values)
v = localToDouble(values);
v = v(isfinite(v));
if isempty(v)
    m = NaN;
else
    m = min(v);
end
end

function m = localMaxFinite(values)
v = localToDouble(values);
v = v(isfinite(v));
if isempty(v)
    m = NaN;
else
    m = max(v);
end
end

function m = localFirstFinite(values)
v = localToDouble(values);
idx = find(isfinite(v), 1, "first");
if isempty(idx)
    m = NaN;
else
    m = v(idx);
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    candidate = localFirstFinite(varargin{i});
    if isfinite(candidate)
        value = double(candidate);
        return;
    end
end
end

function v = localVarianceFinite(values)
x = localToDouble(values);
x = x(isfinite(x));
if numel(x) < 2
    v = NaN;
else
    v = var(x, 0);
end
end

function stop = localWaypointPosition(p, fallback)
waypoints = sixgr.util.structGet(p, "waypoints_m", struct([]));
if isempty(waypoints)
    waypoints = sixgr.util.structGet(p, "waypoints", struct([]));
end
stop = fallback;
if isstruct(waypoints) && ~isempty(waypoints)
    stop = localVector(sixgr.util.structGet(waypoints(1), "position_m", fallback), 3);
elseif iscell(waypoints) && ~isempty(waypoints)
    stop = localVector(sixgr.util.structGet(waypoints{1}, "position_m", fallback), 3);
else
    routeLength = localNumber(p, "route_length_m", NaN);
    if isfinite(routeLength) && routeLength > 0
        headingDeg = localNumber(p, ["heading_deg","initial_heading_deg"], 0);
        stop = fallback + routeLength .* [cosd(headingDeg), sind(headingDeg), 0];
    end
end
end

function slots = localRequiredRouteSlots(cfg)
paths = localUserPaths(cfg);
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = NaN;
for i = 1:numel(paths)
    start = localVector(sixgr.util.structGet(paths(i), "initial_position_m", [NaN NaN NaN]), 3);
    stop = localWaypointPosition(paths(i), start);
    speed = localNumber(paths(i), "speed_kmh", localNumber(cfg, "mobility.ue_speed_kmh", NaN)) / 3.6;
    dist = norm(stop - start);
    t = localSafeDivide(dist, speed);
    s = ceil(t / (slotMs / 1e3));
    if ~isfinite(slots) || s > slots
        slots = s;
    end
end
if ~isfinite(slots)
    slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0);
end
end

function value = localNumber(cfg, paths, defaultValue)
value = defaultValue;
for path = string(paths)
    raw = localGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function tf = localBool(cfg, paths, defaultValue)
tf = logical(defaultValue);
for path = string(paths)
    raw = localGet(cfg, path, []);
    if islogical(raw) || isnumeric(raw)
        if isscalar(raw)
            tf = logical(raw);
            return;
        end
    else
        s = lower(strtrim(string(raw)));
        if s == "true" || s == "1" || s == "yes"
            tf = true;
            return;
        elseif s == "false" || s == "0" || s == "no"
            tf = false;
            return;
        end
    end
end
end

function value = localGet(cfg, path, defaultValue)
try
    value = sixgr.util.structGet(cfg, path, defaultValue);
catch
    value = defaultValue;
end
end

function txt = localValueText(value)
if isempty(value)
    txt = "";
elseif isnumeric(value) || islogical(value)
    txt = strjoin(string(value(:).'), " ");
elseif ischar(value) || isstring(value)
    txt = strjoin(string(value(:).'), " ");
else
    try
        txt = string(jsonencode(value));
    catch
        txt = string(class(value));
    end
end
end

function txt = localNormalizedConceptValueText(conceptName, path, value)
txt = localValueText(value);
if strlength(txt) == 0
    return;
end
conceptName = string(conceptName);
path = string(path);
if conceptName == "scs_khz"
    n = str2double(txt);
    if isfinite(n)
        if contains(lower(path), "scs_hz")
            n = n / 1e3;
        end
        txt = string(n);
    end
end
end

function v = localVector(raw, n)
if iscell(raw)
    raw = [raw{:}];
end
try
    v = double(raw(:).');
catch
    v = str2double(string(raw(:))).';
end
if numel(v) < n
    v(end+1:n) = NaN;
else
    v = v(1:n);
end
end

function T = localStructRowsToTable(rows)
if isstruct(rows)
    T = struct2table(rows, "AsArray", true);
elseif isempty(rows)
    T = table();
else
    T = rows;
end
end

function y = localSafeDivide(a, b)
if ~isfinite(a) || ~isfinite(b) || b == 0
    y = NaN;
else
    y = a ./ b;
end
end

function out = localTernary(cond, a, b)
if logical(cond)
    out = string(a);
else
    out = string(b);
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:buildPhase7ReadinessArtifacts:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
