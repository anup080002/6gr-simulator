function artifacts = exportPHYSignalDiagnostic(runFolder, cfg, diagnostics)
%EXPORTPHYSIGNALDIAGNOSTIC Export truthful same-trial PHY diagnostic figures.
%
% Normal images are emitted only for snapshots that contain contiguous
% waveform samples, a real receiver Hest slice, received data REs, and
% aligned post-equalization/reference symbols from one actual trial tuple.

if nargin < 2 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 3 || ~isstruct(diagnostics)
    diagnostics = struct();
end

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);

sourcePath = fullfile(layout.ReportCSVDir, "phy_signal_diagnostic_source.csv");
dlImagePath = fullfile(layout.ReportImageDir, "dl_phy_signal_diagnostic.png");
ulImagePath = fullfile(layout.ReportImageDir, "ul_phy_signal_diagnostic.png");
sourceT = table();
directions = ["DL","UL"];
snapshots = cell(2, 1);
reasons = strings(2, 1);

for i = 1:numel(directions)
    direction = directions(i);
    snapshot = localDirectionalSnapshot(diagnostics, direction);
    [valid, reason] = localValidateSnapshot(snapshot, direction);
    reasons(i) = reason;
    if valid
        snapshots{i} = snapshot;
        sourceT = localAppendCompatibleTable(sourceT, snapshot.SourceTable);
    else
        snapshots{i} = struct();
    end
end

if istable(sourceT) && ~isempty(sourceT)
    sixgr.util.csvWriteTable(sourcePath, sourceT);
else
    localDeleteIfExists(sourcePath);
end

imagePaths = strings(2, 1);
for i = 1:numel(directions)
    direction = directions(i);
    if direction == "DL"
        imagePath = dlImagePath;
    else
        imagePath = ulImagePath;
    end
    localDeleteIfExists(imagePath);
    localDeleteIfExists(sixgr.visual.unavailableArtifactPath(imagePath));
    if isempty(fieldnames(snapshots{i}))
        sixgr.visual.writeUnavailablePlotCard(imagePath, direction + " PHY Signal Diagnostic", ...
            "No normal diagnostic image was emitted: " + reasons(i) + ".");
        imagePaths(i) = sixgr.visual.unavailableArtifactPath(imagePath);
        continue;
    end
    fig = localRenderDiagnosticFigure(snapshots{i}, cfg);
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    actualPath = sixgr.util.exportFigureArtifact(fig, imagePath, "Resolution", 170);
    imagePaths(i) = string(actualPath);
end

artifacts = struct( ...
    "SourceCSV", string(sourcePath), ...
    "SourceTable", sourceT, ...
    "DLImage", imagePaths(1), ...
    "ULImage", imagePaths(2), ...
    "DLAvailable", ~isempty(fieldnames(snapshots{1})), ...
    "ULAvailable", ~isempty(fieldnames(snapshots{2})), ...
    "DLReason", reasons(1), ...
    "ULReason", reasons(2));
end

function snapshot = localDirectionalSnapshot(diagnostics, direction)
snapshot = struct();
direction = upper(string(direction));
candidateFields = [direction, direction + "SignalDiagnostic", "SignalDiagnostic" + direction];
for i = 1:numel(candidateFields)
    field = char(candidateFields(i));
    if isfield(diagnostics, field) && isstruct(diagnostics.(field))
        snapshot = diagnostics.(field);
        return;
    end
end
if isfield(diagnostics, "PHYSignalDiagnostics") && isstruct(diagnostics.PHYSignalDiagnostics)
    nested = diagnostics.PHYSignalDiagnostics;
    if isfield(nested, char(direction)) && isstruct(nested.(char(direction)))
        snapshot = nested.(char(direction));
    end
end
end

function [ok, reason] = localValidateSnapshot(snapshot, direction)
ok = false;
reason = "snapshot_unavailable";
if ~(isstruct(snapshot) && ~isempty(fieldnames(snapshot)))
    return;
end
if ~logical(sixgr.util.structGet(snapshot, "Available", false))
    reason = string(sixgr.util.structGet(snapshot, "Reason", "snapshot_marked_unavailable"));
    return;
end
T = sixgr.util.structGet(snapshot, "SourceTable", table());
if ~(istable(T) && ~isempty(T))
    reason = "snapshot_source_table_empty";
    return;
