function ok = testHybrid()
%TESTHYBRID Legacy hybrid runners should be removed from the repo.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));
assert(exist(fullfile(repoRoot, "+sixgr", "+hybrid", "HybridRunner.m"), "file") == 0, ...
    "HybridRunner should be removed from the active repository.");
assert(exist(fullfile(repoRoot, "+sixgr", "+hybrid", "End2EndOrchestrator.m"), "file") == 0, ...
    "End2EndOrchestrator should be removed from the active repository.");
ok = true;
end
