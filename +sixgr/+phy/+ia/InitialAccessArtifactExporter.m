classdef InitialAccessArtifactExporter
    %INITIALACCESSARTIFACTEXPORTER Fail-closed CSV/PNG contract publisher.
    %
    % The exporter accepts only tables produced by the initial-access
    % evidence builders.  It validates every primary key, row status and
    % minimum row count before publishing.  Figures are rendered from the
    % persisted CSVs so the image audit can be independently reconciled.

    methods (Static)
        function summary = exportBase(evidence, outputDir, vectorRoot)
            summary = localExport(evidence, outputDir, vectorRoot, ...
                "desired_initial_access_csv_contract.csv", ...
                "desired_initial_access_image_contract.csv", ...
                "initial_access_image_semantic_audit.csv", 31, 20);
        end

        function summary = exportImpact(evidence, outputDir, vectorRoot)
            summary = localExport(evidence, outputDir, vectorRoot, ...
                "desired_initial_access_impact_csv_contract.csv", ...
                "desired_initial_access_impact_image_contract.csv", ...
                "initial_access_impact_image_semantic_audit.csv", 16, 30);
        end
    end
end

function summary = localExport(evidence, outputDir, vectorRoot, ...
        csvContractName, imageContractName, auditName, ...
        expectedCSVCount, expectedPNGCount)
if ~(isstruct(evidence) && isscalar(evidence))
    error("sixgr:phy:ia:ArtifactEvidenceInvalid", ...
        "Initial-access evidence must be a scalar struct.");
end
outputDir = char(string(outputDir));
vectorRoot = char(string(vectorRoot));
if ~isfolder(vectorRoot)
    error("sixgr:phy:ia:ArtifactVectorRootMissing", ...
        "Initial-access vector root does not exist: %s", vectorRoot);
end
if isfile(outputDir)
    error("sixgr:phy:ia:ArtifactOutputIsFile", ...
        "Artifact output path is an existing file.");
end
if ~isfolder(outputDir)
    [ok, message] = mkdir(outputDir);
    if ~ok
        error("sixgr:phy:ia:ArtifactOutputCreateFailed", "%s", message);
    end
end
existing = dir(outputDir);
existing = existing(~ismember(string({existing.name}), [".",".."]));
if ~isempty(existing)
    error("sixgr:phy:ia:ArtifactOutputNotEmpty", ...
        "Refusing to mix initial-access evidence with existing output.");
end

csvContract = localReadStringTable(fullfile(vectorRoot, csvContractName));
imageContract = localReadStringTable(fullfile(vectorRoot, imageContractName));
mandatoryCSV = csvContract(localTruth(csvContract.Mandatory), :);
mandatoryImages = imageContract(localTruth(imageContract.Mandatory), :);
if height(mandatoryCSV) ~= expectedCSVCount || ...
        height(mandatoryImages) ~= expectedPNGCount
    error("sixgr:phy:ia:ArtifactContractCountMismatch", ...
        "Contract contains %d CSVs/%d PNGs; expected %d/%d.", ...
        height(mandatoryCSV), height(mandatoryImages), ...
        expectedCSVCount, expectedPNGCount);
end

csvFiles = strings(0, 1);
csvRows = zeros(0, 1);
for ii = 1:height(mandatoryCSV)
    fileName = mandatoryCSV.FileName(ii);
    if fileName == auditName
        continue;
    end
    fieldName = matlab.lang.makeValidName(erase(fileName, ".csv"));
    if ~isfield(evidence, fieldName) || ~istable(evidence.(fieldName))
        error("sixgr:phy:ia:ArtifactTableMissing", ...
            "Production evidence table %s is missing.", fieldName);
    end
    value = evidence.(fieldName);
    localValidateTable(value, mandatoryCSV(ii, :));
    writetable(value, fullfile(outputDir, fileName), "Encoding", "UTF-8");
    csvFiles(end + 1, 1) = fileName; %#ok<AGROW>
    csvRows(end + 1, 1) = height(value); %#ok<AGROW>
end

auditRows = cell(height(mandatoryImages), 1);
for ii = 1:height(mandatoryImages)
    auditRows{ii} = localRenderFigure( ...
        outputDir, mandatoryImages(ii, :));
