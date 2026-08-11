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
caseVariantPath = fullfile(reportDir,"case_variant_identity.csv");
sixgr.util.csvWriteTable(caseVariantPath,table("scenario_unit",7, ...
    'VariableNames',{'ScenarioId','Value'}));

% Statistical component exporters run before the global identity pass.
% Their source hashes must be refreshed after the source is annotated.
statRoot = fullfile(runFolder, "statistical_campaigns", "prach");
statCSV = fullfile(statRoot, "control", "csv");
statFigures = fullfile(statRoot, "reports", "figures");
mkdir(statCSV);
mkdir(statFigures);
statSource = fullfile(statCSV, "prach_trials.csv");
statImage = fullfile(statFigures, "prach_plot.png");
sixgr.util.csvWriteTable(statSource, table(4, 'VariableNames', {'Value'}));
imwrite(uint8(zeros(8, 8, 3)), statImage);
statLineage = fullfile(statCSV, "prach_plot_lineage.csv");
sixgr.visual.writeComponentPlotLineage(statRoot, statLineage, ...
    "prach_plot", statImage, statSource, "unit_test");
lineageBefore = readtable(statLineage, "VariableNamingRule", "preserve", "TextType", "string");

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
caseVariant = readtable(caseVariantPath,'VariableNamingRule','preserve','TextType','string');
caseNames = string(caseVariant.Properties.VariableNames);
assert(nnz(strcmpi(caseNames,"ScenarioID")) == 1 && ...
    numel(unique(lower(caseNames))) == numel(caseNames), ...
    "Scenario annotation must not append a case-only duplicate identity column.");
assert(summary.AnnotatedCount >= 3 && summary.SkippedImmutableCount >= 4);
statAnnotated = readtable(statSource, "VariableNamingRule", "preserve", "TextType", "string");
lineageAfter = readtable(statLineage, "VariableNamingRule", "preserve", "TextType", "string");
assert(ismember("ScenarioID", string(statAnnotated.Properties.VariableNames)), ...
    "Mutable statistical component evidence must receive scenario identity.");
assert(lineageAfter.SourceCSV_SHA256(1) ~= lineageBefore.SourceCSV_SHA256(1), ...
    "Lineage hash must change when final identity annotation changes source bytes.");
visual = sixgr.visual.verifyVisualArtifacts(runFolder, table());
plotRow = visual.PlotId == "prach_plot";
assert(nnz(plotRow) == 1 && visual.IntegrityOk(plotRow), ...
    "Final statistical component lineage must verify against annotated source bytes.");
assert(summary.RefreshedLineageCount == 1);

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
