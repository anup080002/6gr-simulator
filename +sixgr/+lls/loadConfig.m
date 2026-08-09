function [cfg, provenance] = loadConfig(configPath)
%LOADCONFIG Load a self-contained waveform LLS YAML/JSON configuration.
%
% The LLS loader deliberately does not invoke the system-scenario
% normalizer.  Core link curves have no topology, scheduler, traffic, or
% geometry authority.  A small inheritance mechanism is retained so that
% diagnostic configurations can reduce only Monte-Carlo budgets while the
% complete PHY operating point remains owned by the reference YAML.

arguments
    configPath (1,1) string
end

resolvedPath = localResolvePath(configPath);
[cfg, sources] = localResolveTree(resolvedPath, strings(0,1));
cfg = sixgr.lls.validateConfig(cfg, "ConfigPath", resolvedPath);
canonical = jsonencode(cfg);
configHash = sixgr.util.sha256Hex(uint8(unicode2native(canonical, "UTF-8")));
provenance = struct( ...
    "ConfigPath", string(resolvedPath), ...
    "SourceFiles", sources, ...
    "ConfigSHA256", string(configHash), ...
    "CanonicalJSON", string(canonical));
end

function [merged, sources] = localResolveTree(configPath, stack)
canonical = string(localResolvePath(configPath));
if any(stack == canonical)
    error("sixgr:lls:ConfigInheritanceCycle", ...
        "LLS configuration inheritance contains a cycle at '%s'.", canonical);
end
raw = sixgr.lls6g.config.readConfigFile(canonical);
parents = string(sixgr.util.structGet(raw, "inherits", strings(0,1)));
parents = parents(:);
merged = struct();
sources = strings(0,1);
for idx = 1:numel(parents)
    parentPath = localResolveParent(canonical, parents(idx));
    [parent, parentSources] = localResolveTree(parentPath, [stack; canonical]);
    merged = sixgr.util.mergeStruct(merged, parent);
    sources = [sources; parentSources]; %#ok<AGROW>
end
if isfield(raw, "inherits")
    raw = rmfield(raw, "inherits");
end
merged = sixgr.util.mergeStruct(merged, raw);
sources = unique([sources; canonical], "stable");
end

function path = localResolveParent(childPath, parent)
candidate = fullfile(fileparts(char(childPath)), char(parent));
if exist(candidate, "file") == 2
    path = localCanonical(candidate);
    return;
end
path = localResolvePath(parent);
end

function path = localResolvePath(raw)
raw = char(string(raw));
if exist(raw, "file") == 2
    path = localCanonical(raw);
    return;
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
candidate = fullfile(root, raw);
if exist(candidate, "file") == 2
    path = localCanonical(candidate);
    return;
end
error("sixgr:lls:ConfigNotFound", "LLS configuration not found: %s", raw);
end

function path = localCanonical(path)
path = char(java.io.File(char(string(path))).getCanonicalPath());
end
