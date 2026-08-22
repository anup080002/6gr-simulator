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

% csvWriteTable already applies the canonical structural-column pruning to
% these in-memory producer tables before atomic publication.  Re-reading
% the PRACH candidate/trial CSVs here used tens of gigabytes of memory for
% large statistical campaigns without changing a byte.  Treat the bytes
% just published above as final and hash those exact files below.

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
    "sixgr.phy.prach.exportStrictPRACHArtifacts", ...
    "SourcesAlreadyFinalized", true);
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

localExportPRACHFigure(paths(1), @() localPlotResourceGrid(result.PositiveGrid));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", resourceGridPath);

cand = result.ArtifactTables.prach_detection_candidates;
trialT = result.ArtifactTables.prach_trials;
posTrial = trialT.TrialId(string(trialT.TrialType) == "positive_high_snr");
if isempty(posTrial), posTrial = trialT.TrialId(1); end
mask = cand.TrialId == posTrial(1);
localExportPRACHFigure(paths(2), @() localPlotCandidateMetrics(cand(mask, :), ...
    "PRACH correlation: preamble present"));
rows(2) = localManifestRow(paths(2), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_detection_candidates);

noiseTrial = trialT.TrialId(string(trialT.TrialType) == "false_alarm_sweep");
if isempty(noiseTrial), noiseTrial = trialT.TrialId(end); end
mask = cand.TrialId == noiseTrial(1);
localExportPRACHFigure(paths(3), @() localPlotCandidateMetrics(cand(mask, :), ...
    "PRACH correlation: noise-only occasion"));
rows(3) = localManifestRow(paths(3), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_detection_candidates);

fa = result.ArtifactTables.prach_false_alarm_sweep;
localExportPRACHFigure(paths(4), @() localPlotFalseAlarmSweep(fa));
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_false_alarm_sweep);

md = result.ArtifactTables.prach_missed_detection_sweep;
localExportPRACHFigure(paths(5), @() localPlotMissedDetectionSweep(md));
rows(5) = localManifestRow(paths(5), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_missed_detection_sweep);

tt = result.ArtifactTables.prach_timing_offset_sweep;
localExportPRACHFigure(paths(6), @() localPlotTimingSweep(tt));
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_timing_offset_sweep);

map = result.ArtifactTables.prach_restricted_set_mapping;
localExportPRACHFigure(paths(7), @() localPlotRestrictedSetMapping(map));
rows(7) = localManifestRow(paths(7), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_restricted_set_mapping);

coll = result.ArtifactTables.prach_collision_trials;
localExportPRACHFigure(paths(8), @() localPlotCollisionTrials(coll));
rows(8) = localManifestRow(paths(8), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_collision_trials);

mo = result.ArtifactTables.prach_multi_occasion_trials;
localExportPRACHFigure(paths(9), @() localPlotMultiOccasionTrials(mo));
rows(9) = localManifestRow(paths(9), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_multi_occasion_trials);

sixgr.visual.writeFlowDiagramPNG(paths(10), "Strict PRACH detection flow", ...
    ["nrPRACH waveform","AWGN / offsets","Rx correlation search","Score after detect"], result.StrictOk);
rows(10) = localManifestRow(paths(10), "image/png", "figure", NaN, "sixgr.phy.prach.exportStrictPRACHArtifacts", csvMap.prach_trials);
end

function localExportPRACHFigure(path, plotter)
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 960 600]);
cleanupFigure = onCleanup(@() close(fig)); %#ok<NASGU>
plotter();
set(findall(fig, "Type", "axes"), "Color", "w", ...
    "XColor", [0.12 0.16 0.20], "YColor", [0.12 0.16 0.20], ...
    "FontSize", 10, "LineWidth", 0.8);
set(findall(fig, "Type", "text"), "Color", [0.08 0.12 0.16]);
sixgr.util.exportFigureArtifact(fig, char(string(path)), "Resolution", 150);
end

function localPlotResourceGrid(grid)
magnitude = squeeze(max(abs(grid), [], 3));
if isempty(magnitude) || ~ismatrix(magnitude)
    error("sixgr:phy:prach:MissingResourceGridEvidence", ...
        "The strict PRACH resource-grid image requires a measured two-dimensional grid.");
