function ok = testProfiledLLSRunMonitorHarness()
%TESTPROFILEDLLSRUNMONITORHARNESS Smoke-test profiled LLS monitor artifacts.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@()rmdir(tmp, "s")); %#ok<NASGU>

mon = sixgr.monitor.RunMonitor(tmp, "fixture.yaml");
s = mon.scope("function_name", "fixture_function", "phase", "fixture_phase", "channel", "PDSCH");
pause(0.001);
s.close("status", "completed");
mon.close();
fid = fopen(fullfile(tmp, "run.log"), "w");
assert(fid > 0, "Could not write fixture run.log");
fprintf(fid, "[2026-06-29T00:00:00Z] INFO Coupled canonical slot prepared: sweep=1/1 slot=1/100 duplex=DL.\n");
fprintf(fid, "[2026-06-29T00:00:10Z] INFO Coupled DL schedule complete: sweep=1/1 slot=1/100 active=0 granted=0 grants=0.\n");
fprintf(fid, "[2026-06-29T00:00:20Z] INFO Coupled control gating complete for slot 2/100: acquired=1/1 access=0/1 eligible=0/1.\n");
fclose(fid);

profileInfo = struct("FunctionTable", []);
profileT = sixgr.monitor.ProfileExporter.export(profileInfo, tmp);
[inventoryT, unusedT] = sixgr.monitor.StaticInventory.export(pwd, tmp, profileT);
flowT = sixgr.monitor.ChannelFlowRecorder.export(tmp, profileT, readtable(fullfile(tmp, "activity_timeline.csv"), "Delimiter", ",", "TextType", "string"));
[summaryT, byFunctionT, byChannelT] = sixgr.monitor.ComplexityCounter.export(tmp, profileT);
progressT = sixgr.monitor.LogProgressAnalyzer.export(tmp);
audit = sixgr.monitor.OutputAuditor.audit(tmp, "fixture.yaml", "", false, profileT, flowT, table());

required = [
    "activity_timeline.csv"
    "function_call_trace.csv"
    "runtime_exception_log.csv"
    "matlab_profile_raw.mat"
    "matlab_profile_function_table.csv"
    "function_call_tree.json"
    "function_call_graph.dot"
    "top_runtime_hotspots.md"
    "static_function_inventory.csv"
    "unused_function_report.csv"
    "channel_flow_summary.csv"
    "channel_flow_pdsch.csv"
    "skipped_or_bypassed_activity.csv"
    "complexity_summary.csv"
    "complexity_by_function.csv"
    "complexity_by_channel.csv"
    "runtime_log_progress_summary.csv"
    "output_audit_report.md"
    "output_audit_issues.csv"
    "final_blunt_grade.json"
    "final_fix_plan.md"
    ];
for rel = required(:).'
    assert(isfile(fullfile(tmp, rel)), "Missing monitor artifact %s", rel);
end
assert(height(inventoryT) > 0, "Static inventory must scan +sixgr files.");
assert(height(unusedT) == height(inventoryT), "Unused report must classify every inventory row.");
assert(height(flowT) >= 10, "Channel flow summary must include all major channels.");
assert(height(summaryT) == 1 && height(byFunctionT) > 0 && height(byChannelT) > 0, ...
    "Complexity exports must be populated.");
assert(height(progressT) == 1 && double(progressT.LastSlot(1)) == 2, ...
    "Log progress analyzer must capture slot progress.");
assert(strcmp(string(audit.Grade.verdict), "failed run"), ...
    "A failed/blocked harness smoke must not be graded as successful.");

ok = true;
end
