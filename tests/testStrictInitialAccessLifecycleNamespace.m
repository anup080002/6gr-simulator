function ok = testStrictInitialAccessLifecycleNamespace()
%TESTSTRICTINITIALACCESSLIFECYCLENAMESPACE Strict summary cannot replace runtime events.

runFolder = tempname;
cleanup = onCleanup(@()localCleanup(runFolder)); %#ok<NASGU>
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);

canonical = table(1, "RRC_CONNECTED", 7, 0.0035, ...
    'VariableNames', {'UEIndex','EventName','Slot','Time_s'});
canonicalPath = fullfile(layout.ControlCSVDir, ...
    "initial_access_lifecycle_trace.csv");
sixgr.util.csvWriteTable(canonicalPath, canonical);
strict = table(1, "SSB_PBCH_MIB_SIB1", true, true, ...
    'VariableNames', {'StageOrder','StageName','Attempted','Completed'});

artifacts = sixgr.phy.broadcast.publishStrictInitialAccessLifecycle( ...
    runFolder, strict);
observedCanonical = readtable(canonicalPath, "VariableNamingRule", "preserve");
observedStrict = readtable( ...
    artifacts.StrictInitialAccessValidationLifecycleCSV, ...
    "VariableNamingRule", "preserve");
assert(isequaln(canonical, observedCanonical), ...
    "Strict lifecycle publication overwrote canonical per-UE runtime events.");
assert(isequaln(strict, observedStrict) && ...
    artifacts.CanonicalRuntimeLifecyclePreserved, ...
    "Strict lifecycle summary was not published in its own namespace.");

standaloneFolder = fullfile(runFolder, "standalone");
standaloneArtifacts = sixgr.phy.broadcast.publishStrictInitialAccessLifecycle( ...
    standaloneFolder, strict);
legacy = readtable(standaloneArtifacts.InitialAccessLifecycleCSV, ...
    "VariableNamingRule", "preserve");
assert(isequaln(strict, legacy) && ...
    ~standaloneArtifacts.CanonicalRuntimeLifecyclePreserved, ...
    "Standalone strict mini-anchor compatibility lifecycle was not written.");
ok = true;
end

function localCleanup(path)
if exist(path, "dir") == 7
    rmdir(path, "s");
end
end
