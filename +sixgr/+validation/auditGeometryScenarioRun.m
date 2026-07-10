function audit = auditGeometryScenarioRun(runFolder, varargin)
%AUDITGEOMETRYSCENARIORUN Verify runtime geometry evidence for geometry LLS runs.

p = inputParser;
p.addParameter("Strict", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("WriteOutputs", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("SpeedToleranceKmh", 1.0, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter("DopplerToleranceHz", 1.0, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.parse(varargin{:});
opt = p.Results;

rootRunFolder = localResolveRootRunFolder(runFolder);
if exist(rootRunFolder, "dir") ~= 7
    error("sixgr:validation:auditGeometryScenarioRun:RunFolderMissing", ...
        "Run folder does not exist: %s", rootRunFolder);
end

layout = sixgr.report.resultLayout(rootRunFolder);
reportCSVDir = layout.ReportCSVDir;
reportJSONDir = fullfile(layout.ReportDir, "json");

cfgInfo = localReadOptionalJSON(fullfile(layout.MetaDir, "scenario_config_resolved.json"));
cfg = cfgInfo.Data;
runClassT = localReadOptionalTable(fullfile(reportCSVDir, "run_classification.csv"));

files = localReadGeometryArtifacts(rootRunFolder, reportCSVDir);
req = localResolveGeometryRequirements(cfg, runClassT, opt);

rows = repmat(localEmptyAuditRow(), 0, 1);
rows = [rows; localRequiredArtifactRows(files)]; %#ok<AGROW>
rows = [rows; localRunClassRows(req)]; %#ok<AGROW>
rows = [rows; localTopologyRows(files.TopologyNodes, req)]; %#ok<AGROW>
rows = [rows; localTrajectoryRows(files.Trajectory, req)]; %#ok<AGROW>
rows = [rows; localSpeedRows(files.Trajectory, req)]; %#ok<AGROW>
rows = [rows; localDistanceRows(files.Trajectory)]; %#ok<AGROW>
rows = [rows; localPathlossRows(files.Trajectory, req)]; %#ok<AGROW>
rows = [rows; localPropagationDelayRows(files.Trajectory, files.PropagationDelay)]; %#ok<AGROW>
rows = [rows; localServingAssignmentRows(files.ServingAssignment)]; %#ok<AGROW>
rows = [rows; localDopplerRows(files.Trajectory, files.Doppler, req)]; %#ok<AGROW>
rows = [rows; localContinuityRows(files.Continuity)]; %#ok<AGROW>
rows = [rows; localMeasuredSINRRows(files.MeasuredSINR)]; %#ok<AGROW>

auditTable = struct2table(rows, "AsArray", true);
failMask = string(auditTable.Status) == "FAIL";
warnMask = string(auditTable.Status) == "WARN";

audit = struct();
audit.RootRunFolder = string(rootRunFolder);
audit.RunClass = string(req.RunClass);
audit.Required = logical(req.Required);
audit.Executed = true;
audit.Ok = ~any(failMask);
audit.Status = localTernary(audit.Ok, "pass", "fail");
audit.FailureCount = double(nnz(failMask));
audit.WarningCount = double(nnz(warnMask));
audit.FailureCodes = unique(string(auditTable.FailureCode(failMask)), "stable");
audit.WarningCodes = unique(string(auditTable.FailureCode(warnMask)), "stable");
audit.Table = auditTable;
audit.Options = opt;

if logical(opt.WriteOutputs)
    sixgr.util.ensureFolder(reportCSVDir);
    sixgr.util.ensureFolder(reportJSONDir);
    sixgr.analytics.writeAnalysisTable(fullfile(reportCSVDir, "geometry_runtime_audit.csv"), auditTable);
    jsonAudit = audit;
    jsonAudit.Table = table2struct(auditTable);
    sixgr.util.jsonWrite(fullfile(reportJSONDir, "geometry_runtime_audit.json"), jsonAudit);
end

if logical(opt.Strict) && ~audit.Ok
    error("sixgr:validation:auditGeometryScenarioRun:AuditFailed", ...
        "Geometry runtime audit failed with %d failure row(s): %s", ...
        audit.FailureCount, strjoin(audit.FailureCodes, ", "));
end
end

function files = localReadGeometryArtifacts(rootRunFolder, reportCSVDir)
files = struct();
files.TopologyNodes = localReadTableArtifact(fullfile(rootRunFolder, "geometry", "csv", "topology_nodes.csv"));
files.UEInitial = localReadTableArtifact(fullfile(rootRunFolder, "geometry", "csv", "ue_initial_positions.csv"));
files.Trajectory = localReadTableArtifact(fullfile(rootRunFolder, "geometry", "csv", "trajectory_geometry.csv"));
files.ServingAssignment = localReadTableArtifact(fullfile(rootRunFolder, "geometry", "csv", "serving_cell_assignment.csv"));
files.TrajectorySegments = localReadTableArtifact(fullfile(rootRunFolder, "mobility", "csv", "trajectory_segment_table.csv"));
files.Doppler = localReadTableArtifact(fullfile(rootRunFolder, "mobility", "csv", "doppler_reconciliation.csv"));
files.Pathloss = localReadTableArtifact(fullfile(rootRunFolder, "mobility", "csv", "pathloss_reconciliation.csv"));
files.PropagationDelay = localReadTableArtifact(fullfile(rootRunFolder, "mobility", "csv", "propagation_delay_reconciliation.csv"));
files.Continuity = localReadTableArtifact(fullfile(rootRunFolder, "mobility", "csv", "channel_continuity_reconciliation.csv"));
files.MeasuredSINR = localReadTableArtifact(fullfile(reportCSVDir, "measured_sinr_timeseries.csv"));
end

function req = localResolveGeometryRequirements(cfg, runClassT, opt)
req = struct();
req.RunClass = localFirstText([
    localGetText(cfg, "validation.run_class", "")
    localGetText(cfg, "validation.RunClass", "")
    localRunClassFromTable(runClassT)
    ]);
req.Required = req.RunClass == "ue_placement_geometry_lls" || ...
    localGetLogical(cfg, "validation.geometry_evidence_required", false);
req.FixedSNRSweepClaimed = req.RunClass == "fixed_snr_sweep_lls" || ...
    localGetLogical(cfg, "validation.fixed_snr_sweep_required", false);
req.ExpectedCells = localFirstFinite([
    localGetDouble(cfg, "topology.num_cells", NaN)
    localGetDouble(cfg, "deployment_topology.num_cells", NaN)
    ], NaN);
req.ExpectedUEs = localFirstFinite([
    localGetDouble(cfg, "topology.num_ues", NaN)
    localGetDouble(cfg, "deployment_topology.num_ues", NaN)
    localGetDouble(cfg, "users.n_users", NaN)
    ], NaN);
req.ExpectedSlots = localFirstFinite([
    localGetDouble(cfg, "canonical_control.run.measurement_slots", NaN)
    localGetDouble(cfg, "run_control.measurement_slots", NaN)
    localGetDouble(cfg, "canonical_control.run.total_slots", NaN)
    localGetDouble(cfg, "run_control.total_slots", NaN)
    localGetDouble(cfg, "simulation.n_slots", NaN)
    ], NaN);
req.WarmupSlots = localFirstFinite([
    localGetDouble(cfg, "canonical_control.run.warmup_slots", NaN)
    localGetDouble(cfg, "run_control.warmup_slots", NaN)
    ], 0);
req.ExpectedSpeedKmh = localFirstFinite([
    localGetDouble(cfg, "mobility.ue_speed_kmh", NaN)
    localGetDouble(cfg, "channel.mobility_kmph", NaN)
    localGetDouble(cfg, "channels.mobility_kmph", NaN)
    ], NaN);
req.PathlossEnabled = localFirstLogical([
    localGetLogical(cfg, "channel.pathloss_enabled", false)
    localGetLogical(cfg, "channels.pathloss_enabled", false)
    ], false);
req.SpeedToleranceKmh = double(opt.SpeedToleranceKmh);
req.DopplerToleranceHz = max(double(opt.DopplerToleranceHz), localFirstFinite([
    localGetDouble(cfg, "validation.mobility.doppler_tolerance_hz", NaN)
    localGetDouble(cfg, "validation.channel.doppler_tolerance_hz", NaN)
    ], double(opt.DopplerToleranceHz)));
end

function rows = localRequiredArtifactRows(files)
rows = repmat(localEmptyAuditRow(), 0, 1);
spec = {
    "geometry/csv/topology_nodes.csv", files.TopologyNodes
    "geometry/csv/ue_initial_positions.csv", files.UEInitial
    "geometry/csv/trajectory_geometry.csv", files.Trajectory
    "geometry/csv/serving_cell_assignment.csv", files.ServingAssignment
    "mobility/csv/trajectory_segment_table.csv", files.TrajectorySegments
    "mobility/csv/doppler_reconciliation.csv", files.Doppler
    "mobility/csv/pathloss_reconciliation.csv", files.Pathloss
    "mobility/csv/propagation_delay_reconciliation.csv", files.PropagationDelay
    "mobility/csv/channel_continuity_reconciliation.csv", files.Continuity
    "reports/csv/measured_sinr_timeseries.csv", files.MeasuredSINR
    };
for i = 1:size(spec, 1)
    relPath = string(spec{i, 1});
    art = spec{i, 2};
    fail = ~(logical(art.Present) && logical(art.Readable) && logical(art.NonEmpty));
    rows(end+1, 1) = localAuditRow( ...
        "required_artifact:" + relPath, relPath, localStatusFromFail(fail), ...
        localFailureToken(fail, "required_artifact_missing_or_empty"), ...
        localArtifactReason(art), ...
        string(double(logical(art.NonEmpty))), "true"); %#ok<AGROW>
end
end

function rows = localRunClassRows(req)
rows = repmat(localEmptyAuditRow(), 0, 1);
bad = req.RunClass ~= "ue_placement_geometry_lls";
rows(end+1, 1) = localAuditRow( ...
    "run_class_is_geometry", "reports/csv/run_classification.csv", ...
    localStatusFromFail(bad), localFailureToken(bad, "run_class_not_geometry"), ...
    "Geometry validation runs must resolve to ue_placement_geometry_lls.", ...
    string(req.RunClass), "ue_placement_geometry_lls"); %#ok<AGROW>

bad = logical(req.FixedSNRSweepClaimed);
rows(end+1, 1) = localAuditRow( ...
    "fixed_snr_sweep_not_claimed", "reports/csv/run_classification.csv", ...
    localStatusFromFail(bad), localFailureToken(bad, "fixed_snr_sweep_claim_present"), ...
    "Geometry runs must not claim fixed SNR sweep evidence.", ...
    localTernary(logical(req.FixedSNRSweepClaimed), "true", "false"), "false"); %#ok<AGROW>
end

function rows = localTopologyRows(art, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
if ~(istable(T) && height(T) > 0)
    rows(end+1, 1) = localAuditRow("topology_nodes_nonempty", art.RelativePath, ...
        "FAIL", "topology_nodes_missing_or_empty", ...
        "Topology nodes must include runtime or configured cell and UE nodes.", "0", ">0"); %#ok<AGROW>
    return;
end

nodeClass = upper(localColumnText(T, "NodeClass", strings(height(T), 1)));
cellCount = sum(nodeClass == "CELL");
ueCount = sum(nodeClass == "UE");
fail = isfinite(req.ExpectedCells) && cellCount ~= req.ExpectedCells;
rows(end+1, 1) = localAuditRow("topology_cell_count", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "topology_cell_count_mismatch"), ...
    "Topology nodes must enumerate the configured cell count.", string(cellCount), string(req.ExpectedCells)); %#ok<AGROW>
fail = isfinite(req.ExpectedUEs) && ueCount ~= req.ExpectedUEs;
rows(end+1, 1) = localAuditRow("topology_ue_count", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "topology_ue_count_mismatch"), ...
    "Topology nodes must enumerate the configured UE count.", string(ueCount), string(req.ExpectedUEs)); %#ok<AGROW>
end

function rows = localTrajectoryRows(art, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
if ~(istable(T) && height(T) > 0)
    rows(end+1, 1) = localAuditRow("trajectory_nonempty", art.RelativePath, ...
        "FAIL", "trajectory_geometry_empty", ...
        "Trajectory geometry must contain per-UE slot-backed rows.", "0", ">0"); %#ok<AGROW>
    return;
end

ue = localFirstAvailableNumeric(T, ["UeId","UEID"]);
slot = localFirstAvailableNumeric(T, "CanonicalSlot");
valid = isfinite(ue) & isfinite(slot);
if ~any(valid)
    rows(end+1, 1) = localAuditRow("trajectory_ue_slot_keys", art.RelativePath, ...
        "FAIL", "trajectory_missing_ue_or_slot_keys", ...
        "Trajectory geometry must expose UE and CanonicalSlot keys.", "missing", "present"); %#ok<AGROW>
    return;
end

ueVals = unique(ue(valid), "stable");
expectedSlots = req.ExpectedSlots;
coverageOk = true;
details = strings(0, 1);
for i = 1:numel(ueVals)
    ueMask = valid & ue == ueVals(i) & slot > double(req.WarmupSlots);
    observed = numel(unique(slot(ueMask)));
    if isfinite(expectedSlots) && expectedSlots > 0 && observed ~= max(0, expectedSlots - double(req.WarmupSlots))
        coverageOk = false;
        details(end+1, 1) = "ue" + string(ueVals(i)) + "=" + string(observed); %#ok<AGROW>
    end
end
rows(end+1, 1) = localAuditRow("trajectory_rows_cover_every_ue_slot", art.RelativePath, ...
    localStatusFromFail(~coverageOk), localFailureToken(~coverageOk, "trajectory_slot_coverage_mismatch"), ...
    strjoin(details, "; "), string(numel(ueVals)), string(req.ExpectedUEs)); %#ok<AGROW>
end

function rows = localSpeedRows(art, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(isfinite(req.ExpectedSpeedKmh) && req.ExpectedSpeedKmh > 0)
    return;
end
T = art.Table;
speed = localFirstAvailableNumeric(T, "Speed_kmh");
slot = localFirstAvailableNumeric(T, "CanonicalSlot");
mask = isfinite(speed);
if any(isfinite(slot))
    mask = mask & slot > double(req.WarmupSlots);
end
if ~any(mask)
    rows(end+1, 1) = localAuditRow("speed_rows_present", art.RelativePath, ...
        "FAIL", "speed_rows_missing", ...
        "Trajectory geometry must expose finite Speed_kmh rows.", "0", ">0"); %#ok<AGROW>
    return;
end
delta = abs(speed(mask) - double(req.ExpectedSpeedKmh));
fail = any(delta > double(req.SpeedToleranceKmh));
rows(end+1, 1) = localAuditRow("speed_matches_configured", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "speed_mismatch"), ...
    "UE speed must match the configured geometry scenario speed within tolerance.", ...
    string(sprintf('%.6f', max(delta, [], "omitnan"))), "<=" + string(req.SpeedToleranceKmh)); %#ok<AGROW>
end

function rows = localDistanceRows(art)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
distance3D = localFirstAvailableNumeric(T, "Distance3D_m");
mask = isfinite(distance3D);
fail = ~any(mask) || any(distance3D(mask) <= 0);
rows(end+1, 1) = localAuditRow("distance3d_positive", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "distance3d_nonpositive_or_missing"), ...
    "Trajectory geometry must expose positive 3D distances.", ...
    string(localMinFinite(distance3D(mask))), ">0"); %#ok<AGROW>
end

function rows = localPathlossRows(art, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~logical(req.PathlossEnabled)
    return;
end
T = art.Table;
pathloss = localFirstAvailableNumeric(T, "Pathloss_dB");
fail = ~any(isfinite(pathloss));
if ~fail
    fail = any(~isfinite(pathloss));
end
rows(end+1, 1) = localAuditRow("pathloss_finite_when_enabled", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "pathloss_missing_or_nonfinite"), ...
    "Pathloss evidence must stay finite when pathloss is enabled.", ...
    string(sum(isfinite(pathloss))), string(height(T))); %#ok<AGROW>
end

function rows = localPropagationDelayRows(trajArt, propArt)
rows = repmat(localEmptyAuditRow(), 0, 1);
trajT = trajArt.Table;
delayT = propArt.Table;
delay = localFirstAvailableNumeric(trajT, "PropagationDelay_s");
positive = isfinite(delay) & delay > 0;
fail = ~any(positive) || any(isfinite(delay) & delay <= 0);
rows(end+1, 1) = localAuditRow("trajectory_propagation_delay_positive", trajArt.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "trajectory_propagation_delay_nonpositive"), ...
    "Trajectory geometry must expose finite positive propagation delays.", ...
    string(sum(positive)), string(height(trajT))); %#ok<AGROW>

if istable(delayT) && height(delayT) > 0 && localHasColumn(delayT, "PropagationDelayReconciliationOk")
    ok = localColumnLogical(delayT, "PropagationDelayReconciliationOk", false(height(delayT), 1));
    fail = any(~ok);
    rows(end+1, 1) = localAuditRow("propagation_delay_reconciliation_pass", propArt.RelativePath, ...
        localStatusFromFail(fail), localFailureToken(fail, "propagation_delay_reconciliation_failed"), ...
        "Propagation delay reconciliation rows must pass.", ...
        string(sum(ok)), string(height(delayT))); %#ok<AGROW>
end
end

function rows = localServingAssignmentRows(art)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
fail = ~(istable(T) && height(T) > 0);
rows(end+1, 1) = localAuditRow("serving_cell_assignment_nonempty", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "serving_cell_assignment_empty"), ...
    "Serving cell assignment evidence must contain per-slot UE assignments.", ...
    string(localTableHeight(T)), ">0"); %#ok<AGROW>
end

function rows = localDopplerRows(trajArt, dopplerArt, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
trajT = trajArt.Table;
expected = localFirstAvailableNumeric(trajT, "ExpectedDopplerHz");
applied = localFirstAvailableNumeric(trajT, "AppliedDopplerHz");
err = abs(applied - expected);
mask = isfinite(expected) & isfinite(applied);
fail = ~any(mask) || any(err(mask) > double(req.DopplerToleranceHz));
rows(end+1, 1) = localAuditRow("trajectory_doppler_matches_expected", trajArt.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "trajectory_doppler_mismatch"), ...
    "Applied Doppler must match expected Doppler within tolerance.", ...
    string(localMaxFinite(err(mask))), "<=" + string(req.DopplerToleranceHz)); %#ok<AGROW>

T = dopplerArt.Table;
if istable(T) && height(T) > 0 && localHasColumn(T, "DopplerReconciliationOk")
    ok = localColumnLogical(T, "DopplerReconciliationOk", false(height(T), 1));
    fail = any(~ok);
    rows(end+1, 1) = localAuditRow("doppler_reconciliation_pass", dopplerArt.RelativePath, ...
        localStatusFromFail(fail), localFailureToken(fail, "doppler_reconciliation_failed"), ...
        "Doppler reconciliation rows must pass.", ...
        string(sum(ok)), string(height(T))); %#ok<AGROW>
end
end

function rows = localContinuityRows(art)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
if ~(istable(T) && height(T) > 0 && localHasColumn(T, "ChannelStateContinuityOk"))
    rows(end+1, 1) = localAuditRow("channel_continuity_rows_present", art.RelativePath, ...
        "FAIL", "channel_continuity_missing", ...
        "Channel continuity reconciliation must be present.", "0", ">0"); %#ok<AGROW>
    return;
end
ok = localColumnLogical(T, "ChannelStateContinuityOk", false(height(T), 1));
fail = any(~ok);
rows(end+1, 1) = localAuditRow("channel_continuity_pass", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "channel_continuity_failed"), ...
    "Channel continuity must pass or explain a discontinuity.", ...
    string(sum(ok)), string(height(T))); %#ok<AGROW>