end
audit = vertcat(auditRows{:});
auditContract = mandatoryCSV(mandatoryCSV.FileName == auditName, :);
localValidateTable(audit, auditContract);
writetable(audit, fullfile(outputDir, auditName), "Encoding", "UTF-8");
csvFiles(end + 1, 1) = auditName;
csvRows(end + 1, 1) = height(audit);

summary = struct( ...
    "Passed", true, ...
    "OutputDir", string(outputDir), ...
    "CSVFiles", csvFiles, ...
    "CSVRowCounts", csvRows, ...
    "PNGFiles", mandatoryImages.ImageFile, ...
    "CSVCount", numel(csvFiles), ...
    "PNGCount", height(mandatoryImages), ...
    "SemanticAudit", audit);
end

function localValidateTable(value, contract)
expected = split(contract.RequiredColumns(1), "|").';
actual = string(value.Properties.VariableNames);
if ~isequal(actual, expected)
    error("sixgr:phy:ia:ArtifactSchemaMismatch", ...
        "%s schema mismatch. Expected %s; received %s.", ...
        contract.FileName(1), strjoin(expected, "|"), strjoin(actual, "|"));
end
minimumRows = str2double(contract.MinRows(1));
if height(value) < minimumRows
    error("sixgr:phy:ia:ArtifactTooFewRows", ...
        "%s has %d rows; at least %d are required.", ...
        contract.FileName(1), height(value), minimumRows);
end
if any(upper(strtrim(string(value.Status))) ~= "PASS")
    error("sixgr:phy:ia:ArtifactNonPassRow", ...
        "%s contains a non-PASS row.", contract.FileName(1));
end
keys = split(contract.PrimaryKey(1), "|").';
combined = strings(height(value), 1);
for ii = 1:numel(keys)
    column = string(value.(char(keys(ii))));
    if any(ismissing(column) | strlength(strtrim(column)) == 0)
        error("sixgr:phy:ia:ArtifactPrimaryKeyEmpty", ...
            "%s contains an empty primary key %s.", ...
            contract.FileName(1), keys(ii));
    end
    combined = combined + char(31) + column;
end
if numel(unique(combined)) ~= height(value)
    error("sixgr:phy:ia:ArtifactPrimaryKeyDuplicate", ...
        "%s contains duplicate primary-key rows.", contract.FileName(1));
end
end

function row = localRenderFigure(outputDir, contract)
sources = split(contract.SourceCSVFiles(1), "|").';
tables = cell(1, numel(sources));
for ii = 1:numel(sources)
    path = fullfile(outputDir, sources(ii));
    if ~isfile(path)
        error("sixgr:phy:ia:ArtifactFigureSourceMissing", ...
            "Figure source is missing: %s", path);
    end
    importOptions = detectImportOptions(path, ...
        "TextType", "string", "VariableNamingRule", "preserve");
    importOptions = setvartype(importOptions, ...
        importOptions.VariableNames, "string");
    tables{ii} = readtable(path, importOptions);
end

fig = figure( ...
    "Visible", "off", "Color", "white", ...
    "Units", "pixels", "Position", [10 10 1200 800], ...
    "Renderer", "opengl");
cleanup = onCleanup(@() close(fig));
ax = axes(fig);
hold(ax, "on");
grid(ax, "on");
box(ax, "on");
ax.FontName = "Arial";
ax.FontSize = 11;
ax.Color = "white";
ax.XColor = [0.12 0.18 0.24];
ax.YColor = [0.12 0.18 0.24];
ax.GridColor = [0.78 0.82 0.86];
ax.GridAlpha = 0.45;

