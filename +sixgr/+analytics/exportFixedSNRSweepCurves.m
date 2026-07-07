function out = exportFixedSNRSweepCurves(runFolder, campaign, cfg, opt)
%EXPORTFIXEDSNRSWEEPCURVES Normalize fixed-link SNR sweep evidence and curves.

if nargin < 2 || ~builtin("isstruct", campaign)
    campaign = struct();
end
if nargin < 3 || ~builtin("isstruct", cfg)
    cfg = struct();
end
if nargin < 4 || ~builtin("isstruct", opt)
    opt = struct();
end

rootRunFolder = localResolveRootRunFolder(runFolder);
layout = sixgr.report.resultLayout(rootRunFolder);
writeArtifacts = logical(sixgr.util.structGet(opt, "WriteArtifacts", true));

summary = localAsTable(sixgr.util.structGet(campaign, "Summary", table()));
taskPlan = localAsTable(sixgr.util.structGet(campaign, "TaskPlan", table()));
dlTrials = localNormalizeTrialTable( ...
    localAsTable(sixgr.util.structGet(campaign, "DLTrials", table())), "DL", summary);
ulTrials = localNormalizeTrialTable( ...
    localAsTable(sixgr.util.structGet(campaign, "ULTrials", table())), "UL", summary);
curveSummary = localBuildCurveSummaryTable(summary, dlTrials, ulTrials);
pointCompleteness = localBuildPointCompletenessTable(curveSummary);
curveCrossings = localBuildCurveCrossingTable( ...
    localAsTable(sixgr.util.structGet(campaign, "TargetCrossings", table())), curveSummary);

localValidateSweepArtifacts(summary, dlTrials, ulTrials, curveSummary);

if writeArtifacts
    sixgr.util.ensureFolder(layout.ReportCSVDir);
    sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "lls_fixed_link_campaign.csv"), summary);
    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv"), summary);
    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "lls_reference_snr_sweep.csv"), summary);
    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "fixed_link_campaign_task_plan.csv"), taskPlan);
    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_fixed_link_campaign_trials.csv"), dlTrials);
    localWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_fixed_link_campaign_trials.csv"), ulTrials);

    localWriteTable(fullfile(layout.ReportCSVDir, "fixed_link_campaign_task_plan.csv"), taskPlan);
    localWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_link_campaign_trials.csv"), dlTrials);
    localWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_link_campaign_trials.csv"), ulTrials);
    localWriteTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_curve_summary.csv"), curveSummary);
    localWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_snr_bler_curve.csv"), ...
        localFilterDirection(curveSummary, "DL"));
    localWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_snr_bler_curve.csv"), ...
        localFilterDirection(curveSummary, "UL"));
    localWriteTable(fullfile(layout.ReportCSVDir, "dl_fixed_snr_ber_curve.csv"), ...
        localFilterDirection(curveSummary, "DL"));
    localWriteTable(fullfile(layout.ReportCSVDir, "ul_fixed_snr_ber_curve.csv"), ...
        localFilterDirection(curveSummary, "UL"));
    localWriteTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_point_completeness.csv"), pointCompleteness);
    localWriteTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_curve_crossing.csv"), curveCrossings);
end

out = struct( ...
    "RootRunFolder", string(rootRunFolder), ...
    "WriteArtifacts", logical(writeArtifacts), ...
    "Summary", summary, ...
    "TaskPlan", taskPlan, ...
    "DLTrials", dlTrials, ...
    "ULTrials", ulTrials, ...
    "CurveSummary", curveSummary, ...
    "PointCompleteness", pointCompleteness, ...
    "CurveCrossings", curveCrossings);
end

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
[parent, leaf] = fileparts(rootRunFolder);
leaf = lower(string(leaf));
if any(leaf == ["air_interface", "reports", "control", "packet_flow", "system", "harq"])
    rootRunFolder = parent;
end
end

function T = localAsTable(value)
if istable(value)
    T = value;
else
    T = table();
end
end

function T = localNormalizeTrialTable(T, direction, summary)
if ~istable(T)
    T = table();
end

n = height(T);
direction = upper(string(direction));
T.Direction = repmat(direction, n, 1);

configuredSNR = localNumericColumn(T, ["ConfiguredSNR_dB", "SNR_dB"], NaN(n, 1));
if all(~isfinite(configuredSNR))
    configuredSNR = localInferConfiguredSNR(T, summary, direction);
end
T.ConfiguredSNR_dB = configuredSNR;
T.SNR_dB = localPreferFinite(localNumericColumn(T, ["SNR_dB"], NaN(n, 1)), configuredSNR);

