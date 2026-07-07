function campaign = runFixedLinkCampaign(cfg, varargin)
%RUNFIXEDLINKCAMPAIGN Execute controlled fixed-link BLER/BER/throughput campaigns.

ip = inputParser;
ip.addRequired("cfg", @(x)builtin("isstruct", x) && isscalar(x));
ip.addParameter("Config", struct(), @(x)builtin("isstruct", x) && isscalar(x));
ip.addParameter("RootRunFolder", "", @(x)ischar(x) || isstring(x));
ip.addParameter("WriteArtifacts", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(cfg, varargin{:});
opt = ip.Results;

campaignCfg = localResolveCampaignConfig(cfg, opt.Config);
campaign = localEmptyCampaign(campaignCfg);
if ~logical(campaignCfg.Enabled)
    return;
end

cfgBase = localPrepareCampaignCfg(cfg, campaignCfg);
dlMCS = localResolveDirectionMCS(cfgBase, campaignCfg, "DL");
ulMCS = localResolveDirectionMCS(cfgBase, campaignCfg, "UL");
sharedMCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(campaignCfg, "MCS", []), []);
useSharedMCS = ~isempty(sharedMCS);
if useSharedMCS
    loopMCS = sharedMCS;
else
    loopMCS = NaN;
end

summaryRows = repmat(localEmptySummaryRow(0), 0, 1);
taskPlan = table();
dlTrials = table();
ulTrials = table();
pointIndex = 0;

for mcs = reshape(double(loopMCS), 1, [])
    for snr = reshape(double(campaignCfg.SNR_dB), 1, [])
        pointIndex = pointIndex + 1;
        row = localEmptySummaryRow(snr);
        row.CampaignKind = "fixed_link_monte_carlo";
        row.SweepKind = "fixed_reference_awgn_snr_campaign";
        row.FixedReferenceMode = true;
        row.NoiseOperatingMode = "standalone_awgn_snr_argument";
        row.ConfidenceLevel = double(campaignCfg.ConfidenceLevel);
        row.SequentialMinTrials = double(campaignCfg.MinTBPerPoint);
        row.SequentialMaxTrials = double(campaignCfg.MaxTBPerPoint);
        row.SequentialErrorTarget = double(campaignCfg.MinErrorsForCI);
        row.SequentialCIWidthTarget = 2 * double(campaignCfg.MaxCIHalfWidth);
        row.TrialsPerDrop = double(campaignCfg.BatchTBCount);
        row.PointIndex = double(pointIndex);
        row.PointSeed = double(localPointSeed(campaignCfg, pointIndex, localNaNToZero(mcs)));
        row.MCSIndex = double(mcs);
        row.DLMCSIndex = localFirstFinite(dlMCS, NaN);
        row.ULMCSIndex = localFirstFinite(ulMCS, NaN);
        row.ConfiguredRank = double(campaignCfg.Rank);
        row.ConfiguredLayers = double(campaignCfg.Layers);
        row.ConfiguredPRBCount = double(campaignCfg.NPRB);
        row.ConfiguredChannelModel = string(campaignCfg.ChannelModelResolved);
        row.DirectionMode = string(campaignCfg.Direction);
        row.DL_TargetBLER = double(campaignCfg.PrimaryTargetBLER);
        row.UL_TargetBLER = double(campaignCfg.PrimaryTargetBLER);

        dlPointMCS = localPointMCS(useSharedMCS, mcs, dlMCS);
        if localDirectionEnabled(campaignCfg, "DL") && isfinite(dlPointMCS)
            row.DLMCSIndex = double(dlPointMCS);
            [statsDL, trialsDL, planDL] = localRunDirectionPoint(cfgBase, campaignCfg, "DL", snr, dlPointMCS, pointIndex, row.PointSeed);
            row = localApplyDirectionStats(row, "DL", statsDL);
            dlTrials = localAppendCompatTable(dlTrials, trialsDL);
            taskPlan = localAppendCompatTable(taskPlan, planDL);
        end

        ulPointMCS = localPointMCS(useSharedMCS, mcs, ulMCS);
        if localDirectionEnabled(campaignCfg, "UL") && isfinite(ulPointMCS)
            row.ULMCSIndex = double(ulPointMCS);
            [statsUL, trialsUL, planUL] = localRunDirectionPoint(cfgBase, campaignCfg, "UL", snr, ulPointMCS, pointIndex, row.PointSeed);
            row = localApplyDirectionStats(row, "UL", statsUL);
            ulTrials = localAppendCompatTable(ulTrials, trialsUL);
            taskPlan = localAppendCompatTable(taskPlan, planUL);
        end

        summaryRows(end+1, 1) = row; %#ok<AGROW>
    end
end

summary = struct2table(summaryRows, "AsArray", true);
summary = localAnnotatePrimaryTargetCrossings(summary, campaignCfg);
reportTables = localBuildReportTables(summary, dlTrials, ulTrials, campaignCfg);

campaign.Summary = summary;
campaign.DLTrials = dlTrials;
campaign.ULTrials = ulTrials;
campaign.TaskPlan = taskPlan;
campaign.DLBlerCurve = reportTables.DLBlerCurve;
campaign.ULBlerCurve = reportTables.ULBlerCurve;
campaign.DLBerCurve = reportTables.DLBerCurve;
campaign.ULBerCurve = reportTables.ULBerCurve;
campaign.ReportSummary = reportTables.Summary;
campaign.TargetCrossings = reportTables.TargetCrossings;
campaign.ReportTables = reportTables;
campaign.PointCount = double(height(summary));
campaign.Notes = "fixed_link_campaign_uses_waveform_dl_ul_kernels_with_controlled_post_channel_awgn";

if logical(opt.WriteArtifacts) && strlength(strtrim(string(opt.RootRunFolder))) > 0
    localWriteReportArtifacts(char(string(opt.RootRunFolder)), campaign);
end
end

function campaign = localEmptyCampaign(campaignCfg)
campaign = struct( ...
    "Enabled", logical(sixgr.util.structGet(campaignCfg, "Enabled", false)), ...
    "CampaignKind", "fixed_link_monte_carlo", ...
    "Summary", table(), ...
    "DLTrials", table(), ...
    "ULTrials", table(), ...
    "TaskPlan", table(), ...
    "SNRGrid_dB", double(sixgr.util.structGet(campaignCfg, "SNR_dB", [])), ...
    "SeedBase", double(sixgr.util.structGet(campaignCfg, "SeedBase", NaN)), ...
    "DLBlerCurve", localEmptyCurveTable(), ...
    "ULBlerCurve", localEmptyCurveTable(), ...
    "DLBerCurve", localEmptyCurveTable(), ...
    "ULBerCurve", localEmptyCurveTable(), ...
    "ReportSummary", localEmptySummaryReportTable(), ...
    "TargetCrossings", localEmptyTargetCrossingTable(), ...
    "ReportTables", struct(), ...
    "PointCount", 0, ...
    "Notes", "");
end

function cfgOut = localPrepareCampaignCfg(cfgIn, campaignCfg)
cfgOut = cfgIn;
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.users.enabled", false);
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.users.n_users", 1);
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.mode", "fixed");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.dlPolicy", "fixed");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.ulPolicy", "fixed");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.rankPolicy", "fixed");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.beamPolicy", "fixed");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.deltaCQIPolicy", "none");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.deltaMCSPolicy", "none");
cfgOut = sixgr.util.structSet(cfgOut, "phy.linkAdaptation.fixedReferenceMode", true);
cfgOut = sixgr.util.structSet(cfgOut, "run.fixedReferenceMode", true);
cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
cfgOut = sixgr.util.structSet(cfgOut, "phy.harq.enable", false);
cfgOut = sixgr.util.structSet(cfgOut, "mac.harq.enable", false);

cfgOut = localApplyChannelModel(cfgOut, campaignCfg);
cfgOut = localApplyLayerAndPRBConfig(cfgOut, campaignCfg);
cfgOut = localDisableCampaignReferenceSignals(cfgOut, campaignCfg);
end

