function ok = testPhase7PerOperatingPointStatistics()
%TESTPHASE7PEROPERATINGPOINTSTATISTICS Seeds and adequacy are per link/SNR.

setup6GRSimToolkit("Verbose", false);

root = tempname;
mkdir(root);
cleanupObj = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
cfg = localConfig();

% Four globally distinct seeds but only one seed in each DL/UL operating
% point must not satisfy a three-seed publication requirement.
localWriteCampaign(root, 1, 10, 10, 0.10, 0.10);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(logical(report.Gates.SeedHierarchyOk), ...
    "The deterministic task hierarchy itself should be valid.");
assert(~logical(report.Gates.CampaignDesignOk) && ...
        ~logical(report.Gates.MultiSeedDropStatisticsOk), ...
    ["Globally unique point seeds must not masquerade as three " ...
     "independent seeds at every direction/SNR operating point."]);
summary = readtable(fullfile(root, "reports", "final", ...
    "final_campaign_summary.csv"), "VariableNamingRule", "preserve");
assert(double(summary.SeedsRun(1)) == 1, ...
    "SeedsRun must report the minimum per-direction/per-point seed count.");

% With three independent seeds at every point, campaign design and drop
% statistics pass.  Then make only UL numerically underqualified; neither
% the DL curve nor adequate DL rows may hide that UL failure.
localWriteCampaign(root, 3, 10, 10, 0.10, 0.10);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(logical(report.Gates.CampaignDesignOk) && ...
        logical(report.Gates.MultiSeedDropStatisticsOk) && ...
        logical(report.Gates.SampleAdequacyOk) && ...
        logical(report.Gates.ConfidenceIntervalsOk), ...
    "Three adequate seeds in every DL/UL point must pass the statistical reducers.");

wrongSeedCfg = cfg;
wrongSeedCfg.validation.fixed_link_campaign.seeds = ...
    cfg.validation.fixed_link_campaign.seeds + 10000;
wrongSeedReport = sixgr.analytics.buildPhase7ReadinessArtifacts( ...
    wrongSeedCfg, root);
assert(~logical(wrongSeedReport.Gates.CampaignDesignOk) && ...
        ~logical(wrongSeedReport.Gates.MultiSeedDropStatisticsOk), ...
    ["An observed seed set with the right count but different identities " + ...
     "must not satisfy the YAML-owned campaign contract."]);

% Equal seed counts are insufficient when each operating point uses a
% different configured seed set.  Publication statistics require paired
% YAML seed identities across every direction/SNR group.
layout = sixgr.report.resultLayout(root);
for direction = ["dl", "ul"]
    path = fullfile(layout.AirInterfaceCSVDir, ...
        direction + "_fixed_link_campaign_trials.csv");
    trials = readtable(path, "VariableNamingRule", "preserve");
    pointTwo = double(trials.FixedLinkPointIndex) == 2;
    trials.FixedLinkSeedValue(pointTwo) = ...
        double(trials.FixedLinkSeedValue(pointTwo)) + 10000;
    sixgr.util.csvWriteTable(path, trials);
end
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(~logical(report.Gates.CampaignDesignOk) && ...
        ~logical(report.Gates.MultiSeedDropStatisticsOk), ...
    ["Disjoint configured seed sets at different SNR points must not " + ...
     "satisfy paired multi-seed campaign statistics."]);

localWriteCampaign(root, 3, 10, 10, 0.10, 0.10);

% Hierarchical task seeds vary by point/drop even when the operator's
% configured seed does not.  They are replay identities, not proof of
% independent configured-seed coverage.  Collapse the configured seed
% lineage while preserving distinct task seeds and require failure.
for direction = ["dl", "ul"]
    path = fullfile(layout.AirInterfaceCSVDir, ...
        direction + "_fixed_link_campaign_trials.csv");
    trials = readtable(path, "VariableNamingRule", "preserve");
    trials.FixedLinkSeedIndex(:) = 1;
    trials.FixedLinkSeedValue(:) = 777001;
    sixgr.util.csvWriteTable(path, trials);
end
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(~logical(report.Gates.CampaignDesignOk) && ...
        ~logical(report.Gates.MultiSeedDropStatisticsOk), ...
    ["Distinct hierarchical task seeds must not inflate configured-seed " + ...
     "coverage when every drop uses the same YAML-owned seed."]);

% Restore complete configured-seed evidence for the remaining reductions.
localWriteCampaign(root, 3, 10, 10, 0.10, 0.10);

fixedPath = fullfile(layout.AirInterfaceCSVDir, "lls_fixed_link_campaign.csv");
mixedKind = readtable(fixedPath, "VariableNamingRule", "preserve", "TextType", "string");
mixedKind.CampaignKind(2) = "diagnostic_probe";
sixgr.util.csvWriteTable(fixedPath, mixedKind);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(~logical(report.Gates.CampaignDesignOk), ...
    "Every fixed-link row must carry the publication campaign kind; checking only the first row is unsafe.");

localWriteCampaign(root, 3, 10, 1, 0.10, 0.80);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, root);
assert(~logical(report.Gates.SampleAdequacyOk), ...
    "An under-sampled UL point must fail sample adequacy even when DL passes.");
