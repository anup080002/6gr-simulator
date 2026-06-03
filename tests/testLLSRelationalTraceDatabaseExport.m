function ok = testLLSRelationalTraceDatabaseExport()
%TESTLLSRELATIONALTRACEDATABASEEXPORT Supplementary truth DB export should materialize cleanly.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

layout = sixgr.report.resultLayout(tmp);
dirs = {layout.AirInterfaceCSVDir, layout.ControlCSVDir, layout.BeamformingCSVDir, layout.HARQCSVDir, layout.RFCSVDir, layout.DatabaseDir};
for i = 1:numel(dirs)
    sixgr.util.ensureFolder(dirs{i});
end

dl = table("DL", 10, 1, 1, 1, 101, 24, 2, 1000, "parallel_matlab_workers", "PASS", "", ...
    "VariableNames", {"Direction","SNR_dB","Frame","Slot","UEIndex","RNTI","PRBs","Layers","TBSize_bits","ExecutionModel","Status","Notes"});
task = table(1, "DL", 10, 1, 101, 1, "processes", "parallel_matlab_workers", 1, 1, 1, 1, 1, 1, 24, ...
    "2026-04-07T00:00:00.000Z", "2026-04-07T00:00:01.000Z", 1.0, true, ...
    "VariableNames", {"TaskIndex","Direction","SNR_dB","UEIndex","RNTI","BaseStationID","ParallelPoolType", ...
    "ExecutionModel","WorkerID","TrialCount","FrameStart","FrameEnd","SlotStart","SlotEnd","PRBCountMean", ...
    "StartedUTC","CompletedUTC","Elapsed_s","Ok"});
attach = table(1, 1, 0.001, 1, 1, "DL", "ATTACH_START", "START", true, "", ...
    "VariableNames", {"Step","Slot","Time_s","UE","CellID","Direction","Event","State","Success","Cause"});

sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dl);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "parallel_task_trace.csv"), task);
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "attach_state_trace.csv"), attach);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.carrier.NCellID", 1);
cfg = sixgr.util.structSet(cfg, "run.parallelPoolType", "processes");
cfg = sixgr.util.structSet(cfg, "run.parallelWorkerExecutionModel", "parallel_matlab_workers");
cfg = sixgr.util.structSet(cfg, "run.numWorkers", 2);

out = sixgr.truth.exportLLSRelationalTraceDatabase(cfg, tmp, struct("MultiUserMode", "parallel_matlab_workers"), struct());

assert(exist(layout.TraceDatabaseManifestJSON, "file") == 2, ...
    "Relational trace DB export must always emit a manifest.");
assert(~strcmp(string(out.Status), "sqlite_export_failed"), ...
    "Relational trace DB export should either succeed or report an unavailable SQLite interface.");

if logical(out.Ok)
    assert(exist(layout.TraceDatabaseSQLite, "file") == 2, ...
        "Successful relational trace DB export must create the SQLite file.");
    assert(any(strcmp(string(out.TablesWritten), "radio_link_timeline")), ...
        "Successful relational trace DB export must write the radio link timeline table.");
else
    assert(strcmp(string(out.Status), "sqlite_interface_unavailable"), ...
        "Non-success status must honestly report the missing SQLite interface.");
end

ok = true;
end
