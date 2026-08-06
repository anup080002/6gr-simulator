function T = aggregateBeamPrecoderEvidence(beamPrecoderTable)
%AGGREGATEBEAMPRECODEREVIDENCE Aggregate runtime beam rows by physical link identity.
%
% Missing numeric identity values are encoded explicitly in the grouping key.
% MATLAB missing/NaN values must not create one group per source row because
% that turns repeated observations for the same UE into duplicate summaries.

if ~(istable(beamPrecoderTable) && ~isempty(beamPrecoderTable))
    T = table();
    return;
end

direction = upper(strtrim(localTextColumn(beamPrecoderTable, "direction")));
direction(ismissing(direction) | strlength(direction) == 0) = "NOT_AVAILABLE";
cellId = localNumericColumn(beamPrecoderTable, ["cell_id", "CellID", "cell", "ServingCell"]);
ueId = localNumericColumn(beamPrecoderTable, ["ue_id", "UEID", "UE", "ue"]);
keys = direction + "|cell=" + localNumericKeyToken(cellId) + ...
    "|ue=" + localNumericKeyToken(ueId);
[uniqueKeys, ~, keyIndex] = unique(keys, "stable");

rows = repmat(localEmptyRow(), numel(uniqueKeys), 1);
for index = 1:numel(uniqueKeys)
    mask = keyIndex == index;
    subset = beamPrecoderTable(mask, :);
    beamTruth = localTextColumn(subset, "applied_beam_truth_classification");
    pmiTruth = localTextColumn(subset, "applied_precoder_pmi_truth_classification");
    hit = localNumericColumn(subset, "beam_hit");
    subsetDirection = upper(strtrim(localTextColumn(subset, "direction")));
    subsetCell = localNumericColumn(subset, ["cell_id", "CellID", "cell", "ServingCell"]);
    subsetUE = localNumericColumn(subset, ["ue_id", "UEID", "UE", "ue"]);

    rows(index).direction = subsetDirection(1);
    rows(index).cell_id = subsetCell(1);
    rows(index).ue_id = subsetUE(1);
    rows(index).trial_row_count = height(subset);
    rows(index).beamforming_applied_count = sum(localLogicalColumn(subset, "beamforming_applied"));
    rows(index).runtime_applied_beam_rows = sum(beamTruth == "applied_runtime_value");
    rows(index).runtime_applied_pmi_rows = sum(pmiTruth == "applied_runtime_value");
    rows(index).beam_hit_rate = localFiniteMean(hit);
    rows(index).mean_precoding_ports = localFiniteMean(localNumericColumn(subset, ...
        ["precoding_num_ports", "PrecodingNumPorts"]));
    rows(index).mean_precoding_layers = localFiniteMean(localNumericColumn(subset, ...
        ["precoding_num_layers", "PrecodingNumLayers", "num_layers", "NumLayers"]));
    rows(index).analytics_value_source = "beamforming/csv/beam_precoder_table.csv";
end
T = struct2table(rows, "AsArray", true);
end

function row = localEmptyRow()
row = struct("direction", "", "cell_id", NaN, "ue_id", NaN, ...
    "trial_row_count", NaN, "beamforming_applied_count", NaN, ...
    "runtime_applied_beam_rows", NaN, "runtime_applied_pmi_rows", NaN, ...
    "beam_hit_rate", NaN, "mean_precoding_ports", NaN, ...
    "mean_precoding_layers", NaN, "analytics_value_source", "");
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

function values = localLogicalColumn(T, name)
values = false(height(T), 1);
match = strcmpi(string(T.Properties.VariableNames), string(name));
if ~any(match)
    return;
end
raw = T{:, find(match, 1, "first")};
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    values = ismember(lower(strtrim(string(raw(:)))), ["true", "1", "yes", "pass"]);
end
end

function token = localNumericKeyToken(values)
values = double(values(:));
token = repmat("NOT_AVAILABLE", size(values));
finite = isfinite(values);
token(finite) = string(compose("%.17g", values(finite)));
end

function value = localFiniteMean(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end
