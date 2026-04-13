function out = scanTruthArtifacts(runFolder, summary)
%SCANTRUTHARTIFACTS Reject proxy/fallback markers in primary truth artifacts.

files = strings(0,1);
layout = sixgr.report.resultLayout(runFolder);
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv"))];
files = [files; localExistingFile(fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv"))];
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

summaryFields = ["E2ESummaryCSV","E2EPacketIntegrityCSV","E2EPacketTraceCSV","E2EFlowSummaryCSV", ...
    "E2EBearerSummaryCSV","E2EAttachTraceCSV","E2ESchedulerTraceCSV","E2EHARQTraceCSV","E2EDropCausesCSV"];
for i = 1:numel(summaryFields)
    fn = summaryFields(i);
    if isfield(summary, fn)
        files = [files; localExistingFile(char(string(summary.(char(fn)))))] ; %#ok<AGROW>
    end
end
files = unique(files(strlength(files) > 0), "stable");

rows = repmat(struct("File","","IssueCount",0,"IssueTokens","","Status",""), numel(files), 1);
totalIssues = 0;
for i = 1:numel(files)
    txt = "";
    try
        txt = fileread(char(files(i)));
    catch
    end
    hits = strings(0,1);
    if ~isempty(regexpi(txt, '\bfallback\b', 'once')), hits(end+1,1) = "fallback"; end %#ok<AGROW>
    if ~isempty(regexpi(txt, '\bproxy\b', 'once')), hits(end+1,1) = "proxy"; end %#ok<AGROW>
    if ~isempty(regexpi(txt, '\blut\b', 'once')), hits(end+1,1) = "lut"; end %#ok<AGROW>
    if ~isempty(regexpi(txt, '\blogistic\b', 'once')), hits(end+1,1) = "logistic"; end %#ok<AGROW>
    if ~isempty(regexpi(txt, '\bsynthetic\b', 'once')), hits(end+1,1) = "synthetic"; end %#ok<AGROW>
    if ~isempty(regexpi(txt, 'FAST_PROXY', 'once')), hits(end+1,1) = "FAST_PROXY"; end %#ok<AGROW>
    rows(i) = struct( ...
        "File", string(files(i)), ...
        "IssueCount", double(numel(hits)), ...
        "IssueTokens", strjoin(cellstr(hits), ", "), ...
        "Status", localTernary(numel(hits) == 0, "ok", "forbidden_token_found"));
    totalIssues = totalIssues + numel(hits);
end

if isempty(rows)
    T = table(string.empty(0,1), zeros(0,1), string.empty(0,1), string.empty(0,1), ...
        'VariableNames', {'File','IssueCount','IssueTokens','Status'});
else
    T = struct2table(rows);
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

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
