function ok = testStrictInvariantAudit()
%TESTSTRICTINVARIANTAUDIT Artifact-level impossible evidence checks.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

badRoot = tempname;
mkdir(badRoot);
cleanupBad = onCleanup(@() localCleanup(badRoot)); %#ok<NASGU>
localWriteBadBundle(badRoot);

audit = sixgr.validation.auditLLSArtifacts(badRoot, "Strict", false, "WriteOutputs", true);
assert(~logical(audit.Ok), "Bad fixture must fail strict invariant audit.");
codes = string(audit.FailureCodes);
required = ["negative_packet_latency_detected"
    "ul_raw_trials_present_but_curve_empty"
    "throughput_reconciliation_failed"
    "dl_pdsch_objective_failed"];
for code = required.'
    assert(any(codes == code), "Expected strict invariant failure code: %s", code);
end
assert(any(codes == "configured_effective_operating_point_mismatch"), ...
    "Fixed-anchor configured/effective mismatch must be audited.");
assert(any(codes == "impossible_code_rate_detected"), ...
    "Impossible code-rate rows must be audited.");

layout = sixgr.report.resultLayout(badRoot);
csvPath = fullfile(layout.ReportCSVDir, "strict_invariant_audit.csv");
jsonPath = fullfile(layout.ReportDir, "json", "strict_invariant_audit.json");
assert(exist(csvPath, "file") == 2 && exist(jsonPath, "file") == 2, ...
    "Strict invariant audit must write CSV and JSON artifacts.");
outT = readtable(csvPath, "VariableNamingRule", "preserve", "TextType", "string");
assert(all(ismember(["CheckName","Scope","RowsChecked","RowsFailed","MetricValue", ...
    "Threshold","Status","FailureCode","Details"], string(outT.Properties.VariableNames))), ...
    "Strict invariant audit CSV schema mismatch.");

threw = false;
try
    sixgr.validation.auditLLSArtifacts(badRoot, "Strict", true, "WriteOutputs", false);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:validation:auditLLSArtifacts:StrictInvariantFailure");
end
assert(threw, "Strict=true must throw on impossible evidence.");

goodRoot = tempname;
mkdir(goodRoot);
cleanupGood = onCleanup(@() localCleanup(goodRoot)); %#ok<NASGU>
localWriteGoodBundle(goodRoot);
goodAudit = sixgr.validation.auditLLSArtifacts(goodRoot, "Strict", true, "WriteOutputs", false);
assert(logical(goodAudit.Ok), "Clean fixture must pass strict invariant audit.");

ok = true;
end

function localWriteBadBundle(root)
layout = sixgr.report.resultLayout(root);
packet = table("UL", "pkt1", true, 10, 9, 0.020, 0.015, -5.0, ...
    'VariableNames', {'Direction','PacketId','DeliverySuccess','EnqueueSlot','DeliverySlot', ...
    'EnqueueTime_s','DeliveryTime_s','Latency_ms'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "live_application_packet_ledger.csv"), packet);

ul = table("UL", 18.0, 0.5, ...
    'VariableNames', {'Direction','PostEqSINR_dB','CodeRate'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ul);

dl = table("DL", 1.2, ...
    'VariableNames', {'Direction','CodeRate'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dl);

throughput = table(false, "radio_duration_reconciliation_failed", ...
    'VariableNames', {'ThroughputReconciliationOk','FailureReason'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "throughput_reconciliation.csv"), throughput);

objective = table(false, false, false, "dl_pdsch_bler_objective_failed", ...
    'VariableNames', {'ObjectivePass','ScenarioObjectiveOk','ResultOk','FailureReason'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "dl_pdsch_raw_bler_ber_objective.csv"), objective);

configured = table("DL", "fixed_anchor", true, false, false, ...
    'VariableNames', {'Direction','ScenarioMode','StrictEligible','AdaptiveMode','ExactOperatingPointMatch'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "configured_effective_operating_point.csv"), configured);
end

function localWriteGoodBundle(root)
layout = sixgr.report.resultLayout(root);
packet = table("UL", "pkt1", true, 10, 11, 0.020, 0.025, 5.0, ...
    'VariableNames', {'Direction','PacketId','DeliverySuccess','EnqueueSlot','DeliverySlot', ...
    'EnqueueTime_s','DeliveryTime_s','Latency_ms'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "live_application_packet_ledger.csv"), packet);

ul = table("UL", 18.0, 0.5, ...
    'VariableNames', {'Direction','PostEqSINR_dB','CodeRate'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ul);
curve = table(18.0, 10, 0.0, ...
    'VariableNames', {'PostEqSINR_dB_BinCenter','TrialCount','BLER'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_bler_curve.csv"), curve);

dl = table("DL", 0.5, ...
    'VariableNames', {'Direction','CodeRate'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dl);

throughput = table(true, "", ...
    'VariableNames', {'ThroughputReconciliationOk','FailureReason'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "throughput_reconciliation.csv"), throughput);

objective = table(true, true, true, "", ...
    'VariableNames', {'ObjectivePass','ScenarioObjectiveOk','ResultOk','FailureReason'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "dl_pdsch_raw_bler_ber_objective.csv"), objective);

configured = table("DL", "fixed_anchor", true, false, true, ...
    'VariableNames', {'Direction','ScenarioMode','StrictEligible','AdaptiveMode','ExactOperatingPointMatch'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "configured_effective_operating_point.csv"), configured);
end

function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end