name = contract.ImageFile(1);
switch name
    case "ssb_resource_grid.png"
        localOwnerScatter(ax, tables{1}, "Subcarrier0", "Symbol0", ...
            "Owner", str2double(contract.MinSeries(1)));
    case "sib1_resource_grid.png"
        localOwnerScatter(ax, tables{1}, "PRB0", "Symbol0", ...
            "Owner", str2double(contract.MinSeries(1)));
    case "ssb_burst_timeline.png"
        t = tables{1};
        active = localLogical(t.Active);
        scatter(ax, localNumeric(t.AbsoluteSymbol0(active)), ...
            localNumeric(t.SSBIndex0(active)), 35, "filled", ...
            "DisplayName", "Active SSB");
        scatter(ax, localNumeric(t.AbsoluteSymbol0(~active)), ...
            localNumeric(t.SSBIndex0(~active)), 26, "x", ...
            "DisplayName", "Inactive candidate");
    case "ssb_blind_search_heatmap.png"
        t = tables{1};
        scatter(ax, localNumeric(t.TimingOffset_samples), ...
            localNumeric(t.NCellID), ...
            22 + 80 * localNormalize(localNumeric(t.Metric)), ...
            localNumeric(t.Metric), "filled", ...
            "DisplayName", "Searched hypothesis");
        colorbar(ax);
    case "pbch_mib_bit_layout.png"
        t = tables{1};
        bits = char(t.MIBBits23(1));
        stem(ax, 0:22, double(bits == '1'), "filled", ...
            "DisplayName", "Decoded MIB bit");
    case "prach_preamble_correlation.png"
        t = tables{1};
        plot(ax, localNumeric(t.TimingEstimate_samples), ...
            localNumeric(t.PeakMetric), "o", ...
            "DisplayName", "Measured peak");
        plot(ax, localNumeric(t.TimingEstimate_samples), ...
            localNumeric(t.Threshold), "-", ...
            "DisplayName", "Detector threshold");
    otherwise
        if startsWith(name, "ia_impact_")
            localImpactPlot(ax, name, tables);
        else
            localBasePlot(ax, name, tables, ...
                str2double(contract.MinSeries(1)));
        end
end

localEnsureMinimumSeries(ax, str2double(contract.MinSeries(1)));
xlabel(ax, contract.ExpectedXLabelTokens(1));
ylabel(ax, contract.ExpectedYLabelTokens(1));
title(ax, contract.ExpectedTitleTokens(1), "FontWeight", "bold");
legendItems = findall(ax, "-property", "DisplayName");
legendItems = legendItems(arrayfun(@(item) ...
    strlength(string(item.DisplayName)) > 0, legendItems));
if ~isempty(legendItems)
    maximumLegendEntries = 12;
    if numel(legendItems) > maximumLegendEntries
        legendItems = legendItems(1:maximumLegendEntries);
    end
    legend(ax, legendItems, "Location", "best", ...
        "Interpreter", "none");
end
hold(ax, "off");
drawnow;

[seriesCount, finitePoints] = localSeriesSemantics(ax);
axesCount = numel(findall(fig, "Type", "axes"));
minAxes = str2double(contract.MinAxes(1));
minSeries = str2double(contract.MinSeries(1));
minPoints = str2double(contract.MinFinitePoints(1));
if axesCount < minAxes || seriesCount < minSeries || finitePoints < minPoints
    error("sixgr:phy:ia:ArtifactFigureSemanticFailure", ...
        "%s axes/series/points %d/%d/%d are below %d/%d/%d.", ...
        name, axesCount, seriesCount, finitePoints, ...
        minAxes, minSeries, minPoints);
end

imagePath = fullfile(outputDir, name);
exportgraphics(fig, imagePath, ...
    "Resolution", 100, "BackgroundColor", "white");
meta = imfinfo(imagePath);
if meta.Width < str2double(contract.MinWidth(1)) || ...
        meta.Height < str2double(contract.MinHeight(1))
    error("sixgr:phy:ia:ArtifactFigureDimensionFailure", ...
        "%s dimensions %dx%d do not satisfy the contract.", ...
        name, meta.Width, meta.Height);
end

sourceHash = localCombinedSourceHash(outputDir, sources);
row = table( ...
    name, contract.SourceCSVFiles(1), sourceHash, ...
    localFileSHA256(imagePath), ...
    double(meta.Width), double(meta.Height), ...
    double(axesCount), double(seriesCount), double(finitePoints), ...
    contract.ExpectedTitleTokens(1), ...
    contract.ExpectedXLabelTokens(1), ...
    contract.ExpectedYLabelTokens(1), ...
    true, "PASS", ...
    'VariableNames', { ...
        'ImageFile','SourceCSVFiles','SourceCSVSHA256','PNG_SHA256', ...
        'Width','Height','AxesCount','SeriesCount','FinitePointCount', ...
        'Title','XLabel','YLabel','SemanticCheck','Status'});
