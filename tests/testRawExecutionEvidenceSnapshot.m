function ok = testRawExecutionEvidenceSnapshot()
%TESTRAWEXECUTIONEVIDENCESNAPSHOT Freeze only actual same-run waveform rows.

ok = false;
runFolder = string(tempname());
cleanup = onCleanup(@() localCleanup(runFolder)); %#ok<NASGU>
mkdir(runFolder);
identity = struct("RunID", "raw-run", "ExecutionID", "exec-raw", ...
    "ScenarioID", "scenario-raw", "ConfigHash", string(repmat('a', 1, 64)));

dl = table(["dl-1";"dl-2"], [1;2], [1;1], [1;2], ...
    ["in_path";"in_path"], ["truth";"truth"], [false;false], ...
    'VariableNames', {'TrialID','Frame','Slot','UEID','EvidenceScope', ...
    'SourceClassification','FallbackFlag'});
% CSV serialization expands this one logical table variable into two
% physical columns. The immutable index must record the parsed CSV shape,
% not the smaller in-memory logical-variable count.
dl.PerLayerMetric = [1 2; 3 4];
anchor = dl(1, :);
anchor.TrialID = "anchor-1";
anchor.EvidenceScope = "component_anchor";
link = struct("RawTrials", struct("DL", dl), ...
    "SupplementalStrictRawTrials", struct("PRACH", anchor));

snapshot = sixgr.runtime.snapshotRawExecutionEvidence(runFolder, link, identity);
assert(snapshot.TableCount == 1 && snapshot.RowCount == 2);
indexT = readtable(snapshot.IndexPath, "TextType", "string");
assert(height(indexT) == 1 && indexT.TableName == "rawtrials_dl");
assert(indexT.EvidenceScope == "in_path" && indexT.DuplicateKeyCount == 0);
rawT = readtable(fullfile(fileparts(snapshot.IndexPath), ...
    char(indexT.RelativePath)), "TextType", "string");
assert(indexT.ColumnCount == width(rawT) && width(rawT) > width(dl), ...
    ["Raw evidence must permit lossless expansion of matrix-valued table " ...
    "variables and index the physical CSV column count."]);
assert(all(rawT.RunID == identity.RunID) && ...
    all(rawT.ExecutionID == identity.ExecutionID) && ...
    all(rawT.ScenarioConfigHash == identity.ConfigHash) && ...
    all(rawT.EvidenceScope == "in_path"));

repeat = sixgr.runtime.snapshotRawExecutionEvidence(runFolder, link, identity);
assert(repeat.IndexSHA256 == snapshot.IndexSHA256);

% A later report-identity pass must never invalidate the immutable raw
% index. Re-reading the seal after annotation proves byte preservation.
sixgr.report.annotateScenarioCSVArtifacts(runFolder, identity.ScenarioID, ...
    identity.ConfigHash, "waveform_bundle");
afterAnnotation = sixgr.runtime.snapshotRawExecutionEvidence( ...
    runFolder, link, identity);
assert(afterAnnotation.IndexSHA256 == snapshot.IndexSHA256, ...
    "Report annotation must not change any indexed raw-evidence bytes.");

proxyFolder = string(tempname());
proxyCleanup = onCleanup(@() localCleanup(proxyFolder)); %#ok<NASGU>
mkdir(proxyFolder);
proxy = dl(1, :);
proxy.SourceClassification = "fast_proxy";
localAssertError(@() sixgr.runtime.snapshotRawExecutionEvidence( ...
    proxyFolder, struct("RawTrials", struct("DL", proxy)), identity), ...
    "sixgr:runtime:ProxyRawEvidenceForbidden");

duplicateFolder = string(tempname());
duplicateCleanup = onCleanup(@() localCleanup(duplicateFolder)); %#ok<NASGU>
mkdir(duplicateFolder);
duplicate = [dl(1, :); dl(1, :)];
localAssertError(@() sixgr.runtime.snapshotRawExecutionEvidence( ...
    duplicateFolder, struct("RawTrials", struct("DL", duplicate)), identity), ...
    "sixgr:runtime:RawEvidenceDuplicateKey");

fprintf("PASS testRawExecutionEvidenceSnapshot: immutable in-path snapshot excludes anchors and rejects proxy/duplicates.\n");
ok = true;
end

function localAssertError(fn, identifier)
try
    fn();
    error("testRawExecutionEvidenceSnapshot:ExpectedError", ...
        "Expected %s.", identifier);
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        "Expected %s, received %s: %s", identifier, ME.identifier, ME.message);
end
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
