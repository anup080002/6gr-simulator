function out = run_true_lls(scenarioYAML, runTag, varargin)
%RUN_TRUE_LLS Prompt 9 master entrypoint for measurement-only LLS runs.
%
% This entrypoint composes the repository's validated config-driven LLS
% runner, then runs Prompt 9 registry, export, and measurement-only audits.

if nargin < 2
    runTag = "";
end

p = inputParser;
p.addParameter("ResultsRoot", "results", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("Execute", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("RunAnalysis", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("StrictRegistry", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("ErrorOnOracleViolation", true, @(x)islogical(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

tStart = tic;
fprintf("\n=== run_true_lls: initialising ===\n");
stageStart = tic;
registry = sixgr.utils.verifyFunctionRegistry("Strict", logical(opt.StrictRegistry));
fprintf("[STAGE] stage_name=registry elapsed=%.3fs\n", toc(stageStart));

out = struct();
out.Ok = false;
out.Registry = registry;
out.RunFolder = "";
out.Runner = struct();
out.Export = struct();
out.MeasurementOnly = struct();
out.Grade10 = struct();

if ~logical(opt.Execute)
    out.Ok = logical(registry.Ok);
    out.Status = "registry_only";
    out.WallTime_s = toc(tStart);
    fprintf("=== run_true_lls registry-only complete: ResultOk=%d ===\n", out.Ok);
    return;
end

profile on;
cleanupProfile = onCleanup(@() profile("off")); %#ok<NASGU>

fprintf("[Run] Executing config-driven LLS runner...\n");
stageStart = tic;
runner = sixgr.lls6g.runners.runSingle(scenarioYAML, string(opt.ResultsRoot), runTag);
fprintf("[STAGE] stage_name=lls_runner elapsed=%.3fs\n", toc(stageStart));
out.Runner = runner;
out.RunFolder = string(runner.RunFolder);

fprintf("[Export] Writing Prompt 9 evidence and audits...\n");
stageStart = tic;
exportReport = sixgr.export.exportAllEvidence(runner, runner.Config, out.RunFolder, ...
    "RunAnalysis", logical(opt.RunAnalysis), ...
    "ErrorOnOracleViolation", false);
fprintf("[STAGE] stage_name=export_all_evidence elapsed=%.3fs\n", toc(stageStart));
out.Export = exportReport;

fprintf("[Audit] Verifying measurement-only contracts...\n");
stageStart = tic;
measurementOnly = sixgr.audit.verifyMeasurementOnly(out.RunFolder, ...
    "ErrorOnViolation", logical(opt.ErrorOnOracleViolation));
fprintf("[STAGE] stage_name=measurement_only_audit elapsed=%.3fs\n", toc(stageStart));
violationCount = double(sixgr.util.structGet(measurementOnly, "ViolationCount", NaN));
if isfinite(violationCount) && violationCount == 0
    fprintf("[ORACLE_GUARD] PASS: 0 violations\n");
elseif isfinite(violationCount)
    fprintf("[ORACLE_GUARD] FAIL: %.0f violations\n", violationCount);
else
    fprintf("[ORACLE_GUARD] UNKNOWN: violation count unavailable\n");
end
out.MeasurementOnly = measurementOnly;

profile off;
stageStart = tic;
sixgr.analytics.buildRuntimeCallGraph(out.RunFolder);
fprintf("[STAGE] stage_name=runtime_call_graph elapsed=%.3fs\n", toc(stageStart));

fprintf("[Gate] Running Grade 10 checklist...\n");
stageStart = tic;
grade = grade10Checklist(out.RunFolder);
fprintf("[STAGE] stage_name=grade10_checklist elapsed=%.3fs\n", toc(stageStart));
out.Grade10 = grade;

out.Ok = logical(registry.Ok) && logical(runner.Ok) && ...
    logical(exportReport.Ok) && logical(measurementOnly.Ok) && logical(grade.Ok);
out.Status = "complete";
out.WallTime_s = toc(tStart);

fprintf("\n=== run_true_lls complete: %.0fs wall, ResultOk=%d ===\n", out.WallTime_s, out.Ok);
end
