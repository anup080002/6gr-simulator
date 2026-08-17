function results = generateMeasuredSINRPlots(cfg, runTag, varargin)
%GENERATEMEASUREDSINRPLOTS Retired MATLAB raster compatibility entry point.
%
% Runtime measured-SINR source tables are produced by
% sixgr.analytics.generateMeasuredSINRCurves. Final LLS raster artifacts
% are rendered once, after CSV finalization and audit, by
% scripts.regenerate_lls_rasters_from_csv. Keeping a second MATLAB raster
% producer caused transient legacy images and an obsolete lineage CSV to
% reappear during every run. This compatibility entry point intentionally
% emits no files and can be removed once external callers have migrated.

if nargin < 2
    runTag = "";
end
% Preserve the historical name/value surface while rejecting malformed
% pairs. No option can re-enable the retired producer.
if mod(numel(varargin), 2) ~= 0
    error("sixgr:analytics:MeasuredSINRPlotOptions", ...
        "Measured-SINR plot compatibility options must be name/value pairs.");
end

runDir = localResolveRunDir(cfg);
results = struct( ...
    "Ok", true, ...
    "RunDir", string(runDir), ...
    "RunTag", string(runTag), ...
    "Plots", strings(0, 1), ...
    "LineageCSV", "", ...
    "LineageTable", table(), ...
    "Suppressed", true, ...
    "Status", "retired_contract_raster_authority", ...
    "Producer", "scripts.regenerate_lls_rasters_from_csv");
end

function runDir = localResolveRunDir(cfg)
if ischar(cfg) || (isstring(cfg) && isscalar(cfg))
    runDir = char(string(cfg));
    return;
end
runDir = char(string(sixgr.util.structGet(cfg, "output_dir", ...
    sixgr.util.structGet(cfg, "outputs.output_dir", ...
    sixgr.util.structGet(cfg, "run.rootRunFolder", ...
    sixgr.util.structGet(cfg, "runFolder", pwd))))));
end
