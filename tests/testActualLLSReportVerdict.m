function ok = testActualLLSReportVerdict()
%TESTACTUALLLSREPORTVERDICT Verify dedicated markdown/html/json verdict artifacts.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("partial_actual");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", true);

reportArtifacts = out.ReportArtifacts.ReportArtifacts;
assert(exist(reportArtifacts.MarkdownReport, "file") == 2, "Missing markdown implementation verdict report.");
assert(exist(reportArtifacts.HTMLReport, "file") == 2, "Missing HTML implementation verdict report.");
assert(exist(reportArtifacts.PHYBlockValidationSummaryJSON, "file") == 2, "Missing JSON summary payload.");

md = string(fileread(reportArtifacts.MarkdownReport));
html = string(fileread(reportArtifacts.HTMLReport));
jsonSummary = jsondecode(fileread(reportArtifacts.PHYBlockValidationSummaryJSON));

assert(contains(md, "Actual LLS Implementation Verdict"), ...
    "Markdown report must start with the actual implementation verdict section.");
assert(contains(md, "Partial NR LLS implementation: data-channel path executed"), ...
    "Markdown report must carry the partial-LLS verdict sentence.");
assert(contains(html, "Actual LLS Implementation Verdict"), ...
    "HTML report must include the verdict heading.");
assert(strcmp(string(jsonSummary.ActualLLSVerdict), "partial actual LLS"), ...
    "JSON summary must preserve the partial actual LLS verdict.");

ok = true;
end
