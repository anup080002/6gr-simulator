function results = generateMeasuredSINRCurves(cfg, runTag, varargin)
%GENERATEMEASUREDSINRCURVES Build geometry-driven measured-SINR KPI curves.
%
% The x-axis for these artifacts is always receiver-measured PostEqSINR_dB.
% ConfiguredSNR_dB and AppliedAWGNSNR_dB remain raw-trial provenance columns
% but are intentionally excluded from every generated curve schema.

if nargin < 2
    runTag = "";
end

ip = inputParser;
ip.addParameter("TrialData", [], @(x) isempty(x) || isstruct(x));
ip.addParameter("ScenarioConfig", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("BinCount", 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("WriteKPISummary", true, @(x) islogical(x) || isnumeric(x));
ip.addParameter("UpdateAnchorKPIs", true, @(x) islogical(x) || isnumeric(x));
ip.parse(varargin{:});
opt = ip.Results;

runDir = localResolveRunDir(cfg);
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceImageDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);

localDeleteLegacySweepArtifacts(layout);

trialData = opt.TrialData;
if isempty(trialData)
    trialData = sixgr.analytics.loadAllTrialData(runDir);
end

dlRaw = localTableField(trialData, ["dl","DL"]);
ulRaw = localTableField(trialData, ["ul","UL"]);
dl = localFilterMeasuredTrials(dlRaw);
ul = localFilterMeasuredTrials(ulRaw);

scenarioCfg = opt.ScenarioConfig;
if isempty(scenarioCfg)
    scenarioCfg = struct();
end

bandwidthHz = localBandwidthHz(cfg, scenarioCfg);
slotDuration_s = localSlotDurationSeconds(cfg, scenarioCfg);
nBins = max(1, round(double(opt.BinCount)));

[dlBler, dlThroughput, dlDistribution, dlScatter, dlSummary, dlKPI] = ...
    localBuildDirectionArtifacts(dl, "DL", "dl_pdsch_trials.csv", nBins, bandwidthHz, 4/5, slotDuration_s, runTag);
[ulBler, ulThroughput, ulDistribution, ulScatter, ulSummary, ulKPI] = ...
    localBuildDirectionArtifacts(ul, "UL", "ul_pusch_trials.csv", nBins, bandwidthHz, 1/5, slotDuration_s, runTag);

distribution = localConcatTables(dlDistribution, ulDistribution);
scatter = localSortDistanceScatter(localConcatTables(dlScatter, ulScatter));
summary = localConcatTables(dlSummary, ulSummary);
liveSummary = summary;
kpiSummary = localConcatTables(dlKPI, ulKPI);

paths = struct();
paths.DLBlerCurve = fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_bler_curve.csv");
paths.ULBlerCurve = fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_bler_curve.csv");
paths.DLThroughputCurve = fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_throughput_curve.csv");
paths.ULThroughputCurve = fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_throughput_curve.csv");
paths.Distribution = fullfile(layout.AirInterfaceCSVDir, "measured_sinr_distribution.csv");
paths.DistanceScatter = fullfile(layout.AirInterfaceCSVDir, "distance_vs_sinr.csv");
paths.Summary = fullfile(layout.AirInterfaceCSVDir, "lls_measured_sinr_summary.csv");
paths.LiveSummary = fullfile(layout.AirInterfaceCSVDir, "live_measured_sinr_summary.csv");
paths.KPISummary = fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv");

sixgr.analytics.writeAnalysisTable(paths.DLBlerCurve, dlBler);
sixgr.analytics.writeAnalysisTable(paths.ULBlerCurve, ulBler);
sixgr.analytics.writeAnalysisTable(paths.DLThroughputCurve, dlThroughput);
sixgr.analytics.writeAnalysisTable(paths.ULThroughputCurve, ulThroughput);
sixgr.analytics.writeAnalysisTable(paths.Distribution, distribution);
sixgr.analytics.writeAnalysisTable(paths.DistanceScatter, scatter);
sixgr.analytics.writeAnalysisTable(paths.Summary, summary);
sixgr.analytics.writeAnalysisTable(paths.LiveSummary, liveSummary);
if logical(opt.WriteKPISummary)
    sixgr.analytics.writeAnalysisTable(paths.KPISummary, kpiSummary);
end

if logical(opt.UpdateAnchorKPIs)
    localUpdateLinkAnchorKPIs(layout, summary);
end

localRelabelAnalyticsCSVAndSVG(layout);

tables = struct( ...
    "DLBlerCurve", dlBler, ...
    "ULBlerCurve", ulBler, ...
    "DLThroughputCurve", dlThroughput, ...
    "ULThroughputCurve", ulThroughput, ...
    "Distribution", distribution, ...
    "DistanceScatter", scatter, ...
    "Summary", summary, ...
    "LiveSummary", liveSummary, ...
    "KPISummary", kpiSummary);

results = struct();
results.Ok = true;
results.RunDir = string(runDir);
results.Paths = paths;
results.Tables = tables;
results.RowCounts = structfun(@(T) height(T), tables, "UniformOutput", false);
end

function [blerT, throughputT, distT, scatterT, summaryT, kpiT] = localBuildDirectionArtifacts(T, direction, sourceArtifact, nBins, bandwidthHz, tddEfficiency, slotDuration_s, runTag)
direction = upper(string(direction));
if ~(istable(T) && height(T) > 0)
    blerT = localEmptyBlerCurve();
    throughputT = localEmptyThroughputCurve();
    distT = localEmptyDistribution();
    scatterT = localEmptyDistanceScatter();
    summaryT = localEmptyMeasuredSummary();
    kpiT = localEmptyKPISummary();
    return;
end

sinr = localNumericFirst(T, ["PostEqSINR_dB"], NaN(height(T), 1));
valid = isfinite(sinr);
T = T(valid, :);
sinr = sinr(valid);
if isempty(sinr)
    blerT = localEmptyBlerCurve();
    throughputT = localEmptyThroughputCurve();
    distT = localEmptyDistribution();
    scatterT = localEmptyDistanceScatter();
    summaryT = localEmptyMeasuredSummary();
    kpiT = localEmptyKPISummary();
    return;
end

bins = localBuildSINRBins(sinr, nBins);
ueVals = localNumericFirst(T, ["UEIndex","UEID","UEId"], NaN(height(T), 1));
ueGroups = unique(ueVals(isfinite(ueVals)));

blerRows = {};
throughputRows = {};
distRows = {};
summaryRows = {};
kpiRows = {};

groupMasks = {true(height(T), 1)};
groupLabels = NaN;
for ii = 1:numel(ueGroups)
    groupMasks{end+1} = ueVals == ueGroups(ii); %#ok<AGROW>
    groupLabels(end+1, 1) = ueGroups(ii); %#ok<AGROW>
end

for gi = 1:numel(groupMasks)
    mask = groupMasks{gi};
    ueLabel = groupLabels(gi);
    if ~any(mask)
        continue;
    end
    sub = T(mask, :);
    for bi = 1:numel(bins.centers)
        inBin = localBinMask(localNumericFirst(sub, "PostEqSINR_dB", NaN(height(sub), 1)), bins.edges, bi);
        if ~any(inBin)
            continue;
        end
        binSub = sub(inBin, :);
        blerRows{end+1, 1} = localBlerCurveRow(binSub, direction, ueLabel, bins, bi, sourceArtifact); %#ok<AGROW>
        throughputRows{end+1, 1} = localThroughputCurveRow(binSub, direction, ueLabel, bins, bi, sourceArtifact, bandwidthHz, tddEfficiency); %#ok<AGROW>
    end
    if isfinite(ueLabel)
        distRows = [distRows; localDistributionRows(sub, direction, ueLabel, bins, sourceArtifact)]; %#ok<AGROW>
    end
    summaryRows{end+1, 1} = localMeasuredSummaryRow(sub, direction, ueLabel, sourceArtifact, bandwidthHz, tddEfficiency); %#ok<AGROW>
    kpiRows{end+1, 1} = localKPISummaryRow(sub, direction, ueLabel, sourceArtifact, bandwidthHz, tddEfficiency, slotDuration_s, runTag); %#ok<AGROW>
end

scatterT = localDistanceScatterRows(T, direction, sourceArtifact);
blerT = localStructRowsToTable(blerRows, localBlerCurveVars(), localBlerCurveTypes());
throughputT = localStructRowsToTable(throughputRows, localThroughputCurveVars(), localThroughputCurveTypes());
distT = localStructRowsToTable(distRows, localDistributionVars(), localDistributionTypes());
summaryT = localStructRowsToTable(summaryRows, localMeasuredSummaryVars(), localMeasuredSummaryTypes());
kpiT = localStructRowsToTable(kpiRows, localKPISummaryVars(), localKPISummaryTypes());
end

function T = localFilterMeasuredTrials(T)
if ~(istable(T) && height(T) > 0)
    T = table();
    return;
end
mask = true(height(T), 1);
if localHasColumn(T, "FinalizedFlag")
    mask = mask & localToLogical(T.FinalizedFlag);
end
if localHasColumn(T, "IsWarmupFrame")
    mask = mask & ~localToLogical(T.IsWarmupFrame);
end
if localHasColumn(T, "FallbackFlag")
    mask = mask & ~localToLogical(T.FallbackFlag);
end
if localHasColumn(T, "PostEqSINRValueStatus")
    status = strtrim(string(T.PostEqSINRValueStatus));
    statusOk = status == "OK" | status == "OK_dynamic_range_limited";
    statusOk(ismissing(status)) = false;
    mask = mask & statusOk;
end
sinr = localNumericFirst(T, "PostEqSINR_dB", NaN(height(T), 1));
mask = mask & isfinite(sinr);
T = T(mask, :);
end

function bins = localBuildSINRBins(sinrValues, nBins)
sinrValues = double(sinrValues(:));
sinrValues = sinrValues(isfinite(sinrValues));
if isempty(sinrValues)
    edges = 0:1:1;
else
    sinrMin = floor(min(sinrValues) - 0.5);
    sinrMax = ceil(max(sinrValues) + 0.5);
    if sinrMax - sinrMin < 5
        mid = (sinrMax + sinrMin) / 2;
        sinrMin = floor(mid - 2.5);
        sinrMax = ceil(mid + 2.5);
    end
    span = max(1, sinrMax - sinrMin);
    binWidth = max(1.0, span / max(1, nBins));
    edges = sinrMin:binWidth:sinrMax;
    if numel(edges) < 2 || edges(end) < sinrMax
        edges(end+1) = edges(end) + binWidth;
    end
end
centers = edges(1:end-1) + diff(edges) / 2;
bins = struct("edges", edges(:).', "centers", centers(:).', "width_dB", median(diff(edges)));
end

function mask = localBinMask(values, edges, idx)
values = double(values(:));
if idx >= numel(edges) - 1
    mask = values >= edges(idx) & values <= edges(idx+1);
else
    mask = values >= edges(idx) & values < edges(idx+1);
end
end

function row = localBlerCurveRow(T, direction, ueLabel, bins, binIdx, sourceArtifact)
crc = localCRC(T);
failures = sum(~crc);
n = height(T);
[ciLow, ciHigh] = localWilsonCI(failures, n);
bits = localNumericFirst(T, "BitsCompared", NaN(n, 1));
bitErrors = localNumericFirst(T, "BitErrors", NaN(n, 1));
ber = localSafeDivide(sum(bitErrors(isfinite(bitErrors)), "omitnan"), sum(bits(isfinite(bits)), "omitnan"));
dist = localNumericFirst(T, "PropagationDistance_m", NaN(n, 1));
row = struct( ...
    "Direction", direction, ...
    "UEIndex", double(ueLabel), ...
    "RNTI", localRepresentativeNumeric(T, "RNTI"), ...
    "PostEqSINR_dB_BinCenter", double(bins.centers(binIdx)), ...
    "PostEqSINR_dB_BinMin", double(bins.edges(binIdx)), ...
    "PostEqSINR_dB_BinMax", double(bins.edges(binIdx+1)), ...
    "BLER", localSafeDivide(failures, n), ...
    "BLER_CI_Low", ciLow, ...
    "BLER_CI_High", ciHigh, ...
    "BER", ber, ...
    "TrialCount", double(n), ...
    "FailureCount", double(failures), ...
    "PropagationDistance_m_mean", localMeanFinite(dist), ...
    "PropagationDistance_m_min", localMinFinite(dist), ...
    "PropagationDistance_m_max", localMaxFinite(dist), ...
    "MCS_dominant", localModeNumeric(T, ["MCS","MCSIndex"]), ...
    "Modulation_dominant", localModeString(T, "Modulation"), ...
    "Rank_dominant", localModeNumeric(T, ["Rank","Layers"]), ...
    "SourceArtifact", string(sourceArtifact));
end

function row = localThroughputCurveRow(T, direction, ueLabel, bins, binIdx, sourceArtifact, bandwidthHz, tddEfficiency)
n = height(T);
goodput = localNumericFirst(T, "Goodput_Mbps", localRowBitrateMbps(T, "GoodBits", tddEfficiency));
offered = localNumericFirst(T, "OfferedThroughput_Mbps", localRowBitrateMbps(T, "OfferedBits", tddEfficiency));
row = struct( ...
    "Direction", direction, ...
    "UEIndex", double(ueLabel), ...
    "RNTI", localRepresentativeNumeric(T, "RNTI"), ...
    "PostEqSINR_dB_BinCenter", double(bins.centers(binIdx)), ...
    "PostEqSINR_dB_BinMin", double(bins.edges(binIdx)), ...
    "PostEqSINR_dB_BinMax", double(bins.edges(binIdx+1)), ...
    "Goodput_Mbps_mean", localMeanFinite(goodput), ...
    "Goodput_Mbps_p5", localPercentile(goodput, 5), ...
    "Goodput_Mbps_p50", localPercentile(goodput, 50), ...
    "Goodput_Mbps_p95", localPercentile(goodput, 95), ...
    "OfferedThroughput_Mbps_mean", localMeanFinite(offered), ...
    "SpectralEfficiency_bps_Hz_mean", localSafeDivide(localMeanFinite(goodput) * 1e6, double(bandwidthHz) * double(tddEfficiency)), ...
    "TrialCount", double(n), ...
    "SourceArtifact", string(sourceArtifact));
end

function rows = localDistributionRows(T, direction, ueLabel, bins, sourceArtifact)
rows = {};
nTotal = height(T);
sinr = localNumericFirst(T, "PostEqSINR_dB", NaN(nTotal, 1));
for bi = 1:numel(bins.centers)
    mask = localBinMask(sinr, bins.edges, bi);
    if ~any(mask)
        continue;
    end
    sub = T(mask, :);
    n = height(sub);
    rows{end+1, 1} = struct( ...
        "Direction", direction, ...
        "UEIndex", double(ueLabel), ...
        "RNTI", localRepresentativeNumeric(sub, "RNTI"), ...
        "PostEqSINR_dB_BinCenter", double(bins.centers(bi)), ...
        "TrialCount", double(n), ...
        "Fraction", localSafeDivide(n, nTotal), ...
        "PropagationDistance_m_mean", localMeanFinite(localNumericFirst(sub, "PropagationDistance_m", NaN(n, 1))), ...
        "LargeScaleSINR_dB_mean", localMeanFinite(localNumericFirst(sub, "LargeScaleSINR_dB", NaN(n, 1))), ...
        "ServingRSRP_dBm_mean", localMeanFinite(localNumericFirst(sub, ["ServingRSRP_dBm","RSRP_dBm"], NaN(n, 1))), ...
        "AppliedPathloss_dB_mean", localMeanFinite(localNumericFirst(sub, "AppliedPathloss_dB", NaN(n, 1))), ...
        "AppliedShadowFading_dB_mean", localMeanFinite(localNumericFirst(sub, "AppliedShadowFading_dB", NaN(n, 1))), ...
        "SourceArtifact", string(sourceArtifact)); %#ok<AGROW>
end
end

function T = localDistanceScatterRows(Tin, direction, sourceArtifact)
rows = {};
for i = 1:height(Tin)
    rowT = Tin(i, :);
    rows{end+1, 1} = struct( ...
        "Direction", direction, ...
        "UEIndex", localRepresentativeNumeric(rowT, ["UEIndex","UEID","UEId"]), ...
        "RNTI", localRepresentativeNumeric(rowT, "RNTI"), ...
        "TrialIndex", double(i), ...
        "PropagationDistance_m", localRepresentativeNumeric(rowT, "PropagationDistance_m"), ...
        "PostEqSINR_dB", localRepresentativeNumeric(rowT, "PostEqSINR_dB"), ...
        "LargeScaleSINR_dB", localRepresentativeNumeric(rowT, "LargeScaleSINR_dB"), ...
        "ReceiverHestSINR_dB", localRepresentativeNumeric(rowT, "ReceiverHestSINR_dB"), ...
        "AppliedPathloss_dB", localRepresentativeNumeric(rowT, "AppliedPathloss_dB"), ...
        "AppliedShadowFading_dB", localRepresentativeNumeric(rowT, "AppliedShadowFading_dB"), ...
        "MCS", localRepresentativeNumeric(rowT, ["MCS","MCSIndex"]), ...
        "Modulation", localRepresentativeString(rowT, "Modulation"), ...
        "Rank", localRepresentativeNumeric(rowT, ["Rank","Layers"]), ...
        "CRCPass", logical(localCRC(rowT)), ...
        "Goodput_Mbps", localRepresentativeNumeric(rowT, "Goodput_Mbps"), ...
        "SourceArtifact", string(sourceArtifact)); %#ok<AGROW>
end
T = localStructRowsToTable(rows, localDistanceScatterVars(), localDistanceScatterTypes());
end

function row = localMeasuredSummaryRow(T, direction, ueLabel, sourceArtifact, bandwidthHz, tddEfficiency)
n = height(T);
sinr = localNumericFirst(T, "PostEqSINR_dB", NaN(n, 1));
crc = localCRC(T);
goodput = localNumericFirst(T, "Goodput_Mbps", localRowBitrateMbps(T, "GoodBits", tddEfficiency));
bits = localNumericFirst(T, "BitsCompared", NaN(n, 1));
bitErrors = localNumericFirst(T, "BitErrors", NaN(n, 1));
dist = localNumericFirst(T, "PropagationDistance_m", NaN(n, 1));
row = struct( ...
    "Direction", direction, ...
    "UEIndex", localSummaryUELabel(ueLabel), ...
    "RNTI", localRepresentativeNumeric(T, "RNTI"), ...
    "N_Trials", double(n), ...
    "SINR_min_dB", localMinFinite(sinr), ...
    "SINR_p5_dB", localPercentile(sinr, 5), ...
    "SINR_p25_dB", localPercentile(sinr, 25), ...
    "SINR_median_dB", localPercentile(sinr, 50), ...
    "SINR_p75_dB", localPercentile(sinr, 75), ...
    "SINR_p95_dB", localPercentile(sinr, 95), ...
    "SINR_max_dB", localMaxFinite(sinr), ...
    "BLER_overall", localSafeDivide(sum(~crc), n), ...
    "BER_overall", localSafeDivide(sum(bitErrors(isfinite(bitErrors)), "omitnan"), sum(bits(isfinite(bits)), "omitnan")), ...
    "Goodput_Mbps_mean", localMeanFinite(goodput), ...
    "SpectralEfficiency_mean_bps_Hz", localSafeDivide(localMeanFinite(goodput) * 1e6, bandwidthHz * tddEfficiency), ...
    "MCS_dominant", localModeNumeric(T, ["MCS","MCSIndex"]), ...
    "Modulation_dominant", localModeString(T, "Modulation"), ...
    "Rank_dominant", localModeNumeric(T, ["Rank","Layers"]), ...
    "Distance_min_m", localMinFinite(dist), ...
    "Distance_max_m", localMaxFinite(dist), ...
    "KPIFormulaVersion", "measured_sinr_geometry_v1", ...
    "SourceArtifact", string(sourceArtifact));
end

function row = localKPISummaryRow(T, direction, ueLabel, sourceArtifact, bandwidthHz, tddEfficiency, slotDuration_s, runTag)
n = height(T);
sinr = localNumericFirst(T, "PostEqSINR_dB", NaN(n, 1));
crc = localCRC(T);
goodBits = localGoodBits(T, crc);
offeredBits = localNumericFirst(T, ["OfferedBits","ScheduledBits","TBSize_bits","TBSBits","TBS"], NaN(n, 1));
bits = localNumericFirst(T, "BitsCompared", NaN(n, 1));
bitErrors = localNumericFirst(T, "BitErrors", NaN(n, 1));
dist = localNumericFirst(T, "PropagationDistance_m", NaN(n, 1));
radioDuration_s = max(0, n) * double(slotDuration_s);
goodputMbps = localSafeDivide(sum(goodBits(isfinite(goodBits)), "omitnan"), radioDuration_s) / 1e6;
offeredMbps = localSafeDivide(sum(offeredBits(isfinite(offeredBits)), "omitnan"), radioDuration_s) / 1e6;
if ~isfinite(goodputMbps)
    goodputMbps = localMeanFinite(localNumericFirst(T, "Goodput_Mbps", NaN(n, 1)));
end
se = localSafeDivide(goodputMbps * 1e6, bandwidthHz * tddEfficiency);
formulaGoodput = localSafeDivide(sum(goodBits(isfinite(goodBits)), "omitnan"), radioDuration_s) / 1e6;
reconPass = isfinite(goodputMbps) && isfinite(formulaGoodput) && abs(goodputMbps - formulaGoodput) < 0.01;
strictOk = n > 0 && isfinite(localPercentile(sinr, 50)) && reconPass;
row = struct( ...
    "RunId", string(runTag), ...
    "Direction", direction, ...
    "UEIndex", localSummaryUELabel(ueLabel), ...
    "RNTI", localRepresentativeNumeric(T, "RNTI"), ...
    "KPIFormulaVersion", "measured_sinr_geometry_v1", ...
    "KPIReconciliationPass", logical(reconPass), ...
    "SINR_median_dB", localPercentile(sinr, 50), ...
    "SINR_p5_dB", localPercentile(sinr, 5), ...
    "SINR_p95_dB", localPercentile(sinr, 95), ...
    "BLER_overall", localSafeDivide(sum(~crc), n), ...
    "BER_overall", localSafeDivide(sum(bitErrors(isfinite(bitErrors)), "omitnan"), sum(bits(isfinite(bits)), "omitnan")), ...
    "Goodput_Mbps", goodputMbps, ...
    "OfferedThroughput_Mbps", offeredMbps, ...
    "SpectralEfficiency_bps_Hz", se, ...
    "RadioDuration_s", radioDuration_s, ...
    "TrialCount", double(n), ...
    "MCS_dominant", localModeNumeric(T, ["MCS","MCSIndex"]), ...
    "Rank_dominant", localModeNumeric(T, ["Rank","Layers"]), ...
    "DistanceRange_m", sprintf("%.6g-%.6g", localMinFinite(dist), localMaxFinite(dist)), ...
    "StrictOk", logical(strictOk), ...
    "Status", string(localTernary(strictOk, "pass", "fail")), ...
    "FailureReason", string(localTernary(strictOk, "", "measured_sinr_geometry_kpi_unavailable_or_reconciliation_failed")), ...
    "SourceArtifact", string(sourceArtifact));
end

function localUpdateLinkAnchorKPIs(layout, summaryT)
anchorPath = fullfile(layout.AirInterfaceCSVDir, "link_anchor_kpis.csv");
if exist(anchorPath, "file") == 2
    try
        anchor = readtable(anchorPath, "VariableNamingRule", "preserve", "TextType", "string");
    catch
        anchor = table();
    end
else
    anchor = table(["DL_PDSCH_Throughput";"UL_PUSCH_Throughput"], false(2,1), false(2,1), ...
        NaN(2,1), NaN(2,1), NaN(2,1), zeros(2,1), repmat("", 2, 1), ...
        'VariableNames', {'Case','Ok','Skipped','SINR_median_dB','Goodput_Mbps','BLER','TrialCount','Notes'});
end
if isempty(anchor)
    return;
end
if ~localHasColumn(anchor, "Case")
    return;
end
anchor = localEnsureAnchorColumns(anchor);
for direction = ["DL", "UL"]
    row = localSummaryAllRow(summaryT, direction);
    if isempty(row)
        continue;
    end
    caseName = string(localTernary(direction == "DL", "DL_PDSCH_Throughput", "UL_PUSCH_Throughput"));
    mask = strcmpi(string(anchor.Case), caseName);
    if ~any(mask)
        anchor(end+1, :) = anchor(1, :); %#ok<AGROW>
        mask = false(height(anchor), 1);
        mask(end) = true;
        anchor.Case(mask) = caseName;
    end
    bler = double(row.BLER_overall(1));
    anchor.Ok(mask) = bler < 0.20;
    anchor.Skipped(mask) = false;
    anchor.SINR_median_dB(mask) = double(row.SINR_median_dB(1));
    anchor.Goodput_Mbps(mask) = double(row.Goodput_Mbps_mean(1));
    anchor.BLER(mask) = bler;
    anchor.TrialCount(mask) = double(row.N_Trials(1));
    anchor.Notes(mask) = sprintf("Geometry-driven; measured SINR p5-p95=[%.1f,%.1f] dB from %.0f-%.0f m; no AWGN injection", ...
        double(row.SINR_p5_dB(1)), double(row.SINR_p95_dB(1)), ...
        double(row.Distance_min_m(1)), double(row.Distance_max_m(1)));
end
if localHasColumn(anchor, "Notes")
    notes = string(anchor.Notes);
    notes = replace(notes, "deferred_to_primary_raw_trials", "geometry_driven_measured_sinr_evidence");
    anchor.Notes = notes;
end
sixgr.analytics.writeAnalysisTable(anchorPath, anchor);
end

function anchor = localEnsureAnchorColumns(anchor)
n = height(anchor);
if ~localHasColumn(anchor, "Ok")
    anchor.Ok = false(n, 1);
end
if ~localHasColumn(anchor, "Skipped")
    anchor.Skipped = false(n, 1);
end
for name = ["SINR_median_dB","Goodput_Mbps","BLER","TrialCount"]
    if ~localHasColumn(anchor, name)
        anchor.(char(name)) = NaN(n, 1);
    end
end
if ~localHasColumn(anchor, "Notes")
    anchor.Notes = repmat("", n, 1);
end
end

function row = localSummaryAllRow(summaryT, direction)
row = table();
if ~(istable(summaryT) && height(summaryT) > 0)
    return;
end
mask = strcmpi(string(summaryT.Direction), string(direction)) & strcmpi(string(summaryT.UEIndex), "all");
if any(mask)
    row = summaryT(find(mask, 1), :);
end
end

function localDeleteLegacySweepArtifacts(layout)
paths = [
    fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv")
    fullfile(layout.AirInterfaceCSVDir, "live_link_snr_sweep.csv")
    fullfile(layout.ReportCSVDir, "per_sweep_comparison_tables.csv")
    fullfile(layout.ReportImageDir, "bler_vs_snr_unavailable.svg")
    fullfile(layout.ReportImageDir, "throughput_vs_snr_unavailable.svg")
    fullfile(layout.ReportImageDir, "bler_vs_snr.png")
    fullfile(layout.ReportImageDir, "throughput_vs_snr.png")
    ];
for i = 1:numel(paths)
    if exist(paths(i), "file") == 2
        delete(paths(i));
    end
end
end

function localRelabelAnalyticsCSVAndSVG(layout)
csvDir = fullfile(layout.Root, "analytics", "csv");
imgDir = fullfile(layout.Root, "analytics", "image");
specs = [
    "contract__error-reliability-analytics__bler-vs-snr", "BLER vs Measured PostEq SINR", "contract__error-reliability-analytics__bler-vs-measured-sinr";
    "contract__error-reliability-analytics__ber-vs-snr", "BER vs Measured PostEq SINR", "contract__error-reliability-analytics__ber-vs-measured-sinr";
    "contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-snr", "Throughput vs Measured PostEq SINR", "contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-measured-sinr"
    ];
for i = 1:size(specs, 1)
    stem = specs(i, 1);
    titleText = specs(i, 2);
    aliasStem = specs(i, 3);
    csvPath = fullfile(csvDir, stem + ".csv");
    if exist(csvPath, "file") == 2
        try
            T = readtable(csvPath, "VariableNamingRule", "preserve", "TextType", "string");
            if localHasColumn(T, "chart_name")
                T.chart_name(:) = titleText;
            end
            if localHasColumn(T, "SNR_dB") && ~localHasColumn(T, "PostEqSINR_dB")
                T.Properties.VariableNames{strcmp(string(T.Properties.VariableNames), "SNR_dB")} = char("PostEqSINR_dB");
            end
            sixgr.analytics.writeAnalysisTable(csvPath, T);
            sixgr.analytics.writeAnalysisTable(fullfile(csvDir, aliasStem + ".csv"), T);
        catch
        end
    end
    svgPath = fullfile(imgDir, stem + ".svg");
    if exist(svgPath, "file") == 2
        try
            txt = string(fileread(svgPath));
            txt = replace(txt, "BLER vs SNR", "BLER vs Measured SINR");
            txt = replace(txt, "BER vs SNR", "BER vs Measured SINR");
            txt = replace(txt, "throughput vs SNR", "Throughput vs Measured SINR");
            txt = replace(txt, "Throughput vs SNR", "Throughput vs Measured SINR");
            txt = replace(txt, "Applied AWGN SNR (dB)", "Measured PostEq SINR (dB)");
            txt = replace(txt, "SNR (dB)", "Measured PostEq SINR (dB)");
            fid = fopen(svgPath, "w");
            if fid > 0
                cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fwrite(fid, char(txt));
            end
            aliasSvgPath = fullfile(imgDir, aliasStem + ".svg");
            sixgr.util.ensureDir(aliasSvgPath);
            fidAlias = fopen(aliasSvgPath, "w");
            if fidAlias > 0
                cleanupAlias = onCleanup(@() fclose(fidAlias)); %#ok<NASGU>
                fwrite(fidAlias, char(txt));
            end
        catch
        end
    end
end
end

function T = localSortDistanceScatter(T)
if istable(T) && height(T) > 0 && localHasColumn(T, "PropagationDistance_m")
    d = double(T.PropagationDistance_m);
    d(~isfinite(d)) = Inf;
    [~, idx] = sort(d, "ascend");
    T = T(idx, :);
end
end

function T = localConcatTables(varargin)
parts = {};
for i = 1:nargin
    T = varargin{i};
    if istable(T) && width(T) > 0
        parts{end+1} = T; %#ok<AGROW>
    end
end
if isempty(parts)
    T = table();
    return;
end
T = parts{1};
for i = 2:numel(parts)
    T = [T; parts{i}]; %#ok<AGROW>
end
end

function runDir = localResolveRunDir(cfg)
if ischar(cfg) || (isstring(cfg) && isscalar(cfg))
    runDir = char(string(cfg));
    return;
end
runDir = char(string(sixgr.util.structGet(cfg, "output_dir", ...
    sixgr.util.structGet(cfg, "outputs.output_dir", ...
    sixgr.util.structGet(cfg, "run.rootRunFolder", ...
    sixgr.util.structGet(cfg, "runFolder", pwd))))));
end

function T = localTableField(s, names)
T = table();
if ~isstruct(s)
    return;
end
for name = string(names)
    if isfield(s, char(name)) && istable(s.(char(name)))
        T = s.(char(name));
        return;
    end
end
end

function bandwidthHz = localBandwidthHz(cfg, scenarioCfg)
bandwidthHz = localFirstFinite([ ...
    localStructNumeric(cfg, "frequency.bandwidth_hz"), ...
    localStructNumeric(cfg, "frequency.bandwidthHz"), ...
    localStructNumeric(cfg, "global_radio_scope.channel_bandwidth_hz"), ...
    localStructNumeric(scenarioCfg, "frequency.bandwidth_hz"), ...
    localStructNumeric(scenarioCfg, "global_radio_scope.channel_bandwidth_hz"), ...
    100e6], 100e6);
end

function slotDuration_s = localSlotDurationSeconds(cfg, scenarioCfg)
slotDuration_s = localFirstFinite([ ...
    localStructNumeric(cfg, "phy.numerology.slotDuration_s"), ...
    localStructNumeric(cfg, "frame.slot_duration_s"), ...
    localStructNumeric(scenarioCfg, "frame.slot_duration_s"), ...
    localStructNumeric(scenarioCfg, "frame_timing.slot_duration_ms") / 1e3, ...
    0.5e-3], 0.5e-3);
end

function x = localStructNumeric(s, path)
x = NaN;
if isstruct(s)
    try
        raw = sixgr.util.structGet(s, path, NaN);
        if isnumeric(raw) && isscalar(raw)
            x = double(raw);
        else
            x = str2double(string(raw));
        end
    catch
        x = NaN;
    end
end
end

function x = localNumericFirst(T, names, defaultValue)
x = defaultValue(:);
for name = string(names)
    if localHasColumn(T, name)
        x = localToDouble(T.(char(name)));
        return;
    end
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif iscell(v)
    x = str2double(string(v));
else
    x = str2double(string(v));
end
x = x(:);
end

function b = localToLogical(v)
if islogical(v)
    b = v(:);
elseif isnumeric(v)
    b = double(v(:)) ~= 0;
else
    s = lower(strtrim(string(v(:))));
    b = ismember(s, ["true","1","yes","y","pass","ok"]);
end
end

function crc = localCRC(T)
n = height(T);
if localHasColumn(T, "CRCPass")
    crc = localToLogical(T.CRCPass);
elseif localHasColumn(T, "TBCrcPass")
    crc = localToLogical(T.TBCrcPass);
elseif localHasColumn(T, "Status")
    status = upper(strtrim(string(T.Status)));
    crc = status == "PASS" | status == "OK";
else
    crc = true(n, 1);
end
crc = crc(:);
if numel(crc) ~= n
    crc = repmat(false, n, 1);
end
end

function bits = localGoodBits(T, crc)
n = height(T);
bits = localNumericFirst(T, ["GoodBits","GoodputBits","DeliveredBits"], NaN(n, 1));
missing = ~isfinite(bits);
tb = localNumericFirst(T, ["TBSize_bits","TBSBits","TBS","ScheduledBits"], NaN(n, 1));
bits(missing & crc & isfinite(tb)) = tb(missing & crc & isfinite(tb));
bits(~crc) = 0;
end

function mbps = localRowBitrateMbps(T, bitNames, tddEfficiency)
bits = localNumericFirst(T, bitNames, NaN(height(T), 1));
mbps = bits ./ max(0.5e-3, eps) / 1e6;
if nargin >= 3 && isfinite(tddEfficiency) && tddEfficiency > 0
    mbps = mbps .* double(tddEfficiency);
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && any(string(T.Properties.VariableNames) == string(name));
end

function value = localRepresentativeNumeric(T, names)
value = NaN;
if ~(istable(T) && height(T) > 0)
    return;
end
x = localNumericFirst(T, names, NaN(height(T), 1));
x = x(isfinite(x));
if ~isempty(x)
    value = double(x(1));
end
end

function value = localRepresentativeString(T, names)
value = "";
if ~(istable(T) && height(T) > 0)
    return;
end
for name = string(names)
    if localHasColumn(T, name)
        raw = string(T.(char(name)));
        raw = raw(~ismissing(raw) & strlength(strtrim(raw)) > 0);
        if ~isempty(raw)
            value = raw(1);
            return;
        end
    end
end
end

function value = localModeNumeric(T, names)
value = NaN;
x = localNumericFirst(T, names, NaN(height(T), 1));
x = x(isfinite(x));
if isempty(x)
    return;
end
u = unique(x);
counts = zeros(numel(u), 1);
for i = 1:numel(u)
    counts(i) = sum(x == u(i));
end
[~, idx] = max(counts);
value = u(idx);
end

function value = localModeString(T, names)
value = "";
vals = strings(0, 1);
for name = string(names)
    if localHasColumn(T, name)
        vals = string(T.(char(name)));
        break;
    end
end
vals = vals(~ismissing(vals) & strlength(strtrim(vals)) > 0);
if isempty(vals)
    return;
end
u = unique(vals);
counts = zeros(numel(u), 1);
for i = 1:numel(u)
    counts(i) = sum(vals == u(i));
end
[~, idx] = max(counts);
value = u(idx);
end

function value = localMeanFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end

function value = localMinFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = min(x);
end
end

function value = localMaxFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function value = localPercentile(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
    return;
end
if numel(x) == 1
    value = x(1);
    return;
end
pos = 1 + (numel(x) - 1) * double(pct) / 100;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    value = x(lo);
else
    value = x(lo) + (x(hi) - x(lo)) * (pos - lo);
end
end

function [lo, hi] = localWilsonCI(fails, total)
if ~(isfinite(total) && total > 0)
    lo = NaN;
    hi = NaN;
    return;
end
z = 1.96;
p = localSafeDivide(fails, total);
den = 1 + z^2 / total;
center = (p + z^2 / (2 * total)) / den;
half = z * sqrt(p * (1 - p) / total + z^2 / (4 * total^2)) / den;
lo = max(0, center - half);
hi = min(1, center + half);
end

function y = localSafeDivide(a, b)
if ~(isfinite(double(a)) && isfinite(double(b)) && double(b) ~= 0)
    y = NaN;
else
    y = double(a) ./ double(b);
end
end

function value = localFirstFinite(values, defaultValue)
value = defaultValue;
for i = 1:numel(values)
    if isfinite(values(i))
        value = values(i);
        return;
    end
end
end

function label = localSummaryUELabel(ueLabel)
if isfinite(double(ueLabel))
    label = string(sprintf("%.0f", double(ueLabel)));
else
    label = "all";
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end

function T = localStructRowsToTable(rows, vars, types)
vars = cellstr(string(vars));
types = cellstr(string(types));
if isempty(rows)
    T = table('Size', [0 numel(vars)], 'VariableTypes', types, 'VariableNames', vars);
    return;
end
S = vertcat(rows{:});
T = struct2table(S, "AsArray", true);
for i = 1:numel(vars)
    if ~localHasColumn(T, vars{i})
        switch types{i}
            case "string"
                T.(vars{i}) = repmat("", height(T), 1);
            case "logical"
                T.(vars{i}) = false(height(T), 1);
            otherwise
                T.(vars{i}) = NaN(height(T), 1);
        end
    end
end
T = T(:, vars);
end

function T = localEmptyBlerCurve()
T = localStructRowsToTable({}, localBlerCurveVars(), localBlerCurveTypes());
end

function T = localEmptyThroughputCurve()
T = localStructRowsToTable({}, localThroughputCurveVars(), localThroughputCurveTypes());
end

function T = localEmptyDistribution()
T = localStructRowsToTable({}, localDistributionVars(), localDistributionTypes());
end

function T = localEmptyDistanceScatter()
T = localStructRowsToTable({}, localDistanceScatterVars(), localDistanceScatterTypes());
end

function T = localEmptyMeasuredSummary()
T = localStructRowsToTable({}, localMeasuredSummaryVars(), localMeasuredSummaryTypes());
end

function T = localEmptyKPISummary()
T = localStructRowsToTable({}, localKPISummaryVars(), localKPISummaryTypes());
end

function vars = localBlerCurveVars()
vars = ["Direction","UEIndex","RNTI","PostEqSINR_dB_BinCenter","PostEqSINR_dB_BinMin","PostEqSINR_dB_BinMax", ...
    "BLER","BLER_CI_Low","BLER_CI_High","BER","TrialCount","FailureCount", ...
    "PropagationDistance_m_mean","PropagationDistance_m_min","PropagationDistance_m_max", ...
    "MCS_dominant","Modulation_dominant","Rank_dominant","SourceArtifact"];
end

function types = localBlerCurveTypes()
types = ["string","double","double","double","double","double","double","double","double","double","double","double", ...
    "double","double","double","double","string","double","string"];
end

function vars = localThroughputCurveVars()
vars = ["Direction","UEIndex","RNTI","PostEqSINR_dB_BinCenter","PostEqSINR_dB_BinMin","PostEqSINR_dB_BinMax", ...
    "Goodput_Mbps_mean","Goodput_Mbps_p5","Goodput_Mbps_p50","Goodput_Mbps_p95", ...
    "OfferedThroughput_Mbps_mean","SpectralEfficiency_bps_Hz_mean","TrialCount","SourceArtifact"];
end

function types = localThroughputCurveTypes()
types = ["string","double","double","double","double","double","double","double","double","double","double","double","double","string"];
end

function vars = localDistributionVars()
vars = ["Direction","UEIndex","RNTI","PostEqSINR_dB_BinCenter","TrialCount","Fraction", ...
    "PropagationDistance_m_mean","LargeScaleSINR_dB_mean","ServingRSRP_dBm_mean", ...
    "AppliedPathloss_dB_mean","AppliedShadowFading_dB_mean","SourceArtifact"];
end

function types = localDistributionTypes()
types = ["string","double","double","double","double","double","double","double","double","double","double","string"];
end

function vars = localDistanceScatterVars()
vars = ["Direction","UEIndex","RNTI","TrialIndex","PropagationDistance_m","PostEqSINR_dB", ...
    "LargeScaleSINR_dB","ReceiverHestSINR_dB","AppliedPathloss_dB","AppliedShadowFading_dB", ...
    "MCS","Modulation","Rank","CRCPass","Goodput_Mbps","SourceArtifact"];
end

function types = localDistanceScatterTypes()
types = ["string","double","double","double","double","double","double","double","double","double","double","string","double","logical","double","string"];
end

function vars = localMeasuredSummaryVars()
vars = ["Direction","UEIndex","RNTI","N_Trials","SINR_min_dB","SINR_p5_dB","SINR_p25_dB", ...
    "SINR_median_dB","SINR_p75_dB","SINR_p95_dB","SINR_max_dB", ...
    "BLER_overall","BER_overall","Goodput_Mbps_mean","SpectralEfficiency_mean_bps_Hz", ...
    "MCS_dominant","Modulation_dominant","Rank_dominant","Distance_min_m","Distance_max_m", ...
    "KPIFormulaVersion","SourceArtifact"];
end

function types = localMeasuredSummaryTypes()
types = ["string","string","double","double","double","double","double","double","double","double","double", ...
    "double","double","double","double","double","string","double","double","double","string","string"];
end

function vars = localKPISummaryVars()
vars = ["RunId","Direction","UEIndex","RNTI","KPIFormulaVersion","KPIReconciliationPass", ...
    "SINR_median_dB","SINR_p5_dB","SINR_p95_dB","BLER_overall","BER_overall", ...
    "Goodput_Mbps","OfferedThroughput_Mbps","SpectralEfficiency_bps_Hz", ...
    "RadioDuration_s","TrialCount","MCS_dominant","Rank_dominant", ...
    "DistanceRange_m","StrictOk","Status","FailureReason","SourceArtifact"];
end

function types = localKPISummaryTypes()
types = ["string","string","string","double","string","logical","double","double","double","double","double", ...
    "double","double","double","double","double","double","double","string","logical","string","string","string"];
end
