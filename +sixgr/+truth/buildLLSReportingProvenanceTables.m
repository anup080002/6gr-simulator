function tables = buildLLSReportingProvenanceTables(runFolder, currentTables, logicalPaths, contractRows, meta)
%BUILDLLSREPORTINGPROVENANCETABLES Build plot/report provenance artifacts.

tables = struct();
tables.plot_manifest = iBuildPlotManifestTable(runFolder);
tables.plot_render_status = iBuildPlotRenderStatusTable(tables.plot_manifest);
tables.chart_source_registry = iBuildChartSourceRegistryTable(tables.plot_manifest);
tables.plot_suppression_table = iBuildPlotSuppressionTable(tables.plot_manifest);
tables.unavailable_plot_card_registry = iBuildUnavailablePlotCardRegistryTable(tables.plot_manifest);
tables.plot_data_quality_table = iBuildPlotDataQualityTable(tables.plot_manifest);
tables.raw_to_derived_lineage = iBuildLineageTable(currentTables, logicalPaths, contractRows, meta);
tables.table_field_availability_matrix = iBuildFieldAvailabilityTable(currentTables, logicalPaths, contractRows, meta);
end

function T = iBuildPlotManifestTable(runFolder)
specs = iPlotSpecs();
rows = repmat(sixgr.visual.writePlotManifestRow("", "", "", "", "", "", struct()), 0, 1);
for i = 1:numel(specs)
    spec = specs(i);
    imagePath = fullfile(runFolder, char(spec.ImagePath));
    unavailableImagePath = char(sixgr.visual.unavailableArtifactPath(imagePath));
    sourceCsvPath = fullfile(runFolder, char(spec.SourceCSV));
    stats = struct("RowCount", NaN, "UniqueXCount", NaN, "UniqueYCount", NaN, "NonNaNYCount", NaN, ...
        "PlotType", spec.PlotType, "PlotRenderStatus", "not_rendered", "PlotSuppressionReason", "", ...
        "CountsAsRealPlot", false, "VisualValidity", "unavailable", "WarningBannerText", "");
    if exist(sourceCsvPath, "file") == 2
        try
            sourceT = readtable(sourceCsvPath, "VariableNamingRule", "preserve");
        catch
            sourceT = table();
        end
        stats = sixgr.visual.evaluateVisualArtifactContract(spec, sourceT);
    else
        sourceT = table();
        stats.PlotRenderStatus = "source_csv_missing";
        stats.PlotSuppressionReason = "source_csv_missing";
        stats.CountsAsRealPlot = false;
        stats.VisualValidity = "unavailable";
        stats.WarningBannerText = "";
    end
    imageExists = exist(imagePath, "file") == 2;
    unavailableImageExists = exist(unavailableImagePath, "file") == 2;
    isUnavailableCard = false;
    countsAsRealPlot = false;
    renderStatus = string(stats.PlotRenderStatus);
    suppressionReason = string(stats.PlotSuppressionReason);
    visualValidity = string(iStructField(stats, "VisualValidity", "unavailable"));
    warningBannerText = string(iStructField(stats, "WarningBannerText", ""));
    manifestImagePath = string(spec.ImagePath);
    if imageExists && renderStatus == "rendered"
        if visualValidity == "diagnostic_only"
            countsAsRealPlot = false;
            renderStatus = "rendered_diagnostic_plot";
            if strlength(warningBannerText) == 0
                warningBannerText = "DIAGNOSTIC ONLY - not counted as real LLS evidence";
            end
        else
            countsAsRealPlot = true;
            visualValidity = "real_lls_evidence";
            renderStatus = "rendered_real_plot";
        end
    elseif imageExists && renderStatus ~= "rendered"
        countsAsRealPlot = false;
        visualValidity = "invalid_stale";
        renderStatus = "invalid_stale_artifact";
        if strlength(suppressionReason) == 0
            suppressionReason = "stale_artifact_source_contract_failed";
        end
    elseif unavailableImageExists
        isUnavailableCard = true;
        renderStatus = "rendered_unavailable_card";
        visualValidity = "unavailable";
        manifestImagePath = sixgr.visual.unavailableArtifactPath(spec.ImagePath);
        if strlength(suppressionReason) == 0
            suppressionReason = "insufficient_source_data";
        end
    elseif renderStatus ~= "rendered"
        renderStatus = "suppressed";
        visualValidity = "unavailable";
    else
        renderStatus = "not_rendered";
        countsAsRealPlot = false;
    end
    artifactInfo = sixgr.visual.inspectVisualArtifactFile(fullfile(runFolder, char(manifestImagePath)));
    rows(end + 1, 1) = sixgr.visual.writePlotManifestRow( ... %#ok<AGROW>
        spec.PlotId, manifestImagePath, spec.SourceCSV, spec.SourceCSV, spec.XVariable, spec.YVariable, stats, ...
        "PlotType", spec.PlotType, ...
        "PlotRenderStatus", renderStatus, ...
        "PlotSuppressionReason", suppressionReason, ...
        "IsUnavailableCard", isUnavailableCard, ...
        "CountsAsRealPlot", countsAsRealPlot, ...
        "VisualValidity", visualValidity, ...
        "WarningBannerText", warningBannerText, ...
        "AggregationMethod", spec.AggregationMethod, ...
        "RawRowCount", double(height(sourceT)), ...
        "AggregatedRowCount", double(height(sourceT)), ...
        "DuplicateRowCount", double(iDuplicateRowCount(sourceT)), ...
        "ActualMimeType", artifactInfo.actual_mime_type, ...
        "DeclaredMimeType", artifactInfo.declared_mime_type, ...
        "Extension", artifactInfo.extension, ...
        "SHA256", artifactInfo.sha256, ...
        "ByteCount", artifactInfo.byte_count);
