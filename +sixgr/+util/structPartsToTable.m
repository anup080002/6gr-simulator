function output = structPartsToTable(parts, template)
%STRUCTPARTSTOTABLE Build a columnar table without a giant struct vertcat.

if ~iscell(parts) || ~(isstruct(template) && isscalar(template))
    error("sixgr:util:structPartsToTable:InvalidInput", ...
        "Parts must be a cell array and template must be a scalar struct.");
end
parts = parts(:);
parts = parts(~cellfun(@isempty, parts));
fieldNames = string(fieldnames(template)).';
if isempty(parts)
    output = struct2table(repmat(template, 0, 1), "AsArray", true);
    return;
end

counts = cellfun(@numel, parts);
totalRows = sum(double(counts));
columns = cell(1, numel(fieldNames));
for fieldIndex = 1:numel(fieldNames)
    prototype = template.(char(fieldNames(fieldIndex)));
    columns{fieldIndex} = localAllocateColumn(prototype, totalRows);
end

cursor = 1;
templateFields = fieldnames(template);
for partIndex = 1:numel(parts)
    part = parts{partIndex};
    if ~isstruct(part) || ~isequal(fieldnames(part), templateFields)
        error("sixgr:util:structPartsToTable:SchemaMismatch", ...
            "Struct part %d does not match the canonical template schema.", partIndex);
    end
    part = part(:);
    rowCount = numel(part);
    rowRange = cursor:(cursor + rowCount - 1);
    for fieldIndex = 1:numel(fieldNames)
        fieldName = char(fieldNames(fieldIndex));
        prototype = template.(fieldName);
        columns{fieldIndex}(rowRange, 1) = ...
            localExtractColumn(part, fieldName, prototype, rowCount);
    end
    cursor = cursor + rowCount;
end
output = table(columns{:}, 'VariableNames', cellstr(fieldNames));
end

function column = localAllocateColumn(prototype, rowCount)
if isstring(prototype) || ischar(prototype)
    column = strings(rowCount, 1);
elseif islogical(prototype)
    column = false(rowCount, 1);
elseif isnumeric(prototype)
    column = nan(rowCount, 1, "like", double(prototype));
else
    column = cell(rowCount, 1);
end
end

function values = localExtractColumn(part, fieldName, prototype, rowCount)
if isstring(prototype) || ischar(prototype)
    values = reshape(string({part.(fieldName)}), [], 1);
elseif islogical(prototype)
    values = reshape(logical([part.(fieldName)]), [], 1);
elseif isnumeric(prototype)
    values = reshape(double([part.(fieldName)]), [], 1);
else
    values = reshape({part.(fieldName)}, [], 1);
end
if numel(values) ~= rowCount
    error("sixgr:util:structPartsToTable:NonScalarField", ...
        "Field %s must be scalar in every struct row.", fieldName);
end
end
