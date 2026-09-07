function manifest = exportRAEvidenceArtifacts(runFolder, result)
%EXPORTRAEVIDENCEARTIFACTS Persist four-step RA truth evidence artifacts.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
jsonDir = fullfile(layout.ReportDir, "json");
textDir = fullfile(layout.ReportDir, "text");
figDir = fullfile(layout.ReportDir, "figures");
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(textDir);
sixgr.util.ensureFolder(figDir);

tables = result.ArtifactTables;
csvMap = struct( ...
    "sib1_rach_config_binding", fullfile(layout.ControlCSVDir, "sib1_rach_config_binding.csv"), ...
    "ra_attempts", fullfile(layout.ControlCSVDir, "ra_attempts.csv"), ...
    "ra_state_transitions", fullfile(layout.ControlCSVDir, "ra_state_transitions.csv"), ...
    "msg1_prach_detection", fullfile(layout.ControlCSVDir, "msg1_prach_detection.csv"), ...
    "msg2_rar_trials", fullfile(layout.ControlCSVDir, "msg2_rar_trials.csv"), ...
    "msg2_pdcch_candidates", fullfile(layout.ControlCSVDir, "msg2_pdcch_candidates.csv"), ...
    "msg2_dci_fields", fullfile(layout.ControlCSVDir, "msg2_dci_fields.csv"), ...
    "rar_monitoring_observations", fullfile(layout.ControlCSVDir, "rar_monitoring_observations.csv"), ...
    "rar_monitoring_candidates", fullfile(layout.ControlCSVDir, "rar_monitoring_candidates.csv"), ...
    "rar_monitoring_decoded_fields", fullfile(layout.ControlCSVDir, "rar_monitoring_decoded_fields.csv"), ...
    "msg3_pusch_trials", fullfile(layout.ControlCSVDir, "msg3_pusch_trials.csv"), ...
    "msg4_contention_resolution", fullfile(layout.ControlCSVDir, "msg4_contention_resolution.csv"), ...
    "msg4_trials", fullfile(layout.ControlCSVDir, "msg4_trials.csv"), ...
    "rrc_connection_events", fullfile(layout.ControlCSVDir, "rrc_connection_events.csv"), ...
    "rrc_setup_complete", fullfile(layout.ControlCSVDir, "rrc_setup_complete.csv"), ...
    "ra_timer_events", fullfile(layout.ControlCSVDir, "ra_timer_events.csv"), ...
    "ra_negative_trials", fullfile(layout.ControlCSVDir, "ra_negative_trials.csv"), ...
    "ra_collision_trials", fullfile(layout.ControlCSVDir, "ra_collision_trials.csv"), ...
    "ra_oracle_guard", fullfile(layout.ControlCSVDir, "ra_oracle_guard.csv"), ...
    "ra_runtime_stage_waveforms", fullfile(layout.ControlCSVDir, "ra_runtime_stage_waveforms.csv"));

