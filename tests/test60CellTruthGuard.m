function ok = test60CellTruthGuard()
%TEST60CELLTRUTHGUARD Removed 60-cell proxy runner must not remain in the repo.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));
assert(exist(fullfile(repoRoot, "run_full_2min_60cell_profile.m"), "file") == 0, ...
    "Legacy 60-cell proxy runner should be removed from the repo.");
assert(exist(fullfile(repoRoot, "run_truth_validation_profile.m"), "file") == 2, ...
    "Truth validation runner should remain available.");
ok = true;
end
