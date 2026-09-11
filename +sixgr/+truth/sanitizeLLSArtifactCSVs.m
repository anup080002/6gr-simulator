function out = sanitizeLLSArtifactCSVs(runFolder, varargin)
%SANITIZELLSARTIFACTCSVS Remove structurally blank columns from browser-facing CSVs.
%
% This post-pass is intentionally conservative: it never fabricates values,
% but it removes columns that are entirely blank or entirely inactive for the
% current run. Live signal-chain tables are first canonicalized so truthfully
% emitted semantic metadata is preserved before pruning.  OnlyPaths lets a
% plot producer stabilize its exact declared source CSVs before recording
% lineage hashes; the same transformation is then byte-idempotent when the
% whole run is finalized.

p = inputParser;
p.addParameter("OnlyPaths", strings(0, 1), ...
    @(x) ischar(x) || isstring(x) || iscellstr(x));
p.parse(varargin{:});
onlyPaths = string(p.Results.OnlyPaths(:));
onlyPaths = onlyPaths(strlength(strtrim(onlyPaths)) > 0);

runFolder = char(localCanonicalPath(runFolder));

if ~isempty(onlyPaths)
    files = localValidatedOwnedPaths(runFolder, onlyPaths);
    rows = repmat(struct("LogicalPath","", "Changed", false, "RemovedColumnCount", 0), 0, 1);
    for i = 1:numel(files)
        filePath = char(files(i));
        [changed, removedCount] = localSanitizeOneCSV(filePath);
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "LogicalPath", string(localPortablePath(localRelativeToRunFolder(runFolder, filePath))), ...
            "Changed", logical(changed), ...
            "RemovedColumnCount", double(removedCount));
    end
    out = struct("Files", struct2table(rows));
    return;
end

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

function files = localValidatedOwnedPaths(runFolder, pathValues)
root = localCanonicalPath(runFolder);
files = strings(0, 1);
for i = 1:numel(pathValues)
    candidate = string(pathValues(i));
    if ~localLooksAbsolute(candidate)
        candidate = fullfile(root, strrep(char(candidate), "/", filesep));
    end
    candidate = localCanonicalPath(candidate);
    if candidate ~= root && ~startsWith(candidate, root + string(filesep), ...
            "IgnoreCase", ispc)
        error("sixgr:truth:ArtifactCSVOutsideRun", ...
            "CSV sanitization path must remain inside the run root: %s", ...
            char(candidate));
    end
    if exist(candidate, "file") ~= 2
        continue;
    end
    [~, ~, ext] = fileparts(char(candidate));
    if lower(string(ext)) ~= ".csv"
        error("sixgr:truth:ArtifactCSVExpected", ...
            "Targeted artifact sanitization accepts CSV files only: %s", ...
            char(candidate));
    end
    files(end+1, 1) = candidate; %#ok<AGROW>
end
files = unique(files, "stable");
end

