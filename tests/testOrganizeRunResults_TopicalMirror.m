function ok = testOrganizeRunResults_TopicalMirror()
%TESTORGANIZERUNRESULTSTOPICALMIRROR Ensure lls/sls topical mirrors are created.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

runFolder = fullfile(tmp, "full3gpp_20990101_010101");
sixgr.util.ensureDir(fullfile(runFolder, "control", "csv", ".keep"));
sixgr.util.ensureDir(fullfile(runFolder, "system", "csv", ".keep"));

prachT = table(1, 1, true, 'VariableNames', {'Trial','PreambleIndex','Detected'});
sysT = table(1, 2, 12.5, 'VariableNames', {'TTI','NumUE','MeanSINR_dB'});

sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_trials.csv"), prachT);
sixgr.util.csvWriteTable(fullfile(runFolder, "system", "csv", "system_kpis.csv"), sysT);

sixgr.report.OrganizeRunResults(runFolder, ...
    "ResultsRoot", tmp, ...
    "MirrorToResultsRoot", true);

llsPrach = fullfile(tmp, "lls", "prach", "full3gpp_20990101_010101", "csv", "prach_trials.csv");
slsMobility = fullfile(tmp, "sls", "mobility", "full3gpp_20990101_010101", "csv", "system_kpis.csv");

assert(exist(llsPrach, "file") == 2, "Missing mirrored LLS PRACH artifact: %s", llsPrach);
assert(exist(slsMobility, "file") == 2, "Missing mirrored SLS mobility artifact: %s", slsMobility);
assert(exist(fullfile(tmp, "lls", "LATEST.txt"), "file") == 2, "Missing lls topical latest marker.");
assert(exist(fullfile(tmp, "sls", "LATEST.txt"), "file") == 2, "Missing sls topical latest marker.");

ok = true;
end
