function actions = apply_auto_fixes(runFolder, inputConfigPath, requestedWorkers)
%APPLY_AUTO_FIXES Apply only safe artifact-level fixes for the actual study.

layout = sixgr.report.resultLayout(runFolder);
issues = localReadOptionalTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"));
rows = repmat(localActionRow(), 0, 1);

needsSupportArtifacts = isempty(issues) || any(ismember(string(issues.issue_id), ["PROFILE-01","RESULTS-01"]));
if needsSupportArtifacts
    [ok, note] = sixgr_apply_fix("materialize_support_artifacts", runFolder, inputConfigPath, requestedWorkers);
    rows(end+1, 1) = localActionRow( ... %#ok<AGROW>
        "auto_fix_001", "materialize_support_artifacts", localStatus(ok), false, false, string(note), string(runFolder));
end

actions = struct2table(rows, "AsArray", true);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "e2e_auto_fix_actions.csv"), actions);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "e2e_auto_fix_actions.json"), struct("actions", table2struct(actions)));
end

function row = localActionRow(actionId, fixId, status, changedCode, rerunRequired, note, targetPath)
if nargin == 0
    row = struct( ...
        "ActionId", "", ...
        "FixId", "", ...
        "Status", "", ...
        "ChangedCode", false, ...
        "RerunRequired", false, ...
        "Note", "", ...
        "TargetPath", "");
    return;
end
row = struct( ...
    "ActionId", string(actionId), ...
    "FixId", string(fixId), ...
    "Status", string(status), ...
    "ChangedCode", logical(changedCode), ...
    "RerunRequired", logical(rerunRequired), ...
    "Note", string(note), ...
    "TargetPath", string(targetPath));
end

function out = localStatus(tf)
if tf
    out = "applied";
else
    out = "skipped";
end
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end