appliedSNR = localPreferFinite( ...
    localNumericColumn(T, ["AppliedAWGNSNR_dB", "AppliedSNR_dB"], NaN(n, 1)), ...
    configuredSNR);
T.AppliedAWGNSNR_dB = appliedSNR;
T.AppliedSNR_dB = appliedSNR;

postEqSINR = localNumericColumn(T, ...
    ["MeasuredPostEqSINR_dB", "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN(n, 1));
T.MeasuredPostEqSINR_dB = postEqSINR;
if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames))
    T.PostEqSINR_dB = postEqSINR;
end
T.SINRMinusSNR_dB = postEqSINR - appliedSNR;

tbSizeBits = localNumericColumn(T, ["TBSizeBits", "TBSize_bits", "CurrentTBSBits", "OriginalTBSBits"], NaN(n, 1));
T.TBSizeBits = tbSizeBits;
if ~ismember("TBSize_bits", string(T.Properties.VariableNames))
    T.TBSize_bits = tbSizeBits;
end

rateMatchedBits = localNumericColumn(T, ["RateMatchedBits", "CurrentRateMatchedBits", "OriginalRateMatchedBits"], NaN(n, 1));
T.RateMatchedBits = rateMatchedBits;

rank = localNumericColumn(T, ["Rank", "ConfiguredRank", "EffectiveRank", "RankIndicator", "FixedLinkConfiguredRank"], NaN(n, 1));
T.Rank = rank;

numLayers = localNumericColumn(T, ["NumLayers", "Layers", "ConfiguredLayers", "EffectiveLayers", "FixedLinkConfiguredLayers"], NaN(n, 1));
T.NumLayers = numLayers;

effectiveCodeRate = NaN(n, 1);
validRate = isfinite(tbSizeBits) & isfinite(rateMatchedBits) & rateMatchedBits > 0;
effectiveCodeRate(validRate) = tbSizeBits(validRate) ./ rateMatchedBits(validRate);
T.EffectiveCodeRate = effectiveCodeRate;

fixedPointIndex = localNumericColumn(T, ["FixedLinkPointIndex", "PointIndex"], NaN(n, 1));
if any(~isfinite(fixedPointIndex))
    fixedPointIndex = localPreferFinite(fixedPointIndex, localInferPointIndex(T, summary, direction));
end
T.FixedLinkPointIndex = fixedPointIndex;

trialIndex = localNumericColumn(T, ["FixedLinkTrialIndex"], NaN(n, 1));
dropIndex = localNumericColumn(T, ["FixedLinkDropIndex"], NaN(n, 1));
if any(~isfinite(trialIndex))
    trialIndex = localSequentialIndexPerPoint(fixedPointIndex);
end
if any(~isfinite(dropIndex))
    dropIndex = trialIndex;
end
T.FixedLinkTrialIndex = trialIndex;
T.FixedLinkDropIndex = dropIndex;

fixedCampaign = localLogicalColumn(T, ["FixedLinkCampaign"], true(n, 1));
fixedReference = localLogicalColumn(T, ["FixedReferenceMode"], true(n, 1));
T.FixedLinkCampaign = fixedCampaign;
T.FixedReferenceMode = fixedReference;

if ~ismember("Status", string(T.Properties.VariableNames))
    status = repmat("OK", n, 1);
    if ismember("CRCPass", string(T.Properties.VariableNames))
        crcPass = localLogicalColumn(T, ["CRCPass"], false(n, 1));
        status(~crcPass) = "CRC_FAIL";
    end
    T.Status = status;
else
    T.Status = string(T.Status);
end

if ~ismember("CRCPass", string(T.Properties.VariableNames))
    T.CRCPass = false(n, 1);
else
    T.CRCPass = localLogicalColumn(T, ["CRCPass"], false(n, 1));
end
if ~ismember("BitErrors", string(T.Properties.VariableNames))
    T.BitErrors = NaN(n, 1);
else
    T.BitErrors = localNumericColumn(T, ["BitErrors"], NaN(n, 1));
end
if ~ismember("BitsCompared", string(T.Properties.VariableNames))
    T.BitsCompared = NaN(n, 1);
else
    T.BitsCompared = localNumericColumn(T, ["BitsCompared"], NaN(n, 1));
end
if ~ismember("MCS", string(T.Properties.VariableNames))
    T.MCS = localNumericColumn(T, ["FixedLinkConfiguredMCS"], NaN(n, 1));
else
    T.MCS = localNumericColumn(T, ["MCS"], NaN(n, 1));
end
if ~ismember("Modulation", string(T.Properties.VariableNames))
    T.Modulation = localTextColumn(T, ["ConfiguredModulation", "EffectiveModulation"], "", n);
else
    T.Modulation = string(T.Modulation);
