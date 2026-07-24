function summary = run_two_mode_lls_smoke(varargin)
%RUN_TWO_MODE_LLS_SMOKE Quick smoke command for the two WebGUI LLS modes.
%
%   run_two_mode_lls_smoke
%   run_two_mode_lls_smoke("ResultsRoot", fullfile(tempdir, "two_mode_smoke"))

summary = sixgr.tools.runTwoModeLLS("smoke", varargin{:});
end
