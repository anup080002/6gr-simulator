function ok = testLLSPlotDataValidation()
%TESTLLSPLOTDATAVALIDATION Guard honest plot gating for LLS reporting.

setup6GRSimToolkit("Verbose", false);

status = sixgr.visual.validatePlotData("relation", [0; 0], [1; 2]);
assert(strcmp(string(status.PlotRenderStatus), "suppressed") && strcmp(string(status.PlotSuppressionReason), "insufficient_unique_x"), ...
    "One-point relation plots must be suppressed instead of rendered as a misleading vs-curve.");

status = sixgr.visual.validatePlotData("trace", 1, 5);
assert(strcmp(string(status.PlotRenderStatus), "suppressed") && strcmp(string(status.PlotSuppressionReason), "insufficient_rows"), ...
    "One-row traces must be suppressed instead of rendered as timelines.");

status = sixgr.visual.validatePlotData("line", [1; 1; 2; 2], [10; 11; 12; 13], "XColumnName", "Frame");
assert(strcmp(string(status.PlotRenderStatus), "suppressed") && strcmp(string(status.PlotSuppressionReason), "insufficient_unique_frame_x_for_line_plot"), ...
    "Frame-based line plots with fewer than three unique x values must be suppressed.");

status = sixgr.visual.validatePlotData("line", [1; 2; 3], [10; 11; 12], "XColumnName", "Frame");
assert(strcmp(string(status.PlotRenderStatus), "rendered"), ...
    "Line plots with at least three monotonic finite frame values may render.");

