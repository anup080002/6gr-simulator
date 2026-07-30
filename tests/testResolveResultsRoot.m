function ok = testResolveResultsRoot()
%TESTRESOLVERESULTSROOT Ensure result roots stay inside the repo-local results tree.

setup6GRSimToolkit("Verbose", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
repoResults = fullfile(repoRoot, "results");
parentResults = fullfile(fileparts(repoRoot), "results");

p0 = sixgr.report.resolveResultsRoot("");
p1 = sixgr.report.resolveResultsRoot("results");
p2 = sixgr.report.resolveResultsRoot("truth_validation_profile_runs");
p3 = sixgr.report.resolveResultsRoot(fullfile("results", "custom_bucket"));
p4 = sixgr.report.resolveResultsRoot(parentResults);

oldScratch = getenv("SIXGR_REGRESSION_SCRATCH_ROOT");
cleanup = onCleanup(@() setenv("SIXGR_REGRESSION_SCRATCH_ROOT", oldScratch)); %#ok<NASGU>
regressionScratch = fullfile(tempdir, "sixgr-results-root-test");
setenv("SIXGR_REGRESSION_SCRATCH_ROOT", regressionScratch);
p5 = sixgr.report.resolveResultsRoot(fullfile(regressionScratch, "task-a"));
p6 = sixgr.report.resolveResultsRoot(fullfile(fileparts(regressionScratch), "outside-task"));
repoFromUtility = sixgr.utils.getRepoRoot();

assert(strcmpi(char(string(p0)), char(string(repoResults))), "Empty result root must resolve to repo-local /results.");
assert(strcmpi(char(string(p1)), char(string(repoResults))), "Relative 'results' must resolve to repo-local /results.");
assert(strcmpi(char(string(p2)), char(string(fullfile(repoResults, "truth_validation_profile_runs")))), ...
    "Relative subfolders must stay under repo-local /results.");
assert(strcmpi(char(string(p3)), char(string(fullfile(repoResults, "custom_bucket")))), ...
    "Relative results subtrees must stay under repo-local /results.");
assert(strcmpi(char(string(p4)), char(string(repoResults))), ...
    "Absolute paths outside the repo-local /results tree must be redirected back into the repo.");
assert(strcmpi(char(string(p5)), char(string(fullfile(regressionScratch, "task-a")))), ...
    "A child root under the configured regression scratch tree must be retained.");
assert(strcmpi(char(string(p6)), char(string(repoResults))), ...
    "The regression scratch opt-in must not authorize sibling external paths.");
assert(exist(fullfile(repoFromUtility, "tools", "audit_lls_visual_artifacts.py"), "file") == 2, ...
    "Repository-root resolution must retain visual-audit tooling for external scratch runs.");

ok = true;
end
