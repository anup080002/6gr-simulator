function artifacts = writeImplementationValidationReport(runFolder, validation)
%WRITEIMPLEMENTATIONVALIDATIONREPORT Persist Actual LLS validation summaries.

layout = sixgr.report.resultLayout(runFolder);
jsonDir = fullfile(layout.ReportDir, "json");
mdDir = fullfile(layout.ReportDir, "md");
htmlDir = fullfile(layout.ReportDir, "html");
sixgr.util.ensureFolder(jsonDir);
sixgr.util.ensureFolder(mdDir);
sixgr.util.ensureFolder(htmlDir);

artifacts = struct();
artifacts.PHYBlockValidationSummaryJSON = fullfile(jsonDir, "phy_block_validation_summary.json");
artifacts.DUTReferenceComparisonSummaryJSON = fullfile(jsonDir, "dut_reference_comparison_summary.json");
artifacts.MarkdownReport = fullfile(mdDir, "actual_lls_implementation_validation_report.md");
artifacts.HTMLReport = fullfile(htmlDir, "actual_lls_implementation_validation_report.html");

summaryPayload = localSummaryPayload(validation);
comparisonPayload = localComparisonPayload(validation);

localJsonWrite(artifacts.PHYBlockValidationSummaryJSON, summaryPayload);
localJsonWrite(artifacts.DUTReferenceComparisonSummaryJSON, comparisonPayload);

localWriteMarkdown(artifacts.MarkdownReport, validation);
localWriteHTML(artifacts.HTMLReport, validation);
end

function payload = localSummaryPayload(validation)
summary = validation.Summary;
payload = struct();
payload.RunId = string(summary.RunId);
payload.ActualLLSVerdict = string(summary.ActualLLSVerdict);
payload.VerdictSentence = string(summary.VerdictSentence);
payload.EnabledBlockCount = double(summary.EnabledBlockCount);
payload.PassingBlockCount = double(summary.PassingBlockCount);
payload.ReferenceComparedBlockCount = double(summary.ReferenceComparedBlockCount);
payload.NumericalSanityFailureCount = double(summary.NumericalSanityFailureCount);
payload.FunctionNotCalled = cellstr(string(summary.FunctionNotCalled(:)));
payload.BypassedBlocks = cellstr(string(summary.BypassedBlocks(:)));
payload.LabelOnlyBlocks = cellstr(string(summary.LabelOnlyBlocks(:)));
payload.ProxyBlocks = cellstr(string(summary.ProxyBlocks(:)));
payload.FallbackBlocks = cellstr(string(summary.FallbackBlocks(:)));
payload.TopNumericalFindings = localStructRows(validation.TopNumericalFindings);
payload.SubsystemOutcomes = localStructRows(validation.PHYOutcomeSummary);
end

function payload = localComparisonPayload(validation)
payload = struct();
payload.RunId = string(validation.Summary.RunId);
payload.TotalComparisons = double(height(validation.DUTReferenceComparison));
payload.PassCount = double(sum(localTableLogical(validation.DUTReferenceComparison, "Pass")));
payload.FailCount = double(sum(~localTableLogical(validation.DUTReferenceComparison, "Pass")));
payload.ReferenceUnavailableBlocks = cellstr(string(validation.Summary.ReferenceUnavailableBlocks(:)));
payload.ReferenceSummary = localStructRows(validation.ReferenceComparisonSummary);
end

