function T = appendMeasuredPHYEvidenceColumns(T, evidenceCells)
%APPENDMEASUREDPHYEVIDENCECOLUMNS Add measured PHY evidence columns to a table.

if nargin < 1 || ~istable(T)
    T = table();
end
nRows = height(T);
if nargin < 2
    evidenceCells = cell(nRows, 1);
elseif isstruct(evidenceCells)
    evidenceCells = num2cell(evidenceCells(:));
elseif ~iscell(evidenceCells)
    evidenceCells = cell(nRows, 1);
else
    evidenceCells = evidenceCells(:);
end

defaultRow = sixgr.link.emptyMeasuredPHYEvidenceRow();
rows = repmat(defaultRow, nRows, 1);
hasEvidence = false;
for i = 1:min(nRows, numel(evidenceCells))
    ev = evidenceCells{i};
    if ~(isstruct(ev) && ~isempty(fieldnames(ev)))
        continue;
    end
    hasEvidence = true;
    names = fieldnames(defaultRow);
    for fi = 1:numel(names)
        name = names{fi};
        if isfield(ev, name)
            rows(i).(name) = localCoerceEvidenceValue(defaultRow.(name), ev.(name));
        end
    end
end

evidenceT = struct2table(rows);
names = evidenceT.Properties.VariableNames;
for i = 1:numel(names)
    name = names{i};
    if hasEvidence || ~ismember(name, T.Properties.VariableNames)
        T.(name) = evidenceT.(name);
    end
end
end

function value = localCoerceEvidenceValue(defaultValue, raw)
if isstring(defaultValue) || ischar(defaultValue)
    value = "";
    if isempty(raw)
        return;
    end
    try
        raw = string(raw);
    catch
        return;
    end
    raw = raw(:);
    if isempty(raw)
        return;
    end
    if numel(raw) == 1
        value = raw(1);
    else
        value = strjoin(raw.', "|");
    end
    return;
end

value = NaN;
if isempty(raw)
    return;
end
try
    raw = double(raw);
catch
    return;
end
raw = raw(:);
if isempty(raw)
    return;
end
value = raw(1);
end
