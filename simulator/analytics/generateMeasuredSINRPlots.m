function results = generateMeasuredSINRPlots(cfg, run_tag, varargin)
%GENERATEMEASUREDSINRPLOTS Compatibility wrapper for the package implementation.
if nargin < 2
    run_tag = "";
end
results = sixgr.analytics.generateMeasuredSINRPlots(cfg, run_tag, varargin{:});
end