function localWriteMarkdown(pathOut, validation)
fid = fopen(pathOut, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

summary = validation.Summary;
fprintf(fid, "# Actual LLS Implementation Verdict\n\n");
fprintf(fid, "- Verdict: `%s`\n", string(summary.ActualLLSVerdict));
fprintf(fid, "- Statement: %s\n", string(summary.VerdictSentence));
fprintf(fid, "- Enabled blocks: `%d`\n", double(summary.EnabledBlockCount));
fprintf(fid, "- Passing blocks: `%d`\n", double(summary.PassingBlockCount));
fprintf(fid, "- Blocks compared against a reference path: `%d`\n", double(summary.ReferenceComparedBlockCount));
fprintf(fid, "- Numerical sanity failures: `%d`\n", double(summary.NumericalSanityFailureCount));
fprintf(fid, "\n## Major Subsystems\n\n");
fprintf(fid, "| Subsystem | Feature | Runtime Path | Reference | Numerical Sanity | Negative Tests | Pass |\n");
fprintf(fid, "|---|---|---|---|---|---|---|\n");
for i = 1:height(validation.PHYOutcomeSummary)
    row = validation.PHYOutcomeSummary(i, :);
    fprintf(fid, "| %s | %s | %s | %s | %s | %s | %s |\n", ...
        string(row.Subsystem), string(row.Feature), ...
        localYesNo(row.ActualRuntimePathUsed), ...
        localReferenceStatus(validation, string(row.Feature)), ...
        localPassFail(row.NumericalValuesPlausible), ...
        localPassFail(row.NegativeTestsPassed), ...
        localPassFail(row.OverallBlockPass));
end

fprintf(fid, "\n## Top Numerical Findings\n\n");
for i = 1:height(validation.TopNumericalFindings)
    row = validation.TopNumericalFindings(i, :);
    fprintf(fid, "- `%s`: `%s %s` from `%s`\n", ...
        string(row.MetricName), string(row.DisplayValue), string(row.Units), string(row.SourceArtifact));
end

fprintf(fid, "\n## Functions Not Called\n\n");
if isempty(summary.FunctionNotCalled)
    fprintf(fid, "- None.\n");
else
    for i = 1:numel(summary.FunctionNotCalled)
        fprintf(fid, "- `%s`\n", string(summary.FunctionNotCalled(i)));
    end
end

fprintf(fid, "\n## Bypass And Label Risks\n\n");
localWriteStringList(fid, "Bypassed blocks", summary.BypassedBlocks);
localWriteStringList(fid, "Label-only/proxy detections", unique([summary.LabelOnlyBlocks(:); summary.ProxyBlocks(:); summary.FallbackBlocks(:)]));

fprintf(fid, "\n## DUT-vs-Reference Mismatches\n\n");
failed = validation.DUTReferenceComparison(~localTableLogical(validation.DUTReferenceComparison, "Pass"), :);
if isempty(failed)
    fprintf(fid, "- None.\n");
else
    maxRows = min(height(failed), 12);
    for i = 1:maxRows
        fprintf(fid, "- `%s`: `%s` vs `%s`, delta `%s`, reason `%s`\n", ...
            localTextScalar(failed.BlockId(i)), localTextScalar(failed.DUTOutputName(i)), localTextScalar(failed.ReferenceOutputName(i)), ...
            localTextScalar(failed.DeltaAbs(i)), localTextScalar(failed.FailureReason(i)));
    end
end
end

function localWriteHTML(pathOut, validation)
summary = validation.Summary;
subRows = localHTMLRows(validation.PHYOutcomeSummary, validation);
findingRows = localHTMLRows(validation.TopNumericalFindings, validation);
html = [
    "<!doctype html>"
    "<html><head><meta charset=""utf-8"">"
    "<title>Actual LLS Implementation Validation Report</title>"
    "<style>body{font-family:Arial,sans-serif;margin:24px;}table{border-collapse:collapse;width:100%;margin:16px 0;}th,td{border:1px solid #d0d0d0;padding:6px 8px;text-align:left;}th{background:#f3f6f8;}code{background:#f4f4f4;padding:1px 4px;}ul{padding-left:20px;}</style>"
    "</head><body>"
    "<h1>Actual LLS Implementation Verdict</h1>"
    "<p><strong>Verdict:</strong> <code>" + localEscapeHTML(summary.ActualLLSVerdict) + "</code></p>"
    "<p>" + localEscapeHTML(summary.VerdictSentence) + "</p>"
    "<p>Enabled blocks: <code>" + string(summary.EnabledBlockCount) + "</code> | Passing blocks: <code>" + string(summary.PassingBlockCount) + "</code> | Reference-compared blocks: <code>" + string(summary.ReferenceComparedBlockCount) + "</code></p>"
    "<h2>Major Subsystems</h2>"
    "<table><thead><tr><th>Subsystem</th><th>Feature</th><th>Runtime Path</th><th>Reference</th><th>Numerical Sanity</th><th>Negative Tests</th><th>Pass</th></tr></thead><tbody>"
    subRows
    "</tbody></table>"
    "<h2>Top Numerical Findings</h2>"
    "<table><thead><tr><th>Metric</th><th>Value</th><th>Units</th><th>Source</th></tr></thead><tbody>"
    findingRows
    "</tbody></table>"
    "</body></html>"
    ];
localWriteText(pathOut, strjoin(cellstr(html), newline));
end

function rows = localHTMLRows(T, validation)
rows = strings(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
if all(ismember(["Subsystem","Feature","ActualRuntimePathUsed","ReferenceCompared","NumericalValuesPlausible","NegativeTestsPassed","OverallBlockPass"], vars))
    for i = 1:height(T)
        refStatus = localReferenceStatus(validation, string(T.Feature(i)));
        rows(end+1, 1) = "<tr><td>" + localEscapeHTML(T.Subsystem(i)) + "</td><td>" + ... %#ok<AGROW>
            localEscapeHTML(T.Feature(i)) + "</td><td>" + localEscapeHTML(localYesNo(T.ActualRuntimePathUsed(i))) + ...
            "</td><td>" + localEscapeHTML(refStatus) + "</td><td>" + ...
            localEscapeHTML(localPassFail(T.NumericalValuesPlausible(i))) + "</td><td>" + ...
            localEscapeHTML(localPassFail(T.NegativeTestsPassed(i))) + "</td><td>" + ...
            localEscapeHTML(localPassFail(T.OverallBlockPass(i))) + "</td></tr>";
    end
elseif all(ismember(["MetricName","DisplayValue","Units","SourceArtifact"], vars))
    for i = 1:height(T)
        rows(end+1, 1) = "<tr><td>" + localEscapeHTML(T.MetricName(i)) + "</td><td>" + ... %#ok<AGROW>
            localEscapeHTML(T.DisplayValue(i)) + "</td><td>" + localEscapeHTML(T.Units(i)) + ...
            "</td><td>" + localEscapeHTML(T.SourceArtifact(i)) + "</td></tr>";
    end
end
end

function localWriteStringList(fid, titleText, values)
fprintf(fid, "- %s:\n", titleText);
if isempty(values)
    fprintf(fid, "  none\n");
    return;
end
for i = 1:numel(values)
    fprintf(fid, "  %s\n", localTextScalar(values(i)));
end
end

function out = localStructRows(T)
if ~(istable(T) && ~isempty(T))
    out = struct([]);
    return;
end
out = table2struct(T);
end

function tf = localTableLogical(T, name)
tf = false(height(T), 1);
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = T.(name);
try
    tf = logical(raw);
catch
    txt = lower(strtrim(string(raw)));
    tf = ismember(txt, ["1","true","yes","on","pass"]);
end
tf = tf(:);
end

function out = localYesNo(value)
if logical(value)
    out = "yes";
else
    out = "no";
end
end

function out = localPassFail(value)
if logical(value)
    out = "pass";
else
    out = "fail";
end
end

function out = localPassFailNA(value)
if any(ismissing(string(value))) || strlength(strtrim(string(value))) == 0
    out = "unavailable";
elseif logical(value)
    out = "pass";
else
    out = "fail";
end
end

function out = localReferenceStatus(validation, blockId)
out = "unavailable";
if ~(isstruct(validation) && isfield(validation, "ReferenceComparisonSummary") && ...
        istable(validation.ReferenceComparisonSummary) && ~isempty(validation.ReferenceComparisonSummary))
    return;
end
summaryT = validation.ReferenceComparisonSummary;
mask = string(summaryT.BlockId) == string(blockId);
if ~any(mask)
    return;
end
row = summaryT(find(mask, 1, "first"), :);
if ~logical(row.ReferenceAvailable)
    return;
end
if logical(row.DUTReferencePass)
    out = "pass";
else
    out = "fail";
end
end

function out = localEscapeHTML(value)
out = string(value);
out = replace(out, "&", "&amp;");
out = replace(out, "<", "&lt;");
out = replace(out, ">", "&gt;");
out = replace(out, '"', "&quot;");
end

function out = localTextScalar(value)
out = string(value);
if any(ismissing(out))
    out(ismissing(out)) = "";
end
out = char(out);
end

function localJsonWrite(pathOut, payload)
payload = localJsonSafeValue(payload);
try
    txt = jsonencode(payload, "PrettyPrint", true);
catch
    txt = jsonencode(payload);
end
localWriteText(pathOut, string(txt) + newline);
end

function out = localJsonSafeValue(value)
if isa(value, "function_handle")
    out = struct("json_type", "function_handle", "text", func2str(value));
    return;
end
if istable(value)
    out = table2struct(value);
    return;
end
if iscell(value)
    out = value;
    for i = 1:numel(value)
        out{i} = localJsonSafeValue(value{i});
    end
    return;
end
if isstruct(value)
    out = value;
    fields = fieldnames(value);
    for idx = 1:numel(value)
        for f = 1:numel(fields)
            out(idx).(fields{f}) = localJsonSafeValue(value(idx).(fields{f}));
        end
    end
    return;
end
out = value;
end

function localWriteText(pathOut, txt)
pathOut = char(string(pathOut));
txt = char(string(txt));
sixgr.util.ensureDir(pathOut);
fid = fopen(pathOut, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:validation:WriteImplementationValidationReportOpenFailed", ...
        "Cannot open report artifact for writing: %s", pathOut);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, "char");
end
