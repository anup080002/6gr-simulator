function result = runRAN1UL10523(mode, varargin)
%RUNRAN1UL10523 Run the config-driven RAN1 10.5.2.3 UL evidence suite.
%   Modes: plan, unit, quick, tdoc, full, sls, figure_replay, audit.
if nargin < 1 || strlength(string(mode)) == 0
    mode = "quick";
end
result = sixgr.tdoc.ul10523.runTDocSuite(string(mode), varargin{:});
end
