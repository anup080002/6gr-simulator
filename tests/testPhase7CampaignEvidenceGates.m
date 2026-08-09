function ok = testPhase7CampaignEvidenceGates()
%TESTPHASE7CAMPAIGNEVIDENCEGATES Verify Phase 7 campaign gates use real rows.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = localCampaignCfg();
localWriteAdequateCampaignEvidence(tmp, cfg);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);

assert(isfield(report, "Campaign") && isstruct(report.Campaign), ...
    "Phase 7 report must expose campaign evidence details.");

summaryPath = fullfile(tmp, "reports", "final", "final_campaign_summary.csv");
curvePath = fullfile(tmp, "air_interface", "csv", "dl_multi_seed_bler_curve.csv");
dropPath = fullfile(tmp, "air_interface", "csv", "multi_seed_drop_statistics.csv");
auditPath = fullfile(tmp, "reports", "csv", "campaign_evidence_audit.csv");
gatePath = fullfile(tmp, "reports", "csv", "phase7_truth_gates.csv");
for path = string([summaryPath, curvePath, dropPath, auditPath, gatePath])
    assert(exist(char(path), "file") == 2, "Missing campaign evidence artifact: %s", path);
end

summary = readtable(summaryPath, "VariableNamingRule", "preserve", "TextType", "string");
assert(strcmp(string(summary.Status(1)), "campaign_complete"), ...
    "Adequate fixed-link evidence must produce a complete campaign summary.");
assert(double(summary.FinalRuns(1)) > 0 && double(summary.NDLTrialsTotal(1)) > 0, ...
    "Campaign summary must derive executed trial totals from fixed-link rows.");
assert(localAsLogical(summary.SeedHierarchyOk(1)) && localAsLogical(summary.SampleAdequacyOk(1)) && ...
    localAsLogical(summary.ConfidenceIntervalsOk(1)), ...
    "Campaign summary must expose passing seed/sample/CI gates.");

curve = readtable(curvePath, "VariableNamingRule", "preserve", "TextType", "string");
assert(height(curve) == 5 && all(double(curve.TrialCount) >= 5000), ...
    "Derived DL BLER curve must keep all configured SNR bins and trial counts.");
assert(all(double(curve.BLER_CI_Width) <= 0.05), ...
    "Derived DL BLER curve must carry confidence intervals within the configured bound.");

drops = readtable(dropPath, "VariableNamingRule", "preserve", "TextType", "string");
assert(height(drops) >= 30 && any(strcmp(string(drops.EvidenceStatus), "executed_trial_rows")), ...
    "Drop statistics must come from executed trial rows, not planned rows only.");

gates = readtable(gatePath, "VariableNamingRule", "preserve", "TextType", "string");
assert(height(gates) == 1 && width(gates) == ...
    numel(fieldnames(report.Gates)), ...
    "Phase-7 truth gates must remain one rectangular row; vector diagnostics belong in one scalar cell.");
assert(~any(startsWith(string(gates.Properties.VariableNames), "Var")), ...
    "Phase-7 truth gate export must not spill FailureCodes into anonymous columns.");
for name = ["SeedHierarchyOk", "CampaignDesignOk", "CampaignCompletionOk", ...
        "MultiSeedDropStatisticsOk", "ConfidenceIntervalsOk", "SampleAdequacyOk", ...
        "CheckpointResumeEquivalenceOk", "SerialParallelDeterminismOk", "SweepDataQualityOk"]
    assert(localAsLogical(gates.(char(name))(1)), ...
        "Expected Phase 7 campaign gate %s to pass with adequate evidence.", name);
end

