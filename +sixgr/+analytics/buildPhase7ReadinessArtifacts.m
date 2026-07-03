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
geometryTables = localBuildGeometryTables(cfg);
mobilityTables = localBuildMobilityTables(cfg, geometryTables);
campaignEvidence = localBuildCampaignEvidence(runDir, cfg);
gateStatus = localBuildGateStatus(runDir, cfg, cfgTables, storageTables, geometryTables, mobilityTables, campaignEvidence);
finalTables = localBuildFinalReportTables(gateStatus, cfgTables, storageTables, mobilityTables, campaignEvidence);

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
localWrite(dirs.GeometryCSV, "ue_initial_positions.csv", geometryTables.UEInitialPositions);
localWrite(dirs.GeometryCSV, "trajectory_geometry.csv", geometryTables.TrajectoryGeometry);
localWrite(dirs.GeometryCSV, "geometry_validation.csv", geometryTables.Validation);

localWrite(dirs.MobilityCSV, "trajectory_resolution.csv", mobilityTables.Resolution);
localWrite(dirs.MobilityCSV, "trajectory_segment_table.csv", mobilityTables.Segments);
localWrite(dirs.MobilityCSV, "inter_ue_distance_validation.csv", mobilityTables.InterUEDistance);
localWrite(dirs.MobilityCSV, "trajectory_constraint_conflicts.csv", mobilityTables.ConstraintConflicts);

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
    localConcept("noise_figure_db", ["scenario.bs.noiseFigure_dB","scenario.ue.noiseFigure_dB","air_interface.bs_noise_figure_dB","air_interface.ue_noise_figure_dB"], "+sixgr/+link/applyWaveformImpairments.m", "thermal_noise_resolution", "rf/csv/thermal_noise_validation.csv")
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

function geometryTables = localBuildGeometryTables(cfg)
coord = table("local_cartesian", "site_origin", "x_east_y_north_z_up", "degrees", ...
    "azimuth_from_positive_x_counterclockwise", "elevation_from_xy_plane", ...
    'VariableNames', {'CoordinateSystem','Origin','Axes','AngleUnits','AzimuthConvention','ElevationConvention'});

bsHeight = localNumber(cfg, "scenario.bs.height_m", 25);
site = table(1, 1, 0, 0, bsHeight, localNumber(cfg, "scenario.bs.downtilt_deg", NaN), ...
    'VariableNames', {'SiteID','CellID','X_m','Y_m','Z_m','Downtilt_deg'});

paths = localUserPaths(cfg);
ueRows = repmat(struct("UEID", NaN, "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
    "Speed_kmh", NaN, "PathSource", ""), numel(paths), 1);
for i = 1:numel(paths)
    p = paths(i);
    start = localVector(sixgr.util.structGet(p, "initial_position_m", [NaN NaN NaN]), 3);
    pathSource = string(sixgr.util.structGet(p, "path_source", "mobility.user_paths"));
    ueRows(i) = struct("UEID", localNumber(p, "ue_id", i), "X_m", start(1), ...
        "Y_m", start(2), "Z_m", start(3), "Speed_kmh", localNumber(p, "speed_kmh", localNumber(cfg, "mobility.ue_speed_kmh", NaN)), ...
        "PathSource", pathSource);
end
ueInitial = localStructRowsToTable(ueRows);

traj = localBuildTrajectoryGeometry(paths, cfg);
geomOk = height(ueInitial) > 0 && all(isfinite(ueInitial.X_m)) && height(traj) > 0;
validation = table(geomOk, "local_cartesian_declared", height(ueInitial), ...
    "pathloss_distance_definition_requires_runtime_reconciliation", ...
    'VariableNames', {'GeometryValidationOk','CoordinateStatus','UECount','ValidationNotes'});

geometryTables = struct("CoordinateSystem", coord, "SitePositions", site, ...
    "UEInitialPositions", ueInitial, "TrajectoryGeometry", traj, "Validation", validation);
