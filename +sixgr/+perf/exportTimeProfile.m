function out = exportTimeProfile(runFolder, cfg)
%EXPORTTIMEPROFILE Write profiler call, summary, and coverage CSV artifacts.

if nargin < 2
    cfg = struct();
end
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
analyticsDir = fullfile(runFolder, "analytics", "csv");
sixgr.util.ensureFolder(analyticsDir);

[callT, summaryT, coverageT] = sixgr.perf.TimeProfiler.snapshot();
callT = localAnnotate(callT, cfg);
summaryT = localAnnotate(summaryT, cfg);
coverageT = localAnnotate(coverageT, cfg);

sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "time_profile_calls.csv"), callT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "time_profile_summary.csv"), summaryT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "time_profile_coverage.csv"), coverageT);
sixgr.util.csvWriteTable(fullfile(analyticsDir, "time_profile_analytics.csv"), callT);

out = struct( ...
    "CallTable", callT, ...
    "SummaryTable", summaryT, ...
    "CoverageTable", coverageT, ...
    "Ok", true);
end

function T = localAnnotate(T, cfg)
if ~istable(T)
    return;
end
scenarioID = string(sixgr.util.structGet(cfg, "scenario.id", ...
    sixgr.util.structGet(cfg, "meta.lls6gScenarioID", "")));
runTag = string(sixgr.util.structGet(cfg, "run.runTag", ""));
if ~ismember("ScenarioID", string(T.Properties.VariableNames))
    T = addvars(T, repmat(scenarioID, height(T), 1), 'Before', 1, 'NewVariableNames', 'ScenarioID');
end
if ~ismember("RunTag", string(T.Properties.VariableNames))
    T = addvars(T, repmat(runTag, height(T), 1), 'After', 'ScenarioID', 'NewVariableNames', 'RunTag');
end
end
