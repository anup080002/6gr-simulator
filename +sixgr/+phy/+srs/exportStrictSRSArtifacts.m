function manifest = exportStrictSRSArtifacts(runFolder, result)
%EXPORTSTRICTSRSARTIFACTS Persist strict SRS evidence artifacts.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
refCsvDir = fullfile(runFolder, "reference_signals", "csv");
jsonDir = fullfile(layout.ReportDir, "json");
textDir = fullfile(layout.ReportDir, "text");
binaryDir = fullfile(layout.ReportDir, "binary");
figDir = fullfile(layout.ReportDir, "figures");
sixgr.util.ensureFolder(refCsvDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(textDir);
sixgr.util.ensureFolder(binaryDir);
sixgr.util.ensureFolder(figDir);

tables = result.ArtifactTables;
csvMap = struct( ...
    "srs_config_strict", fullfile(refCsvDir, "srs_config_strict.csv"), ...
    "srs_resource_sets", fullfile(refCsvDir, "srs_resource_sets.csv"), ...
    "srs_resources", fullfile(refCsvDir, "srs_resources.csv"), ...
    "srs_resource_mapping", fullfile(refCsvDir, "srs_resource_mapping.csv"), ...
    "srs_tx_waveform", fullfile(refCsvDir, "srs_tx_waveform.csv"), ...
    "srs_rx_extraction", fullfile(refCsvDir, "srs_rx_extraction.csv"), ...
    "srs_detection_metrics", fullfile(refCsvDir, "srs_detection_metrics.csv"), ...
    "srs_channel_estimation", fullfile(refCsvDir, "srs_channel_estimation.csv"), ...
    "srs_channel_estimation_per_prb", fullfile(refCsvDir, "srs_channel_estimation_per_prb.csv"), ...
    "srs_channel_estimation_per_port", fullfile(refCsvDir, "srs_channel_estimation_per_port.csv"), ...
    "srs_timing_tracking", fullfile(refCsvDir, "srs_timing_tracking.csv"), ...
    "srs_coverage", fullfile(refCsvDir, "srs_coverage.csv"), ...
    "srs_trigger_events", fullfile(refCsvDir, "srs_trigger_events.csv"), ...
    "srs_trials", fullfile(refCsvDir, "srs_trials.csv"), ...
    "srs_negative_trials", fullfile(refCsvDir, "srs_negative_trials.csv"), ...
    "srs_low_snr_sweep", fullfile(refCsvDir, "srs_low_snr_sweep.csv"), ...
    "srs_timing_offset_sweep", fullfile(refCsvDir, "srs_timing_offset_sweep.csv"), ...
    "srs_multi_ue_trials", fullfile(refCsvDir, "srs_multi_ue_trials.csv"), ...
    "srs_oracle_guard", fullfile(refCsvDir, "srs_oracle_guard.csv"));
names = string(fieldnames(csvMap));
rows = repmat(localManifestRow(), numel(names) + 1, 1);
for ii = 1:numel(names)
    name = names(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.srs.exportStrictSRSArtifacts");
end
airPath = fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv");
sixgr.util.csvWriteTable(airPath, tables.srs_trials);
rows(numel(names)+1) = localManifestRow(airPath, "text/csv", "csv", height(tables.srs_trials), ...
    "sixgr.phy.srs.exportStrictSRSArtifacts");

jsonMap = struct( ...
    "srs_config_binding", fullfile(jsonDir, "srs_config_binding.json"), ...
    "srs_detection_summary", fullfile(jsonDir, "srs_detection_summary.json"), ...
    "srs_coverage_summary", fullfile(jsonDir, "srs_coverage_summary.json"), ...
    "srs_negative_summary", fullfile(jsonDir, "srs_negative_summary.json"), ...
    "srs_toolbox_capabilities", fullfile(jsonDir, "srs_toolbox_capabilities.json"));
payloads = localJsonPayloads(result, csvMap);
jsonNames = string(fieldnames(jsonMap));
jsonRows = repmat(localManifestRow(), numel(jsonNames), 1);
for ii = 1:numel(jsonNames)
    name = jsonNames(ii);
    sixgr.util.jsonWrite(jsonMap.(name), payloads.(name));
    jsonRows(ii) = localManifestRow(jsonMap.(name), "application/json", "json", NaN, ...
        "sixgr.phy.srs.exportStrictSRSArtifacts");
end

textRows = localWriteTextArtifacts(textDir, result);
binaryRows = localWriteBinaryArtifacts(binaryDir, result);
figureRows = localWriteFigures(figDir, result);
manifestRows = [rows(:); jsonRows(:); textRows(:); binaryRows(:); figureRows(:)];
manifest = struct2table(manifestRows, "AsArray", true);
manifestPath = fullfile(refCsvDir, "srs_strict_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
manifest(end + 1, :) = struct2table(localManifestRow(manifestPath, "text/csv", "csv", height(manifest), ...
    "sixgr.phy.srs.exportStrictSRSArtifacts"), "AsArray", true);
sixgr.util.csvWriteTable(manifestPath, manifest);
end

function payloads = localJsonPayloads(result, csvMap)
base = localEnvelope(result, "strict_srs_waveform_channel_sounding_validation", csvMap.srs_trials);
payloads = struct();
payloads.srs_config_binding = base;
payloads.srs_config_binding.ConfigHash = string(result.ConfigHash);
payloads.srs_config_binding.BindingSource = string(result.Config.BindingSource);
payloads.srs_config_binding.SourceCSVHash = localFileSHA256(csvMap.srs_config_strict);
payloads.srs_detection_summary = result.DetectionSummary;
payloads.srs_detection_summary.source_csv = string(csvMap.srs_trials);
payloads.srs_detection_summary.source_csv_sha256 = localFileSHA256(csvMap.srs_trials);
payloads.srs_coverage_summary = base;
payloads.srs_coverage_summary.source_csv = string(csvMap.srs_coverage);
payloads.srs_coverage_summary.source_csv_sha256 = localFileSHA256(csvMap.srs_coverage);
payloads.srs_coverage_summary.FullCarrierClaimValid = any(logical(result.ArtifactTables.srs_coverage.FullCarrierClaimValid));
payloads.srs_negative_summary = base;
payloads.srs_negative_summary.NegativeRows = height(result.ArtifactTables.srs_negative_trials);
payloads.srs_negative_summary.source_csv = string(csvMap.srs_negative_trials);
payloads.srs_negative_summary.source_csv_sha256 = localFileSHA256(csvMap.srs_negative_trials);
payloads.srs_toolbox_capabilities = result.ToolboxCapabilities;
end

function payload = localEnvelope(result, status, sourceCsv)
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = string(status);
payload.ProducerModule = "sixgr.phy.srs.exportStrictSRSArtifacts";
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
cfgPath = fullfile(textDir, "srs_config_dump.txt");
hashPath = fullfile(textDir, "srs_trial_hashes.txt");
sixgr.util.writeTextFile(cfgPath, evalc("disp(result.Config.ConfigExport)"));
T = result.ArtifactTables.srs_trials;
hashLines = "TrialId,TrialType,StrictOk,ConfigHash" + newline + ...
    strjoin(string(T.TrialId) + "," + string(T.TrialType) + "," + string(T.StrictOk) + "," + string(T.ConfigHash), newline);
sixgr.util.writeTextFile(hashPath, hashLines);
rows = [
    localManifestRow(cfgPath, "text/plain", "text", NaN, "sixgr.phy.srs.exportStrictSRSArtifacts")
    localManifestRow(hashPath, "text/plain", "text", height(T), "sixgr.phy.srs.exportStrictSRSArtifacts")];
end

function rows = localWriteBinaryArtifacts(binaryDir, result)
posPath = fullfile(binaryDir, "srs_positive_grid.bin");
noisePath = fullfile(binaryDir, "srs_no_signal_grid.bin");
localWriteComplex(posPath, result.PositiveGrid);
localWriteComplex(noisePath, result.NoSignalGrid);
rows = [
    localManifestRow(posPath, "application/octet-stream", "binary", NaN, "sixgr.phy.srs.exportStrictSRSArtifacts")
    localManifestRow(noisePath, "application/octet-stream", "binary", NaN, "sixgr.phy.srs.exportStrictSRSArtifacts")];
end

function localWriteComplex(path, x)
sixgr.util.ensureDir(path);
fid = fopen(path, "w");
if fid < 0
    error("sixgr:phy:srs:BinaryOpenFailed", "Cannot open SRS binary artifact '%s'.", string(path));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = single([real(x(:)).'; imag(x(:)).']);
fwrite(fid, data(:), "single");
end

function rows = localWriteFigures(figDir, result)
paths = [
    string(fullfile(figDir, "srs_resource_grid.svg"))
    string(fullfile(figDir, "srs_detection_metric_by_trial.svg"))
    string(fullfile(figDir, "srs_coverage_summary.svg"))
    string(fullfile(figDir, "srs_channel_estimation_nmse.svg"))
    string(fullfile(figDir, "srs_low_snr_sweep.svg"))
    string(fullfile(figDir, "srs_timing_offset_sweep.svg"))
    string(fullfile(figDir, "srs_negative_trial_outcomes.svg"))
    string(fullfile(figDir, "srs_strict_flow.svg"))];
rows = repmat(localManifestRow(), numel(paths), 1);
gridPower = abs(result.PositiveGrid(:,:,1));
localWriteHeatSVG(paths(1), "SRS resource grid power", gridPower);
rows(1) = localManifestRow(paths(1), "image/svg+xml", "figure", numel(gridPower), "sixgr.phy.srs.exportStrictSRSArtifacts");
det = result.ArtifactTables.srs_detection_metrics;
localWriteLineSVG(paths(2), "SRS detection metric by trial", double(det.TrialId), double(det.DetectionMetric));
rows(2) = localManifestRow(paths(2), "image/svg+xml", "figure", height(det), "sixgr.phy.srs.exportStrictSRSArtifacts");
cov = result.ArtifactTables.srs_coverage;
localWriteBarSVG(paths(3), "SRS coverage percent", double(cov.CoveragePercent));
rows(3) = localManifestRow(paths(3), "image/svg+xml", "figure", height(cov), "sixgr.phy.srs.exportStrictSRSArtifacts");
ch = result.ArtifactTables.srs_channel_estimation;
localWriteLineSVG(paths(4), "SRS channel NMSE by trial", double(ch.TrialId), double(ch.NMSE_dB));
rows(4) = localManifestRow(paths(4), "image/svg+xml", "figure", height(ch), "sixgr.phy.srs.exportStrictSRSArtifacts");
low = result.ArtifactTables.srs_low_snr_sweep;
localWriteLineSVG(paths(5), "SRS low-SNR detection probability", double(low.SNRdB), double(low.DetectionProbability));
rows(5) = localManifestRow(paths(5), "image/svg+xml", "figure", height(low), "sixgr.phy.srs.exportStrictSRSArtifacts");
tim = result.ArtifactTables.srs_timing_offset_sweep;
localWriteLineSVG(paths(6), "SRS timing error sweep", double(tim.InjectedTimingOffsetSamples), abs(double(tim.MeanTimingErrorSamples)));
rows(6) = localManifestRow(paths(6), "image/svg+xml", "figure", height(tim), "sixgr.phy.srs.exportStrictSRSArtifacts");
neg = result.ArtifactTables.srs_negative_trials;
localWriteBarSVG(paths(7), "SRS negative trial expected failures", double(neg.NegativeExpectedOk));
rows(7) = localManifestRow(paths(7), "image/svg+xml", "figure", height(neg), "sixgr.phy.srs.exportStrictSRSArtifacts");
localWriteFlowSVG(paths(8), "Strict SRS channel sounding flow", ...
    ["nrSRS generation","UL OFDM waveform","gNB resource extraction","LS/MMSE/DFT channel estimate","coverage gate"], result.StrictOk);
rows(8) = localManifestRow(paths(8), "image/svg+xml", "figure", NaN, "sixgr.phy.srs.exportStrictSRSArtifacts");
end

function localWriteLineSVG(path, titleText, x, y)
x = double(x(:));
y = double(y(:));
mask = isfinite(x) & isfinite(y);
x = x(mask);
y = y(mask);
poly = "";
if ~isempty(x)
    px = localScale(x, 60, 700);
    py = localScale(y, 300, 60);
    points = strings(numel(px), 1);
    for ii = 1:numel(px)
        points(ii) = sprintf("%.1f,%.1f", px(ii), py(ii));
    end
    poly = string(sprintf('<polyline points="%s" fill="none" stroke="#1f5a9d" stroke-width="3"/>', strjoin(points, " ")));
    for ii = 1:numel(px)
        poly = poly + string(sprintf('<circle cx="%.1f" cy="%.1f" r="4" fill="#d94b2b"/>', px(ii), py(ii)));
    end
end
txt = sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="760" height="360"><rect width="760" height="360" fill="white"/><text x="24" y="32" font-family="Arial" font-size="20">%s</text><line x1="60" y1="300" x2="720" y2="300" stroke="#444"/><line x1="60" y1="300" x2="60" y2="50" stroke="#444"/>%s</svg>', char(titleText), char(poly));
sixgr.util.writeTextFile(path, string(txt), "MimeType", "image/svg+xml", "ArtifactKind", "image_svg");
end

function localWriteBarSVG(path, titleText, y)
y = double(y(:));
y = y(isfinite(y));
bars = "";
if ~isempty(y)
    x = linspace(90, 680, numel(y));
    py = localScale(y, 280, 80);
    for ii = 1:numel(y)
        h = max(1, 300 - py(ii));
        bars = bars + string(sprintf('<rect x="%.1f" y="%.1f" width="28" height="%.1f" fill="#317d7e"/>', x(ii), py(ii), h));
    end
end
txt = sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="760" height="360"><rect width="760" height="360" fill="white"/><text x="24" y="32" font-family="Arial" font-size="20">%s</text><line x1="60" y1="300" x2="720" y2="300" stroke="#444"/><line x1="60" y1="300" x2="60" y2="50" stroke="#444"/>%s</svg>', char(titleText), char(bars));
sixgr.util.writeTextFile(path, string(txt), "MimeType", "image/svg+xml", "ArtifactKind", "image_svg");
end

function localWriteHeatSVG(path, titleText, M)
M = abs(double(M));
M(~isfinite(M)) = 0;
if isempty(M)
    M = zeros(1, 1);
end
rows = min(24, size(M, 1));
cols = min(24, size(M, 2));
ridx = max(1, round(linspace(1, size(M, 1), rows)));
cidx = max(1, round(linspace(1, size(M, 2), cols)));
M = M(ridx, cidx);
if max(M(:)) > min(M(:))
    M = (M - min(M(:))) ./ (max(M(:)) - min(M(:)));
else
    M = zeros(size(M));
end
cells = "";
for r = 1:size(M, 1)
    for c = 1:size(M, 2)
        val = M(r, c);
        color = sprintf("#%02x%02x%02x", round(255 * val), round(110 * (1 - val)), round(220 * (1 - val)));
        cells = cells + string(sprintf('<rect x="%d" y="%d" width="20" height="12" fill="%s"/>', 60 + (c-1)*20, 55 + (r-1)*12, color));
    end
end
txt = sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="760" height="360"><rect width="760" height="360" fill="white"/><text x="24" y="32" font-family="Arial" font-size="20">%s</text>%s</svg>', char(titleText), char(cells));
sixgr.util.writeTextFile(path, string(txt), "MimeType", "image/svg+xml", "ArtifactKind", "image_svg");
end

function localWriteFlowSVG(path, titleText, labels, ok)
labels = string(labels(:));
x = round(linspace(35, 565, numel(labels)));
txt = string(sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="760" height="240"><rect width="760" height="240" fill="white"/><text x="24" y="36" font-family="Arial" font-size="20">%s</text>', char(string(titleText))));
for ii = 1:numel(labels)
    txt = txt + sprintf('<rect x="%d" y="84" width="135" height="62" fill="#e8f8f2" stroke="#264"/>', x(ii));
    txt = txt + sprintf('<text x="%d" y="118" font-family="Arial" font-size="11">%s</text>', x(ii)+8, char(labels(ii)));
    if ii < numel(labels)
        txt = txt + sprintf('<line x1="%d" y1="115" x2="%d" y2="115" stroke="#333"/>', x(ii)+135, x(ii+1));
    end
end
txt = txt + sprintf('<text x="590" y="190" font-family="Arial" font-size="12">StrictOk=%d</text></svg>', double(logical(ok)));
sixgr.util.writeTextFile(path, txt, "MimeType", "image/svg+xml", "ArtifactKind", "image_svg");
end

function pix = localScale(v, pMin, pMax)
v = double(v(:));
if isempty(v) || max(v) <= min(v)
    pix = round((pMin + pMax) / 2) * ones(size(v));
else
    pix = pMin + (v - min(v)) ./ (max(v) - min(v)) .* (pMax - pMin);
end
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
