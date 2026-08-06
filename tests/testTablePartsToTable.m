function ok = testTablePartsToTable()
%TESTTABLEPARTSTOTABLE Columnar table assembly preserves exact evidence.

template = struct("RunId", "", "TrialId", NaN, ...
    "Metric", NaN, "Selected", false, "Status", "");
parts = cell(1000, 1);
for partIndex = 1:numel(parts)
    count = mod(partIndex, 7) + 1;
    rows = repmat(template, count, 1);
    for rowIndex = 1:count
        sequence = (partIndex - 1) * 10 + rowIndex;
        rows(rowIndex) = struct("RunId", "run-a", ...
            "TrialId", double(partIndex), "Metric", double(sequence) / 10, ...
            "Selected", mod(sequence, 2) == 0, "Status", "measured");
    end
    parts{partIndex} = struct2table(rows, "AsArray", true);
end

actual = sixgr.util.tablePartsToTable(parts, template);
reference = vertcat(parts{:});
assert(isequal(actual, reference), ...
    "Columnar table-part assembly changed row order, schema, type, or value.");

empty = sixgr.util.tablePartsToTable(cell(0, 1), template);
assert(isempty(empty) && isequal(string(empty.Properties.VariableNames), ...
    string(fieldnames(template)).'), ...
    "Empty table-part assembly must retain the canonical schema.");

bad = parts(1);
bad{1}.Properties.VariableNames{1} = 'WrongName';
localAssertIdentifier(@()sixgr.util.tablePartsToTable(bad, template), ...
    "sixgr:util:tablePartsToTable:SchemaMismatch");
ok = true;
end

function localAssertIdentifier(fcn, expected)
caught = false;
try
    fcn();
catch ME
    caught = true;
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, observed %s.", expected, ME.identifier);
end
assert(caught, "Expected typed error %s.", expected);
end
