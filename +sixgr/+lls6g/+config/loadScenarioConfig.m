function scfg = loadScenarioConfig(configPath)
%LOADSCENARIOCONFIG Resolve layered config inheritance into ScenarioConfig.

configPath = localResolvePath(configPath);
[resolved, chain, leafAuthority] = localResolveConfigTree(configPath, strings(0,1));
% Preserve last-writer authority across legacy/modern alias pairs.  The
% merged tree alone cannot distinguish a child-authored value from an
% inherited alias, so an inherited nested true could otherwise reverse a
% leaf flat false during normalization.
resolved = sixgr.lls6g.config.normalizeScenarioAliases(resolved, ...
    "SourceFiles", chain, "ConfigPath", configPath, ...
    "Authority", leafAuthority);
sixgr.lls6g.config.validateScenarioConfig(resolved, ...
    "Kind", "scenario", "AllowPartial", false, "Context", configPath);
cfgHash = sixgr.lls6g.config.hashResolvedScenario(resolved);
scfg = sixgr.lls6g.config.ScenarioConfig(resolved, ...
    "SourceFiles", chain, ...
    "ConfigPath", configPath, ...
    "ConfigHash", cfgHash, ...
    "Kind", "scenario");
end

function [merged, chain, authority] = localResolveConfigTree(configPath, chain)
raw = sixgr.lls6g.config.readConfigFile(configPath);
sixgr.lls6g.config.validateScenarioConfig(raw, ...
    "Kind", "scenario", "AllowPartial", true, "Context", configPath);

inherits = string(sixgr.util.structGet(raw, "inherits", strings(0,1)));
if ischar(inherits)
    inherits = string({inherits});
end

merged = struct();
parentAuthority = struct();
for i = 1:numel(inherits)
    parentPath = localResolveRelativeConfig(configPath, inherits(i));
    [parentCfg, chain, parentAuthority] = localResolveConfigTree(parentPath, chain);
    merged = sixgr.util.mergeStruct(merged, parentCfg);
end

if isfield(raw, "inherits")
    raw = rmfield(raw, "inherits");
end
merged = sixgr.util.mergeStruct(merged, raw);
authority = raw;
if numel(inherits)==1 && localOperationalOnly(raw)
    % A checkpoint-only wrapper is not a new scientific author. Retain its
    % parent's alias authority as well as the requested execution controls.
    % Otherwise adding resume_from can revive an older inherited seed (or
    % feature alias) despite making no scientific override. Multi-parent
    % compositions and children with scientific fields retain normal rules.
    authority = sixgr.util.mergeStruct(parentAuthority, raw);
end
chain(end+1,1) = string(configPath); %#ok<AGROW>
end

function tf = localOperationalOnly(raw)
tf = isempty(fieldnames(raw));
if tf, return; end
if ~isequal(fieldnames(raw),{'run_control'}) || ...
        ~isstruct(raw.run_control) || ~isscalar(raw.run_control)
    return;
end
% Use the checkpoint contract's exact exclusion set, not a second whitelist
% which could accidentally hide a scientific field from resume validation.
science = sixgr.runtime.SlotCheckpoint.scientificScenario(raw);
tf = isempty(fieldnames(science.run_control));
end

function resolved = localResolveRelativeConfig(baseFile, relativePath)
relativePath = char(string(relativePath));
relativeFile = java.io.File(relativePath);
if relativeFile.isAbsolute() && exist(relativePath, "file") == 2
    resolved = localCanonicalPath(relativePath);
    return;
end
baseDir = fileparts(char(string(baseFile)));
candidate = fullfile(baseDir, relativePath);
if exist(candidate, "file") == 2
    resolved = localCanonicalPath(candidate);
    return;
end
root = localRepoRoot();
candidate = fullfile(root, relativePath);
if exist(candidate, "file") == 2
    resolved = localCanonicalPath(candidate);
    return;
end
error("sixgr:lls6g:config:InheritedConfigNotFound", ...
    "Unable to resolve inherited config '%s' from '%s'.", relativePath, string(baseFile));
end

function p = localResolvePath(configPath)
configPath = char(string(configPath));
% MATLAB R2026a can return a partial match from which() when an absolute
% Windows path contains spaces.  Resolve an existing absolute path before
% consulting the MATLAB search path.
absoluteFile = java.io.File(configPath);
if absoluteFile.isAbsolute() && exist(configPath, "file") == 2
    p = localCanonicalPath(configPath);
    return;
end
located = which(configPath);
if ~isempty(located) && exist(located, "file") == 2
    p = localCanonicalPath(located);
    return;
end
root = localRepoRoot();
candidate = fullfile(root, configPath);
if exist(candidate, "file") == 2
    p = localCanonicalPath(candidate);
    return;
end
error("sixgr:lls6g:config:ConfigNotFound", ...
    "Scenario config not found: %s", string(configPath));
end

function out = localRepoRoot()
here = fileparts(mfilename("fullpath"));
out = fileparts(fileparts(fileparts(here)));
end

function path = localCanonicalPath(path)
path = char(java.io.File(char(string(path))).getCanonicalPath());
end