end
if ~ismember("IsRetransmission", string(T.Properties.VariableNames))
    T.IsRetransmission = false(n, 1);
else
    T.IsRetransmission = localLogicalColumn(T, ["IsRetransmission"], false(n, 1));
end

seedHierarchy = localTextColumn(T, ["FixedLinkSeedHierarchy"], "", n);
if any(strlength(seedHierarchy) == 0)
    seedHierarchy = localPopulateSeedHierarchy(seedHierarchy, direction, fixedPointIndex, dropIndex, trialIndex);
end
T.FixedLinkSeedHierarchy = seedHierarchy;

T = localEnsureRequiredTrialSchema(T);
end

function configuredSNR = localInferConfiguredSNR(T, summary, direction)
n = height(T);
configuredSNR = NaN(n, 1);
if n == 0 || ~(istable(summary) && ~isempty(summary))
    return;
end
pointIndex = localInferPointIndex(T, summary, direction);
summaryPoint = localNumericColumn(summary, ["PointIndex"], NaN(height(summary), 1));
summarySNR = localNumericColumn(summary, ["SNR_dB"], NaN(height(summary), 1));
for i = 1:n
    if ~isfinite(pointIndex(i))
        continue;
    end
    match = find(summaryPoint == pointIndex(i), 1, "first");
    if ~isempty(match)
        configuredSNR(i) = summarySNR(match);
    end
end
end

function pointIndex = localInferPointIndex(T, summary, direction)
n = height(T);
pointIndex = NaN(n, 1);
if n == 0 || ~(istable(summary) && ~isempty(summary))
    return;
end

summaryPoint = localNumericColumn(summary, ["PointIndex"], NaN(height(summary), 1));
summarySNR = localNumericColumn(summary, ["SNR_dB"], NaN(height(summary), 1));
summaryMCS = localNumericColumn(summary, [localDirectionMCSColumn(direction), "MCSIndex"], NaN(height(summary), 1));
trialSNR = localNumericColumn(T, ["ConfiguredSNR_dB", "SNR_dB"], NaN(n, 1));
trialMCS = localNumericColumn(T, ["MCS", "FixedLinkConfiguredMCS"], NaN(n, 1));

for i = 1:n
    if ~isfinite(trialSNR(i))
        continue;
    end
    mask = abs(summarySNR - trialSNR(i)) < 1e-9;
    if isfinite(trialMCS(i))
        mask = mask & (abs(summaryMCS - trialMCS(i)) < 1e-9 | ~isfinite(summaryMCS));
    end
    idx = find(mask, 1, "first");
    if ~isempty(idx)
        pointIndex(i) = summaryPoint(idx);
    end
end
end

function values = localSequentialIndexPerPoint(pointIndex)
n = numel(pointIndex);
values = NaN(n, 1);
if n == 0
    return;
end
finitePoints = pointIndex;
finitePoints(~isfinite(finitePoints)) = -1;
for point = reshape(unique(finitePoints, "stable"), 1, [])
    mask = finitePoints == point;
    values(mask) = (1:nnz(mask)).';
end
end

function values = localPopulateSeedHierarchy(values, direction, pointIndex, dropIndex, trialIndex)
n = numel(values);
for i = 1:n
    if strlength(values(i)) > 0
        continue;
    end
    values(i) = lower(direction) + "_point_" + localToken(pointIndex(i)) + ...
        "_drop_" + localToken(dropIndex(i)) + "_trial_" + localToken(trialIndex(i));
end
end

function token = localToken(value)
if ~isfinite(double(value))
    token = "na";
else
    token = string(round(double(value)));
end
end

function T = localEnsureRequiredTrialSchema(T)
n = height(T);
required = struct( ...
    "Direction", strings(n, 1), ...
    "SNR_dB", NaN(n, 1), ...
    "ConfiguredSNR_dB", NaN(n, 1), ...
    "AppliedSNR_dB", NaN(n, 1), ...
    "AppliedAWGNSNR_dB", NaN(n, 1), ...
    "MeasuredPostEqSINR_dB", NaN(n, 1), ...
    "SINRMinusSNR_dB", NaN(n, 1), ...
    "Status", strings(n, 1), ...
    "CRCPass", false(n, 1), ...
    "BitErrors", NaN(n, 1), ...
    "BitsCompared", NaN(n, 1), ...
    "MCS", NaN(n, 1), ...
    "Modulation", strings(n, 1), ...
    "Rank", NaN(n, 1), ...
    "NumLayers", NaN(n, 1), ...
    "TBSizeBits", NaN(n, 1), ...
    "RateMatchedBits", NaN(n, 1), ...
    "EffectiveCodeRate", NaN(n, 1), ...
    "FixedLinkCampaign", false(n, 1), ...
    "FixedReferenceMode", false(n, 1), ...
    "FixedLinkPointIndex", NaN(n, 1), ...
    "FixedLinkDropIndex", NaN(n, 1), ...
    "FixedLinkTrialIndex", NaN(n, 1), ...
    "FixedLinkSeedHierarchy", strings(n, 1));
