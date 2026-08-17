function T = buildMobilityKPIReconciliation(cfg, mobilityArtifacts, runFolder)
%BUILDMOBILITYKPIRECONCILIATION Reconcile configured motion with runtime trajectory evidence.
%   The reconciliation is fail-closed: a row passes only when the complete
%   runtime trajectory is present and its measured travelled distance
%   agrees with the configured speed, slot count, and slot duration.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
if nargin < 3 || strlength(strtrim(string(runFolder))) == 0
    runFolder = pwd;
end

resolution = sixgr.util.structGet(mobilityArtifacts, "Resolution", table());
if ~(istable(resolution) && height(resolution) > 0)
    resolution = localReadTable(fullfile(char(string(runFolder)), ...
        "mobility", "csv", "trajectory_resolution.csv"));
end

slotMs = localNumber(cfg, ["frame_timing.slot_duration_ms", ...
    "numerology.slot_duration_ms"], 0.5);
slots = localNumber(cfg, ["run.total_slots", "run_control.total_slots", ...
    "simulation.n_slots"], NaN);
speedKmh = localNumber(cfg, [ ...
    "deployment_topology.mobility.speed_kmh", ...
    "topology.mobility.speed_kmh", ...
    "mobility.speed_kmh", ...
    "mobility.ue_speed_kmh", ...
    "channels.mobility_kmph"], NaN);

actual = localFirstFinite(localFiniteColumn(resolution, "ActualDistanceTravelled_m"));
required = localFirstFinite(localFiniteColumn(resolution, "RequiredTraversalSlots"));
configuredSlots = localFirstFinite(localFiniteColumn(resolution, "ConfiguredSlots"));
if isfinite(configuredSlots)
    slots = configuredSlots;
end
full = localFirstLogicalColumn(resolution, "FullTrajectoryExecutedOk", false);

expected = NaN;
if isfinite(speedKmh) && isfinite(slots)
    expected = (speedKmh / 3.6) * double(slots) * (slotMs / 1e3);
end
if isfinite(required) && isfinite(speedKmh)
    expected = (speedKmh / 3.6) * double(required) * (slotMs / 1e3);
end

mismatch = abs(expected - actual);
ok = full && isfinite(mismatch) && mismatch <= 0.1;
T = table(logical(full), slots, required, speedKmh, expected, actual, mismatch, ok, ...
    "mobility_runtime_trajectory_resolution", ...
    'VariableNames', {'FullTrajectoryExecuted','ConfiguredSlots','RequiredTraversalSlots', ...
    'ConfiguredSpeed_kmh','ExpectedDistance_m','ActualDistance_m','DistanceMismatch_m', ...
    'MobilityKpiReconciliationOk','EvidenceSource'});
end

function T = localReadTable(path)
T = table();
if exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function vals = localFiniteColumn(T, name)
vals = zeros(0, 1);
if ~(istable(T) && height(T) > 0 && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(string(name)));
if isnumeric(raw) || islogical(raw)
    vals = double(raw(:));
else
    vals = str2double(string(raw(:)));
end
vals = vals(isfinite(vals));
end

function value = localFirstFinite(vals)
vals = double(vals(:));
idx = find(isfinite(vals), 1, "first");
if isempty(idx)
    value = NaN;
else
    value = vals(idx);
end
end

function tf = localFirstLogicalColumn(T, name, defaultValue)
tf = logical(defaultValue);
if ~(istable(T) && height(T) > 0 && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(string(name)));
if islogical(raw)
    values = logical(raw(:));
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = token == "1" | token == "true" | token == "yes" | ...
        token == "pass" | token == "passed" | token == "ok";
end
if ~isempty(values)
    tf = logical(values(1));
end
end

function value = localNumber(cfg, paths, defaultValue)
value = defaultValue;
for path = string(paths)
    raw = sixgr.util.structGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        number = str2double(string(raw));
        if isscalar(number) && isfinite(number)
            value = number;
            return;
        end
    end
end
end