end
requiredColumns = ["SnapshotID","Panel","Series","PointIndex","XValue","YValue", ...
    "Direction","UEIndex","RNTI","CellID","Frame","SFN","Slot","AbsoluteSlot","TBId", ...
    "SampleIndex","SubcarrierIndex","OFDMSymbolIndex", ...
    "MatlabSubcarrierIndex","MatlabOFDMSymbolIndex", ...
    "ResourceBlockIndex","SubcarrierInResourceBlock", ...
    "RxPortIndex0Based","TxPortIndex0Based","IValue","QValue", ...
    "ReferenceI","ReferenceQ","EqualizedI","EqualizedQ", ...
    "ChannelEstimateSource","ChannelEstimateMethod", ...
    "CurveConstruction","truth_status","SourceArtifact","Status"];
missing = requiredColumns(~ismember(requiredColumns, string(T.Properties.VariableNames)));
if ~isempty(missing)
    reason = "snapshot_source_schema_missing:" + strjoin(missing, "|");
    return;
end
if any(upper(strtrim(string(T.Direction))) ~= upper(string(direction)))
    reason = "snapshot_direction_mismatch";
    return;
end
snapshotIds = unique(strtrim(string(T.SnapshotID)), "stable");
snapshotIds = snapshotIds(strlength(snapshotIds) > 0);
if numel(snapshotIds) ~= 1
    reason = "snapshot_mixes_multiple_trial_ids";
    return;
end
if any(lower(strtrim(string(T.truth_status))) ~= "real_lls_evidence")
    reason = "snapshot_truth_status_not_real_lls_evidence";
    return;
end
if any(lower(strtrim(string(T.CurveConstruction))) ~= "runtime_same_trial_phy_signal_snapshot")
    reason = "snapshot_curve_construction_invalid";
    return;
end
if any(lower(strtrim(string(T.SourceArtifact))) ~= "runtime_phy_arrays_same_trial")
    reason = "snapshot_source_artifact_invalid";
    return;
end
estimatorSource = strtrim(string(T.ChannelEstimateSource));
estimatorMethod = strtrim(string(T.ChannelEstimateMethod));
estimatorText = lower(estimatorSource + "|" + estimatorMethod);
if any(strlength(estimatorSource) == 0 | strlength(estimatorMethod) == 0) || ...
        any(contains(estimatorText, [ ...
        "fallback","synthetic","proxy","logistic","lut","oracle", ...
        "perfect","ideal","genie"]))
    reason = "snapshot_channel_estimator_provenance_invalid";
    return;
end
tupleColumns = ["UEIndex","RNTI","Frame","Slot","TBId"];
for i = 1:numel(tupleColumns)
    values = strtrim(string(T.(tupleColumns(i))));
    lowered = lower(values);
    if any(ismissing(values) | strlength(values) == 0 | ...
            ismember(lowered, ["nan","missing","<missing>"])) || ...
            numel(unique(values, "stable")) ~= 1
        reason = "snapshot_trial_tuple_invalid:" + tupleColumns(i);
        return;
    end
end
requiredPanels = ["time_domain","spectrum","channel_estimate", ...
    "pre_equalization_re_cloud","post_equalization_constellation","kpi"];
panels = unique(strtrim(string(T.Panel)), "stable");
missingPanels = requiredPanels(~ismember(requiredPanels, panels));
if ~isempty(missingPanels)
    reason = "snapshot_missing_panels:" + strjoin(missingPanels, "|");
    return;
end

txTime = T(string(T.Panel) == "time_domain" & string(T.Series) == "tx", :);
rxTime = T(string(T.Panel) == "time_domain" & string(T.Series) == "rx", :);
if ~localContiguousMatchingSamples(txTime, rxTime)
    reason = "snapshot_time_samples_not_contiguous_or_matched";
    return;
end
if height(T(string(T.Panel) == "spectrum" & string(T.Series) == "tx", :)) < 64 || ...
        height(T(string(T.Panel) == "spectrum" & string(T.Series) == "rx", :)) < 64
    reason = "snapshot_fft_evidence_incomplete";
    return;
end

channelT = T(string(T.Panel) == "channel_estimate", :);
if isempty(channelT) || ~any(isfinite(double(channelT.IValue)) & isfinite(double(channelT.QValue)))
    reason = "snapshot_channel_estimate_evidence_incomplete";
    return;
end
channelToken = upper(strjoin(unique(string(channelT.ChannelModel), "stable"), "|") + "|" + ...
    strjoin(unique(string(channelT.DelayProfile), "stable"), "|"));
if (contains(channelToken, "TDL") || contains(channelToken, "CDL") || contains(channelToken, "FADING")) && ...
        numel(unique(double(channelT.SubcarrierIndex(isfinite(channelT.SubcarrierIndex))))) <= 1
    reason = "fading_snapshot_channel_estimate_is_scalar";
    return;
end