end

function rows = localMeasuredSINRRows(art)
rows = repmat(localEmptyAuditRow(), 0, 1);
T = art.Table;
if ~(istable(T) && height(T) > 0)
    rows(end+1, 1) = localAuditRow("measured_sinr_rows_present", art.RelativePath, ...
        "FAIL", "measured_sinr_timeseries_empty", ...
        "Measured SINR timeseries must contain runtime rows for DL and/or UL.", "0", ">0"); %#ok<AGROW>
    return;
end
sinr = localFirstAvailableNumeric(T, "MeasuredSINR_dB");
finiteRows = isfinite(sinr);
fail = ~any(finiteRows);
rows(end+1, 1) = localAuditRow("measured_sinr_rows_finite", art.RelativePath, ...
    localStatusFromFail(fail), localFailureToken(fail, "measured_sinr_nonfinite_or_missing"), ...
    "Measured SINR timeseries must contain finite SINR evidence.", ...
    string(sum(finiteRows)), ">0"); %#ok<AGROW>
end

function row = localEmptyAuditRow()
row = struct( ...
    "CheckName", "", "ArtifactPath", "", "Status", "", "FailureCode", "", ...
    "Details", "", "ObservedValue", "", "ExpectedValue", "");
end

function row = localAuditRow(checkName, artifactPath, status, failureCode, details, observedValue, expectedValue)
row = localEmptyAuditRow();
row.CheckName = string(checkName);
row.ArtifactPath = string(artifactPath);
row.Status = string(status);
row.FailureCode = string(failureCode);
row.Details = string(details);
row.ObservedValue = string(observedValue);
row.ExpectedValue = string(expectedValue);
end

