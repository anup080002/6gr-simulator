function out = End2EndOrchestrator(ctx, params)
%END2ENDORCHESTRATOR Convenience wrapper for complete hybrid run.
%
% Stages:
%   1) Link-level KPIs
%   2) BLER calibration
%   3) System-level run with calibrated abstract PHY

if nargin < 2 || isempty(params)
    params = struct();
end

out = struct();
out.Ok = true;
out.Errors = strings(0,1);
out.Link = struct();
out.Hybrid = struct();

try
    out.Link = sixgr.link.LinkLevelRunner.run(ctx, params);
catch ME
    out.Ok = false;
    out.Errors(end+1,1) = "Link stage failed: " + string(ME.message);
end

try
    out.Hybrid = sixgr.hybrid.HybridRunner.run(ctx, params);
    out.Ok = out.Ok && logical(sixgr.util.structGet(out.Hybrid, "Ok", false));
catch ME
    out.Ok = false;
    out.Errors(end+1,1) = "Hybrid stage failed: " + string(ME.message);
end
end
