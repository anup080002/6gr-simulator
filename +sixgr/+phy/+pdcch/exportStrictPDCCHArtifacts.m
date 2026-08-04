function manifest = exportStrictPDCCHArtifacts(runFolder, result)
%EXPORTSTRICTPDCCHARTIFACTS Persist strict PDCCH evidence artifacts.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
jsonDir = fullfile(layout.ReportDir, "json");
textDir = fullfile(layout.ReportDir, "text");
binaryDir = fullfile(layout.ReportDir, "binary");
figDir = fullfile(layout.ReportDir, "figures");
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(textDir);
sixgr.util.ensureFolder(binaryDir);
sixgr.util.ensureFolder(figDir);

tables = result.ArtifactTables;
airPath = fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv");
runtimeTrials = sixgr.truth.selectCanonicalRuntimeControlTrials( ...
    localReadOptionalTable(airPath), "pdcch");
if isempty(runtimeTrials)
    strictTrialPath = fullfile(layout.ControlCSVDir, "pdcch_trials.csv");
else
    strictTrialPath = fullfile(layout.ControlCSVDir, "pdcch_strict_trials.csv");
end
csvMap = struct( ...
    "pdcch_config_strict", fullfile(layout.ControlCSVDir, "pdcch_config_strict.csv"), ...
    "pdcch_trials", strictTrialPath, ...
    "pdcch_candidates", fullfile(layout.ControlCSVDir, "pdcch_candidates.csv"), ...
    "pdcch_dci_fields", fullfile(layout.ControlCSVDir, "pdcch_dci_fields.csv"), ...
    "pdcch_grant_validation", fullfile(layout.ControlCSVDir, "pdcch_grant_validation.csv"), ...
    "pdcch_wrong_rnti_trials", fullfile(layout.ControlCSVDir, "pdcch_wrong_rnti_trials.csv"), ...
    "pdcch_no_signal_trials", fullfile(layout.ControlCSVDir, "pdcch_no_signal_trials.csv"), ...
    "pdcch_corruption_trials", fullfile(layout.ControlCSVDir, "pdcch_corruption_trials.csv"), ...
    "pdcch_false_alarm_sweep", fullfile(layout.ControlCSVDir, "pdcch_false_alarm_sweep.csv"), ...
    "pdcch_low_snr_sweep", fullfile(layout.ControlCSVDir, "pdcch_low_snr_sweep.csv"), ...
    "pdcch_oracle_guard", fullfile(layout.ControlCSVDir, "pdcch_oracle_guard.csv"));
names = string(fieldnames(csvMap));
rows = repmat(localManifestRow(), numel(names) + 1, 1);
for ii = 1:numel(names)
    name = names(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
end
if isempty(runtimeTrials)
    primaryTrials = tables.pdcch_trials;
else
    primaryTrials = runtimeTrials;
    sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), primaryTrials);
end
sixgr.util.csvWriteTable(airPath, primaryTrials);
rows(numel(names)+1) = localManifestRow(airPath, "text/csv", "csv", height(primaryTrials), ...
    "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");

jsonPayloads = localJsonPayloads(result, csvMap);
jsonMap = struct( ...
    "pdcch_config_binding", fullfile(jsonDir, "pdcch_config_binding.json"), ...
    "pdcch_detection_summary", fullfile(jsonDir, "pdcch_detection_summary.json"), ...
    "pdcch_negative_summary", fullfile(jsonDir, "pdcch_negative_summary.json"), ...
    "pdcch_false_alarm_summary", fullfile(jsonDir, "pdcch_false_alarm_summary.json"), ...
    "pdcch_dci_tx_fields", fullfile(jsonDir, "pdcch_dci_tx_fields.json"), ...
    "pdcch_dci_rx_fields", fullfile(jsonDir, "pdcch_dci_rx_fields.json"), ...
    "pdcch_toolbox_capabilities", fullfile(jsonDir, "pdcch_toolbox_capabilities.json"));
