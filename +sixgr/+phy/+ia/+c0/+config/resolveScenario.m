function [cfg,sources] = resolveScenario(sourcePath,runMode)
%RESOLVESCENARIO Resolve C0 IA YAML inheritance and run-mode overlay.
sourcePath = localResolve(sourcePath);
[cfg,sources] = localResolveTree(sourcePath,strings(0,1));
if nargin >= 2 && strlength(strtrim(string(runMode))) > 0
    mode = lower(strtrim(string(runMode)));
    overlay = fullfile(localRepoRoot(),"simulator","configs", ...
        "initial_access","c0","run_modes",mode+".yaml");
    if exist(overlay,"file") ~= 2
        error("sixgr:phy:ia:c0:config:RunModeNotFound", ...
            "IA run-mode overlay does not exist: %s.",overlay);
    end
    cfg = sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile(overlay));
    sources(end+1,1) = string(overlay);
end
end

function [cfg,sources] = localResolveTree(path,sources)
raw = sixgr.lls6g.config.readConfigFile(path);
cfg = struct();
if isfield(raw,"inherits")
    parents = string(raw.inherits);
    for k = 1:numel(parents)
        parent = char(parents(k));
        if ~java.io.File(parent).isAbsolute()
            parent = fullfile(fileparts(path),parent);
        end
        [base,sources] = localResolveTree(localResolve(parent),sources);
        cfg = sixgr.util.mergeStruct(cfg,base);
    end
    raw = rmfield(raw,"inherits");
end
cfg = sixgr.util.mergeStruct(cfg,raw);
sources(end+1,1) = string(path);
end

function path = localResolve(value)
path = char(string(value));
if exist(path,"file") ~= 2
    path = fullfile(localRepoRoot(),path);
end
if exist(path,"file") ~= 2
    error("sixgr:phy:ia:c0:config:ConfigNotFound", ...
        "C0 IA config not found: %s.",value);
end
path = char(java.io.File(path).getCanonicalPath());
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath")))))));
end
