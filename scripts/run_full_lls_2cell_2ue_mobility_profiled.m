function out = run_full_lls_2cell_2ue_mobility_profiled(varargin)
%RUN_FULL_LLS_2CELL_2UE_MOBILITY_PROFILED Execute and audit the real scenario.
%
% This runner does not change PHY behavior. It wraps the existing
% config-driven front door with MATLAB profiler, static inventory, call-flow
% export, complexity estimates and a blunt output audit.

p = inputParser;
p.addParameter("ScenarioPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("OutputRoot", fullfile("outputs", "profiled_runs"), @(x)ischar(x) || isstring(x));
p.addParameter("RunTag", "profiled_2cell_2ue_mobility", @(x)ischar(x) || isstring(x));
p.addParameter("RunDirSuffix", "2cell_2ue_mobility", @(x)ischar(x) || isstring(x));
p.addParameter("ProfileMode", "", @(x)ischar(x) || isstring(x));
p.addParameter("FlushEverySlots", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("FlushEverySeconds", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("InternalWallClockGuardSeconds", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("StopAfterAccessComplete", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("StopAfterFirstExecutableDataGrant", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("StopAfterFirstNPDSCHGrants", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("StopAfterFirstNPUSCHGrants", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("OutputBackendOverride", "", @(x)ischar(x) || isstring(x));
p.parse(varargin{:});

repoRoot = localRepoRoot();
cd(repoRoot);
setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scenarioPath = string(p.Results.ScenarioPath);
if strlength(strtrim(scenarioPath)) == 0
    scenarioPath = localDiscoverScenario(repoRoot);
end
if exist(char(scenarioPath), "file") ~= 2
    error("sixgr:monitor:ScenarioNotFound", "Could not locate 2-cell/2-UE mobility scenario YAML.");
end

stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
runDir = fullfile(repoRoot, char(string(p.Results.OutputRoot)), char(stamp + "_" + string(p.Results.RunDirSuffix)));
sixgr.util.ensureFolder(runDir);
simOutputRoot = fullfile(runDir, "simulator_output");
sixgr.util.ensureFolder(simOutputRoot);

fprintf("Selected 2-cell/2-UE mobility YAML: %s\n", scenarioPath);
fprintf("Profiled output directory: %s\n", runDir);

diaryPath = fullfile(runDir, "run.log");
diary(diaryPath);
diary on;
cleanupDiary = onCleanup(@()diary("off")); %#ok<NASGU>

mon = sixgr.monitor.RunMonitor(runDir, scenarioPath);
cleanupMonitor = onCleanup(@()mon.close()); %#ok<NASGU>
rerunRows = localEmptyRerunRows();
runOk = false;
simRunFolder = "";
runResult = struct();
runError = [];
startWall = string(sixgr.util.utcNowISO8601());
startTic = tic;
startCpu = cputime;

mon.record("START_PHASE", "function_name", mfilename, "phase", "static_inventory", "status", "started");
inventoryT = sixgr.monitor.StaticInventory.scan(repoRoot);
sixgr.util.csvWriteTable(fullfile(runDir, "static_function_inventory.csv"), inventoryT);
mon.record("END_PHASE", "function_name", mfilename, "phase", "static_inventory", "status", "completed");

profileInfo = struct();
profileT = table();
envCleanup = localApplyProfileEnvironment(p.Results, runDir); %#ok<NASGU>
try
    mon.record("START_PHASE", "function_name", mfilename, "phase", "scenario_run", ...
        "status", "started", "file_path", scenarioPath);
    localStartProfiler();
    scope = mon.scope("function_name", "run_6g_phy_lls_single", "phase", "scenario_run", ...
        "channel", "ALL", "file_path", which("run_6g_phy_lls_single"));
    runResult = run_6g_phy_lls_single(char(scenarioPath), simOutputRoot, char(string(p.Results.RunTag)));
    scope.close("status", "completed");
    runOk = logical(sixgr.util.structGet(runResult, "Ok", false));
    simRunFolder = string(sixgr.util.structGet(runResult, "RunFolder", ""));
    mon.record("END_PHASE", "function_name", mfilename, "phase", "scenario_run", ...
        "status", "completed", "file_path", simRunFolder);
catch ME
    runError = ME;
    mon.recordException(ME, "function_name", mfilename, "phase", "scenario_run");
    mon.record("END_PHASE", "function_name", mfilename, "phase", "scenario_run", ...
        "status", "error", "error_message", ME.message);
end
profileInfo = localStopProfiler();
profileT = sixgr.monitor.ProfileExporter.export(profileInfo, runDir);
[~, unusedT] = sixgr.monitor.StaticInventory.export(repoRoot, runDir, profileT); %#ok<ASGLU>
[eventT, ~, exceptionT] = mon.snapshot();
flowSummaryT = sixgr.monitor.ChannelFlowRecorder.export(runDir, profileT, eventT);
sixgr.monitor.ComplexityCounter.export(runDir, profileT);
sixgr.monitor.LogProgressAnalyzer.export(runDir);

if ~isempty(runError)
    rerunRows(end+1, 1) = struct("attempt_id", 1, "start_time", startWall, ...
        "end_time", string(sixgr.util.utcNowISO8601()), "status", "BLOCKED", ...
        "error_function", localFirstStackName(runError), "error_message", string(runError.message), ...
        "root_cause", "see runtime_exception_log.csv", "files_changed", "", ...
        "fix_summary", "no automatic root-cause patch was applied by the profiling harness", ...
        "rerun_result", "not_rerun"); %#ok<AGROW>
else
    rerunRows(end+1, 1) = struct("attempt_id", 1, "start_time", startWall, ...
        "end_time", string(sixgr.util.utcNowISO8601()), "status", localStatus(runOk), ...
        "error_function", "", "error_message", "", "root_cause", "", ...
        "files_changed", "", "fix_summary", "", "rerun_result", localStatus(runOk)); %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(runDir, "rerun_attempts.csv"), struct2table(rerunRows));

audit = sixgr.monitor.OutputAuditor.audit(runDir, scenarioPath, simRunFolder, runOk, profileT, flowSummaryT, exceptionT);
elapsedWall = toc(startTic);
elapsedCpu = cputime - startCpu;
summary = localRunSummary(runOk, scenarioPath, runDir, simRunFolder, startWall, elapsedWall, elapsedCpu, audit);
sixgr.util.jsonWrite(fullfile(runDir, "run_summary.json"), summary);
localWriteRunSummaryMarkdown(fullfile(runDir, "run_summary.md"), summary);

out = struct("Ok", runOk, "RunDir", string(runDir), "ScenarioPath", scenarioPath, ...
    "SimulatorRunFolder", string(simRunFolder), "Result", runResult, "Audit", audit, ...
    "ProfileTable", profileT, "FlowSummary", flowSummaryT);

if ~isempty(runError)
    fprintf("Profiled run BLOCKED by runtime error. See %s\n", fullfile(runDir, "runtime_exception_log.csv"));
else
    fprintf("Profiled run completed with Ok=%d. Audit score %.2f/10. Output: %s\n", ...
        double(runOk), double(audit.Grade.final_score_out_of_10), runDir);
end
end

function cleanup = localApplyProfileEnvironment(opt, runDir)
names = ["SIXGR_PROFILE_MODE","SIXGR_FLUSH_EVERY_SLOTS","SIXGR_FLUSH_EVERY_SECONDS", ...
    "SIXGR_INTERNAL_WALL_GUARD_SECONDS","SIXGR_STOP_AFTER_ACCESS_COMPLETE", ...
    "SIXGR_STOP_AFTER_FIRST_EXECUTABLE_DATA_GRANT","SIXGR_STOP_AFTER_FIRST_N_PDSCH_GRANTS", ...
    "SIXGR_STOP_AFTER_FIRST_N_PUSCH_GRANTS","SIXGR_PROFILE_RUN_DIR","SIXGR_OUTPUT_BACKEND_OVERRIDE"];
old = containers.Map("KeyType", "char", "ValueType", "char");
for i = 1:numel(names)
    old(char(names(i))) = getenv(char(names(i)));
end
setIfText("SIXGR_PROFILE_MODE", string(opt.ProfileMode));
setIfFinite("SIXGR_FLUSH_EVERY_SLOTS", opt.FlushEverySlots);
setIfFinite("SIXGR_FLUSH_EVERY_SECONDS", opt.FlushEverySeconds);
setIfFinite("SIXGR_INTERNAL_WALL_GUARD_SECONDS", opt.InternalWallClockGuardSeconds);
setIfLogical("SIXGR_STOP_AFTER_ACCESS_COMPLETE", opt.StopAfterAccessComplete);
setIfLogical("SIXGR_STOP_AFTER_FIRST_EXECUTABLE_DATA_GRANT", opt.StopAfterFirstExecutableDataGrant);
setIfFinite("SIXGR_STOP_AFTER_FIRST_N_PDSCH_GRANTS", opt.StopAfterFirstNPDSCHGrants);
setIfFinite("SIXGR_STOP_AFTER_FIRST_N_PUSCH_GRANTS", opt.StopAfterFirstNPUSCHGrants);
setenv("SIXGR_PROFILE_RUN_DIR", char(string(runDir)));
setIfText("SIXGR_OUTPUT_BACKEND_OVERRIDE", string(opt.OutputBackendOverride));
cleanup = onCleanup(@()restoreEnv(names, old));

    function setIfText(name, value)
        if strlength(strtrim(value)) > 0
            setenv(name, char(value));
        else
            setenv(name, "");
        end
    end

    function setIfFinite(name, value)
        value = double(value);
        if isfinite(value)
            setenv(name, char(string(value)));
        else
            setenv(name, "");
        end
    end

    function setIfLogical(name, value)
        if logical(value)
            setenv(name, "1");
        else
            setenv(name, "0");
        end
    end
end

function restoreEnv(names, old)
for i = 1:numel(names)
    key = char(names(i));
    setenv(key, old(key));
end
end

function scenarioPath = localDiscoverScenario(repoRoot)
roots = [fullfile(repoRoot, "simulator", "configs"), fullfile(repoRoot, "configs")];
files = [];
for r = roots
    files = [files; dir(fullfile(r, "**", "*.yaml")); dir(fullfile(r, "**", "*.yml"))]; %#ok<AGROW>
end
if isempty(files)
    scenarioPath = "";
    return;
end
terms = ["2cell","2_cell","two_cell","2ue","2_ue","two_ue","mobility","full_profile","optimized"];
scores = zeros(numel(files), 1);
for i = 1:numel(files)
    name = lower(string(files(i).name) + " " + string(fullfile(files(i).folder, files(i).name)));
    for t = terms
        if contains(name, t)
            scores(i) = scores(i) + 1;
        end
    end
    if contains(name, "scenario")
        scores(i) = scores(i) + 0.5;
    end
end
[~, idx] = max(scores);
scenarioPath = string(fullfile(files(idx).folder, files(idx).name));
end

function localStartProfiler()
profile("clear");
try
    profile("on", "-history");
catch
    profile("on");
end
end

function info = localStopProfiler()
try
    profile("off");
    info = profile("info");
catch
    info = struct();
end
end

function rows = localEmptyRerunRows()
rows = repmat(struct("attempt_id", NaN, "start_time", "", "end_time", "", ...
    "status", "", "error_function", "", "error_message", "", "root_cause", "", ...
    "files_changed", "", "fix_summary", "", "rerun_result", ""), 0, 1);
end

function status = localStatus(ok)
if logical(ok)
    status = "SUCCESS";
else
    status = "FAILED";
end
end

function name = localFirstStackName(ME)
name = "";
if isa(ME, "MException") && ~isempty(ME.stack)
    name = string(ME.stack(1).name);
end
end

function summary = localRunSummary(ok, scenarioPath, runDir, simRunFolder, startWall, elapsedWall, elapsedCpu, audit)
summary = struct();
summary.status = string(localStatus(ok));
summary.scenario_path = string(scenarioPath);
summary.scenario_hash = sixgr.monitor.OutputAuditor.fileHash(scenarioPath);
summary.output_directory = string(runDir);
summary.simulator_run_folder = string(simRunFolder);
summary.start_time_utc = string(startWall);
summary.end_time_utc = string(sixgr.util.utcNowISO8601());
summary.elapsed_wall_s = double(elapsedWall);
summary.elapsed_cpu_s = double(elapsedCpu);
summary.git_commit = localGitCommit();
summary.matlab_version = string(version);
summary.toolbox_versions = localToolboxVersions();
summary.final_grade = audit.Grade;
end

function localWriteRunSummaryMarkdown(path, summary)
fid = fopen(path, "w");
if fid < 0
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Profiled 2-Cell / 2-UE Mobility LLS Run\n\n");
fprintf(fid, "- Status: `%s`\n", string(summary.status));
fprintf(fid, "- Scenario YAML: `%s`\n", string(summary.scenario_path));
fprintf(fid, "- Scenario SHA-256: `%s`\n", string(summary.scenario_hash));
fprintf(fid, "- Output directory: `%s`\n", string(summary.output_directory));
fprintf(fid, "- Simulator run folder: `%s`\n", string(summary.simulator_run_folder));
fprintf(fid, "- Elapsed wall time: %.3f s\n", double(summary.elapsed_wall_s));
fprintf(fid, "- Elapsed CPU time: %.3f s\n", double(summary.elapsed_cpu_s));
fprintf(fid, "- Git commit: `%s`\n", string(summary.git_commit));
fprintf(fid, "- MATLAB version: `%s`\n", string(summary.matlab_version));
fprintf(fid, "- Final blunt grade: %.2f / 10\n", double(summary.final_grade.final_score_out_of_10));
fprintf(fid, "- Verdict: `%s`\n\n", string(summary.final_grade.verdict));
fprintf(fid, "## Exact command\n\n");
fprintf(fid, "```matlab\nout=run_full_lls_2cell_2ue_mobility_profiled;\n```\n");
end

function root = localRepoRoot()
root = fileparts(fileparts(mfilename("fullpath")));
end

function hash = localGitCommit()
[status, raw] = system("git rev-parse HEAD");
if status == 0
    hash = strtrim(string(raw));
else
    hash = "";
end
end

function versions = localToolboxVersions()
v = ver;
versions = repmat(struct("Name", "", "Version", ""), numel(v), 1);
for i = 1:numel(v)
    versions(i).Name = string(v(i).Name);
    versions(i).Version = string(v(i).Version);
end
end
