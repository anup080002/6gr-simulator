function ok = testCSVEmptySchemaPreservation()
%TESTCSVEMPTYSCHEMAPRESERVATION Empty canonical CSVs retain their headers.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
pathValue = fullfile(root, "evaluated_empty.csv");
expected = table(strings(0,1), zeros(0,1), false(0,1), ...
    'VariableNames', {'Status','MeasuredSINR_dB','Pass'});

sixgr.util.csvWriteTable(pathValue, expected);
raw = string(fileread(pathValue));
assert(contains(raw, "Status") && contains(raw, "MeasuredSINR_dB") && ...
    contains(raw, "Pass"), ...
    "A zero-row canonical CSV must retain a decodable schema header.");
actual = readtable(pathValue, "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(height(actual) == 0 && isequal(string(actual.Properties.VariableNames), ...
    string(expected.Properties.VariableNames)), ...
    "The persisted empty CSV schema must round-trip exactly.");

ok = true;
fprintf("PASS testCSVEmptySchemaPreservation: typed empty CSV header retained.\n");
end
