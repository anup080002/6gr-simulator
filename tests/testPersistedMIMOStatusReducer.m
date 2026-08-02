function ok = testPersistedMIMOStatusReducer()
%TESTPERSISTEDMIMOSTATUSREDUCER Verify recovery cannot pass vacuously.

setup6GRSimToolkit("Verbose", false);
runFolder = tempname;
mkdir(runFolder);
cleanup = onCleanup(@() localCleanup(runFolder)); %#ok<NASGU>
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureDir(fullfile(layout.BeamformingCSVDir, ".keep"));

cfg = struct();
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numLayers", 2);
cfg = sixgr.util.structSet(cfg, "phy.pusch.numLayers", 2);
status = struct("ConfiguredEffectiveOk", true, "StatusNotes", "");

missing = sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus( ...
    status, runFolder, cfg);
assert(~missing.ConfiguredEffectiveOk && ...
    ~missing.ConfiguredEffectiveSupplementalEvaluated, ...
    "Required MIMO evidence must fail closed when the artifact is absent.");

mimoPath = fullfile(layout.BeamformingCSVDir, ...
    "mimo_configured_vs_effective.csv");
passTable = table(["DL";"UL"], [true;true], ...
    'VariableNames', {'Direction','ScenarioObjectivePass'});
sixgr.util.csvWriteTable(mimoPath, passTable);
passed = sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus( ...
    status, runFolder, cfg);
assert(passed.ConfiguredEffectiveOk && ...
    passed.ConfiguredEffectiveSupplementalEvaluated, ...
    "Complete passing DL/UL MIMO evidence must preserve an upstream pass.");

failTable = passTable;
failTable.ScenarioObjectivePass(2) = false;
sixgr.util.csvWriteTable(mimoPath, failTable);
failed = sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus( ...
    status, runFolder, cfg);
assert(~failed.ConfiguredEffectiveOk && ...
    failed.ConfiguredEffectiveSupplementalEvaluated, ...
    "Any failing MIMO direction must force recovery configured/effective failure.");
ok = true;
end

function localCleanup(pathStr)
if isfolder(pathStr)
    rmdir(pathStr, "s");
end
end
