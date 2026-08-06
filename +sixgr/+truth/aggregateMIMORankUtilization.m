function T = aggregateMIMORankUtilization(beamPrecoderTable)
%AGGREGATEMIMORANKUTILIZATION Aggregate rank use by direction/cell/rank.
%
% Missing CellID is an explicit grouping value.  It must not cause one
% duplicate aggregate per source row.

if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end
rankValue = localNumericColumn(beamPrecoderTable, ...
    ["precoding_num_layers", "PrecodingNumLayers", "num_layers", "NumLayers"]);
direction = upper(strtrim(localTextColumn(beamPrecoderTable, "direction")));
direction(ismissing(direction) | strlength(direction) == 0) = "NOT_AVAILABLE";
cellId = localNumericColumn(beamPrecoderTable, ...
    ["cell_id", "CellID", "cell", "ServingCell"]);
valid = isfinite(rankValue);
if ~any(valid)
    T = table();
    return;
end
keys = direction + "|cell=" + localNumericKeyToken(cellId) + ...
    "|rank=" + localNumericKeyToken(rankValue);
directionCellKeys = direction + "|cell=" + localNumericKeyToken(cellId);
[uniqueKeys, ~, keyIndex] = unique(keys(valid), "stable");
validRows = find(valid);

rows = repmat(localEmptyRow(), numel(uniqueKeys), 1);
for index = 1:numel(uniqueKeys)
    memberRows = validRows(keyIndex == index);
    first = memberRows(1);
    denominator = nnz(directionCellKeys == directionCellKeys(first) & isfinite(rankValue));
    rows(index).direction = direction(first);
    rows(index).cell_id = cellId(first);
    rows(index).rank_or_layer_count = rankValue(first);
    rows(index).trial_row_count = numel(memberRows);
    rows(index).utilization_fraction = numel(memberRows) / max(denominator, 1);
    rows(index).source_artifact_ref = "beamforming/csv/beam_precoder_table.csv";
end
T = struct2table(rows, "AsArray", true);
end

function row = localEmptyRow()
row = struct("direction", "", "cell_id", NaN, "rank_or_layer_count", NaN, ...
    "trial_row_count", NaN, "utilization_fraction", NaN, ...
    "source_artifact_ref", "");
end

function values = localTextColumn(T, name)
values = strings(height(T), 1);
match = strcmpi(string(T.Properties.VariableNames), string(name));
if any(match)
    values = string(T{:, find(match, 1, "first")});
    values = reshape(values, [], 1);
end
end

function values = localNumericColumn(T, names)
values = nan(height(T), 1);
for name = string(names)
    match = strcmpi(string(T.Properties.VariableNames), name);
    if ~any(match)
        continue;
    end
    raw = T{:, find(match, 1, "first")};
    try
        candidate = double(raw);
    catch
        candidate = str2double(string(raw));
    end
    candidate = reshape(candidate, [], 1);
    if numel(candidate) == height(T)
        values = candidate;
        return;
    end
end
end

function token = localNumericKeyToken(values)
values = double(values(:));
token = repmat("NOT_AVAILABLE", size(values));
finite = isfinite(values);
token(finite) = string(compose("%.17g", values(finite)));
end
