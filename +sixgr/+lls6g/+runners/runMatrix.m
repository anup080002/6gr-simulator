function out = runMatrix(configPath, outputDir, runTag)
%RUNMATRIX Execute a config-driven scenario matrix.

if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = "results";
end
if nargin < 3
    runTag = "";
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

matrixCfg = sixgr.lls6g.config.readConfigFile(configPath);
sixgr.lls6g.config.validateScenarioConfig(matrixCfg, ...
    "Kind", "matrix", "AllowPartial", false, "Context", configPath);

matrixID = string(matrixCfg.meta.matrix_id);
leaf = localResolveLeaf(runTag);
matrixRoot = sixgr.report.defaultRunFolder(outputDir, ...
    "Bucket", "lls", "Profile", matrixID, "Leaf", leaf, "CleanExisting", true);
layout = sixgr.report.resultLayout(matrixRoot);
sixgr.util.ensureFolder(layout.MetaDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(fullfile(matrixRoot, "runs"));
localWriteMatrixSnapshots(layout, configPath, matrixCfg);

scenarioList = string(matrixCfg.scenarios(:));
repeatCount = max(1, round(double(matrixCfg.execution.repeat_count)));
stopOnFailure = logical(matrixCfg.execution.stop_on_failure);
requestedParallelJobs = max(1, round(double(matrixCfg.execution.max_parallel_jobs)));
saveCombinedSummary = logical(matrixCfg.execution.save_combined_summary);
parallelAvailable = localParallelComputingToolboxAvailable();
parallelUnavailableWarningIssued = false;
parallelUnavailableReason = "";
if requestedParallelJobs > 1 && ~parallelAvailable
    warning("sixgr:runtime:NoParallelToolbox", ...
        ["Parallel Computing Toolbox licence unavailable. " ...
         "Simulation will run single-threaded (%d workers requested). " ...
         "Expected wall-clock time may be approximately %dx longer."], ...
        double(requestedParallelJobs), double(requestedParallelJobs));
    parallelUnavailableWarningIssued = true;
    parallelUnavailableReason = "parallel_computing_toolbox_license_unavailable";
end
rows = repmat(struct("ScenarioID","", "ConfigPath","", "Repeat", NaN, "RunFolder","", "Ok", false), 0, 1);
executionMode = "sequential";
if requestedParallelJobs > 1 && parallelAvailable && repeatCount == 1 && ~stopOnFailure && numel(scenarioList) > 1
    executionMode = "parallel";
    rows(1:numel(scenarioList),1) = struct("ScenarioID","", "ConfigPath","", "Repeat", NaN, "RunFolder","", "Ok", false); %#ok<AGROW>
    parfor (i = 1:numel(scenarioList), requestedParallelJobs)
        scenarioPath = localResolveScenarioPath(configPath, scenarioList(i));
        result = sixgr.lls6g.runners.runSingle(scenarioPath, fullfile(matrixRoot, "runs"), "repeat_1");
        rows(i,1) = struct( ...
            "ScenarioID", string(result.Config.ScenarioID), ...
            "ConfigPath", localPortablePath(scenarioPath), ...
            "Repeat", 1, ...
            "RunFolder", localPortablePath(result.RunFolder), ...
            "Ok", logical(result.Ok));
    end
else
    if requestedParallelJobs > 1 && ~parallelAvailable
        executionMode = "sequential_parallel_toolbox_unavailable";
    end
    for r = 1:repeatCount
        for i = 1:numel(scenarioList)
            scenarioPath = localResolveScenarioPath(configPath, scenarioList(i));
            scenarioRunTag = "repeat_" + string(r);
            result = sixgr.lls6g.runners.runSingle(scenarioPath, fullfile(matrixRoot, "runs"), scenarioRunTag);
            rows(end+1,1) = struct( ... %#ok<AGROW>
                "ScenarioID", string(result.Config.ScenarioID), ...
                "ConfigPath", localPortablePath(scenarioPath), ...
                "Repeat", r, ...
                "RunFolder", localPortablePath(result.RunFolder), ...
                "Ok", logical(result.Ok));
            if stopOnFailure && ~result.Ok
                break;
            end
        end
        if stopOnFailure && ~rows(end).Ok
            break;
        end
    end
end

summaryT = struct2table(rows);
summaryCsv = fullfile(layout.ReportCSVDir, "matrix_combined_summary.csv");
if saveCombinedSummary
    sixgr.util.csvWriteTable(summaryCsv, summaryT);
else
    summaryCsv = "";
end
[scenarioSummaryCsv, pointSummaryCsv, suiteSummaryCsv, baselineScenarioCsv, openStudyScenarioCsv, ...
    baselinePointCsv, openStudyPointCsv] = localWriteMatrixAggregateReports(layout, matrixID, summaryT);
[codeVersion, codeDetail] = localDetectCodeVersion();
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "matrix_manifest.json"), struct( ...
    "MatrixID", char(matrixID), ...
    "ConfigPath", char(localPortablePath(configPath)), ...
    "RunFolder", char(localPortablePath(matrixRoot)), ...
    "ScenarioCount", numel(scenarioList), ...
    "RepeatCount", repeatCount, ...
    "RequestedParallelJobs", requestedParallelJobs, ...
    "EffectiveWorkers", localEffectiveWorkers(executionMode, requestedParallelJobs), ...
    "ExecutionMode", executionMode, ...
    "ParallelUnavailableWarningIssued", logical(parallelUnavailableWarningIssued), ...
    "ParallelUnavailableReason", char(string(parallelUnavailableReason)), ...
    "SaveCombinedSummary", saveCombinedSummary, ...
    "CodeVersion", char(string(codeVersion)), ...
    "CodeDetail", char(string(codeDetail)), ...
    "RunScope", "6G_PHY_LLS_SCENARIO_MATRIX", ...
    "RunCompletion", localMatrixCompletion(summaryT), ...
    "SummaryCSV", char(localPortablePath(summaryCsv)), ...
    "ScenarioSummaryCSV", char(localPortablePath(scenarioSummaryCsv)), ...
    "PointSummaryCSV", char(localPortablePath(pointSummaryCsv)), ...
    "SuiteSummaryCSV", char(localPortablePath(suiteSummaryCsv)), ...
    "BaselineScenarioCSV", char(localPortablePath(baselineScenarioCsv)), ...
    "OpenStudyScenarioCSV", char(localPortablePath(openStudyScenarioCsv)), ...
    "BaselinePointCSV", char(localPortablePath(baselinePointCsv)), ...
    "OpenStudyPointCSV", char(localPortablePath(openStudyPointCsv))));

