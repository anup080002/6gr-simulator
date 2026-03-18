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
p.parse(varargin{:});
opt = p.Results;

rootDir = fileparts(mfilename("fullpath"));
doChecks = opt.Verbose;
if ~isempty(opt.RunToolboxChecks)
    doChecks = logical(opt.RunToolboxChecks);
end

persistent cache
if isempty(cache)
    cache = struct("rootDir","", "subfoldersAdded", false, "checks", struct("name",{}, "symbol",{}, "ok",{}));
end

pathChanged = false;

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