function cfgOut = localApplyChannelModel(cfgOut, campaignCfg)
model = upper(string(sixgr.util.structGet(campaignCfg, "ChannelModel", "AWGN")));
cfgOut = sixgr.util.structSet(cfgOut, "channel.model", model);
switch model
    case "AWGN"
        cfgOut = sixgr.util.structSet(cfgOut, "channel.awgnOnly", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.fading.enable", false);
    case "TDL"
        cfgOut = sixgr.util.structSet(cfgOut, "channel.awgnOnly", false);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.fading.enable", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.tdlProfile", string(campaignCfg.ChannelProfileResolved));
        cfgOut = sixgr.util.structSet(cfgOut, "channel.fading.profile", string(campaignCfg.ChannelProfileResolved));
    case "CDL"
        cfgOut = sixgr.util.structSet(cfgOut, "channel.awgnOnly", false);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.fading.enable", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.cdlProfile", string(campaignCfg.ChannelProfileResolved));
        cfgOut = sixgr.util.structSet(cfgOut, "channel.fading.profile", string(campaignCfg.ChannelProfileResolved));
end
end

function cfgOut = localApplyLayerAndPRBConfig(cfgOut, campaignCfg)
layers = max(1, round(double(campaignCfg.Layers)));
rank = max(1, round(double(campaignCfg.Rank)));
nPRB = max(1, round(double(campaignCfg.NPRB)));
prbSet = 0:max(nPRB - 1, 0);

for root = ["phy.pdsch", "phy.pusch"]
    cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", layers);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", layers);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".rank", rank);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".PRBSet", prbSet);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", nPRB);
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", nPRB);
cfgOut = sixgr.util.structSet(cfgOut, "phy.numerology.activeGridNumRBs", nPRB);
cfgOut = sixgr.util.structSet(cfgOut, "phy.numerology.configuredGridNumRBs", nPRB);
end

function cfgOut = localDisableCampaignReferenceSignals(cfgOut, campaignCfg)
nPRB = max(1, round(double(campaignCfg.NPRB)));
for path = { ...
        "phy.pbch.enable"
        "phy.mib.enable"
        "phy.sib1.enable"
        "phy.pdcch.enable"
        "phy.pucch.enable"
        "phy.prach.enable"
        "phy.csirs.enable"
        "phy.srs.enable"
        "phy.trs.enable"
        "phy.ptrs.enable"
        "phy.csi.enable"
        "reference_signals.pbch_enabled"
        "reference_signals.csi_rs_enabled"
        "reference_signals.nzp_csi_rs.enabled"
        "reference_signals.srs_enabled"
        "reference_signals.trs_enabled"
        "reference_signals.ptrs_enabled"}
    cfgOut = sixgr.util.structSet(cfgOut, char(path{1}), false);
end
cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.numRB", nPRB);
cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.rbOffset", 0);
cfgOut = sixgr.util.structSet(cfgOut, "phy.trs.numRB", nPRB);
cfgOut = sixgr.util.structSet(cfgOut, "phy.trs.rbOffset", 0);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.enablePTRS", false);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.enablePTRS", false);
cfgOut = sixgr.util.structSet(cfgOut, "phy.csirs.replayDisabledReason", ...
    "fixed_link_campaign_disables_runtime_reference_signals_for_controlled_tb_trials");
end

function [stats, T, taskPlan] = localRunDirectionPoint(cfgBase, campaignCfg, direction, snr, mcs, pointIndex, pointSeed)
direction = upper(string(direction));
T = table();
taskPlan = localEmptyTaskPlanTable();
completed = 0;
dropIndex = 0;

while true
    stats = localSummarizeDirectionTrials(T, cfgBase);
    [shouldStop, stopReason, incomplete] = localShouldStopPoint(stats, campaignCfg);
    if shouldStop
        stats.StopReason = stopReason;
        stats.Incomplete = incomplete;
        stats.PointSeed = double(pointSeed);
        return;
    end

    remaining = max(0, round(double(campaignCfg.MaxTBPerPoint)) - completed);
    if remaining <= 0
        stats.StopReason = "max_tb_per_point_reached";
        stats.Incomplete = localPointIncomplete(stats, campaignCfg);
        stats.PointSeed = double(pointSeed);
        return;
    end

    dropIndex = dropIndex + 1;
    seedIndex = 1 + mod(dropIndex - 1, numel(campaignCfg.Seeds));
    seedValue = double(campaignCfg.Seeds(seedIndex));
    taskSeed = double(sixgr.util.hierarchicalSeed(seedValue, pointIndex, dropIndex, mcs, direction));
    batchTBCount = max(1, min(round(double(campaignCfg.BatchTBCount)), remaining));
    startFrame = completed + 1;
    cfgPoint = localConfigureDirectionPoint(cfgBase, campaignCfg, direction, snr, mcs, taskSeed);

    if direction == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfgPoint, ...
            "NumFrames", batchTBCount, ...
            "SNR_dB", snr, ...
            "StartFrameIndex", startFrame);
    else
        res = sixgr.link.runULPUSCHThroughput(cfgPoint, ...
            "NumFrames", batchTBCount, ...
            "SNR_dB", snr, ...
            "StartFrameIndex", startFrame);
    end

    if logical(sixgr.util.structGet(res, "Skipped", false))
        error("sixgr:lls6g:campaign:FixedLinkPointSkipped", ...
            "%s fixed-link campaign point %.6g dB skipped: %s", ...
            direction, double(snr), string(sixgr.util.structGet(res, "Notes", "")));
    end

    Ti = sixgr.util.structGet(res, "TrialTable", table());
    if ~(istable(Ti) && ~isempty(Ti))
        error("sixgr:lls6g:campaign:MissingTrialTable", ...
            "%s fixed-link campaign point %.6g dB produced no trial rows.", ...
            direction, double(snr));
    end

    Ti = localAnnotateTrialRows(Ti, direction, snr, pointIndex, dropIndex, taskSeed, seedIndex, seedValue, completed, campaignCfg, mcs, pointSeed);
    T = localAppendCompatTable(T, Ti);
    completed = height(localEffectiveTrialRows(T));
    taskPlan = localAppendCompatTable(taskPlan, ...
        localTaskPlanRow(direction, snr, mcs, pointIndex, dropIndex, startFrame, height(Ti), pointSeed, taskSeed, seedIndex, seedValue, campaignCfg));
end
end

function cfgPoint = localConfigureDirectionPoint(cfgBase, campaignCfg, direction, snr, mcs, taskSeed)
cfgPoint = cfgBase;
cfgPoint = sixgr.util.structSet(cfgPoint, "run.seed", double(taskSeed));
cfgPoint = sixgr.util.structSet(cfgPoint, "channel.snr_dB", double(snr));
cfgPoint = sixgr.util.structSet(cfgPoint, "run.noiseOperatingMode", "standalone_awgn_snr_argument");

if direction == "DL"
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pdsch.enable", true);
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pusch.enable", false);
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pdsch.mcsIndex", double(mcs));
else
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pdsch.enable", false);
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pusch.enable", true);
    cfgPoint = sixgr.util.structSet(cfgPoint, "phy.pusch.mcsIndex", double(mcs));
end

cfgPoint = localApplyLayerAndPRBConfig(cfgPoint, campaignCfg);
cfgPoint = localDisableCampaignReferenceSignals(cfgPoint, campaignCfg);
end

function T = localAnnotateTrialRows(T, direction, snr, pointIndex, dropIndex, taskSeed, seedIndex, seedValue, completed, campaignCfg, mcs, pointSeed)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);

