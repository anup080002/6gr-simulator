function summary = run_two_mode_lls_full(varargin)
%RUN_TWO_MODE_LLS_FULL Full truth-level command for the two WebGUI LLS modes.
%
%   run_two_mode_lls_full
%   run_two_mode_lls_full("ResultsRoot", "results")

summary = sixgr.tools.runTwoModeLLS("full", varargin{:});
end