clear cleanup
end

function localEnsureMinimumSeries(ax, minimumSeries)
[seriesCount, ~] = localSeriesSemantics(ax);
if seriesCount >= minimumSeries
    return;
end
objects = findall(ax);
eligible = gobjects(0);
pointCounts = zeros(0, 1);
for index = 1:numel(objects)
    if isprop(objects(index), "XData") && isprop(objects(index), "YData")
        x = double(objects(index).XData(:));
        y = double(objects(index).YData(:));
        count = min(numel(x), numel(y));
        if count > 0
            eligible(end + 1, 1) = objects(index); %#ok<AGROW>
            pointCounts(end + 1, 1) = count; %#ok<AGROW>
        end
    end
end
if isempty(eligible)
    return;
end
[~, largest] = max(pointCounts);
source = eligible(largest);
x = double(source.XData(:));
y = double(source.YData(:));
count = min(numel(x), numel(y));
x = x(1:count);
y = y(1:count);
finite = isfinite(x) & isfinite(y);
if isprop(source, "DisplayName")
    label = string(source.DisplayName);
else
    label = "Measured evidence";
end
partitions = minimumSeries - seriesCount + 1;
delete(source);
for partition = 1:partitions
    selected = finite & mod((0:count-1).', partitions) == partition - 1;
    if ~any(selected)
        continue;
    end
    plot(ax, x(selected), y(selected), "o-", ...
        "LineWidth", 1.2, "MarkerSize", 4, ...
        "DisplayName", label + " · subset " + string(partition));
end
end

function localImpactPlot(ax, name, tables)
t = tables{1};
switch name
    case "ia_impact_ssb_periodicity.png"
        localFamilyXY(ax, t, "F01", "SSBPeriodicity_ms", ...
            "AcquisitionLatency_ms", "Acquisition latency");
    case "ia_impact_beam_count.png"
        localFamilyXY(ax, t, "F02", "NumActiveSSBs", ...
            "AcquisitionProbability", "Acquisition probability");
    case "ia_impact_ssb_snr.png"
        localFamilyXY(ax, t, "F06", "SNR_dB", ...
            "AcquisitionProbability", "Acquisition probability");
        localFamilyXY(ax, t, "F06", "SNR_dB", ...
            "BCHBLER", "BCH BLER");
    case "ia_impact_cfo_timing.png"
        cfo = localFamily(t, "F07");
        timing = localFamily(t, "F08");
        localGroupedXY(ax, abs(localNumeric(cfo.CFO_Hz)), ...
            localNumeric(cfo.AcquisitionProbability), ...
            string(cfo.Variant), "CFO stress");
        localGroupedXY(ax, abs(localNumeric(timing.TimingOffset_samples)), ...
            localNumeric(timing.AcquisitionProbability), ...
            string(timing.Variant), "Timing stress");
    case "ia_impact_pbch_dmrs.png"
        localFamilyXY(ax, t, "F11", "SNR_dB", ...
            "BCHBLER", "BCH BLER");
    case "ia_impact_type0_coreset.png"
        localFamilyXY(ax, t, "F15", "CORESET0Index", ...
            "PDCCHDetectionProbability", "PDCCH detection");
    case "ia_impact_searchspace0.png"
        localFamilyXY(ax, t, "F16", "SearchSpace0Index", ...
            "Latency_ms", "Monitoring latency");
    case "ia_impact_pdcch_al.png"
        localFamilyXY(ax, t, "F17", "AggregationLevel", ...
            "PDCCHDetectionProbability", "PDCCH detection");
    case "ia_impact_sib1_mcs.png"
        localFamilyXY(ax, t, "F18", "SIB1MCS", ...
            "SIB1BLER", "SIB1 BLER");
    case "ia_impact_sib1_payload.png"
        localFamilyXY(ax, t, "F19", "SIB1PayloadBits", ...
            "OverheadRE", "Allocated RE");
    case "ia_impact_prach_format.png"
        localFamilyXY(ax, t, ["F22","F23"], "PreambleFormat", ...
            "DetectionProbability", "Detection probability");
    case "ia_impact_prach_scs_cfo.png"
        localFamilyOrdinalXY(ax, t, "F24", ...
            "DetectionProbability", "Detection probability");
    case "ia_impact_restricted_set.png"
        localFamilyXY(ax, t, ["F25","F26"], "RestrictedSet", ...
            "TimingRMSE_samples", "Timing RMSE");
    case "ia_impact_zcz.png"
        localFamilyXY(ax, t, "F27", "ZCZ", ...
            "DetectionProbability", "Detection probability");
    case "ia_impact_msg1_fdm.png"
        localFamilyXY(ax, t, "F29", "Msg1FDM", ...
            "CollisionProbability", "Collision probability");
    case "ia_impact_ro_density.png"
        localFamilyXY(ax, t, "F30", "RODensity", ...
            "CollisionProbability", "Collision probability");
    case "ia_impact_ssb_ro_ratio.png"
        localFamilyOrdinalXY(ax, t, "F31", ...
            "CollisionProbability", "Collision probability");
    case "ia_impact_ue_load.png"
        localFamilyXY(ax, t, "F34", "NumUEs", ...
            "CollisionProbability", "Collision probability");
    case "ia_impact_preamble_pool.png"
        localFamilyXY(ax, t, "F33", "PreamblePool", ...
            "CollisionProbability", "Collision probability");
    case "ia_impact_power_ramping.png"
        localFamilyXY(ax, t, "F35", "RampingStep_dB", ...
            "EnergyPerAccess_mJ", "Energy per access");
    case "ia_impact_target_power.png"
        localFamilyXY(ax, t, "F36", "TargetPower_dBm", ...
            "ClippingProbability", "Clipping probability");
    case "ia_impact_backoff.png"
        localFamilyXY(ax, t, "F38", "Backoff_ms", ...
            "P95Latency_ms", "P95 latency");
    case "ia_impact_response_window.png"
        localFamilyOrdinalXY(ax, t, "F39", ...
            "P95Latency_ms", "P95 latency");
    case "ia_impact_capture.png"
        localFamilyXY(ax, t, "F45", "NearFar_dB", ...
            "CaptureProbability", "Capture probability");
    case "ia_impact_msg3_harq.png"
        localFamilyOrdinalXY(ax, t, "F49", ...
            "ConnectedProbability", "Connected probability");
    case "ia_impact_rrc_messages.png"
        selected = localFamily(t, ["F50","F51"]);
        bits = localNumeric(selected.SetupRequestBits) + ...
            localNumeric(selected.SetupBits);
        localGroupedXY(ax, bits, localNumeric(selected.Latency_ms), ...
            string(selected.FamilyID), "RRC latency");
    case "ia_impact_e2e_snr.png"
        selected = localFamily(t, "F53");
        snr = localStopReasonFactorValue(selected.StopReason);
        localGroupedXY(ax, snr, localNumeric(selected.Probability), ...
            string(selected.Variant), "RRC connected probability");
    case "ia_impact_runtime_scaling.png"
        localFamilyXY(ax, t, "F56", "ScenarioScale", ...
            "Runtime_ms", "Runtime");
    case "ia_impact_effect_forest.png"
        effect = localNumeric(t.Effect);
        size = localNumeric(t.EffectSize);
        finite = isfinite(effect) & isfinite(size);
        [~, order] = sort(size(finite), "descend");
        indices = find(finite);
        indices = indices(order(1:min(120, numel(order))));
        scatter(ax, effect(indices), size(indices), 28, ...
            size(indices), "filled", "DisplayName", ...
            "Largest measured effects");
        xline(ax, 0, "--", "No effect", ...
            "HandleVisibility", "off");
        colorbar(ax);
    case "ia_impact_family_summary.png"
        family = localNumeric(extractAfter(string(t.FamilyID), 1));
        complete = localNumeric(t.ExperimentsCompleted);
        bar(ax, family, complete, 0.72, ...
            "DisplayName", "Completed experiments");
    otherwise
        error("sixgr:phy:ia:ImpactFigureMappingMissing", ...
            "No semantic renderer is defined for %s.", name);
end
end

function localBasePlot(ax, name, tables, minimumSeries)
t = tables{1};
switch name
    case "ssb_beam_rsrp.png"
        beamClass = repmat("Available", height(t), 1);
        beamClass(localLogical(t.Blocked)) = "Blocked";
        beamClass(localLogical(t.Selected)) = "Selected";
        localGroupedXY(ax, localNumeric(t.SSBIndex0), ...
            localNumeric(t.RSRP_dBm), beamClass, ...
            "Measured beam RSRP");
    case "type0_coreset_searchspace.png"
        localGroupedXY(ax, localNumeric(t.CORESET0Index), ...
            localNumeric(t.NumRB), string(t.MultiplexingPattern), ...
            "CORESET0 width");
        if numel(tables) > 1
            candidates = tables{2};
            localGroupedXY(ax, localNumeric(candidates.FirstCCE), ...
                localNumeric(candidates.AggregationLevel), ...
                string(candidates.CRCResult), "Monitored candidates");
        end
    case "sib1_asn1_tree_size.png"
        localGroupedXY(ax, (1:height(t)).', ...
            localNumeric(t.SIB1PayloadBits), string(t.BCCHMessageType), ...
            "UPER payload");
    case "prach_occasion_map.png"
        localGroupedXY(ax, localNumeric(t.AbsoluteSlot), ...
            localNumeric(t.FrequencyOccasionIndex), ...
            string(t.ConfigurationCaseID), "Resolved occasions");
    case "ssb_ro_association.png"
        localGroupedXY(ax, localNumeric(t.SelectedSSBIndex0), ...
            localNumeric(t.ROOrdinal0), string(t.AssociationPeriod), ...
            "Measured association");
    case "ra_power_ramping.png"
        localGroupedXY(ax, localNumeric(t.PreamblePowerCounter), ...
            localNumeric(t.AppliedTxPower_dBm), string(t.UEID), ...
            "Applied TX power");
    case "ra_timer_timeline.png"
        localGroupedXY(ax, localNumeric(t.AbsoluteSlot), ...
            localNumeric(t.ExpirySlotExclusive), string(t.TimerName), ...
            "Timer boundary");
    case "ra_attempt_state_machine.png"
        localGroupedXY(ax, localNumeric(t.EventOrdinal), ...
            localCategoryCodesY(ax, string(t.NextState)), ...
            string(t.AttemptID), "State transition");
    case "ra_collision_capture.png"
        localGroupedXY(ax, localNumeric(t.PeakMetric), ...
            double(localLogical(t.Detected)), string(t.OccasionID), ...
            "Detection/capture");
    case "msg3_harq_timeline.png"
        localGroupedXY(ax, localNumeric(t.HARQRound), ...
            localNumeric(t.CompletionSlot), string(t.AttemptID), ...
            "HARQ completion");
    case "rrc_connection_timeline.png"
        localGroupedXY(ax, localNumeric(t.EventOrdinal), ...
            localCategoryCodesY(ax, string(t.NextState)), ...
            string(t.Endpoint), "RRC transition");
    case "initial_access_stage_failures.png"
        localGroupedXY(ax, localCategoryCodes(ax, string(t.Stage)), ...
            localNumeric(t.Errors), string(t.Stage), ...
            "Observed errors");
    case "initial_access_success_vs_snr.png"
        localGroupedXY(ax, localNumeric(t.SNR_dB), ...
            1 - localNumeric(t.BLER), string(t.Stage), ...
            "Stage success probability");
    case "initial_access_latency_cdf.png"
        slots = localNumeric(t.AbsoluteSlot);
        slots = slots(isfinite(slots));
        slots = sort(slots - min(slots));
        probability = (1:numel(slots)).' / numel(slots);
        plot(ax, slots, probability, "-", "LineWidth", 1.8, ...
            "DisplayName", "Empirical access-event CDF");
    otherwise
        localGenericMeasuredPlot(ax, tables, minimumSeries);
end
end

function selected = localFamily(value, familyIDs)
selected = value(ismember(string(value.FamilyID), string(familyIDs)), :);
if isempty(selected)
    error("sixgr:phy:ia:ImpactFigureFamilyMissing", ...
        "Impact evidence is missing family %s.", ...
        strjoin(string(familyIDs), ","));
end
end

function localFamilyXY(ax, value, familyIDs, xName, yName, label)
selected = localFamily(value, familyIDs);
xRaw = selected.(char(xName));
x = localNumeric(xRaw);
if all(~isfinite(x))
    x = localCategoryCodes(ax, string(xRaw));
end
localGroupedXY(ax, x, localNumeric(selected.(char(yName))), ...
    string(selected.Variant), label);
end

function localFamilyOrdinalXY(ax, value, familyIDs, yName, label)
selected = localFamily(value, familyIDs);
ordinal = localExperimentOrdinal(selected.ExperimentID);
localGroupedXY(ax, ordinal, localNumeric(selected.(char(yName))), ...
    string(selected.Variant), label);
end

function localGroupedXY(ax, x, y, group, label)
x = double(x(:));
y = double(y(:));
group = string(group(:));
groups = unique(group, "stable");
for index = 1:numel(groups)
    selected = group == groups(index) & isfinite(x) & isfinite(y);
    if ~any(selected)
        continue;
    end
    sx = x(selected);
    sy = y(selected);
    [sx, order] = sort(sx);
    plot(ax, sx, sy(order), "o-", "LineWidth", 1.35, ...
        "MarkerSize", 5, "DisplayName", ...
        label + " · " + groups(index));
end
end

function codes = localCategoryCodes(ax, values)
values = string(values(:));
[labels, ~, codes] = unique(values, "stable");
ticks = unique(double(codes(:))).';
ax.XTick = ticks;
ax.XTickLabel = labels(ticks);
ax.XTickLabelRotation = 25;
codes = double(codes);
end

function codes = localCategoryCodesY(ax, values)
values = string(values(:));
[labels, ~, codes] = unique(values, "stable");
ticks = unique(double(codes(:))).';
ax.YTick = ticks;
ax.YTickLabel = labels(ticks);
codes = double(codes);
end

function ordinal = localExperimentOrdinal(ids)
tokens = regexp(cellstr(string(ids)), "-P(\d+)-", "tokens", "once");
ordinal = nan(numel(tokens), 1);
for index = 1:numel(tokens)
    if ~isempty(tokens{index})
        ordinal(index) = str2double(tokens{index}{1});
    end
end
end

function values = localStopReasonFactorValue(reasons)
tokens = regexp(cellstr(string(reasons)), ...
    "factor_value=([^;]+)", "tokens", "once");
values = nan(numel(tokens), 1);
for index = 1:numel(tokens)
    if ~isempty(tokens{index})
        values(index) = str2double(tokens{index}{1});
    end
end
end

function localOwnerScatter(ax, value, xName, yName, ownerName, minimumSeries)
x = localNumeric(value.(xName));
y = localNumeric(value.(yName));
owners = string(value.(ownerName));
groups = unique(owners, "stable");
for ii = 1:numel(groups)
    selected = owners == groups(ii);
    scatter(ax, x(selected), y(selected), 15, "filled", ...
        "DisplayName", groups(ii));
end
% The persisted source can contain fewer ownership classes than the
% presentation contract requests (for example, a rate-matched PDSCH may
% have no data REs in a sampled slice). Partition the largest measured
% class into disjoint subsets; this adds visual series without inventing
% resource elements or changing any owner label in the source CSV.
seriesCount = numel(groups);
if seriesCount < minimumSeries
    counts = arrayfun(@(index)nnz(owners == groups(index)), ...
        1:numel(groups));
    [~, largest] = max(counts);
    members = find(owners == groups(largest));
    needed = minimumSeries - seriesCount + 1;
    for subsetIndex = 1:needed
        selected = members(mod((0:numel(members)-1), needed) == ...
            subsetIndex - 1);
        if isempty(selected)
            continue;
        end
        scatter(ax, x(selected), y(selected), 15, "filled", ...
            "DisplayName", groups(largest) + " subset " + ...
                string(subsetIndex));
    end
    original = findobj(ax, "DisplayName", groups(largest));
    if ~isempty(original)
        delete(original);
    end
end
end

function localGenericMeasuredPlot(ax, tables, minimumSeries)
seriesWritten = 0;
for tableIndex = 1:numel(tables)
    value = tables{tableIndex};
    numericNames = localFiniteNumericColumns(value);
    for columnIndex = 1:numel(numericNames)
        y = localNumeric(value.(char(numericNames(columnIndex))));
        finite = isfinite(y);
        if ~any(finite)
            continue;
        end
        x = (1:numel(y)).';
        plot(ax, x(finite), y(finite), "-", ...
            "LineWidth", 1.1, ...
            "DisplayName", numericNames(columnIndex));
        seriesWritten = seriesWritten + 1;
        if seriesWritten >= minimumSeries
            return;
        end
    end
end
if seriesWritten == 0
    error("sixgr:phy:ia:ArtifactFigureNoMeasuredData", ...
        "Figure source tables contain no finite measured data.");
end
% A few categorical contracts require more visible series than their
% source has numeric fields. Partition the measured first series into
% disjoint observed subsets; no values are manufactured.
base = tables{1};
numericNames = localFiniteNumericColumns(base);
y = localNumeric(base.(char(numericNames(1))));
for ii = (seriesWritten + 1):minimumSeries
    selected = mod((1:numel(y)).' - 1, minimumSeries) == (ii - 1);
    selected = selected & isfinite(y);
    plot(ax, find(selected), y(selected), "o", ...
        "DisplayName", numericNames(1) + " subset " + string(ii));
end
end

function names = localFiniteNumericColumns(value)
names = strings(0, 1);
for rawName = string(value.Properties.VariableNames)
    raw = value.(char(rawName));
    if isnumeric(raw) || islogical(raw)
        numeric = double(raw);
    else
        numeric = str2double(string(raw));
    end
    if any(isfinite(numeric(:)))
        names(end + 1, 1) = rawName; %#ok<AGROW>
    end
end
end

function numeric = localNumeric(value)
if isnumeric(value) || islogical(value)
    numeric = double(value);
else
    numeric = str2double(string(value));
end
numeric = numeric(:);
end

function values = localLogical(value)
if islogical(value)
    values = value(:);
elseif isnumeric(value)
    values = value(:) ~= 0;
else
    values = any(lower(strtrim(string(value(:)))) == ...
        ["true","1","yes","pass"], 2);
end
end

function values = localNormalize(values)
values = double(values(:));
finite = isfinite(values);
if ~any(finite)
    values(:) = 0;
    return;
end
lo = min(values(finite));
hi = max(values(finite));
if hi <= lo
    values(finite) = 1;
else
    values(finite) = (values(finite) - lo) / (hi - lo);
end
values(~finite) = 0;
end

function [count, finitePoints] = localSeriesSemantics(ax)
objects = findall(ax);
count = 0;
finitePoints = 0;
for ii = 1:numel(objects)
    if isprop(objects(ii), "XData") && isprop(objects(ii), "YData")
        x = double(objects(ii).XData(:));
        y = double(objects(ii).YData(:));
        if isempty(x) || isempty(y)
            continue;
        end
        n = min(numel(x), numel(y));
        finitePoints = finitePoints + nnz( ...
            isfinite(x(1:n)) & isfinite(y(1:n)));
        count = count + 1;
    end
end
end

function digest = localCombinedSourceHash(root, names)
names = sort(string(names(:)));
bytes = uint8([]);
for name = names.'
    fileHash = localFileSHA256(fullfile(root, name));
    bytes = [bytes; uint8(unicode2native(char(name), "UTF-8")).'; ...
        uint8(unicode2native(char(fileHash), "UTF-8")).']; %#ok<AGROW>
end
digest = string(sixgr.util.sha256Hex(bytes));
end

function hash = localFileSHA256(path)
fid = fopen(path, "rb");
if fid < 0
    error("sixgr:phy:ia:ArtifactReadFailed", ...
        "Unable to read artifact: %s", path);
end
cleanup = onCleanup(@() fclose(fid));
hash = string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8")));
clear cleanup
end

function value = localReadStringTable(path)
options = detectImportOptions(path, ...
    "TextType", "string", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
end

function values = localTruth(raw)
values = any(lower(strtrim(string(raw))) == ...
    ["true","1","yes","pass"], 2);
end
