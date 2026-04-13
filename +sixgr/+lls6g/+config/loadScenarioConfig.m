function scfg = loadScenarioConfig(configPath)
%LOADSCENARIOCONFIG Resolve layered config inheritance into ScenarioConfig.

configPath = localResolvePath(configPath);
[resolved, chain] = localResolveConfigTree(configPath, strings(0,1));
resolved = sixgr.lls6g.config.normalizeScenarioAliases(resolved, ...
    "SourceFiles", chain, "ConfigPath", configPath);
sixgr.lls6g.config.validateScenarioConfig(resolved, ...
    "Kind", "scenario", "AllowPartial", false, "Context", configPath);
cfgHash = localComputeConfigHash(resolved);
scfg = sixgr.lls6g.config.ScenarioConfig(resolved, ...
    "SourceFiles", chain, ...
    "ConfigPath", configPath, ...
    "ConfigHash", cfgHash, ...
    "Kind", "scenario");
end

function [merged, chain] = localResolveConfigTree(configPath, chain)
raw = sixgr.lls6g.config.readConfigFile(configPath);
sixgr.lls6g.config.validateScenarioConfig(raw, ...
    "Kind", "scenario", "AllowPartial", true, "Context", configPath);

inherits = string(sixgr.util.structGet(raw, "inherits", strings(0,1)));
if ischar(inherits)
    inherits = string({inherits});
end

merged = struct();
for i = 1:numel(inherits)
    parentPath = localResolveRelativeConfig(configPath, inherits(i));
    [parentCfg, chain] = localResolveConfigTree(parentPath, chain);
    merged = sixgr.util.mergeStruct(merged, parentCfg);
end

if isfield(raw, "inherits")
    raw = rmfield(raw, "inherits");
end
merged = sixgr.util.mergeStruct(merged, raw);
chain(end+1,1) = string(configPath); %#ok<AGROW>
end

function cfgHash = localComputeConfigHash(cfg)
txt = jsonencode(cfg);
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(uint8(txt));
    d = typecast(md.digest(), "uint8");
    cfgHash = lower(reshape(dec2hex(d, 2).', 1, []));
catch
    cfgHash = "fallback_" + string(sum(double(uint8(txt))));
end
cfgHash = char(string(cfgHash));
end

function resolved = localResolveRelativeConfig(baseFile, relativePath)
relativePath = char(string(relativePath));
if exist(relativePath, "file") == 2
    resolved = relativePath;
    return;
end
baseDir = fileparts(char(string(baseFile)));
candidate = fullfile(baseDir, relativePath);
if exist(candidate, "file") == 2
    resolved = candidate;
    return;
end
root = localRepoRoot();
candidate = fullfile(root, relativePath);
if exist(candidate, "file") == 2
    resolved = candidate;
    return;
end
error("sixgr:lls6g:config:InheritedConfigNotFound", ...
    "Unable to resolve inherited config '%s' from '%s'.", relativePath, string(baseFile));
end

function p = localResolvePath(configPath)
if exist(char(string(configPath)), "file") == 2
    p = char(string(configPath));
    return;
end
root = localRepoRoot();
candidate = fullfile(root, char(string(configPath)));
if exist(candidate, "file") == 2
    p = candidate;
    return;
end
error("sixgr:lls6g:config:ConfigNotFound", ...
    "Scenario config not found: %s", string(configPath));
end

function out = localRepoRoot()
here = fileparts(mfilename("fullpath"));
out = fileparts(fileparts(fileparts(here)));
end
