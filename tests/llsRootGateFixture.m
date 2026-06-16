function ctx = llsRootGateFixture(caseName)
%LLSROOTGATEFIXTURE Build a compact strict-anchor run folder for root-gate tests.

caseName = lower(strtrim(string(caseName)));
tmp = tempname;
mkdir(tmp);
layout = sixgr.report.resultLayout(tmp);
for folder = [layout.ReportCSVDir, layout.AirInterfaceCSVDir, layout.PacketFlowCSVDir]
    sixgr.util.ensureDir(fullfile(folder, ".keep"));
end

[scfg, cfg, target, effective] = localScenario(caseName);
localWriteEvidence(layout, scfg, target, effective);
if caseName == "critical_waiver"
    localWriteCriticalWaiverIssue(layout);
end

ctx = struct();
ctx.RunFolder = tmp;
ctx.Layout = layout;
ctx.ScenarioConfig = scfg;
ctx.InternalConfig = cfg;
ctx.Cleanup = onCleanup(@() localCleanup(tmp));
end

function [scfg, cfg, target, effective] = localScenario(caseName)
target = struct("Rank", 1, "Layers", 1, "Modulation", "QPSK", "MCS", 4);
effective = target;
scenarioName = "nr_baseline_study_root_gate_fixture";
scenarioMode = "fixed_anchor";
claimProfile = "";

switch caseName
    case "broad_claim"
        scenarioName = "Rel20 6G full 3GPP conformance anchor";
    case "honest_study"
        scenarioName = "Rel20 study context NR-inspired research fixture";
        claimProfile = "rel20_study_context";
    case {"fixed_collapse", "configured_effective_mismatch"}
        target = struct("Rank", 2, "Layers", 2, "Modulation", "256QAM", "MCS", 20);
        effective = struct("Rank", 1, "Layers", 1, "Modulation", "QPSK", "MCS", 1);
    case "adaptive_link"
        target = struct("Rank", 2, "Layers", 2, "Modulation", "256QAM", "MCS", 20);
        effective = struct("Rank", 1, "Layers", 1, "Modulation", "QPSK", "MCS", 1);
        scenarioMode = "adaptive_link";
    case "missing_effective"
        target = struct("Rank", 2, "Layers", 2, "Modulation", "256QAM", "MCS", 20);
        effective = struct("Rank", NaN, "Layers", NaN, "Modulation", "", "MCS", NaN);
    case "critical_waiver"
        scenarioName = "critical waiver fixture";
end

scfg = struct();
scfg = sixgr.util.structSet(scfg, "scenario_id", "root_gate_" + matlab.lang.makeValidName(char(caseName)));
scfg = sixgr.util.structSet(scfg, "scenario.name", scenarioName);
scfg = sixgr.util.structSet(scfg, "scenario.scenario_mode", scenarioMode);
scfg = sixgr.util.structSet(scfg, "scenario.honesty_mode", "strict");
scfg = sixgr.util.structSet(scfg, "scenario.claim_profile", claimProfile);
scfg = sixgr.util.structSet(scfg, "users.execution_model", "slot_coupled_truth");
scfg = sixgr.util.structSet(scfg, "users.n_users", 1);
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", "both");
scfg = sixgr.util.structSet(scfg, "mimo.n_layers", target.Layers);
scfg = sixgr.util.structSet(scfg, "modulation.dl_mcs_index", target.MCS);
scfg = sixgr.util.structSet(scfg, "modulation.ul_mcs_index", target.MCS);
scfg = sixgr.util.structSet(scfg, "pdsch.modulation", target.Modulation);
scfg = sixgr.util.structSet(scfg, "pusch.modulation", target.Modulation);
if scenarioMode == "adaptive_link"
    scfg = sixgr.util.structSet(scfg, "link_adaptation.fixed_or_amc", "adaptive");
    scfg = sixgr.util.structSet(scfg, "link_adaptation.pdsch_link_adaptation_policy", "cqi_driven");
    scfg = sixgr.util.structSet(scfg, "link_adaptation.pusch_link_adaptation_policy", "cqi_driven");
else
    scfg = sixgr.util.structSet(scfg, "link_adaptation.fixed_or_amc", "fixed");
    scfg = sixgr.util.structSet(scfg, "link_adaptation.pdsch_link_adaptation_policy", "fixed");
    scfg = sixgr.util.structSet(scfg, "link_adaptation.pusch_link_adaptation_policy", "fixed");
end

cfg = struct();
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", string(scenarioMode));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", string(scfg.link_adaptation.pdsch_link_adaptation_policy));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", string(scfg.link_adaptation.pusch_link_adaptation_policy));
end

function localWriteEvidence(layout, scfg, target, effective)
scenarioName = string(scfg.scenario.name);
summaryT = table( ...
    "completed", scfg.scenario_id, scenarioName, true, true, 0, true, 0, 0, 0, ...
    "scenario_status_aggregation_v2_runtime_truth_contract", ...
    'VariableNames', {'RunCompletion','ScenarioID','ScenarioName','Ok','ResultOk','RequiredFailureCount','RuntimeTruthContractOk', ...
    'RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount','StrictTruthFailureCount','StatusAuthority'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);

runtimeT = table( ...
    ["DL"; "UL"], repmat(string(scfg.link_adaptation.pdsch_link_adaptation_policy), 2, 1), repmat("scheduler_grant", 2, 1), ...
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

trialT = localTrialTable(target, effective, "DL");
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), trialT);
ulTrialT = localTrialTable(target, effective, "UL");
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ulTrialT);