tmpMissing = tempname;
mkdir(tmpMissing);
cleanupMissing = onCleanup(@() rmdir(tmpMissing, "s")); %#ok<NASGU>
sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmpMissing);
missingSummary = readtable(fullfile(tmpMissing, "reports", "final", "final_campaign_summary.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(strcmp(string(missingSummary.Status(1)), "no_phase7_campaign_runs_provided"), ...
    "Missing campaign rows must fail closed with the original no-runs status.");
missingGates = readtable(fullfile(tmpMissing, "reports", "csv", "phase7_truth_gates.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(~localAsLogical(missingGates.CampaignCompletionOk(1)) && ...
    ~localAsLogical(missingGates.SampleAdequacyOk(1)), ...
    "Missing campaign evidence must not pass completion or sample adequacy gates.");

tmpScalarMobility = tempname;
mkdir(tmpScalarMobility);
cleanupScalarMobility = onCleanup(@() rmdir(tmpScalarMobility, "s")); %#ok<NASGU>
scalarCfg = cfg;
scalarCfg.mobility = rmfield(scalarCfg.mobility, "user_paths");
scalarCfg.mobility.ue_speed_kmh = 200;
scalarCfg.users.n_users = 2;
scalarCfg.deployment_topology.max_ue_distance_from_bs_m = 500;
scalarCfg.deployment_topology.min_ue_distance_from_bs_m = 35;
sixgr.analytics.buildPhase7ReadinessArtifacts(scalarCfg, tmpScalarMobility);
traj = readtable(fullfile(tmpScalarMobility, "geometry", "csv", "trajectory_geometry.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
ueInit = readtable(fullfile(tmpScalarMobility, "geometry", "csv", "ue_initial_positions.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
resolution = readtable(fullfile(tmpScalarMobility, "mobility", "csv", "trajectory_resolution.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(height(traj) == 2 && height(ueInit) == 2, ...
    "Scalar mobility speed plus UE count must synthesize per-UE trajectory geometry.");
assert(all(string(ueInit.PathSource) == "mobility.ue_speed_kmh"), ...
    "Synthesized mobility paths must disclose scalar-speed provenance.");
assert(all(string(ueInit.PathProvenance) == "synthesized_from_scalar_speed") && ...
        all(string(traj.PathProvenance) == "synthesized_from_scalar_speed") && ...
        strcmp(string(resolution.PathProvenance(1)), "synthesized_from_scalar_speed"), ...
    "Scalar-speed mobility artifacts must label synthesized path provenance consistently.");
assert(~strcmp(string(resolution.Status(1)), "no_user_paths"), ...
    "Scalar-speed mobility must not export no_user_paths when UE count and distance bounds are configured.");

tmpScalarOnlyMobility = tempname;
mkdir(tmpScalarOnlyMobility);
cleanupScalarOnlyMobility = onCleanup(@() rmdir(tmpScalarOnlyMobility, "s")); %#ok<NASGU>
scalarOnlyCfg = struct();
scalarOnlyCfg.mobility.ue_speed_kmh = 200;
scalarOnlyCfg.scenario.numUEs = 2;
scalarOnlyCfg.scenario.ue.initial_distance_m = 300;
scalarOnlyCfg.frame_timing.slot_duration_ms = 0.5;
scalarOnlyCfg.run_control.total_slots = 100;
sixgr.analytics.buildPhase7ReadinessArtifacts(scalarOnlyCfg, tmpScalarOnlyMobility);
scalarOnlyTraj = readtable(fullfile(tmpScalarOnlyMobility, "geometry", "csv", "trajectory_geometry.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
scalarOnlyResolution = readtable(fullfile(tmpScalarOnlyMobility, "mobility", "csv", "trajectory_resolution.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(height(scalarOnlyTraj) == 2 && all(double(scalarOnlyTraj.RouteLength_m) > 0), ...
    "Scalar speed plus scenario UE count and initial distance must synthesize nonzero per-UE paths.");
assert(~strcmp(string(scalarOnlyResolution.Status(1)), "no_user_paths") && ...
        strcmp(string(scalarOnlyResolution.PathProvenance(1)), "synthesized_from_scalar_speed"), ...
    "Schema-minimal scalar mobility must not be reported as no_user_paths.");

ok = true;
end

function cfg = localCampaignCfg()
cfg = struct();
cfg.canonical_control.run.seed = 104729;
cfg.canonical_control.run.num_seeds = 30;
cfg.canonical_control.run.final_runs = 30;
cfg.canonical_control.run.min_campaign_snr_points = 5;
cfg.canonical_control.run.min_trials_per_sinr_bin = 5000;
cfg.canonical_control.run.max_ci_width = 0.05;
cfg.canonical_control.run.confidence_level = 0.95;
cfg.frame_timing.slot_duration_ms = 0.5;
cfg.run_control.total_slots = 1;
cfg.scenario.bs.height_m = 25;
cfg.mobility.user_paths = struct([]);
end

function localWriteAdequateCampaignEvidence(runDir, cfg)
layout = sixgr.report.resultLayout(runDir);
snr = (-2:2:6).';
n = numel(snr);
trialCount = repmat(5000, n, 1);
failures = [2200; 1200; 500; 120; 20];
fixed = table(snr, repmat("fixed_link_monte_carlo", n, 1), ...
    repmat("fixed_reference_awgn_snr_campaign", n, 1), true(n, 1), ...
    repmat("standalone_awgn_snr_argument", n, 1), ...
    (1000 + (1:n).'), trialCount, failures, failures ./ trialCount, ...
    zeros(n, 1), repmat(0.05, n, 1), repmat(0.05, n, 1), ...
    repmat(30, n, 1), false(n, 1), trialCount, failures, failures ./ trialCount, ...
    repmat(0.05, n, 1), repmat(30, n, 1), false(n, 1), ...
    'VariableNames', {'SNR_dB','CampaignKind','SweepKind','FixedReferenceMode', ...
    'NoiseOperatingMode','PointSeed','DL_TrialCount','DL_FailureCount','DL_BLER', ...
    'DL_BLER_CI_Low','DL_BLER_CI_High','DL_BLER_CI_Width','DL_DropCount','DL_Incomplete', ...
    'UL_TrialCount','UL_FailureCount','UL_BLER','UL_BLER_CI_Width','UL_DropCount','UL_Incomplete'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "lls_fixed_link_campaign.csv"), fixed);

taskPlan = sixgr.util.buildDeterministicTaskPlan(double(cfg.canonical_control.run.seed), snr, ["DL", "UL"], ...
    "MaxTrials", 30, "TrialsPerDrop", 1, "IncludePointTasks", true, ...
    "ExecutionGranularity", "fixed_link_campaign_point_drop_link");
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "fixed_link_campaign_task_plan.csv"), taskPlan);

dlTasks = taskPlan(strcmp(string(taskPlan.LinkToken), "DL") & double(taskPlan.DropIndex) > 0, :);
ulTasks = taskPlan(strcmp(string(taskPlan.LinkToken), "UL") & double(taskPlan.DropIndex) > 0, :);
dlTrials = localTrialRows(dlTasks, "DL");
ulTrials = localTrialRows(ulTasks, "UL");
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_fixed_link_campaign_trials.csv"), dlTrials);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_fixed_link_campaign_trials.csv"), ulTrials);

checkpoint = table(true, "resume_matches_uninterrupted_fixed_link_campaign", ...
    'VariableNames', {'CheckpointResumeEquivalenceOk','EvidenceStatus'});
determinism = table(true, "serial_parallel_task_rows_hash_match", ...
    'VariableNames', {'SerialParallelDeterminismOk','EvidenceStatus'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "checkpoint_resume_equivalence.csv"), checkpoint);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "serial_parallel_determinism.csv"), determinism);
sixgr.util.jsonWrite(fullfile(runDir, "reports", "json", "scenario_manifest.json"), struct("Fixture", "phase7_campaign_evidence"));
end

function T = localTrialRows(taskPlan, direction)
n = height(taskPlan);
idx = (1:n).';
status = repmat("PASS", n, 1);
status(mod(idx, 17) == 0) = "FAIL";
crcPass = status == "PASS";
T = table(double(taskPlan.PointIndex), double(taskPlan.DropIndex), double(taskPlan.TaskSeed), ...
    double(idx), repmat(upper(string(direction)), n, 1), double(taskPlan.PointValue), ...
    crcPass, status, repmat(1000, n, 1), repmat(1.0, n, 1), ...
    'VariableNames', {'FixedLinkPointIndex','FixedLinkDropIndex','FixedLinkDropSeed', ...
    'FixedLinkTrialIndex','FixedLinkDirection','SNR_dB','CRCPass','Status','GoodBits','Goodput_Mbps'});
end

function out = localAsLogical(value)
if islogical(value)
    out = logical(value(1));
elseif isnumeric(value)
    value = double(value(1));
    out = isfinite(value) && value ~= 0;
else
    token = lower(strtrim(string(value(1))));
    out = token == "1" || token == "true" || token == "yes" || token == "pass" || token == "passed";
end
end