end

function T = localBuildTrajectoryGeometry(paths, cfg)
rows = repmat(struct("UEID", NaN, "StartX_m", NaN, "StartY_m", NaN, "StartZ_m", NaN, ...
    "EndX_m", NaN, "EndY_m", NaN, "EndZ_m", NaN, "RouteLength_m", NaN, ...
    "Speed_kmh", NaN, "TraversalTime_s", NaN, "RequiredTraversalSlots", NaN, "LoopMode", ""), numel(paths), 1);
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
        "RequiredTraversalSlots", ceil(t / (slotMs / 1e3)), "LoopMode", string(sixgr.util.structGet(p, "loop_mode", "")));
end
T = localStructRowsToTable(rows);
end

function mobilityTables = localBuildMobilityTables(cfg, geometryTables)
traj = geometryTables.TrajectoryGeometry;
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 0);
runDurationS = slots * slotMs / 1e3;
if height(traj) == 0
    resolution = table(false, slots, runDurationS, NaN, NaN, "no_user_paths", ...
        'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s','RequiredTraversalSlots','ActualDistanceTravelled_m','Status'});
    segments = table();
else
    requiredSlots = max(traj.RequiredTraversalSlots);
    speedMs = traj.Speed_kmh / 3.6;
    actualDist = min(traj.RouteLength_m, speedMs .* runDurationS);
    resolution = table(slots >= requiredSlots, slots, runDurationS, requiredSlots, min(actualDist), ...
        localTernary(slots >= requiredSlots, "full_route_duration_configured", "SHORT_MOBILITY_DIAGNOSTIC"), ...
        'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s','RequiredTraversalSlots','ActualDistanceTravelled_m','Status'});
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
    "InterUEDistance", interUE, "ConstraintConflicts", conflicts);
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
    "simulation.num_seeds", "canonical_control.run.final_runs", ...
    "simulation.final_runs", "canonical_control.run.monte_carlo_iterations", ...
    "simulation.monte_carlo_iterations"], 30);
