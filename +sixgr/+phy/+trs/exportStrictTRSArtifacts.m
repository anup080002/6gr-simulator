function manifest = exportStrictTRSArtifacts(runFolder, result)
%EXPORTSTRICTTRSARTIFACTS Persist strict TRS evidence artifacts.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
refCsvDir = fullfile(runFolder, "reference_signals", "csv");
controlCsvDir = layout.ControlCSVDir;
reportCsvDir = layout.ReportCSVDir;
jsonDir = fullfile(layout.ReportDir, "json");
textDir = fullfile(layout.ReportDir, "text");
binaryDir = fullfile(layout.ReportDir, "binary");
figDir = fullfile(layout.ReportDir, "figures");
sixgr.util.ensureFolder(refCsvDir);
sixgr.util.ensureFolder(controlCsvDir);
sixgr.util.ensureFolder(reportCsvDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(textDir);
sixgr.util.ensureFolder(binaryDir);
sixgr.util.ensureFolder(figDir);

tables = result.ArtifactTables;
tables.trs_resource_grid_power = localGridEvidence(result.PositiveGrid);
csvMap = struct( ...
    "trs_config_strict", fullfile(refCsvDir, "trs_config_strict.csv"), ...
    "trs_trials", fullfile(refCsvDir, "trs_trials.csv"), ...
    "trs_resource_mapping", fullfile(refCsvDir, "trs_resource_mapping.csv"), ...
    "trs_resource_grid_power", fullfile(refCsvDir, "trs_resource_grid_power.csv"), ...
    "trs_detection_metrics", fullfile(refCsvDir, "trs_detection_metrics.csv"), ...
    "trs_timing_tracking", fullfile(refCsvDir, "trs_timing_tracking.csv"), ...
    "trs_frequency_tracking", fullfile(refCsvDir, "trs_frequency_tracking.csv"), ...
    "trs_channel_estimation", fullfile(refCsvDir, "trs_channel_estimation.csv"), ...
    "trs_coverage", fullfile(refCsvDir, "trs_coverage.csv"), ...
    "trs_negative_trials", fullfile(refCsvDir, "trs_negative_trials.csv"), ...
    "trs_low_snr_sweep", fullfile(refCsvDir, "trs_low_snr_sweep.csv"), ...
    "trs_timing_offset_sweep", fullfile(refCsvDir, "trs_timing_offset_sweep.csv"), ...
    "trs_frequency_offset_sweep", fullfile(refCsvDir, "trs_frequency_offset_sweep.csv"), ...
    "trs_oracle_guard", fullfile(refCsvDir, "trs_oracle_guard.csv"), ...
    "trs_tracking_summary", fullfile(refCsvDir, "trs_tracking_summary.csv"));
names = string(fieldnames(csvMap));
compatMap = struct( ...
    "trs_config_strict_control", fullfile(controlCsvDir, "trs_config_strict.csv"), ...
    "trs_trials_control", fullfile(controlCsvDir, "trs_trials.csv"), ...
    "trs_tracking_summary_control", fullfile(controlCsvDir, "trs_tracking_summary.csv"), ...
    "trs_config_strict_reports", fullfile(reportCsvDir, "trs_config_strict.csv"), ...
    "trs_trials_reports", fullfile(reportCsvDir, "trs_trials.csv"), ...
    "trs_tracking_summary_reports", fullfile(reportCsvDir, "trs_tracking_summary.csv"));
compatNames = string(fieldnames(compatMap));
rows = repmat(localManifestRow(), numel(names) + 1 + numel(compatNames), 1);
for ii = 1:numel(names)
    name = names(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.trs.exportStrictTRSArtifacts");
end
airPath = fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv");
runtimeTrialsForAir = sixgr.truth.selectCanonicalRuntimeControlTrials( ...
    localReadOptionalTable(airPath), "trs");
if isempty(runtimeTrialsForAir)
    airTrials = tables.trs_trials;
else
    airTrials = runtimeTrialsForAir;
end
sixgr.util.csvWriteTable(airPath, airTrials);
rows(numel(names)+1) = localManifestRow(airPath, "text/csv", "csv", height(airTrials), ...
    "sixgr.phy.trs.exportStrictTRSArtifacts");
compatTables = struct( ...
    "trs_config_strict_control", "trs_config_strict", ...
    "trs_trials_control", "trs_trials", ...
    "trs_tracking_summary_control", "trs_tracking_summary", ...
    "trs_config_strict_reports", "trs_config_strict", ...
    "trs_trials_reports", "trs_trials", ...
    "trs_tracking_summary_reports", "trs_tracking_summary");
for ii = 1:numel(compatNames)
    name = compatNames(ii);
    tableName = string(compatTables.(name));
    if tableName == "trs_trials"
        T = airTrials;
    else
        T = tables.(tableName);
    end
    outPath = compatMap.(name);
    sixgr.util.csvWriteTable(outPath, T);
    rows(numel(names) + 1 + ii) = localManifestRow(outPath, "text/csv", "csv", height(T), ...
        "sixgr.phy.trs.exportStrictTRSArtifacts");
end
sixgr.truth.sanitizeLLSArtifactCSVs(runFolder, ...
    "OnlyPaths", [string(struct2cell(csvMap)); string(airPath); ...
    string(struct2cell(compatMap))]);

jsonPayloads = localJsonPayloads(result, csvMap);
jsonMap = struct( ...
    "trs_config_binding", fullfile(jsonDir, "trs_config_binding.json"), ...
    "trs_detection_summary", fullfile(jsonDir, "trs_detection_summary.json"), ...
    "trs_tracking_summary", fullfile(jsonDir, "trs_tracking_summary.json"), ...
    "trs_negative_summary", fullfile(jsonDir, "trs_negative_summary.json"), ...
    "trs_toolbox_capabilities", fullfile(jsonDir, "trs_toolbox_capabilities.json"));
jsonNames = string(fieldnames(jsonMap));
jsonRows = repmat(localManifestRow(), numel(jsonNames), 1);
for ii = 1:numel(jsonNames)
    name = jsonNames(ii);
    sixgr.util.jsonWrite(jsonMap.(name), jsonPayloads.(name));
    jsonRows(ii) = localManifestRow(jsonMap.(name), "application/json", "json", NaN, ...
        "sixgr.phy.trs.exportStrictTRSArtifacts");
end

textRows = localWriteTextArtifacts(textDir, result);
binaryRows = localWriteBinaryArtifacts(binaryDir, result);
[figureRows, plotLineagePath] = localWriteFigures(runFolder, refCsvDir, figDir, result, csvMap);
lineageRow = localManifestRow(plotLineagePath, "text/csv", "plot_lineage", height(readtable(plotLineagePath)), ...
    "sixgr.phy.trs.exportStrictTRSArtifacts");
manifestRows = [rows(:); jsonRows(:); textRows(:); binaryRows(:); figureRows(:); lineageRow];
manifestPath = fullfile(refCsvDir, "trs_strict_artifact_manifest.csv");
manifest = sixgr.artifact.writeIntegrityManifest(manifestPath, manifestRows);
end

function T = localReadOptionalTable(path)
T = table();
if exist(char(string(path)), "file") ~= 2
    return;
end
try
    T = readtable(char(string(path)), "FileType", "text", ...
        "Delimiter", ",", "ReadVariableNames", true, ...
        "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function payloads = localJsonPayloads(result, csvMap)
base = localEnvelope(result, "strict_trs_waveform_tracking_validation", csvMap.trs_trials);
payloads = struct();
payloads.trs_config_binding = base;
payloads.trs_config_binding.ConfigHash = string(result.ConfigHash);
payloads.trs_config_binding.BindingSource = string(result.Config.BindingSource);
payloads.trs_config_binding.SourceCSVHash = localFileSHA256(csvMap.trs_config_strict);
payloads.trs_detection_summary = result.DetectionSummary;
payloads.trs_detection_summary.source_csv = string(csvMap.trs_trials);
payloads.trs_detection_summary.source_csv_sha256 = localFileSHA256(csvMap.trs_trials);
payloads.trs_tracking_summary = base;
payloads.trs_tracking_summary.source_csv = string(csvMap.trs_timing_tracking);
payloads.trs_tracking_summary.timing_csv_sha256 = localFileSHA256(csvMap.trs_timing_tracking);
payloads.trs_tracking_summary.frequency_csv_sha256 = localFileSHA256(csvMap.trs_frequency_tracking);
payloads.trs_tracking_summary.channel_csv_sha256 = localFileSHA256(csvMap.trs_channel_estimation);
payloads.trs_negative_summary = base;
payloads.trs_negative_summary.NegativeRows = height(result.ArtifactTables.trs_negative_trials);
payloads.trs_negative_summary.source_csv = string(csvMap.trs_negative_trials);
payloads.trs_negative_summary.source_csv_sha256 = localFileSHA256(csvMap.trs_negative_trials);
payloads.trs_toolbox_capabilities = result.ToolboxCapabilities;
payloads.trs_toolbox_capabilities.RunId = string(result.RunId);
payloads.trs_toolbox_capabilities.scenario = string(result.ScenarioName);
end

function payload = localEnvelope(result, status, sourceCsv)
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = string(status);
payload.ProducerModule = "sixgr.phy.trs.exportStrictTRSArtifacts";
payload.source_csv = string(sourceCsv);
payload.source_csv_sha256 = localFileSHA256(sourceCsv);
payload.StrictOk = logical(result.StrictOk);
payload.ProxyUsed = logical(result.ProxyUsed);
payload.Skipped = logical(result.Skipped);
payload.ToolboxMissing = logical(result.ToolboxMissing);
payload.UsedOracleFields = string(result.UsedOracleFields);
payload.FailureReason = string(result.FailureReason);
end

function rows = localWriteTextArtifacts(textDir, result)
cfgPath = fullfile(textDir, "trs_config_dump.txt");
hashPath = fullfile(textDir, "trs_trial_hashes.txt");
sixgr.util.writeTextFile(cfgPath, evalc("disp(result.Config.ConfigExport)"));
T = result.ArtifactTables.trs_trials;
hashLines = "TrialId,TrialType,StrictOk,ConfigHash" + newline + ...
    strjoin(string(T.TrialId) + "," + string(T.TrialType) + "," + string(T.StrictOk) + "," + string(T.ConfigHash), newline);
sixgr.util.writeTextFile(hashPath, hashLines);
rows = [
    localManifestRow(cfgPath, "text/plain", "text", NaN, "sixgr.phy.trs.exportStrictTRSArtifacts")
    localManifestRow(hashPath, "text/plain", "text", height(T), "sixgr.phy.trs.exportStrictTRSArtifacts")];
end

function rows = localWriteBinaryArtifacts(binaryDir, result)
posPath = fullfile(binaryDir, "trs_positive_grid.bin");
noisePath = fullfile(binaryDir, "trs_no_signal_grid.bin");
localWriteComplex(posPath, result.PositiveGrid);
localWriteComplex(noisePath, result.NoSignalGrid);
rows = [
    localManifestRow(posPath, "application/octet-stream", "binary", NaN, "sixgr.phy.trs.exportStrictTRSArtifacts")
    localManifestRow(noisePath, "application/octet-stream", "binary", NaN, "sixgr.phy.trs.exportStrictTRSArtifacts")];
end

function localWriteComplex(path, x)
sixgr.util.ensureDir(path);
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = single([real(x(:)).'; imag(x(:)).']);
fwrite(fid, data(:), "single");
end

function [rows, lineagePath] = localWriteFigures(runFolder, refCsvDir, figDir, result, csvMap)
paths = [
    string(fullfile(figDir, "trs_resource_grid.png"))
    string(fullfile(figDir, "trs_detection_metric_by_slot.png"))
    string(fullfile(figDir, "trs_coverage_heatmap.png"))
    string(fullfile(figDir, "trs_timing_error_sweep.png"))
    string(fullfile(figDir, "trs_frequency_offset_sweep.png"))
    string(fullfile(figDir, "trs_channel_estimation_nmse.png"))
    string(fullfile(figDir, "trs_negative_trial_outcomes.png"))
    string(fullfile(figDir, "trs_tracking_flow.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);
localWritePNG(paths(1), localHeatImage(abs(result.PositiveGrid(:,:,1))));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.trs.exportStrictTRSArtifacts");
det = result.ArtifactTables.trs_detection_metrics;
localWritePNG(paths(2), localLineImage(double(det.Slot), double(det.DetectionMetric)));
rows(2) = localManifestRow(paths(2), "image/png", "figure", height(det), "sixgr.phy.trs.exportStrictTRSArtifacts");
localWritePNG(paths(3), localHeatImage(reshape(double(det.ResourceCoverageRatio), [], 1)));
rows(3) = localManifestRow(paths(3), "image/png", "figure", height(det), "sixgr.phy.trs.exportStrictTRSArtifacts");
tim = result.ArtifactTables.trs_timing_offset_sweep;
localWritePNG(paths(4), localLineImage(double(tim.InjectedTimingOffset_samples), abs(double(tim.TimingError_samples))));
rows(4) = localManifestRow(paths(4), "image/png", "figure", height(tim), "sixgr.phy.trs.exportStrictTRSArtifacts");
fr = result.ArtifactTables.trs_frequency_offset_sweep;
localWritePNG(paths(5), localLineImage(double(fr.InjectedCFO_Hz), abs(double(fr.FrequencyError_Hz))));
rows(5) = localManifestRow(paths(5), "image/png", "figure", height(fr), "sixgr.phy.trs.exportStrictTRSArtifacts");
ch = result.ArtifactTables.trs_channel_estimation;
localWritePNG(paths(6), localLineImage(double(ch.Slot), double(ch.NMSE_dB)));
rows(6) = localManifestRow(paths(6), "image/png", "figure", height(ch), "sixgr.phy.trs.exportStrictTRSArtifacts");
neg = result.ArtifactTables.trs_negative_trials;
localWritePNG(paths(7), localBarImage(double(neg.NegativeExpectedOk)));
rows(7) = localManifestRow(paths(7), "image/png", "figure", height(neg), "sixgr.phy.trs.exportStrictTRSArtifacts");
sixgr.visual.writeFlowDiagramPNG(paths(8), "Strict TRS tracking flow", ...
    ["NZP-CSI-RS/TRS grid","Timing estimate","CFO phase slope","nrChannelEstimate","Strict gate"], result.StrictOk);
rows(8) = localManifestRow(paths(8), "image/png", "figure", NaN, "sixgr.phy.trs.exportStrictTRSArtifacts");
lineagePath = fullfile(refCsvDir, "trs_plot_lineage.csv");
sourceCSVs = [
    string(csvMap.trs_resource_grid_power)
    string(csvMap.trs_detection_metrics)
    string(csvMap.trs_detection_metrics)
    string(csvMap.trs_timing_offset_sweep)
    string(csvMap.trs_frequency_offset_sweep)
    string(csvMap.trs_channel_estimation)
    string(csvMap.trs_negative_trials)
    string(csvMap.trs_config_strict) + "|" + string(csvMap.trs_trials)];
sixgr.visual.writeComponentPlotLineage(runFolder, lineagePath, ...
    ["trs_resource_grid","trs_detection_metric_by_slot","trs_coverage_heatmap", ...
    "trs_timing_error_sweep","trs_frequency_offset_sweep","trs_channel_estimation_nmse", ...
    "trs_negative_trial_outcomes","trs_tracking_flow"], ...
    paths, sourceCSVs, "sixgr.phy.trs.exportStrictTRSArtifacts");
end

function localWritePNG(path, img)
sixgr.util.ensureDir(path);
img = uint8(img);
[heightPx, widthPx, channels] = size(img);
if channels ~= 3
    error("sixgr:phy:trs:BadPNGImage", "Strict TRS PNG writer expects RGB image data.");
end
rawPath = char(string(tempname) + ".rgb");
fid = fopen(rawPath, "w");
if fid < 0
    error("sixgr:phy:trs:PNGRawOpenFailed", "Cannot open temporary PNG raw buffer.");
end
cleanupClose = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, permute(img, [3 2 1]), "uint8");
clear cleanupClose;
scriptPath = fullfile(localRepoRoot(), "tools", "write_png_from_raw_rgb.py");
cmd = sprintf('python "%s" "%s" "%s" %d %d', localShellEscape(scriptPath), ...
    localShellEscape(rawPath), localShellEscape(char(string(path))), widthPx, heightPx);
[status, out] = system(cmd);
try
    if exist(rawPath, "file") == 2
        delete(rawPath);
    end
catch
end
if status ~= 0 || exist(char(string(path)), "file") ~= 2
    error("sixgr:phy:trs:PNGWriteFailed", "Strict TRS PNG writer failed: %s", string(out));
end
end

function img = localBaseImage()
img = uint8(255 * ones(480, 720, 3));
img(430:433, 70:660, :) = 190;
img(70:430, 67:70, :) = 190;
end

function img = localHeatImage(M)
M = abs(double(M));
if isempty(M)
    error("sixgr:phy:trs:MissingPlotEvidence", ...
        "Cannot publish a TRS heat map without measured source samples.");
end
M = localNormalizeMatrix(M);
rowIdx = max(1, min(size(M, 1), round(linspace(1, size(M, 1), 420))));
colIdx = max(1, min(size(M, 2), round(linspace(1, size(M, 2), 620))));
M = M(rowIdx, colIdx);
img = localBaseImage();
heat = uint8(cat(3, 255 .* M, 80 .* (1 - M), 220 .* (1 - M)));
img(40:459, 80:699, :) = heat;
end

function img = localLineImage(x, y)
img = localBaseImage();
x = double(x(:)); y = double(y(:));
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
if isempty(x)
    error("sixgr:phy:trs:MissingPlotEvidence", ...
        "Cannot publish a TRS line plot without finite measured samples.");
end
px = localScaleToPixels(x, 80, 660);
py = localScaleToPixels(y, 420, 80);
for ii = 1:(numel(px)-1)
    img = localDrawLine(img, px(ii), py(ii), px(ii+1), py(ii+1), [30 90 180]);
end
for ii = 1:numel(px)
    img = localPaintPatch(img, px(ii), py(ii), 3, [220 60 40]);
end
end

function img = localBarImage(y)
img = localBaseImage();
y = double(y(:)); y = y(isfinite(y));
if isempty(y)
    error("sixgr:phy:trs:MissingPlotEvidence", ...
        "Cannot publish a TRS bar plot without finite measured samples.");
end
py = localScaleToPixels(y, 420, 80);
x = round(linspace(90, 650, numel(y)));
for ii = 1:numel(y)
    img(max(80, py(ii)):420, max(1, x(ii)-8):min(720, x(ii)+8), 1) = 45;
    img(max(80, py(ii)):420, max(1, x(ii)-8):min(720, x(ii)+8), 2) = 135;
    img(max(80, py(ii)):420, max(1, x(ii)-8):min(720, x(ii)+8), 3) = 190;
end
end

function M = localNormalizeMatrix(M)
M(~isfinite(M)) = 0;
lo = min(M(:)); hi = max(M(:));
if hi <= lo
    M = zeros(size(M));
else
    M = (M - lo) ./ (hi - lo);
end
end

function pix = localScaleToPixels(v, pMin, pMax)
v = double(v(:));
if max(v) <= min(v)
    pix = round((pMin + pMax) / 2) * ones(size(v));
else
    pix = round(pMin + (v - min(v)) ./ (max(v) - min(v)) .* (pMax - pMin));
end
pix = max(1, min(720, pix));
end

function img = localDrawLine(img, x1, y1, x2, y2, color)
n = max(2, round(hypot(double(x2 - x1), double(y2 - y1))));
xs = round(linspace(x1, x2, n)); ys = round(linspace(y1, y2, n));
for kk = 1:n
    x = max(1, min(size(img, 2), xs(kk)));
    y = max(1, min(size(img, 1), ys(kk)));
    img = localPaintPatch(img, x, y, 1, color);
end
end

function img = localPaintPatch(img, x, y, radius, color)
r = max(0, round(double(radius)));
x1 = max(1, round(double(x)) - r);
x2 = min(size(img, 2), round(double(x)) + r);
y1 = max(1, round(double(y)) - r);
y2 = min(size(img, 1), round(double(y)) + r);
if x2 < x1 || y2 < y1
    return;
end
rgb = uint8(reshape(color, 1, 1, 3));
img(y1:y2, x1:x2, :) = repmat(rgb, y2 - y1 + 1, x2 - x1 + 1, 1);
end

function row = localManifestRow(path, mime, kind, rowCount, producer)
if nargin == 0
    path = ""; mime = ""; kind = ""; rowCount = NaN; producer = "";
end
artifactId = "";
if strlength(string(path)) > 0
    [~, name, ext] = fileparts(char(string(path)));
    artifactId = string(name) + string(ext);
end
row = struct("ArtifactId", string(artifactId), "FilePath", string(path), ...
    "ArtifactPath", string(path), "MimeType", string(mime), ...
    "Kind", string(kind), "ArtifactKind", string(kind), ...
    "RowCount", double(rowCount), "ByteCount", localFileBytes(path), ...
    "SHA256", localFileSHA256(path), "ProducerModule", string(producer));
end

function bytes = localFileBytes(path)
bytes = NaN;
if nargin < 1 || strlength(string(path)) == 0 || exist(path, "file") ~= 2
    return;
end
d = dir(path);
if ~isempty(d)
    bytes = double(d(1).bytes);
end
end

function hash = localFileSHA256(path)
hash = "";
if nargin < 1 || strlength(string(path)) == 0 || exist(path, "file") ~= 2
    return;
end
fid = fopen(path, "r");
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, "*uint8");
hash = sixgr.rrc.asn1.sha256Hex(data);
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function out = localShellEscape(value)
out = strrep(char(string(value)), '"', '""');
end

function T = localGridEvidence(grid)
if isempty(grid)
    error("sixgr:phy:trs:MissingGridEvidence", ...
        "Strict TRS resource-grid evidence is empty.");
end
sz = size(grid);
if numel(sz) < 3
    sz(3) = 1;
end
[subcarrier, symbol, port] = ndgrid(0:(sz(1)-1), 0:(sz(2)-1), 0:(sz(3)-1));
values = grid(:);
T = table(subcarrier(:), symbol(:), port(:), real(values), imag(values), abs(values).^2, ...
    'VariableNames', {'Subcarrier','Symbol','Port','ValueI','ValueQ','Power'});
end