fields = string(fieldnames(required));
for i = 1:numel(fields)
    if ~ismember(fields(i), string(T.Properties.VariableNames))
        T.(char(fields(i))) = required.(char(fields(i)));
    end
end
T.Direction = string(T.Direction);
T.Status = string(T.Status);
T.Modulation = string(T.Modulation);
T.FixedLinkSeedHierarchy = string(T.FixedLinkSeedHierarchy);
end

function curveSummary = localBuildCurveSummaryTable(summary, dlTrials, ulTrials)
rows = repmat(localEmptyCurveRow(), 0, 1);
rows = localAppendDirectionRows(rows, summary, dlTrials, "DL");
rows = localAppendDirectionRows(rows, summary, ulTrials, "UL");
if isempty(rows)
    curveSummary = localEmptyCurveSummaryTable();
else
    curveSummary = struct2table(rows, "AsArray", true);
end
end

function rows = localAppendDirectionRows(rows, summary, trials, direction)
if ~(istable(summary) && ~isempty(summary) && localDirectionEnabled(summary, direction))
    return;
end

for i = 1:height(summary)
    row = localEmptyCurveRow();
    row.Direction = string(direction);
    row.ChannelModel = localTextScalar(summary(i, :), ["ConfiguredChannelModel"], "");
    row.SweepKind = localTextScalar(summary(i, :), ["SweepKind"], "");
    row.NoiseVariable = "AppliedAWGNSNR_dB";
    row.PointIndex = localScalarNumeric(summary(i, :), ["PointIndex"], NaN);
    row.PointSeed = localScalarNumeric(summary(i, :), ["PointSeed"], NaN);
    row.SNR_dB = localScalarNumeric(summary(i, :), ["SNR_dB"], NaN);
    row.ConfiguredSNR_dB = row.SNR_dB;
    row.MinTrialsRequired = localScalarNumeric(summary(i, :), ["SequentialMinTrials"], NaN);
    row.MaxTrialsAllowed = localScalarNumeric(summary(i, :), ["SequentialMaxTrials"], NaN);
    row.ConfidenceLevel = localScalarNumeric(summary(i, :), ["ConfidenceLevel"], NaN);
    row.MCS = localScalarNumeric(summary(i, :), [localDirectionMCSColumn(direction), "MCSIndex"], NaN);
    row.Rank = localScalarNumeric(summary(i, :), ["ConfiguredRank"], NaN);
    row.Layers = localScalarNumeric(summary(i, :), ["ConfiguredLayers"], NaN);

    sub = localTrialsForPoint(trials, summary(i, :), direction);
    row.Modulation = localFirstText(sub, ["Modulation", "ConfiguredModulation", "EffectiveModulation"], "");
    row.Rank = localFirstFinite(localNumericColumn(sub, ["Rank", "ConfiguredRank", "EffectiveRank"], NaN(height(sub), 1)), row.Rank);
    row.Layers = localFirstFinite(localNumericColumn(sub, ["NumLayers", "ConfiguredLayers", "EffectiveLayers"], NaN(height(sub), 1)), row.Layers);
    row.TrialCount = double(height(sub));
    crcPass = localLogicalColumn(sub, ["CRCPass"], false(height(sub), 1));
    row.TBPassCount = double(sum(crcPass));
    row.TBFailCount = double(row.TrialCount - row.TBPassCount);
    row.BitErrors = double(sum(localNumericColumn(sub, ["BitErrors"], zeros(height(sub), 1)), "omitnan"));
    row.BitsCompared = double(sum(localNumericColumn(sub, ["BitsCompared"], zeros(height(sub), 1)), "omitnan"));

    row.AppliedSNR_dB = localSummaryOrTrialValue(sub, ["AppliedSNR_dB", "AppliedAWGNSNR_dB"], row.ConfiguredSNR_dB);
    measuredSINR = localNumericColumn(sub, ["MeasuredPostEqSINR_dB", "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"], NaN(height(sub), 1));
    finiteSINR = measuredSINR(isfinite(measuredSINR));
    if ~isempty(finiteSINR)
        row.MeanMeasuredSINR_dB = double(mean(finiteSINR, "omitnan"));
        row.MedianMeasuredSINR_dB = double(median(finiteSINR, "omitnan"));
    else
        row.MeanMeasuredSINR_dB = localScalarNumeric(summary(i, :), [direction + "_MeasuredSINR_dB"], NaN);
        row.MedianMeasuredSINR_dB = row.MeanMeasuredSINR_dB;
    end
    row.SINRMinusSNRMean_dB = row.MeanMeasuredSINR_dB - row.AppliedSNR_dB;

    prefix = upper(string(direction));
    row.BLER = localScalarNumeric(summary(i, :), [prefix + "_BLER"], NaN);
    row.BLER_CI_Low = localScalarNumeric(summary(i, :), [prefix + "_BLER_CI_Low"], NaN);
    row.BLER_CI_High = localScalarNumeric(summary(i, :), [prefix + "_BLER_CI_High"], NaN);
    row.BLER_CI_Width = localCIWidth(row.BLER_CI_Low, row.BLER_CI_High, ...
        localScalarNumeric(summary(i, :), [prefix + "_BLER_CI_Width"], NaN));
    row.BER = localScalarNumeric(summary(i, :), [prefix + "_BER"], NaN);
    if ~isfinite(row.BER) && row.BitsCompared > 0
        row.BER = row.BitErrors / row.BitsCompared;
    end
    row.BER_CI_Low = localScalarNumeric(summary(i, :), [prefix + "_BER_CI_Low"], NaN);
    row.BER_CI_High = localScalarNumeric(summary(i, :), [prefix + "_BER_CI_High"], NaN);
    row.BER_CI_Width = localCIWidth(row.BER_CI_Low, row.BER_CI_High, ...
        localScalarNumeric(summary(i, :), [prefix + "_BER_CI_Width"], NaN));
    row.Throughput_Mbps = localScalarNumeric(summary(i, :), [prefix + "_Throughput_Mbps"], NaN);
    row.Goodput_Mbps = localScalarNumeric(summary(i, :), [prefix + "_Goodput_Mbps"], NaN);
    row.TargetBLER = localScalarNumeric(summary(i, :), [prefix + "_TargetBLER"], NaN);
    row.TargetCrossingSNR_dB = localScalarNumeric(summary(i, :), [prefix + "_TargetCrossingSNR_dB"], NaN);
    row.TargetCrossingStatus = localTextScalar(summary(i, :), [prefix + "_TargetCrossingStatus"], "");
    row.StopReason = localTextScalar(summary(i, :), [prefix + "_StopReason"], "");
    row.Incomplete = localScalarLogical(summary(i, :), [prefix + "_Incomplete"], false);

    row.Status = localCurveRowStatus(row);
    row.FailureCode = localCurveFailureCode(row);
    rows(end + 1, 1) = row; %#ok<AGROW>