out = struct();
out.Ok = all(summaryT.Ok);
out.MatrixID = matrixID;
out.RunFolder = string(matrixRoot);
out.SummaryTable = summaryT;
out.SummaryCSV = string(summaryCsv);
out.ScenarioSummaryCSV = string(scenarioSummaryCsv);
out.PointSummaryCSV = string(pointSummaryCsv);
out.SuiteSummaryCSV = string(suiteSummaryCsv);
end

function tf = localParallelComputingToolboxAvailable()
tf = false;
try
    tf = license("test", "Distrib_Computing_Toolbox") && ~isempty(ver("parallel"));
catch
    tf = false;
end
end

function n = localEffectiveWorkers(executionMode, requestedParallelJobs)
if string(executionMode) == "parallel"
    n = double(requestedParallelJobs);
else
    n = 1;
end
end

function completion = localMatrixCompletion(summaryT)
if isempty(summaryT) || all(summaryT.Ok)
    completion = "completed";
else
    completion = "completed_with_failures";
end
end

function localWriteMatrixSnapshots(layout, configPath, matrixCfg)
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "matrix_config_resolved.json"), matrixCfg);
sixgr.lls6g.config.writeYAML(fullfile(layout.MetaDir, "matrix_config_resolved.yaml"), matrixCfg);
srcT = table(localPortablePath(configPath), 'VariableNames', {'SourceConfigFile'});
sixgr.util.csvWriteTable(fullfile(layout.MetaDir, "matrix_source_chain.csv"), srcT);
end

function [codeVersion, detail] = localDetectCodeVersion()
repoRoot = localRepoRoot();
codeVersion = "unknown";
detail = "git_unavailable";
cmdHash = sprintf('git -C "%s" rev-parse --short HEAD', repoRoot);
[s1, out1] = system(cmdHash);
if s1 ~= 0
    return;
end
hash = strtrim(out1);
cmdBranch = sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot);
[~, out2] = system(cmdBranch);
branch = strtrim(out2);
codeVersion = "git:" + string(hash);
detail = "branch=" + string(branch) + "; hash=" + string(hash);
end

function pathOut = localResolveScenarioPath(matrixConfigPath, scenarioPath)
scenarioPath = char(string(scenarioPath));
if exist(scenarioPath, "file") == 2
    pathOut = scenarioPath;
    return;
end
baseDir = fileparts(char(string(matrixConfigPath)));
candidate = fullfile(baseDir, scenarioPath);
if exist(candidate, "file") == 2
    pathOut = candidate;
    return;
