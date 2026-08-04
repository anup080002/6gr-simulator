function manifest = exportStrictSRSArtifacts(runFolder, result)
%EXPORTSTRICTSRSARTIFACTS Persist strict SRS evidence artifacts.

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
compatMap = struct( ...
    "srs_config_strict_control", fullfile(controlCsvDir, "srs_config_strict.csv"), ...
    "srs_trials_control", fullfile(controlCsvDir, "srs_trials.csv"), ...
    "srs_measurement_table_control", fullfile(controlCsvDir, "srs_measurement_table.csv"), ...
    "srs_config_strict_reports", fullfile(reportCsvDir, "srs_config_strict.csv"), ...
    "srs_trials_reports", fullfile(reportCsvDir, "srs_trials.csv"), ...
    "srs_measurement_table_reports", fullfile(reportCsvDir, "srs_measurement_table.csv"));
compatNames = string(fieldnames(compatMap));
rows = repmat(localManifestRow(), numel(names) + 1 + numel(compatNames), 1);
for ii = 1:numel(names)
    name = names(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.srs.exportStrictSRSArtifacts");
end
airPath = fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv");
strictTrialsForAir = localEnsureSRSLineageColumns(tables.srs_trials);
runtimeTrialsForAir = sixgr.truth.selectCanonicalRuntimeControlTrials( ...
    localEnsureSRSLineageColumns(localReadOptionalTable(airPath)), "srs");
if isempty(runtimeTrialsForAir)
    airTrials = strictTrialsForAir;
else
    % A coupled scenario's air-interface table is primary runtime truth.
    % Standalone strict trials remain in reference_signals/csv and must not
    % be appended into that primary lifecycle.
    airTrials = runtimeTrialsForAir;
end
sixgr.util.csvWriteTable(airPath, airTrials);
rows(numel(names)+1) = localManifestRow(airPath, "text/csv", "csv", height(airTrials), ...
    "sixgr.phy.srs.exportStrictSRSArtifacts");
compatTables = struct( ...
    "srs_config_strict_control", "srs_config_strict", ...
    "srs_trials_control", "srs_trials", ...
    "srs_measurement_table_control", "srs_channel_estimation", ...
    "srs_config_strict_reports", "srs_config_strict", ...
    "srs_trials_reports", "srs_trials", ...
    "srs_measurement_table_reports", "srs_channel_estimation");
for ii = 1:numel(compatNames)
    name = compatNames(ii);
    tableName = string(compatTables.(name));
    if tableName == "srs_trials"
        T = airTrials;
    else
        T = tables.(tableName);
    end
    outPath = compatMap.(name);
    sixgr.util.csvWriteTable(outPath, T);
    rows(numel(names) + 1 + ii) = localManifestRow(outPath, "text/csv", "csv", height(T), ...
        "sixgr.phy.srs.exportStrictSRSArtifacts");
end

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

function T = localEnsureSRSLineageColumns(T)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
if ~ismember("Frame", string(T.Properties.VariableNames))
    T.Frame = NaN(n, 1);
end
if ~ismember("Slot", string(T.Properties.VariableNames))
    T.Slot = NaN(n, 1);
end
if ~ismember("UEIndex", string(T.Properties.VariableNames))
    if ismember("UEId", string(T.Properties.VariableNames))
        T.UEIndex = localNumericColumn(T, "UEId", NaN(n, 1));
    elseif ismember("UEID", string(T.Properties.VariableNames))
        T.UEIndex = localNumericColumn(T, "UEID", NaN(n, 1));
    else
        T.UEIndex = NaN(n, 1);
    end
end
if ~ismember("UEID", string(T.Properties.VariableNames))
    T.UEID = localNumericColumn(T, "UEIndex", NaN(n, 1));
end
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = repmat("UL", n, 1);
end
end

function T = localRuntimeSRSRows(T)
if ~(istable(T) && ~isempty(T))
    return;
end
slot = localNumericColumn(T, "Slot", NaN(height(T), 1));
frame = localNumericColumn(T, "Frame", NaN(height(T), 1));
runtimeMask = isfinite(slot) | isfinite(frame);
T = T(runtimeMask, :);
end

function Tout = localAppendCompatTable(Ta, Tb)
if ~(istable(Ta) && ~isempty(Ta))
    if istable(Tb)
        Tout = Tb;
    else
        Tout = table();
    end
    return;
end
if ~(istable(Tb) && ~isempty(Tb))
    Tout = Ta;
    return;
end
vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
Ta = localEnsureTableVars(Ta, vars, Tb);
Tb = localEnsureTableVars(Tb, vars, Ta);
Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
end

function T = localEnsureTableVars(T, vars, refT)
for i = 1:numel(vars)
    v = char(vars(i));
    if ~ismember(v, T.Properties.VariableNames)
        T.(v) = localDefaultColumnLike(refT, v, height(T));
    end
end
end

function col = localDefaultColumnLike(refT, varName, nRows)
if istable(refT) && ismember(varName, refT.Properties.VariableNames)
    refVal = refT.(varName);
    if isstring(refVal)
        col = strings(nRows, 1);
        return;
    end
    if iscellstr(refVal)
        col = repmat({''}, nRows, 1);
        return;
    end
    if islogical(refVal)
        col = false(nRows, 1);
        return;
    end
    if isnumeric(refVal)
        col = NaN(nRows, 1);
        return;
    end
end
col = strings(nRows, 1);
end

function vals = localNumericColumn(T, varName, defaultValue)
vals = defaultValue;
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(varName));
if isnumeric(raw) || islogical(raw)
    vals = double(raw);