end
T = struct2table(rows);
end

function T = iBuildPlotRenderStatusTable(manifestT)
if ~(istable(manifestT) && ~isempty(manifestT))
    T = table();
    return;
end
T = manifestT(:, intersect(["PlotId","ImagePath","PlotRenderStatus","PlotSuppressionReason","IsUnavailableCard","CountsAsRealPlot","VisualValidity","WarningBannerText", ...
    "actual_mime_type","declared_mime_type","extension","sha256","byte_count"], string(manifestT.Properties.VariableNames), 'stable'));
end

function T = iBuildChartSourceRegistryTable(manifestT)
if ~(istable(manifestT) && ~isempty(manifestT))
    T = table();
    return;
end
T = table( ...
    string(manifestT.PlotId), string(manifestT.SourceCSV), string(manifestT.SourceTable), ...
    repmat("sixgr.truth.buildLLSReportingProvenanceTables", height(manifestT), 1), ...
    repmat("+sixgr/+truth/buildLLSReportingProvenanceTables.m", height(manifestT), 1), ...
    repmat("plot_source_csv", height(manifestT), 1), ...
    string(manifestT.XVariable), string(manifestT.YVariables), string(manifestT.PlotRenderStatus), string(manifestT.VisualValidity), ...
    'VariableNames', ["PlotId","SourceCSV","SourceTable","SourceFunction","SourceMATLABFile","RuntimeEvidenceStatus","XVariable","YVariables","DerivationStatus","VisualValidity"]);
end

function T = iBuildPlotSuppressionTable(manifestT)
if ~(istable(manifestT) && ~isempty(manifestT))
    T = table();
    return;
end
mask = string(manifestT.PlotRenderStatus) ~= "rendered_real_plot";
T = manifestT(mask, intersect(["PlotId","ImagePath","PlotRenderStatus","PlotSuppressionReason","IsUnavailableCard","VisualValidity","WarningBannerText"], string(manifestT.Properties.VariableNames), 'stable'));
end

function T = iBuildUnavailablePlotCardRegistryTable(manifestT)
if ~(istable(manifestT) && ~isempty(manifestT))
    T = table();
    return;
end
mask = logical(manifestT.IsUnavailableCard);
T = manifestT(mask, intersect(["PlotId","ImagePath","SourceCSV","PlotSuppressionReason","VisualValidity"], string(manifestT.Properties.VariableNames), 'stable'));
end

function T = iBuildPlotDataQualityTable(manifestT)
if ~(istable(manifestT) && ~isempty(manifestT))
    T = table();
    return;