jsonNames = string(fieldnames(jsonMap));
jsonRows = repmat(localManifestRow(), numel(jsonNames), 1);
for ii = 1:numel(jsonNames)
    name = jsonNames(ii);
    sixgr.util.jsonWrite(jsonMap.(name), jsonPayloads.(name));
    jsonRows(ii) = localManifestRow(jsonMap.(name), "application/json", "json", NaN, ...
        "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
end

textRows = localWriteTextArtifacts(textDir, result);
binaryRows = localWriteBinaryArtifacts(binaryDir, result);
figureRows = localWriteFigures(figDir, result);
manifestRows = [rows(:); jsonRows(:); textRows(:); binaryRows(:); figureRows(:)];
manifest = struct2table(manifestRows, "AsArray", true);
manifestPath = fullfile(layout.ControlCSVDir, "pdcch_strict_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
manifest(end + 1, :) = struct2table(localManifestRow(manifestPath, "text/csv", "csv", height(manifest), ...
    "sixgr.phy.pdcch.exportStrictPDCCHArtifacts"), "AsArray", true);
sixgr.util.csvWriteTable(manifestPath, manifest);
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
base = localEnvelope(result, "strict_pdcch_waveform_blind_decode_validation", csvMap.pdcch_trials);
payloads = struct();
payloads.pdcch_config_binding = base;
payloads.pdcch_config_binding.ConfigHash = string(result.ConfigHash);
payloads.pdcch_config_binding.BindingSource = string(result.Config.BindingSource);
payloads.pdcch_config_binding.SourceCSVHash = localFileSHA256(csvMap.pdcch_config_strict);
payloads.pdcch_detection_summary = result.DetectionSummary;
payloads.pdcch_detection_summary.source_csv = string(csvMap.pdcch_trials);
payloads.pdcch_detection_summary.source_csv_sha256 = localFileSHA256(csvMap.pdcch_trials);
payloads.pdcch_negative_summary = base;
payloads.pdcch_negative_summary.WrongRNTIRows = height(result.ArtifactTables.pdcch_wrong_rnti_trials);
payloads.pdcch_negative_summary.NoSignalRows = height(result.ArtifactTables.pdcch_no_signal_trials);
payloads.pdcch_negative_summary.CorruptionRows = height(result.ArtifactTables.pdcch_corruption_trials);
payloads.pdcch_false_alarm_summary = base;
payloads.pdcch_false_alarm_summary.source_csv = string(csvMap.pdcch_false_alarm_sweep);
payloads.pdcch_false_alarm_summary.source_csv_sha256 = localFileSHA256(csvMap.pdcch_false_alarm_sweep);
payloads.pdcch_false_alarm_summary.Rows = height(result.ArtifactTables.pdcch_false_alarm_sweep);
payloads.pdcch_dci_tx_fields = base;
payloads.pdcch_dci_tx_fields.DCI10 = result.TxDCI10.Fields;
payloads.pdcch_dci_tx_fields.DCI00 = result.TxDCI00.Fields;
payloads.pdcch_dci_rx_fields = base;
payloads.pdcch_dci_rx_fields.source_csv = string(csvMap.pdcch_dci_fields);
payloads.pdcch_dci_rx_fields.source_csv_sha256 = localFileSHA256(csvMap.pdcch_dci_fields);
payloads.pdcch_toolbox_capabilities = result.ToolboxCapabilities;
payloads.pdcch_toolbox_capabilities.RunId = string(result.RunId);
payloads.pdcch_toolbox_capabilities.scenario = string(result.ScenarioName);
payloads.pdcch_toolbox_capabilities.implementation_status = "strict_pdcch_toolbox_capability_report";
end

function payload = localEnvelope(result, status, sourceCsv)
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = string(status);
payload.ProducerModule = "sixgr.phy.pdcch.exportStrictPDCCHArtifacts";
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
txPath = fullfile(textDir, "pdcch_tx_dci.hex.txt");
rxPath = fullfile(textDir, "pdcch_rx_dci.hex.txt");
summaryPath = fullfile(textDir, "pdcch_candidate_summary.txt");
sixgr.util.writeTextFile(txPath, "DCI1_0=" + string(result.TxDCI10.PayloadHex) + newline + ...
    "DCI0_0=" + string(result.TxDCI00.PayloadHex));
sixgr.util.writeTextFile(rxPath, string(result.RxDCIHex));
T = result.ArtifactTables.pdcch_trials;
summary = "TrialId,TrialType,StrictOk,NegativeExpectedOk,CandidatesAttempted" + newline + ...
    strjoin(string(T.TrialId) + "," + string(T.TrialType) + "," + string(T.StrictOk) + "," + ...
    string(T.NegativeExpectedOk) + "," + string(T.CandidatesAttempted), newline);
sixgr.util.writeTextFile(summaryPath, summary);
rows = [
    localManifestRow(txPath, "text/plain", "text", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts")
    localManifestRow(rxPath, "text/plain", "text", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts")
    localManifestRow(summaryPath, "text/plain", "text", height(T), "sixgr.phy.pdcch.exportStrictPDCCHArtifacts")];
end

function rows = localWriteBinaryArtifacts(binaryDir, result)
posPath = fullfile(binaryDir, "pdcch_positive_grid.bin");
noisePath = fullfile(binaryDir, "pdcch_no_signal_grid.bin");
localWriteComplex(posPath, result.PositiveGrid);
localWriteComplex(noisePath, result.NoSignalGrid);
rows = [
    localManifestRow(posPath, "application/octet-stream", "binary", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts")
    localManifestRow(noisePath, "application/octet-stream", "binary", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts")];
end

function localWriteComplex(path, x)
sixgr.util.ensureDir(path);
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = single([real(x(:)).'; imag(x(:)).']);
fwrite(fid, data(:), "single");
end

function rows = localWriteFigures(figDir, result)
paths = [
    string(fullfile(figDir, "pdcch_coreset_resource_grid.png"))
    string(fullfile(figDir, "pdcch_candidate_metrics.png"))
    string(fullfile(figDir, "pdcch_wrong_rnti_rejections.png"))
    string(fullfile(figDir, "pdcch_false_alarm_probability.png"))
    string(fullfile(figDir, "pdcch_low_snr_detection_probability.png"))
    string(fullfile(figDir, "pdcch_decode_flow.png"))
    string(fullfile(figDir, "pdcch_dci_to_grant_flow.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);
localWritePNG(paths(1), localHeatImage(abs(result.PositiveGrid(:,:,1))));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
cand = result.ArtifactTables.pdcch_candidates;
localWritePNG(paths(2), localBarImage(double(cand.Metric)));
rows(2) = localManifestRow(paths(2), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
wr = result.ArtifactTables.pdcch_wrong_rnti_trials;
localWritePNG(paths(3), localBarImage(double(wr.WrongRNTIRejectCount)));
rows(3) = localManifestRow(paths(3), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
fa = result.ArtifactTables.pdcch_false_alarm_sweep;
localWritePNG(paths(4), localLineImage(double(fa.SNRdB), double(fa.FalseAlarmProbability)));
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
ls = result.ArtifactTables.pdcch_low_snr_sweep;
localWritePNG(paths(5), localLineImage(double(ls.SNRdB), double(ls.DetectionProbability)));
rows(5) = localManifestRow(paths(5), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
sixgr.visual.writeFlowDiagramPNG(paths(6), "Strict PDCCH blind decode", ["PDCCH waveform","CORESET/search-space candidates","RNTI CRC + DCI decode","Score after decode"], result.StrictOk);
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
sixgr.visual.writeFlowDiagramPNG(paths(7), "PDCCH DCI to grant flow", ["Decoded DCI bits","Field parser","Grant validator","PDSCH/PUSCH reference ID"], result.StrictOk);
rows(7) = localManifestRow(paths(7), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
end

function localWritePNG(path, img)
sixgr.util.ensureDir(path);
img = uint8(img);
[height, width, channels] = size(img);
if channels ~= 3
    error("sixgr:phy:pdcch:BadPNGImage", "Strict PDCCH PNG writer expects RGB image data.");
end
rawPath = char(string(tempname) + ".rgb");
fid = fopen(rawPath, "w");
if fid < 0
    error("sixgr:phy:pdcch:PNGRawOpenFailed", "Cannot open temporary PNG raw buffer.");
end
cleanupClose = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, permute(img, [3 2 1]), "uint8");
clear cleanupClose;
scriptPath = fullfile(localRepoRoot(), "tools", "write_png_from_raw_rgb.py");
cmd = sprintf('python "%s" "%s" "%s" %d %d', localShellEscape(scriptPath), ...
    localShellEscape(rawPath), localShellEscape(char(string(path))), width, height);
[status, out] = system(cmd);
try
    if exist(rawPath, "file") == 2
        delete(rawPath);
    end
catch
end
if status ~= 0 || exist(char(string(path)), "file") ~= 2
    error("sixgr:phy:pdcch:PNGWriteFailed", "Strict PDCCH PNG writer failed: %s", string(out));
end
end

function img = localBaseImage()
img = uint8(255 * ones(480, 720, 3));
img(430:433, 70:660, :) = 190;
img(70:430, 67:70, :) = 190;
end

function img = localHeatImage(M)
M = abs(double(M));
if isempty(M), M = zeros(16, 16); end
M = localNormalizeMatrix(M);
rowIdx = max(1, min(size(M, 1), round(linspace(1, size(M, 1), 420))));
colIdx = max(1, min(size(M, 2), round(linspace(1, size(M, 2), 620))));
M = M(rowIdx, colIdx);
img = localBaseImage();
heat = uint8(cat(3, 255 .* M, 90 .* (1 - M), 255 .* (1 - M)));
img(40:459, 80:699, :) = heat;
end

function img = localBarImage(y)
img = localBaseImage();
y = double(y(:));
y = y(isfinite(y));
if isempty(y), return; end
y = y(1:min(numel(y), 40));
py = localScaleToPixels(y, 420, 80);
x = round(linspace(90, 650, numel(y)));
for ii = 1:numel(y)
    img(max(80, py(ii)):420, max(1, x(ii)-4):min(720, x(ii)+4), 1) = 40;
    img(max(80, py(ii)):420, max(1, x(ii)-4):min(720, x(ii)+4), 2) = 120;
    img(max(80, py(ii)):420, max(1, x(ii)-4):min(720, x(ii)+4), 3) = 220;
end
end

function img = localLineImage(x, y)
img = localBaseImage();
x = double(x(:)); y = double(y(:));
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
if isempty(x), return; end
px = localScaleToPixels(x, 80, 660);
py = localScaleToPixels(y, 420, 80);
for ii = 1:(numel(px)-1)
    img = localDrawLine(img, px(ii), py(ii), px(ii+1), py(ii+1), [30 90 180]);
end
for ii = 1:numel(px)
    img = localDrawDisk(img, px(ii), py(ii), 5, [30 90 180]);
end
end

function vals = localScaleToPixels(v, lo, hi)
v = double(v(:));
mn = min(v); mx = max(v);
if ~(isfinite(mn) && isfinite(mx)) || mx == mn
    vals = round((lo + hi) / 2) * ones(size(v));
else
    vals = round(lo + (v - mn) ./ (mx - mn) .* (hi - lo));
end
end

function M = localNormalizeMatrix(M)
M = double(M);
M(~isfinite(M)) = 0;
mn = min(M(:)); mx = max(M(:));
if mx > mn
    M = (M - mn) ./ (mx - mn);
else
    M = zeros(size(M));
end
end

function img = localDrawLine(img, x1, y1, x2, y2, color)
n = max(2, round(hypot(double(x2-x1), double(y2-y1))));
xs = round(linspace(x1, x2, n));
ys = round(linspace(y1, y2, n));
for ii = 1:n
    img = localDrawDisk(img, xs(ii), ys(ii), 2, color);
end
end

function img = localDrawDisk(img, x, y, r, color)
[xx, yy] = meshgrid(max(1,x-r):min(size(img,2),x+r), max(1,y-r):min(size(img,1),y+r));
mask = (xx - x).^2 + (yy - y).^2 <= r.^2;
rows = yy(mask); cols = xx(mask);
for c = 1:3
    plane = img(:,:,c);
    plane(sub2ind(size(plane), rows, cols)) = uint8(color(c));
    img(:,:,c) = plane;
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

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function out = localShellEscape(value)
out = strrep(char(string(value)), '"', '""');
end
