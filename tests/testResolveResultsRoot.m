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

assert(strcmpi(char(string(p0)), char(string(repoResults))), "Empty result root must resolve to repo-local /results.");
assert(strcmpi(char(string(p1)), char(string(repoResults))), "Relative 'results' must resolve to repo-local /results.");
assert(strcmpi(char(string(p2)), char(string(fullfile(repoResults, "truth_validation_profile_runs")))), ...
    "Relative subfolders must stay under repo-local /results.");
assert(strcmpi(char(string(p3)), char(string(fullfile(repoResults, "custom_bucket")))), ...
    "Relative results subtrees must stay under repo-local /results.");
assert(strcmpi(char(string(p4)), char(string(repoResults))), ...
    "Absolute paths outside the repo-local /results tree must be redirected back into the repo.");

ok = true;
end
