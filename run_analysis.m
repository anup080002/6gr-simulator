function report = run_analysis(runDir, scenarioCfg)
%RUN_ANALYSIS Generate comprehensive analysis for a completed LLS run.
%
% This function does not rerun the scenario. It reads completed-run
% artifacts, derives secondary analysis tables, and builds HTML dashboards.

arguments
    runDir {mustBeTextScalar}
    scenarioCfg = struct()
end

runDir = char(string(runDir));
if exist(runDir, "dir") ~= 7
    error("sixgr:analysis:RunDirMissing", "Run directory does not exist: %s", runDir);
end

fprintf("\n=== 6GR Simulator v2 - Run Analysis ===\n");
fprintf("Run dir: %s\n\n", runDir);

fprintf("[1/5] Loading completed-run trial data...\n");
trialData = sixgr.analytics.loadAllTrialData(runDir);

fprintf("[2/5] Building derived analysis CSV tables...\n");
physicsT = sixgr.analytics.buildPhysicsAuditTable(runDir, scenarioCfg, trialData);
analyticsReport = sixgr.analytics.buildScenarioAnalyticsTables(runDir, trialData, scenarioCfg);

fprintf("[3/5] Exporting live instrumented traces if enabled...\n");
sixgr.analytics.CallFlowInstrumentor.getInstance().exportCSV();
sixgr.analytics.MessageLogger.getInstance().exportCSV();
sixgr.analytics.AlgorithmAuditLogger.getInstance().exportCSV();

fprintf("[4/5] Running Python visualization pipeline...\n");
pythonReports = localRunPostprocessors(runDir);

fprintf("[5/5] Validating analysis outputs...\n");
validation = sixgr.analytics.validateAnalysisOutputs(runDir);

report = struct( ...
    "RunDir", string(runDir), ...
    "PhysicsAuditRows", height(physicsT), ...
    "Analytics", analyticsReport, ...
    "PythonReports", pythonReports, ...
    "Validation", validation);

fprintf("\n=== Analysis Complete ===\n");
fprintf("Master dashboard: %s\n", fullfile(runDir, "reports", "html", "master_dashboard.html"));
end

function reports = localRunPostprocessors(runDir)
repoRoot = localRepoRoot();
scripts = [
    "postprocess/plot_call_flow.py"
    "postprocess/plot_message_sequence.py"
    "postprocess/plot_algorithm_analysis.py"
    "postprocess/plot_master_dashboard.py"
    ];
reports = repmat(struct("Script", "", "Exists", false, "Status", NaN, "Output", ""), numel(scripts), 1);
for i = 1:numel(scripts)
    scriptPath = fullfile(repoRoot, char(scripts(i)));
    reports(i).Script = scripts(i);
    reports(i).Exists = exist(scriptPath, "file") == 2;
    if ~reports(i).Exists
        reports(i).Status = -1;
        reports(i).Output = "script_missing";
        continue;
    end
    cmd = sprintf('python "%s" "%s"', scriptPath, runDir);
    [status, out] = system(cmd);
    reports(i).Status = status;
    reports(i).Output = string(out);
    if status ~= 0
        warning("sixgr:analysis:PostprocessorFailed", "Script %s failed:\n%s", scripts(i), out);
    end
end
end

function repoRoot = localRepoRoot()
repoRoot = fileparts(mfilename("fullpath"));
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analysis:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
