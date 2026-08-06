function ok = testArtifactTransaction()
%TESTARTIFACTTRANSACTION Verify artifact begin/commit journaling.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanupObj = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>

relPath = fullfile("reports", "json", "unit_artifact.txt");
sixgr.runtime.RuntimeArtifactTransaction.writeTextAtomic(runFolder, relPath, ...
    "hello runtime artifact", ...
    "ProducerStage", "unit_stage", ...
    "ProducerBlock", "unit_artifact_writer");

finalPath = fullfile(runFolder, relPath);
assert(exist(finalPath, "file") == 2, "Committed artifact must exist at final path.");
assert(strcmp(fileread(finalPath), "hello runtime artifact"), "Committed artifact content must match.");

artifactCsv = fullfile(runFolder, "runtime", "csv", "artifact_transactions.csv");
assert(exist(artifactCsv, "file") == 2, "Artifact transaction CSV must exist.");
T = readtable(artifactCsv, "Delimiter", ",", "VariableNamingRule", "preserve");
assert(ismember("event_type", string(T.Properties.VariableNames)), ...
    "Artifact transaction schema was parsed as: %s", ...
    strjoin(string(T.Properties.VariableNames), "|"));
eventTypes = string(T.event_type);
assert(any(eventTypes == "ARTIFACT_BEGIN"), "Artifact begin must be recorded.");
assert(any(eventTypes == "ARTIFACT_COMMIT"), "Artifact commit must be recorded.");
assert(~any(eventTypes == "ARTIFACT_FAIL"), "Successful artifact write must not record a failure.");
commitRows = T(eventTypes == "ARTIFACT_COMMIT", :);
assert(all(double(commitRows.byte_count) > 0), "Committed artifact must include byte count.");
assert(all(strlength(string(commitRows.sha256)) == 64), "Committed artifact must include SHA-256.");

ok = true;
end