else
    vals = str2double(string(raw));
end
vals = vals(:);
if numel(vals) ~= height(T)
    vals = defaultValue;
end
end

function T = localReadOptionalTable(pathStr)
T = table();
if exist(char(string(pathStr)), "file") ~= 2
    return;
end
try
    opts = detectImportOptions(char(string(pathStr)), "Delimiter", ",");
    opts.VariableNamingRule = "preserve";
    T = readtable(char(string(pathStr)), opts);
catch
    T = table();
end
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
    string(fullfile(figDir, "srs_resource_grid.png"))
    string(fullfile(figDir, "srs_detection_metric_by_trial.png"))
    string(fullfile(figDir, "srs_coverage_summary.png"))
    string(fullfile(figDir, "srs_channel_estimation_nmse.png"))
    string(fullfile(figDir, "srs_low_snr_sweep.png"))
    string(fullfile(figDir, "srs_timing_offset_sweep.png"))
    string(fullfile(figDir, "srs_negative_trial_outcomes.png"))
    string(fullfile(figDir, "srs_strict_flow.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);
gridPower = abs(result.PositiveGrid(:,:,1));
localWriteHeatPNG(paths(1), "SRS resource grid power", gridPower);
rows(1) = localManifestRow(paths(1), "image/png", "figure", numel(gridPower), "sixgr.phy.srs.exportStrictSRSArtifacts");
det = result.ArtifactTables.srs_detection_metrics;
localWriteLinePNG(paths(2), "SRS detection metric by trial", double(det.TrialId), double(det.DetectionMetric));
rows(2) = localManifestRow(paths(2), "image/png", "figure", height(det), "sixgr.phy.srs.exportStrictSRSArtifacts");
cov = result.ArtifactTables.srs_coverage;
localWriteBarPNG(paths(3), "SRS coverage percent", double(cov.CoveragePercent));
rows(3) = localManifestRow(paths(3), "image/png", "figure", height(cov), "sixgr.phy.srs.exportStrictSRSArtifacts");
ch = result.ArtifactTables.srs_channel_estimation;
localWriteLinePNG(paths(4), "SRS channel NMSE by trial", double(ch.TrialId), double(ch.NMSE_dB));
rows(4) = localManifestRow(paths(4), "image/png", "figure", height(ch), "sixgr.phy.srs.exportStrictSRSArtifacts");
low = result.ArtifactTables.srs_low_snr_sweep;
localWriteLinePNG(paths(5), "SRS low-SNR detection probability", double(low.SNRdB), double(low.DetectionProbability));
rows(5) = localManifestRow(paths(5), "image/png", "figure", height(low), "sixgr.phy.srs.exportStrictSRSArtifacts");
tim = result.ArtifactTables.srs_timing_offset_sweep;
localWriteLinePNG(paths(6), "SRS timing error sweep", double(tim.InjectedTimingOffsetSamples), abs(double(tim.MeanTimingErrorSamples)));
rows(6) = localManifestRow(paths(6), "image/png", "figure", height(tim), "sixgr.phy.srs.exportStrictSRSArtifacts");
neg = result.ArtifactTables.srs_negative_trials;
localWriteBarPNG(paths(7), "SRS negative trial expected failures", double(neg.NegativeExpectedOk));
rows(7) = localManifestRow(paths(7), "image/png", "figure", height(neg), "sixgr.phy.srs.exportStrictSRSArtifacts");
sixgr.visual.writeFlowDiagramPNG(paths(8), "Strict SRS channel sounding flow", ...
    ["nrSRS generation","UL OFDM waveform","gNB resource extraction","LS/MMSE/DFT channel estimate","coverage gate"], result.StrictOk);
rows(8) = localManifestRow(paths(8), "image/png", "figure", NaN, "sixgr.phy.srs.exportStrictSRSArtifacts");
end

function localWriteLinePNG(path, titleText, x, y)
x = double(x(:));
y = double(y(:));
mask = isfinite(x) & isfinite(y);
x = x(mask);
y = y(mask);
fig = localPlotFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
if isempty(x)
    axis(ax, "off"); text(ax, 0.5, 0.5, "No finite runtime samples", "HorizontalAlignment", "center");
else
    plot(ax, x, y, "-o", "LineWidth", 1.6, "MarkerSize", 5);
    grid(ax, "on");
end
title(ax, string(titleText), "Interpreter", "none");
sixgr.util.exportFigureArtifact(fig, path, "Resolution", 170);
end

function localWriteBarPNG(path, titleText, y)
y = double(y(:));
y = y(isfinite(y));
fig = localPlotFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
if isempty(y)
    axis(ax, "off"); text(ax, 0.5, 0.5, "No finite runtime samples", "HorizontalAlignment", "center");
else
    bar(ax, y, "FaceColor", [0.19 0.49 0.49]); grid(ax, "on");
end
title(ax, string(titleText), "Interpreter", "none");
sixgr.util.exportFigureArtifact(fig, path, "Resolution", 170);
end

function localWriteHeatPNG(path, titleText, M)
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
fig = localPlotFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
imagesc(ax, M); axis(ax, "xy"); colorbar(ax); colormap(ax, "turbo");
title(ax, string(titleText), "Interpreter", "none");
sixgr.util.exportFigureArtifact(fig, path, "Resolution", 170);
end

function fig = localPlotFigure()
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 820 480]);
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