end
imagesc(0:size(magnitude, 2)-1, 0:size(magnitude, 1)-1, magnitude);
axis xy tight;
colormap(parula(256));
colorbar;
xlabel("OFDM symbol index");
ylabel("subcarrier index");
title("PRACH transmit resource-grid magnitude");
end

function localPlotCandidateMetrics(T, plotTitle)
if isempty(T)
    error("sixgr:phy:prach:MissingCandidateEvidence", ...
        "The strict PRACH correlation image requires measured candidate rows.");
end
x = double(T.PreambleIndexCandidate);
y = double(T.Metric);
[x, order] = sort(x);
y = y(order);
stem(x, y, "filled", "DisplayName", "measured correlation");
hold on;
thresholdIndex = find(isfinite(double(T.Threshold)), 1, "first");
if ~isempty(thresholdIndex)
    threshold = double(T.Threshold(thresholdIndex));
    yline(threshold, "--r", "detection threshold", "LineWidth", 1.2, ...
        "DisplayName", "detection threshold");
end
selected = logical(T.SelectedCandidate(order));
if any(selected)
    scatter(x(selected), y(selected), 55, "o", "filled", ...
        "DisplayName", "selected candidate");
end
grid on;
xlabel("preamble candidate index");
ylabel("normalized correlation metric");
title(plotTitle);
legend("Location", "best");
hold off;
end

function localPlotFalseAlarmSweep(T)
localRequirePlotColumns(T, ["SNRdB","FalseAlarmProbability","CILower", ...
    "CIUpper","TargetFalseAlarmProbability"], "false-alarm sweep");
[x, order] = sort(double(T.SNRdB));
y = double(T.FalseAlarmProbability(order));
lo = max(0, y - double(T.CILower(order)));
hi = max(0, double(T.CIUpper(order)) - y);
target = double(T.TargetFalseAlarmProbability(order));
errorbar(x, y, lo, hi, "o-", "LineWidth", 1.4, ...
    "MarkerFaceColor", [0.1 0.45 0.8], "DisplayName", "measured P_{FA} (exact CI)");
hold on;
plot(x, target, "--r", "LineWidth", 1.3, "DisplayName", "required maximum");
upper = max([hi + y; target; eps], [], "all");
ylim([0, max(1.2 * upper, 1.2e-3)]);
grid on;
xlabel("configured noise-only SNR label (dB)");
ylabel("false-alarm probability");
title("PRACH false-alarm probability with exact confidence bounds");
legend("Location", "best");
hold off;
end

function localPlotMissedDetectionSweep(T)
localRequirePlotColumns(T, ["SNRdB","MissedDetectionProbability", ...
    "MissedDetectionCILower","MissedDetectionCIUpper", ...
    "TargetMissedDetectionProbability","QualificationRequired"], ...
    "missed-detection sweep");
[x, order] = sort(double(T.SNRdB));
y = double(T.MissedDetectionProbability(order));
lo = max(0, y - double(T.MissedDetectionCILower(order)));
hi = max(0, double(T.MissedDetectionCIUpper(order)) - y);
required = logical(T.QualificationRequired(order));
errorbar(x, y, lo, hi, "o-", "LineWidth", 1.2, ...
    "Color", [0.4 0.4 0.4], "DisplayName", "measured P_{MD} (exact CI)");
hold on;
if any(required)
    scatter(x(required), y(required), 65, [0.05 0.55 0.25], "filled", ...
        "DisplayName", "qualification point");
end
target = double(T.TargetMissedDetectionProbability(order));
plot(x, target, "--r", "LineWidth", 1.3, "DisplayName", "required maximum");
ylim([0 1]);
grid on;
xlabel("SNR (dB)");
ylabel("missed-detection probability");
title("PRACH missed-detection probability with exact confidence bounds");
legend("Location", "best");
hold off;
end

function localPlotTimingSweep(T)
localRequirePlotColumns(T, ["InjectedTimingOffsetSamples", ...
    "MeanEstimatedTimingOffsetSamples","MeanTimingErrorSamples", ...
    "MaxAbsTimingErrorSamples"], "timing-offset sweep");
