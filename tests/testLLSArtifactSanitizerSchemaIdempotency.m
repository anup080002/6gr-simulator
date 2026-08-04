function ok = testLLSArtifactSanitizerSchemaIdempotency()
%TESTLLSARTIFACTSANITIZERSCHEMAIDEMPOTENCY Preserve required blank guards.

setup6GRSimToolkit("Verbose", false);
runFolder = string(tempname);
reportCSV = fullfile(runFolder, "reports", "csv");
mkdir(reportCSV);
cleanupObj = onCleanup(@() localRemoveTree(runFolder)); %#ok<NASGU>

Scope = ["run"; "ue"];
StrictOk = [true; true];
UsedOracleFields = [""; ""];
Notes = ["No oracle fields were consumed, strict waveform row."; ...
    "No oracle fields were consumed, strict waveform row."];
fixture = table(Scope, StrictOk, UsedOracleFields, Notes);
pathOut = fullfile(reportCSV, "schema_guard_fixture.csv");
sixgr.util.csvWriteTable(pathOut, fixture);

sixgr.truth.sanitizeLLSArtifactCSVs(runFolder);
sixgr.truth.sanitizeLLSArtifactCSVs(runFolder);
roundTrip = readtable(pathOut, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(all(ismember(["Scope","StrictOk","UsedOracleFields"], ...
    string(roundTrip.Properties.VariableNames))), ...
    "Repeated sanitization removed a contract-required blank oracle guard column.");
assert(all(string(roundTrip.Scope) == ["run"; "ue"]), ...
    "Repeated sanitization changed populated scope semantics.");

ferT = table("run", "DL", 1, 0, 0, ...
    'VariableNames', {'Scope','Direction','ObservedFrames','ErroredFrames','FER'});
sixgr.util.csvWriteTable(fullfile(reportCSV, "fer_summary.csv"), ferT);
sixgr.truth.restoreCompletedRunTruthArtifacts(runFolder, struct());
ferMirror = readtable(fullfile(reportCSV, "live_error_rate_summary.csv"), ...
    "FileType", "text", "Delimiter", ",", "ReadVariableNames", true, ...
    "VariableNamingRule", "preserve");
assert(ismember("Scope", string(ferMirror.Properties.VariableNames)) && ...
    string(ferMirror.Scope(1)) == "run", ...
    "Completed-run recovery did not restore the FER mirror from its canonical runtime table.");

ok = true;
end

function localRemoveTree(pathValue)
if exist(pathValue, "dir") == 7
    rmdir(pathValue, "s");
end
end
