function out = SixGR_Simulator(ctx, params)
%SIXGR_SIMULATOR Deprecated compatibility wrapper.
%
% This function is retained only for backward compatibility.
% All simulation runs are forwarded to:
%   sixgr_run_3gpp_full_campaign

if nargin < 1 || isempty(ctx)
    error("sixgr:sim:NoContext", "SixGR_Simulator requires a SimContext or cfg struct.");
end
if nargin < 2 || isempty(params)
    params = struct();
end

id = "sixgr:deprecated:SixGR_Simulator";
if datetime("now") > datetime(2026,9,1)
    error(id, "SixGR_Simulator removed after 2026-09-01; use sixgr_run_3gpp_full_campaign.");
end
ws = warning("query", id);
warning("on", id);
warning(id, ...
    ["SixGR_Simulator is DEPRECATED (kept for backward compatibility only). " ...
     "Migrate all call sites to sixgr_run_3gpp_full_campaign. " ...
     "This shim will be removed on 2026-09-01."]);
warning(ws.state, id);
localWarnMigration(mfilename("fullpath"));

if isa(ctx, "sixgr.core.SimContext")
    cfg = ctx.Cfg;
elseif isstruct(ctx) && isfield(ctx, "Cfg") && isstruct(ctx.Cfg)
    cfg = ctx.Cfg;
elseif isstruct(ctx)
    cfg = ctx;
else
    error("sixgr:sim:BadContext", "Unsupported ctx type for SixGR_Simulator.");
end

nv = localBuildCampaignNV(params, cfg);
report = sixgr_run_3gpp_full_campaign(cfg, nv{:});

out = struct();
out.Ok = logical(sixgr.util.structGet(report, "Ok", false));
out.Mode = "full";
out.Errors = strings(0,1);
if ~out.Ok
    out.Errors(end+1,1) = "sixgr_run_3gpp_full_campaign reported failure";
end
out.Link = sixgr.util.structGet(report, "Link", struct());
out.System = sixgr.util.structGet(report, "System", struct());
out.Hybrid = struct();
out.ExecutedStages = "full_campaign";
out.Report = report;

end

function localWarnMigration(callerFile)
if nargin < 1 || isempty(callerFile)
    return;
end
fprintf("[MIGRATION] SixGR_Simulator called from: %s\n  Replace with: sixgr_run_3gpp_full_campaign(cfg)\n", callerFile);
end

function nv = localBuildCampaignNV(params, cfg)
% Map legacy mode/profile intent to unified campaign knobs.

profile = lower(strtrim(char(string( ...
    sixgr.util.structGet(params, "Mode", sixgr.util.structGet(cfg, "run.profile", "full"))))));
if isempty(profile)
    profile = "full";
end

switch profile
    case "quick"
        linkDur = 60;
        sysDur = 60;
        linkMaxFrames = 220;
        linkSweepFrames = 8;
    case "long"
        linkDur = 1800;
        sysDur = 1800;
        linkMaxFrames = 2400;
        linkSweepFrames = 16;
    otherwise
        linkDur = 180;
        sysDur = 180;
        linkMaxFrames = 500;
        linkSweepFrames = 12;
end

resultsRoot = char(string(sixgr.util.structGet(cfg, "run.resultsRoot", "results")));
runE2E = logical(sixgr.util.structGet(cfg, "run.enableE2EProbe", true));
e2eDur = double(sixgr.util.structGet(cfg, "run.e2eDuration_s", 60));
e2eUE = double(sixgr.util.structGet(cfg, "run.e2eUECount", 8));
e2eTraffic = char(string(sixgr.util.structGet(cfg, "run.e2eTrafficModel", "xr")));
enableAI = logical(sixgr.util.structGet(cfg, "ai.enable", true));
linkSNR = double(sixgr.util.structGet(cfg, "channel.snr_dB", 20));
nUE = max(4, round(double(sixgr.util.structGet(cfg, "scenario.ue.nUE", 120))));

nv = { ...
    "ResultsRoot", resultsRoot, ...
    "LinkDuration_s", linkDur, ...
    "SystemDuration_s", sysDur, ...
    "LinkMaxSimFrames", linkMaxFrames, ...
    "LinkSweepFrames", linkSweepFrames, ...
    "SystemNumUE", nUE, ...
    "LinkSNR_dB", linkSNR, ...
    "RunE2EStackProbe", runE2E, ...
    "E2EDuration_s", e2eDur, ...
    "E2EUECount", e2eUE, ...
    "E2ETrafficModel", e2eTraffic, ...
    "E2EEnableAI", enableAI, ...
    "Verbose", false ...
    };
end
