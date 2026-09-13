function tb = setup6GRSimToolkit(varargin)
%SETUP6GRSIMTOOLKIT Add 6GR Sim Studio root to MATLAB path and detect toolboxes.
%
%   tb = setup6GRSimToolkit()
%   tb = setup6GRSimToolkit("AddSubfolders",true|false,"Verbose",true|false)
%
% Notes:
% - Add ONLY the project root (folder containing +sixgr). Do NOT add "+sixgr" itself.
% - Optionally add non-package subfolders (skips +pkg and @class folders).

p = inputParser;
p.addParameter("AddSubfolders", true, @(x)islogical(x) && isscalar(x));
p.addParameter("Verbose", true, @(x)islogical(x) && isscalar(x));
p.addParameter("RunToolboxChecks", [], @(x) isempty(x) || (islogical(x) && isscalar(x)));
p.addParameter("CheckYAMLRuntime", true, @(x)islogical(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

rootDir = fileparts(mfilename("fullpath"));
resultsDir = fullfile(rootDir, "results");
logsDir = fullfile(rootDir, "logs");
doChecks = opt.Verbose;
if ~isempty(opt.RunToolboxChecks)
    doChecks = logical(opt.RunToolboxChecks);
end

persistent cache
if isempty(cache)
    cache = struct("rootDir","", "subfoldersAdded", false, "checks", struct("name",{}, "symbol",{}, "ok",{}));
end

pathChanged = false;

% Keep sibling copies of this toolkit off the active MATLAB path.
pathChanged = localPruneSiblingToolkitRoots(rootDir) || pathChanged;

% Generated result folders are not source code and must stay off the MATLAB path.
pathChanged = localPruneGeneratedTrees(resultsDir) || pathChanged;
% Logs can contain preserved source/patch evidence. Never execute those
% snapshots as current tests or packages, including on cached setup calls.
pathChanged = localPruneGeneratedTrees(logsDir) || pathChanged;

% Add root
if ~contains(path, rootDir)
    addpath(rootDir);
    pathChanged = true;
end

% Add non-package subfolders (skip +pkg/@class/.git/config)
if opt.AddSubfolders
    if ~(strcmp(cache.rootDir, rootDir) && cache.subfoldersAdded)
        sub = strsplit(genpath(rootDir), pathsep);
        keep = strings(0,1);
        for i = 1:numel(sub)
            d = string(sub{i});
            if strlength(d)==0
                continue;
            end
            if localPathIsUnder(d, resultsDir) || localPathIsUnder(d, logsDir)
                continue;
            end
            if contains(d, filesep + "+") || contains(d, filesep + "@")
                continue;
            end
            if endsWith(d, filesep + "config") || contains(d, filesep + ".git")
                continue;
            end
            keep(end+1,1) = d; %#ok<AGROW>
        end
        if ~isempty(keep)
            addpath(strjoin(keep, pathsep));
            pathChanged = true;
        end
        cache.rootDir = rootDir;
        cache.subfoldersAdded = true;
    end
end

if pathChanged
    rehash toolboxcache;
end

if opt.Verbose
    fprintf("[setup] Added paths under: %s\n", rootDir);
end

% Toolbox/capability detection (function-availability based; no license checks)
tb = struct();
tb.rootDir = rootDir;
tb.yaml = struct();

checks = { ...
    "5G Toolbox", "nrOFDMInfo", "file"; ...
    "5G Toolbox", "nrPUSCH", "file"; ...
    "5G Toolbox", "nrPDSCH", "file"; ...
    "5G Toolbox", "nrLDPCEncode", "file"; ...
    "5G Toolbox", "nrRateRecoverLDPC", "file"; ...
    "COMM Toolbox", "awgn", "file"; ...
    "DL Toolbox", "trainNetwork", "file"; ...
    "PCT", "parpool", "file"; ...
    "PHASED", "phased.URA", "class"; ...
    % Wireless Network Simulation Library uses a class with static init() in current releases
    "WNS Lib", "wirelessNetworkSimulator", "any"; ...
    % Site Viewer is a constructor returning a siteviewer object
    "Site Viewer", "siteviewer", "any"; ...
    "RF Prop", "txsite", "file"; ...
    "5G Toolbox", "nrPathLoss", "file" ...
    };

rows = size(checks,1);
if doChecks
    tb.checks = repmat(struct("name","", "symbol","", "ok",false), rows, 1);
else
    tb.checks = cache.checks;
end

if doChecks
    for r = 1:rows
        name = string(checks{r,1});
        sym  = string(checks{r,2});
        typ  = string(checks{r,3});
        ok = localSymbolExists(sym, typ);

        tb.checks(r).name = char(name);
        tb.checks(r).symbol = char(sym);
        tb.checks(r).ok = ok;

        if opt.Verbose
            tag = "MISS";
            if ok, tag = "OK  "; end
            fprintf("[setup] %s: %-28s (%s)\n", tag, name, sym);
        end
    end
    cache.checks = tb.checks;
end

if opt.Verbose
    if ~doChecks
        fprintf("[setup] Toolbox checks skipped (RunToolboxChecks=false).\n");
    end
    if logical(opt.CheckYAMLRuntime) && exist("sixgr.lls6g.config.ensureYAMLRuntime", "file") == 2
        try
            tb.yaml = sixgr.lls6g.config.ensureYAMLRuntime("Verbose", true, "RequireYAML", false, "ConfigurePyEnv", true);
        catch ME
            tb.yaml = struct("Status", "error", "Message", char(string(ME.message)));
            fprintf("[setup] YAML runtime: error      %s\n", ME.message);
        end
    else
        tb.yaml = struct();
    end
    fprintf("[setup] Done.\n");
end

end

function ok = localSymbolExists(sym, typ)
% Return true if sym exists (file/builtin/class). typ: file|class|any
ok = false;
try
    sym = char(sym);

    fileOK = any(exist(sym,"file") == [2 3 5 6]);
    classOK = (exist(sym,"class") == 8);

    if strcmpi(typ,"file")
        ok = fileOK;
    elseif strcmpi(typ,"class")
        ok = classOK;
    else
        ok = fileOK || classOK;
    end
catch
    ok = false;
end
end

function changed = localPruneGeneratedTrees(resultsDir)
changed = false;
resultsDir = char(string(resultsDir));
if strlength(string(resultsDir)) == 0 || ~isfolder(resultsDir)
    return;
end

pathParts = strsplit(path, pathsep);
pathParts = pathParts(~cellfun(@isempty, pathParts));
toRemove = strings(0,1);
for i = 1:numel(pathParts)
    p = char(string(pathParts{i}));
    if localPathIsUnder(p, resultsDir)
        toRemove(end+1,1) = string(p); %#ok<AGROW>
    end
end
if isempty(toRemove)
    return;
end

try
    rmpath(strjoin(toRemove, pathsep));
    changed = true;
catch
    for i = 1:numel(toRemove)
        try
            rmpath(char(toRemove(i)));
            changed = true;
        catch
        end
    end
end
end

function tf = localPathIsUnder(pathValue, rootValue)
pathValue = localNormalizePath(pathValue);
rootValue = localNormalizePath(rootValue);
if strlength(string(pathValue)) == 0 || strlength(string(rootValue)) == 0
    tf = false;
    return;
end
if ispc
    pathCmp = lower(pathValue);
    rootCmp = lower(rootValue);
else
    pathCmp = pathValue;
    rootCmp = rootValue;
end
tf = strcmp(pathCmp, rootCmp) || startsWith(pathCmp, [rootCmp filesep]);
end

function changed = localPruneSiblingToolkitRoots(rootDir)
changed = false;
hits = which("setup6GRSimToolkit", "-all");
if ischar(hits)
    hits = {hits};
end
if isempty(hits)
    return;
end

pathParts = strsplit(path, pathsep);
pathParts = pathParts(~cellfun(@isempty, pathParts));
toRemove = strings(0,1);
for i = 1:numel(hits)
    hitRoot = fileparts(char(string(hits{i})));
    if localSamePath(hitRoot, rootDir)
        continue;
    end
    for j = 1:numel(pathParts)
        p = char(string(pathParts{j}));
        if localPathIsUnder(p, hitRoot)
            toRemove(end+1,1) = string(p); %#ok<AGROW>
        end
    end
end
toRemove = unique(toRemove, "stable");
if isempty(toRemove)
    return;
end

try
    rmpath(strjoin(toRemove, pathsep));
    changed = true;
catch
    for i = 1:numel(toRemove)
        try
            rmpath(char(toRemove(i)));
            changed = true;
        catch
        end
    end
end
end

function tf = localSamePath(a, b)
a = localNormalizePath(a);
b = localNormalizePath(b);
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end
end

function p = localNormalizePath(inPath)
p = char(string(strtrim(string(inPath))));
if strlength(string(p)) == 0
    p = "";
    return;
end
p = strrep(p, "/", filesep);
p = strrep(p, "\", filesep);
while contains(p, [filesep filesep])
    p = strrep(p, [filesep filesep], filesep);
end
if strlength(string(p)) > 1 && endsWith(p, filesep) && ~(ispc && numel(p) == 3 && p(2) == ':')
    p = char(extractBefore(string(p), strlength(string(p))));
end
end