end
end

function sub = localTrialsForPoint(trials, summaryRow, direction)
if ~istable(trials) || isempty(trials)
    sub = trials;
    return;
end
pointIndex = localScalarNumeric(summaryRow, ["PointIndex"], NaN);
summarySNR = localScalarNumeric(summaryRow, ["SNR_dB"], NaN);
summaryMCS = localScalarNumeric(summaryRow, [localDirectionMCSColumn(direction), "MCSIndex"], NaN);

mask = false(height(trials), 1);
trialPointIndex = localNumericColumn(trials, ["FixedLinkPointIndex", "PointIndex"], NaN(height(trials), 1));
if isfinite(pointIndex) && any(isfinite(trialPointIndex))
    mask = abs(trialPointIndex - pointIndex) < 1e-9;
else
    trialSNR = localNumericColumn(trials, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(trials), 1));
    mask = abs(trialSNR - summarySNR) < 1e-9;
    if isfinite(summaryMCS)
        trialMCS = localNumericColumn(trials, ["MCS", "FixedLinkConfiguredMCS"], NaN(height(trials), 1));
        mask = mask & (abs(trialMCS - summaryMCS) < 1e-9 | ~isfinite(trialMCS));
    end
end
sub = trials(mask, :);
end

function completeness = localBuildPointCompletenessTable(curveSummary)
if ~(istable(curveSummary) && ~isempty(curveSummary))
    completeness = localEmptyPointCompletenessTable();
    return;
end

status = strings(height(curveSummary), 1);
failure = strings(height(curveSummary), 1);
zeroTrials = double(curveSummary.TrialCount) == 0;
for i = 1:height(curveSummary)
    if zeroTrials(i)
        status(i) = "missing";
        failure(i) = "zero_trials";
    elseif logical(curveSummary.Incomplete(i))
        status(i) = "incomplete";
        failure(i) = "stopping_rule_incomplete";
    else
        status(i) = "complete";
        failure(i) = "";
    end
end