end
T = manifestT(:, intersect(["PlotId","SourceCSV","RowCount","UniqueXCount","UniqueYCount","NonNaNYCount","PlotType","PlotRenderStatus","CountsAsRealPlot","VisualValidity"], string(manifestT.Properties.VariableNames), 'stable'));
end

function T = iBuildLineageTable(currentTables, logicalPaths, contractRows, meta)
rows = repmat(struct("OutputId", "", "SourceFunction", "", "SourceMATLABFile", "", "SourceRuntimeObject", "", "SourceTable", "", ...
    "SourceColumn", "", "DerivedTable", "", "DerivedColumn", "", "TransformType", "", "TransformDescription", "", ...
    "RuntimeEvidenceStatus", "", "DerivationStatus", "", "run_id", meta.run_id), 0, 1);
fieldNames = fieldnames(logicalPaths);
for i = 1:numel(fieldNames)
    fieldName = string(fieldNames{i});
    logicalPath = string(logicalPaths.(fieldNames{i}));
    Tref = iTable(currentTables, fieldName);
    if ~(istable(Tref) && ~isempty(Tref))
        continue;
    end
    [~, nm] = fileparts(char(logicalPath));
    outputId = string(nm);
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "OutputId", outputId, ...
        "SourceFunction", iColumnScalarText(Tref, ["producer_module"]), ...
        "SourceMATLABFile", iColumnScalarText(Tref, ["producer_module"]), ...
        "SourceRuntimeObject", iColumnScalarText(Tref, ["runtime_evidence"]), ...
        "SourceTable", iColumnScalarText(Tref, ["source_artifact_ref"]), ...
        "SourceColumn", "", ...
        "DerivedTable", logicalPath, ...
        "DerivedColumn", "", ...
        "TransformType", iIf(any(contractRows.OutputId == outputId & string(contractRows.OutputKind) == "table"), "derived_table", "derived_artifact"), ...
        "TransformDescription", "LLS public output extracted from persisted runtime-backed tables.", ...
        "RuntimeEvidenceStatus", iIf(height(Tref) > 0, "published", "not_published"), ...
        "DerivationStatus", iIf(height(Tref) > 0, "derived", "missing"), ...
        "run_id", meta.run_id);
end
T = struct2table(rows);
end

function T = iBuildFieldAvailabilityTable(currentTables, logicalPaths, contractRows, meta)
rows = repmat(struct("OutputId", "", "FieldName", "", "RequiredFlag", false, "PresentFlag", false, "AllNaNFlag", false, ...
    "LogicalPath", "", "PresentNonNaNCount", NaN, "TotalRowCount", NaN, "AvailabilityStatus", "", "run_id", meta.run_id), 0, 1);
for i = 1:height(contractRows)
    outputId = string(contractRows.OutputId(i));
    [fieldName, logicalPath] = iFieldForOutputId(logicalPaths, outputId);
    Tref = iTable(currentTables, fieldName);
    requiredColumns = split(string(contractRows.RequiredColumns(i)), "|");
    requiredColumns = requiredColumns(strlength(requiredColumns) > 0);
    for j = 1:numel(requiredColumns)
        column = strtrim(requiredColumns(j));
        present = istable(Tref) && ismember(column, string(Tref.Properties.VariableNames));
        nonNaNCount = 0;
        allNaNFlag = false;
        if present
            vals = Tref.(column);
            if isnumeric(vals)
                nonNaNCount = sum(isfinite(double(vals)));
                allNaNFlag = nonNaNCount == 0;
            else
                txt = strtrim(string(vals));
                nonNaNCount = sum(strlength(txt) > 0 & txt ~= "<missing>" & lower(txt) ~= "nan");
                allNaNFlag = nonNaNCount == 0;
            end
        end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "OutputId", outputId, "FieldName", column, "RequiredFlag", true, "PresentFlag", present, ...
            "AllNaNFlag", allNaNFlag, "LogicalPath", logicalPath, "PresentNonNaNCount", double(nonNaNCount), ...
            "TotalRowCount", double(iIf(istable(Tref), height(Tref), 0)), ...
            "AvailabilityStatus", iAvailabilityStatus(present, allNaNFlag), "run_id", meta.run_id);
    end
end
T = struct2table(rows);
end

