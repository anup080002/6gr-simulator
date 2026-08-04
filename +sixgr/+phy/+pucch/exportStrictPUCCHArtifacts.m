function manifest = exportStrictPUCCHArtifacts(runFolder, result)
%EXPORTSTRICTPUCCHARTIFACTS Persist strict PUCCH waveform evidence.
% Keep this file ASCII-only.

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
jsonDir = fullfile(layout.ReportDir, "json");
sixgr.util.ensureFolder(jsonDir);

tables = result.ArtifactTables;
airPath = fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv");
runtimeTrials = sixgr.truth.selectCanonicalRuntimeControlTrials( ...
    localReadOptionalTable(airPath), "pucch");
if isempty(runtimeTrials)
    strictTrialPath = fullfile(layout.ControlCSVDir, "pucch_trials.csv");
else
    strictTrialPath = fullfile(layout.ControlCSVDir, "pucch_strict_trials.csv");
end
csvMap = struct( ...
    "pucch_trials", strictTrialPath, ...
    "pucch_resource_mapping", fullfile(layout.ControlCSVDir, "pucch_resource_mapping.csv"), ...
    "pucch_false_alarm_trials", fullfile(layout.ControlCSVDir, "pucch_false_alarm_trials.csv"), ...
    "pucch_summary", fullfile(layout.ControlCSVDir, "pucch_summary.csv"));
names = string(fieldnames(csvMap));
rows = repmat(localManifestRow(), numel(names) + 2, 1);
for ii = 1:numel(names)
    name = names(ii);
    T = tables.(name);
    sixgr.util.csvWriteTable(csvMap.(name), T);
    rows(ii) = localManifestRow(csvMap.(name), "text/csv", "csv", height(T), ...
        "sixgr.phy.pucch.exportStrictPUCCHArtifacts");
end

if isempty(runtimeTrials)
    primaryTrials = tables.pucch_trials;
else
    primaryTrials = runtimeTrials;
    sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "pucch_trials.csv"), primaryTrials);
end
sixgr.util.csvWriteTable(airPath, primaryTrials);
rows(numel(names) + 1) = localManifestRow(airPath, "text/csv", "csv", height(primaryTrials), ...
    "sixgr.phy.pucch.exportStrictPUCCHArtifacts");

summaryJson = fullfile(jsonDir, "pucch_detection_summary.json");
payload = struct();
payload.RunId = string(result.RunId);
payload.scenario = string(result.ScenarioName);
payload.timestamp = sixgr.util.utcNowISO8601();
payload.implementation_status = "strict_pucch_waveform_resource_mapping_and_uci_decode_validation";
payload.StrictOk = logical(result.StrictOk);
payload.ProxyUsed = logical(result.ProxyUsed);
payload.Skipped = logical(result.Skipped);
payload.ToolboxMissing = logical(result.ToolboxMissing);
payload.FailureReason = string(result.FailureReason);
payload.source_csv = string(csvMap.pucch_trials);
payload.source_csv_sha256 = localFileSHA256(csvMap.pucch_trials);
payload.resource_mapping_csv = string(csvMap.pucch_resource_mapping);
payload.false_alarm_csv = string(csvMap.pucch_false_alarm_trials);
payload.PositivePassCount = localSummaryValue(tables.pucch_summary, "PositivePassCount");
payload.NegativePassCount = localSummaryValue(tables.pucch_summary, "NegativePassCount");
sixgr.util.jsonWrite(summaryJson, payload);
rows(numel(names) + 2) = localManifestRow(summaryJson, "application/json", "json", NaN, ...
    "sixgr.phy.pucch.exportStrictPUCCHArtifacts");

manifest = struct2table(rows, "AsArray", true);
manifestPath = fullfile(layout.ControlCSVDir, "pucch_strict_artifact_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, manifest);
manifest(end + 1, :) = struct2table(localManifestRow(manifestPath, "text/csv", "csv", height(manifest), ...
    "sixgr.phy.pucch.exportStrictPUCCHArtifacts"), "AsArray", true);
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

function row = localManifestRow(path, mediaType, kind, rowCount, producer)
if nargin < 1
    path = "";
end
if nargin < 2
    mediaType = "";
end
if nargin < 3
    kind = "";
end
if nargin < 4
    rowCount = NaN;
end
if nargin < 5
    producer = "";
end
row = struct( ...
    "Path", string(path), ...
    "MediaType", string(mediaType), ...
    "ArtifactKind", string(kind), ...
    "Rows", double(rowCount), ...
    "Producer", string(producer), ...
    "SHA256", localFileSHA256(path));
end

function hash = localFileSHA256(path)
hash = "";
path = char(string(path));
if strlength(string(path)) == 0 || exist(path, "file") ~= 2
    return;
end
try
    fid = fopen(path, "r");
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, inf, "*uint8");
    hash = string(sixgr.rrc.asn1.sha256Hex(bytes));
catch
    hash = "";
end
end

function value = localSummaryValue(T, name)
value = NaN;
if istable(T) && ~isempty(T) && ismember(name, string(T.Properties.VariableNames))
    try
        value = double(T.(name)(1));
    catch
        value = NaN;
    end
end
end