preT = T(string(T.Panel) == "pre_equalization_re_cloud", :);
postT = T(string(T.Panel) == "post_equalization_constellation", :);
if isempty(preT) || ~any(isfinite(double(preT.XValue)) & isfinite(double(preT.YValue)))
    reason = "snapshot_pre_equalization_re_evidence_incomplete";
    return;
end
if isempty(postT) || ~any(isfinite(double(postT.EqualizedI)) & isfinite(double(postT.EqualizedQ)) & ...
        isfinite(double(postT.ReferenceI)) & isfinite(double(postT.ReferenceQ)))
    reason = "snapshot_post_equalization_constellation_incomplete";
    return;
end
ok = true;
reason = "";
end

function ok = localContiguousMatchingSamples(txT, rxT)
ok = false;
if isempty(txT) || isempty(rxT) || height(txT) ~= height(rxT)
    return;
end
txIndex = double(txT.SampleIndex);
rxIndex = double(rxT.SampleIndex);
if any(~isfinite(txIndex)) || any(~isfinite(rxIndex)) || any(txIndex ~= rxIndex)
    return;
end
ok = txIndex(1) == 1 && all(diff(txIndex) == 1);
end

function fig = localRenderDiagnosticFigure(snapshot, cfg)
T = snapshot.SourceTable;
meta = snapshot.Metadata;
direction = string(snapshot.Direction);
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1500 980]);
tl = tiledlayout(fig, 3, 3, "Padding", "compact", "TileSpacing", "compact");

ax = nexttile(tl, [1 2]);
txT = T(string(T.Panel) == "time_domain" & string(T.Series) == "tx", :);
rxT = T(string(T.Panel) == "time_domain" & string(T.Series) == "rx", :);
hold(ax, "on");
plot(ax, double(txT.XValue) .* 1e6, double(txT.IValue), "-", "LineWidth", 0.8, "DisplayName", "TX I");
plot(ax, double(txT.XValue) .* 1e6, double(txT.QValue), "-", "LineWidth", 0.8, "DisplayName", "TX Q");
plot(ax, double(rxT.XValue) .* 1e6, double(rxT.IValue), "-", "LineWidth", 0.8, "DisplayName", "RX I");
plot(ax, double(rxT.XValue) .* 1e6, double(rxT.QValue), "-", "LineWidth", 0.8, "DisplayName", "RX Q");
hold(ax, "off");
grid(ax, "on");
xlabel(ax, "Time (\mus)");
ylabel(ax, "Complex baseband amplitude");
title(ax, direction + " contiguous TX/RX waveform");
legend(ax, "Location", "best", "NumColumns", 2);

ax = nexttile(tl);
axis(ax, "off");
localWriteContextCard(ax, meta, cfg);

ax = nexttile(tl, [1 2]);
txSpec = T(string(T.Panel) == "spectrum" & string(T.Series) == "tx", :);
rxSpec = T(string(T.Panel) == "spectrum" & string(T.Series) == "rx", :);
plot(ax, double(txSpec.XValue) ./ 1e6, double(txSpec.YValue), "LineWidth", 1.0, "DisplayName", "TX");
hold(ax, "on");
plot(ax, double(rxSpec.XValue) ./ 1e6, double(rxSpec.YValue), "LineWidth", 1.0, "DisplayName", "RX");
hold(ax, "off");
grid(ax, "on");
xlabel(ax, "Baseband frequency offset (MHz)");
ylabel(ax, "Relative magnitude (dB, common reference)");
title(ax, "Windowed spectrum from contiguous samples");
legend(ax, "Location", "best");

channelT = T(string(T.Panel) == "channel_estimate", :);
ax = nexttile(tl);
plot(ax, double(channelT.SubcarrierIndex), double(channelT.Magnitude_dB), "LineWidth", 1.0);
grid(ax, "on");
xlabel(ax, "Subcarrier index");
ylabel(ax, "|H_{est}| (dB)");
title(ax, "Receiver Hest magnitude");

ax = nexttile(tl);
plot(ax, double(channelT.SubcarrierIndex), double(channelT.Phase_deg), "LineWidth", 1.0);
grid(ax, "on");
xlabel(ax, "Subcarrier index");
ylabel(ax, "Unwrapped phase (deg)");
title(ax, "Receiver Hest phase");

preT = T(string(T.Panel) == "pre_equalization_re_cloud", :);
ax = nexttile(tl);
scatter(ax, double(preT.XValue), double(preT.YValue), 10, ".", "MarkerEdgeAlpha", 0.55);
grid(ax, "on");
axis(ax, "equal");
xlabel(ax, "Received data-RE I");
ylabel(ax, "Received data-RE Q");
title(ax, "Pre-EQ RX RE cloud (antenna 1)");