function status = localStatusFromFail(fail)
status = "PASS";
if logical(fail)
    status = "FAIL";
end
end

function failureCode = localFailureToken(fail, token)
failureCode = "";
if logical(fail)
    failureCode = string(token);
end
end

function reason = localArtifactReason(art)
if logical(art.NonEmpty)
    reason = "runtime_rows_present";
elseif logical(art.Present) && logical(art.Readable)
    reason = "artifact_empty";
elseif logical(art.Present)
    reason = "artifact_unreadable";
else
    reason = "artifact_missing";
end
end

function heightValue = localTableHeight(T)
if istable(T)
    heightValue = height(T);
else
    heightValue = 0;
end
end

function value = localRunClassFromTable(T)
value = "";
if istable(T) && height(T) > 0 && localHasColumn(T, "RunClass")
    value = string(T.RunClass(1));
end
end

function art = localReadTableArtifact(pathValue)
art = struct();
art.Path = string(pathValue);
art.RelativePath = string(localRelativePath(pathValue, fileparts(fileparts(fileparts(pathValue)))));
art.Present = exist(pathValue, "file") == 2;
art.Readable = false;
art.NonEmpty = false;
art.Table = table();
if ~art.Present
    return;
end
try
    art.Table = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
    art.Readable = true;
    art.NonEmpty = height(art.Table) > 0;
