function manifest = exportStrictPRACHArtifacts(runFolder, result)
%EXPORTSTRICTPRACHARTIFACTS Persist strict PRACH evidence artifacts.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
jsonDir = fullfile(layout.ReportDir, "json");
textDir = fullfile(layout.ReportDir, "text");
binaryDir = fullfile(layout.ReportDir, "binary");
figDir = fullfile(layout.ReportDir, "figures");
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(textDir);
sixgr.util.ensureFolder(binaryDir);
sixgr.util.ensureFolder(figDir);

tables = result.ArtifactTables;
csvMap = struct( ...
    "prach_config_strict", fullfile(layout.ControlCSVDir, "prach_config_strict.csv"), ...
    "prach_trials", fullfile(layout.ControlCSVDir, "prach_strict_trials.csv"), ...
    "prach_detection_candidates", fullfile(layout.ControlCSVDir, "prach_detection_candidates.csv"), ...
    "prach_restricted_set_mapping", fullfile(layout.ControlCSVDir, "prach_restricted_set_mapping.csv"), ...
    "prach_root_sequence_budget", fullfile(layout.ControlCSVDir, "prach_root_sequence_budget.csv"), ...
    "prach_zcz_cyclic_shift_mapping", fullfile(layout.ControlCSVDir, "prach_zcz_cyclic_shift_mapping.csv"), ...
    "prach_missed_detection_sweep", fullfile(layout.ControlCSVDir, "prach_missed_detection_sweep.csv"), ...
    "prach_false_alarm_sweep", fullfile(layout.ControlCSVDir, "prach_false_alarm_sweep.csv"), ...
    "prach_timing_offset_sweep", fullfile(layout.ControlCSVDir, "prach_timing_offset_sweep.csv"), ...
    "prach_frequency_offset_sweep", fullfile(layout.ControlCSVDir, "prach_frequency_offset_sweep.csv"), ...
    "prach_collision_trials", fullfile(layout.ControlCSVDir, "prach_collision_trials.csv"), ...
    "prach_multi_occasion_trials", fullfile(layout.ControlCSVDir, "prach_multi_occasion_trials.csv"), ...
    "prach_negative_trials", fullfile(layout.ControlCSVDir, "prach_negative_trials.csv"), ...
    "prach_oracle_guard", fullfile(layout.ControlCSVDir, "prach_oracle_guard.csv"));
