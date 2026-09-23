function ok = test6GScenarioMatrixRunner()
%TEST6GSCENARIOMATRIXRUNNER Execute a lightweight 6G matrix run.

setup6GRSimToolkit("Verbose", false);

previousScratch=string(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
scratchRoot=previousScratch;
ownsScratchRoot=strlength(strtrim(scratchRoot))==0;
if ownsScratchRoot
    scratchRoot=string(tempname);
    mkdir(scratchRoot);
    setenv("SIXGR_REGRESSION_SCRATCH_ROOT",scratchRoot);
elseif ~isfolder(scratchRoot)
    mkdir(scratchRoot);
end
scratchCleanup=onCleanup(@()localRestoreScratch(previousScratch,scratchRoot,ownsScratchRoot)); %#ok<NASGU>
tmp=localScratchChild(scratchRoot,"m",ownsScratchRoot);
mkdir(tmp);
c = onCleanup(@() localRemoveFolder(tmp)); %#ok<NASGU>

scenarioA = fullfile(tmp, "scenario_a.yaml");
fid = fopen(scenarioA, "w");
fprintf(fid, "%s", "inherits:");
fprintf(fid, "\n  - %s", fullfile(pwd, "simulator", "configs", "scenarios", "ce_ai_nn.yaml"));
fprintf(fid, "\nmeta:");
fprintf(fid, "\n  scenario_id: matrix_ai_sweep_a");
fprintf(fid, "\n  description: ai sweep a");
fprintf(fid, "\n  version: '1'");
fprintf(fid, "\n  owner: test");
fprintf(fid, "\n  maturity_tag: smoke");
fprintf(fid, "\n  research_class: baseline_benchmark");
fprintf(fid, "\nscenario:");
fprintf(fid, "\n  runner_profile: generic_sweep");
fprintf(fid, "\n  target_cases: [srs]");
fprintf(fid, "\n  sweep:");
fprintf(fid, "\n    base_profile: ai_benchmark");
fprintf(fid, "\n    output_name: matrix_ai_sweep");
fprintf(fid, "\n    overrides:");
fprintf(fid, "\n      - label: baseline_point");
fprintf(fid, "\n        config:");
fprintf(fid, "\n          meta:");
fprintf(fid, "\n            research_class: baseline_benchmark");
fprintf(fid, "\n          ai_ml:");
fprintf(fid, "\n            enabled: false");
fprintf(fid, "\n      - label: candidate_point");
fprintf(fid, "\n        config:");
fprintf(fid, "\n          meta:");
fprintf(fid, "\n            research_class: optional_research_experiment");
fprintf(fid, "\n          ai_ml:");
fprintf(fid, "\n            enabled: true");
fprintf(fid, "\nrun_control:");
fprintf(fid, "\n  num_workers: 1");
fprintf(fid, "\noutput:");
fprintf(fid, "\n  save_figures: false");
fprintf(fid, "\n  profiler_enabled: true");
fclose(fid);

scenarioB = fullfile(tmp, "scenario_b.yaml");
fid = fopen(scenarioB, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "scenarios", "prach_detection.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"matrix_prach_b","description":"b","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"monte_carlo_iterations":2,"random_seed":5},' ...
    '"run_control":{"num_workers":1},' ...
    '"output":{"save_figures":false}}']);
fclose(fid);

matrixPath = fullfile(tmp, "matrix.yaml");
fid = fopen(matrixPath, "w");
fprintf(fid, "%s", "meta:");
fprintf(fid, "\n  matrix_id: smoke_matrix");
fprintf(fid, "\n  description: smoke matrix");
fprintf(fid, "\nexecution:");
fprintf(fid, "\n  stop_on_failure: false");
fprintf(fid, "\n  max_parallel_jobs: 1");
fprintf(fid, "\n  repeat_count: 1");
fprintf(fid, "\n  save_combined_summary: true");
fprintf(fid, "\nscenarios:");
fprintf(fid, "\n  - %s", scenarioA);
fprintf(fid, "\n  - %s", scenarioB);
fclose(fid);

out = run_6g_phy_lls_matrix(matrixPath, tmp, "smoke");
assert(out.Ok, "Matrix runner should complete.");
if strlength(strtrim(scratchRoot)) > 0
    assert(localPathStartsWith(out.RunFolder, tmp), ...
        "Regression matrix output must remain inside its configured task scratch root.");
end
assert(exist(char(out.SummaryCSV), "file") == 2, "Matrix summary CSV missing.");
assert(exist(fullfile(char(out.RunFolder), "meta", "matrix_config_resolved.json"), "file") == 2, ...
    "Matrix run must save resolved JSON snapshot.");
assert(exist(fullfile(char(out.RunFolder), "meta", "matrix_config_resolved.yaml"), "file") == 2, ...
    "Matrix run must save resolved YAML snapshot.");
