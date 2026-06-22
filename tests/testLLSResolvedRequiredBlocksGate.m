function ok = testLLSResolvedRequiredBlocksGate()
%TESTLLSRESOLVEDREQUIREDBLOCKSGATE Resolved YAML required blocks fail closed.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
layout = sixgr.report.resultLayout(tmp);
for f = ["ReportCSVDir","AirInterfaceCSVDir","ControlCSVDir","PacketFlowCSVDir"]
    sixgr.util.ensureDir(layout.(f));
end

scfg = struct();
scfg = sixgr.util.structSet(scfg, "scenario_id", "required_block_gate_fixture");
scfg = sixgr.util.structSet(scfg, "scenario.honesty_mode", "strict");
scfg = sixgr.util.structSet(scfg, "users.execution_model", "slot_coupled_truth");
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", "both");
scfg = sixgr.util.structSet(scfg, "control_gating.prach_required", true);
scfg = sixgr.util.structSet(scfg, "control_gating.pdcch_required", true);
scfg = sixgr.util.structSet(scfg, "control_gating.srs_required", true);
scfg = sixgr.util.structSet(scfg, "control_gating.trs_required", true);
scfg = sixgr.util.structSet(scfg, "sib1_and_initial_access.sib1_required", true);
scfg = sixgr.util.structSet(scfg, "random_access_evidence.four_step_ra_required", true);
scfg = sixgr.util.structSet(scfg, "channel_rf_configured_vs_applied.enabled", true);
scfg = sixgr.util.structSet(scfg, "dut_reference_validation.enabled", true);
for block = ["sib1","prach","pdcch","srs","trs","channel_rf"]
    scfg = sixgr.util.structSet(scfg, "dut_reference_validation.compare_blocks." + block, true);
end

cfg = struct();
localWriteMinimalMetadata(layout);

verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(tmp, scfg, cfg);
assert(~logical(verdict.Ok), "Missing resolved-required strict blocks must fail the truth contract.");

summaryT = readtable(fullfile(layout.ReportCSVDir, "truth_contract_summary.csv"), "VariableNamingRule", "preserve");
assert(logical(summaryT.SIB1Required(1)) && logical(summaryT.RARequired(1)) && ...
    logical(summaryT.PRACHRequired(1)) && logical(summaryT.PDCCHRequired(1)) && ...
    logical(summaryT.SRSRequired(1)) && logical(summaryT.TRSRequired(1)) && ...
    logical(summaryT.ChannelRFRequired(1)), ...
    "Resolved YAML required flags must propagate to the truth-contract summary.");

failureText = strjoin(string(verdict.Failures), " | ");
for token = ["sib1_strict", "ra_strict", "prach_strict", "pdcch_strict", "srs_strict", "trs_strict", "channel_rf"]
    assert(contains(failureText, token), "Missing required block failure was not reported: %s", token);
end

ok = true;
end

function localWriteMinimalMetadata(layout)
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), ...
    table("completed", true, true, 'VariableNames', {'RunCompletion','Ok','ResultOk'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"), ...
    table("fixture", "consistent", 'VariableNames', {'CheckName','ConsistencyStatus'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv"), ...
    table("fixture", "consistent", 'VariableNames', {'CheckName','ConsistencyStatus'}));
end
