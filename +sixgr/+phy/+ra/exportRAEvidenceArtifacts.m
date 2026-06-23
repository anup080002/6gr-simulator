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
    "msg3_pusch_trials", fullfile(layout.ControlCSVDir, "msg3_pusch_trials.csv"), ...
    "msg4_contention_resolution", fullfile(layout.ControlCSVDir, "msg4_contention_resolution.csv"), ...
    "msg4_trials", fullfile(layout.ControlCSVDir, "msg4_trials.csv"), ...
    "ra_timer_events", fullfile(layout.ControlCSVDir, "ra_timer_events.csv"), ...
    "ra_negative_trials", fullfile(layout.ControlCSVDir, "ra_negative_trials.csv"), ...
    "ra_collision_trials", fullfile(layout.ControlCSVDir, "ra_collision_trials.csv"), ...
    "ra_oracle_guard", fullfile(layout.ControlCSVDir, "ra_oracle_guard.csv"));

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
sixgr.util.writeTextFile(textMap.msg2_rar_bytes, string(result.RARBytesHex));
sixgr.util.writeTextFile(textMap.msg3_payload, string(result.Msg3PayloadHex));
sixgr.util.writeTextFile(textMap.msg4_payload, string(result.Msg4PayloadHex));
textFields = string(fieldnames(textMap));
textRows = repmat(localManifestRow(), numel(textFields), 1);
for ii = 1:numel(textFields)
    path = textMap.(textFields(ii));
    textRows(ii) = localManifestRow(path, "text/plain", "text", NaN, ...
        "sixgr.phy.ra.exportRAEvidenceArtifacts");
end

figRows = localWriteFigures(figDir, result);
manifestRows = [rows(:); jsonRows(:); textRows(:); figRows(:)];
manifest = struct2table(manifestRows, "AsArray", true);
manifestPath = fullfile(layout.ControlCSVDir, "ra_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
manifest(end+1, :) = struct2table(localManifestRow(manifestPath, "text/csv", "csv", height(manifest), ...
    "sixgr.phy.ra.exportRAEvidenceArtifacts"), "AsArray", true);
sixgr.util.csvWriteTable(manifestPath, manifest);
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

function rows = localWriteFigures(figDir, result)
paths = [
    string(fullfile(figDir, "ra_procedure_timeline.png"))
    string(fullfile(figDir, "msg1_prach_correlation.png"))
    string(fullfile(figDir, "msg2_rar_pdcch_candidates.png"))
    string(fullfile(figDir, "msg3_pusch_constellation.png"))
    string(fullfile(figDir, "msg4_contention_resolution_flow.svg"))
    string(fullfile(figDir, "ra_collision_outcome.png"))];
rows = repmat(localManifestRow(), numel(paths), 1);
if ~usejava("jvm")
    rows = rows(1:0);
    return;
end

fig = figure("Visible", "off");
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
states = string(result.Events.StateAfter);
plot(1:numel(states), 1:numel(states), "o-", "LineWidth", 1.5);
grid on; xlabel("transition index"); ylabel("state index");
title("Four-step random-access state timeline");
yticks(1:numel(states)); yticklabels(states);
sixgr.util.exportFigureArtifact(fig, paths(1));
rows(1) = localManifestRow(paths(1), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

trace = sixgr.util.structGet(result.Msg1Tx, "PRACHRuntimeConfig", struct()); %#ok<NASGU>
detTrace = sixgr.util.structGet(result, "Msg1DetectionTrace", struct());
if isempty(fieldnames(detTrace))
    try
        det = result.ArtifactTables.msg1_prach_detection;
        stem(det.PreambleIndexDetected, det.DetectionMetric, "filled");
        hold on; yline(det.DetectionThreshold(1), "--r", "threshold");
    catch
        stem(0, result.PreambleDetectionMetric, "filled");
    end
else
    plot(detTrace.LagSamples, detTrace.CorrelationAbs, "LineWidth", 1.2);
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
try
    eq = result.Msg3Rx.EqualizedSymbolsForEvidence;
catch
end
if isempty(eq)
    try
        eq = result.Msg3Tx.PUSCHSymbolsForEvidence;
    catch
    end
end
if isempty(eq)
    error("sixgr:phy:ra:MissingMsg3ConstellationEvidence", ...
        "MSG3 constellation plot requires runtime PUSCH symbol evidence.");
end
scatter(real(eq(:)), imag(eq(:)), 10, "filled");
axis equal; grid on; xlabel("I"); ylabel("Q");
title("MSG3 PUSCH runtime constellation evidence");
sixgr.util.exportFigureArtifact(fig, paths(4));
rows(4) = localManifestRow(paths(4), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
clf(fig);

localWriteMsg4FlowSVG(paths(5), result);
rows(5) = localManifestRow(paths(5), "image/svg+xml", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");

bar(categorical(["collision_detected","ra_completed"]), double([result.CollisionDetected, result.RACompleted]));
ylim([0 1.2]); grid on; ylabel("boolean");
title("RA collision and completion outcome");
sixgr.util.exportFigureArtifact(fig, paths(6));
rows(6) = localManifestRow(paths(6), "image/png", "figure", NaN, "sixgr.phy.ra.exportRAEvidenceArtifacts");
end

function localWriteMsg4FlowSVG(path, result)
text = sprintf(['<svg xmlns="http://www.w3.org/2000/svg" width="820" height="220">' ...
    '<rect width="820" height="220" fill="white"/>' ...
    '<text x="20" y="35" font-family="Arial" font-size="20">MSG4 contention-resolution flow</text>' ...
    '<rect x="30" y="80" width="190" height="60" fill="#e8f4ff" stroke="#245"/>' ...
    '<rect x="315" y="80" width="190" height="60" fill="#eaffea" stroke="#252"/>' ...
    '<rect x="600" y="80" width="190" height="60" fill="#fff3e6" stroke="#742"/>' ...
    '<text x="55" y="115" font-family="Arial" font-size="14">gNB decoded Msg3</text>' ...
    '<text x="335" y="108" font-family="Arial" font-size="14">PDCCH/PDSCH Msg4</text>' ...
    '<text x="333" y="126" font-family="Arial" font-size="12">Temp C-RNTI %.0f</text>' ...
    '<text x="620" y="108" font-family="Arial" font-size="14">UE identity check</text>' ...
    '<text x="620" y="126" font-family="Arial" font-size="12">match=%d, completed=%d</text>' ...
    '<line x1="220" y1="110" x2="315" y2="110" stroke="#333" marker-end="url(#a)"/>' ...
    '<line x1="505" y1="110" x2="600" y2="110" stroke="#333" marker-end="url(#a)"/>' ...
    '<defs><marker id="a" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">' ...
    '<path d="M0,0 L0,6 L7,3 z" fill="#333"/></marker></defs>' ...
    '</svg>'], double(result.TemporaryCRNTI), logical(result.ContentionIdentityMatches), logical(result.RACompleted));
sixgr.util.writeTextFile(path, text, "MimeType", "image/svg+xml", "ArtifactKind", "image_svg");
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
hash = sixgr.rrc.asn1.sha256Hex(data);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