T.FixedLinkCampaign = true(n, 1);
T.FixedLinkCampaignKind = repmat("fixed_link_monte_carlo", n, 1);
T.FixedReferenceMode = true(n, 1);
T.FixedLinkPointIndex = repmat(double(pointIndex), n, 1);
T.FixedLinkDropIndex = repmat(double(dropIndex), n, 1);
T.FixedLinkDropSeed = repmat(double(taskSeed), n, 1);
T.FixedLinkTrialIndex = double(completed) + (1:n).';
T.FixedLinkDirection = repmat(upper(string(direction)), n, 1);
T.FixedLinkNoiseVariable = repmat("SNR_dB", n, 1);
T.FixedLinkConfidenceLevel = repmat(double(campaignCfg.ConfidenceLevel), n, 1);
T.FixedLinkSeedIndex = repmat(double(seedIndex), n, 1);
T.FixedLinkSeedValue = repmat(double(seedValue), n, 1);
T.FixedLinkConfiguredMCS = repmat(double(mcs), n, 1);
T.FixedLinkConfiguredRank = repmat(double(campaignCfg.Rank), n, 1);
T.FixedLinkConfiguredLayers = repmat(double(campaignCfg.Layers), n, 1);
T.FixedLinkConfiguredPRBCount = repmat(double(campaignCfg.NPRB), n, 1);
T.FixedLinkConfiguredChannelModel = repmat(string(campaignCfg.ChannelModelResolved), n, 1);
T.PointSeed = repmat(double(pointSeed), n, 1);
T.FixedLinkSeedHierarchy = "campaign=" + string(double(campaignCfg.SeedBase)) + ...
    "|point=" + string(double(pointIndex)) + ...
    "|drop=" + string(double(dropIndex)) + ...
    "|trial=" + string(T.FixedLinkTrialIndex) + ...
    "|seed_index=" + string(double(seedIndex)) + ...
    "|link=" + upper(string(direction));

if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = repmat(upper(string(direction)), n, 1);
end
if ~ismember("SNR_dB", string(T.Properties.VariableNames))
    T.SNR_dB = repmat(double(snr), n, 1);
else
    snrCol = double(T.SNR_dB);
    snrCol(~isfinite(snrCol)) = double(snr);
    T.SNR_dB = snrCol;
end
if ~ismember("ConfiguredSNR_dB", string(T.Properties.VariableNames))
    T.ConfiguredSNR_dB = repmat(double(snr), n, 1);
end
end

function stats = localSummarizeDirectionTrials(T, cfg)
stats = localEmptyDirectionStats();
Te = localEffectiveTrialRows(T);
if isempty(Te)
    stats.TrialCount = 0;
    stats.FailureCount = 0;
    return;
end

failMask = localTrialFailureMask(Te);
stats.TrialCount = double(height(Te));
stats.FailureCount = double(sum(failMask));
stats.BLER = localSafeDivide(stats.FailureCount, stats.TrialCount);
stats.BLER_CI_Method = "wilson_95pct";
stats.BER_CI_Method = "wilson_95pct";
stats.BLER_CI_Width = NaN;
stats.BLER_CI_HalfWidth = NaN;
stats.BER_CI_Width = NaN;
stats.BER_CI_HalfWidth = NaN;
stats.StopReason = "continue";
stats.Incomplete = false;

[~, blerHalfWidth, stats.BLER_CI_Low, stats.BLER_CI_High] = sixgr.stats.wilsonBinomialCI(stats.FailureCount, stats.TrialCount);
stats.BLER_CI_HalfWidth = double(blerHalfWidth);
stats.BLER_CI_Width = 2 * double(blerHalfWidth);

bitErr = localNumericColumn(Te, ["BitErrors"], 0);
bits = localNumericColumn(Te, ["BitsCompared", "TBSize_bits"], 0);
bitErrTotal = sum(bitErr, "omitnan");
bitTotal = sum(bits, "omitnan");
stats.BER = localSafeDivide(bitErrTotal, bitTotal);
if isfinite(bitTotal) && bitTotal > 0
    [~, berHalfWidth, stats.BER_CI_Low, stats.BER_CI_High] = sixgr.stats.wilsonBinomialCI(bitErrTotal, bitTotal);
    stats.BER_CI_HalfWidth = double(berHalfWidth);
    stats.BER_CI_Width = 2 * double(berHalfWidth);
end

goodputSamples = localNumericColumn(Te, ["Goodput_Mbps", "Throughput_Mbps"], NaN);
[stats.Throughput_Mbps, stats.Throughput_CI_Low, stats.Throughput_CI_High] = localMeanCI(goodputSamples);
stats.OfferedThroughput_Mbps = localMeanOrNaN(localNumericColumn(Te, ["OfferedThroughput_Mbps"], NaN));
stats.Goodput_Mbps = localMeanOrNaN(localNumericColumn(Te, ["Goodput_Mbps", "Throughput_Mbps"], NaN));
stats.CodeBlockBLER = localSafeDivide(sum(localNumericColumn(Te, ["CodeBlockErrors"], 0), "omitnan"), ...
    sum(localNumericColumn(Te, ["CodeBlockCount"], 0), "omitnan"));
stats.CBG_BLER = localSafeDivide(sum(localNumericColumn(Te, ["CBGErrors"], 0), "omitnan"), ...
    sum(localNumericColumn(Te, ["CBGCount"], 0), "omitnan"));
stats.DecodeLatency_ms = localMeanOrNaN(localNumericColumn(Te, ["DecodeLatency_ms"], NaN));
stats.DecoderComplexityUnits = localMeanOrNaN(localNumericColumn(Te, ["DecoderComplexityUnits"], NaN));
stats.NormalizedDecoderComplexity = localMeanOrNaN(localNumericColumn(Te, ["NormalizedDecoderComplexity"], NaN));