completeness = table( ...
    string(curveSummary.Direction), ...
    double(curveSummary.PointIndex), ...
    double(curveSummary.PointSeed), ...
    double(curveSummary.SNR_dB), ...
    double(curveSummary.MCS), ...
    double(curveSummary.TrialCount), ...
    double(curveSummary.MinTrialsRequired), ...
    double(curveSummary.MaxTrialsAllowed), ...
    logical(curveSummary.Incomplete), ...
    zeroTrials, ...
    string(curveSummary.StopReason), ...
    status, ...
    failure, ...
    'VariableNames', {'Direction','PointIndex','PointSeed','SNR_dB','MCS', ...
    'TrialCount','MinTrialsRequired','MaxTrialsAllowed','Incomplete','ZeroTrials', ...
    'StopReason','Status','FailureCode'});
end

function crossings = localBuildCurveCrossingTable(targetCrossings, curveSummary)
if ~(istable(targetCrossings) && ~isempty(targetCrossings))
    crossings = localEmptyCurveCrossingTable();
    return;
end

n = height(targetCrossings);
channelModel = strings(n, 1);
status = strings(n, 1);
failure = strings(n, 1);
for i = 1:n
    dirToken = upper(string(targetCrossings.Direction(i)));
    mcsValue = double(localTableValue(targetCrossings, i, "MCSIndex", NaN));
    if istable(curveSummary) && ~isempty(curveSummary)
        match = string(curveSummary.Direction) == dirToken & ...
            abs(double(curveSummary.MCS) - mcsValue) < 1e-9;
    else
        match = false(0, 1);
    end
    if any(match)
        channelModel(i) = localFirstText(curveSummary(match, :), ["ChannelModel"], "");
    else
        channelModel(i) = "";
    end

    crossingStatus = string(localTableValue(targetCrossings, i, "CrossingStatus", ""));
    if strlength(crossingStatus) == 0
        status(i) = "missing";
        failure(i) = "crossing_status_missing";
    else
        status(i) = "reported";
        failure(i) = "";
    end
end

crossings = table( ...
    string(targetCrossings.Direction), ...
    channelModel, ...
    double(localColumnOrDefault(targetCrossings, "MCSIndex", NaN(n, 1))), ...
    double(localColumnOrDefault(targetCrossings, "TargetBLER", NaN(n, 1))), ...
    double(localColumnOrDefault(targetCrossings, "CrossingSNR_dB", NaN(n, 1))), ...
    string(localColumnOrDefault(targetCrossings, "CrossingStatus", strings(n, 1))), ...
    status, ...
    failure, ...
    'VariableNames', {'Direction','ChannelModel','MCS','TargetBLER', ...
    'TargetCrossingSNR_dB','TargetCrossingStatus','Status','FailureCode'});
end

function localValidateSweepArtifacts(summary, dlTrials, ulTrials, curveSummary)
if ~(istable(summary) && ~isempty(summary))
    return;
end

localValidateDirectionCurveSummary(curveSummary, summary, "DL");
localValidateDirectionCurveSummary(curveSummary, summary, "UL");
localValidateTrialCodeRates(dlTrials, "DL");
localValidateTrialCodeRates(ulTrials, "UL");
end

function localValidateDirectionCurveSummary(curveSummary, summary, direction)
if ~localDirectionEnabled(summary, direction)
    return;
end

dirRows = localFilterDirection(curveSummary, direction);
expectedPointCount = height(summary);
if height(dirRows) ~= expectedPointCount
    error("sixgr:analytics:exportFixedSNRSweepCurves:PointCountMismatch", ...
        "Fixed SNR sweep direction %s exported %d rows for %d configured SNR points.", ...
        char(direction), height(dirRows), expectedPointCount);
end
if any(double(dirRows.TrialCount) <= 0)
    error("sixgr:analytics:exportFixedSNRSweepCurves:ZeroTrials", ...
        "Fixed SNR sweep direction %s contains at least one configured SNR point with zero trials.", ...
        char(direction));
end

minTrials = double(dirRows.MinTrialsRequired);
incomplete = logical(dirRows.Incomplete);
trialCount = double(dirRows.TrialCount);
if any(trialCount < minTrials & ~incomplete)
    error("sixgr:analytics:exportFixedSNRSweepCurves:TrialCountUnderflow", ...
        "Fixed SNR sweep direction %s reported TrialCount < min_trials on a supposedly complete point.", ...
        char(direction));
end

localValidateProbabilityMetric(double(dirRows.BLER), "BLER", direction);
localValidateProbabilityMetric(double(dirRows.BER), "BER", direction);
localValidateCI(double(dirRows.BLER), double(dirRows.BLER_CI_Low), double(dirRows.BLER_CI_High), "BLER", direction);
localValidateCI(double(dirRows.BER), double(dirRows.BER_CI_Low), double(dirRows.BER_CI_High), "BER", direction);
end