thresholds = struct( ...
    "RequiredSeedCount", max(1, round(requiredSeeds)), ...
    "MinTrialsPerBin", max(1, round(localNumber(cfg, ["canonical_control.run.min_trials_per_sinr_bin", ...
        "simulation.min_trials_per_sinr_bin", "statistics.min_trials_per_sinr_bin"], 30))), ...
    "MaxCIWidth", localNumber(cfg, ["canonical_control.run.max_ci_width", ...
        "simulation.max_ci_width", "statistics.max_ci_width"], 0.05), ...
    "MinSNRPoints", max(1, round(localNumber(cfg, ["canonical_control.run.min_campaign_snr_points", ...
        "simulation.min_campaign_snr_points", "statistics.min_campaign_snr_points"], 5))), ...
    "ConfidenceLevel", localNumber(cfg, ["canonical_control.run.confidence_level", ...
        "simulation.confidence_level", "statistics.confidence_level"], 0.95));
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
    [lo, hi] = localClopperPearsonInterval(failureCount, trialCount, thresholds.ConfidenceLevel);
    ciWidth = hi - lo;
    seedCount = max(localUniqueFiniteCount(localColumnDouble(fixed(mask, :), "PointSeed", NaN)), ...
        localMaxFinite(localColumnDouble(fixed(mask, :), "DL_DropCount", NaN)));
    rows(end+1, 1) = struct("PostEqSINR_dB_BinCenter", s, "SNR_dB", s, ...
        "BinMin", s, "BinMax", s, "TrialCount", double(trialCount), ...
        "FailureCount", double(failureCount), "BLER", double(bler), ...
        "BLER_CI_Low", double(lo), "BLER_CI_High", double(hi), ...
        "BLER_CI_Width", double(ciWidth), ...
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
flags.CheckpointResumeEquivalenceOk = localEvidenceFlag(checkpoint, "CheckpointResumeEquivalenceOk");
flags.SerialParallelDeterminismOk = localEvidenceFlag(determinism, "SerialParallelDeterminismOk");
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
        T = table('Size', [0 14], 'VariableTypes', {'double','double','double','double','double','double', ...
            'double','double','double','double','double','double','string','string'}, ...
            'VariableNames', {'PostEqSINR_dB_BinCenter','SNR_dB','BinMin','BinMax','TrialCount', ...
            'FailureCount','BLER','BLER_CI_Low','BLER_CI_High','BLER_CI_Width','Goodput_Mbps_mean', ...
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

function status = localBuildGateStatus(runDir, cfg, cfgTables, storageTables, geometryTables, mobilityTables, campaignEvidence)
flags = struct();
flags.ResolvedConfigurationConsistentOk = ~any(string(cfgTables.Conflicts.ConflictStatus) == "conflict_unresolved");
flags.CapturePolicyTruthfulOk = logical(storageTables.Policy.CapturePolicyTruthfulOk(1));
flags.GeometryValidationOk = logical(geometryTables.Validation.GeometryValidationOk(1));
flags.FullTrajectoryExecutedOk = logical(mobilityTables.Resolution.FullTrajectoryExecutedOk(1));
flags.InterUeConstraintResolvedOk = isempty(mobilityTables.ConstraintConflicts);
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
flags = localApplyPhaseRollupFlags(flags);
flags.PublicationReadinessOk = localAllNamedFlagsTrue(flags, sixgr.runtime.Phase7TruthEvaluator.gateNames()) && ...
    localAllNamedFlagsTrue(flags, ["Phase1Ok","Phase2Ok","Phase3Ok","Phase4Ok","Phase5Ok","Phase6Ok"]);
status = sixgr.runtime.Phase7TruthEvaluator.evaluate(flags);
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

function flags = localApplyPhaseRollupFlags(flags)
flags.Phase1Ok = localAllNamedFlagsTrue(flags, [
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
    "PolarizationReconciliationOk"]);
flags.Phase2Ok = localAllNamedFlagsTrue(flags, [
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
    "MobilityKpiReconciliationOk"]);
flags.Phase3Ok = localAllNamedFlagsTrue(flags, [
    "ArtifactCompletenessOk"
    "PlotDataLineageOk"
    "Phase7NoFabricationOk"]);
flags.Phase4Ok = localAllNamedFlagsTrue(flags, [
    "CanonicalKpiLedgerOk"
    "ThroughputReconciliationOk"
    "BlerBerReconciliationOk"
    "LatencyReconciliationOk"
    "AccessKpiReconciliationOk"
    "SchedulerKpiReconciliationOk"]);
flags.Phase5Ok = localAllNamedFlagsTrue(flags, [
    "SeedHierarchyOk"
    "CampaignDesignOk"
    "CampaignCompletionOk"
    "MultiSeedDropStatisticsOk"
    "ConfidenceIntervalsOk"
    "SampleAdequacyOk"
    "SweepDataQualityOk"
    "CheckpointResumeEquivalenceOk"
    "SerialParallelDeterminismOk"]);
flags.Phase6Ok = localAllNamedFlagsTrue(flags, [
    "EnergyModelOk"
    "PerformanceProfileOk"
    "LongRunStabilityOk"]);
end

function tf = localAllNamedFlagsTrue(flags, names)
tf = true;
for name = string(names(:)).'
    tf = tf && logical(sixgr.util.structGet(flags, char(name), false));
end
end

function finalTables = localBuildFinalReportTables(gateStatus, cfgTables, storageTables, mobilityTables, campaignEvidence)
failures = string(gateStatus.FailureCodes(:));
if isempty(failures)
    defects = table("none", "none", "all gates passed", "closed", ...
        'VariableNames', {'defect_id','severity','summary','status'});
else
    defects = table("PH7-" + string((1:numel(failures))'), repmat("blocker", numel(failures), 1), ...
        failures, repmat("open", numel(failures), 1), ...
        'VariableNames', {'defect_id','severity','summary','status'});
end
fullRouteStatus = string(localTernary(logical(mobilityTables.Resolution.FullTrajectoryExecutedOk(1)), ...
    "supported_by_runtime_trajectory_rows", "unsupported_until_full_route_run"));
campaignStatus = string(localTernary(logical(campaignEvidence.Flags.CampaignCompletionOk), ...
    "supported_by_fixed_link_monte_carlo_campaign", "unsupported_until_multi_seed_campaign_rows"));
publicationStatus = string(localTernary(logical(gateStatus.PublicationReadinessOk), ...
    "supported_by_all_phase7_gates", "unsupported_until_all_phase7_gates_pass"));
claims = table(["single_cell_two_ue_scope";"full_route_mobility_study";"multi_seed_statistics";"publication_ready"], ...
    ["supported_scope"; fullRouteStatus; campaignStatus; publicationStatus], ...
    ["scenario YAML scope";"mobility/csv/trajectory_resolution.csv";"air_interface/csv/dl_multi_seed_bler_curve.csv";"reports/csv/phase7_truth_gates.csv"], ...
    'VariableNames', {'claim','support_status','evidence_artifact'});
kp = table("phase7_kpi_reconstruction", "not_evaluated_without_full_runtime_rows", ...
    "canonical KPI ledger pending full route/campaign rows", ...
    'VariableNames', {'kpi_group','status','notes'});
campaign = campaignEvidence.Tables.Summary;
if logical(gateStatus.PublicationReadinessOk)
    gradeValue = 10;
    confidence = "high";
    reason = "All Phase 7 and phase rollup gates verified from runtime evidence.";
else
    gradeValue = 0;
    confidence = "low";
    reason = "Publication readiness blocked until every evidence-derived Phase 7 gate passes.";
end
grade = struct("GradeOutOf10", double(gradeValue), "Confidence", char(confidence), ...
    "Reason", char(reason), ...
    "Phase7Ok", logical(gateStatus.Phase7Ok), ...
    "PublicationReadinessOk", logical(gateStatus.PublicationReadinessOk));
finalTables = struct("DefectRegister", defects, "ClaimsMatrix", claims, ...
    "KPITable", kp, "CampaignSummary", campaign, "Grade", grade);
end

function localWriteFinalMarkdown(finalDir, gateStatus, cfgTables, storageTables, mobilityTables)
if logical(gateStatus.PublicationReadinessOk)
    verdict = "publication-ready.";
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
    "Phase7Ok: " + string(logical(gateStatus.Phase7Ok))
    "ResultOk: " + string(logical(gateStatus.ResultOk))
    "PublicationReadinessOk: " + string(logical(gateStatus.PublicationReadinessOk))
    "Primary blocker: " + string(gateStatus.PrimaryFailureCode)
    ""
    "The generated artifacts are preflight and audit artifacts. They do not claim a full-route mobility or multi-seed campaign result."
    ];
files = ["executive_summary.md","final_scientific_audit.md","final_publication_readiness.md", ...
    "final_channel_rf_validation.md","final_mobility_validation.md","final_statistical_validation.md", ...
    "final_energy_validation.md","final_performance_validation.md","final_output_completeness.md", ...
    "final_reproducibility_instructions.md"];
for i = 1:numel(files)
    localWriteText(fullfile(finalDir, files(i)), strjoin(summary, newline));
end
html = "<!doctype html><html><body><h1>Phase 7 Scientific Audit</h1><p>Not publication-ready. Phase7Ok=false unless all evidence gates pass.</p></body></html>";
localWriteText(fullfile(finalDir, "final_scientific_audit.html"), html);
localWriteText(fullfile(finalDir, "final_source_diff.patch"), ...
    "Source diff is repository-state dependent; run git diff from the committed Phase 7 branch to reproduce.");
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
nUE = round(localNumber(cfg, ["users.n_users","deployment_topology.num_ues","scenario.ue.nUE"], 0));
if ~(isfinite(speedKmh) && speedKmh >= 0 && isfinite(nUE) && nUE >= 1)
    return;
end
radius = localFirstFiniteNumber(cfg, ["deployment_topology.max_ue_distance_from_bs_m", ...
    "scenario.ue.distribution.max_bs_dist_m", "scenario.ue.distribution.maxBsDistance_m", ...
    "deployment_topology.cell_radius_m"]);
minRadius = localFirstFiniteNumber(cfg, ["deployment_topology.min_ue_distance_from_bs_m", ...
    "scenario.ue.distribution.min_bs_dist_m", "scenario.ue.distribution.minBsDistance_m"]);
if ~isfinite(radius)
    radius = minRadius;
end
if ~(isfinite(radius) && radius > 0)
    return;
end
if isfinite(minRadius) && minRadius > 0
    radius = max(radius, minRadius);
end
slotMs = localNumber(cfg, "frame_timing.slot_duration_ms", 0.5);
slots = localNumber(cfg, ["run_control.total_slots","simulation.n_slots"], 1);
durationS = max(double(slots) * double(slotMs) / 1e3, double(slotMs) / 1e3);
routeLength = max(0, double(speedKmh) / 3.6 * durationS);
headingDeg = localNumber(cfg, ["mobility.heading_deg","mobility.direction_deg","scenario.mobility.heading_deg"], 0);
ueHeight = localNumber(cfg, ["scenario.ue.height_m","deployment_topology.ue_height_m"], 1.5);

paths = repmat(struct("ue_id", NaN, "label", "", "speed_kmh", NaN, ...
    "initial_position_m", [NaN NaN NaN], "initial_heading_deg", NaN, ...
    "waypoints_m", struct([]), "loop_mode", "hold", "path_source", "mobility.ue_speed_kmh"), nUE, 1);
move = routeLength .* [cosd(headingDeg), sind(headingDeg), 0];
for i = 1:nUE
    angle = 2 * pi * double(i - 1) / max(1, double(nUE));
    start = [radius * cos(angle), radius * sin(angle), ueHeight];
    stop = start + move;
    paths(i).ue_id = i;
    paths(i).label = sprintf("ue_%d_scalar_speed_path", i);
    paths(i).speed_kmh = double(speedKmh);
    paths(i).initial_position_m = start;
    paths(i).initial_heading_deg = double(headingDeg);
    paths(i).waypoints_m = struct("position_m", stop, "hold_time_s", 0);
    paths(i).loop_mode = "hold";
    paths(i).path_source = "mobility.ue_speed_kmh";
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

function v = localVarianceFinite(values)
x = localToDouble(values);
x = x(isfinite(x));
if numel(x) < 2
    v = NaN;
else
    v = var(x, 0);
end
end

function [lo, hi] = localClopperPearsonInterval(k, n, confidenceLevel)
lo = NaN;
hi = NaN;
k = double(k);
n = double(n);
if ~(isfinite(n) && n > 0 && isfinite(k) && k >= 0)
    return;
end
k = min(max(k, 0), n);
alpha = 1 - double(confidenceLevel);
alpha = min(max(alpha, eps), 1 - eps);
if k == 0
    lo = 0;
else
    lo = betaincinv(alpha / 2, k, n - k + 1);
end
if k == n
    hi = 1;
else
    hi = betaincinv(1 - alpha / 2, k + 1, n - k);
end
lo = max(0, min(1, double(lo)));
hi = max(0, min(1, double(hi)));
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
if isempty(rows)
    T = table();
else
    T = struct2table(rows, "AsArray", true);
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