measuredSINR = localNumericColumn(Te, ["PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN);
[stats.MeasuredSINR_dB, stats.MeasuredSINR_CI_Low, stats.MeasuredSINR_CI_High] = localMeanCI(measuredSINR);
stats.ConfiguredSNR_dB = localFirstFinite(localNumericColumn(Te, ["ConfiguredSNR_dB", "SNR_dB"], NaN), NaN);
stats.DropCount = double(localUniqueFiniteCount(localNumericColumn(Te, ["FixedLinkDropIndex"], NaN)));
end

function [shouldStop, stopReason, incomplete] = localShouldStopPoint(stats, campaignCfg)
trialCount = double(sixgr.util.structGet(stats, "TrialCount", 0));
failureCount = double(sixgr.util.structGet(stats, "FailureCount", 0));
halfWidth = double(sixgr.util.structGet(stats, "BLER_CI_HalfWidth", inf));

shouldStop = false;
stopReason = "continue";
incomplete = false;

if trialCount < double(campaignCfg.MinTBPerPoint)
    return;
end

metConfidence = isfinite(halfWidth) && halfWidth <= double(campaignCfg.MaxCIHalfWidth);
metErrorCount = failureCount >= double(campaignCfg.MinErrorsForCI);
if metConfidence && metErrorCount
    shouldStop = true;
    stopReason = "ci_target_reached";
    return;
end

if trialCount >= double(campaignCfg.MaxTBPerPoint)
    shouldStop = true;
    stopReason = "max_tb_per_point_reached";
    incomplete = ~(metConfidence && metErrorCount);
end
end

function tf = localPointIncomplete(stats, campaignCfg)
[~, ~, tf] = localShouldStopPoint(stats, campaignCfg);
end

function row = localTaskPlanRow(direction, snr, mcs, pointIndex, dropIndex, trialStartIndex, trialCount, pointSeed, taskSeed, seedIndex, seedValue, campaignCfg)
taskKey = localTaskKey(pointIndex, mcs, dropIndex, direction);
taskIndex = double(pointIndex) * 1e6 + double(max(mcs, 0)) * 1e3 + double(dropIndex);
row = table( ...
    double(taskIndex), ...
    string(taskKey), ...
    "point_drop_link", ...
    upper(string(direction)), ...
    "fixed_link_campaign_point_drop_link", ...
    double(pointIndex), ...
    double(snr), ...
    double(dropIndex), ...
    double(trialStartIndex), ...
    double(trialCount), ...
    double(pointSeed), ...
    double(taskSeed), ...
    double(seedIndex), ...
    double(seedValue), ...
    double(mcs), ...
    double(campaignCfg.Rank), ...
    double(campaignCfg.Layers), ...
    double(campaignCfg.NPRB), ...
    repmat("worker_order_independent_seed_per_task", 1, 1), ...
    'VariableNames', {'TaskIndex','TaskKey','TaskKind','LinkToken','ExecutionGranularity', ...
    'PointIndex','PointValue','DropIndex','TrialStartIndex','TrialCount','PointSeed','TaskSeed', ...
    'SeedIndex','SeedValue','MCSIndex','ConfiguredRank','ConfiguredLayers','ConfiguredPRBCount', ...
    'SchedulingInvariant'});
end

function key = localTaskKey(pointIndex, mcs, dropIndex, direction)
key = "point_" + string(double(pointIndex)) + "_mcs_" + string(double(mcs)) + ...
    "_drop_" + string(double(dropIndex)) + "_" + upper(string(direction));
end

function row = localEmptySummaryRow(snr)
row = struct( ...
    "SNR_dB", double(snr), ...
    "CampaignKind", "", ...
    "SweepKind", "", ...
    "FixedReferenceMode", false, ...
    "NoiseOperatingMode", "", ...
    "ConfidenceLevel", NaN, ...
    "SequentialMinTrials", NaN, ...
    "SequentialMaxTrials", NaN, ...
    "SequentialErrorTarget", NaN, ...
    "SequentialCIWidthTarget", NaN, ...
    "TrialsPerDrop", NaN, ...
    "PointIndex", NaN, ...
    "PointSeed", NaN, ...
    "MCSIndex", NaN, ...
    "DLMCSIndex", NaN, ...
    "ULMCSIndex", NaN, ...
    "ConfiguredRank", NaN, ...
    "ConfiguredLayers", NaN, ...
    "ConfiguredPRBCount", NaN, ...
    "ConfiguredChannelModel", "", ...
    "DirectionMode", "", ...
    "DL_BER", NaN, "DL_BER_CI_Low", NaN, "DL_BER_CI_High", NaN, "DL_BER_CI_HalfWidth", NaN, ...
    "DL_BLER", NaN, "DL_BLER_CI_Low", NaN, "DL_BLER_CI_High", NaN, "DL_BLER_CI_HalfWidth", NaN, "DL_TrialCount", NaN, "DL_FailureCount", NaN, ...
    "DL_BLER_CI_Method", "", "DL_BLER_CI_Width", NaN, "DL_BER_CI_Method", "", "DL_BER_CI_Width", NaN, ...
    "DL_StopReason", "", "DL_Incomplete", false, "DL_TargetBLER", NaN, ...
    "DL_TargetCrossingStatus", "", "DL_TargetCrossingSNR_dB", NaN, ...
    "DL_Throughput_Mbps", NaN, "DL_Throughput_CI_Low", NaN, "DL_Throughput_CI_High", NaN, ...
    "DL_OfferedThroughput_Mbps", NaN, "DL_Goodput_Mbps", NaN, "DL_CodeBlockBLER", NaN, "DL_CBG_BLER", NaN, ...
    "DL_DecodeLatency_ms", NaN, "DL_DecoderComplexityUnits", NaN, "DL_NormalizedDecoderComplexity", NaN, ...
    "DL_MeasuredSINR_dB", NaN, "DL_MeasuredSINR_CI_Low", NaN, "DL_MeasuredSINR_CI_High", NaN, ...
    "UL_BER", NaN, "UL_BER_CI_Low", NaN, "UL_BER_CI_High", NaN, "UL_BER_CI_HalfWidth", NaN, ...
    "UL_BLER", NaN, "UL_BLER_CI_Low", NaN, "UL_BLER_CI_High", NaN, "UL_BLER_CI_HalfWidth", NaN, "UL_TrialCount", NaN, "UL_FailureCount", NaN, ...
    "UL_BLER_CI_Method", "", "UL_BLER_CI_Width", NaN, "UL_BER_CI_Method", "", "UL_BER_CI_Width", NaN, ...
    "UL_StopReason", "", "UL_Incomplete", false, "UL_TargetBLER", NaN, ...
    "UL_TargetCrossingStatus", "", "UL_TargetCrossingSNR_dB", NaN, ...
    "UL_Throughput_Mbps", NaN, "UL_Throughput_CI_Low", NaN, "UL_Throughput_CI_High", NaN, ...
    "UL_OfferedThroughput_Mbps", NaN, "UL_Goodput_Mbps", NaN, "UL_CodeBlockBLER", NaN, "UL_CBG_BLER", NaN, ...
    "UL_DecodeLatency_ms", NaN, "UL_DecoderComplexityUnits", NaN, "UL_NormalizedDecoderComplexity", NaN, ...
    "UL_MeasuredSINR_dB", NaN, "UL_MeasuredSINR_CI_Low", NaN, "UL_MeasuredSINR_CI_High", NaN);
end

function stats = localEmptyDirectionStats()
stats = struct( ...
    "TrialCount", 0, ...
    "FailureCount", 0, ...
    "BER", NaN, ...
    "BER_CI_Low", NaN, ...
    "BER_CI_High", NaN, ...
    "BER_CI_HalfWidth", NaN, ...
    "BER_CI_Width", NaN, ...
    "BLER", NaN, ...
    "BLER_CI_Low", NaN, ...
    "BLER_CI_High", NaN, ...
    "BLER_CI_HalfWidth", NaN, ...
    "BLER_CI_Width", NaN, ...
    "BLER_CI_Method", "", ...
    "BER_CI_Method", "", ...
    "StopReason", "continue", ...
    "Incomplete", false, ...
    "Throughput_Mbps", NaN, ...
    "Throughput_CI_Low", NaN, ...
    "Throughput_CI_High", NaN, ...
    "OfferedThroughput_Mbps", NaN, ...
    "Goodput_Mbps", NaN, ...
    "CodeBlockBLER", NaN, ...
    "CBG_BLER", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "DecoderComplexityUnits", NaN, ...
    "NormalizedDecoderComplexity", NaN, ...
    "MeasuredSINR_dB", NaN, ...
    "MeasuredSINR_CI_Low", NaN, ...
    "MeasuredSINR_CI_High", NaN, ...
    "ConfiguredSNR_dB", NaN, ...
    "DropCount", NaN, ...
    "PointSeed", NaN);
end

function row = localApplyDirectionStats(row, prefix, stats)
prefix = upper(string(prefix));
row.(char(prefix + "_BER")) = double(sixgr.util.structGet(stats, "BER", NaN));
row.(char(prefix + "_BER_CI_Low")) = double(sixgr.util.structGet(stats, "BER_CI_Low", NaN));
row.(char(prefix + "_BER_CI_High")) = double(sixgr.util.structGet(stats, "BER_CI_High", NaN));
row.(char(prefix + "_BER_CI_HalfWidth")) = double(sixgr.util.structGet(stats, "BER_CI_HalfWidth", NaN));
row.(char(prefix + "_BER_CI_Width")) = double(sixgr.util.structGet(stats, "BER_CI_Width", NaN));
row.(char(prefix + "_BLER")) = double(sixgr.util.structGet(stats, "BLER", NaN));
row.(char(prefix + "_BLER_CI_Low")) = double(sixgr.util.structGet(stats, "BLER_CI_Low", NaN));
row.(char(prefix + "_BLER_CI_High")) = double(sixgr.util.structGet(stats, "BLER_CI_High", NaN));
row.(char(prefix + "_BLER_CI_HalfWidth")) = double(sixgr.util.structGet(stats, "BLER_CI_HalfWidth", NaN));
row.(char(prefix + "_BLER_CI_Width")) = double(sixgr.util.structGet(stats, "BLER_CI_Width", NaN));
row.(char(prefix + "_TrialCount")) = double(sixgr.util.structGet(stats, "TrialCount", NaN));
row.(char(prefix + "_FailureCount")) = double(sixgr.util.structGet(stats, "FailureCount", NaN));
row.(char(prefix + "_BLER_CI_Method")) = string(sixgr.util.structGet(stats, "BLER_CI_Method", ""));
row.(char(prefix + "_BER_CI_Method")) = string(sixgr.util.structGet(stats, "BER_CI_Method", ""));
row.(char(prefix + "_StopReason")) = string(sixgr.util.structGet(stats, "StopReason", ""));
row.(char(prefix + "_Incomplete")) = logical(sixgr.util.structGet(stats, "Incomplete", false));
row.(char(prefix + "_Throughput_Mbps")) = double(sixgr.util.structGet(stats, "Throughput_Mbps", NaN));
row.(char(prefix + "_Throughput_CI_Low")) = double(sixgr.util.structGet(stats, "Throughput_CI_Low", NaN));
row.(char(prefix + "_Throughput_CI_High")) = double(sixgr.util.structGet(stats, "Throughput_CI_High", NaN));
row.(char(prefix + "_OfferedThroughput_Mbps")) = double(sixgr.util.structGet(stats, "OfferedThroughput_Mbps", NaN));
row.(char(prefix + "_Goodput_Mbps")) = double(sixgr.util.structGet(stats, "Goodput_Mbps", NaN));
row.(char(prefix + "_CodeBlockBLER")) = double(sixgr.util.structGet(stats, "CodeBlockBLER", NaN));
row.(char(prefix + "_CBG_BLER")) = double(sixgr.util.structGet(stats, "CBG_BLER", NaN));
row.(char(prefix + "_DecodeLatency_ms")) = double(sixgr.util.structGet(stats, "DecodeLatency_ms", NaN));
row.(char(prefix + "_DecoderComplexityUnits")) = double(sixgr.util.structGet(stats, "DecoderComplexityUnits", NaN));
row.(char(prefix + "_NormalizedDecoderComplexity")) = double(sixgr.util.structGet(stats, "NormalizedDecoderComplexity", NaN));
row.(char(prefix + "_MeasuredSINR_dB")) = double(sixgr.util.structGet(stats, "MeasuredSINR_dB", NaN));
row.(char(prefix + "_MeasuredSINR_CI_Low")) = double(sixgr.util.structGet(stats, "MeasuredSINR_CI_Low", NaN));
row.(char(prefix + "_MeasuredSINR_CI_High")) = double(sixgr.util.structGet(stats, "MeasuredSINR_CI_High", NaN));
end

function summary = localAnnotatePrimaryTargetCrossings(summary, campaignCfg)
if ~(istable(summary) && ~isempty(summary))
    return;
end

target = double(campaignCfg.PrimaryTargetBLER);
for prefix = ["DL", "UL"]
    blerCol = prefix + "_BLER";
    if ~ismember(char(blerCol), summary.Properties.VariableNames)
        continue;
    end
    [statuses, crossings] = localPerMCSTargetCrossings(summary, prefix, target);
    summary.(char(prefix + "_TargetBLER")) = repmat(target, height(summary), 1);
    summary.(char(prefix + "_TargetCrossingStatus")) = statuses;
    summary.(char(prefix + "_TargetCrossingSNR_dB")) = crossings;
end
end

function [statusCol, snrCol] = localPerMCSTargetCrossings(summary, prefix, target)
statusCol = repmat("not_requested", height(summary), 1);
snrCol = NaN(height(summary), 1);
mcsCol = localDirectionMCSColumnName(prefix);
mcsValues = localNumericColumn(summary, [mcsCol, "MCSIndex"], NaN);
finiteMCS = unique(mcsValues(isfinite(mcsValues)));
for mcs = reshape(finiteMCS, 1, [])
    mask = mcsValues == mcs;
    if ~any(mask)
        continue;
    end
    [status, crossingSNR] = localTargetCrossingStatus(summary(mask, :), prefix, target);
    statusCol(mask) = string(status);
    snrCol(mask) = double(crossingSNR);
end
end

function [status, crossingSNR] = localTargetCrossingStatus(T, prefix, targetBLER)
status = "insufficient_finite_points";
crossingSNR = NaN;

x = localNumericColumn(T, ["SNR_dB"], NaN);
y = localNumericColumn(T, [prefix + "_BLER"], NaN);
mask = isfinite(x) & isfinite(y);
if nnz(mask) < 2
    return;
end

x = x(mask);
y = y(mask);
[x, order] = sort(x(:));
y = y(order);

for i = 1:numel(x) - 1
    y1 = y(i);
    y2 = y(i + 1);
    if (y1 >= targetBLER && y2 <= targetBLER) || (y1 <= targetBLER && y2 >= targetBLER)
        if abs(y2 - y1) < eps
            crossingSNR = x(i);
        else
            crossingSNR = x(i) + (targetBLER - y1) * (x(i + 1) - x(i)) / (y2 - y1);
        end
        status = "crossing_observed";
        return;
    end
end

if all(y > targetBLER)
    status = "no_crossing_all_points_above_target";
elseif all(y < targetBLER)
    status = "no_crossing_all_points_below_target";
else
    status = "non_monotonic_curve";
end
end

function reportTables = localBuildReportTables(summary, dlTrials, ulTrials, campaignCfg)
reportTables = struct();
reportTables.TaskPlan = localExecutedTaskPlan(summary);
reportTables.DLTrials = dlTrials;
reportTables.ULTrials = ulTrials;
reportTables.DLBlerCurve = localBuildCurveTable(summary, "DL", "BLER");
reportTables.ULBlerCurve = localBuildCurveTable(summary, "UL", "BLER");
reportTables.DLBerCurve = localBuildCurveTable(summary, "DL", "BER");
reportTables.ULBerCurve = localBuildCurveTable(summary, "UL", "BER");
reportTables.TargetCrossings = localBuildTargetCrossingTable(summary, campaignCfg);
reportTables.Summary = localBuildCampaignSummaryTable(summary, campaignCfg, reportTables.TargetCrossings);
end

function taskPlan = localExecutedTaskPlan(summary)
if ~(istable(summary) && ~isempty(summary))
    taskPlan = localEmptyTaskPlanTable();
    return;
end
taskPlan = localEmptyTaskPlanTable();
end

function T = localBuildCurveTable(summary, direction, metricKind)
if ~(istable(summary) && ~isempty(summary))
    T = localEmptyCurveTable();
    return;
end

prefix = upper(string(direction));
metricKind = upper(string(metricKind));
metricCol = char(prefix + "_" + metricKind);
trialCol = char(prefix + "_TrialCount");
mcsCol = localDirectionMCSColumnName(prefix);
if ~all(ismember(string({metricCol, trialCol}), string(summary.Properties.VariableNames)))
    T = localEmptyCurveTable();
    return;
end

mask = isfinite(localNumericColumn(summary, [metricCol], NaN)) & localNumericColumn(summary, [trialCol], 0) > 0;
if ~any(mask)
    T = localEmptyCurveTable();
    return;
end

sub = summary(mask, :);
T = table( ...
    repmat(prefix, height(sub), 1), ...
    localNumericColumn(sub, [mcsCol, "MCSIndex"], NaN), ...
    localNumericColumn(sub, ["PointIndex"], NaN), ...
    localNumericColumn(sub, ["PointSeed"], NaN), ...
    localNumericColumn(sub, ["SNR_dB"], NaN), ...
    repmat(string(metricKind), height(sub), 1), ...
    localNumericColumn(sub, [metricCol], NaN), ...
    localNumericColumn(sub, [prefix + "_" + metricKind + "_CI_Low"], NaN), ...
    localNumericColumn(sub, [prefix + "_" + metricKind + "_CI_High"], NaN), ...
    localNumericColumn(sub, [prefix + "_" + metricKind + "_CI_HalfWidth"], NaN), ...
    localNumericColumn(sub, [prefix + "_" + metricKind + "_CI_Width"], NaN), ...
    localNumericColumn(sub, [trialCol], NaN), ...
    localNumericColumn(sub, [prefix + "_FailureCount"], NaN), ...
    localNumericColumn(sub, [prefix + "_MeasuredSINR_dB"], NaN), ...
    localNumericColumn(sub, [prefix + "_MeasuredSINR_CI_Low"], NaN), ...
    localNumericColumn(sub, [prefix + "_MeasuredSINR_CI_High"], NaN), ...
    localNumericColumn(sub, [prefix + "_Throughput_Mbps"], NaN), ...
    localNumericColumn(sub, [prefix + "_Throughput_CI_Low"], NaN), ...
    localNumericColumn(sub, [prefix + "_Throughput_CI_High"], NaN), ...
    localNumericColumn(sub, [prefix + "_Goodput_Mbps"], NaN), ...
    localNumericColumn(sub, [prefix + "_OfferedThroughput_Mbps"], NaN), ...
    localNumericColumn(sub, ["ConfiguredRank"], NaN), ...
    localNumericColumn(sub, ["ConfiguredLayers"], NaN), ...
    localNumericColumn(sub, ["ConfiguredPRBCount"], NaN), ...
    string(localTextColumn(sub, ["ConfiguredChannelModel"], "")), ...
    string(localTextColumn(sub, [prefix + "_StopReason"], "")), ...
    localLogicalColumn(sub, [prefix + "_Incomplete"], false), ...
    localNumericColumn(sub, [prefix + "_TargetBLER"], NaN), ...
    string(localTextColumn(sub, [prefix + "_TargetCrossingStatus"], "")), ...
    localNumericColumn(sub, [prefix + "_TargetCrossingSNR_dB"], NaN), ...
    'VariableNames', {'Direction','MCSIndex','PointIndex','PointSeed','SNR_dB','Metric', ...
    'Value','CI_Low','CI_High','CI_HalfWidth','CI_Width','TrialCount','FailureCount', ...
    'MeasuredSINR_dB','MeasuredSINR_CI_Low','MeasuredSINR_CI_High', ...
    'Throughput_Mbps','Throughput_CI_Low','Throughput_CI_High','Goodput_Mbps','OfferedThroughput_Mbps', ...
    'ConfiguredRank','ConfiguredLayers','ConfiguredPRBCount','ConfiguredChannelModel', ...
    'StopReason','Incomplete','PrimaryTargetBLER','PrimaryTargetCrossingStatus','PrimaryTargetCrossingSNR_dB'});
end

function T = localBuildTargetCrossingTable(summary, campaignCfg)
rows = repmat(struct( ...
    "Direction", "", ...
    "MCSIndex", NaN, ...
    "TargetBLER", NaN, ...
    "CrossingStatus", "", ...
    "CrossingSNR_dB", NaN), 0, 1);

    if istable(summary) && ~isempty(summary)
    for prefix = ["DL", "UL"]
        mcsCol = localDirectionMCSColumnName(prefix);
        mcsValues = unique(localNumericColumn(summary, [mcsCol, "MCSIndex"], NaN));
        mcsValues = mcsValues(isfinite(mcsValues));
        for mcs = reshape(double(mcsValues), 1, [])
            mask = localNumericColumn(summary, [mcsCol, "MCSIndex"], NaN) == mcs;
            if ~any(mask) || all(~isfinite(localNumericColumn(summary(mask, :), [prefix + "_TrialCount"], NaN)))
                continue;
            end
            for target = reshape(double(campaignCfg.TargetBLER), 1, [])
                [status, crossingSNR] = localTargetCrossingStatus(summary(mask, :), prefix, target);
                rows(end+1, 1) = struct( ... %#ok<AGROW>
                    "Direction", char(prefix), ...
                    "MCSIndex", double(mcs), ...
                    "TargetBLER", double(target), ...
                    "CrossingStatus", char(string(status)), ...
                    "CrossingSNR_dB", double(crossingSNR));
            end
        end
    end
end

if isempty(rows)
    T = localEmptyTargetCrossingTable();
else
    T = struct2table(rows, "AsArray", true);
end
end

function T = localBuildCampaignSummaryTable(summary, campaignCfg, targetCrossings)
rows = repmat(struct( ...
    "Direction", "", ...
    "MCSIndex", NaN, ...
    "ConfiguredChannelModel", "", ...
    "ConfiguredRank", NaN, ...
    "ConfiguredLayers", NaN, ...
    "ConfiguredPRBCount", NaN, ...
    "SNRPointCount", NaN, ...
    "TotalTBCount", NaN, ...
    "TotalFailureCount", NaN, ...
    "MaxBLERCIHalfWidth", NaN, ...
    "IncompletePointCount", NaN, ...
    "CurvePresent", false, ...
    "ConfidenceIntervalsPresent", false, ...
    "Status", ""), 0, 1);

if ~(istable(summary) && ~isempty(summary))
    T = localEmptySummaryReportTable();
    return;
end

for prefix = ["DL", "UL"]
    mcsCol = localDirectionMCSColumnName(prefix);
    mcsValues = unique(localNumericColumn(summary, [mcsCol, "MCSIndex"], NaN));
    mcsValues = mcsValues(isfinite(mcsValues));
    for mcs = reshape(double(mcsValues), 1, [])
        mask = localNumericColumn(summary, [mcsCol, "MCSIndex"], NaN) == mcs;
        trialVals = localNumericColumn(summary(mask, :), [prefix + "_TrialCount"], NaN);
        if ~any(isfinite(trialVals) & trialVals > 0)
            continue;
        end
        ciVals = localNumericColumn(summary(mask, :), [prefix + "_BLER_CI_HalfWidth"], NaN);
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "Direction", char(prefix), ...
            "MCSIndex", double(mcs), ...
            "ConfiguredChannelModel", char(string(localTextScalar(summary(mask, :), "ConfiguredChannelModel", campaignCfg.ChannelModelResolved))), ...
            "ConfiguredRank", localFirstFinite(localNumericColumn(summary(mask, :), ["ConfiguredRank"], NaN), NaN), ...
            "ConfiguredLayers", localFirstFinite(localNumericColumn(summary(mask, :), ["ConfiguredLayers"], NaN), NaN), ...
            "ConfiguredPRBCount", localFirstFinite(localNumericColumn(summary(mask, :), ["ConfiguredPRBCount"], NaN), NaN), ...
            "SNRPointCount", double(sum(isfinite(localNumericColumn(summary(mask, :), ["SNR_dB"], NaN)))), ...
            "TotalTBCount", double(sum(trialVals, "omitnan")), ...
            "TotalFailureCount", double(sum(localNumericColumn(summary(mask, :), [prefix + "_FailureCount"], 0), "omitnan")), ...
            "MaxBLERCIHalfWidth", double(max(ciVals, [], "omitnan")), ...
            "IncompletePointCount", double(sum(localLogicalColumn(summary(mask, :), [prefix + "_Incomplete"], false))), ...
            "CurvePresent", true, ...
            "ConfidenceIntervalsPresent", any(isfinite(ciVals)), ...
            "Status", char(localSummaryStatus(summary(mask, :), prefix, targetCrossings, mcs)));
    end
end

if isempty(rows)
    T = localEmptySummaryReportTable();
else
    T = struct2table(rows, "AsArray", true);
end
end

function status = localSummaryStatus(summary, prefix, targetCrossings, mcs)
curvePresent = any(localNumericColumn(summary, [prefix + "_TrialCount"], 0) > 0);
ciPresent = any(isfinite(localNumericColumn(summary, [prefix + "_BLER_CI_HalfWidth"], NaN)));
incomplete = any(localLogicalColumn(summary, [prefix + "_Incomplete"], false));
hasCrossingRows = istable(targetCrossings) && ~isempty(targetCrossings) && ...
    any(string(targetCrossings.Direction) == prefix & double(targetCrossings.MCSIndex) == double(mcs));
if curvePresent && ciPresent && ~incomplete
    status = "complete";
elseif curvePresent && hasCrossingRows
    status = "partial";
else
    status = "missing";
end
end

function localWriteReportArtifacts(rootRunFolder, campaign)
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "fixed_link_campaign_task_plan.csv"), ...
    sixgr.util.structGet(campaign, "TaskPlan", localEmptyTaskPlanTable()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_link_campaign_trials.csv"), ...
    sixgr.util.structGet(campaign, "DLTrials", table()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_link_campaign_trials.csv"), ...
    sixgr.util.structGet(campaign, "ULTrials", table()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_link_bler_curve.csv"), ...
    sixgr.util.structGet(campaign, "DLBlerCurve", localEmptyCurveTable()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_link_bler_curve.csv"), ...
    sixgr.util.structGet(campaign, "ULBlerCurve", localEmptyCurveTable()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_link_ber_curve.csv"), ...
    sixgr.util.structGet(campaign, "DLBerCurve", localEmptyCurveTable()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_link_ber_curve.csv"), ...
    sixgr.util.structGet(campaign, "ULBerCurve", localEmptyCurveTable()));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "fixed_link_campaign_summary.csv"), ...
    sixgr.util.structGet(campaign, "ReportSummary", localEmptySummaryReportTable()));
end

function cfg = localResolveCampaignConfig(cfgIn, cfgOpt)
cfg = sixgr.util.structGet(cfgIn, "validation.fixed_link_campaign", struct());
if builtin("isstruct", cfgOpt) && ~isempty(fieldnames(cfgOpt))
    cfg = localOverlayStruct(cfg, cfgOpt);
end

cfg.Enabled = logical(sixgr.util.structGet(cfg, "Enabled", sixgr.util.structGet(cfg, "enabled", false)));
cfg.Direction = localResolveDirectionToken(sixgr.util.structGet(cfg, "Direction", sixgr.util.structGet(cfg, "direction", "both")));
cfg.ChannelModel = upper(string(sixgr.util.structGet(cfg, "ChannelModel", sixgr.util.structGet(cfg, "channel_model", "AWGN"))));
cfg.SNR_dB = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfg, "SNR_dB", sixgr.util.structGet(cfg, "snr_db", [])), []);
cfg.MCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfg, "MCS", sixgr.util.structGet(cfg, "mcs", [])), []);
cfg.DLMCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfg, "DLMCS", []), cfg.MCS);
cfg.ULMCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfg, "ULMCS", []), cfg.MCS);
cfg.Rank = localPositiveIntegerDefault(sixgr.util.structGet(cfg, "Rank", sixgr.util.structGet(cfg, "rank", ...
    sixgr.util.structGet(cfgIn, "phy.pdsch.rank", 1))), 1);
