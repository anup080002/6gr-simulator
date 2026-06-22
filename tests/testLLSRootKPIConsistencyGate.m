function ok = testLLSRootKPIConsistencyGate()
%TESTLLSROOTKPICONSISTENCYGATE KPI reconstruction failure blocks ResultOk.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
layout = sixgr.report.resultLayout(tmp);
sixgr.util.ensureDir(layout.ReportCSVDir);
sixgr.util.ensureDir(layout.AirInterfaceCSVDir);

sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), ...
    table("completed", true, true, 'VariableNames', {'RunCompletion','Ok','ResultOk'}));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv"), ...
    table("fixture", false, false, "fail", "radio_duration_unavailable", ...
    'VariableNames', {'ScenarioID','KPIReconciliationPass','StrictOk','Status','FailureReason'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "kpi_reconstruction_summary.csv"), ...
    table("DL_BLER", "DL", false, false, false, "unavailable", "fail", "radio_duration_unavailable", ...
    'VariableNames', {'KPIName','Direction','StrictOk','ReconciliationPass','FormulaExecuted','DurationSource','Status','FailureReason'}));

scfg = struct();
scfg = sixgr.util.structSet(scfg, "scenario_id", "kpi_gate_fixture");
scfg = sixgr.util.structSet(scfg, "scenario.honesty_mode", "strict");
scfg = sixgr.util.structSet(scfg, "users.execution_model", "slot_coupled_truth");
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", "both");

verdict = struct("Failures", strings(0, 1), "CanonicalArtifactGapCount", 0, ...
    "RequiredRuntimeEvidenceMissingCount", 0, "RoundtripMismatchCount", 0, ...
    "StrictProxyGuardFailureCount", 0);
root = sixgr.truth.evaluateStrictAnchorStatus(tmp, scfg, struct(), verdict, localTrialRows("DL"), localTrialRows("UL"), struct());

assert(~logical(root.Status.KpiConsistencyOk), "Failed KPI reconstruction must set KpiConsistencyOk=false.");
assert(~logical(root.Status.ResultOk), "Failed KPI reconstruction must block ResultOk.");
assert(any(contains(string(root.Failures), "kpi_consistency_gate_failed")), ...
    "Root failures must include the KPI consistency gate failure.");

ok = true;
end

function T = localTrialRows(direction)
T = table( ...
    repmat(string(direction), 1, 1), 0, 1, 1, "QPSK", 1, false, ...
    'VariableNames', {'Direction','Slot','Layers','Rank','Modulation','MCS','IsWarmupFrame'});
end
