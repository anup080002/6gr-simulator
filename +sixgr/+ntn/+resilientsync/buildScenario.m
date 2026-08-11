function scenario = buildScenario(configPath)
%BUILDSCENARIO Resolve the resilient NTN campaign and state-profile YAML.

arguments
    configPath (1,1) string
end

root = localRepoRoot();
resolvedPath = localResolveFile(configPath, root, "sixgr:ntn:resilientsync:ConfigNotFound");
[scenario, sources] = localResolveTree(resolvedPath, strings(0,1), root);
scenario.carriers = localStructSequence(scenario.carriers,"carriers");
scenario.ConfigPath = string(resolvedPath);
scenario.ConfigSourceFiles = sources;

statePath = string(sixgr.util.structGet(scenario, "state_profiles.file", ""));
statePath = localResolveFile(statePath, root, "sixgr:ntn:resilientsync:StateProfilesNotFound");
stateDoc = sixgr.lls6g.config.readConfigFile(statePath);
scenario.StateProfilesPath = string(statePath);
scenario.StateProfiles = sixgr.ntn.resilientsync.state.buildCompensationStateProfile( ...
    stateDoc, string(scenario.state_profiles.enabled));

scenario = sixgr.ntn.resilientsync.validateScenario(scenario);
hashInput = scenario;
for field = ["ConfigSHA256","StateProfileSHA256"]
    if isfield(hashInput,field)
        hashInput=rmfield(hashInput,char(field));
    end
end
scenario.ConfigSHA256 = sixgr.util.sha256Hex(unicode2native(jsonencode(hashInput), "UTF-8"));
scenario.StateProfileSHA256 = sixgr.util.sha256Hex(uint8(fileread(statePath)));
end

function values=localStructSequence(raw,path)
if isstruct(raw)
    values=raw(:);return;
end
if iscell(raw) && all(cellfun(@isstruct,raw))
    names=string.empty(1,0);
    for index=1:numel(raw)
        names=union(names,string(fieldnames(raw{index})).','stable');
    end
    normalized=cell(size(raw));
    for index=1:numel(raw)
        value=raw{index};
        for field=names
            if ~isfield(value,char(field)),value.(char(field))=[];end
        end
        normalized{index}=orderfields(value,cellstr(names));
    end
    values=vertcat(normalized{:});return;
end
error("sixgr:ntn:resilientsync:InvalidConfigSequence", ...
    "%s must be a YAML sequence of mappings.",path);
end

function [merged, sources] = localResolveTree(path, stack, root)
path = string(path);
if any(stack == path)
    error("sixgr:ntn:resilientsync:ConfigInheritanceCycle", ...
        "Configuration inheritance cycle at %s.", char(path));
end
raw = sixgr.lls6g.config.readConfigFile(path);
parents = string(sixgr.util.structGet(raw, "inherits", strings(0,1)));
parents = parents(:);
merged = struct();
sources = strings(0,1);
for index = 1:numel(parents)
    candidate = fullfile(fileparts(char(path)), char(parents(index)));
    if exist(candidate, "file") ~= 2
        candidate = fullfile(root, char(parents(index)));
    end
    parentPath = localResolveFile(string(candidate), root, ...
        "sixgr:ntn:resilientsync:InheritedConfigNotFound");
    [parent, parentSources] = localResolveTree(parentPath, [stack; path], root);
    merged = sixgr.util.mergeStruct(merged, parent);
    sources = [sources; parentSources]; %#ok<AGROW>
end
if isfield(raw, "inherits")
    raw = rmfield(raw, "inherits");
end
merged = sixgr.util.mergeStruct(merged, raw);
sources = unique([sources; path], "stable");
end

function path = localResolveFile(raw, root, errorId)
candidate = char(string(raw));
% exist(relative,'file') searches the MATLAB path, while Java canonicalizes
% relative text against pwd.  Mixing those behaviours made class tests
% resolve a repository config under their temporary working directory.
if ~java.io.File(candidate).isAbsolute()
    candidate = fullfile(root, candidate);
end
if exist(candidate, "file") ~= 2
    error(errorId, "Required configuration file does not exist: %s", char(string(raw)));
end
path = char(java.io.File(candidate).getCanonicalPath());
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
% +sixgr/+ntn/+resilientsync is three levels below the repository root.
% Do not use pwd here: matlab.unittest temporarily changes the working
% directory while class-based tests execute.
root = fileparts(fileparts(fileparts(here)));
end
