function ok = testRestoreStrictPRACHComponentAnchor()
%TESTRESTORESTRICTPRACHCOMPONENTANCHOR Validate resumable PRACH evidence.

setup6GRSimToolkit("Verbose", false);
anchorRoot = string(tempname());
mkdir(anchorRoot);
cleanup = onCleanup(@() localRemove(anchorRoot)); %#ok<NASGU>
scenarioID = "scenario_unit";
configHash = string(repmat('a', 1, 64));

identity = struct( ...
    "SchemaName", "sixgr.component_anchor_identity", ...
    "SchemaVersion", "1.0.0", ...
    "Component", "prach", ...
    "ParentScenarioID", scenarioID, ...
    "ParentConfigHash", configHash);
sixgr.util.jsonWrite(fullfile(anchorRoot, "component_anchor_identity.json"), identity);

csvRoot = fullfile(anchorRoot, "control", "csv");
jsonRoot = fullfile(anchorRoot, "reports", "json");
mkdir(csvRoot);
mkdir(jsonRoot);
trial = table((1:4).', ...
    ["positive_high_snr"; "missed_detection_sweep"; ...
     "false_alarm_sweep"; "negative_wrong_root"], ...
    [true; false; false; false], [false; false; false; true], ...
    false(4, 1), false(4, 1), false(4, 1), ...
    repmat(configHash, 4, 1), repmat(scenarioID, 4, 1), ...
    ["PASS"; "NOT_EVALUATED"; "PASS"; "EXPECTED_FAIL"], ...
    'VariableNames', {'TrialId','TrialType','StrictOk','NegativeExpectedOk', ...
    'ProxyUsed','Skipped','ToolboxMissing','ConfigHash','RunId','Status'});
config = table("unit", 'VariableNames', {'ConfigName'});
trialPath = fullfile(csvRoot, "prach_strict_trials.csv");
configPath = fullfile(csvRoot, "prach_config_strict.csv");
sixgr.util.csvWriteTable(trialPath, trial);
sixgr.util.csvWriteTable(configPath, config);

paths = [string(configPath); string(trialPath)];
ids = ["prach_config_strict.csv"; "prach_strict_trials.csv"];
bytes = arrayfun(@(pathValue) double(dir(pathValue).bytes), paths);
hashes = arrayfun(@(pathValue) sixgr.protocol.ProtocolHash.file(pathValue), paths);
manifest = table(ids, paths, bytes, hashes, ...
    'VariableNames', {'ArtifactId','FilePath','ByteCount','SHA256'});
manifestPath = fullfile(csvRoot, "prach_strict_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
% Reproduce the legacy exporter defect: its manifest listed a stale hash of
% itself. Restoration may ignore this mathematically unverifiable row, but
% must still authenticate every evidence artifact and the summary binding.
selfRow = table("prach_strict_artifact_manifest.csv", string(manifestPath), ...
    1, "stale-self-hash", 'VariableNames', ...
    {'ArtifactId','FilePath','ByteCount','SHA256'});
manifest = [manifest; selfRow];
sixgr.util.csvWriteTable(manifestPath, manifest);
summary = struct("StrictOk", true, "StatisticallyQualified", true, ...
    "StatisticalQualification", "PASS", "ConfigHash", configHash, ...
    "source_csv", string(trialPath), ...
    "source_csv_sha256", sixgr.protocol.ProtocolHash.file(trialPath));
sixgr.util.jsonWrite(fullfile(jsonRoot, "prach_conformance_summary.json"), summary);

restored = sixgr.truth.restoreStrictPRACHComponentAnchor( ...
    anchorRoot, scenarioID, configHash);
assert(restored.Ok && restored.StrictOk && restored.StatisticallyQualified);
assert(restored.RestoredFromPersistedCompletedSupplementalEvidence);
assert(restored.LegacySelfReferentialManifestRowIgnored);
assert(height(restored.ArtifactTables.prach_trials) == 4);

trial.ProxyUsed(1) = true;
sixgr.util.csvWriteTable(trialPath, trial);
try
    sixgr.truth.restoreStrictPRACHComponentAnchor(anchorRoot, scenarioID, configHash);
    error("testRestoreStrictPRACHComponentAnchor:ExpectedHashFailure", ...
        "Mutated PRACH evidence must fail closed.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:truth:prachResume:ArtifactHashMismatch"), ...
        "Unexpected restore failure: %s | %s", ME.identifier, ME.message);
end

ok = true;
fprintf("PASS testRestoreStrictPRACHComponentAnchor: identity/hash restore is fail closed.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
