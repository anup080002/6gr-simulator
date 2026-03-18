function report = selftest6GRSimToolkit(cfgFile)
%SELFTEST6GRSIMTOOLKIT End-to-end smoke test for unified simulator flow.
%
% Sequence:
%   1) setup + toolbox detection
%   2) config load and validation
%   3) scenario preview (layout + UE drop)
%   4) link-level smoke
%   5) system-level smoke
%   6) hybrid smoke (LLS calibration -> SLS)
%
% Usage:
%   report = selftest6GRSimToolkit("config/suite_config.json");

if nargin < 1 || (isstring(cfgFile) && strlength(cfgFile)==0) || (ischar(cfgFile) && isempty(cfgFile))
    cfgFile = fullfile("config","suite_config.json");
end

setup6GRSimToolkit("Verbose", true);

report = struct();
report.ok = false;
report.cfgFile = string(cfgFile);
report.errors = strings(0,1);
report.runFolder = "";
report.toolbox = struct();
report.smoke = struct();

% Toolbox/capability status (function-availability based)
try
    report.toolbox = sixgr.util.getToolboxStatus();
catch ME
    report.errors(end+1,1) = "Toolbox status failed: " + string(ME.message);
end

% Load config
try
    cfg = sixgr_loadConfig(cfgFile);
    report.cfg = cfg;
catch ME
    report.errors(end+1,1) = "Config load FAILED: " + string(ME.message);
    return;
end

% Create a selftest run folder
projRoot = fileparts(which("setup6GRSimToolkit"));
saveRoot = fullfile(projRoot, "results");
runFolder = fullfile(saveRoot, "selftest_" + sixgr.util.timeStamp());
report.runFolder = string(runFolder);

try
    sixgr.util.ensureDir(runFolder);
catch ME
    report.errors(end+1,1) = "ensureDir FAILED: " + string(ME.message);
    return;
end

% Export a tiny CSV + MAT as a sanity check
try
    t = table((1:5).', rand(5,1), 'VariableNames', {'idx','rand'});
    sixgr.util.csvWriteTable(fullfile(runFolder,"csv","selftest_table.csv"), t);
    sixgr.util.matSave(fullfile(runFolder,"mat","selftest.mat"), struct("cfg",cfg,"t",t));
catch ME
    report.errors(end+1,1) = "Export FAILED: " + string(ME.message);
    return;
end

% Build shared run context for all smoke stages
try
    ctx = sixgr.core.SimContext(cfg, "RootDir", projRoot, "RunFolder", runFolder);
    ctx.Logger.info("selftest: context created");
catch ME
    report.errors(end+1,1) = "SimContext FAILED: " + string(ME.message);
    return;
end

% Scenario preview
try
    layout = sixgr.scenario.generateLayout(cfg);
    ue = sixgr.scenario.dropUEs(cfg, layout);
    report.smoke.scenario = struct( ...
        "ok", true, ...
        "nTRxP", layout.nTRxP, ...
        "nUE", ue.K);
catch ME
    report.errors(end+1,1) = "Scenario preview FAILED: " + string(ME.message);
    report.smoke.scenario = struct("ok", false);
end

% Link-level smoke
try
    linkRes = sixgr.link.LinkLevelRunner.run(ctx, struct("NumFrames", 4));
    report.smoke.link = struct("ok", logical(linkRes.Ok), ...
        "kpiRows", height(linkRes.KPITable), ...
        "skippedCases", sum(linkRes.KPITable.Skipped));
catch ME
    report.errors(end+1,1) = "Link smoke FAILED: " + string(ME.message);
    report.smoke.link = struct("ok", false);
end

% System-level smoke
try
    sysRes = sixgr.system.SystemLevelRunner.run(ctx, struct("NumTTI", 20));
    report.smoke.system = struct("ok", logical(sysRes.Ok), ...
        "throughput_Mbps", localTblGet(sysRes.KPITable, "Throughput_Mbps"));
catch ME
    report.errors(end+1,1) = "System smoke FAILED: " + string(ME.message);
    report.smoke.system = struct("ok", false);
end

% Hybrid smoke
try
    hybRes = sixgr.hybrid.HybridRunner.run(ctx, struct("NumTTI", 20, "CalibFrames", 4));
    report.smoke.hybrid = struct("ok", logical(hybRes.Ok), ...
        "lutPoints", height(hybRes.Calibration.Table));
catch ME
    report.errors(end+1,1) = "Hybrid smoke FAILED: " + string(ME.message);
    report.smoke.hybrid = struct("ok", false);
end

% Optional: instantiate and close Site Viewer if available
try
    if report.toolbox.siteviewer
        v = siteviewer; %#ok<NASGU>
        % Close without leaving UI around
        close(v);
    end
catch ME
    report.errors(end+1,1) = "Site Viewer smoke FAILED: " + string(ME.message);
end

report.ok = (numel(report.errors) == 0);

end

function v = localTblGet(T, varName)
v = NaN;
if istable(T) && height(T) >= 1 && any(strcmp(T.Properties.VariableNames, varName))
    v = T.(varName)(1);
end
end
