function ok = testPRACHParallelStatisticalDeterminism()
%TESTPRACHPARALLELSTATISTICALDETERMINISM Exact serial/parallel PRACH evidence.

setup6GRSimToolkit("Verbose", false);
serialBundle = prachStrictAnchorResult("Refresh", true);
serial = serialBundle.Result;

cfg = serialBundle.InternalConfig;
cfg.run.useParallel = true;
cfg.run.parallelRequestedWorkers = 2;
cfg.run.numWorkers = 2;
poolCleanup = onCleanup(@localDeletePool); %#ok<NASGU>
parallel = sixgr.phy.prach.runStrictPRACHValidation(cfg, ...
    "WriteArtifacts", false, ...
    "RunId", "strict_prach_unit", ...
    "ScenarioName", "lls_prach_strict_mini_anchor");

assert(parallel.ParallelExecution.Active && ...
    parallel.ParallelExecution.EffectiveWorkers == 2, ...
    "The dedicated parallel regression must execute on two process workers.");

names = ["prach_trials", "prach_detection_candidates", ...
    "prach_missed_detection_sweep", "prach_false_alarm_sweep", ...
    "prach_oracle_guard"];
for k = 1:numel(names)
    a = serial.ArtifactTables.(names(k));
    b = parallel.ArtifactTables.(names(k));
    common = intersect(string(a.Properties.VariableNames), ...
        string(b.Properties.VariableNames), "stable");
    common = common(common ~= "ConfigHash");
    assert(isequaln(a(:, cellstr(common)), b(:, cellstr(common))), ...
        "%s serial/parallel evidence mismatch.", names(k));
end

ok = true;
end

function localDeletePool()
pool = gcp("nocreate");
if ~isempty(pool)
    delete(pool);
end
end