postT = T(string(T.Panel) == "post_equalization_constellation", :);
ax = nexttile(tl);
scatter(ax, double(postT.EqualizedI), double(postT.EqualizedQ), 12, ".", "DisplayName", "Equalized");
hold(ax, "on");
scatter(ax, double(postT.ReferenceI), double(postT.ReferenceQ), 28, "o", ...
    "LineWidth", 0.8, "DisplayName", "Reference");
hardMask = isfinite(double(postT.HardDecisionI)) & isfinite(double(postT.HardDecisionQ));
if any(hardMask)
    scatter(ax, double(postT.HardDecisionI(hardMask)), double(postT.HardDecisionQ(hardMask)), ...
        20, "x", "DisplayName", "Hard decision");
end
hold(ax, "off");
grid(ax, "on");
axis(ax, "equal");
xlabel(ax, "Normalized I");
ylabel(ax, "Normalized Q");
title(ax, "Post-EQ constellation");
legend(ax, "Location", "best");

title(tl, direction + " PHY signal diagnostic - same-trial runtime evidence", ...
    "FontWeight", "bold");
end

function localWriteContextCard(ax, meta, cfg)
configuredSNR = localDisplayNumber(sixgr.util.structGet(meta, "ConfiguredSNR_dB", NaN), "%.2f");
postEqSINR = localDisplayNumber(sixgr.util.structGet(meta, "PostEqSINR_dB", NaN), "%.2f");
evm = localDisplayNumber(sixgr.util.structGet(meta, "EVM_rms_pct", NaN), "%.2f");
crc = "unavailable";
crcValue = double(sixgr.util.structGet(meta, "CRCPass", NaN));
if isfinite(crcValue)
    crc = string(logical(crcValue));
end
scenarioId = string(sixgr.util.structGet(cfg, "run.scenarioID", ...
    sixgr.util.structGet(cfg, "meta.lls6gScenarioID", "")));
lines = [ ...
    "Snapshot: " + string(sixgr.util.structGet(meta, "SnapshotID", "")); ...
    "Scenario: " + scenarioId; ...
    "UE / RNTI: " + string(sixgr.util.structGet(meta, "UEIndex", NaN)) + " / " + string(sixgr.util.structGet(meta, "RNTI", NaN)); ...
    "Frame / slot / TB: " + string(sixgr.util.structGet(meta, "Frame", NaN)) + " / " + ...
        string(sixgr.util.structGet(meta, "Slot", NaN)) + " / " + string(sixgr.util.structGet(meta, "TBId", "")); ...
    "Channel: " + string(sixgr.util.structGet(meta, "ChannelModel", "")) + " " + string(sixgr.util.structGet(meta, "DelayProfile", "")); ...
    "Mod / MCS / layers: " + string(sixgr.util.structGet(meta, "Modulation", "")) + " / " + ...
        string(sixgr.util.structGet(meta, "MCSIndex", NaN)) + " / " + string(sixgr.util.structGet(meta, "Layers", NaN)); ...
    "Configured SNR: " + configuredSNR + " dB (stimulus)"; ...
    "Post-EQ SINR: " + postEqSINR + " dB"; ...
    "EVM RMS: " + evm + " %"; ...
    "CRC pass: " + crc; ...
    "Hest source: " + string(sixgr.util.structGet(meta, "ChannelEstimateSource", "")); ...
    "Hest method: " + string(sixgr.util.structGet(meta, "ChannelEstimateMethod", "")); ...
    "FFT: " + string(sixgr.util.structGet(meta, "FFTLength", NaN)) + " samples"];
text(ax, 0.02, 0.98, char(strjoin(lines, newline)), ...
    "Units", "normalized", "VerticalAlignment", "top", "HorizontalAlignment", "left", ...
    "FontName", "Consolas", "FontSize", 8.5, "Interpreter", "none");
title(ax, "Snapshot context / lineage");
end

function out = localDisplayNumber(value, format)
value = double(value);
if isscalar(value) && isfinite(value)
    out = string(sprintf(format, value));
else
    out = "unavailable";
end
end

function T = localAppendCompatibleTable(T, U)
if ~(istable(U) && ~isempty(U))
    return;
end
if ~(istable(T) && ~isempty(T))
    T = U;
    return;
end
if ~isequal(string(T.Properties.VariableNames), string(U.Properties.VariableNames))
    error("sixgr:truth:PHYSignalDiagnosticSchemaMismatch", ...
        "Directional PHY diagnostic snapshots must share one canonical source schema.");
end
T = [T; U];
end

function localDeleteIfExists(path)
path = char(string(path));
if exist(path, "file") == 2
    delete(path);
end
end
