function out = run_mobile_2ue_study(configPath, outputRoot, runTag, varargin)
%RUN_MOBILE_2UE_STUDY Execute the actual mobile-2UE study and post-run audits.

p = inputParser;
p.addParameter("DiaryPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("RegistryPath", fullfile(pwd, "configs", "lls", "e2e_expected_process_registry.yaml"), @(x)ischar(x) || isstring(x));
p.addParameter("RequestedWorkers", 32, @(x)isnumeric(x) && isscalar(x));
p.addParameter("AutoFixSafeIssues", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scfg = sixgr.lls6g.config.loadScenarioConfig(configPath);
predictedRunFolder = localExpectedRunFolder(outputRoot, scfg.ScenarioID, runTag);
totalSlots = double(scfg.get("run_control.total_slots", scfg.get("simulation.n_slots", 0)));
diaryTempPath = string(opt.DiaryPath);
if strlength(diaryTempPath) == 0
    diaryTempPath = fullfile(fileparts(predictedRunFolder), string(runTag) + "_matlab_diary.tmp.log");
end
sixgr.util.ensureDir(diaryTempPath);
try
    diary(char(diaryTempPath));
catch
end

runnerOut = struct();
runError = [];
runFolder = string(predictedRunFolder);
try
    runnerOut = sixgr.lls6g.runners.runSingle(configPath, outputRoot, runTag);
    runFolder = string(runnerOut.RunFolder);
catch ME
    runError = ME;
end
try
    diary off;
catch
end

cfg = localSafeBuildInternalConfig(scfg, runFolder);
traceCtx = sixgr.trace.TraceContext(runTag, scfg.ScenarioID, runFolder, totalSlots, double(opt.RequestedWorkers), outputRoot);
finalDiaryPath = fullfile(runFolder, "logs", "matlab_diary.log");
if exist(diaryTempPath, "file") == 2
    copyfile(diaryTempPath, finalDiaryPath);
end
traceCtx.LatestLogPath = string(finalDiaryPath);
traceCtx.writeStatus("LatestLogPath", traceCtx.LatestLogPath);

traceCtx.startStage("post_run_materialization", totalSlots);
support = sixgr.trace.TraceArtifactWriter.materializeSupportArtifacts(runFolder, configPath, opt.RequestedWorkers);
traceCtx.completeStage("completed", totalSlots, totalSlots, 4, 0, 0, 0, "");

traceCtx.startStage("trace_synthesis", totalSlots);
msgTrace = sixgr.trace.MessageFlowTracer.generate(runFolder, runTag);
calcTrace = sixgr.trace.CalculationTracer.generate(runFolder, runTag, scfg);
fnTrace = sixgr.trace.FunctionBlockTracer.generate(runFolder, runTag, opt.RegistryPath);
traceCtx.completeStage("completed", totalSlots, totalSlots, 3, height(msgTrace) + height(calcTrace) + height(fnTrace), 0, 0, "");

validationSummary = struct("ActualLLSVerdict", "failed_evidence_run");
traceCtx.startStage("validation_and_truth", totalSlots);
if isempty(runError)
    try
        validation = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", true);
        if isfield(validation, "Summary")
            validationSummary = localStructify(validation.Summary);
        end
    catch ME
        runError = localPreferFirstError(runError, ME);
    end
end
traceCtx.completeStage("completed", totalSlots, totalSlots, 4, 0, 0, 0, "");

traceCtx.startStage("output_readback_audit", totalSlots);
readbackSummary = sixgr.trace.TraceArtifactWriter.auditOutputs(runFolder, runTag);
traceCtx.completeStage("completed", totalSlots, totalSlots, readbackSummary.TotalGeneratedFiles, readbackSummary.TotalCSVFiles, ...
    readbackSummary.TotalCSVReadFailed, double(readbackSummary.TotalCSVReadFailed > 0), "");

traceCtx.startStage("issue_detection", totalSlots);
issues = detect_all_issues(runFolder, scfg, cfg, "RequestedWorkers", opt.RequestedWorkers);
criticalCount = 0;
if ~isempty(issues)
    criticalCount = sum(strcmpi(string(issues.severity), "critical"));
end
traceCtx.completeStage("completed", totalSlots, totalSlots, 1, 0, height(issues), criticalCount, "");

fixActions = table();
if logical(opt.AutoFixSafeIssues)
    traceCtx.startStage("safe_auto_fix", totalSlots);
    fixActions = apply_auto_fixes(runFolder, configPath, opt.RequestedWorkers);
    traceCtx.completeStage("completed", totalSlots, totalSlots, height(fixActions), 0, 0, 0, "");
end

traceCtx.startStage("truth_gate_refresh", totalSlots);
try
    sixgr.truth.evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, "Result", sixgr.util.structGet(runnerOut, "Result", struct()));
catch ME
    runError = localPreferFirstError(runError, ME);
end
traceCtx.completeStage("completed", totalSlots, totalSlots, 2, 0, 0, 0, "");

traceCtx.startStage("report_generation", totalSlots);
reportArtifacts = sixgr.trace.TraceArtifactWriter.writeStudyReport(runFolder, runTag, validationSummary, readbackSummary, fixActions);
traceCtx.completeStage("completed", totalSlots, totalSlots, 5, 0, 0, 0, "");

parallelSummary = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "parallel_execution_summary.csv"));
workersUsed = localScalarDouble(parallelSummary, "WorkersUsed", NaN);
statusT = localReadOptionalTable(fullfile(runFolder, "reports", "csv", "result_status_summary.csv"));
runCompleted = localScalarLogical(statusT, "RunCompleted", isempty(runError));
resultOk = localScalarLogical(statusT, "ResultOk", false);
fatalMessage = "";
if ~isempty(runError)
    fatalMessage = string(getReport(runError, "extended", "hyperlinks", "off"));