function [fieldName, logicalPath] = iFieldForOutputId(logicalPaths, outputId)
fieldNames = fieldnames(logicalPaths);
fieldName = "";
logicalPath = "";
for i = 1:numel(fieldNames)
    path = string(logicalPaths.(fieldNames{i}));
    [~, nm] = fileparts(char(path));
    if string(nm) == outputId
        fieldName = string(fieldNames{i});
        logicalPath = path;
        return;
    end
end
end

function status = iAvailabilityStatus(present, allNaNFlag)
if ~present
    status = "missing_field";
elseif allNaNFlag
    status = "present_all_nan";
else
    status = "present_with_values";
end
end

function value = iColumnScalarText(T, names)
value = "";
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(T.Properties.VariableNames)) && ~isempty(T.(name))
        value = string(T.(name)(1));
        return;
    end
end
end

function count = iDuplicateRowCount(T)
count = 0;
if ~(istable(T) && ~isempty(T))
    return;
end
try
    count = height(T) - height(unique(T, "rows"));
catch
    count = 0;
end
end

function value = iStructField(s, name, fallback)
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = fallback;
end
end

function values = iResolveColumn(T, columnName)
values = [];
if ~(istable(T) && ~isempty(T))
    return;
end
if strlength(string(columnName)) == 0
    values = (1:height(T)).';
    return;
end
if ismember(string(columnName), string(T.Properties.VariableNames))
    raw = T.(string(columnName));
    try
        values = double(raw);
    catch
        values = str2double(string(raw));
    end
else
    values = [];
end
end

function T = iTable(S, name)
if isstruct(S) && isfield(S, char(name))
    T = S.(char(name));
else
    T = table();
end
end

function specs = iPlotSpecs()
contractSpecs = sixgr.visual.loadVisualArtifactContract();
if ~isempty(contractSpecs)
    specs = contractSpecs;
    return;
