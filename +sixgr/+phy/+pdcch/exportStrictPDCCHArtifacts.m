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
sixgr.truth.sanitizeLLSArtifactCSVs(runFolder, ...
    "OnlyPaths", [string(struct2cell(csvMap)); string(airPath)]);

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
[figureRows, figurePaths] = localWriteFigures(figDir, result, csvMap);
plotLineagePath = fullfile(layout.ControlCSVDir, "pdcch_plot_lineage.csv");
sixgr.visual.writeComponentPlotLineage(runFolder, plotLineagePath, ...
    ["pdcch_coreset_resource_grid"; "pdcch_candidate_metrics"; ...
    "pdcch_wrong_rnti_rejections"; "pdcch_false_alarm_probability"; ...
    "pdcch_low_snr_detection_probability"; "pdcch_decode_flow"; ...
    "pdcch_dci_to_grant_flow"], figurePaths, [ ...
    string(csvMap.pdcch_config_strict); string(csvMap.pdcch_candidates); ...
    string(csvMap.pdcch_wrong_rnti_trials); string(csvMap.pdcch_false_alarm_sweep); ...
    string(csvMap.pdcch_low_snr_sweep); string(csvMap.pdcch_trials); ...
    string(csvMap.pdcch_dci_fields) + "|" + string(csvMap.pdcch_grant_validation)], ...
    "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
plotLineageRow = localManifestRow(plotLineagePath, "text/csv", "plot_lineage", 7, ...
    "sixgr.phy.pdcch.exportStrictPDCCHArtifacts");
manifestRows = [rows(:); jsonRows(:); textRows(:); binaryRows(:); figureRows(:); plotLineageRow];
manifestPath = fullfile(layout.ControlCSVDir, "pdcch_strict_artifact_manifest.csv");
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

function [rows, paths] = localWriteFigures(figDir, result, csvMap)
paths = [
    string(fullfile(figDir, "pdcch_coreset_resource_grid.png"))
    string(fullfile(figDir, "pdcch_candidate_metrics.png"))
    string(fullfile(figDir, "pdcch_wrong_rnti_rejections.png"))
    string(fullfile(figDir, "pdcch_false_alarm_probability.png"))
    string(fullfile(figDir, "pdcch_low_snr_detection_probability.png"))
    string(fullfile(figDir, "pdcch_decode_flow.png"))
    string(fullfile(figDir, "pdcch_dci_to_grant_flow.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);

% Figure publication is a single evidence transaction.  A renderer error
% must not leave a prefix of apparently valid but unmanifested PNGs in the
% run folder.  Remove stale targets before starting and delete every target
% again unless the complete seven-figure set was produced successfully.
for ii = 1:numel(paths)
    if exist(char(paths(ii)), "file") == 2
        delete(char(paths(ii)));
    end
end
committed = false;
cleanupPartial = onCleanup(@localCleanupUncommittedFigures); %#ok<NASGU>

localExportHeatmap(paths(1), abs(result.PositiveGrid(:,:,1)), ...
    "PDCCH CORESET resource-grid magnitude", "OFDM symbol index", "subcarrier index");
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_config_strict);
cand = result.ArtifactTables.pdcch_candidates;
localExportCandidateMetrics(paths(2), cand);
rows(2) = localManifestRow(paths(2), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_candidates);
wr = result.ArtifactTables.pdcch_wrong_rnti_trials;
localExportBars(paths(3), double(wr.WrongRNTIRejectCount), ...
    "Wrong-RNTI candidate rejections", "negative trial", "rejected candidates");
rows(3) = localManifestRow(paths(3), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_wrong_rnti_trials);
fa = result.ArtifactTables.pdcch_false_alarm_sweep;
localExportProbabilitySweep(paths(4), fa, "FalseAlarmProbability", ...
    "CILower", "CIUpper", "TargetFalseAlarmProbability", ...
    "PDCCH false-alarm probability", "SNR (dB)", "false-alarm probability");
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_false_alarm_sweep);
ls = result.ArtifactTables.pdcch_low_snr_sweep;
localExportProbabilitySweep(paths(5), ls, "DetectionProbability", ...
    "DetectionCILower", "DetectionCIUpper", "", ...
    "PDCCH low-SNR detection probability", "SNR (dB)", "detection probability");
rows(5) = localManifestRow(paths(5), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_low_snr_sweep);
sixgr.visual.writeFlowDiagramPNG(paths(6), "Strict PDCCH blind decode", ["PDCCH waveform","CORESET/search-space candidates","RNTI CRC + DCI decode","Score after decode"], result.StrictOk);
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", csvMap.pdcch_trials);
sixgr.visual.writeFlowDiagramPNG(paths(7), "PDCCH DCI to grant flow", ["Decoded DCI bits","Field parser","Grant validator","PDSCH/PUSCH reference ID"], result.StrictOk);
rows(7) = localManifestRow(paths(7), "image/png", "figure", NaN, "sixgr.phy.pdcch.exportStrictPDCCHArtifacts", ...
    string(csvMap.pdcch_dci_fields) + "|" + string(csvMap.pdcch_grant_validation));
committed = true;
clear cleanupPartial;

    function localCleanupUncommittedFigures()
        if committed
            return;
        end
        for jj = 1:numel(paths)
            if exist(char(paths(jj)), "file") == 2
                delete(char(paths(jj)));
            end
        end
    end
end

function localExportHeatmap(path, values, plotTitle, xLabel, yLabel)
values = double(values);
if isempty(values) || ~any(isfinite(values(:)))
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "Cannot publish a PDCCH heat map without finite measured values.");
end
localExportMeasuredFigure(path, @render);
    function render()
        imagesc(0:size(values,2)-1, 0:size(values,1)-1, values);
        axis xy tight;
        colormap(parula(256));
        colorbar;
        title(plotTitle);
        xlabel(xLabel);
        ylabel(yLabel);
    end
end

function localExportCandidateMetrics(path, T)
if isempty(T) || ~ismember("Metric", string(T.Properties.VariableNames))
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "Cannot publish PDCCH candidate metrics without measured candidate rows.");
end
y = double(T.Metric);
x = (1:height(T)).';
valid = isfinite(y);
x = x(valid); y = y(valid);
if isempty(y)
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "PDCCH candidate metrics contain no finite measurements.");
end
selected = false(height(T),1);
if ismember("SelectedCandidate", string(T.Properties.VariableNames))
    selected = logical(T.SelectedCandidate);