cfg.Layers = localPositiveIntegerDefault(sixgr.util.structGet(cfg, "Layers", sixgr.util.structGet(cfg, "layers", ...
    sixgr.util.structGet(cfgIn, "phy.pdsch.nLayers", sixgr.util.structGet(cfgIn, "phy.pusch.nLayers", 1)))), 1);
cfg.NPRB = localPositiveIntegerDefault(sixgr.util.structGet(cfg, "NPRB", sixgr.util.structGet(cfg, "n_prb", ...
    localDefaultNPRB(cfgIn))), max(1, localDefaultNPRB(cfgIn)));
cfg.MinTBPerPoint = localPositiveIntegerDefault(sixgr.util.structGet(cfg, "MinTBPerPoint", sixgr.util.structGet(cfg, "min_tb_per_point", 5000)), 5000);
cfg.MaxTBPerPoint = max(cfg.MinTBPerPoint, localPositiveIntegerDefault(sixgr.util.structGet(cfg, "MaxTBPerPoint", sixgr.util.structGet(cfg, "max_tb_per_point", 20000)), 20000));
cfg.MinErrorsForCI = max(0, round(double(sixgr.util.structGet(cfg, "MinErrorsForCI", sixgr.util.structGet(cfg, "min_errors_for_ci", 100)))));
cfg.MaxCIHalfWidth = localFiniteNonNegativeDefault(sixgr.util.structGet(cfg, "MaxCIHalfWidth", sixgr.util.structGet(cfg, "max_ci_half_width", 0.05)), 0.05);
cfg.Seeds = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfg, "Seeds", sixgr.util.structGet(cfg, "seeds", [])), ...
    double(sixgr.util.structGet(cfgIn, "run.seed", 1)) + 730001);
