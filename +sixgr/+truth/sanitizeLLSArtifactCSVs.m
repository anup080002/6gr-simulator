function out = sanitizeLLSArtifactCSVs(runFolder)
%SANITIZELLSARTIFACTCSVS Remove structurally blank columns from browser-facing CSVs.
%
% This post-pass is intentionally conservative: it never fabricates values,
% but it removes columns that are entirely blank or entirely inactive for the
% current run. Live signal-chain tables are first canonicalized so truthfully
% emitted semantic metadata is preserved before pruning.

layout = sixgr.report.resultLayout(runFolder);
dirs = unique([
    string(layout.ReportCSVDir)
    string(fullfile(runFolder, "analytics", "csv"))
    string(layout.ControlCSVDir)
    string(layout.PacketFlowCSVDir)
    string(layout.BeamformingCSVDir)
    string(layout.RFCSVDir)
    string(layout.AirInterfaceCSVDir)
    string(layout.HARQCSVDir)
], "stable");

rows = repmat(struct("LogicalPath","", "Changed", false, "RemovedColumnCount", 0), 0, 1);
for d = dirs.'
    if exist(char(d), "dir") ~= 7
        continue;
    end
    files = dir(fullfile(char(d), "*.csv"));
    for i = 1:numel(files)
        filePath = fullfile(files(i).folder, files(i).name);
        [changed, removedCount] = localSanitizeOneCSV(filePath);
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "LogicalPath", string(localPortablePath(localRelativeToRunFolder(runFolder, filePath))), ...
            "Changed", logical(changed), ...
            "RemovedColumnCount", double(removedCount));
    end
end
out = struct();
out.Files = struct2table(rows);
end

function [changed, removedCount] = localSanitizeOneCSV(filePath)
changed = false;
removedCount = 0;
try
    T = readtable(filePath, "VariableNamingRule", "preserve");
catch
    return;
end
if ~istable(T) || isempty(T)
    return;
end
inputWidth = width(T);
scope = localScopeTokenFromFile(filePath);
canonicalized = false;
if strlength(scope) > 0
    T = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, T);
    canonicalized = true;
end
originalWidth = width(T);
T = sixgr.util.pruneStructurallyBlankTableColumns(T);
removedCount = max(0, inputWidth - originalWidth) + max(0, originalWidth - width(T));
if removedCount <= 0 && ~canonicalized
    [rawChanged, rawRemoved] = localPruneRawBlankCSVColumns(filePath);
    changed = rawChanged;
    removedCount = rawRemoved;
    return;
end
sixgr.util.csvWriteTable(filePath, T);
changed = true;
[rawChanged, rawRemoved] = localPruneRawBlankCSVColumns(filePath);
changed = changed || rawChanged;
removedCount = removedCount + rawRemoved;
end

function scope = localScopeTokenFromFile(filePath)
[~, name, ~] = fileparts(char(string(filePath)));
scope = "";
name = string(name);
scopeMap = struct( ...
    'live_modulation_demodulation_trace', "modulation_demodulation", ...
    'live_channel_estimation_tti', "channel_estimation", ...
    'live_channel_state_tti', "channel_state", ...
    'live_tx_rx_stage_trace', "tx_rx_stage_trace", ...
    'live_receiver_tracking_state', "receiver_tracking_state", ...
    'live_receiver_tracking_trace', "receiver_tracking_trace", ...
    'live_control_gating_state', "control_gating_state", ...
    'live_csirs_stats', "csirs_stats");
key = matlab.lang.makeValidName(char(name));
if isfield(scopeMap, key)
    scope = string(scopeMap.(key));
elseif startsWith(name, "live_")
    scope = erase(name, "live_");
end
scope = regexprep(lower(scope), "[^a-z0-9]+", "_");
end

function rel = localRelativeToRunFolder(runFolder, pathStr)
runFolder = string(runFolder);
pathStr = string(pathStr);
rel = pathStr;
prefix = runFolder + filesep;
if startsWith(pathStr, prefix, "IgnoreCase", true)
    rel = extractAfter(pathStr, strlength(prefix));
end
end

function out = localPortablePath(in)
vals = string(in(:));
vals = replace(vals, "\", "/");
if isscalar(vals)
    out = char(vals);
else
    out = vals;
end
end

function [changed, removedCount] = localPruneRawBlankCSVColumns(filePath)
changed = false;
removedCount = 0;
try
    cells = readcell(filePath, "Delimiter", ",");
catch
    return;
end
if isempty(cells) || size(cells, 1) < 2 || size(cells, 2) < 1
    return;
end
keepMask = false(1, size(cells, 2));
for j = 1:size(cells, 2)
    keepMask(j) = ~all(arrayfun(@(i)localCellIsBlank(cells{i, j}), 2:size(cells, 1)));
end
removedCount = sum(~keepMask);
if removedCount <= 0
    return;
end
cells = cells(:, keepMask);
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
for i = 1:size(cells, 1)
    row = strings(1, size(cells, 2));
    for j = 1:size(cells, 2)
        row(j) = localCSVCellText(cells{i, j});
    end
    fprintf(fid, "%s\n", strjoin(row, ","));
end
changed = true;
end

function tf = localCellIsBlank(value)
if isempty(value)
    tf = true;
    return;
end
if ismissing(value)
    tf = true;
    return;
end
if isnumeric(value)
    tf = ~any(isfinite(double(value)));
    return;
end
if islogical(value)
    tf = false;
    return;
end
try
    txt = string(value);
    trimmed = lower(strtrim(txt));
    tf = all(strlength(trimmed) == 0 | trimmed == "nan" | txt == "<missing>" | trimmed == "not_applicable");
catch
    tf = false;
end
end

function txt = localCSVCellText(value)
if localCellIsBlank(value)
    txt = "";
elseif isnumeric(value)
    if ~isfinite(double(value))
        txt = "";
    else
        txt = string(value);
    end
elseif islogical(value)
    txt = string(value);
else
    txt = string(value);
end
txt = replace(txt, """", """""");
if contains(txt, ",") || contains(txt, """") || contains(txt, newline)
    txt = """" + txt + """";
end
end
