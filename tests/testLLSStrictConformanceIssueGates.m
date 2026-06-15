function ok = testLLSStrictConformanceIssueGates()
%TESTLLSSTRICTCONFORMANCEISSUEGATES Active issue rows and fixed-point collapse must fail strict LLS.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = localStrictScenarioConfig();
cfg = sixgr.util.structSet(struct(), "phy.linkAdaptation.mode", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", "fixed");

layout = sixgr.report.resultLayout(fullfile(tmp, "issue_gate"));
localEnsureLayout(layout);
localWriteEvidence(layout, false);
localWriteIssueRegistry(layout, "high", "REVIEW_REQUIRED");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(fullfile(tmp, "issue_gate"), scfg, cfg);
assert(~logical(verdict.Ok), "Strict LLS runs with active high/medium/critical issue rows must fail.");
assert(any(contains(string(verdict.Failures), "active_result_issue_registry_blockers=1")), ...
    "Truth-contract failures must include the active issue-registry blocker count.");
summaryT = readtable(fullfile(layout.ReportCSVDir, "truth_contract_summary.csv"), "VariableNamingRule", "preserve");
assert(double(summaryT.ActiveMandatoryIssueCount(1)) == 1 && double(summaryT.ActiveHighIssueCount(1)) == 1, ...
    "Truth-contract summary must export active mandatory issue counts.");

layout2 = sixgr.report.resultLayout(fullfile(tmp, "objective_gate"));
localEnsureLayout(layout2);
localWriteEvidence(layout2, true);
verdict2 = sixgr.truth.evaluateLLSRuntimeTruthContract(fullfile(tmp, "objective_gate"), scfg, cfg);
assert(~logical(verdict2.Ok), "Fixed operating-point collapse must fail strict scenario objective gating.");
assert(any(contains(string(verdict2.Failures), "configured_effective_match_rate_below_required")), ...
    "Fixed-point mismatch failures must name the configured/effective match gate.");
summaryT2 = readtable(fullfile(layout2.ReportCSVDir, "truth_contract_summary.csv"), "VariableNamingRule", "preserve");
assert(~logical(summaryT2.ScenarioObjectiveOk(1)), ...
    "Truth-contract summary must expose ScenarioObjectiveOk=false for fixed-point collapse.");

ok = true;
end

function scfg = localStrictScenarioConfig()
scfg = struct();
scfg = sixgr.util.structSet(scfg, "scenario_id", "STRICT_CONFORMANCE_GATE_TEST");
scfg = sixgr.util.structSet(scfg, "meta.configHash", "unit_hash");
scfg = sixgr.util.structSet(scfg, "scenario.honesty_mode", "strict");
scfg = sixgr.util.structSet(scfg, "users.execution_model", "slot_coupled_truth");
scfg = sixgr.util.structSet(scfg, "users.n_users", 1);
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", "both");
scfg = sixgr.util.structSet(scfg, "mimo.n_layers", 2);
scfg = sixgr.util.structSet(scfg, "modulation.dl_mcs_index", 20);
scfg = sixgr.util.structSet(scfg, "modulation.ul_mcs_index", 20);
scfg = sixgr.util.structSet(scfg, "pdsch.modulation", "256QAM");
scfg = sixgr.util.structSet(scfg, "pusch.modulation", "256QAM");
scfg = sixgr.util.structSet(scfg, "link_adaptation.fixed_or_amc", "fixed");
scfg = sixgr.util.structSet(scfg, "link_adaptation.pdsch_link_adaptation_policy", "fixed");
scfg = sixgr.util.structSet(scfg, "link_adaptation.pusch_link_adaptation_policy", "fixed");
end

function localEnsureLayout(layout)
fields = ["ReportCSVDir", "AirInterfaceCSVDir", "PacketFlowCSVDir"];
for ii = 1:numel(fields)
    sixgr.util.ensureDir(layout.(fields(ii)));
end
end

function localWriteEvidence(layout, mismatchedOperatingPoint)
summaryT = table( ...
    "completed", true, true, 0, true, 0, 0, 0, "scenario_status_aggregation_v2_runtime_truth_contract", ...
    'VariableNames', {'RunCompletion','Ok','ResultOk','RequiredFailureCount','RuntimeTruthContractOk', ...
    'RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount','StrictTruthFailureCount','StatusAuthority'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);

runtimeT = table( ...
    ["DL"; "UL"], repmat("fixed", 2, 1), repmat("scheduler_grant", 2, 1), ...
    repmat("configured_fixed_operating_point", 2, 1), repmat("scheduler_grant", 2, 1), ...
    repmat("WAVEFORM_LINK_BUNDLE", 2, 1), repmat("COUPLED_WAVEFORM_GRANT_EXECUTION", 2, 1), ...
    [1; 1], [0; 0], [0; 0], repmat("full_per_link_channel_waveform_sum", 2, 1), [1; 1], ...
    'VariableNames', {'Direction','ConfiguredMCSSelectionPolicy','ActualMCSSelectionMode', ...
    'RequestedOperatingPointSource','AppliedOperatingPointSource','ExecutionBackend','PHYMode', ...
    'WaveformPHYActive','ProxyPHYActive','FallbackUsed','InterferenceMode','ConfiguredUsers'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"), runtimeT);

consistentT = table("simulation.link_direction", "consistent", ...
    'VariableNames', {'ParameterName','ConsistencyStatus'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"), consistentT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv"), consistentT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv"), ...
    table("effective_trial_count", "consistent", 'VariableNames', {'CheckName','ConsistencyStatus'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "value_source_audit.csv"), ...
    table("simulation.link_direction", "observed", 'VariableNames', {'ParameterName','Status'}));

if mismatchedOperatingPoint
    layers = [1; 1];
    rank = [1; 1];
    modulation = ["QPSK"; "QPSK"];
    mcs = [1; 1];
else
    layers = [2; 2];
    rank = [2; 2];
    modulation = ["256QAM"; "256QAM"];
    mcs = [20; 20];
end
trialT = table((0:1).', layers, rank, modulation, mcs, [false; false], ...
    repmat("finalized", 2, 1), [1; 1], [0; 0], repmat("OK", 2, 1), ...
    repmat("scheduler_grant", 2, 1), repmat("scheduler_grant", 2, 1), ...
    repmat("scheduler_grant", 2, 1), repmat("fixed", 2, 1), ...
    'VariableNames', {'Slot','Layers','RankIndicator','Modulation','MCS','IsWarmupFrame', ...
    'RowLifecycleState','FinalizedFlag','PartialRowFlag','PrimaryTruthValueStatus', ...
    'MCSAuthority','ModulationAuthority','AppliedOperatingPointSource','ConfiguredMCSSelectionPolicy'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), trialT);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), trialT);

ferT = table( ...
    ["run"; "run"], ...
    repmat("all_ues_in_direction_aggregated_per_frame_no_ue_identity", 2, 1), ...
    ["DL"; "UL"], [NaN; NaN], [NaN; NaN], [NaN; NaN], ...
    [1; 1], [0; 0], [0; 0], ...
    repmat("frame_fails_if_any_executed_transport_block_fails_crc_or_crashes", 2, 1), ...
    repmat("truth_contract_test_fixture", 2, 1), ...
    'VariableNames', {'Scope','ScopeDefinition','Direction','UEID','UEIndex','RNTI', ...
    'ObservedFrames','ErroredFrames','FER','FERDefinition','TraceSource'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv"), ferT);

grantT = table((0:1).', [1; 1], [0; 12], [12; 12], ...
    'VariableNames', {'Slot','UEID','PRBStart','PRBLength'});
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), grantT);
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), grantT);
end

function localWriteIssueRegistry(layout, severity, issueStatus)
T = table( ...
    "unit_active_issue", string(severity), string(issueStatus), "unit_test", ...
    "", NaN, NaN, "run", "ResultOk", "true", ...
    "No active mandatory result issues may remain in strict LLS.", ...
    "reports/csv/result_issue_registry.csv", ...
    "unit test active issue", ...
    "fix underlying issue", true, ...
    'VariableNames', {'issue_id','severity','issue_status','issue_category','direction','ue_id','cell_id', ...
    'block_name','metric_name','observed_value','expected_or_policy','evidence_artifact_ref', ...
    'root_cause_hint','fix_plan','analytics_visible_flag'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"), T);
end