csvNames = string(fieldnames(csvMap));
rows = repmat(localManifestRow(), numel(csvNames), 1);
for ii = 1:numel(csvNames)
    name = csvNames(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.prach.exportStrictPRACHArtifacts");
end
resourceGridPath = fullfile(layout.ControlCSVDir, "prach_resource_grid.csv");
resourceGrid = localResourceGridTable(result);
sixgr.util.csvWriteTable(resourceGridPath, resourceGrid);
resourceGridRow = localManifestRow(resourceGridPath, "text/csv", "csv", ...
    height(resourceGrid), "sixgr.phy.prach.exportStrictPRACHArtifacts");

% JSON bindings and plot lineage contain hashes of these primary CSVs. Make
% their browser-facing bytes final before any dependent hash is recorded.
sourceCSVPaths = [string(struct2cell(csvMap)); string(resourceGridPath)];
sixgr.truth.sanitizeLLSArtifactCSVs(runFolder, "OnlyPaths", sourceCSVPaths);

jsonPayloads = localJsonPayloads(result, csvMap);
jsonMap = struct( ...
    "prach_config_binding", fullfile(jsonDir, "prach_config_binding.json"), ...
    "prach_detection_summary", fullfile(jsonDir, "prach_detection_summary.json"), ...
    "prach_conformance_summary", fullfile(jsonDir, "prach_conformance_summary.json"), ...
    "prach_false_alarm_summary", fullfile(jsonDir, "prach_false_alarm_summary.json"), ...
    "prach_missed_detection_summary", fullfile(jsonDir, "prach_missed_detection_summary.json"), ...
    "prach_restricted_set_summary", fullfile(jsonDir, "prach_restricted_set_summary.json"), ...
    "prach_toolbox_capabilities", fullfile(jsonDir, "prach_toolbox_capabilities.json"));
jsonNames = string(fieldnames(jsonMap));
jsonRows = repmat(localManifestRow(), numel(jsonNames), 1);
for ii = 1:numel(jsonNames)
    name = jsonNames(ii);
    sixgr.util.jsonWrite(jsonMap.(name), jsonPayloads.(name));
    jsonRows(ii) = localManifestRow(jsonMap.(name), "application/json", "json", NaN, ...
        "sixgr.phy.prach.exportStrictPRACHArtifacts");
end

textRows = localWriteTextArtifacts(textDir, result);
binaryRows = localWriteBinaryArtifacts(binaryDir, result);
[figureRows, figurePaths] = localWriteFigures(figDir, result, csvMap, resourceGridPath);
plotLineagePath = fullfile(layout.ControlCSVDir, "prach_plot_lineage.csv");
sixgr.visual.writeComponentPlotLineage(runFolder, plotLineagePath, [ ...
    "prach_resource_grid"; "prach_correlation_positive"; ...
    "prach_correlation_noise_only"; "prach_false_alarm_probability"; ...
    "prach_missed_detection_probability"; "prach_timing_error_histogram"; ...
    "prach_restricted_set_comparison"; "prach_collision_peaks"; ...
    "prach_multi_occasion_map"; "prach_detection_flow"], figurePaths, [ ...
    string(resourceGridPath); string(csvMap.prach_detection_candidates); ...
    string(csvMap.prach_detection_candidates); string(csvMap.prach_false_alarm_sweep); ...
    string(csvMap.prach_missed_detection_sweep); string(csvMap.prach_timing_offset_sweep); ...
    string(csvMap.prach_restricted_set_mapping); string(csvMap.prach_collision_trials); ...
    string(csvMap.prach_multi_occasion_trials); string(csvMap.prach_trials)], ...
    "sixgr.phy.prach.exportStrictPRACHArtifacts");
plotLineageRow = localManifestRow(plotLineagePath, "text/csv", "plot_lineage", 10, ...
    "sixgr.phy.prach.exportStrictPRACHArtifacts");
manifestRows = [rows(:); resourceGridRow; jsonRows(:); textRows(:); ...
    binaryRows(:); figureRows(:); plotLineageRow];
manifestPath = fullfile(layout.ControlCSVDir, "prach_strict_artifact_manifest.csv");
manifest = sixgr.artifact.writeIntegrityManifest(manifestPath, manifestRows);
end

function payloads = localJsonPayloads(result, csvMap)
base = localEnvelope(result, "strict_prach_waveform_validation", csvMap.prach_trials);
payloads = struct();
payloads.prach_config_binding = base;
payloads.prach_config_binding.ConfigHash = string(result.ConfigHash);
payloads.prach_config_binding.BindingSource = string(result.Config.BindingSource);
payloads.prach_config_binding.SourceCSVHash = localFileSHA256(csvMap.prach_config_strict);
payloads.prach_detection_summary = base;
payloads.prach_detection_summary.SourceCSVHash = localFileSHA256(csvMap.prach_trials);
payloads.prach_detection_summary.PositiveStrictOkCount = result.DetectionSummary.PositiveStrictOkCount;
payloads.prach_conformance_summary = result.DetectionSummary;
payloads.prach_conformance_summary.source_csv = string(csvMap.prach_trials);
payloads.prach_conformance_summary.source_csv_sha256 = localFileSHA256(csvMap.prach_trials);
payloads.prach_false_alarm_summary = base;
payloads.prach_false_alarm_summary.source_csv = string(csvMap.prach_false_alarm_sweep);
payloads.prach_false_alarm_summary.source_csv_sha256 = localFileSHA256(csvMap.prach_false_alarm_sweep);
payloads.prach_false_alarm_summary.Rows = height(result.ArtifactTables.prach_false_alarm_sweep);
payloads.prach_missed_detection_summary = base;
payloads.prach_missed_detection_summary.source_csv = string(csvMap.prach_missed_detection_sweep);
payloads.prach_missed_detection_summary.source_csv_sha256 = localFileSHA256(csvMap.prach_missed_detection_sweep);
payloads.prach_missed_detection_summary.Rows = height(result.ArtifactTables.prach_missed_detection_sweep);
payloads.prach_restricted_set_summary = base;
payloads.prach_restricted_set_summary.source_csv = string(csvMap.prach_restricted_set_mapping);
payloads.prach_restricted_set_summary.source_csv_sha256 = localFileSHA256(csvMap.prach_restricted_set_mapping);
payloads.prach_restricted_set_summary.ValidRows = sum(logical(result.ArtifactTables.prach_restricted_set_mapping.Valid));
payloads.prach_toolbox_capabilities = result.ToolboxCapabilities;
payloads.prach_toolbox_capabilities.RunId = string(result.RunId);
payloads.prach_toolbox_capabilities.scenario = string(result.ScenarioName);
payloads.prach_toolbox_capabilities.implementation_status = "strict_toolbox_capability_report";
end

function payload = localEnvelope(result, status, sourceCsv)
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = string(status);
payload.ProducerModule = "sixgr.phy.prach.exportStrictPRACHArtifacts";
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
cfgDump = fullfile(textDir, "prach_config_dump.txt");
hashDump = fullfile(textDir, "prach_trial_hashes.txt");
sixgr.util.writeTextFile(cfgDump, evalc("disp(result.Config.ConfigExport)"));
T = result.ArtifactTables.prach_trials;
txt = strjoin(string(T.TrialId) + "," + string(T.WaveformHash), newline);
sixgr.util.writeTextFile(hashDump, txt);
rows = [
    localManifestRow(cfgDump, "text/plain", "text", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts")
    localManifestRow(hashDump, "text/plain", "text", height(T), "sixgr.phy.prach.exportStrictPRACHArtifacts")];
end

function rows = localWriteBinaryArtifacts(binaryDir, result)
posPath = fullfile(binaryDir, "prach_positive_waveform_iq.bin");
noisePath = fullfile(binaryDir, "prach_noise_only_waveform_iq.bin");
localWriteIQ(posPath, result.PositiveWaveform);
localWriteIQ(noisePath, result.NoiseOnlyWaveform);
rows = [
    localManifestRow(posPath, "application/octet-stream", "binary", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts")
    localManifestRow(noisePath, "application/octet-stream", "binary", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts")];
end

function localWriteIQ(path, wave)
sixgr.util.ensureDir(path);
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = single([real(wave(:)).'; imag(wave(:)).']);
fwrite(fid, data(:), "single");
end

function [rows, paths] = localWriteFigures(figDir, result, csvMap, resourceGridPath)
paths = [
    string(fullfile(figDir, "prach_resource_grid.png"))
    string(fullfile(figDir, "prach_correlation_positive.png"))
    string(fullfile(figDir, "prach_correlation_noise_only.png"))
    string(fullfile(figDir, "prach_false_alarm_probability.png"))
    string(fullfile(figDir, "prach_missed_detection_probability.png"))
    string(fullfile(figDir, "prach_timing_error_histogram.png"))
    string(fullfile(figDir, "prach_restricted_set_comparison.png"))
    string(fullfile(figDir, "prach_collision_peaks.png"))
    string(fullfile(figDir, "prach_multi_occasion_map.png"))
    string(fullfile(figDir, "prach_detection_flow.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);

localWritePNG(paths(1), localHeatImage(abs(result.PositiveGrid)));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", resourceGridPath);

cand = result.ArtifactTables.prach_detection_candidates;
trialT = result.ArtifactTables.prach_trials;
posTrial = trialT.TrialId(string(trialT.TrialType) == "positive_high_snr");
if isempty(posTrial), posTrial = trialT.TrialId(1); end
mask = cand.TrialId == posTrial(1);
localWritePNG(paths(2), localBarImage(double(cand.Metric(mask))));
rows(2) = localManifestRow(paths(2), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_detection_candidates);

noiseTrial = trialT.TrialId(string(trialT.TrialType) == "false_alarm_sweep");
if isempty(noiseTrial), noiseTrial = trialT.TrialId(end); end
mask = cand.TrialId == noiseTrial(1);
localWritePNG(paths(3), localBarImage(double(cand.Metric(mask))));
rows(3) = localManifestRow(paths(3), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_detection_candidates);

fa = result.ArtifactTables.prach_false_alarm_sweep;
localWritePNG(paths(4), localLineImage(double(fa.SNRdB), double(fa.FalseAlarmProbability)));
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_false_alarm_sweep);

md = result.ArtifactTables.prach_missed_detection_sweep;
localWritePNG(paths(5), localLineImage(double(md.SNRdB), double(md.MissedDetectionProbability)));
rows(5) = localManifestRow(paths(5), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_missed_detection_sweep);

tt = result.ArtifactTables.prach_timing_offset_sweep;
localWritePNG(paths(6), localHistImage(double(tt.MeanTimingErrorSamples)));
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_timing_offset_sweep);

map = result.ArtifactTables.prach_restricted_set_mapping;
[~, ~, grp] = unique(string(map.RestrictedSet));
ncs = splitapply(@(x) x(1), double(map.NCS), grp);
localWritePNG(paths(7), localBarImage(ncs));
rows(7) = localManifestRow(paths(7), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_restricted_set_mapping);

coll = result.ArtifactTables.prach_collision_trials;
localWritePNG(paths(8), localBarImage(double(coll.DetectedCandidateCount)));
rows(8) = localManifestRow(paths(8), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_collision_trials);

mo = result.ArtifactTables.prach_multi_occasion_trials;
localWritePNG(paths(9), localScatterImage(double(mo.OccasionSlot), double(mo.RARNTI)));
rows(9) = localManifestRow(paths(9), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_multi_occasion_trials);

sixgr.visual.writeFlowDiagramPNG(paths(10), "Strict PRACH detection flow", ...
    ["nrPRACH waveform","AWGN / offsets","Rx correlation search","Score after detect"], result.StrictOk);
rows(10) = localManifestRow(paths(10), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_trials);
end

function T = localResourceGridTable(result)
grid = complex(sixgr.util.structGet(result, "PositiveGrid", complex(zeros(0, 0))));
[subcarrier, symbol, port] = ndgrid(0:size(grid, 1)-1, ...
    0:size(grid, 2)-1, 0:size(grid, 3)-1);
samples = grid(:);
T = table(subcarrier(:), symbol(:), port(:), real(samples), imag(samples), ...
    abs(samples), abs(samples) > 0, repmat("runtime_nr_prach_grid", numel(samples), 1), ...
    'VariableNames', {'SubcarrierIndex','OFDMSymbolIndex','PortIndex', ...
    'GridReal','GridImag','GridMagnitude','Occupied','truth_status'});
end

function localWritePNG(path, img)
targetPath = char(string(path));
sixgr.util.ensureDir(targetPath);
img = uint8(img);
[~, ~, channels] = size(img);
if channels ~= 3
    error("sixgr:phy:prach:BadPNGImage", "Strict PRACH PNG writer expects RGB image data.");
end

targetDir = fileparts(targetPath);
if isempty(targetDir)
    targetDir = pwd;
end
tempPath = char(string(tempname(targetDir)) + ".png");
cleanupTemp = onCleanup(@() localDeleteFile(tempPath)); %#ok<NASGU>
try
    imwrite(img, tempPath, "png");
catch ME
    throwAsCaller(MException("sixgr:phy:prach:PNGWriteFailed", ...
        "Strict PRACH PNG encoding failed for %s: %s", targetPath, ME.message));
end

info = dir(tempPath);
if isempty(info) || info(1).bytes <= 0
    error("sixgr:phy:prach:PNGWriteFailed", ...
        "Strict PRACH PNG encoder produced no data for %s.", targetPath);
end

lastMessage = "";
for attempt = 1:12
    [moved, message] = movefile(tempPath, targetPath, "f");
    if moved
        if exist(targetPath, "file") == 2
            finalInfo = dir(targetPath);
            if ~isempty(finalInfo) && finalInfo(1).bytes > 0
                return;
            end
        end
        lastMessage = "destination exists but is empty";
    else
        lastMessage = string(message);
    end
    pause(min(0.05 * 2^(attempt - 1), 1.0));
end
error("sixgr:phy:prach:PNGWriteFailed", ...
    "Strict PRACH PNG publication failed for %s after 12 attempts: %s", ...
    targetPath, lastMessage);
end

function localDeleteFile(path)
if exist(path, "file") ~= 2
    return;
end
try
    delete(path);
catch
    % Best-effort cleanup only; the primary write or move error is authoritative.
end
end

function img = localBaseImage()
img = uint8(255 * ones(480, 720, 3));
img(430:433, 70:660, :) = 190;
img(70:430, 67:70, :) = 190;
end

function img = localHeatImage(M)
M = double(M);
M = M(isfinite(M));
if isempty(M)
    M = zeros(16, 16);
else
    M = abs(double(M));
end
if isvector(M)
    M = reshape(M(:), [], 1);
end
M = localNormalizeMatrix(M);
rowIdx = max(1, min(size(M, 1), round(linspace(1, size(M, 1), 420))));
colIdx = max(1, min(size(M, 2), round(linspace(1, size(M, 2), 620))));
M = M(rowIdx, colIdx);
img = localBaseImage();
heat = uint8(cat(3, 255 .* M, 80 .* (1 - M), 255 .* (1 - M)));
img(40:459, 80:699, :) = heat;
end

function img = localLineImage(x, y)
img = localBaseImage();
x = double(x(:)); y = double(y(:));
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
if isempty(x)
    return;
end
px = localScaleToPixels(x, 80, 660);
py = localScaleToPixels(y, 420, 80);
for ii = 1:(numel(px)-1)
    img = localDrawLine(img, px(ii), py(ii), px(ii+1), py(ii+1), [30 90 180]);
end
for ii = 1:numel(px)
    img = localDrawDisk(img, px(ii), py(ii), 5, [30 90 180]);
end
end

function img = localBarImage(values)
img = localBaseImage();
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    return;
end
values = localNormalizeVector(values);
n = numel(values);
barW = max(2, floor(560 / max(n, 1)));
for ii = 1:n
    x0 = 80 + (ii - 1) * barW;
    x1 = min(660, x0 + max(1, barW - 2));
    y1 = 430;
    y0 = max(80, round(430 - values(ii) * 330));
    img(y0:y1, x0:x1, 1) = 35;
    img(y0:y1, x0:x1, 2) = 120;
    img(y0:y1, x0:x1, 3) = 200;
end
end

function img = localHistImage(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    img = localBaseImage();
    return;
end
edges = linspace(min(values), max(values) + eps, min(12, max(3, numel(values) + 1)));
counts = histcounts(values, edges);
img = localBarImage(counts(:));
end

function img = localScatterImage(x, y)
img = localBaseImage();
x = double(x(:)); y = double(y(:));
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
if isempty(x)
    return;
end
px = localScaleToPixels(x, 80, 660);
py = localScaleToPixels(y, 420, 80);
for ii = 1:numel(px)
    img = localDrawDisk(img, px(ii), py(ii), 6, [180 70 30]);
end
end

function M = localNormalizeMatrix(M)
M = double(M);
mn = min(M(:), [], "omitnan");
mx = max(M(:), [], "omitnan");
if ~isfinite(mn) || ~isfinite(mx) || abs(mx - mn) < eps
    M = zeros(size(M));
else
    M = (M - mn) ./ (mx - mn);
end
end

function v = localNormalizeVector(v)
mn = min(v, [], "omitnan");
mx = max(v, [], "omitnan");
if ~isfinite(mn) || ~isfinite(mx) || abs(mx - mn) < eps
    v = ones(size(v));
else
    v = (v - mn) ./ (mx - mn);
end
end

function p = localScaleToPixels(v, lo, hi)
v = double(v(:));
mn = min(v, [], "omitnan");
mx = max(v, [], "omitnan");
if ~isfinite(mn) || ~isfinite(mx) || abs(mx - mn) < eps
    p = round((lo + hi) / 2) * ones(size(v));
else
    p = round(lo + (v - mn) ./ (mx - mn) .* (hi - lo));
end
p = max(min(p, max(lo, hi)), min(lo, hi));
end

function img = localDrawLine(img, x0, y0, x1, y1, color)
n = max(abs(x1 - x0), abs(y1 - y0)) + 1;
xs = round(linspace(x0, x1, n));
ys = round(linspace(y0, y1, n));
for ii = 1:numel(xs)
    img = localDrawDisk(img, xs(ii), ys(ii), 2, color);
end
end

function img = localDrawDisk(img, x, y, r, color)
[h, w, ~] = size(img);
x = round(x); y = round(y); r = round(r);
xr = max(1, x-r):min(w, x+r);
yr = max(1, y-r):min(h, y+r);
[X, Y] = meshgrid(xr, yr);
mask = (X - x).^2 + (Y - y).^2 <= r.^2;
for cc = 1:3
    plane = img(yr, xr, cc);
    plane(mask) = uint8(color(cc));
    img(yr, xr, cc) = plane;
end
end

function localPlotCorrelation(~, candT, trialType, trialT, selectedOnly)
trialIds = trialT.TrialId(string(trialT.TrialType) == string(trialType));
if isempty(trialIds)
    trialIds = trialT.TrialId(1);
end
mask = candT.TrialId == trialIds(1);
if selectedOnly
    mask = mask & candT.SelectedCandidate;
end
if ~any(mask)
    mask = candT.TrialId == trialIds(1);
end
stem(double(candT.PreambleIndexCandidate(mask)), double(candT.Metric(mask)), "filled");
hold on;
yline(double(candT.Threshold(find(mask, 1, "first"))), "--r", "threshold");
grid on; xlabel("preamble candidate"); ylabel("correlation metric");
title("PRACH measured candidate correlation");
hold off;
end

function row = localManifestRow(path, mime, kind, rowCount, producer, sourceCSV)
if nargin == 0
    path = "";
    mime = "";
    kind = "";
    rowCount = NaN;
    producer = "";
    sourceCSV = "";
elseif nargin < 6
    sourceCSV = "";
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
    "SHA256", localFileSHA256(path), "ProducerModule", string(producer), ...
    "SourceCSV", string(sourceCSV));
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