status = sixgr.visual.validatePlotData("cdf", (1:3).', [NaN; NaN; NaN]);
assert(strcmp(string(status.PlotRenderStatus), "suppressed"), ...
    "All-NaN CDF sources must be suppressed.");

status = sixgr.visual.validatePlotData("relation", [0; 1; 2], [10; 12; 13]);
assert(strcmp(string(status.PlotRenderStatus), "rendered") && logical(status.CountsAsRealPlot), ...
    "Valid multi-point relation plots must remain renderable.");

status = sixgr.visual.validatePlotData("relation", [0; 1; 2], [10; 12; 13], "LLSValidity", "diagnostic_only");
assert(strcmp(string(status.VisualValidity), "diagnostic_only") && ~logical(status.CountsAsRealPlot) && strlength(string(status.WarningBannerText)) > 0, ...
    "Diagnostic-only plots must render with a warning and must not count as real LLS evidence.");

row = sixgr.visual.writePlotManifestRow( ...
    "unit_plot", "reports/image/unit_plot.png", "reports/csv/unit_plot.csv", "reports/csv/unit_plot.csv", ...
    "SNR_dB", "MetricValue", status, ...
    "PlotType", "relation", ...
    "PlotRenderStatus", status.PlotRenderStatus, ...
    "PlotSuppressionReason", status.PlotSuppressionReason, ...
    "CountsAsRealPlot", true, ...
    "AggregationMethod", "none");
assert(strcmp(string(row.SourceCSV), "reports/csv/unit_plot.csv") && strcmp(string(row.PlotId), "unit_plot"), ...
    "Plot manifest rows must retain direct source-CSV provenance.");
assert(ismember("VisualValidity", string(fieldnames(row))) && strcmp(string(row.VisualValidity), "diagnostic_only"), ...
    "Plot manifest rows must carry visual validity.");
assert(all(ismember(["actual_mime_type","declared_mime_type","extension","sha256","byte_count"], string(fieldnames(row)))), ...
    "Plot manifest rows must carry file-signature metadata fields.");

contracts = sixgr.visual.loadVisualArtifactContract();
assert(~isempty(contracts) && all(ismember(["PlotId","ImagePath","SourceCSV","RequiredColumns","MinRows","MinUniqueX","MinUniqueY","LLSValidity"], string(fieldnames(contracts)))), ...
    "Canonical visual artifact contract must load with required schema fields.");

tmpCleanup = string(tempname);
cleanupTmpCleanup = onCleanup(@() localRemoveFolder(tmpCleanup)); %#ok<NASGU>
mkdir(fullfile(tmpCleanup, "reports", "image"));
localWriteBytes(fullfile(tmpCleanup, "reports", "image", "old_stale.png"), uint8([137 80 78 71 13 10 26 10]));
cleanupReport = sixgr.visual.clearRunImageDirectories(tmpCleanup);
assert(exist(fullfile(tmpCleanup, "reports", "image", "old_stale.png"), "file") ~= 2 && ...
    istable(cleanupReport) && any(logical(cleanupReport.Cleared)), ...
    "Run-start visual cleanup must clear stale image directory contents.");

tmp = string(tempname);
cleanupTmp = onCleanup(@() localRemoveFolder(tmp)); %#ok<NASGU>
mkdir(fullfile(tmp, "reports", "csv"));
mkdir(fullfile(tmp, "reports", "image"));

diagnosticCsv = fullfile(tmp, "reports", "csv", "bler_vs_sinr.csv");
diagnosticT = table(["DL";"DL";"DL"], [1; 2; 3], [0.10; 0.20; 0.30], ...
    'VariableNames', ["Direction","XValue","YValue"]);
writetable(diagnosticT, diagnosticCsv);
fig = figure("Visible", "off", "Color", "w");
cleanupFig = onCleanup(@() close(fig)); %#ok<NASGU>
plot([1 2 3], [0.10 0.20 0.30]);
sixgr.util.exportFigureArtifact(fig, fullfile(tmp, "reports", "image", "bler_vs_sinr.png"));
clear cleanupFig;
prov = sixgr.truth.buildLLSReportingProvenanceTables(tmp, struct(), struct(), table(), struct("run_id", 0));
diagRow = prov.plot_manifest(strcmp(string(prov.plot_manifest.PlotId), "bler_vs_sinr"), :);
assert(~isempty(diagRow) && strcmp(string(diagRow.PlotRenderStatus), "rendered_diagnostic_plot") && ...
    strcmp(string(diagRow.VisualValidity), "diagnostic_only") && ~logical(diagRow.CountsAsRealPlot) && ...
    strlength(string(diagRow.WarningBannerText)) > 0, ...
    "Rendered non-real plots must be diagnostic-only and disclose their warning banner.");
assert(ismember("actual_mime_type", string(prov.plot_manifest.Properties.VariableNames)) && ...
    double(diagRow.byte_count) > 0 && strcmp(string(diagRow.actual_mime_type), "image/png"), ...
    "Rendered plot manifest rows must include actual byte-level MIME evidence.");

latencyCsv = fullfile(tmp, "reports", "csv", "latency_cdf_plot.csv");
writetable(table(1, 1, 'VariableNames', ["latency_ms","cdf_probability"]), latencyCsv);
stalePng = fullfile(tmp, "reports", "image", "latency_cdf.png");
fid = fopen(stalePng, "w");
fprintf(fid, "stale");
fclose(fid);
sixgr.visual.enforceVisualArtifactContract(tmp, "StrictMode", true, "CreateUnavailableCards", true);
unavailableSvg = fullfile(tmp, "reports", "image", "latency_cdf_unavailable.svg");
assert(exist(stalePng, "file") ~= 2 && exist(unavailableSvg, "file") == 2, ...
    "Suppressed plots must not leave normal PNG artifacts in strict mode.");

tmpConst = string(tempname);
cleanupTmpConst = onCleanup(@() localRemoveFolder(tmpConst)); %#ok<NASGU>
mkdir(fullfile(tmpConst, "reports", "csv"));
mkdir(fullfile(tmpConst, "reports", "image"));
constCsv = fullfile(tmpConst, "reports", "csv", "equalized_constellations.csv");
writetable(table([0; 1; 0], [0; 0; 1], ...
    'VariableNames', ["EqualizedReal","EqualizedImag"]), constCsv);
staleConstPng = fullfile(tmpConst, "reports", "image", "equalized_constellations.png");
localWriteBytes(staleConstPng, uint8([137 80 78 71 13 10 26 10 9 9 9 9]));
sixgr.visual.enforceVisualArtifactContract(tmpConst, "StrictMode", true, "CreateUnavailableCards", true);
constUnavailableSvg = fullfile(tmpConst, "reports", "image", "equalized_constellations_unavailable.svg");
assert(exist(staleConstPng, "file") ~= 2 && exist(constUnavailableSvg, "file") == 2, ...
    "Constellation plots must be suppressed when modulation/layer/SNR lineage is missing.");

prov = sixgr.truth.buildLLSReportingProvenanceTables(tmp, struct(), struct(), table(), struct("run_id", 0));
latencyRow = prov.plot_manifest(strcmp(string(prov.plot_manifest.PlotId), "latency_cdf"), :);
assert(~isempty(latencyRow) && strcmp(string(latencyRow.PlotRenderStatus), "rendered_unavailable_card") && ...
    strcmp(string(latencyRow.VisualValidity), "unavailable") && logical(latencyRow.IsUnavailableCard) && ...
    endsWith(string(latencyRow.ImagePath), "_unavailable.svg"), ...
    "Unavailable cards must be explicit SVG artifacts with no stale normal image.");

tmpIntegrity = string(tempname);
cleanupTmpIntegrity = onCleanup(@() localRemoveFolder(tmpIntegrity)); %#ok<NASGU>
mkdir(fullfile(tmpIntegrity, "reports", "image"));
pngAsSvg = fullfile(tmpIntegrity, "reports", "image", "png_bytes.svg");
localWriteBytes(pngAsSvg, uint8([137 80 78 71 13 10 26 10 0 0 0 0]));
pngAsSvgInfo = sixgr.visual.inspectVisualArtifactFile(pngAsSvg);
assert(strcmp(string(pngAsSvgInfo.actual_mime_type), "image/png") && ~logical(pngAsSvgInfo.extension_mime_match), ...
    "A .svg artifact containing PNG bytes must be detected as a MIME mismatch.");
pngAsSvgRow = sixgr.visual.writePlotManifestRow( ...
    "png_bytes_svg", "reports/image/png_bytes.svg", "reports/csv/source.csv", "reports/csv/source.csv", ...
    "x", "y", struct("RowCount", 3, "UniqueXCount", 3, "UniqueYCount", 3, "NonNaNYCount", 3), ...
    "PlotType", "relation", "PlotRenderStatus", "rendered_real_plot", ...
    "CountsAsRealPlot", true, "VisualValidity", "real_lls_evidence");
integrityT = sixgr.visual.verifyVisualArtifacts(tmpIntegrity, struct2table(pngAsSvgRow));
assert(any(~logical(integrityT.IntegrityOk) & string(integrityT.FailureCode) == "extension_mime_mismatch"), ...
    "The visual artifact verifier must fail PNG bytes written with a .svg extension.");

tmpStale = string(tempname);
cleanupTmpStale = onCleanup(@() localRemoveFolder(tmpStale)); %#ok<NASGU>
mkdir(fullfile(tmpStale, "reports", "image"));
staleSuppressedPng = fullfile(tmpStale, "reports", "image", "latency_cdf.png");
localWriteBytes(staleSuppressedPng, uint8([137 80 78 71 13 10 26 10 1 2 3 4]));
suppressedRow = sixgr.visual.writePlotManifestRow( ...
    "latency_cdf", "reports/image/latency_cdf.png", "reports/csv/latency_cdf_plot.csv", "reports/csv/latency_cdf_plot.csv", ...
    "latency_ms", "cdf_probability", struct("RowCount", 1, "UniqueXCount", 1, "UniqueYCount", 1, "NonNaNYCount", 1), ...
    "PlotType", "cdf", "PlotRenderStatus", "suppressed", ...
    "PlotSuppressionReason", "insufficient_rows", "CountsAsRealPlot", false, "VisualValidity", "unavailable");
staleIntegrityT = sixgr.visual.verifyVisualArtifacts(tmpStale, struct2table(suppressedRow));
assert(any(~logical(staleIntegrityT.IntegrityOk) & string(staleIntegrityT.FailureCode) == "stale_suppressed_normal_artifact"), ...
    "A suppressed plot must fail visual integrity if a normal PNG artifact still exists.");

tmpCard = string(tempname);
cleanupTmpCard = onCleanup(@() localRemoveFolder(tmpCard)); %#ok<NASGU>
mkdir(fullfile(tmpCard, "reports", "image"));
sixgr.visual.writeUnavailablePlotCard(fullfile(tmpCard, "reports", "image", "good_card.png"), "good_card", "not enough runtime evidence");
goodCardPath = fullfile(tmpCard, "reports", "image", "good_card_unavailable.svg");
goodCardInfo = sixgr.visual.inspectVisualArtifactFile(goodCardPath);
assert(exist(goodCardPath, "file") == 2 && strcmp(string(goodCardInfo.actual_mime_type), "image/svg+xml"), ...
    "Unavailable cards must be written as real SVG XML artifacts ending _unavailable.svg.");
badCardPath = fullfile(tmpCard, "reports", "image", "bad_card.svg");
localWriteText(badCardPath, "<svg xmlns=""http://www.w3.org/2000/svg""><text>Unavailable</text></svg>");
badCardRow = sixgr.visual.writePlotManifestRow( ...
    "bad_card", "reports/image/bad_card.svg", "reports/csv/source.csv", "reports/csv/source.csv", ...
    "x", "y", struct("RowCount", 0, "UniqueXCount", 0, "UniqueYCount", 0, "NonNaNYCount", 0), ...
    "PlotType", "card", "PlotRenderStatus", "rendered_unavailable_card", ...
    "IsUnavailableCard", true, "CountsAsRealPlot", false, "VisualValidity", "unavailable");
badCardIntegrityT = sixgr.visual.verifyVisualArtifacts(tmpCard, struct2table(badCardRow));
assert(any(~logical(badCardIntegrityT.IntegrityOk) & string(badCardIntegrityT.FailureCode) == "bad_unavailable_card_name"), ...
    "Unavailable cards must fail integrity unless the artifact name ends with _unavailable.svg.");

tmpSNR = string(tempname);
cleanupTmpSNR = onCleanup(@() localRemoveFolder(tmpSNR)); %#ok<NASGU>
mkdir(fullfile(tmpSNR, "air_interface", "csv"));
mkdir(fullfile(tmpSNR, "reports", "image"));
writetable(localEmptyControlledSNRSweepTable(), fullfile(tmpSNR, "air_interface", "csv", "lls_snr_sweep.csv"));
snrPng = fullfile(tmpSNR, "reports", "image", "bler_vs_snr.png");
fig = figure("Visible", "off", "Color", "w");
cleanupFig = onCleanup(@() close(fig)); %#ok<NASGU>
plot([0 1 2], [0.8 0.5 0.2]);
sixgr.util.exportFigureArtifact(fig, snrPng);
clear cleanupFig;
snrUnavailable = fullfile(tmpSNR, "reports", "image", "bler_vs_snr_unavailable.svg");
assert(exist(snrPng, "file") ~= 2 && exist(snrUnavailable, "file") == 2, ...
    "An empty controlled SNR sweep must not produce a normal BLER-vs-SNR PNG.");

ok = true;
end

function T = localEmptyControlledSNRSweepTable()
T = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), false(0,1), strings(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', ["direction","snr_db","noise_variance","n_tb","n_crc_fail","bler","bler_ci_low", ...
    "bler_ci_high","n_bits","n_bit_errors","ber","throughput_mbps","goodput_mbps","mcs_index", ...
    "mcs_table","cqi_table","modulation_order","code_rate","tbs","n_layers","rv_sequence", ...
    "harq_enabled","channel_model","seed","truth_status"]);
end

function localRemoveFolder(path)
try
    if exist(path, "dir") == 7
        rmdir(path, "s");
    end
catch
end
end

function localWriteBytes(filePath, data)
sixgr.util.ensureFolder(fileparts(char(string(filePath))));
fid = fopen(filePath, "w");
assert(fid >= 0, "Failed to create visual byte fixture.");
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8(data), "uint8");
end

function localWriteText(filePath, textValue)
sixgr.util.ensureFolder(fileparts(char(string(filePath))));
fid = fopen(filePath, "w");
assert(fid >= 0, "Failed to create visual text fixture.");
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", char(string(textValue)));
end
