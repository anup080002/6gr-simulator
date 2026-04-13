function ok = testRequiredOutputCompleteness()
%TESTREQUIREDOUTPUTCOMPLETENESS Verify exact required-output completeness checks.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

csvDir = fullfile(tmp, "csv");
mkdir(csvDir);
existingFile = fullfile(csvDir, "present.csv");
fid = fopen(existingFile, "w");
assert(fid >= 0, "Failed to create required-output fixture.");
fprintf(fid, "x,y\n1,2\n");
fclose(fid);

out = sixgr.report.checkRequiredOutputs(tmp, ["csv/present.csv", "csv/missing.csv"]);
assert(~out.Ok, "Missing required outputs must fail completeness checks.");
assert(out.MissingCount == 1, "Expected one missing required output.");
assert(any(string(out.Missing) == "csv/missing.csv"), "Missing relative output was not reported.");

threw = false;
try
    sixgr.report.checkRequiredOutputs(tmp, ["csv/present.csv", "csv/missing.csv"], "StrictMode", true); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "sixgr:report:MissingRequiredOutputs");
end
assert(threw, "Strict required-output completeness must throw on missing files.");

ok = true;
end
