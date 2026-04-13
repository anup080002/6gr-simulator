function ok = test60CellStressProfileMode()
%TEST60CELLSTRESSPROFILEMODE Legacy stress/proxy runner should be removed.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));
assert(exist(fullfile(repoRoot, "run_full_2min_60cell_profile.m"), "file") == 0, ...
    "Legacy stress/proxy 60-cell runner should be removed from the repo.");
assert(exist(fullfile(repoRoot, "run_truth_validation_profile.m"), "file") == 2, ...
    "Truth validation runner should remain available.");

ok = true;
end
