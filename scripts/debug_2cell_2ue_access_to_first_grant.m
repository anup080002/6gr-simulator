function out = debug_2cell_2ue_access_to_first_grant(varargin)
%DEBUG_2CELL_2UE_ACCESS_TO_FIRST_GRANT Run access-deep 2-cell/2-UE debug.
%
% This is a diagnostic wrapper only. It preserves the configured PHY,
% mobility, RA, control, UE/cell counts and truth execution path.

p = inputParser;
p.addParameter("ScenarioPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("OutputRoot", fullfile("outputs", "debug_runs"), @(x)ischar(x) || isstring(x));
p.addParameter("InternalWallClockGuardSeconds", 1800, @(x)isnumeric(x) && isscalar(x));
p.addParameter("FlushEverySlots", 25, @(x)isnumeric(x) && isscalar(x));
p.addParameter("FlushEverySeconds", 30, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});

out = run_full_lls_2cell_2ue_mobility_profiled( ...
    "ScenarioPath", p.Results.ScenarioPath, ...
    "OutputRoot", p.Results.OutputRoot, ...
    "RunTag", "debug_2cell_2ue_access_to_first_grant", ...
    "RunDirSuffix", "2cell_2ue_access_to_first_grant", ...
    "ProfileMode", "ACCESS_DEEP", ...
    "FlushEverySlots", double(p.Results.FlushEverySlots), ...
    "FlushEverySeconds", double(p.Results.FlushEverySeconds), ...
    "InternalWallClockGuardSeconds", double(p.Results.InternalWallClockGuardSeconds), ...
    "StopAfterAccessComplete", false, ...
    "StopAfterFirstExecutableDataGrant", true, ...
    "StopAfterFirstNPDSCHGrants", 1, ...
    "StopAfterFirstNPUSCHGrants", 1, ...
    "OutputBackendOverride", "filesystem");

runDir = string(out.RunDir);
simRunFolder = string(sixgr.util.structGet(out, "SimulatorRunFolder", ""));
localCopyDebugTables(runDir, simRunFolder);
localWriteFilesChanged(runDir);
localWriteDiagnosis(runDir, simRunFolder);
end

function localCopyDebugTables(runDir, simRunFolder)
debugDir = fullfile(char(runDir), "debug_csv");
sixgr.util.ensureFolder(debugDir);
sources = [ ...
    "control/csv/access_transition_ledger.csv"; ...
    "reports/csv/access_transition_ledger.csv"; ...
    "control/csv/access_state_timeline.csv"; ...
    "control/csv/prach_trials.csv"; ...
    "control/csv/initial_access_lifecycle_trace.csv"; ...
    "control/csv/msg2_rar_trials.csv"; ...
    "control/csv/msg3_pusch_trials.csv"; ...
    "control/csv/msg4_contention_resolution.csv"; ...
    "packet_flow/csv/live_dl_scheduler_grants.csv"; ...
    "packet_flow/csv/live_ul_scheduler_grants.csv"; ...
    "reports/csv/live_control_gating_summary.csv"; ...
    "reports/csv/live_control_gating_state.csv"; ...
    "reports/csv/run_state.csv"; ...
    "reports/csv/slot_trace.csv"];
roots = [runDir; simRunFolder];
for i = 1:numel(sources)
    copied = false;
    for r = roots(:).'
        if strlength(string(r)) == 0
            continue;
        end
        src = fullfile(char(string(r)), char(sources(i)));
        if exist(src, "file") == 2
            [~, name, ext] = fileparts(src);
            copyfile(src, fullfile(debugDir, char(string(name) + string(ext))));
            copied = true;
            break;
        end
    end
    if ~copied
        localAppendText(fullfile(debugDir, "missing_debug_tables.txt"), string(sources(i)) + newline);
    end
end
end

function localWriteFilesChanged(runDir)
[status, txt] = system("git diff --name-only");
if status ~= 0
    txt = "";
end
path = fullfile(char(runDir), "files_changed_for_fix.md");
fid = fopen(path, "w");
if fid < 0
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Files Changed For This Fix\n\n");
names = strtrim(string(splitlines(txt)));
names = names(strlength(names) > 0);
if isempty(names)
    fprintf(fid, "No uncommitted source changes were visible to git at debug finalization time.\n");
else
    for i = 1:numel(names)
        fprintf(fid, "- `%s`\n", names(i));
    end
end
end

function localWriteDiagnosis(runDir, simRunFolder)
diagPath = fullfile(char(runDir), "root_blocker_diagnosis.md");
fid = fopen(diagPath, "w");
if fid < 0
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, "# 2-Cell / 2-UE Access-To-First-Grant Diagnosis\n\n");
fprintf(fid, "- Debug run directory: `%s`\n", string(runDir));
fprintf(fid, "- Simulator run folder: `%s`\n\n", string(simRunFolder));

ledger = localReadFirstExisting(runDir, simRunFolder, "control/csv/access_transition_ledger.csv");
prach = localReadFirstExisting(runDir, simRunFolder, "control/csv/prach_trials.csv");
dlGrants = localReadFirstExisting(runDir, simRunFolder, "packet_flow/csv/live_dl_scheduler_grants.csv");
ulGrants = localReadFirstExisting(runDir, simRunFolder, "packet_flow/csv/live_ul_scheduler_grants.csv");

fprintf(fid, "## Access Ledger\n\n");
fprintf(fid, "- Ledger rows: %.0f\n", localHeight(ledger));
if istable(ledger) && ~isempty(ledger) && ismember("new_state", string(ledger.Properties.VariableNames))
    states = unique(string(ledger.new_state));
    fprintf(fid, "- Observed states: `%s`\n", strjoin(states.', "`, `"));
end

fprintf(fid, "\n## PRACH\n\n");
fprintf(fid, "- PRACH trial rows: %.0f\n", localHeight(prach));
if istable(prach) && ~isempty(prach)
    if ismember("Status", string(prach.Properties.VariableNames))
        fprintf(fid, "- PRACH statuses: `%s`\n", strjoin(unique(string(prach.Status)).', "`, `"));
    end
    if ismember("Notes", string(prach.Properties.VariableNames))
        notes = unique(string(prach.Notes));
        notes = notes(strlength(strtrim(notes)) > 0);
        if ~isempty(notes)
            fprintf(fid, "- PRACH notes: `%s`\n", strjoin(notes(1:min(5,end)).', "`, `"));
        end
    end
end

fprintf(fid, "\n## Grants\n\n");
fprintf(fid, "- DL grant rows: %.0f\n", localHeight(dlGrants));
fprintf(fid, "- UL grant rows: %.0f\n", localHeight(ulGrants));
if localHeight(dlGrants) + localHeight(ulGrants) > 0
    fprintf(fid, "- Root blocker status: first executable data-grant evidence was reached.\n");
elseif localHeight(ledger) == 0
    fprintf(fid, "- Root blocker status: access state ledger was not emitted; investigate runtime table flushing or early setup failure.\n");
else
    fprintf(fid, "- Root blocker status: access/control gating did not produce an executable data grant before stop condition.\n");
end
end

function T = localReadFirstExisting(runDir, simRunFolder, rel)
T = table();
for root = [runDir; simRunFolder].'
    if strlength(string(root)) == 0
        continue;
    end
    path = fullfile(char(string(root)), char(string(rel)));
    if exist(path, "file") == 2
        try
            T = readtable(path);
            return;
        catch
            T = table();
            return;
        end
    end
end
end

function n = localHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function localAppendText(path, text)
fid = fopen(path, "a");
if fid < 0
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", char(text));
end
