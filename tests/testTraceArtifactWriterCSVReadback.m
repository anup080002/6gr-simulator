function ok = testTraceArtifactWriterCSVReadback()
%TESTTRACEARTIFACTWRITERCSVREADBACK Verify CSV readback audit marks readable CSVs as read_ok.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanupObj = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>

sampleDir = fullfile(runFolder, "reports", "csv");
mkdir(sampleDir);
samplePath = fullfile(sampleDir, "sample_metrics.csv");
sampleTable = table([1; 2], [3.5; 4.5], ["ok"; "ok"], ...
    'VariableNames', {'Slot','SINR_dB','Status'});
sixgr.util.csvWriteTable(samplePath, sampleTable);

summary = sixgr.trace.TraceArtifactWriter.auditOutputs(runFolder, "unit_readback");
assert(double(summary.TotalCSVFiles) >= 1, ...
    "CSV audit must discover the sample CSV artifact.");
assert(double(summary.TotalCSVReadSuccessfully) == double(summary.TotalCSVFiles), ...
    "Readable CSV artifacts must be counted as successful readbacks.");
assert(double(summary.TotalCSVReadFailed) == 0, ...
    "Readable CSV artifacts must not be marked as read_failed.");

auditTable = readtable(char(summary.CSVAuditCSV), "VariableNamingRule", "preserve");
assert(any(strcmpi(string(auditTable.RelativePath), "reports/csv/sample_metrics.csv")), ...
    "CSV audit must preserve the sample CSV entry.");
assert(all(logical(auditTable.ReadOk)), ...
    "CSV audit output must mark the sample CSV as readable.");

ok = true;
end