catch
    art.Table = table();
end
end

function info = localReadOptionalJSON(pathValue)
info = struct("Present", false, "Readable", false, "Data", struct());
if exist(pathValue, "file") ~= 2
    return;
end
info.Present = true;
try
    info.Data = sixgr.util.jsonRead(pathValue);
    info.Readable = true;
catch
    info.Data = struct();
end
end

function T = localReadOptionalTable(pathValue)
if exist(pathValue, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
while true
    [parentPath, leaf] = fileparts(rootRunFolder);
    leaf = lower(string(leaf));
    if any(leaf == ["geometry", "mobility", "reports", "air_interface", "meta"])
        rootRunFolder = parentPath;
    else
        break;
    end
end
end

function rel = localRelativePath(pathValue, rootRunFolder)
pathValue = string(pathValue);
rootRunFolder = string(rootRunFolder);
if strlength(rootRunFolder) == 0
    rel = pathValue;
    return;
end
prefix = rootRunFolder + filesep;
if startsWith(pathValue, prefix, "IgnoreCase", true)
    rel = extractAfter(pathValue, strlength(prefix));
else
    rel = pathValue;
end
end

function text = localGetText(cfg, pathValue, defaultValue)
value = localGetValue(cfg, pathValue, defaultValue);
if isstring(value) || ischar(value)
    text = string(value);
elseif isnumeric(value) || islogical(value)
    text = string(value);
else
    text = string(defaultValue);
end
text = strtrim(text);
if strlength(text) == 0
    text = string(defaultValue);
end
end

function value = localGetDouble(cfg, pathValue, defaultValue)
raw = localGetValue(cfg, pathValue, defaultValue);
if isnumeric(raw) || islogical(raw)
    raw = double(raw);
    if isscalar(raw) && isfinite(raw)
        value = double(raw);
        return;
    end
elseif ischar(raw) || isstring(raw)
    numericValue = str2double(string(raw));
    if isfinite(numericValue)
        value = double(numericValue);
        return;
    end
end
value = double(defaultValue);
end

function tf = localGetLogical(cfg, pathValue, defaultValue)
raw = localGetValue(cfg, pathValue, defaultValue);
if islogical(raw)
    tf = logical(raw);
elseif isnumeric(raw)
    tf = isfinite(raw) && raw ~= 0;
else
    token = lower(strtrim(string(raw)));
    tf = any(token == ["true","1","yes","on"]);
end
end

function value = localGetValue(cfg, pathValue, defaultValue)
value = defaultValue;
try
    value = sixgr.util.structGet(cfg, pathValue, defaultValue);
catch
    value = defaultValue;
end
end

function value = localFirstFinite(values, defaultValue)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = defaultValue;
else
    value = values(idx);
end
end

function tf = localFirstLogical(values, defaultValue)
tf = logical(defaultValue);
values = logical(values(:));
if ~isempty(values)
    tf = logical(values(1));
end
end

function text = localFirstText(values)
values = string(values(:));
values = strtrim(values);
idx = find(strlength(values) > 0, 1, "first");
if isempty(idx)
    text = "";
else
    text = values(idx);
end
end

function values = localFirstAvailableNumeric(T, names)
for name = reshape(string(names), 1, [])
    if localHasColumn(T, name)
        values = localColumnNumeric(T, name, NaN(height(T), 1));
        return;
    end
end
values = NaN(height(T), 1);
end

function values = localColumnNumeric(T, name, fallback)
if ~(istable(T) && height(T) > 0)
    values = zeros(0, 1);
    return;
end
if localHasColumn(T, name)
    raw = T.(char(name));
    if isnumeric(raw) || islogical(raw)
        values = double(raw);
    else
        values = str2double(string(raw));
    end
    values = reshape(values, [], 1);
else
    values = repmat(double(fallback(1)), height(T), 1);
end
end

function values = localColumnText(T, name, fallback)
if ~(istable(T) && height(T) > 0)
    values = strings(0, 1);
    return;
end
if localHasColumn(T, name)
    values = string(T.(char(name)));
    values = reshape(values, [], 1);
else
    values = reshape(string(fallback), [], 1);
    if isscalar(values)
        values = repmat(values, height(T), 1);
    end
end
end

function values = localColumnLogical(T, name, fallback)
if ~(istable(T) && height(T) > 0)
    values = false(0, 1);
    return;
end
if localHasColumn(T, name)
    raw = T.(char(name));
    if islogical(raw)
        values = logical(raw);
    elseif isnumeric(raw)
        values = raw ~= 0;
    else
        token = lower(strtrim(string(raw)));
        values = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok";
    end
else
    values = logical(fallback);
end
values = reshape(values, [], 1);
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function value = localMinFinite(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = min(values);
end
end

function value = localMaxFinite(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
