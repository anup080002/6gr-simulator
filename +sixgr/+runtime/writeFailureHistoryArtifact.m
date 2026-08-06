function out = writeFailureHistoryArtifact(metaDir, exception, varargin)
%WRITEFAILUREHISTORYARTIFACT Preserve every terminal exception by content hash.

p = inputParser;
p.addRequired("metaDir", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addRequired("exception", @(x)isa(x, "MException"));
p.addParameter("Stage", "", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.parse(metaDir, exception, varargin{:});

metaDir = char(string(metaDir));
historyDir = fullfile(metaDir, "failure_history");
sixgr.util.ensureFolder(metaDir);
sixgr.util.ensureFolder(historyDir);
currentPath = fullfile(metaDir, "failure_debug_report.txt");
manifestPath = fullfile(metaDir, "failure_history.csv");

manifest = localReadManifest(manifestPath);
if exist(currentPath, "file") == 2
    priorText = string(fileread(currentPath));
    [manifest, ~] = localPersistReport(manifest, historyDir, priorText, ...
        "historical_unstructured", "", "unknown", currentPath);
end

reportText = string(getReport(exception, "extended", "hyperlinks", "off"));
[manifest, historyPath] = localPersistReport(manifest, historyDir, reportText, ...
    string(exception.identifier), string(exception.message), ...
    string(p.Results.Stage), currentPath);
sixgr.util.writeTextFile(currentPath, char(reportText), ...
    "ArtifactKind", "failure_debug_report", ...
    "MimeType", "text/plain; charset=UTF-8");
sixgr.util.csvWriteTable(manifestPath, manifest);

out = struct("CurrentReportPath", string(currentPath), ...
    "HistoryReportPath", string(historyPath), ...
    "ManifestPath", string(manifestPath), ...
    "HistoryCount", height(manifest));
end

function manifest = localReadManifest(path)
names = ["TimestampUTC","Identifier","Message","Stage", ...
    "ReportPath","ReportSHA256","CurrentReportPath"];
types = repmat("string", 1, numel(names));
manifest = table('Size', [0 numel(names)], ...
    'VariableTypes', cellstr(types), 'VariableNames', cellstr(names));
if exist(path, "file") ~= 2
    return;
end
candidate = readtable(path, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "TextType", "string", ...
    "VariableNamingRule", "preserve");
if ~isequal(string(candidate.Properties.VariableNames), names)
    error("sixgr:runtime:FailureHistorySchemaMismatch", ...
        "Existing failure-history schema does not match the canonical schema: %s", path);
end
manifest = candidate;
end

function [manifest, historyPath] = localPersistReport(manifest, historyDir, ...
        reportText, identifier, message, stage, currentPath)
bytes = uint8(unicode2native(char(reportText), "UTF-8"));
hash = lower(string(sixgr.util.sha256Hex(bytes)));
historyPath = string(fullfile(historyDir, "failure_" + extractBefore(hash, 17) + ".txt"));
if exist(char(historyPath), "file") ~= 2
    sixgr.util.writeTextFile(char(historyPath), char(reportText), ...
        "ArtifactKind", "failure_history_report", ...
        "MimeType", "text/plain; charset=UTF-8");
end
if ~isempty(manifest) && any(lower(string(manifest.ReportSHA256)) == hash)
    return;
end
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
row = table(timestamp, string(identifier), string(message), string(stage), ...
    string(historyPath), hash, string(currentPath), ...
    'VariableNames', manifest.Properties.VariableNames);
manifest = [manifest; row]; %#ok<AGROW>
end
