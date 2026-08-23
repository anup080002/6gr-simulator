function ok = testLLSOptionalFeaturePrimaryTableSuppression()
%TESTLLSOPTIONALFEATUREPRIMARYTABLESUPPRESSION No disabled header-only truth CSVs.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
layout = sixgr.report.resultLayout(tmp);

cfg = sixgr.config.defaultConfig();
cfg.runtime.features.pbch = struct("Enabled", false);
emptyT = table(zeros(0, 1), 'VariableNames', {'Attempt'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "pbch_trials.csv"), emptyT);
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, ...
    "pbch_trials.csv"), emptyT);
assert(isfile(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")), ...
    "Fixture must first create the legacy header-only primary table.");

paths = [string(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")); ...
    string(fullfile(layout.ControlCSVDir, "pbch_trials.csv"))];
sixgr.truth.writeOptionalRuntimeFeatureTable(cfg, "pbch", paths, emptyT);
assert(~isfile(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")) && ...
    ~isfile(fullfile(layout.ControlCSVDir, "pbch_trials.csv")), ...
    "A disabled zero-observation feature must suppress both primary and mirror CSVs.");

cfg.runtime.features.pbch.Enabled = true;
sixgr.truth.writeOptionalRuntimeFeatureTable(cfg, "pbch", paths, emptyT);
assert(~isfile(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")) && ...
    ~isfile(fullfile(layout.ControlCSVDir, "pbch_trials.csv")), ...
    "Enabled intent without observations must not create a header-only truth CSV.");

observedT = table(1, 'VariableNames', {'Attempt'});
sixgr.truth.writeOptionalRuntimeFeatureTable(cfg, "pbch", paths, observedT);
assert(height(readtable(fullfile(layout.AirInterfaceCSVDir, ...
    "pbch_trials.csv"))) == 1, ...
    "Genuine observations must be retained even when they contradict disabled intent.");

ok = true;
end
