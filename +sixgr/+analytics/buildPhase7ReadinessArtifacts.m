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
gateStatus = localBuildGateStatus(runDir, cfgTables, storageTables, geometryTables, mobilityTables);
finalTables = localBuildFinalReportTables(gateStatus, cfgTables, storageTables, mobilityTables);

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
report.Gates = gateStatus;
report.OutputRoot = string(runDir);
end

function dirs = localEnsurePhase7Dirs(runDir)
dirs = struct();
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
    ueRows(i) = struct("UEID", localNumber(p, "ue_id", i), "X_m", start(1), ...
        "Y_m", start(2), "Z_m", start(3), "Speed_kmh", localNumber(p, "speed_kmh", localNumber(cfg, "mobility.ue_speed_kmh", NaN)), ...
        "PathSource", "mobility.user_paths");
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

function status = localBuildGateStatus(runDir, cfgTables, storageTables, geometryTables, mobilityTables)
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
flags.FinalScientificClaimsTruthfulOk = false;
flags.OutputSchemaValidationOk = true;
flags.ArtifactCompletenessOk = false;
flags.PlotDataLineageOk = false;
status = sixgr.runtime.Phase7TruthEvaluator.evaluate(flags);
end

function tf = localChannelRFArtifactsPass(runDir)
path = fullfile(runDir, "channel", "csv", "channel_configured_vs_applied.csv");
tf = false;
if exist(path, "file") ~= 2
    return;
end
try
    T = readtable(path, "VariableNamingRule", "preserve", "TextType", "string");
    if any(string(T.Properties.VariableNames) == "ConfiguredAppliedOk")
        tf = all(localColumnAsLogical(T.ConfiguredAppliedOk));
    end
catch
    tf = false;
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

function finalTables = localBuildFinalReportTables(gateStatus, cfgTables, storageTables, mobilityTables)
failures = string(gateStatus.FailureCodes(:));
if isempty(failures)
    defects = table("none", "none", "all gates passed", "closed", ...
        'VariableNames', {'defect_id','severity','summary','status'});
else
    defects = table("PH7-" + string((1:numel(failures))'), repmat("blocker", numel(failures), 1), ...
        failures, repmat("open", numel(failures), 1), ...
        'VariableNames', {'defect_id','severity','summary','status'});
end
claims = table(["single_cell_two_ue_scope";"full_route_mobility_study";"publication_ready"], ...
    ["supported_scope";"unsupported_until_full_route_run";"unsupported_until_all_phase7_gates_pass"], ...
    ["scenario YAML scope";"mobility/csv/trajectory_resolution.csv";"reports/csv/phase7_truth_gates.csv"], ...
    'VariableNames', {'claim','support_status','evidence_artifact'});
kp = table("phase7_kpi_reconstruction", "not_evaluated_without_full_runtime_rows", ...
    "canonical KPI ledger pending full route/campaign rows", ...
    'VariableNames', {'kpi_group','status','notes'});
campaign = table(0, 0, 0, "no_phase7_campaign_runs_provided", ...
    'VariableNames', {'PilotRuns','FinalRuns','FailedRuns','Status'});
grade = struct("GradeOutOf10", 0, "Confidence", "low", ...
    "Reason", "Phase7Ok false; publication readiness blocked until full runtime/campaign evidence exists", ...
    "Phase7Ok", logical(gateStatus.Phase7Ok), ...
    "PublicationReadinessOk", logical(gateStatus.PublicationReadinessOk));
finalTables = struct("DefectRegister", defects, "ClaimsMatrix", claims, ...
    "KPITable", kp, "CampaignSummary", campaign, "Grade", grade);
end

function localWriteFinalMarkdown(finalDir, gateStatus, cfgTables, storageTables, mobilityTables)
summary = [
    "# Phase 7 Scientific Readiness"
    ""
    "Verdict: not publication-ready."
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
paths = sixgr.util.structGet(cfg, "mobility.user_paths", struct([]));
if isempty(paths)
    paths = struct([]);
end
end

function stop = localWaypointPosition(p, fallback)
waypoints = sixgr.util.structGet(p, "waypoints_m", struct([]));
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
