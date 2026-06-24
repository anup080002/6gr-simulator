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
registry = sixgr.utils.verifyFunctionRegistry("Strict", logical(opt.StrictRegistry));

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
runner = sixgr.lls6g.runners.runSingle(scenarioYAML, string(opt.ResultsRoot), runTag);
out.Runner = runner;
out.RunFolder = string(runner.RunFolder);

fprintf("[Export] Writing Prompt 9 evidence and audits...\n");
exportReport = sixgr.export.exportAllEvidence(runner, runner.Config, out.RunFolder, ...
    "RunAnalysis", logical(opt.RunAnalysis), ...
    "ErrorOnOracleViolation", false);
out.Export = exportReport;

fprintf("[Audit] Verifying measurement-only contracts...\n");
measurementOnly = sixgr.audit.verifyMeasurementOnly(out.RunFolder, ...
    "ErrorOnViolation", logical(opt.ErrorOnOracleViolation));
out.MeasurementOnly = measurementOnly;

profile off;
sixgr.analytics.buildRuntimeCallGraph(out.RunFolder);

fprintf("[Gate] Running Grade 10 checklist...\n");
grade = grade10Checklist(out.RunFolder);
out.Grade10 = grade;

out.Ok = logical(registry.Ok) && logical(runner.Ok) && ...
    logical(exportReport.Ok) && logical(measurementOnly.Ok) && logical(grade.Ok);
out.Status = "complete";
out.WallTime_s = toc(tStart);

fprintf("\n=== run_true_lls complete: %.0fs wall, ResultOk=%d ===\n", out.WallTime_s, out.Ok);
end
