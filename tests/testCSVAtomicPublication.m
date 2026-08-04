function ok = testCSVAtomicPublication()
%TESTCSVATOMICPUBLICATION CSV replacement is complete and leaves no temp file.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
path = fullfile(root, "canonical.csv");

first = table((1:3).', ["a";"b";"c"], ...
    'VariableNames', {'Trial','Label'});
second = table((4:8).', ["d";"e";"f";"g";"h"], ...
    'VariableNames', {'Trial','Label'});
sixgr.util.csvWriteTable(path, first);
sixgr.util.csvWriteTable(path, second);

actual = readtable(path, "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(isequal(actual, second), ...
    "Atomic CSV replacement must publish the complete replacement table.");
temps = dir(fullfile(root, "*.csv"));
assert(numel(temps) == 1 && string(temps(1).name) == "canonical.csv", ...
    "Successful publication must not leave same-directory temporary CSVs.");
ok = true;
end