cfg.TargetBLER = localFiniteRowVector(sixgr.util.structGet(cfg, "TargetBLER", sixgr.util.structGet(cfg, "target_bler", [0.1 0.01])), [0.1 0.01]);
cfg.PrimaryTargetBLER = double(cfg.TargetBLER(1));
cfg.ConfidenceLevel = 0.95;
cfg.BatchTBCount = localPositiveIntegerDefault(sixgr.util.structGet(cfg, "BatchTBCount", 1), 1);
cfg.SeedBase = double(cfg.Seeds(1));
cfg.ChannelProfileResolved = localResolveConcreteChannelProfile(cfgIn, cfg.ChannelModel);
cfg.ChannelModelResolved = localResolvedChannelLabel(cfg.ChannelModel, cfg.ChannelProfileResolved);

if isempty(cfg.SNR_dB)
    cfg.SNR_dB = localFiniteRowVector(sixgr.util.structGet(cfgIn, "channel.snr_dB", 0), 0);
end
if isempty(cfg.DLMCS)
    cfg.DLMCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfgIn, "phy.pdsch.mcsIndex", 0), 0);
end
if isempty(cfg.ULMCS)
    cfg.ULMCS = localFiniteIntegerAwareRowVector(sixgr.util.structGet(cfgIn, "phy.pusch.mcsIndex", 0), 0);