assert(exist(fullfile(char(out.RunFolder), "meta", "matrix_source_chain.csv"), "file") == 2, ...
    "Matrix run must save matrix source chain.");
assert(exist(char(out.ScenarioSummaryCSV), "file") == 2, "Matrix scenario summary CSV missing.");
assert(exist(char(out.PointSummaryCSV), "file") == 2, "Matrix point summary CSV missing.");
assert(exist(char(out.SuiteSummaryCSV), "file") == 2, "Matrix suite summary CSV missing.");
assert(exist(fullfile(char(out.RunFolder), "reports", "csv", "matrix_baseline_scenarios.csv"), "file") == 2, ...
    "Matrix baseline scenario CSV missing.");
assert(exist(fullfile(char(out.RunFolder), "reports", "csv", "matrix_open_study_scenarios.csv"), "file") == 2, ...
    "Matrix open-study scenario CSV missing.");
assert(exist(fullfile(char(out.RunFolder), "reports", "csv", "matrix_baseline_points.csv"), "file") == 2, ...
    "Matrix baseline point CSV missing.");
assert(exist(fullfile(char(out.RunFolder), "reports", "csv", "matrix_open_study_points.csv"), "file") == 2, ...
    "Matrix open-study point CSV missing.");

T = readtable(char(out.SummaryCSV), 'Delimiter', ',', ...
    'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(height(T) == 2, "Matrix summary should contain two scenario rows.");
aiRow = find(string(T.ScenarioID) == "matrix_ai_sweep_a", 1, "first");
assert(~isempty(aiRow), "Matrix summary must retain the AI sweep parent row.");
aiRunFolder = char(string(T.RunFolder(aiRow)));
assert(isfile(fullfile(aiRunFolder,"reports","csv", ...
    "runtime_profiler_summary.csv")), ...
    'The generic-sweep parent must persist its orchestration preflight profile.');
parentProfile=readtable(fullfile(aiRunFolder,"reports","csv", ...
    "runtime_profiler_summary.csv"),'TextType','string');
assert(height(parentProfile)==1 && ...
    contains(parentProfile.Notes,"Scope=sweep_parent_preflight_only"), ...
    'The parent profile must not be mislabeled as child PHY execution.');
artifactIndexPath = fullfile(aiRunFolder, "reports", "csv", ...
    "sweep_artifact_index.csv");
assert(isfile(artifactIndexPath), ...
    "Generic sweep parent must persist a child-artifact lineage index.");
artifactIndexT = readtable(artifactIndexPath, "VariableNamingRule", ...
    "preserve", "TextType", "string");
assert(height(artifactIndexT) >= 10 && ...
        all(strlength(strtrim(artifactIndexT.PointRunID)) > 0) && ...
        all(strlength(strtrim(artifactIndexT.PointConfigHash)) == 64) && ...
        all(strlength(strtrim(artifactIndexT.SHA256)) == 64) && ...
        all(~logical(artifactIndexT.ParentPrimaryWaveformRowsCopied)), ...
    ["Sweep lineage must bind every required measured child artifact to " ...
     "its run/config hash without copying child PHY rows into parent truth."]);
childConfigRows=artifactIndexT(artifactIndexT.ArtifactRole=="resolved_configuration",:);
assert(height(childConfigRows)==2, ...
    'The sweep index must bind both configured child executions.');
for childIndex=1:height(childConfigRows)
    % Published CSVs omit absolute RunFolder columns. Use the verified
    % relative artifact index rather than an internal pre-publication path.
    childConfigPath=fullfile(aiRunFolder, ...
        char(childConfigRows.RelativePath(childIndex)));
    childFolder=fileparts(fileparts(childConfigPath));
    assert(isfile(fullfile(childFolder,"reports","csv", ...
        "runtime_profiler_summary.csv")), ...
        'Every profiling-enabled child must persist its own execution profile.');
    childResolved=jsondecode(fileread(childConfigPath));
    assert(logical(childResolved.output.profiler_enabled) && ...
        logical(childResolved.run_control.time_profiling_enable) && ...
        logical(childResolved.analytics.export_time_profile), ...
        'Sweep execution must preserve configured child diagnostics.');
    childProfile=readtable(fullfile(childFolder,"reports","csv", ...
        "runtime_profiler_summary.csv"),'TextType','string');
    assert(height(childProfile)==1 && childProfile.FunctionCount>0 && ...
        ~contains(childProfile.Notes,"sweep_parent_preflight_only"), ...
        'A child must retain its measured execution profile, not parent setup.');
end
assert(~isfile(fullfile(aiRunFolder,"reports","csv","time_profile_calls.csv")), ...
    'The parent must not export the last child''s per-function timings as its own.');
aggregatePath = fullfile(aiRunFolder, "reports", "csv", ...
    "ai_channel_estimation_benchmark.csv");
assert(isfile(aggregatePath), ...
    "AI sweep parent must expose the exact selected use-case aggregate.");
aggregateT = readtable(aggregatePath, "VariableNamingRule", "preserve", ...
    "TextType", "string");
assert(height(aggregateT) >= 2 && ...
        all(ismember(["SweepLabel","SweepPointRunID", ...
            "SweepPointConfigHash","SweepPointSourceSHA256"], ...
            string(aggregateT.Properties.VariableNames))) && ...
        all(strlength(strtrim(aggregateT.SweepPointRunID)) > 0) && ...
        all(strlength(strtrim(aggregateT.SweepPointConfigHash)) == 64), ...
    "AI sweep aggregate must retain exact child identity and source hashes.");

scenarioT = readtable(char(out.ScenarioSummaryCSV), 'Delimiter', ',', ...
    'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(all(ismember(["ResearchClass","StudyBucket","LabDefaultFlag","LabDefaultCount","LabDefaultPaths","PointCount"], ...
    string(scenarioT.Properties.VariableNames))), ...
    "Matrix scenario summary must include study-bucket and lab-default columns.");
