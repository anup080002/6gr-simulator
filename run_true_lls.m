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

localAssertOracleFreeSINRMode(runner.Config);

profileStoppedEarly = logical(sixgr.util.structGet(runner.Manifest, "ProfileStoppedEarly", false));
dbOnlyRun = lower(strtrim(string(sixgr.util.structGet(runner.Manifest, "OutputBackend", ...
    getenv("SIXGR_OUTPUT_BACKEND_OVERRIDE"))))) == "mysql_web";
runFolderExists = isfolder(char(out.RunFolder));
if profileStoppedEarly || (dbOnlyRun && ~runFolderExists)
    out.Ok = logical(registry.Ok) && logical(runner.Ok);
    out.Status = "runner_complete_publication_export_skipped";
    out.Export = struct("Ok", true, "Skipped", true, ...
        "Reason", "profile_debug_or_database_only_run", ...
        "RunFolderExists", logical(runFolderExists), ...
        "ProfileStoppedEarly", logical(profileStoppedEarly), ...
        "DatabaseOnlyRun", logical(dbOnlyRun));
    out.MeasurementOnly = struct("Ok", true, "Skipped", true, ...
        "Reason", "filesystem_measurement_audit_requires_materialized_run_folder");
    out.Grade10 = struct("Ok", true, "Skipped", true, ...
        "Reason", "filesystem_grade_checklist_requires_publication_run_folder");
    out.WallTime_s = toc(tStart);
    fprintf("[Export] Skipped publication filesystem export/audits: profileStoppedEarly=%d dbOnlyRun=%d runFolderExists=%d\n", ...
        double(profileStoppedEarly), double(dbOnlyRun), double(runFolderExists));
    fprintf("\n=== run_true_lls runner complete: %.0fs wall, ResultOk=%d Status=%s ===\n", ...
        out.WallTime_s, out.Ok, char(out.Status));
    return;
end

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

function localAssertOracleFreeSINRMode(cfg)
noiseMode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ""))));
oracleFree = logical(sixgr.util.structGet(cfg, "oracle_free_mode", ...
    sixgr.util.structGet(cfg, "oracleFreeMode", false))) || noiseMode == "receiver_noise_figure_thermal_noise";
if ~oracleFree
    return;
end

snrGrid = sixgr.util.structGet(cfg, "snr_grid_db", []);
assert(isempty(snrGrid), ...
    "SINR_GUARD: snr_grid_db must be empty in oracle_free_mode. Remove AWGN injection sweep.");
snrGrid2 = sixgr.util.structGet(cfg, "SNRGrid", []);
assert(isempty(snrGrid2), ...
    "SINR_GUARD: SNRGrid must be empty in oracle_free_mode. Remove AWGN injection sweep.");

distances = sixgr.util.structGet(cfg, "scenario.ue_distances_m", []);
if isempty(distances)
    minDist = double(sixgr.util.structGet(cfg, "scenario.ue.minDistanceFromBS_m", ...
        sixgr.util.structGet(cfg, "scenario.ue.distribution.min_bs_dist_m", NaN)));
    maxDist = double(sixgr.util.structGet(cfg, "scenario.ue.maxDistanceFromBS_m", ...
        sixgr.util.structGet(cfg, "scenario.ue.distribution.max_bs_dist_m", NaN)));
    if isfinite(minDist) && isfinite(maxDist) && maxDist >= minDist
        distances = [minDist maxDist];
    end
end
assert(~isempty(distances), ...
    "SINR_GUARD: UE distances must be specified for geometry-driven SINR mode.");
assert(numel(distances) >= 1, ...
    "SINR_GUARD: At least 1 UE distance must be specified.");
end