[x, order] = sort(double(T.InjectedTimingOffsetSamples));
estimated = double(T.MeanEstimatedTimingOffsetSamples(order));
meanError = double(T.MeanTimingErrorSamples(order));
maxError = double(T.MaxAbsTimingErrorSamples(order));
tiledlayout(2, 1, "TileSpacing", "compact", "Padding", "compact");
nexttile;
plot(x, x, "--k", "DisplayName", "ideal", "LineWidth", 1.1);
hold on;
plot(x, estimated, "o-", "DisplayName", "measured estimate", "LineWidth", 1.4);
grid on;
ylabel("estimated offset (samples)");
title("PRACH timing-offset recovery");
legend("Location", "best");
hold off;
nexttile;
plot(x, meanError, "o-", "DisplayName", "mean error", "LineWidth", 1.3);
hold on;
plot(x, maxError, "s--", "DisplayName", "maximum absolute error", "LineWidth", 1.3);
yline(0, ":k");
grid on;
xlabel("injected timing offset (samples)");
ylabel("timing error (samples)");
legend("Location", "best");
hold off;
end

function localPlotRestrictedSetMapping(T)
localRequirePlotColumns(T, ["RestrictedSet","NCS","Valid"], ...
    "restricted-set mapping");
[sets, ~, group] = unique(string(T.RestrictedSet), "stable");
ncs = splitapply(@(x) x(1), double(T.NCS), group);
validFraction = splitapply(@(x) mean(double(x)), logical(T.Valid), group);
yyaxis left;
bar(1:numel(sets), ncs, 0.55, "DisplayName", "N_{CS}");
ylabel("cyclic-shift spacing N_{CS}");
yyaxis right;
plot(1:numel(sets), validFraction, "o-", "LineWidth", 1.4, ...
    "DisplayName", "valid mapping fraction");
ylim([0 1.05]);
ylabel("valid mapping fraction");
xticks(1:numel(sets));
xticklabels(sets);
xlabel("restricted-set configuration");
title("PRACH restricted-set cyclic-shift mapping");
grid on;
legend("Location", "best");
end

function localPlotCollisionTrials(T)
localRequirePlotColumns(T, ["CollisionGroupId","UEId", ...
    "DetectedCandidateCount","CollisionDetected"], "collision trials");
x = 1:height(T);
bar(x, double(T.DetectedCandidateCount), 0.65, ...
    "DisplayName", "detected candidates");
hold on;
detected = logical(T.CollisionDetected);
scatter(x(detected), double(T.DetectedCandidateCount(detected)), 55, ...
    [0.8 0.2 0.1], "filled", "DisplayName", "collision detected");
labels = "G" + string(T.CollisionGroupId) + "/UE" + string(T.UEId);
xticks(x);
xticklabels(labels);
xtickangle(35);
xlabel("collision group / UE");
ylabel("detected preamble-candidate count");
title("PRACH collision and multi-preamble resolution");
grid on;
legend("Location", "best");
hold off;
end

function localPlotMultiOccasionTrials(T)
localRequirePlotColumns(T, ["OccasionSlot","RARNTI", ...
    "OccasionFrequencyIndex","DetectedOnCorrectOccasion","TrialId"], ...
    "multi-occasion trials");
slot = double(T.OccasionSlot);
rarnti = double(T.RARNTI);
freq = double(T.OccasionFrequencyIndex);
correct = logical(T.DetectedOnCorrectOccasion);
scatter(slot, rarnti, 65, freq, "filled", "DisplayName", "measured occasion");
hold on;
if any(~correct)
    scatter(slot(~correct), rarnti(~correct), 90, "rx", "LineWidth", 1.6, ...
        "DisplayName", "wrong occasion");
end
text(slot, rarnti, "  trial " + string(T.TrialId), "FontSize", 8);
colorbar;
grid on;
xlabel("PRACH occasion slot");
ylabel("RA-RNTI");
title("PRACH multi-occasion RA-RNTI mapping (color = frequency index)");
legend("Location", "best");
hold off;
end

function localRequirePlotColumns(T, names, context)
if ~istable(T) || isempty(T) || ~all(ismember(string(names), ...
        string(T.Properties.VariableNames)))
    error("sixgr:phy:prach:MissingPlotEvidence", ...
        "The strict PRACH %s image requires measured columns: %s.", ...
        char(string(context)), char(strjoin(string(names), ", ")));
end
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
hash = sixgr.rrc.asn1.asn1SHA256Hex(data);
end
