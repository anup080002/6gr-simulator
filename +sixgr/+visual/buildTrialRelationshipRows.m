function T = buildTrialRelationshipRows(sourceT, x, y, direction, sourceArtifact)
%BUILDTRIALRELATIONSHIPROWS Preserve event identity in relationship plot data.
%
% Coincident BER/BLER or SINR samples are valid repeated measurements.  They
% must retain source-row/event identity instead of becoming indistinguishable
% exact duplicate CSV rows.

if ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptyTable();
    return;
end
x = double(x(:));
y = double(y(:));
n = min([height(sourceT), numel(x), numel(y)]);
if n == 0
    T = localEmptyTable();
    return;
end
x = x(1:n);
y = y(1:n);
mask = isfinite(x) & isfinite(y);
sourceRow = (1:n).';
sourceRow = sourceRow(mask);
trialId = localTrialIdentity(sourceT(1:n, :), direction);
ueId = localNumericIdentity(sourceT(1:n, :), ["UEID", "UEIndex", "UE"]);
snrDb = localNumericIdentity(sourceT(1:n, :), ["SNR_dB", "AppliedSNR_dB", "ConfiguredSNR_dB"]);
frame = localNumericIdentity(sourceT(1:n, :), "Frame");
slot = localNumericIdentity(sourceT(1:n, :), "Slot");

T = table( ...
    repmat(string(direction), nnz(mask), 1), ...
    sourceRow, trialId(mask), ueId(mask), snrDb(mask), frame(mask), slot(mask), ...
    x(mask), y(mask), repmat(string(sourceArtifact), nnz(mask), 1), ...
    'VariableNames', ["Direction", "SourceRow", "TrialID", "UEID", ...
    "SNR_dB", "Frame", "Slot", "XValue", "YValue", "SourceArtifact"]);
end

function T = localEmptyTable()
T = table('Size', [0 10], ...
    'VariableTypes', {'string','double','string','double','double','double','double','double','double','string'}, ...
    'VariableNames', ["Direction", "SourceRow", "TrialID", "UEID", ...
    "SNR_dB", "Frame", "Slot", "XValue", "YValue", "SourceArtifact"]);
end

function values = localTrialIdentity(T, direction)
values = strings(height(T), 1);
for name = ["TrialID", "TransportBlockId", "TransportBlockID", "TBID", "BlockID"]
    match = strcmpi(string(T.Properties.VariableNames), name);
    if ~any(match)
        continue;
    end
    candidate = string(T{:, find(match, 1, "first")});
    candidate = reshape(candidate, [], 1);
    valid = ~ismissing(candidate) & strlength(strtrim(candidate)) > 0 & lower(strtrim(candidate)) ~= "nan";
    values(valid) = candidate(valid);
    if all(strlength(values) > 0)
        return;
    end
end
missing = strlength(values) == 0;
row = (1:height(T)).';
values(missing) = lower(string(direction)) + "_source_row_" + string(row(missing));
end

function values = localNumericIdentity(T, names)
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
