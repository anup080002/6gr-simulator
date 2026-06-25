function results = generateMeasuredSINRCurves(cfg, run_tag, varargin)
%GENERATEMEASUREDSINRCURVES Compatibility wrapper for the package implementation.
if nargin < 2
    run_tag = "";
end
results = sixgr.analytics.generateMeasuredSINRCurves(cfg, run_tag, varargin{:});
end
