function output = tablePartsToTable(parts, template)
%TABLEPARTSTOTABLE Concatenate schema-identical tables column by column.

if ~iscell(parts) || ~(isstruct(template) && isscalar(template))
    error("sixgr:util:tablePartsToTable:InvalidInput", ...
        "Parts must be a cell array and template must be a scalar struct.");
end
parts = parts(:);
parts = parts(~cellfun(@isempty, parts));
fieldNames = string(fieldnames(template)).';
if isempty(parts)
    output = struct2table(repmat(template, 0, 1), "AsArray", true);
    return;
end

counts = zeros(numel(parts), 1);
for partIndex = 1:numel(parts)
    part = parts{partIndex};
    if ~istable(part) || ~isequal(string(part.Properties.VariableNames), fieldNames)
        error("sixgr:util:tablePartsToTable:SchemaMismatch", ...
            "Table part %d does not match the canonical template schema.", partIndex);
    end
    counts(partIndex) = height(part);
end
totalRows = sum(counts);
columns = cell(1, numel(fieldNames));
for fieldIndex = 1:numel(fieldNames)
    prototype = template.(char(fieldNames(fieldIndex)));
    columns{fieldIndex} = localAllocateColumn(prototype, totalRows);
end

cursor = 1;
for partIndex = 1:numel(parts)
    part = parts{partIndex};
    rowCount = counts(partIndex);
    if rowCount == 0
        continue;
    end
    rowRange = cursor:(cursor + rowCount - 1);
    for fieldIndex = 1:numel(fieldNames)
        fieldName = char(fieldNames(fieldIndex));
        values = part.(fieldName);
        if size(values, 1) ~= rowCount || size(values, 2) ~= 1
            error("sixgr:util:tablePartsToTable:NonScalarVariable", ...
                "Variable %s in table part %d must contain one scalar value per row.", ...
                fieldName, partIndex);
        end
        columns{fieldIndex}(rowRange, 1) = values;
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
    column = nan(rowCount, 1);
else
    error("sixgr:util:tablePartsToTable:UnsupportedVariableType", ...
        "Unsupported canonical table variable type %s.", class(prototype));
end
end
