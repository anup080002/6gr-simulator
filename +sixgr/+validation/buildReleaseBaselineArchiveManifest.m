function out = buildReleaseBaselineArchiveManifest(runFolder, cfg, varargin)
%BUILDRELEASEBASELINEARCHIVEMANIFEST Build reproducibility archive metadata.
% This records source/config/environment/seed/artifact provenance. It never
% fabricates missing artifacts or converts unrun acceptance gates into passes.

if nargin < 1 || strlength(string(runFolder)) == 0
    runFolder = tempname;
end
if nargin < 2 || isempty(cfg)
    cfg = struct();
end

p = inputParser;
p.addParameter("WriteArtifacts", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ScenarioMatrixPath", fullfile(pwd, "simulator", "configs", "scenarios", "release_acceptance_matrix.yaml"), @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("TaskPlan", table(), @(x) istable(x) || isempty(x));
p.addParameter("PrimaryArtifacts", strings(0, 1), @(x) isstring(x) || ischar(x) || iscellstr(x));
p.addParameter("AcceptanceResults", table(), @(x) istable(x) || isempty(x));
p.parse(varargin{:});
opt = p.Results;

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
artifactInventory = localBuildArtifactInventory(runFolder, string(opt.PrimaryArtifacts));
taskPlan = opt.TaskPlan;
taskPlanHash = localTableHash(taskPlan);
cfgHash = localConfigHash(cfg);
gitInfo = localGitInfo();
environment = localEnvironmentSummary();
acceptance = localAcceptanceSummary(opt.AcceptanceResults);
matrixPath = string(opt.ScenarioMatrixPath);

manifest = struct();
manifest.ManifestKind = "release_baseline_archive";
manifest.SchemaVersion = "1.0";
manifest.CreatedUTC = char(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
manifest.ConfigHash = char(cfgHash);
manifest.Git = gitInfo;
manifest.Environment = environment;
manifest.ScenarioMatrixPath = char(localRelativePath(pwd, matrixPath));
manifest.ScenarioMatrixSHA256 = char(localFileHash(matrixPath));
manifest.SeedHierarchy = struct( ...
    "TaskPlanHash", char(taskPlanHash), ...
    "TaskCount", double(height(taskPlan)), ...
    "SeedSource", "sixgr.util.buildDeterministicTaskPlan/sixgr.util.hierarchicalSeed");
manifest.PrimaryArtifactCount = double(height(artifactInventory));
manifest.PrimaryArtifactsPresent = double(sum(logical(artifactInventory.Exists)));
manifest.PrimaryArtifactsMissing = double(sum(~logical(artifactInventory.Exists)));
manifest.Acceptance = acceptance;
manifest.FailureFreeManifestRequired = true;
manifest.FailureFreeManifestStatus = acceptance.Status;
manifest.NoSyntheticArchiveRows = true;
manifest.PrimaryArtifactInventory = table2struct(artifactInventory);

out = struct();
out.Manifest = manifest;
out.ArtifactInventory = artifactInventory;
out.ManifestJSON = string(fullfile(layout.MetaDir, "release_baseline_archive_manifest.json"));
out.ArtifactInventoryCSV = string(fullfile(layout.ReportCSVDir, "release_baseline_archive_artifacts.csv"));
out.ConfigHash = cfgHash;
out.TaskPlanHash = taskPlanHash;
out.Git = gitInfo;
out.Environment = environment;
out.Acceptance = acceptance;

if logical(opt.WriteArtifacts)
    sixgr.util.ensureDir(out.ManifestJSON);
    sixgr.util.ensureDir(out.ArtifactInventoryCSV);
    sixgr.util.jsonWrite(out.ManifestJSON, manifest);
    sixgr.util.csvWriteTable(out.ArtifactInventoryCSV, artifactInventory);
end
end

function T = localBuildArtifactInventory(runFolder, artifactPaths)
artifactPaths = string(artifactPaths(:));
artifactPaths(strlength(strtrim(artifactPaths)) == 0) = [];
rows = repmat(struct( ...
    "ArtifactPath", "", ...
    "RelativePath", "", ...
    "Exists", false, ...
    "ByteCount", NaN, ...
    "SHA256", "", ...
    "CountsTowardArchive", false, ...
    "ArchiveState", ""), numel(artifactPaths), 1);
for i = 1:numel(artifactPaths)
    path = artifactPaths(i);
    if ~isAbsolutePath(path)
        path = string(fullfile(runFolder, path));
    end
    exists = exist(char(path), "file") == 2;
    bytes = NaN;
    hash = "";
    if exists
        info = dir(char(path));
        bytes = double(info.bytes);
        hash = localFileHash(path);
    end
    rows(i).ArtifactPath = string(path);
    rows(i).RelativePath = localRelativePath(runFolder, path);
    rows(i).Exists = logical(exists);
    rows(i).ByteCount = double(bytes);
    rows(i).SHA256 = string(hash);
    rows(i).CountsTowardArchive = logical(exists);
    rows(i).ArchiveState = string(localTernary(exists, "available_real_artifact", "missing_not_counted"));
end
T = struct2table(rows, "AsArray", true);
end

function tf = isAbsolutePath(path)
path = char(string(path));
tf = ~isempty(regexp(path, "^[A-Za-z]:[\\/]", "once")) || startsWith(path, "\\") || startsWith(path, "/");
end

function hash = localConfigHash(cfg)
try
    payload = jsonencode(cfg);
catch
    payload = char(string(cfg));
end
hash = sixgr.util.sha256Hex(payload);
end

function hash = localTableHash(T)
if ~(istable(T) && ~isempty(T))
    hash = sixgr.util.sha256Hex("empty_table");
    return;
end
try
    payload = jsonencode(table2struct(T));
catch
    payload = strjoin(string(T.Properties.VariableNames), "|") + "|height=" + string(height(T));
end
hash = sixgr.util.sha256Hex(payload);
end

function hash = localFileHash(path)
path = string(path);
if exist(char(path), "file") ~= 2
    hash = "";
    return;
end
fid = fopen(char(path), "r");
if fid < 0
    hash = "";
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8");
hash = sixgr.util.sha256Hex(bytes);
end

function gitInfo = localGitInfo()
gitInfo = struct("Commit", "", "Branch", "", "Dirty", true, "StatusSource", "git_unavailable");
[okCommit, commit] = localSystemText("git rev-parse HEAD");
[okBranch, branch] = localSystemText("git branch --show-current");
[okStatus, statusText] = localSystemText("git status --porcelain");
if okCommit
    gitInfo.Commit = char(commit);
    gitInfo.StatusSource = "git_cli";
end
if okBranch
    gitInfo.Branch = char(branch);
end
if okStatus
    gitInfo.Dirty = strlength(strtrim(statusText)) > 0;
end
end

function [ok, text] = localSystemText(cmd)
ok = false;
text = "";
try
    [status, raw] = system(cmd);
    ok = status == 0;
    if ok
        text = strtrim(string(raw));
    end
catch
    ok = false;
end
end

function env = localEnvironmentSummary()
env = struct();
env.MATLABVersion = char(string(version));
env.MATLABRelease = char(string(version("-release")));
env.Platform = char(string(computer));
env.Hostname = char(string(getenv("COMPUTERNAME")));
tbx = ver("5G Toolbox");
if isempty(tbx)
    env.FiveGToolboxVersion = "not_reported";
else
    env.FiveGToolboxVersion = char(string(tbx(1).Version));
end
end

function summary = localAcceptanceSummary(results)
summary = struct("Status", "requires_acceptance_suite_results", ...
    "PassedCount", 0, "FailedCount", 0, "TotalCount", 0, "ResultsHash", "");
if ~(istable(results) && ~isempty(results))
    summary.ResultsHash = char(sixgr.util.sha256Hex("empty_acceptance_results"));
    return;
end
vars = string(results.Properties.VariableNames);
passVar = "";
for candidate = ["Passed", "Pass", "Ok", "ok"]
    if ismember(candidate, vars)
        passVar = candidate;
        break;
    end
end
if strlength(passVar) == 0
    summary.Status = "acceptance_results_missing_pass_column";
    summary.TotalCount = height(results);
    summary.ResultsHash = char(localTableHash(results));
    return;
end
passed = logical(results.(passVar));
summary.PassedCount = double(sum(passed));
summary.FailedCount = double(sum(~passed));
summary.TotalCount = double(height(results));
summary.ResultsHash = char(localTableHash(results));
if all(passed)
    summary.Status = "failure_free";
else
    summary.Status = "has_failures";
end
end

function rel = localRelativePath(root, path)
root = string(root);
path = string(path);
try
    rootAbs = string(java.io.File(char(root)).getCanonicalPath());
    pathAbs = string(java.io.File(char(path)).getCanonicalPath());
catch
    rootAbs = root;
    pathAbs = path;
end
if startsWith(lower(pathAbs), lower(rootAbs))
    rel = extractAfter(pathAbs, strlength(rootAbs));
    rel = regexprep(rel, "^[\\/]", "");
else
    rel = path;
end
rel = strrep(string(rel), "\", "/");
end

function value = localTernary(cond, a, b)
if cond
    value = a;
else
    value = b;
end
end
