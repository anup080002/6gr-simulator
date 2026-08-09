function ok = testScenarioCSVAnnotationRuntimeIsolation()
%TESTSCENARIOCSVANNOTATIONRUNTIMEISOLATION Keep runtime schemas immutable.

setup6GRSimToolkit("Verbose", false);
runFolder = string(tempname());
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>

bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, ...
    "RunId", "annotation_isolation", ...
    "ExecutionId", "execution_001", ...
    "FinalizationId", "finalization_001", ...
    "AttemptId", "attempt_001");
bus.stageStart("annotation_guard");

runtimePath = fullfile(runFolder, "runtime", "csv", "stage_timing_events.csv");
runtimeBefore = fileread(runtimePath);

reportDir = fullfile(runFolder, "reports", "csv");
if ~isfolder(reportDir)
    mkdir(reportDir);
end
reportPath = fullfile(reportDir, "ordinary_report.csv");
sixgr.util.csvWriteTable(reportPath, table((1:2).', 'VariableNames', {'Value'}));

mirrorDir = fullfile(runFolder, "prach", "csv");
if ~isfolder(mirrorDir)
    mkdir(mirrorDir);
end
mirrorPath = fullfile(mirrorDir, "mirror.csv");
sixgr.util.csvWriteTable(mirrorPath, table(1, 'VariableNames', {'Value'}));
mirrorBefore = fileread(mirrorPath);

% Air-interface and beamforming tables are direct plot sources.  Their byte
% hashes are sealed into component plot-lineage rows when the waveform
% runner renders the PNGs, so late report annotation must not mutate them.
airDir = fullfile(runFolder, "air_interface", "csv");
beamDir = fullfile(runFolder, "beamforming", "csv");
mkdir(airDir);
mkdir(beamDir);
airPath = fullfile(airDir, "dl_pdsch_trials.csv");
beamPath = fullfile(beamDir, "probe_beam_mimo.csv");
sixgr.util.csvWriteTable(airPath, table(2, 'VariableNames', {'Value'}));
sixgr.util.csvWriteTable(beamPath, table(3, 'VariableNames', {'Value'}));
airBefore = fileread(airPath);
beamBefore = fileread(beamPath);

summary = sixgr.report.annotateScenarioCSVArtifacts(runFolder, ...
    "scenario_unit", "hash_unit", "waveform_bundle");

assert(strcmp(fileread(runtimePath), runtimeBefore), ...
    "Runtime journal projections must remain byte-for-byte unchanged.");
assert(strcmp(fileread(mirrorPath), mirrorBefore), ...
    "Component mirrors must remain byte-for-byte unchanged.");
assert(strcmp(fileread(airPath), airBefore) && ...
    strcmp(fileread(beamPath), beamBefore), ...
    "Waveform plot-source tables must remain byte-for-byte unchanged after their lineage hashes are sealed.");
report = readtable(reportPath, 'VariableNamingRule', 'preserve');
assert(isequal(string(report.Properties.VariableNames(1:3)), ...
    ["ScenarioID", "ConfigHash", "RunnerProfile"]));
assert(all(string(report.ScenarioID) == "scenario_unit"));
assert(all(string(report.ConfigHash) == "hash_unit"));
assert(all(string(report.RunnerProfile) == "waveform_bundle"));
assert(summary.AnnotatedCount == 1 && summary.SkippedImmutableCount >= 4);

% Prove the unchanged runtime file still accepts the next versioned event.
bus.stageEnd("annotation_guard");
runtime = readtable(runtimePath, 'VariableNamingRule', 'preserve');
assert(width(runtime) == 19, "Runtime stage schema must retain 19 fields.");
assert(height(runtime) == 2, "Both stage events must remain appendable.");

ok = true;
fprintf("PASS testScenarioCSVAnnotationRuntimeIsolation: runtime journals remain immutable.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