function localValidateProbabilityMetric(values, metricName, direction)
bad = ~isfinite(values) | values < 0 | values > 1;
if any(bad)
    error("sixgr:analytics:exportFixedSNRSweepCurves:InvalidProbability", ...
        "Fixed SNR sweep direction %s has invalid %s values outside [0,1].", ...
        char(direction), char(metricName));
end
end

function localValidateCI(center, low, high, metricName, direction)
mask = isfinite(center) | isfinite(low) | isfinite(high);
if ~any(mask)
    error("sixgr:analytics:exportFixedSNRSweepCurves:MissingCI", ...
        "Fixed SNR sweep direction %s has no finite %s confidence intervals.", ...
        char(direction), char(metricName));
end
tol = 1e-9;
bad = mask & (~isfinite(low) | ~isfinite(high) | low < -tol | high > 1 + tol | low > high + tol);
centerMask = mask & isfinite(center);
bad = bad | (centerMask & (low > center + tol | high < center - tol));
if any(bad)
    error("sixgr:analytics:exportFixedSNRSweepCurves:InvalidCI", ...
        "Fixed SNR sweep direction %s has invalid %s confidence intervals.", ...
        char(direction), char(metricName));
end
end

function localValidateTrialCodeRates(T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
eff = localNumericColumn(T, ["EffectiveCodeRate"], NaN(height(T), 1));
isRetx = localLogicalColumn(T, ["IsRetransmission"], false(height(T), 1));
bad = ~isRetx & isfinite(eff) & eff > 1.0 + 1e-9;
if any(bad)
    error("sixgr:analytics:exportFixedSNRSweepCurves:EffectiveCodeRateExceeded", ...
        "Fixed SNR sweep direction %s produced EffectiveCodeRate > 1.0 for a new transport block.", ...
        char(direction));
end
end

function tf = localDirectionEnabled(summary, direction)
tf = false;
if ~(istable(summary) && ~isempty(summary))
    return;
end
modes = lower(string(localColumnOrDefault(summary, "DirectionMode", strings(height(summary), 1))));
if any(strlength(modes) > 0)
    tf = any(modes == "both" | modes == lower(string(direction)));
    return;
end
trialCol = direction + "_TrialCount";
tf = ismember(char(trialCol), summary.Properties.VariableNames);
end

function T = localFilterDirection(T, direction)
if ~(istable(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
T = T(string(T.Direction) == upper(string(direction)), :);
end

function row = localEmptyCurveRow()
row = struct( ...
    "Direction", "", ...
    "ChannelModel", "", ...
    "SweepKind", "", ...
    "NoiseVariable", "", ...
    "PointIndex", NaN, ...
    "PointSeed", NaN, ...
    "SNR_dB", NaN, ...
    "ConfiguredSNR_dB", NaN, ...
    "AppliedSNR_dB", NaN, ...
    "MeanMeasuredSINR_dB", NaN, ...
    "MedianMeasuredSINR_dB", NaN, ...
    "SINRMinusSNRMean_dB", NaN, ...
    "MCS", NaN, ...
    "Modulation", "", ...
    "Rank", NaN, ...
    "Layers", NaN, ...
    "TrialCount", NaN, ...
    "TBPassCount", NaN, ...
    "TBFailCount", NaN, ...
    "BLER", NaN, ...
    "BLER_CI_Low", NaN, ...
    "BLER_CI_High", NaN, ...
    "BLER_CI_Width", NaN, ...
    "BitErrors", NaN, ...
    "BitsCompared", NaN, ...
    "BER", NaN, ...
    "BER_CI_Low", NaN, ...
    "BER_CI_High", NaN, ...
    "BER_CI_Width", NaN, ...
    "Throughput_Mbps", NaN, ...
    "Goodput_Mbps", NaN, ...
    "TargetBLER", NaN, ...
    "TargetCrossingSNR_dB", NaN, ...
    "TargetCrossingStatus", "", ...
    "MinTrialsRequired", NaN, ...
    "MaxTrialsAllowed", NaN, ...
    "ConfidenceLevel", NaN, ...
    "StopReason", "", ...
    "Incomplete", false, ...
    "Status", "", ...
    "FailureCode", "");
end

function T = localEmptyCurveSummaryTable()
T = struct2table(repmat(localEmptyCurveRow(), 0, 1), "AsArray", true);
end

function T = localEmptyPointCompletenessTable()
T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), false(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Direction','PointIndex','PointSeed','SNR_dB','MCS','TrialCount', ...
    'MinTrialsRequired','MaxTrialsAllowed','Incomplete','ZeroTrials','StopReason','Status','FailureCode'});
end

function T = localEmptyCurveCrossingTable()
T = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Direction','ChannelModel','MCS','TargetBLER', ...
    'TargetCrossingSNR_dB','TargetCrossingStatus','Status','FailureCode'});