end
traceCtx.finalize(runCompleted, resultOk, fatalMessage, workersUsed, finalDiaryPath);

out = struct();
out.RunFolder = string(runFolder);
out.DiaryPath = string(finalDiaryPath);
out.SupportArtifacts = support;
out.ReportArtifacts = reportArtifacts;
out.ReadbackSummary = readbackSummary;
out.ValidationSummary = validationSummary;
out.RunCompleted = logical(runCompleted);
out.ResultOk = logical(resultOk);
out.FatalErrorMessage = string(fatalMessage);
out.ScenarioID = string(scfg.ScenarioID);
out.RunId = string(runTag);
out.RegistryPath = string(opt.RegistryPath);
out.PointerPath = string(fullfile(pwd, "results", "latest_actual_mobile_2ue_full_phy_study.txt"));

sixgr.util.jsonWrite(fullfile(runFolder, "study_report", "run_mobile_2ue_study_summary.json"), out);
end

function folder = localExpectedRunFolder(outputRoot, scenarioId, runTag)
root = sixgr.report.resolveResultsRoot(char(string(outputRoot)));
folder = fullfile(root, "lls", char(string(scenarioId)), char(string(runTag)));
end

function cfg = localSafeBuildInternalConfig(scfg, runFolder)
try
    cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
catch
    cfg = struct();
end
end

function out = localStructify(value)
if isstruct(value)
    out = value;
else
    out = struct("Value", value);
end
end

function err = localPreferFirstError(existing, candidate)
if isempty(existing)
    err = candidate;
else
    err = existing;
end
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end

function out = localScalarLogical(T, varName, defaultValue)
out = logical(defaultValue);
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
try
    out = logical(T.(varName)(1));
catch
    out = any(strcmpi(string(T.(varName)(1)), ["true","1","yes","pass"]));
end
end

function out = localScalarDouble(T, varName, defaultValue)
out = defaultValue;
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
try
    out = double(T.(varName)(1));
catch
    out = defaultValue;
end
end
