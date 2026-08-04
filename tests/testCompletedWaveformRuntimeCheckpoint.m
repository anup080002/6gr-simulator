function ok = testCompletedWaveformRuntimeCheckpoint()
%TESTCOMPLETEDWAVEFORMRUNTIMECHECKPOINT Fail-closed resumable checkpoint guard.

runFolder = tempname;
cleanup = onCleanup(@()localCleanup(runFolder)); %#ok<NASGU>
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.MetaDir);

status = table(1, 12, 12, 3, 3, 2, 1, 1, 1, 0, 0, 0, 0, false, ...
    'VariableNames', {'RunCompletion','CurrentSlot','TotalSlots', ...
    'SweepPointIndex','SweepPointCount','DLTrialRows','ULTrialRows', ...
    'DLTrialsReady','ULTrialsReady','PBCHAttemptCount','PRACHAttemptCount', ...
    'SRSAttemptCount','TRSAttemptCount','FinalBundleReady'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_stage_status.csv"), status);

dl = table([1;2], [0;0], 'VariableNames', {'UEIndex','SNR_dB'});
ul = table(1, 0, 'VariableNames', {'UEIndex','SNR_dB'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dl);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ul);
for name = ["pbch","prach","srs","trs"]
    sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, name + "_trials.csv"), ...
        table(zeros(0,1), 'VariableNames', {'Trial'}));
end

checkpoint = sixgr.truth.assertCompletedWaveformRuntimeCheckpoint(runFolder, ...
    "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3);
assert(checkpoint.Ok && checkpoint.DLTrialRows == 2 && ...
    checkpoint.ULTrialRows == 1 && checkpoint.RequiresFinalizationResume, ...
    "A valid completed waveform runtime checkpoint was not accepted.");

badStatus = status;
badStatus.DLTrialRows = 3;
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_stage_status.csv"), badStatus);
localAssertIdentifier(@()sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    runFolder, "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3), ...
    "sixgr:truth:resume:PersistedRowCountMismatch");

finalStatus = status;
finalStatus.Stage = "final_bundle_ready";
finalStatus.FinalBundleReady = true;
finalStatus.SRSAttemptCount = 1;
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "live_stage_status.csv"), finalStatus);
localAssertIdentifier(@()sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    runFolder, "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3), ...
    "sixgr:truth:resume:PersistedRowCountMismatch");
reconciled = sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    runFolder, "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3, ...
    "ReconcileFinalizedControlCounters", true);
assert(reconciled.Ok && ...
    height(reconciled.ControlCounterReconciliation) == 1 && ...
    string(reconciled.ControlCounterReconciliation.Signal(1)) == "SRS" && ...
    double(reconciled.Status.SRSAttemptCount) == 0, ...
    ["Explicit finalized-counter reconciliation must repair only derived " ...
     "checkpoint metadata from the canonical persisted runtime table."]);
assert(exist(fullfile(layout.ReportCSVDir, ...
    "runtime_checkpoint_counter_reconciliation.csv"), "file") == 2, ...
    "Finalized checkpoint reconciliation must write an audit sidecar.");

nonFinalStatus = finalStatus;
nonFinalStatus.Stage = "control_gating_streaming";
nonFinalStatus.FinalBundleReady = false;
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "live_stage_status.csv"), nonFinalStatus);
localAssertIdentifier(@()sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    runFolder, "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3, ...
    "ReconcileFinalizedControlCounters", true), ...
    "sixgr:truth:resume:PersistedRowCountMismatch");

sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_stage_status.csv"), status);
sixgr.util.writeTextFile(fullfile(layout.MetaDir, "failure_debug_report.txt"), "failure");
localAssertIdentifier(@()sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    runFolder, "ExpectedTotalSlots", 12, "ExpectedSweepPointCount", 3), ...
    "sixgr:truth:resume:RecordedRuntimeFailure");

ok = true;
end

function localAssertIdentifier(fcn, expected)
caught = false;
try
    fcn();
catch ME
    caught = true;
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, observed %s.", expected, ME.identifier);
end
assert(caught, "Expected typed error %s.", expected);
end

function localCleanup(path)
if exist(path, "dir") == 7
    rmdir(path, "s");
end
end