end
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
candidate = fullfile(root, scenarioPath);
if exist(candidate, "file") == 2
    pathOut = candidate;
    return;
end
error("sixgr:lls6g:runner:MatrixScenarioNotFound", ...
    "Unable to resolve matrix scenario '%s'.", string(scenarioPath));
end

function leaf = localResolveLeaf(runTag)
runTag = char(string(runTag));
if strlength(string(runTag)) == 0
    leaf = "current";
else
    leaf = lower(regexprep(runTag, '[^a-zA-Z0-9]+', '_'));
end
end

function p = localPortablePath(inPath)
p = replace(string(inPath), "\", "/");
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function [scenarioCsv, pointCsv, suiteCsv, baselineScenarioCsv, openStudyScenarioCsv, baselinePointCsv, openStudyPointCsv] = localWriteMatrixAggregateReports(layout, matrixID, summaryT)
scenarioT = localBuildMatrixScenarioSummary(summaryT);
pointT = localBuildMatrixPointSummary(summaryT);
suiteT = localBuildMatrixSuiteSummary(matrixID, scenarioT, pointT);

scenarioCsv = fullfile(layout.ReportCSVDir, "matrix_scenario_summary.csv");
pointCsv = fullfile(layout.ReportCSVDir, "matrix_point_summary.csv");
suiteCsv = fullfile(layout.ReportCSVDir, "matrix_suite_summary.csv");
baselineScenarioCsv = fullfile(layout.ReportCSVDir, "matrix_baseline_scenarios.csv");
openStudyScenarioCsv = fullfile(layout.ReportCSVDir, "matrix_open_study_scenarios.csv");
baselinePointCsv = fullfile(layout.ReportCSVDir, "matrix_baseline_points.csv");
openStudyPointCsv = fullfile(layout.ReportCSVDir, "matrix_open_study_points.csv");

sixgr.util.csvWriteTable(scenarioCsv, scenarioT);
sixgr.util.csvWriteTable(pointCsv, pointT);
sixgr.util.csvWriteTable(suiteCsv, suiteT);
sixgr.util.csvWriteTable(baselineScenarioCsv, localFilterStudyBucket(scenarioT, "baseline"));
sixgr.util.csvWriteTable(openStudyScenarioCsv, localFilterStudyBucket(scenarioT, "open_study"));
sixgr.util.csvWriteTable(baselinePointCsv, localFilterStudyBucket(pointT, "baseline"));
sixgr.util.csvWriteTable(openStudyPointCsv, localFilterStudyBucket(pointT, "open_study"));
end

function T = localBuildMatrixScenarioSummary(summaryT)
rows = repmat(localEmptyScenarioRow(), 0, 1);
for i = 1:height(summaryT)
    runFolder = char(string(summaryT.RunFolder(i)));
    manifest = localReadOptionalJSON(fullfile(runFolder, "meta", "scenario_manifest.json"));
    resolved = localReadOptionalJSON(fullfile(runFolder, "meta", "scenario_config_resolved.json"));
    summaryRow = localReadOptionalSingleRowTable(fullfile(runFolder, "reports", "csv", "scenario_summary.csv"));
    pointCount = localPointCountForScenario(runFolder);
    researchClass = localJsonGet(resolved, "meta.research_class", "");
    studyBucket = localStudyBucket(researchClass);
    [labFlag, labCount, labPaths] = localDetectLabDefaults(resolved);
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "ScenarioID", string(summaryT.ScenarioID(i)), ...
        "ConfigPath", string(summaryT.ConfigPath(i)), ...
        "Repeat", double(summaryT.Repeat(i)), ...
        "RunFolder", localPortablePath(summaryT.RunFolder(i)), ...
        "Ok", logical(summaryT.Ok(i)), ...
        "RunnerProfile", string(localJsonGet(manifest, "RunnerProfile", localTableValue(summaryRow, "RunnerProfile", ""))), ...
        "RunCompletion", string(localJsonGet(manifest, "RunCompletion", localTableValue(summaryRow, "RunCompletion", ""))), ...
        "ResearchClass", string(researchClass), ...
        "StudyBucket", string(studyBucket), ...
        "BaselineReferenceName", string(localJsonGet(resolved, "meta.baseline_reference_name", "")), ...
        "LabDefaultFlag", logical(labFlag), ...
        "LabDefaultCount", double(labCount), ...
        "LabDefaultPaths", string(strjoin(cellstr(labPaths), "|")), ...
        "PointCount", double(pointCount));