end
specs = [ ...
    iSpec("bler_vs_snr", "reports/image/bler_vs_snr.png", "reports/csv/bler_vs_snr.csv", "SNR_dB", "MetricValue", "relation", "none"), ...
    iSpec("throughput_vs_snr", "reports/image/throughput_vs_snr.png", "reports/csv/throughput_vs_snr.csv", "SNR_dB", "MetricValue", "relation", "none"), ...
    iSpec("nmse_vs_snr", "reports/image/nmse_vs_snr.png", "reports/csv/nmse_vs_snr.csv", "SNR_dB", "MetricValue", "relation", "none"), ...
    iSpec("bler_vs_sinr", "reports/image/bler_vs_sinr.png", "reports/csv/bler_vs_sinr.csv", "XValue", "YValue", "relation", "none"), ...
    iSpec("ber_vs_sinr", "reports/image/ber_vs_sinr.png", "reports/csv/ber_vs_sinr.csv", "XValue", "YValue", "relation", "none"), ...
    iSpec("ber_vs_bler", "reports/image/ber_vs_bler.png", "reports/csv/ber_vs_bler.csv", "XValue", "YValue", "relation", "none"), ...
    iSpec("ber_vs_ecno", "reports/image/ber_vs_ecno.png", "reports/csv/ber_vs_ecno.csv", "XValue", "YValue", "relation", "none"), ...
    iSpec("bler_vs_ecno", "reports/image/bler_vs_ecno.png", "reports/csv/bler_vs_ecno.csv", "XValue", "YValue", "relation", "none"), ...
    iSpec("control_pass_rates", "reports/image/control_pass_rates.png", "reports/csv/control_pass_rates.csv", "Entity", "PassRate", "summary", "entity_summary"), ...
    iSpec("metric_coverage_by_category", "reports/image/metric_coverage_by_category.png", "reports/csv/metric_coverage_by_category.csv", "CategoryCode", "MetricCount", "summary", "category_rollup"), ...
    iSpec("gains_losses_waterfall", "reports/image/gains_losses_waterfall.png", "reports/csv/per_scenario_summary_tables.csv", "ScenarioID", "DL_Throughput_Mbps_mean", "summary", "single_row_summary"), ...
    iSpec("papr_ccdf", "reports/image/papr_ccdf.png", "reports/csv/papr_ccdf.csv", "PAPR_dB", "CCDF", "cdf", "runtime_samples"), ...
    iSpec("latency_cdf", "reports/image/latency_cdf.png", "reports/csv/latency_cdf_plot.csv", "latency_ms", "cdf_probability", "cdf", "empirical_cdf"), ...
    iSpec("access_delay_cdf", "reports/image/access_delay_cdf.png", "control/csv/initial_access_lifecycle_trace.csv", "ProcedureDelay_ms", "ProcedureDelay_ms", "cdf", "empirical_cdf"), ...
    iSpec("energy_vs_throughput", "reports/image/energy_vs_throughput.png", "reports/csv/energy_vs_throughput.csv", "successful_bits", "energy_j", "relation", "runtime_pairs"), ...
    iSpec("complexity_vs_gain", "reports/image/complexity_vs_gain.png", "reports/csv/complexity_vs_gain.csv", "DecoderComplexityUnits", "PostEqSINR_dB", "relation", "runtime_pairs"), ...
    iSpec("heatmap_band_feature_kpi", "reports/image/heatmap_band_feature_kpi.png", "reports/csv/heatmap_band_feature_kpi.csv", "Feature", "KPIValue", "heatmap", "summary_heatmap"), ...
    iSpec("heatmap_impairment_kpi", "reports/image/heatmap_impairment_kpi.png", "reports/csv/heatmap_impairment_kpi.csv", "Feature", "KPIValue", "heatmap", "summary_heatmap"), ...
    iSpec("heatmap_beam_rank_trp_kpi", "reports/image/heatmap_beam_rank_trp_kpi.png", "reports/csv/heatmap_beam_rank_trp_kpi.csv", "Feature", "KPIValue", "heatmap", "summary_heatmap"), ...
    iSpec("equalized_constellations", "reports/image/equalized_constellations.png", "reports/csv/equalized_constellations.csv", "equalized_i", "equalized_q", "scatter", "runtime_constellation_by_direction_modulation_layer_snr"), ...
    iSpec("llr_histograms", "reports/image/llr_histograms.png", "reports/csv/llr_histograms.csv", "BinStart", "Count", "histogram", "binned_summary"), ...
    iSpec("cfo_to_tracking_traces", "reports/image/cfo_to_tracking_traces.png", "reports/csv/cfo_to_tracking_traces.csv", "Frame", "ResidualCFO_PostCorrection_Hz", "trace", "runtime_trace"), ...
    iSpec("prach_correlation_traces", "reports/image/prach_correlation_traces.png", "reports/csv/prach_correlation_trace.csv", "lag_samples", "correlation_abs", "trace", "runtime_prach_lag_correlation_trace"), ...
    iSpec("ai_confidence_trace", "reports/image/ai_confidence_trace.png", "reports/csv/ai_confidence_trace.csv", "InvocationIndex", "ConfidenceScore", "trace", "runtime_trace"), ...
    iSpec("prb_allocation_heatmap", "reports/image/prb_allocation_heatmap.png", "reports/csv/prb_allocation_heatmap.csv", "slot", "occupancy_count", "heatmap", "aggregated_heatmap"), ...
    iSpec("power_energy_cumulative", "reports/image/power_energy_cumulative.png", "rf/csv/power_energy_table.csv", "timestamp_sim_ms", "cumulative_energy_J", "trace", "runtime_trace") ...
    ];
end

function spec = iSpec(plotId, imagePath, sourceCsv, xVariable, yVariable, plotType, aggregationMethod)
spec = struct("PlotId", string(plotId), "ImagePath", string(imagePath), "SourceCSV", string(sourceCsv), ...
    "FilePath", string(imagePath), ...
    "RequiredColumns", [string(xVariable); string(yVariable)], ...
    "XVariable", string(xVariable), "YVariable", string(yVariable), ...
    "XSemantics", "", "YSemantics", "", "Units", "", ...
    "MinRows", 2, "MinUniqueX", 1, "MinUniqueY", 1, ...
    "AllowedTruthStatus", "real_lls_evidence", "AllowedCurveConstruction", string(aggregationMethod), ...
    "PlotType", string(plotType), "PlotKind", string(plotType), ...
    "LLSValidity", "real_lls_evidence", ...
    "AggregationMethod", string(aggregationMethod));
end

function out = iIf(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
