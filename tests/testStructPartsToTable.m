function ok = testStructPartsToTable()
%TESTSTRUCTPARTSTOTABLE Columnar assembly preserves order and exact values.

template = struct("RunId", "", "TrialId", NaN, ...
    "Metric", NaN, "Selected", false, "Status", "");
parts = cell(1000, 1);
expectedRows = 0;
for partIndex = 1:numel(parts)
    count = mod(partIndex, 7) + 1;
    rows = repmat(template, count, 1);
    for rowIndex = 1:count
        sequence = expectedRows + rowIndex;
        rows(rowIndex) = struct("RunId", "run-a", ...
            "TrialId", double(partIndex), "Metric", double(sequence) / 10, ...
            "Selected", mod(sequence, 2) == 0, "Status", "measured");
    end
    parts{partIndex} = rows;
    expectedRows = expectedRows + count;
end

actual = sixgr.util.structPartsToTable(parts, template);
reference = struct2table(vertcat(parts{:}), "AsArray", true);
assert(height(actual) == expectedRows && isequal(actual, reference), ...
    "Columnar struct-part assembly changed row order, schema, type, or value.");

empty = sixgr.util.structPartsToTable(cell(0, 1), template);
assert(isempty(empty) && isequal(string(empty.Properties.VariableNames), ...
    string(fieldnames(template)).'), ...
    "Empty columnar assembly must retain the canonical schema.");

bad = parts(1);
bad{1} = rmfield(bad{1}, "Metric");
localAssertIdentifier(@()sixgr.util.structPartsToTable(bad, template), ...
    "sixgr:util:structPartsToTable:SchemaMismatch");
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
