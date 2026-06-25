function out = scanTruthArtifacts(runFolder, summary)
%SCANTRUTHARTIFACTS Reject proxy/fallback markers in primary truth artifacts.

files = strings(0,1);
layout = sixgr.report.resultLayout(runFolder);
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"))];
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "system_waveform_scale_profile.csv"))];
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "system_waveform_runtime_profile.csv"))];
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "live_stage_status.csv"))];
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"))];
files = [files; localExistingFile(fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "lls_measured_sinr_summary.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_bler_curve.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_bler_curve.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_throughput_curve.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_throughput_curve.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "distance_vs_sinr.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "cell_search_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "pbch_recovery_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "prach_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "pdcch_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "pucch_trials.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "attach_state_trace.csv"))];
files = [files; localExistingFile(fullfile(runFolder, "control", "csv", "rrc_message_trace.csv"))];
files = [files; localExistingFile(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"))];
files = [files; localExistingFile(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_kpis.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_time_series.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_scheduler_grants.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_harq_processes.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_cell_load.csv"))];
files = [files; localExistingFile(fullfile(layout.SystemCSVDir, "system_interference_detail.csv"))];

summaryFields = ["E2ESummaryCSV","E2EPacketIntegrityCSV","E2EPacketTraceCSV","E2EFlowSummaryCSV", ...
    "E2EBearerSummaryCSV","E2EAttachTraceCSV","E2ESchedulerTraceCSV","E2EHARQTraceCSV","E2EDropCausesCSV"];
for i = 1:numel(summaryFields)
    fn = summaryFields(i);
    if isfield(summary, fn)
        files = [files; localExistingFile(char(string(summary.(char(fn)))))] ; %#ok<AGROW>
    end
end
files = unique(files(strlength(files) > 0), "stable");

rows = repmat(struct("File","","IssueCount",0,"IssueTokens","","Status","", ...
    "AllowedDisclosureCount",0,"ScannedValueCount",0), numel(files), 1);
totalIssues = 0;
for i = 1:numel(files)
    [issueCount, hits, allowedCount, valueCount] = localScanArtifactFile(files(i));
    rows(i) = struct( ...
        "File", string(files(i)), ...
        "IssueCount", double(issueCount), ...
        "IssueTokens", strjoin(cellstr(unique(hits, "stable")), ", "), ...
        "Status", localTernary(issueCount == 0, "ok", "forbidden_token_found"), ...
        "AllowedDisclosureCount", double(allowedCount), ...
        "ScannedValueCount", double(valueCount));
    totalIssues = totalIssues + issueCount;
end

if isempty(rows)
    T = table(string.empty(0,1), zeros(0,1), string.empty(0,1), string.empty(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'File','IssueCount','IssueTokens','Status','AllowedDisclosureCount','ScannedValueCount'});
else
    T = struct2table(rows, "AsArray", true);
end

csvFile = layout.TruthScanCSV;
sixgr.util.csvWriteTable(csvFile, T);

out = struct();
out.Ok = (totalIssues == 0);
out.Table = T;
out.CSV = csvFile;
out.IssueCount = double(totalIssues);

if totalIssues > 0
    error("sixgr:truth:PrimaryArtifactsContainProxyMarkers", ...
        "Truth validation artifacts contain forbidden proxy/fallback markers.");
end
end

function p = localExistingFile(pathStr)
p = string(pathStr);
if strlength(p) == 0 || exist(char(p), "file") ~= 2
    p = "";
end
end

function [issueCount, hits, allowedCount, valueCount] = localScanArtifactFile(filePath)
tokens = ["fallback";"proxy";"lut";"logistic";"synthetic";"FAST_PROXY"];
[values, fields] = localArtifactValues(filePath);
hits = strings(0,1);
issueCount = 0;
allowedCount = 0;
valueCount = double(numel(values));
for i = 1:numel(values)
    v = string(values(i));
    fieldName = "";
    if numel(fields) >= i
        fieldName = fields(i);
    end
    for k = 1:numel(tokens)
        token = tokens(k);
        if ~localContainsForbiddenToken(v, token)
            continue;
        end
        if localAllowedTruthDisclosure(v, fieldName)
            allowedCount = allowedCount + 1;
            continue;
        end
        issueCount = issueCount + 1;
        hits(end+1,1) = token; %#ok<AGROW>
    end
end
end

function [values, fields] = localArtifactValues(filePath)
values = strings(0,1);
fields = strings(0,1);
filePath = char(string(filePath));
if endsWith(lower(string(filePath)), ".csv")
    try
        opts = detectImportOptions(filePath, "Delimiter", ",");
        opts.VariableNamingRule = "preserve";
        T = readtable(filePath, opts);
        [values, fields] = localTableValues(T);
        return;
    catch
    end
end

try
    lines = splitlines(string(fileread(filePath)));
catch
    return;
end
if endsWith(lower(string(filePath)), ".csv") && numel(lines) > 1
    lines = lines(2:end);
end
values = lines(strlength(strtrim(lines)) > 0);
fields = repmat("line", numel(values), 1);
end

function [values, fields] = localTableValues(T)
values = strings(0,1);
fields = strings(0,1);
if ~istable(T)
    return;
end
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    raw = T.(char(names(i)));
    try
        if iscell(raw)
            vals = string(raw(:));
        elseif isstring(raw) || ischar(raw) || iscategorical(raw)
            vals = string(raw(:));
        else
            vals = string(raw(:));
        end
        values = [values; vals(:)]; %#ok<AGROW>
        fields = [fields; repmat(names(i), numel(vals), 1)]; %#ok<AGROW>
    catch
    end
end
keep = strlength(strtrim(values)) > 0;
values = values(keep);
fields = fields(keep);
end

function tf = localContainsForbiddenToken(value, token)
value = char(string(value));
token = char(string(token));
if strcmpi(token, "FAST_PROXY")
    tf = ~isempty(regexpi(value, 'FAST_PROXY', 'once'));
    return;
end
if strcmpi(token, "lut")
    tf = ~isempty(regexpi(lower(value), '(^|[^A-Za-z0-9])lut([^A-Za-z0-9]|$)', 'once'));
    return;
end
pat = ['(^|[^A-Za-z0-9])' regexptranslate('escape', lower(token)) '([^A-Za-z0-9]|$)'];
tf = ~isempty(regexpi(lower(value), pat, 'once'));
end

function tf = localAllowedTruthDisclosure(value, ~)
v = lower(strtrim(char(string(value))));
allowedNeedles = { ...
    'unavailable', 'not_', 'not-', 'not ', 'no_', 'no-', 'no ', ...
    'without', 'blocked', 'removed', 'disabled', 'false', ...
    'not_materialized', 'does_not', 'must_be_waveform'};
tf = false;
for i = 1:numel(allowedNeedles)
    if contains(v, allowedNeedles{i})
        tf = true;
        return;
    end
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