assert(~logical(report.Gates.ConfidenceIntervalsOk), ...
    "A wide UL confidence interval must fail CI adequacy even when DL passes.");

ok = true;
end

function cfg = localConfig()
cfg = struct();
cfg.canonical_control.run.num_seeds = 3;
cfg.canonical_control.run.final_runs = 3;
cfg.canonical_control.run.min_campaign_snr_points = 2;
cfg.canonical_control.run.min_trials_per_sinr_bin = 10;
cfg.canonical_control.run.max_ci_width = 0.20;
cfg.canonical_control.run.confidence_level = 0.95;
cfg.validation.run_class = "fixed_snr_sweep_lls";
cfg.validation.fixed_link_campaign.interval_method = ...
    "CLOPPER_PEARSON_TWO_SIDED";
cfg.validation.fixed_link_campaign.seeds = [700001 700002 700003];
cfg.channel.model = "AWGN";
end

function localWriteCampaign(root, seedCount, dlTrials, ulTrials, dlCI, ulCI)
layout = sixgr.report.resultLayout(root);
snr = [0; 5];
fixed = table(snr, repmat("fixed_link_monte_carlo", 2, 1), ...
    repmat("both", 2, 1), (1001:1002).', ...
    repmat(double(dlTrials), 2, 1), zeros(2, 1), zeros(2, 1), ...
    repmat(double(dlCI), 2, 1), repmat(double(seedCount), 2, 1), false(2, 1), ...
    repmat(double(ulTrials), 2, 1), zeros(2, 1), zeros(2, 1), ...
    repmat(double(ulCI), 2, 1), repmat(double(seedCount), 2, 1), false(2, 1), ...
    'VariableNames', {'SNR_dB','CampaignKind','DirectionMode','PointSeed', ...
    'DL_TrialCount','DL_FailureCount','DL_BLER','DL_BLER_CI_Width', ...
    'DL_DropCount','DL_Incomplete','UL_TrialCount','UL_FailureCount', ...
    'UL_BLER','UL_BLER_CI_Width','UL_DropCount','UL_Incomplete'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "lls_fixed_link_campaign.csv"), fixed);

taskRows = repmat(struct("TaskKind", "point_drop_link", "LinkToken", "", ...
    "PointIndex", NaN, "PointValue", NaN, "DropIndex", NaN, ...
    "TaskSeed", NaN, "SchedulingInvariant", ...
    "worker_order_independent_seed_per_task"), 0, 1);
dlRows = repmat(localTrialRow(), 0, 1);
ulRows = repmat(localTrialRow(), 0, 1);
for point = 1:numel(snr)
    for drop = 1:seedCount
        dlSeed = 100000 + point * 100 + drop;
        ulSeed = 200000 + point * 100 + drop;
        taskRows(end+1, 1) = localTaskRow("DL", point, snr(point), drop, dlSeed); %#ok<AGROW>
        taskRows(end+1, 1) = localTaskRow("UL", point, snr(point), drop, ulSeed); %#ok<AGROW>
        for trial = 1:localTrialsForDrop(dlTrials, seedCount, drop)
            dlRows(end+1, 1) = localRuntimeTrialRow("DL", point, snr(point), drop, dlSeed); %#ok<AGROW>
        end
        for trial = 1:localTrialsForDrop(ulTrials, seedCount, drop)
            ulRows(end+1, 1) = localRuntimeTrialRow("UL", point, snr(point), drop, ulSeed); %#ok<AGROW>
        end
    end
end
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "fixed_link_campaign_task_plan.csv"), struct2table(taskRows));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "dl_fixed_link_campaign_trials.csv"), struct2table(dlRows));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "ul_fixed_link_campaign_trials.csv"), struct2table(ulRows));
end

function count = localTrialsForDrop(totalTrials, seedCount, drop)
count = floor(double(totalTrials) / double(seedCount));
if drop <= mod(double(totalTrials), double(seedCount))
    count = count + 1;
end
end

function row = localTaskRow(direction, point, snr, drop, seed)
row = struct("TaskKind", "point_drop_link", "LinkToken", string(direction), ...
    "PointIndex", double(point), "PointValue", double(snr), ...
    "DropIndex", double(drop), "TaskSeed", double(seed), ...
    "SchedulingInvariant", "worker_order_independent_seed_per_task");
end

function row = localTrialRow()
row = struct("FixedLinkPointIndex", NaN, "FixedLinkDropIndex", NaN, ...
    "FixedLinkDropSeed", NaN, "FixedLinkSeedIndex", NaN, ...
    "FixedLinkSeedValue", NaN, "SNR_dB", NaN, "CRCPass", true, ...
    "Status", "PASS", "Goodput_Mbps", 1.0, "Direction", "");
end

function row = localRuntimeTrialRow(direction, point, snr, drop, seed)
row = localTrialRow();
row.FixedLinkPointIndex = double(point);
row.FixedLinkDropIndex = double(drop);
row.FixedLinkDropSeed = double(seed);
row.FixedLinkSeedIndex = double(drop);
% Task/drop seeds vary with direction and operating point.  The configured
% YAML seed value is intentionally paired across all groups.
row.FixedLinkSeedValue = 700000 + double(drop);
row.SNR_dB = double(snr);
row.Direction = string(direction);
end
