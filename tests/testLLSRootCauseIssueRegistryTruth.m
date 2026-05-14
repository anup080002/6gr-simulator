function ok = testLLSRootCauseIssueRegistryTruth()
%TESTLLSROOTCAUSEISSUEREGISTRYTRUTH Keep issue labels aligned with the actual root-cause symptom.

setup6GRSimToolkit("Verbose", false);
sixgr.db.deactivateArtifactStore();

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

runFolder = fullfile(tmp, "run");
layout = sixgr.report.resultLayout(runFolder);
localEnsureDirs({layout.ReportCSVDir, layout.PacketFlowCSVDir, layout.RFCSVDir, layout.SystemCSVDir, layout.ControlCSVDir, layout.AirInterfaceCSVDir, layout.BeamformingCSVDir});

scfg = struct("ScenarioID", "ROOT_CAUSE_TRUTH", "ConfigHash", "unit_hash");
cfg = sixgr.config.defaultConfig();

localWrite(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), table( ...
    "ROOT_CAUSE_TRUTH", true, 0, ...
    'VariableNames', {'ScenarioID','ResultOk','RequiredFailureCount'}));

coverageT = table( ...
    [1; 2; 3; 4], ...
    [11; 12; 13; 14], ...
    [12; 3; 14; 15], ...
    [1; 2; -1.5; 3], ...
    'VariableNames', {'UEID','ServingCell','LargeScaleWidebandSINR_dB','MeasuredWidebandSINR_dB'});
localWrite(fullfile(layout.ReportCSVDir, "live_coverage_layer.csv"), coverageT);

userPerfT = table( ...
    [1; 2; 3; 4], ...
    [0.75; NaN; NaN; 1.0], ...
    [4; NaN; NaN; 1], ...
    [0.1; 0.2; 0.3; 0.4], ...
    'VariableNames', {'UEIndex','HARQFailureRate','HARQObservationCount','UserThroughput_Mbps'});
localWrite(fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"), userPerfT);

out = sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg); %#ok<NASGU>
issuePath = fullfile(layout.ReportCSVDir, "result_issue_registry.csv");
issues = readtable(issuePath, "VariableNamingRule", "preserve");

harqRow = issues(strcmp(string(issues.issue_category), "link_reliability"), :);
assert(~isempty(harqRow), ...
    "HARQ-driven root-cause rows must be labeled link_reliability, not generic channel_interference.");
assert(any(startsWith(string(harqRow.issue_id), "harq_failure_window_")) && any(double(harqRow.ue_id) == 1), ...
    "HARQ-driven issue ids must preserve the harq_failure_window symptom for the affected UE.");

coverageRow = issues(strcmp(string(issues.issue_category), "coverage_edge"), :);
assert(~isempty(coverageRow) && any(double(coverageRow.ue_id) == 2), ...
    "Coverage-edge rows must stay labeled as coverage_edge when the evidence is low large-scale SINR.");

sinrRow = issues(strcmp(string(issues.issue_category), "channel_interference"), :);
assert(~isempty(sinrRow) && any(double(sinrRow.ue_id) == 3), ...
    "Negative measured-SINR rows must remain labeled as channel_interference.");

assert(~any(double(issues.ue_id) == 4 & startsWith(string(issues.issue_id), "harq_failure_window_")), ...
    "Single-observation HARQ spikes must not be escalated into high_harq_failure_rate root-cause rows.");

ok = true;
end

function localEnsureDirs(paths)
for i = 1:numel(paths)
    if exist(paths{i}, "dir") ~= 7
        mkdir(paths{i});
    end
end
end

function localWrite(pathStr, T)
[folder, ~, ~] = fileparts(pathStr);
if exist(folder, "dir") ~= 7
    mkdir(folder);
end
writetable(T, pathStr);
end