ferT = table( ...
    ["run"; "run"], ...
    repmat("all_ues_in_direction_aggregated_per_frame_no_ue_identity", 2, 1), ...
    ["DL"; "UL"], [NaN; NaN], [NaN; NaN], [NaN; NaN], ...
    [1; 1], [0; 0], [0; 0], ...
    repmat("frame_fails_if_any_executed_transport_block_fails_crc_or_crashes", 2, 1), ...
    repmat("root_gate_fixture", 2, 1), ...
    'VariableNames', {'Scope','ScopeDefinition','Direction','UEID','UEIndex','RNTI', ...
    'ObservedFrames','ErroredFrames','FER','FERDefinition','TraceSource'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv"), ferT);

grantT = table((0:1).', [1; 1], [0; 12], [12; 12], ...
    'VariableNames', {'Slot','UEID','PRBStart','PRBLength'});
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), grantT);
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), grantT);
end

function T = localTrialTable(target, effective, direction)
n = 2;
T = table((0:1).', repmat(effective.Layers, n, 1), repmat(effective.Rank, n, 1), ...
    repmat(string(effective.Modulation), n, 1), repmat(effective.MCS, n, 1), ...
    repmat(target.Layers, n, 1), repmat(target.Rank, n, 1), repmat(string(target.Modulation), n, 1), repmat(target.MCS, n, 1), ...
    repmat(effective.Layers, n, 1), repmat(effective.Rank, n, 1), repmat(string(effective.Modulation), n, 1), repmat(effective.MCS, n, 1), ...
    repmat(effective.Layers, n, 1), repmat(effective.Rank, n, 1), repmat(string(effective.Modulation), n, 1), repmat(effective.MCS, n, 1), ...
    [false; false], repmat("finalized", n, 1), [1; 1], [0; 0], repmat("OK", n, 1), ...
    repmat("scheduler_grant", n, 1), repmat("scheduler_grant", n, 1), repmat("scheduler_grant", n, 1), repmat("fixed", n, 1), ...
    'VariableNames', {'Slot','Layers','RankIndicator','Modulation','MCS', ...
    'ScheduledLayers','ScheduledRank','ScheduledModulation','ScheduledMCS', ...
    'TransmittedLayers','TransmittedRank','TransmittedModulation','TransmittedMCS', ...
    'EffectiveLayers','EffectiveRank','EffectiveModulation','EffectiveMCS', ...
    'IsWarmupFrame','RowLifecycleState','FinalizedFlag','PartialRowFlag','PrimaryTruthValueStatus', ...
    'MCSAuthority','ModulationAuthority','AppliedOperatingPointSource','ConfiguredMCSSelectionPolicy'});
T.Direction = repmat(string(direction), height(T), 1);
T.TrialId = string((1:height(T)).');
T.GrantId = "grant_" + string((1:height(T)).');
T.SchedulerDecisionId = "sched_" + string((1:height(T)).');
T.TxEvidenceId = "tx_" + string((1:height(T)).');
T.RxEvidenceId = "rx_" + string((1:height(T)).');
T.AdaptationEvidenceId = "cqi_" + string((1:height(T)).');
T.TBSize_bits = [1000; 1000];
T.CRCPass = [true; true];
T.BitErrors = [0; 0];
T.BitsCompared = [1000; 1000];
T.StrictReceiverEvidenceOk = [true; true];
T.TruthStatus = repmat("real_lls_evidence", height(T), 1);
T.ChannelEstimateAttempted = [true; true];
T.ChannelEstimateAvailable = [true; true];
T.ResourceExtractionAttempted = [true; true];
T.ResourceExtractionAvailable = [true; true];
T.EqualizationAttempted = [true; true];
T.EqualizationAvailable = [true; true];
T.DLSCHDecodeAttempted = [true; true];
T.DLSCHDecodeAvailable = [true; true];
T.ULSCHDecodeAttempted = [true; true];
T.ULSCHDecodeAvailable = [true; true];
T.DecodeAttempted = [true; true];
T.DecodeUsable = [true; true];
T.LLRAvailable = [true; true];
T.LLRFinite = [true; true];
T.PostEqSINRWidebanddB = [24; 25];
T.PostEqSINRSource = repmat("post_equalization_sinr_from_equalizer_channel_estimate", height(T), 1);
T.PostEqSINRValueRole = repmat("measured_post_equalization_scheduling_input", height(T), 1);
T.PostEqSINRValueStatus = repmat("OK", height(T), 1);
T.PostEqSINRAvailable = [true; true];
T.PostEqSINRReceiverDerived = [true; true];
T.SINRValidationStatus = repmat("pass", height(T), 1);
T.SINRComputationMethod = repmat("mmse", height(T), 1);
T.ChannelComplianceMode = repmat("strict_38901_runtime", height(T), 1);
T.AppliedLargeScaleGainSource = repmat("root_gate_fixture_channel_reference", height(T), 1);
end

function localWriteCriticalWaiverIssue(layout)
T = table( ...
    "AUD-001", "critical", "waived_non_blocking", "standards_claim", ...
    "", NaN, NaN, "result_status", "ResultOk", "true", ...
    "Critical root issue cannot be waived for strict anchor.", ...
    "reports/csv/result_issue_registry.csv", ...
    "unit test critical waiver", ...
    "critical issues are not waivable", true, ...
    'VariableNames', {'issue_id','severity','issue_status','issue_category','direction','ue_id','cell_id', ...
    'block_name','metric_name','observed_value','expected_or_policy','evidence_artifact_ref', ...
    'root_cause_hint','fix_plan','analytics_visible_flag'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"), T);
end

function localCleanup(pathValue)
if exist(pathValue, "dir") == 7
    rmdir(pathValue, "s");
end
end
