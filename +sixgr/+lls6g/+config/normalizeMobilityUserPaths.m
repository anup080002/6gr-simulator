function paths = normalizeMobilityUserPaths(raw)
%NORMALIZEMOBILITYUSERPATHS Validate and normalize configured UE mobility traces.

if isempty(raw)
    paths = struct([]);
    return;
end
if istable(raw)
    raw = table2struct(raw);
end
if ~isstruct(raw)
    error("sixgr:lls6g:config:InvalidMobilityUserPaths", ...
        "mobility.user_paths must resolve to a struct array.");
end

paths = repmat(struct( ...
    "ue_id", NaN, ...
    "label", "", ...
    "speed_kmh", NaN, ...
    "initial_position_m", [NaN NaN NaN], ...
    "initial_heading_deg", NaN, ...
    "waypoints", struct([]), ...
    "loop_mode", "hold"), 0, 1);

for i = 1:numel(raw)
    entry = raw(i);
    ueId = double(sixgr.util.structGet(entry, "ue_id", NaN));
    if ~(isfinite(ueId) && ueId >= 1 && abs(ueId - round(ueId)) < 1e-9)
        error("sixgr:lls6g:config:InvalidMobilityUserPathUEId", ...
            "mobility.user_paths(%d).ue_id must be a positive integer.", i);
    end
    initialPos = localNormalizeMobilityPosition( ...
        sixgr.util.structGet(entry, "initial_position_m", []), ...
        sprintf("mobility.user_paths(%d).initial_position_m", i));
    loopMode = lower(strtrim(char(string(sixgr.util.structGet(entry, "loop_mode", "hold")))));
    if ~any(strcmp(loopMode, {'hold', 'ping_pong', 'wrap'}))
        error("sixgr:lls6g:config:InvalidMobilityLoopMode", ...
            "mobility.user_paths(%d).loop_mode must be one of hold, ping_pong, or wrap.", i);
    end
    defaultLabel = sprintf("ue_%d_path", round(double(ueId)));
    paths(end+1, 1) = struct( ... %#ok<AGROW>
        "ue_id", round(double(ueId)), ...
        "label", char(string(sixgr.util.structGet(entry, "label", defaultLabel))), ...
        "speed_kmh", localNumericScalarOrNaN(sixgr.util.structGet(entry, "speed_kmh", NaN)), ...
        "initial_position_m", initialPos, ...
        "initial_heading_deg", localNumericScalarOrNaN(sixgr.util.structGet(entry, "initial_heading_deg", NaN)), ...
        "waypoints", localNormalizeMobilityWaypoints( ...
            sixgr.util.structGet(entry, "waypoints_m", struct([])), ...
            sprintf("mobility.user_paths(%d).waypoints_m", i)), ...
        "loop_mode", loopMode);
end

if numel(unique([paths.ue_id])) ~= numel(paths)
    error("sixgr:lls6g:config:DuplicateMobilityUserPaths", ...
        "mobility.user_paths must not repeat ue_id values.");
end

[~, order] = sort([paths.ue_id]);
paths = paths(order);
end

function position = localNormalizeMobilityPosition(raw, fieldName)
raw = double(raw);
raw = raw(:).';
if ~(numel(raw) == 2 || numel(raw) == 3) || any(~isfinite(raw(1:2)))
    error("sixgr:lls6g:config:InvalidMobilityPosition", ...
        "%s must contain two or three finite numeric coordinates in meters.", fieldName);
end
position = [raw(1:2) NaN];
if numel(raw) >= 3 && isfinite(raw(3))
    position(3) = raw(3);
end
end

function waypoints = localNormalizeMobilityWaypoints(raw, fieldName)
if isempty(raw)
    waypoints = struct([]);
    return;
end
if istable(raw)
    raw = table2struct(raw);
end
if ~isstruct(raw)
    error("sixgr:lls6g:config:InvalidMobilityWaypoints", ...
        "%s must resolve to a struct array.", fieldName);
end

waypoints = repmat(struct("position_m", [NaN NaN NaN], "hold_time_s", 0), 0, 1);
for i = 1:numel(raw)
    entry = raw(i);
    waypoints(end+1, 1) = struct( ... %#ok<AGROW>
        "position_m", localNormalizeMobilityPosition( ...
            sixgr.util.structGet(entry, "position_m", []), ...
            sprintf("%s(%d).position_m", fieldName, i)), ...
        "hold_time_s", max(0, double(sixgr.util.structGet(entry, "hold_time_s", 0))));
end
end

function value = localNumericScalarOrNaN(raw)
if isempty(raw) || ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw)
    value = NaN;
    return;
end
value = double(raw);
if ~isfinite(value)
    value = NaN;
end
end