end
T = struct2table(rows);
end

function T = localBuildMatrixPointSummary(summaryT)
rows = repmat(localEmptyPointRow(), 0, 1);
for i = 1:height(summaryT)
    parentScenarioID = string(summaryT.ScenarioID(i));
    parentRunFolder = char(string(summaryT.RunFolder(i)));
    parentResolved = localReadOptionalJSON(fullfile(parentRunFolder, "meta", "scenario_config_resolved.json"));
    sweepT = localReadOptionalTable(fullfile(parentRunFolder, "reports", "csv", "sweep_summary.csv"));
    if isempty(sweepT)
        rows(end+1,1) = localMakePointRow(parentScenarioID, "nominal", parentRunFolder, summaryT.Ok(i), parentResolved); %#ok<AGROW>
        continue;
    end
    for k = 1:height(sweepT)
        label = localTableValue(sweepT, "Label", "", k);
        pointFolder = localTableValue(sweepT, "RunFolder", "", k);
        if strlength(pointFolder) == 0
            pointFolder = fullfile(parentRunFolder, "sweeps", char(label));
        end
        pointOk = localTableValue(sweepT, "Ok", false, k);
        pointResolved = localReadOptionalJSON(fullfile(char(pointFolder), "meta", "scenario_config_resolved.json"));
        if isempty(fieldnames(pointResolved))
            pointResolved = parentResolved;
        end
        rows(end+1,1) = localMakePointRow(parentScenarioID, label, char(pointFolder), pointOk, pointResolved); %#ok<AGROW>
    end
end
T = struct2table(rows);
end

function row = localMakePointRow(parentScenarioID, pointLabel, pointFolder, pointOk, resolved)
manifest = localReadOptionalJSON(fullfile(pointFolder, "meta", "scenario_manifest.json"));
researchClass = localJsonGet(resolved, "meta.research_class", "");
studyBucket = localStudyBucket(researchClass);
[labFlag, labCount, labPaths] = localDetectLabDefaults(resolved);
row = localEmptyPointRow();
row.ParentScenarioID = string(parentScenarioID);
row.PointLabel = string(pointLabel);
row.PointRunFolder = localPortablePath(pointFolder);
row.Ok = logical(pointOk);
row.PointScenarioID = string(localJsonGet(manifest, "ScenarioID", parentScenarioID));
row.RunnerProfile = string(localJsonGet(manifest, "RunnerProfile", ""));
row.RunCompletion = string(localJsonGet(manifest, "RunCompletion", ""));
row.ResearchClass = string(researchClass);
row.StudyBucket = string(studyBucket);
row.BaselineReferenceName = string(localJsonGet(resolved, "meta.baseline_reference_name", ""));
row.LabDefaultFlag = logical(labFlag);
row.LabDefaultCount = double(labCount);
row.LabDefaultPaths = string(strjoin(cellstr(labPaths), "|"));
end

function T = localBuildMatrixSuiteSummary(matrixID, scenarioT, pointT)
T = table( ...
    string(matrixID), ...
    double(height(scenarioT)), ...
    double(sum(logical(scenarioT.Ok))), ...
    double(height(pointT)), ...
    double(sum(logical(pointT.Ok))), ...
    double(sum(string(scenarioT.StudyBucket) == "baseline")), ...
    double(sum(string(scenarioT.StudyBucket) == "open_study")), ...
    double(sum(string(pointT.StudyBucket) == "baseline")), ...
    double(sum(string(pointT.StudyBucket) == "open_study")), ...
    double(sum(logical(scenarioT.LabDefaultFlag))), ...
    double(sum(logical(pointT.LabDefaultFlag))), ...
    string(localMatrixCompletion(table(logical(scenarioT.Ok), 'VariableNames', {'Ok'}))), ...
    'VariableNames', {'MatrixID','ScenarioCount','ScenarioOkCount','PointCount','PointOkCount', ...
    'BaselineScenarioCount','OpenStudyScenarioCount','BaselinePointCount','OpenStudyPointCount', ...
    'LabDefaultScenarioCount','LabDefaultPointCount','RunCompletion'});
end

function T = localFilterStudyBucket(Tin, bucket)
if isempty(Tin)
    T = Tin;
    return;
end
T = Tin(string(Tin.StudyBucket) == string(bucket), :);
end