end
selected = selected(valid);
localExportMeasuredFigure(path, @render);
    function render()
        scatter(x, y, 12, [0.10 0.45 0.75], "filled", ...
            "DisplayName", "blind-search candidate");
        hold on;
        if any(selected)
            scatter(x(selected), y(selected), 38, [0.85 0.20 0.15], "filled", ...
                "DisplayName", "selected candidate");
            legend("Location", "best");
        end
        title("PDCCH blind-search candidate metrics");
        xlabel("candidate evidence row");
        ylabel("decoder metric");
        grid on;
    end
end

function localExportBars(path, y, plotTitle, xLabel, yLabel)
y = double(y(:));
y = y(isfinite(y));
if isempty(y)
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "Cannot publish a PDCCH bar chart without finite measured values.");
end
localExportMeasuredFigure(path, @render);
    function render()
        bar((1:numel(y)).', y, 0.72, "FaceColor", [0.10 0.45 0.75]);
        title(plotTitle);
        xlabel(xLabel);
        ylabel(yLabel);
        grid on;
    end
end

function localExportProbabilitySweep(path, T, valueField, lowerField, upperField, ...
        targetField, plotTitle, xLabel, yLabel)
required = ["SNRdB", string(valueField)];
if isempty(T) || ~all(ismember(required, string(T.Properties.VariableNames)))
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "Cannot publish %s without measured sweep values.", plotTitle);
end
x = double(T.SNRdB);
y = double(T.(char(valueField)));
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
[x, order] = sort(x); y = y(order);
if isempty(x)
    error("sixgr:phy:pdcch:MissingPlotEvidence", ...
        "Cannot publish %s without finite sweep values.", plotTitle);
end
lower = nan(size(y)); upper = nan(size(y));
if ismember(string(lowerField), string(T.Properties.VariableNames))
    raw = double(T.(char(lowerField))); lower = raw(valid); lower = lower(order);
end
if ismember(string(upperField), string(T.Properties.VariableNames))
    raw = double(T.(char(upperField))); upper = raw(valid); upper = upper(order);
end
target = NaN;
if strlength(string(targetField)) > 0 && ...
        ismember(string(targetField), string(T.Properties.VariableNames))
    raw = double(T.(char(targetField)));
    raw = raw(isfinite(raw));
    if ~isempty(raw), target = raw(1); end
end
localExportMeasuredFigure(path, @render);
    function render()
        if all(isfinite(lower) & isfinite(upper))
            errorbar(x, y, max(0, y-lower), max(0, upper-y), "o-", ...
                "LineWidth", 1.5, "MarkerFaceColor", [0.10 0.45 0.75], ...
                "DisplayName", "measured (confidence interval)");
        else
            plot(x, y, "o-", "LineWidth", 1.5, ...
                "MarkerFaceColor", [0.10 0.45 0.75], "DisplayName", "measured");
        end
        hold on;
        if isfinite(target)
            yline(target, "--", "target", "LineWidth", 1.2, ...
                "DisplayName", "configured target");
        end
        ylim([0 1]);
        title(plotTitle);
        xlabel(xLabel);
        ylabel(yLabel);
        grid on;
        legend("Location", "best");
    end
end

function localExportMeasuredFigure(path, plotter)
sixgr.util.ensureDir(path);
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 960 600]);
cleanupFigure = onCleanup(@() close(fig)); %#ok<NASGU>
plotter();
axesHandles = findall(fig, "Type", "axes");
set(axesHandles, "Color", "w", "XColor", [0.12 0.16 0.20], ...
    "YColor", [0.12 0.16 0.20], "FontSize", 10, "LineWidth", 0.8);
set(findall(fig, "Type", "text"), "Color", [0.08 0.12 0.16]);
sixgr.util.exportFigureArtifact(fig, char(string(path)), "Resolution", 150);
end

function row = localManifestRow(path, mime, kind, rowCount, producer, sourceCSV)
if nargin == 0
    path = ""; mime = ""; kind = ""; rowCount = NaN; producer = ""; sourceCSV = "";
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
hash = sixgr.rrc.asn1.asn1SHA256Hex(data);
end