end
end

function direction = localResolveDirectionToken(value)
token = lower(strtrim(string(value)));
switch token
    case "dl"
        direction = "DL";
    case "ul"
        direction = "UL";
    otherwise
        direction = "both";
end
end

function tf = localDirectionEnabled(campaignCfg, direction)
direction = upper(string(direction));
mode = string(campaignCfg.Direction);
tf = mode == "both" || mode == direction;
end

function mcsList = localResolveDirectionMCS(cfg, campaignCfg, direction)
direction = upper(string(direction));
if direction == "DL"
    defaultMCS = sixgr.util.structGet(cfg, "phy.pdsch.mcsIndex", 0);
    mcsList = localFiniteIntegerAwareRowVector(sixgr.util.structGet(campaignCfg, "DLMCS", []), defaultMCS);
else
    defaultMCS = sixgr.util.structGet(cfg, "phy.pusch.mcsIndex", 0);
    mcsList = localFiniteIntegerAwareRowVector(sixgr.util.structGet(campaignCfg, "ULMCS", []), defaultMCS);
end
end

function profile = localResolveConcreteChannelProfile(cfg, model)
model = upper(string(model));
switch model
    case "TDL"
        profile = upper(string(sixgr.util.structGet(cfg, "channel.tdlProfile", sixgr.util.structGet(cfg, "channel.fading.profile", "TDL-C"))));
        if strlength(profile) == 0 || ~startsWith(profile, "TDL-")
            profile = "TDL-C";
        end
    case "CDL"
        profile = upper(string(sixgr.util.structGet(cfg, "channel.cdlProfile", sixgr.util.structGet(cfg, "channel.fading.profile", "CDL-D"))));
        if strlength(profile) == 0 || ~startsWith(profile, "CDL-")
            profile = "CDL-D";
        end
    otherwise
        profile = "AWGN";
end
end

function label = localResolvedChannelLabel(model, profile)
model = upper(string(model));
if model == "AWGN"
    label = "AWGN";
else
    label = upper(string(profile));
end
end

function seed = localPointSeed(campaignCfg, pointIndex, mcs)
seed = double(sixgr.util.hierarchicalSeed(double(campaignCfg.SeedBase), pointIndex, 0, mcs, "POINT"));
end

function mcs = localPointMCS(useSharedMCS, sharedMCSValue, directionMCSList)
if useSharedMCS
    mcs = double(sharedMCSValue);
else
    mcs = localFirstFinite(directionMCSList, NaN);
end
end

function value = localNaNToZero(value)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    value = 0;
end
end

function name = localDirectionMCSColumnName(prefix)
prefix = upper(string(prefix));
if prefix == "DL"
    name = "DLMCSIndex";
else
    name = "ULMCSIndex";
end
end

function values = localFiniteRowVector(value, fallback)
values = double(value);
values = values(:).';
values = values(isfinite(values));
if isempty(values)
    values = double(fallback);
    values = values(:).';
    values = values(isfinite(values));