function tf = localLooksAbsolute(pathValue)
pathValue = char(string(pathValue));
tf = ~isempty(regexp(pathValue, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(string(pathValue), "\\\\") || startsWith(string(pathValue), "/");
end

function value = localCanonicalPath(pathValue)
value = string(char(java.io.File(char(string(pathValue))).getCanonicalPath()));
end

function [changed, removedCount] = localSanitizeOneCSV(filePath)
changed = false;
removedCount = 0;
if localPreserveDeclaredRawSchemaFile(filePath)
    % Canonical metric catalogs contain deliberately heterogeneous text
    % values (timestamps, histogram encodings, artifact paths and numeric
    % renderings) in one ValueText column.  MATLAB readtable type inference
    % can coerce that column to double and silently replace the nonnumeric
    % values with NaN.  These files were already written atomically with
    % PreserveSchema=true, so the only lossless sanitizer operation is a
    % byte-preserving no-op.
    return;
end
try
    T = sixgr.util.csvReadTable(filePath);
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
if localPreserveDeclaredSchemaScope(scope) || localPreserveDeclaredSchemaFile(filePath)
    % Canonical waveform/control trial schemas are versioned interfaces.
    % A column that is not applicable in this run (for example the second
    % hop PRB while hopping is disabled) must stay present as missing data;
    % removing it changes the interface and also changes the DB mirror.
    % readtable infers an entirely blank CSV field as a numeric NaN column.
    % Writing that inferred table back would turn honest absence into the
    % literal token "NaN" on every row.  A CSV has no numeric type metadata,
    % so preserve the declared header while serializing wholly absent fields
    % as empty strings.  Mixed measured/missing numeric columns are left
    % untouched; this rule cannot erase a partially observed measurement.
    T = localNormalizeDeclaredAllMissingColumns(T);
    removedCount = max(0, inputWidth - originalWidth);
    sixgr.util.csvWriteTable(filePath, T, "PreserveSchema", true);
    changed = canonicalized;
    return;
end

T = sixgr.util.pruneStructurallyBlankTableColumns(T);
removedCount = max(0, inputWidth - originalWidth) + max(0, originalWidth - width(T));
if removedCount <= 0 && ~canonicalized
    [rawChanged, rawRemoved] = localPruneRawBlankCSVColumns( ...
        filePath, string(T.Properties.VariableNames));
    changed = rawChanged;
    removedCount = rawRemoved;
    return;
end
sixgr.util.csvWriteTable(filePath, T);
changed = true;
[rawChanged, rawRemoved] = localPruneRawBlankCSVColumns( ...
    filePath, string(T.Properties.VariableNames));
changed = changed || rawChanged;
removedCount = removedCount + rawRemoved;
end

function T = localNormalizeDeclaredAllMissingColumns(T)
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    name = char(names(i));
    column = T.(name);
    if localColumnIsEntirelyMissing(column)
        T.(name) = strings(height(T), 1);
    end
end
end

function tf = localColumnIsEntirelyMissing(column)
if isempty(column)
    tf = true;
    return;
end
if isnumeric(column)
    % Infinity is invalid measured data, not absence.  Never conceal it.
    tf = all(isnan(double(column(:))));
    return;
end
if islogical(column)
    tf = false;
    return;
end
try
    values = string(column(:));
    normalized = lower(strtrim(fillmissing(values, "constant", "")));
    tf = all(ismissing(values) | strlength(normalized) == 0 | ...
        normalized == "nan" | normalized == "<missing>" | ...
        normalized == "null");
catch
    try
        tf = all(ismissing(column(:)));
    catch
        tf = false;
    end
end
end

function tf = localPreserveDeclaredSchemaFile(filePath)
% These tables are versioned evidence interfaces.  Some required fields are
% legitimately all-missing for a diagnostic run (for example a measured FRC
% crossing that was not statistically resolved, or scheduled-MCS metadata
% in a fixed-MCS campaign).  Their absence is semantically different from a
% declared column containing missing values, so the sanitizer must retain
% the declared schema without manufacturing values.
[~, name, ~] = fileparts(char(string(filePath)));
name = lower(string(name));
tf = any(name == [ ...
    "dl_fixed_link_campaign_trials", ...
    "ul_fixed_link_campaign_trials", ...
    "frc_reference_diagnostic", ...
    "frc_reference_qualification", ...
    "frc_reference_plot_lineage", ...
    "rank_layer_trials", ...
    "mimo_config_strict", ...
    "mimo_configured_vs_effective", ...
    "beam_precoder_table", ...
    "phy_signal_diagnostic_source", ...
    "live_harq_observation_timeline", ...
    "live_harq_observation_summary", ...
    "kpi_formula_registry", ...
    "kpi_source_table_manifest", ...
    "kpi_raw_table_schema_audit", ...
    "kpi_reconstruction_summary", ...
    "kpi_row_contributions_ul", ...
    "kpi_row_contributions_dl", ...
    "kpi_harq_delivery_trace_ul", ...
    "kpi_harq_delivery_trace_dl", ...
    "kpi_direction_isolation_audit", ...
    "kpi_legacy_alias_map", ...
    "kpi_known_bug_regression", ...
    "kpi_unit_conversion_audit", ...
    "kpi_duration_source_audit", ...
    "kpi_objective_binding"]) || ...
    name == "two_mode_acceptance_gates" || ...
    localPreserveDeclaredRawSchemaFile(filePath);
end

function tf = localPreserveDeclaredRawSchemaFile(filePath)
[~, name, ~] = fileparts(char(string(filePath)));
name = lower(string(name));
tf = any(name == [ ...
    "run_metadata_outputs", ...
    "basic_phy_performance_outputs", ...
    "coding_decoder_outputs", ...
    "modulation_shaping_outputs", ...
    "channel_estimation_tracking_outputs", ...
    "pdcch_control_outputs", ...
    "pdsch_outputs", ...
    "pusch_pucch_outputs", ...
    "csi_outputs", ...
    "beam_management_outputs", ...
    "initial_access_random_access_outputs", ...
    "harq_outputs", ...
    "energy_efficiency_outputs", ...
    "complexity_implementation_outputs", ...
    "ai_ml_outputs", ...
    "debug_trace_outputs", ...
    "aggregated_reporting_outputs", ...
    "beam_codebook", ...
    "lls_output_metric_rows", ...
    "lls_output_spec_coverage"]);
end

function scope = localScopeTokenFromFile(filePath)
[~, name, ~] = fileparts(char(string(filePath)));
scope = "";
name = string(name);
scopeMap = struct( ...
    'dl_fixed_link_campaign_trials', "dl_fixed_link_campaign_trials", ...
    'ul_fixed_link_campaign_trials', "ul_fixed_link_campaign_trials", ...
    'dl_pdsch_trials', "dl_pdsch_trials", ...
    'ul_pusch_trials', "ul_pusch_trials", ...
    'pdcch_trials', "pdcch_trials", ...
    'pucch_trials', "pucch_trials", ...
    'prach_trials', "prach_trials", ...
    'pbch_trials', "pbch_trials", ...
    'srs_trials', "srs_trials", ...
    'trs_trials', "trs_trials", ...
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

function tf = localPreserveDeclaredSchemaScope(scope)
scope = lower(strtrim(string(scope)));
tf = any(scope == ["dl_pdsch_trials", "ul_pusch_trials", ...
    "pdcch_trials", "pucch_trials", "prach_trials", "pbch_trials", ...
    "srs_trials", "trs_trials"]);
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

function [changed, removedCount] = localPruneRawBlankCSVColumns(filePath, preserveColumns)
changed = false;
removedCount = 0;
if nargin < 2
    preserveColumns = strings(0, 1);
end
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
    header = strtrim(string(cells{1, j}));
    keepMask(j) = any(strcmpi(header, preserveColumns)) || ...
        ~all(arrayfun(@(i)localCellIsBlank(cells{i, j}), 2:size(cells, 1)));
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
