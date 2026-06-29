function out = finalize_profiled_lls_run(runDir, varargin)
%FINALIZE_PROFILED_LLS_RUN Write blocked audit artifacts after interruption.
%   Use when an external timeout or manual termination stops the profiled
%   MATLAB process before its onCleanup handlers can flush profiler/audit
%   artifacts. This does not convert the run to success.

p = inputParser;
p.addRequired("runDir", @(x)ischar(x) || isstring(x));
p.addParameter("ScenarioPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("Reason", "external_timeout_or_interrupted_before_runner_cleanup", @(x)ischar(x) || isstring(x));
p.parse(runDir, varargin{:});

repoRoot = localRepoRoot();
cd(repoRoot);
setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

runDir = char(string(p.Results.runDir));
scenarioPath = string(p.Results.ScenarioPath);
if strlength(strtrim(scenarioPath)) == 0
    scenarioPath = localDiscoverScenario(repoRoot);
end
sixgr.util.ensureFolder(runDir);

logPath = fullfile(runDir, "run.log");
progress = localParseProgress(logPath);
mon = sixgr.monitor.RunMonitor(runDir, scenarioPath);
mon.record("ERROR", "function_name", "scripts.finalize_profiled_lls_run", ...
    "phase", "interrupted_run_finalization", "status", "blocked", ...
    "error_message", string(p.Results.Reason) + "; " + progress);
mon.close();
ex = sixgr.monitor.RunMonitor.defaultExceptionRow();
ex.run_id = "interrupted_finalizer";
ex.timestamp_wall = string(sixgr.util.utcNowISO8601());
ex.event_index = NaN;
ex.identifier = "sixgr:monitor:InterruptedProfiledRun";
ex.message = string(p.Results.Reason) + "; " + progress;
ex.stack = "MATLAB process was externally terminated before runner cleanup.";
ex.scenario_path = scenarioPath;
ex.last_trace_events_json = "[]";
sixgr.util.csvWriteTable(fullfile(runDir, "runtime_exception_log.csv"), struct2table(ex));

profileInfo = struct("FunctionTable", []);
profileT = sixgr.monitor.ProfileExporter.export(profileInfo, runDir);
sixgr.monitor.StaticInventory.export(repoRoot, runDir, profileT);
eventT = readtable(fullfile(runDir, "activity_timeline.csv"), "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");
flowSummaryT = sixgr.monitor.ChannelFlowRecorder.export(runDir, profileT, eventT);
sixgr.monitor.ComplexityCounter.export(runDir, profileT);
sixgr.monitor.LogProgressAnalyzer.export(runDir);
exceptionT = readtable(fullfile(runDir, "runtime_exception_log.csv"), "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");

rerunRows = struct("attempt_id", 1, "start_time", "", "end_time", string(sixgr.util.utcNowISO8601()), ...
    "status", "BLOCKED", "error_function", "external_timeout", ...
    "error_message", string(p.Results.Reason) + "; " + progress, ...
    "root_cause", "full scenario did not complete within external execution window", ...
    "files_changed", "", "fix_summary", "profile finalizer emitted blocked audit only", ...
    "rerun_result", "not_rerun");
sixgr.util.csvWriteTable(fullfile(runDir, "rerun_attempts.csv"), struct2table(rerunRows));

audit = sixgr.monitor.OutputAuditor.audit(runDir, scenarioPath, "", false, profileT, flowSummaryT, exceptionT);
summary = struct("status", "BLOCKED", "scenario_path", scenarioPath, ...
    "scenario_hash", sixgr.monitor.OutputAuditor.fileHash(scenarioPath), ...
    "output_directory", string(runDir), "simulator_run_folder", "", ...
    "start_time_utc", "", "end_time_utc", string(sixgr.util.utcNowISO8601()), ...
    "elapsed_wall_s", NaN, "elapsed_cpu_s", NaN, "git_commit", localGitCommit(), ...
    "matlab_version", string(version), "toolbox_versions", localToolboxVersions(), ...
    "final_grade", audit.Grade, "interruption_reason", string(p.Results.Reason), ...
    "last_progress", progress);
sixgr.util.jsonWrite(fullfile(runDir, "run_summary.json"), summary);
localWriteSummary(fullfile(runDir, "run_summary.md"), summary);
out = struct("Ok", false, "RunDir", string(runDir), "Audit", audit, "Progress", progress);
fprintf("Finalized interrupted profiled run as BLOCKED: %s\n", runDir);
end

function progress = localParseProgress(logPath)
progress = "no run.log progress found";
if exist(logPath, "file") ~= 2
    return;
end
txt = string(fileread(logPath));
matches = regexp(char(txt), "slot[ =](\d+)/(\d+)", "tokens");
if ~isempty(matches)
    last = matches{end};
    progress = "last observed slot " + string(last{1}) + "/" + string(last{2});
end
grants = regexp(char(txt), "grants=(\d+)", "tokens");
if ~isempty(grants)
    progress = progress + "; last observed grants=" + string(grants{end}{1});
end
end

function localWriteSummary(path, summary)
fid = fopen(path, "w");
if fid < 0
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Interrupted Profiled LLS Run\n\n");
fprintf(fid, "- Status: `BLOCKED`\n");
fprintf(fid, "- Scenario YAML: `%s`\n", string(summary.scenario_path));
fprintf(fid, "- Output directory: `%s`\n", string(summary.output_directory));
fprintf(fid, "- Interruption reason: `%s`\n", string(summary.interruption_reason));
fprintf(fid, "- Last progress: `%s`\n", string(summary.last_progress));
fprintf(fid, "- Final blunt grade: %.2f / 10\n", double(summary.final_grade.final_score_out_of_10));
fprintf(fid, "- Verdict: `%s`\n\n", string(summary.final_grade.verdict));
fprintf(fid, "## Exact command attempted\n\n");
fprintf(fid, "```matlab\nout=run_full_lls_2cell_2ue_mobility_profiled;\n```\n");
end

function scenarioPath = localDiscoverScenario(repoRoot)
roots = [fullfile(repoRoot, "simulator", "configs"), fullfile(repoRoot, "configs")];
files = [];
for r = roots
    files = [files; dir(fullfile(r, "**", "*.yaml")); dir(fullfile(r, "**", "*.yml"))]; %#ok<AGROW>
end
terms = ["2cell","2_cell","two_cell","2ue","2_ue","two_ue","mobility","full_profile","optimized"];
scores = zeros(numel(files), 1);
for i = 1:numel(files)
    name = lower(string(files(i).name) + " " + string(fullfile(files(i).folder, files(i).name)));
    for t = terms
        scores(i) = scores(i) + double(contains(name, t));
    end
end
[~, idx] = max(scores);
scenarioPath = string(fullfile(files(idx).folder, files(idx).name));
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
