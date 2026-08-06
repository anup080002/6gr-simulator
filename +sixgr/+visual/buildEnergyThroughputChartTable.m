function T = buildEnergyThroughputChartTable(powerT, sourceArtifact)
%BUILDENERGYTHROUGHPUTCHARTTABLE Build row-aligned, traceable energy plot data.
%
% The source row is an explicit lineage key.  Numeric columns are selected
% without independently dropping NaNs, which prevents cross-row pairing.

if nargin < 2 || strlength(string(sourceArtifact)) == 0
    sourceArtifact = "rf/csv/power_energy_table.csv";
end
if ~(istable(powerT) && ~isempty(powerT))
    T = localEmptyTable();
    return;
end

bits = localNumericColumn(powerT, ["useful_bits", "successful_bits"]);
energy = localNumericColumn(powerT, ["cumulative_energy_J", "energy_j"]);
mask = isfinite(bits) & bits > 0 & isfinite(energy) & energy >= 0;
sourceRow = (1:height(powerT)).';
entityType = localTextColumn(powerT, ["entity_type", "EntityType", "Entity"]);
entityId = localNumericColumn(powerT, ["entity_id", "EntityID", "UEID", "CellID"]);
direction = localTextColumn(powerT, ["direction", "Direction"]);
timestampMs = localNumericColumn(powerT, ["timestamp_sim_ms", "TimestampSim_ms"]);

T = table(sourceRow(mask), entityType(mask), entityId(mask), direction(mask), ...
    timestampMs(mask), bits(mask), energy(mask), ...
    repmat(string(sourceArtifact), nnz(mask), 1), ...
    repmat("runtime_row_aligned_pairs", nnz(mask), 1), ...
    repmat("real_lls_evidence", nnz(mask), 1), ...
    'VariableNames', ["SourceRow", "EntityType", "EntityID", "Direction", ...
    "TimestampSim_ms", "successful_bits", "energy_j", "source_artifact_ref", ...
    "curve_construction", "truth_status"]);
end

function T = localEmptyTable()
T = table('Size', [0 10], ...
    'VariableTypes', {'double','string','double','string','double','double','double','string','string','string'}, ...
    'VariableNames', ["SourceRow", "EntityType", "EntityID", "Direction", ...
    "TimestampSim_ms", "successful_bits", "energy_j", "source_artifact_ref", ...
    "curve_construction", "truth_status"]);
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

function values = localTextColumn(T, names)
values = strings(height(T), 1);
for name = string(names)
    match = strcmpi(string(T.Properties.VariableNames), name);
    if any(match)
        values = string(T{:, find(match, 1, "first")});
        values = reshape(values, [], 1);
        return;
    end
end
end