csvFields = string(fieldnames(csvMap));
rows = repmat(localManifestRow(), numel(csvFields), 1);
for ii = 1:numel(csvFields)
    name = csvFields(ii);
    path = csvMap.(name);
    if name == "msg4_trials"
        T = tables.msg4_contention_resolution;
    else
        T = tables.(name);
    end
    sixgr.util.csvWriteTable(path, T);
    rows(ii) = localManifestRow(path, "text/csv", "csv", height(T), ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
end
decodedOwnershipRows = localWriteDecodedOwnershipArtifacts(layout, tables);
% Stabilize every primary RA CSV before any JSON envelope records its
% source hash. Figure-only source CSVs are stabilized later by the shared
% component-lineage writer.
sixgr.truth.sanitizeLLSArtifactCSVs(runFolder, ...
    "OnlyPaths", string(struct2cell(csvMap)));

summary = localJsonEnvelope(result, "ra_attempt_summary", csvMap.ra_attempts);
binding = localJsonEnvelope(result, "ra_config_binding", csvMap.ra_attempts);
binding.RABindingSource = string(result.RABindingSource);
binding.RACHConfigHash = string(result.RACHConfigHash);
binding.AUD_RA_001_Status = string(ternary(logical(result.StrictOk), "fixed_for_four_step_anchor_profile", "failed"));
rarDecoded = localJsonEnvelope(result, "msg2_rar_decoded", csvMap.msg2_rar_trials);
rarDecoded.RARBytesHex = string(result.RARBytesHex);
rarDecoded.RAPIDDecoded = double(result.RAPIDDecoded);
rarDecoded.TemporaryCRNTI = double(result.TemporaryCRNTI);
rarDecoded.ULGrantHex = string(result.RARULGrantHex);
msg3Decoded = localJsonEnvelope(result, "msg3_payload_decoded", csvMap.msg3_pusch_trials);
msg3Decoded.PayloadHex = string(result.Msg3PayloadHex);
msg3Decoded.ContentionIdentity = string(result.Msg3ContentionIdentity);
msg4Decoded = localJsonEnvelope(result, "msg4_contention_resolution_decoded", csvMap.msg4_contention_resolution);
msg4Decoded.PayloadHex = string(result.Msg4PayloadHex);
msg4Decoded.DecodedContentionIdentity = string(result.Msg4ContentionIdentity);
msg4Decoded.ContentionIdentityMatches = logical(result.ContentionIdentityMatches);
negative = localJsonEnvelope(result, "ra_negative_summary", csvMap.ra_negative_trials);
negative.FaultMode = string(result.FaultMode);
negative.ExpectedFailureObserved = string(result.FaultMode) ~= "none" && ~logical(result.RACompleted) && ~logical(result.StrictOk);

jsonMap = struct( ...
    "ra_config_binding", fullfile(jsonDir, "ra_config_binding.json"), ...
    "ra_attempt_summary", fullfile(jsonDir, "ra_attempt_summary.json"), ...
    "msg2_rar_decoded", fullfile(jsonDir, "msg2_rar_decoded.json"), ...
    "msg3_payload_decoded", fullfile(jsonDir, "msg3_payload_decoded.json"), ...
    "msg4_contention_resolution_decoded", fullfile(jsonDir, "msg4_contention_resolution_decoded.json"), ...
    "ra_negative_summary", fullfile(jsonDir, "ra_negative_summary.json"));
jsonPayloads = struct("ra_config_binding", binding, "ra_attempt_summary", summary, ...
    "msg2_rar_decoded", rarDecoded, "msg3_payload_decoded", msg3Decoded, ...
    "msg4_contention_resolution_decoded", msg4Decoded, "ra_negative_summary", negative);
jsonFields = string(fieldnames(jsonMap));
jsonRows = repmat(localManifestRow(), numel(jsonFields), 1);
for ii = 1:numel(jsonFields)
    name = jsonFields(ii);
    path = jsonMap.(name);
    sixgr.util.jsonWrite(path, jsonPayloads.(name));
    jsonRows(ii) = localManifestRow(path, "application/json", "json", NaN, ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
end

textMap = struct( ...
    "msg2_rar_bytes", fullfile(textDir, "msg2_rar_bytes.hex.txt"), ...
    "msg3_payload", fullfile(textDir, "msg3_payload.hex.txt"), ...
    "msg4_payload", fullfile(textDir, "msg4_payload.hex.txt"));
if logical(sixgr.util.structGet(result, "RequireRRCSetupComplete", false))
    textMap.rrc_setup_complete_payload = fullfile( ...
        textDir, "rrc_setup_complete_payload.hex.txt");
end
sixgr.util.writeTextFile(textMap.msg2_rar_bytes, string(result.RARBytesHex));
sixgr.util.writeTextFile(textMap.msg3_payload, string(result.Msg3PayloadHex));
sixgr.util.writeTextFile(textMap.msg4_payload, string(result.Msg4PayloadHex));
if isfield(textMap, "rrc_setup_complete_payload")
    sixgr.util.writeTextFile( ...
        textMap.rrc_setup_complete_payload, ...
        string(sixgr.util.structGet( ...
        result, "SetupCompleteTx.RRCSetupComplete.PayloadHex", "")));
end
textFields = string(fieldnames(textMap));
textRows = repmat(localManifestRow(), numel(textFields), 1);
for ii = 1:numel(textFields)
    path = textMap.(textFields(ii));
    textRows(ii) = localManifestRow(path, "text/plain", "text", NaN, ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
end

figRows = localWriteFigures(layout, result);
manifestRows = [rows(:); decodedOwnershipRows(:); jsonRows(:); textRows(:); figRows(:)];
manifestRows = localRefreshManifestRows(manifestRows);
manifest = struct2table(manifestRows, "AsArray", true);
manifestPath = fullfile(layout.ControlCSVDir, "ra_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
end

function rows = localRefreshManifestRows(rows)
% Plot-source stabilization may canonically prune a CSV after its first
% write.  Publish hashes only after every producer and lineage writer has
% finished.  The manifest intentionally does not contain a self-hash row;
% a file cannot truthfully embed the SHA-256 of its own final bytes.
for i = 1:numel(rows)
    rows(i).ByteCount = localFileBytes(rows(i).ArtifactPath);
    rows(i).SHA256 = localFileSHA256(rows(i).ArtifactPath);
end
end

function rows = localWriteDecodedOwnershipArtifacts(layout, tables)
rows = repmat(localManifestRow(), 0, 1);
if ~isfield(tables, "sib1_rach_config_binding") || ~istable(tables.sib1_rach_config_binding) || ...
        height(tables.sib1_rach_config_binding) == 0
    return;
end
T = tables.sib1_rach_config_binding;
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
paths = [
    string(fullfile(layout.ControlCSVDir, "rach_config_from_decoded_sib1.csv"))
    string(fullfile(layout.ReportCSVDir, "phase4_decoded_config_ownership_audit.csv"))];
rows = repmat(localManifestRow(), numel(paths), 1);
for ii = 1:numel(paths)
    sixgr.util.csvWriteTable(paths(ii), T);
    rows(ii) = localManifestRow(paths(ii), "text/csv", "csv", height(T), ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
end
end

function payload = localJsonEnvelope(result, implementationStatus, sourceCsv)
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = string(implementationStatus);
payload.source_csv = string(sourceCsv);
payload.source_csv_sha256 = localFileSHA256(sourceCsv);
payload.RACompleted = logical(result.RACompleted);
payload.StrictOk = logical(result.StrictOk);
payload.FailureReason = string(result.FailureReason);
payload.ProxyUsed = logical(result.ProxyUsed);
payload.Skipped = logical(result.Skipped);
payload.ToolboxMissing = logical(result.ToolboxMissing);
payload.UsedOracleFields = string(result.UsedOracleFields);
end

function rows = localWriteFigures(layout, result)
figDir = fullfile(layout.ReportDir, "figures");
paths = [
    string(fullfile(figDir, "ra_procedure_timeline.png"))
    string(fullfile(figDir, "msg1_prach_correlation.png"))
    string(fullfile(figDir, "msg2_rar_pdcch_candidates.png"))
    string(fullfile(figDir, "msg3_pusch_constellation.png"))
    string(fullfile(figDir, "msg4_contention_resolution_flow.png"))
    string(fullfile(figDir, "ra_collision_outcome.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);
if ~usejava("jvm")
    rows = rows(1:0);
    return;
end

fig = figure("Visible", "off");
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
stateSource = fullfile(layout.ControlCSVDir, "ra_state_transitions.csv");
states = string(result.ArtifactTables.ra_state_transitions.StateAfter);
plot(1:numel(states), 1:numel(states), "o-", "LineWidth", 1.5);
grid on; xlabel("transition index"); ylabel("state index");
title("Four-step random-access state timeline");
yticks(1:numel(states)); yticklabels(states);
sixgr.util.exportFigureArtifact(fig, paths(1));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

trace = sixgr.util.structGet(result.Msg1Tx, "PRACHRuntimeConfig", struct()); %#ok<NASGU>
detTrace = sixgr.util.structGet(result, "Msg1DetectionTrace", struct());
msg1Source = fullfile(layout.ControlCSVDir, "msg1_prach_detection.csv");
sourceRows = repmat(localManifestRow(), 0, 1);
if isempty(fieldnames(detTrace))
    det = result.ArtifactTables.msg1_prach_detection;
    stem(det.PreambleIndexDetected, det.DetectionMetric, "filled");
    hold on; yline(det.DetectionThreshold(1), "--r", "threshold");
else
    lag = double(detTrace.LagSamples(:));
    correlation = double(detTrace.CorrelationAbs(:));
    if numel(lag) ~= numel(correlation) || isempty(lag) || ...
            any(~isfinite(lag)) || any(~isfinite(correlation))
        error("sixgr:phy:ra:InvalidMsg1CorrelationTrace", ...
            "MSG1 correlation lineage requires equal-length finite lag and correlation vectors.");
    end
    msg1TraceT = table((1:numel(lag)).', lag, correlation, ...
        repmat("real_lls_evidence", numel(lag), 1), ...
        repmat("runtime_msg1_waveform_correlation", numel(lag), 1), ...
        'VariableNames', ["SampleIndex","LagSamples","CorrelationAbs", ...
        "TruthStatus","ValueSource"]);
    msg1Source = fullfile(layout.ControlCSVDir, ...
        "msg1_prach_correlation_trace.csv");
    sixgr.util.csvWriteTable(msg1Source, msg1TraceT);
    sourceRows(end+1, 1) = localManifestRow(msg1Source, ... %#ok<AGROW>
        "text/csv", "csv", height(msg1TraceT), ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
    plot(lag, correlation, "LineWidth", 1.2);
end
grid on; xlabel("lag / detected preamble evidence"); ylabel("correlation metric");
title("MSG1 PRACH measured correlation evidence");
sixgr.util.exportFigureArtifact(fig, paths(2));
rows(2) = localManifestRow(paths(2), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

pc = result.ArtifactTables.msg2_pdcch_candidates;
bar(double(pc.CandidateIndex), double(pc.CrcPass));
ylim([0 1.2]); grid on; xlabel("candidate index"); ylabel("CRC pass");
title("MSG2 RA-RNTI PDCCH candidate outcomes");
sixgr.util.exportFigureArtifact(fig, paths(3));
rows(3) = localManifestRow(paths(3), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

eq = complex([]);
constellationSource = "post_equalized_msg3_pusch_symbols";
try
    eq = result.Msg3Rx.EqualizedSymbolsForEvidence;
catch
end
if isempty(eq)
    try
        eq = result.Msg3Tx.PUSCHSymbolsForEvidence;
        constellationSource = "transmitted_msg3_pusch_symbols";
    catch
    end
end
if isempty(eq)
    error("sixgr:phy:ra:MissingMsg3ConstellationEvidence", ...
        "MSG3 constellation plot requires runtime PUSCH symbol evidence.");
end
msg3ConstellationT = table((1:numel(eq)).', real(eq(:)), imag(eq(:)), ...
    repmat(constellationSource, numel(eq), 1), ...
    'VariableNames', ["SampleIndex","InPhase","Quadrature","SymbolSource"]);
msg3Source = fullfile(layout.ControlCSVDir, ...
    "msg3_pusch_constellation_samples.csv");
sixgr.util.csvWriteTable(msg3Source, msg3ConstellationT);
sourceRows(end+1, 1) = localManifestRow(msg3Source, ... %#ok<AGROW>
    "text/csv", "csv", height(msg3ConstellationT), ...
    "sixgr.phy.ra.exportRAEvidenceArtifacts");
scatter(msg3ConstellationT.InPhase, msg3ConstellationT.Quadrature, 10, "filled");
axis equal; grid on; xlabel("I"); ylabel("Q");
title("MSG3 PUSCH runtime constellation evidence");
sixgr.util.exportFigureArtifact(fig, paths(4));
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

sixgr.visual.writeFlowDiagramPNG(paths(5), "MSG4 contention-resolution flow", ...
    ["gNB decoded Msg3", "PDCCH/PDSCH Msg4 (Temp C-RNTI " + string(result.TemporaryCRNTI) + ")", ...
     "UE identity match=" + string(logical(result.ContentionIdentityMatches))], result.RACompleted);
rows(5) = localManifestRow(paths(5), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");

collisionT = table(["collision_detected";"ra_completed"], ...
    double([result.CollisionDetected; result.RACompleted]), ...
    'VariableNames', ["Outcome","Value"]);
collisionSource = fullfile(layout.ControlCSVDir, "ra_collision_outcome.csv");
sixgr.util.csvWriteTable(collisionSource, collisionT);
sourceRows(end+1, 1) = localManifestRow(collisionSource, ... %#ok<AGROW>
    "text/csv", "csv", height(collisionT), ...
    "sixgr.phy.ra.exportRAEvidenceArtifacts");
bar(categorical(collisionT.Outcome), collisionT.Value);
ylim([0 1.2]); grid on; ylabel("boolean");
title("RA collision and completion outcome");
sixgr.util.exportFigureArtifact(fig, paths(6));
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");

plotIds = ["ra_procedure_timeline"; "msg1_prach_correlation"; ...
    "msg2_rar_pdcch_candidates"; "msg3_pusch_constellation"; ...
    "msg4_contention_resolution_flow"; "ra_collision_outcome"];
msg4Source = string(fullfile(layout.ControlCSVDir, ...
    "msg4_contention_resolution.csv")) + "|" + ...
    string(fullfile(layout.ControlCSVDir, "ra_attempts.csv"));
plotSources = [string(stateSource); string(msg1Source); ...
    string(fullfile(layout.ControlCSVDir, "msg2_pdcch_candidates.csv")); ...
    string(msg3Source); msg4Source; string(collisionSource)];
lineagePath = fullfile(layout.ControlCSVDir, "ra_plot_lineage.csv");
sixgr.visual.writeComponentPlotLineage(layout.Root, lineagePath, ...
    plotIds, paths, plotSources, ...
    "sixgr.phy.ra.exportRAEvidenceArtifacts");
lineageRow = localManifestRow(lineagePath, "text/csv", "csv", ...
    numel(plotIds), "sixgr.phy.ra.exportRAEvidenceArtifacts");
rows = [rows(:); sourceRows(:); lineageRow];
end

function row = localManifestRow(path, mime, kind, rowCount, producer)
if nargin == 0
    path = "";
    mime = "";
    kind = "";
    rowCount = NaN;
    producer = "";
end
row = struct("ArtifactPath", string(path), "MimeType", string(mime), "ArtifactKind", string(kind), ...
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
hash = sixgr.rrc.asn1.asn1SHA256Hex(data);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
