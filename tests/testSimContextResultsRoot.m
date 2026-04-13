function ok = testSimContextResultsRoot()
%TESTSIMCONTEXTRESULTSROOT Generic SimContext runs must stay under repo-local /results.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.resultsRoot = "results";
cfg.run.mode = "link";

ctx = sixgr.core.SimContext(cfg);
cleanupObj = onCleanup(@() localCleanupRunFolder(ctx.RunFolder)); %#ok<NASGU>

repoRoot = fileparts(fileparts(mfilename("fullpath")));
repoResults = fullfile(repoRoot, "results");
repoResultsPrefix = string([char(repoResults) filesep]);
parentResults = fullfile(fileparts(repoRoot), "results");
runFolder = char(string(ctx.RunFolder));

assert(startsWith(lower(string(runFolder)), lower(repoResultsPrefix)), ...
    "SimContext run folder must stay under repo-local /results.");
assert(~startsWith(lower(string(runFolder)), lower(string([char(parentResults) filesep]))), ...
    "SimContext run folder must not leak into the parent Simulator/results path.");
assert(contains(lower(string(runFolder)), lower(string([filesep 'lls' filesep 'session' filesep 'current']))), ...
    "SimContext link runs must use a stable /results/lls/session/current folder.");

ok = true;
end

function localCleanupRunFolder(runFolder)
runFolder = char(string(runFolder));
if strlength(string(runFolder)) == 0
    return;
end
if isfolder(runFolder)
    try
        rmdir(runFolder, "s");
    catch
    end
end
end