end
end

function values = localFiniteIntegerAwareRowVector(value, fallback)
values = localFiniteRowVector(value, fallback);
values = round(double(values));
values = unique(values, "stable");
end

function value = localPositiveIntegerDefault(value, fallback)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 1)
    value = double(fallback);
end
if ~(isscalar(value) && isfinite(value) && value >= 1)
    value = 1;
end
value = round(double(value));
end

function value = localFiniteNonNegativeDefault(value, fallback)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 0)
    value = double(fallback);
end
if ~(isscalar(value) && isfinite(value) && value >= 0)
    value = 0;
end
end

function value = localDefaultNPRB(cfg)
value = numel(double(sixgr.util.structGet(cfg, "phy.pdsch.PRBSet", [])));
if ~(isfinite(value) && value >= 1)
    value = numel(double(sixgr.util.structGet(cfg, "phy.pusch.PRBSet", [])));
end
if ~(isfinite(value) && value >= 1)
    value = double(sixgr.util.structGet(cfg, "phy.numerology.activeGridNumRBs", sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24)));
end
if ~(isfinite(value) && value >= 1)
    value = 24;
end
value = round(double(value));
end

function T = localEffectiveTrialRows(T)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
mask = true(height(T), 1);
if ismember("IsWarmupFrame", string(T.Properties.VariableNames))
    warmMask = logical(T.IsWarmupFrame);
    if any(~warmMask)
        mask = ~warmMask;
    end
end
T = T(mask, :);
end

function mask = localTrialFailureMask(T)
mask = false(height(T), 1);
if ismember("Status", string(T.Properties.VariableNames))
    status = upper(strtrim(string(T.Status)));
    mask = status == "FAIL" | status == "CRASH";
end
if ismember("CRCPass", string(T.Properties.VariableNames))
    crc = logical(T.CRCPass);
    mask = mask | ~crc;
end
end

function values = localNumericColumn(T, names, defaultValue)
values = [];
if ~(istable(T) && ~isempty(T))
    return;
end
names = localNameList(names);
vars = string(T.Properties.VariableNames);
for i = 1:numel(names)
    if ismember(names(i), vars)
        values = double(T.(char(names(i))));
        values(~isfinite(values)) = double(defaultValue);
        return;
    end
end
values = repmat(double(defaultValue), height(T), 1);
end

function values = localTextColumn(T, names, defaultValue)
if ~(istable(T) && ~isempty(T))
    values = strings(0, 1);
    return;
end
names = localNameList(names);
vars = string(T.Properties.VariableNames);
for i = 1:numel(names)
    if ismember(names(i), vars)
        values = string(T.(char(names(i))));
        return;
    end
end
values = repmat(string(defaultValue), height(T), 1);
end

function value = localTextScalar(T, name, defaultValue)
values = localTextColumn(T, name, defaultValue);
if isempty(values)
    value = string(defaultValue);
else
    value = values(1);
end
end

function values = localLogicalColumn(T, names, defaultValue)
if ~(istable(T) && ~isempty(T))
    values = false(0, 1);
    return;
end
names = localNameList(names);
vars = string(T.Properties.VariableNames);
for i = 1:numel(names)
    if ismember(names(i), vars)
        values = logical(T.(char(names(i))));
        return;
    end
end
values = repmat(logical(defaultValue), height(T), 1);
end

function value = localFirstFinite(values, fallback)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = double(fallback);
else
    value = double(values(idx));
end
end

function value = localMeanOrNaN(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values, "omitnan");
end
end

function [meanValue, lo, hi] = localMeanCI(values)
meanValue = NaN;
lo = NaN;
hi = NaN;
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    return;
end
meanValue = mean(values, "omitnan");
if numel(values) < 2
    lo = meanValue;
    hi = meanValue;
    return;
end
z = 1.95996398454005;
se = std(values, 0, "omitnan") / sqrt(numel(values));
lo = meanValue - z * se;
hi = meanValue + z * se;
end

function ratio = localSafeDivide(num, den)
num = double(num);
den = double(den);
if ~(isfinite(num) && isfinite(den) && den > 0)
    ratio = NaN;
    return;
end
ratio = num / den;
end

function n = localUniqueFiniteCount(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    n = 0;
else
    n = numel(unique(values));
end
end

function Tout = localAppendCompatTable(Ta, Tb)
if ~(istable(Ta) && ~isempty(Ta))
    Tout = Tb;
    return;
end
if ~(istable(Tb) && ~isempty(Tb))
    Tout = Ta;
    return;
end

varsA = string(Ta.Properties.VariableNames);
varsB = string(Tb.Properties.VariableNames);
allVars = union(varsA, varsB, "stable");

for v = reshape(allVars, 1, [])
    name = char(v);
    if ~ismember(v, varsA)
        Ta.(name) = localMissingLike(Tb.(name), height(Ta));
    end
    if ~ismember(v, varsB)
        Tb.(name) = localMissingLike(Ta.(name), height(Tb));
    end
end

Tout = [Ta(:, cellstr(allVars)); Tb(:, cellstr(allVars))];
end

function values = localMissingLike(sample, nRows)
if isnumeric(sample)
    values = NaN(nRows, size(sample, 2));
elseif islogical(sample)
    values = false(nRows, size(sample, 2));
elseif isstring(sample)
    values = strings(nRows, size(sample, 2));
elseif iscell(sample)
    values = cell(nRows, size(sample, 2));
else
    values = repmat(missing, nRows, size(sample, 2));
end
end

function T = localEmptyCurveTable()
T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), false(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    'VariableNames', {'Direction','MCSIndex','PointIndex','PointSeed','SNR_dB','Metric', ...
    'Value','CI_Low','CI_High','CI_HalfWidth','CI_Width','TrialCount','FailureCount', ...
    'MeasuredSINR_dB','MeasuredSINR_CI_Low','MeasuredSINR_CI_High', ...
    'Throughput_Mbps','Throughput_CI_Low','Throughput_CI_High','Goodput_Mbps','OfferedThroughput_Mbps', ...
    'ConfiguredRank','ConfiguredLayers','ConfiguredPRBCount','ConfiguredChannelModel', ...
    'StopReason','Incomplete','PrimaryTargetBLER','PrimaryTargetCrossingStatus','PrimaryTargetCrossingSNR_dB'});
end

function T = localEmptySummaryReportTable()
T = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), false(0, 1), strings(0, 1), ...
    'VariableNames', {'Direction','MCSIndex','ConfiguredChannelModel','ConfiguredRank','ConfiguredLayers', ...
    'ConfiguredPRBCount','SNRPointCount','TotalTBCount','TotalFailureCount','MaxBLERCIHalfWidth', ...
    'IncompletePointCount','CurvePresent','ConfidenceIntervalsPresent','Status'});
end

function T = localEmptyTargetCrossingTable()
T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    'VariableNames', {'Direction','MCSIndex','TargetBLER','CrossingStatus','CrossingSNR_dB'});
end

function T = localEmptyTaskPlanTable()
T = table(zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'TaskIndex','TaskKey','TaskKind','LinkToken','ExecutionGranularity', ...
    'PointIndex','PointValue','DropIndex','TrialStartIndex','TrialCount','PointSeed','TaskSeed', ...
    'SeedIndex','SeedValue','MCSIndex','ConfiguredRank','ConfiguredLayers','ConfiguredPRBCount', ...
    'SchedulingInvariant'});
end

function names = localNameList(namesIn)
if ischar(namesIn)
    names = string({namesIn});
elseif isstring(namesIn)
    names = reshape(string(namesIn), [], 1);
elseif iscellstr(namesIn)
    names = string(namesIn(:));
else
    names = reshape(string(namesIn), [], 1);
end
end

function out = localOverlayStruct(base, overlay)
out = base;
if ~(builtin("isstruct", overlay) && isscalar(overlay))
    return;
end
fields = string(fieldnames(overlay));
for i = 1:numel(fields)
    out.(char(fields(i))) = overlay.(char(fields(i)));
end
end