end

function status = localCurveRowStatus(row)
if ~(isfinite(row.TrialCount) && row.TrialCount > 0)
    status = "missing";
elseif logical(row.Incomplete)
    status = "incomplete";
else
    status = "complete";
end
end

function failureCode = localCurveFailureCode(row)
if ~(isfinite(row.TrialCount) && row.TrialCount > 0)
    failureCode = "zero_trials";
elseif logical(row.Incomplete)
    failureCode = "stopping_rule_incomplete";
else
    failureCode = "";
end
end

function value = localCIWidth(low, high, fallback)
if isfinite(low) && isfinite(high)
    value = high - low;
else
    value = fallback;
end
end

function value = localSummaryOrTrialValue(T, candidates, fallback)
value = localFirstFinite(localNumericColumn(T, candidates, NaN(height(T), 1)), NaN);
if ~isfinite(value)
    value = fallback;
end
end

function value = localScalarNumeric(T, candidates, fallback)
values = localNumericColumn(T, candidates, fallback);
if isempty(values)
    value = fallback;
else
    value = double(values(1));
end
end

function value = localScalarLogical(T, candidates, fallback)
values = localLogicalColumn(T, candidates, fallback);
if isempty(values)
    value = logical(fallback);
else
    value = logical(values(1));
end
end

function value = localTextScalar(T, candidates, fallback)
values = localTextColumn(T, candidates, fallback, height(T));
if isempty(values)
    value = string(fallback);
else
    value = string(values(1));
end
end

function value = localFirstText(T, candidates, fallback)
values = localTextColumn(T, candidates, fallback, height(T));
values = values(strlength(values) > 0);
if isempty(values)
    value = string(fallback);
else
    value = string(values(1));
end
end

function values = localNumericColumn(T, candidates, fallback)
if istable(T)
    n = height(T);
else
    n = numel(fallback);
end
values = localExpandFallback(fallback, n);
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(string(candidates), 1, [])
    if ismember(char(name), T.Properties.VariableNames)
        raw = T.(char(name));
        if isnumeric(raw) || islogical(raw)
            values = double(raw);
        else
            values = str2double(string(raw));
        end
        values = reshape(values, n, 1);
        return;
    end
end
end

function values = localLogicalColumn(T, candidates, fallback)
if istable(T)
    n = height(T);
else
    n = numel(fallback);
end
values = logical(localExpandFallback(fallback, n));
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(string(candidates), 1, [])
    if ismember(char(name), T.Properties.VariableNames)
        raw = T.(char(name));
        if islogical(raw)
            values = logical(raw);
        elseif isnumeric(raw)
            values = double(raw) ~= 0;
        else
            token = lower(strtrim(string(raw)));
            values = token == "1" | token == "true" | token == "yes" | token == "pass";
        end
        values = reshape(values, n, 1);
        return;
    end
end
end

function values = localTextColumn(T, candidates, fallback, n)
if nargin < 4
    n = istable(T) * height(T);
end
values = repmat(string(fallback), n, 1);
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(string(candidates), 1, [])
    if ismember(char(name), T.Properties.VariableNames)
        values = string(T.(char(name)));
        values = reshape(values, n, 1);
        return;
    end
end
end

function values = localExpandFallback(fallback, n)
if isscalar(fallback)
    values = repmat(double(fallback), n, 1);
else
    values = double(fallback);
    values = reshape(values, [], 1);
    if numel(values) ~= n
        values = repmat(values(1), n, 1);
    end
end
end

function values = localPreferFinite(primary, secondary)
values = primary;
mask = ~isfinite(values) & isfinite(secondary);
values(mask) = secondary(mask);
end

function value = localFirstFinite(values, fallback)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = fallback;
else
    value = values(idx);
end
end

function name = localDirectionMCSColumn(direction)
if upper(string(direction)) == "UL"
    name = "ULMCSIndex";
else
    name = "DLMCSIndex";
end
end

function value = localColumnOrDefault(T, varName, fallback)
if istable(T) && ismember(char(string(varName)), T.Properties.VariableNames)
    value = T.(char(string(varName)));
else
    value = fallback;
end
end

function value = localTableValue(T, rowIdx, varName, fallback)
if istable(T) && ismember(char(string(varName)), T.Properties.VariableNames)
    value = T.(char(string(varName)))(rowIdx);
else
    value = fallback;
end
end

function localWriteTable(pathValue, T)
if ~istable(T)
    T = table();
end
sixgr.analytics.writeAnalysisTable(pathValue, T);
end
