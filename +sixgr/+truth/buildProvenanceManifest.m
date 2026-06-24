function manifest = buildProvenanceManifest(scenarioCfg, runDir)
%BUILDPROVENANCEMANIFEST Complete scenario manifest provenance fields.
%
% The runner's canonical manifest lives in meta/scenario_manifest.json. This
% helper preserves that file and mirrors an enriched copy to reports/json for
% auditors that expect all report-facing JSON under reports/json.

arguments
    scenarioCfg = struct()
    runDir {mustBeTextScalar} = pwd
end

layout = sixgr.report.resultLayout(runDir);
reportJsonDir = fullfile(layout.ReportDir, "json");
sixgr.util.ensureFolder(reportJsonDir);
sixgr.util.ensureFolder(layout.MetaDir);

metaPath = fullfile(layout.MetaDir, "scenario_manifest.json");
if exist(metaPath, "file") == 2
    try
        manifest = sixgr.util.jsonRead(metaPath);
    catch
        manifest = struct();
    end
else
    manifest = struct();
end

cfgInfo = localConfigInfo(scenarioCfg);
gitInfo = localGitInfo(localRepoRoot());
existingOverlay = string(sixgr.util.structGet(manifest, "ConfigOverlay", ""));
existingOverlayPath = string(sixgr.util.structGet(manifest, "ConfigOverlayPath", ""));
existingSourceFiles = string(sixgr.util.structGet(manifest, "SourceFiles", strings(0, 1)));
if isempty(cfgInfo.SourceFiles) && ~isempty(existingSourceFiles)
    cfgInfo.SourceFiles = existingSourceFiles(:);
end
if cfgInfo.ConfigOverlay == "none_detected" && ~isempty(existingOverlay) && strlength(strtrim(existingOverlay(1))) > 0
    cfgInfo.ConfigOverlay = existingOverlay(1);
end
if strlength(strtrim(cfgInfo.ConfigOverlayPath)) == 0 && ~isempty(existingOverlayPath) && strlength(strtrim(existingOverlayPath(1))) > 0
    cfgInfo.ConfigOverlayPath = existingOverlayPath(1);
end

manifest.GeneratedUTC = char(string(sixgr.util.structGet(manifest, "GeneratedUTC", sixgr.util.utcNowISO8601())));
manifest.ScenarioID = char(string(localFirstNonempty( ...
    string(sixgr.util.structGet(manifest, "ScenarioID", "")), cfgInfo.ScenarioID)));
manifest.ConfigPath = char(string(localFirstNonempty( ...
    string(sixgr.util.structGet(manifest, "ConfigPath", "")), cfgInfo.ConfigPath)));
manifest.ScenarioYAML = char(string(localFirstNonempty( ...
    string(sixgr.util.structGet(manifest, "ScenarioYAML", "")), cfgInfo.ConfigPath)));
manifest.ConfigOverlay = char(string(cfgInfo.ConfigOverlay));
manifest.ConfigOverlayPath = char(string(cfgInfo.ConfigOverlayPath));
manifest.ConfigHash = char(string(localFirstNonempty( ...
    string(sixgr.util.structGet(manifest, "ConfigHash", "")), cfgInfo.ConfigHash)));
manifest.SourceFiles = cellstr(cfgInfo.SourceFiles(:));
manifest.SourceFileCount = numel(cfgInfo.SourceFiles);
manifest.GitCommit = char(string(gitInfo.Commit));
manifest.GitBranch = char(string(gitInfo.Branch));
manifest.GitDirty = logical(gitInfo.Dirty);
manifest.GitStatusSource = char(string(gitInfo.StatusSource));
manifest.ProvenanceManifestPath = "reports/json/scenario_manifest.json";
manifest.MetaManifestPath = "meta/scenario_manifest.json";

sixgr.util.jsonWrite(metaPath, manifest);
sixgr.util.jsonWrite(fullfile(reportJsonDir, "scenario_manifest.json"), manifest);
end

function info = localConfigInfo(cfg)
info = struct("ScenarioID", "", "ConfigPath", "", "ConfigHash", "", ...
    "SourceFiles", strings(0, 1), "ConfigOverlay", "none_detected", "ConfigOverlayPath", "");
try
    if isa(cfg, "sixgr.lls6g.config.ScenarioConfig")
        info.ScenarioID = string(cfg.ScenarioID);
        info.ConfigPath = string(cfg.ConfigPath);
        info.ConfigHash = string(cfg.ConfigHash);
        info.SourceFiles = string(cfg.SourceFiles(:));
    elseif isstruct(cfg)
        info.ScenarioID = string(sixgr.util.structGet(cfg, "meta.scenario_id", ...
            sixgr.util.structGet(cfg, "ScenarioID", "")));
        info.ConfigPath = string(sixgr.util.structGet(cfg, "ConfigPath", ...
            sixgr.util.structGet(cfg, "meta.config_path", "")));
        info.ConfigHash = string(sixgr.util.structGet(cfg, "ConfigHash", ...
            sixgr.util.structGet(cfg, "meta.config_hash", "")));
        info.SourceFiles = string(sixgr.util.structGet(cfg, "SourceFiles", strings(0, 1)));
        info.SourceFiles = info.SourceFiles(:);
    end
catch
end
overlay = localDetectOverlay(info.ConfigPath, info.SourceFiles);
if strlength(overlay) > 0
    info.ConfigOverlay = overlay;
    info.ConfigOverlayPath = overlay;
end
if isempty(info.SourceFiles) && strlength(info.ConfigPath) > 0
    info.SourceFiles = info.ConfigPath;
end
end

function overlay = localDetectOverlay(configPath, sourceFiles)
paths = [string(configPath); string(sourceFiles(:))];
overlay = "";
for i = 1:numel(paths)
    p = paths(i);
    token = lower(p);
    if strlength(strtrim(p)) > 0 && (contains(token, "overlay") || contains(token, "browser_runtime"))
        overlay = p;
        return;
    end
end
end

function gitInfo = localGitInfo(repoRoot)
gitInfo = struct("Commit", "unavailable", "Branch", "unavailable", "Dirty", false, "StatusSource", "git_unavailable");
[s1, out1] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
if s1 ~= 0
    return;
end
gitInfo.Commit = string(strtrim(out1));
[s2, out2] = system(sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot));
if s2 == 0
    gitInfo.Branch = string(strtrim(out2));
end
[s3, out3] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
if s3 == 0
    gitInfo.Dirty = strlength(strtrim(string(out3))) > 0;
    gitInfo.StatusSource = "git_status_porcelain";
else
    gitInfo.StatusSource = "git_commit_only";
end
end

function out = localFirstNonempty(varargin)
out = "";
for i = 1:nargin
    v = string(varargin{i});
    if ~isempty(v) && strlength(strtrim(v(1))) > 0
        out = v(1);
        return;
    end
end
end

function repoRoot = localRepoRoot()
truthDir = fileparts(mfilename("fullpath"));
pkgDir = fileparts(truthDir);
repoRoot = fileparts(pkgDir);
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:truth:buildProvenanceManifest:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