function row = localEmptyScenarioRow()
row = struct( ...
    "ScenarioID", "", "ConfigPath", "", "Repeat", NaN, "RunFolder", "", "Ok", false, ...
    "RunnerProfile", "", "RunCompletion", "", "ResearchClass", "", "StudyBucket", "", ...
    "BaselineReferenceName", "", "LabDefaultFlag", false, "LabDefaultCount", NaN, ...
    "LabDefaultPaths", "", "PointCount", NaN);
end

function row = localEmptyPointRow()
row = struct( ...
    "ParentScenarioID", "", "PointLabel", "", "PointScenarioID", "", "PointRunFolder", "", ...
    "Ok", false, "RunnerProfile", "", "RunCompletion", "", "ResearchClass", "", ...
    "StudyBucket", "", "BaselineReferenceName", "", "LabDefaultFlag", false, ...
    "LabDefaultCount", NaN, "LabDefaultPaths", "");
end

function n = localPointCountForScenario(runFolder)
sweepT = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "sweep_summary.csv"));
if isempty(sweepT)
    n = 1;
else
    n = height(sweepT);
end
end

function s = localReadOptionalJSON(pathStr)
s = struct();
if exist(pathStr, "file") ~= 2
    return;
end
try
    s = jsondecode(fileread(pathStr));
catch
    s = struct();
end
end

function T = localReadOptionalTable(pathStr)
T = table();
if exist(pathStr, "file") ~= 2
    return;
end
try
    T = readtable(pathStr, 'Delimiter', ',', 'ReadVariableNames', true, ...
        'VariableNamingRule', 'preserve');
catch
    T = table();
end
end

function T = localReadOptionalSingleRowTable(pathStr)
T = localReadOptionalTable(pathStr);
if ~isempty(T) && height(T) > 1
    T = T(1, :);
end
end

function value = localTableValue(T, varName, defaultValue, rowIdx)
if nargin < 4
    rowIdx = 1;
end
value = defaultValue;
if isempty(T) || ~ismember(varName, T.Properties.VariableNames) || height(T) < rowIdx
    return;
end
raw = T.(varName)(rowIdx);
if iscell(raw)
    value = raw{1};
else
    value = raw;
end
end

function value = localJsonGet(s, pathStr, defaultValue)
value = defaultValue;
if isempty(fieldnames(s))
    return;
end
parts = split(string(pathStr), ".");
cur = s;
for i = 1:numel(parts)
    key = char(parts(i));
    if ~(isstruct(cur) && isfield(cur, key))
        return;
    end
    cur = cur.(key);
end
if isstring(cur) || ischar(cur) || islogical(cur) || isnumeric(cur)
    value = cur;
else
    value = defaultValue;
end
end

function bucket = localStudyBucket(researchClass)
researchClass = lower(string(researchClass));
if any(researchClass == ["baseline_benchmark", "agreed_starting_point"])
    bucket = "baseline";
elseif any(researchClass == ["study_item_candidate", "optional_research_experiment"])
    bucket = "open_study";
else
    bucket = "unclassified";
end
end

function [flag, count, paths] = localDetectLabDefaults(s)
paths = strings(0, 1);
paths = localCollectLabDefaultPaths(s, "", paths);
paths = unique(paths, "stable");
flag = ~isempty(paths);
count = numel(paths);
end

function paths = localCollectLabDefaultPaths(v, prefix, paths)
if isstruct(v)
    if numel(v) > 1
        for j = 1:numel(v)
            if strlength(prefix) == 0
                nextPrefix = "(" + string(j) + ")";
            else
                nextPrefix = prefix + "(" + string(j) + ")";
            end
            paths = localCollectLabDefaultPaths(v(j), nextPrefix, paths);
        end
        return;
    end
    names = fieldnames(v);
    for i = 1:numel(names)
        key = string(names{i});
        if strlength(prefix) == 0
            nextPrefix = key;
        else
            nextPrefix = prefix + "." + key;
        end
        paths = localCollectLabDefaultPaths(v.(names{i}), nextPrefix, paths);
    end
elseif iscell(v)
    for i = 1:numel(v)
        nextPrefix = prefix + "{" + string(i) + "}";
        paths = localCollectLabDefaultPaths(v{i}, nextPrefix, paths);
    end
elseif isstring(v)
    for i = 1:numel(v)
        if lower(strtrim(v(i))) == "lab_default"
            if numel(v) == 1
                paths(end+1,1) = prefix; %#ok<AGROW>
            else
                paths(end+1,1) = prefix + "(" + string(i) + ")"; %#ok<AGROW>
            end
        end
    end
elseif ischar(v)
    if lower(string(strtrim(v))) == "lab_default"
        paths(end+1,1) = prefix; %#ok<AGROW>
    end
end
end