pointT = readtable(char(out.PointSummaryCSV), 'Delimiter', ',', ...
    'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(height(pointT) >= 3, "Matrix point summary must expand sweep points and nominal scenarios.");
assert(all(ismember(["ParentScenarioID","PointLabel","PointScenarioID","ResearchClass","StudyBucket","LabDefaultFlag"], ...
    string(pointT.Properties.VariableNames))), ...
    "Matrix point summary must include point and study-bucket columns.");
assert(any(string(pointT.StudyBucket) == "baseline"), "Matrix point summary must retain baseline points.");
assert(any(string(pointT.StudyBucket) == "open_study"), "Matrix point summary must retain open-study points.");

suiteT = readtable(char(out.SuiteSummaryCSV), 'Delimiter', ',', ...
    'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(height(suiteT) == 1, "Matrix suite summary must contain one row.");
assert(all(ismember(["MatrixID","ScenarioCount","PointCount","BaselineScenarioCount","OpenStudyScenarioCount", ...
    "BaselinePointCount","OpenStudyPointCount","LabDefaultScenarioCount","LabDefaultPointCount","RunCompletion"], ...
    string(suiteT.Properties.VariableNames))), ...
    "Matrix suite summary must expose suite totals.");

manifest = jsondecode(fileread(fullfile(char(out.RunFolder), "meta", "matrix_manifest.json")));
assert(isfield(manifest, "RequestedParallelJobs"), "Matrix manifest must include RequestedParallelJobs.");
assert(isfield(manifest, "RunScope"), "Matrix manifest must include RunScope.");
assert(isfield(manifest, "RunCompletion"), "Matrix manifest must include RunCompletion.");
assert(isfield(manifest, "CodeVersion"), "Matrix manifest must include CodeVersion.");
assert(isfield(manifest, "CodeDetail"), "Matrix manifest must include CodeDetail.");
assert(isfield(manifest, "ScenarioSummaryCSV"), "Matrix manifest must include ScenarioSummaryCSV.");
assert(isfield(manifest, "PointSummaryCSV"), "Matrix manifest must include PointSummaryCSV.");
assert(isfield(manifest, "SuiteSummaryCSV"), "Matrix manifest must include SuiteSummaryCSV.");
assert(isfield(manifest, "BaselineScenarioCSV"), "Matrix manifest must include BaselineScenarioCSV.");
assert(isfield(manifest, "OpenStudyScenarioCSV"), "Matrix manifest must include OpenStudyScenarioCSV.");
assert(isfield(manifest, "BaselinePointCSV"), "Matrix manifest must include BaselinePointCSV.");
assert(isfield(manifest, "OpenStudyPointCSV"), "Matrix manifest must include OpenStudyPointCSV.");

ok = true;
end

function tf = localPathStartsWith(pathValue, rootValue)
pathValue = replace(string(pathValue), "/", filesep);
rootValue = replace(string(rootValue), "/", filesep);
if ispc
    pathValue = lower(pathValue);
    rootValue = lower(rootValue);
end
tf = pathValue == rootValue || startsWith(pathValue, rootValue + filesep);
end

function localRestoreScratch(previousScratch,scratchRoot,ownsScratchRoot)
setenv("SIXGR_REGRESSION_SCRATCH_ROOT",previousScratch);
if ownsScratchRoot
    localRemoveFolder(scratchRoot);
end
end

function pathValue=localScratchChild(scratchRoot,prefix,ownsScratchRoot)
if ownsScratchRoot
    pathValue=fullfile(scratchRoot,prefix);
else
    token=char(java.util.UUID.randomUUID());
    pathValue=fullfile(scratchRoot,prefix+string(token(1:8)));
end
end

function localRemoveFolder(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,"s");
end
end
