function issues = detect_all_issues(runFolder, scfg, cfg, varargin)
%DETECT_ALL_ISSUES Aggregate actual-run findings into the runtime issue registry.

p = inputParser;
p.addParameter("RequestedWorkers", 32, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

layout = sixgr.report.resultLayout(runFolder);
existing = localReadIssueRegistry(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"));
issuesToAdd = repmat(localIssueRow(), 0, 1);

localWriteColumnAliasResolution(runFolder);

invariants = localReadOptionalTable(fullfile(layout.ReportCSVDir, "phy_value_invariant_checks.csv"));
if ~isempty(invariants)
    failed = invariants(~logical(invariants.Pass), :);
    for i = 1:height(failed)
        issuesToAdd(end+1, 1) = localIssueFromInvariant(failed(i, :)); %#ok<AGROW>
    end
end

fnTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_function_block_trace.csv"));
if ~isempty(fnTrace)
    bad = fnTrace(logical(fnTrace.ExpectedForScenario) & ...
        (~logical(fnTrace.Called) | logical(fnTrace.ConfigOnlyEvidence) | logical(fnTrace.ProxyUsed) | logical(fnTrace.FallbackUsed) | ~logical(fnTrace.MeasurementEvidence)), :);
    for i = 1:height(bad)
        issueId = string(bad.IssueIdIfFailed(i));
        if strlength(issueId) == 0
            issueId = "REALPHY-001";
        end
        issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            issueId, localSeverity(issueId), "active_blocking", "runtime_function_block", ...
            "", NaN, NaN, string(bad.BlockId(i)), "ImplementationPass", string(bad.ImplementationPass(i)), ...
            string(bad.FailureReason(i)), "reports/csv/runtime_function_block_trace.csv", ...
            "required process evidence missing", "restore measurement-backed execution and rerun", true);
    end
end

readback = localReadOptionalTable(fullfile(layout.ReportCSVDir, "e2e_output_readback_findings.csv"));
if ~isempty(readback)
    for i = 1:height(readback)
        issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            string(readback.IssueId(i)), string(readback.Severity(i)), "active_blocking", "readback", ...
            "", NaN, NaN, "output_readback", "Detail", string(readback.Detail(i)), ...
            string(readback.Message(i)), string(readback.RelativePath(i)), ...
            "readback finding from exhaustive audit", "inspect the named artifact and upstream writer", true);
    end
end

parallel = localReadOptionalTable(fullfile(layout.ReportCSVDir, "parallel_execution_summary.csv"));
if ~isempty(parallel) && logical(parallel.ParallelDegraded(1))
    issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "PAR-01", "medium", "active_non_blocking", "parallel", "", NaN, NaN, "parallel_pool", ...
        "WorkersUsed", string(parallel.WorkersUsed(1)), "requested workers were not available", ...
        "reports/csv/parallel_execution_summary.csv", "parallel capacity degraded", ...
        "record degraded parallel state; rerun only if strict worker parity is mandatory", true);
end

profileRequired = [ ...
    fullfile(layout.ReportDir, "profiling", "matlab_profile_info.mat"); ...
    fullfile(layout.ReportDir, "profiling", "matlab_profile_summary.txt"); ...
    fullfile(layout.ReportDir, "profiling", "matlab_profile_functions.csv"); ...
    fullfile(layout.ReportDir, "profiling", "matlab_profile_callgraph.csv")];
if any(arrayfun(@(p) exist(p{1}, "file") ~= 2, num2cell(profileRequired)))
    issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "PROFILE-01", "high", "active_blocking", "profiling", "", NaN, NaN, "matlab_profile", ...
        "ProfileArtifacts", "missing", "required profiling aliases are missing", ...
        "reports/profiling", "profiling export incomplete", ...
        "materialize profiling aliases before claiming full evidence", true);
end

statusPath = fullfile(layout.ReportCSVDir, "result_status_summary.csv");
if exist(statusPath, "file") ~= 2
    issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
        "RESULTS-01", "critical", "active_blocking", "run_status", "", NaN, NaN, "result_status_summary", ...
        "RunCompleted", "missing", "result status summary missing", ...
        "reports/csv/result_status_summary.csv", "run status artifact missing", ...
        "capture the run failure stage and rerun after fixing the blocker", true);
end

status = localReadOptionalTable(statusPath);
if ~isempty(status)
    claimProfile = localTableText(status, 1, "ClaimProfile", "");
    standardsOk = localTableLogical(status, 1, "StandardsConformanceOk", false);
    if strlength(claimProfile) > 0 && contains(lower(claimProfile), "conformance") && ~standardsOk
        issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "CLAIM-01", "critical", "active_blocking", "claim_gate", "", NaN, NaN, "ClaimProfile", ...
            "ClaimProfile", claimProfile, "broad conformance claim is not supported by runtime evidence", ...
            "reports/csv/result_status_summary.csv", "claim profile conflicts with standards gate", ...
            "downgrade the public claim or add the missing standards-mapped evidence", true);
    end
end

validationSummary = localReadJSON(fullfile(layout.ReportDir, "json", "phy_block_validation_summary.json"));
if isstruct(validationSummary) && isfield(validationSummary, "ActualLLSVerdict")
    verdict = lower(string(validationSummary.ActualLLSVerdict));
    if contains(verdict, "label") || contains(verdict, "proxy")
        issuesToAdd(end+1, 1) = localIssueRow( ... %#ok<AGROW>
            "TRUTH-01", "critical", "active_blocking", "truth_gate", "", NaN, NaN, "ActualLLSVerdict", ...
            "ActualLLSVerdict", verdict, "actual LLS verdict is label/proxy rather than measurement-backed", ...
            "reports/json/phy_block_validation_summary.json", "validation verdict is not full actual LLS", ...
            "keep ResultOk false until mandatory blocks are measurement-backed", true);
    end
end

issues = localMergeIssueTables(existing, struct2table(issuesToAdd, "AsArray", true));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"), issues);
end

function localWriteColumnAliasResolution(runFolder)
layout = sixgr.report.resultLayout(runFolder);
specs = { ...
    "CRCPass", fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ["CRCPass","crc_pass"]; ...
    "LLRMeanAbs", fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ["LLRMeanAbs","llr_mean_abs"]; ...
    "PostEqSINR_dB", fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ["PostEqSINR_dB","PostEqSINRWidebanddB"]; ...
    "InjectedCFO_Hz", fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"), ["InjectedCFO_Hz"]; ...
    "EstimatedCFO_Hz", fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"), ["EstimatedCFO_Hz"]; ...
    "DopplerHz", fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"), ["DopplerHz","InjectedDoppler_Hz"]; ...
    "NMSE_dB", fullfile(layout.Root, "reference_signals", "csv", "trs_trials.csv"), ["NMSE_dB"] ...
    };
rows = repmat(struct("CanonicalName", "", "SourcePath", "", "ResolvedColumn", "", "Status", ""), 0, 1);
for i = 1:size(specs, 1)
    sourcePath = string(specs{i, 2});
    resolvedColumn = "";
    status = "source_missing";
    if exist(sourcePath, "file") == 2
        T = readtable(sourcePath, "VariableNamingRule", "preserve");
        vars = string(T.Properties.VariableNames);
        aliases = string(specs{i, 3});
        hit = vars(ismember(lower(vars), lower(aliases)));
        if isempty(hit)
            status = "alias_missing";
        else
            resolvedColumn = string(hit(1));
            status = "resolved";
        end
    end
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "CanonicalName", string(specs{i, 1}), ...
        "SourcePath", sourcePath, ...
        "ResolvedColumn", resolvedColumn, ...
        "Status", status);
end
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "column_alias_resolution.csv"), struct2table(rows, "AsArray", true));
end

function issue = localIssueFromInvariant(row)
issue = localIssueRow( ...
    string(row.CheckId), string(row.Severity), localInvariantStatus(row), "numerical_invariant", ...
    "", double(row.UEId), NaN, string(row.Subsystem), string(row.MetricName), string(row.ObservedValue), ...
    string(row.FailureReason), "reports/csv/phy_value_invariant_checks.csv", ...
    "actual runtime invariant failed", string(row.RecommendedFix), true);
end

function status = localInvariantStatus(row)
if strcmpi(string(row.Severity), "critical")
    status = "active_blocking";
else
    status = "active_observation";
end
end

function issues = localReadIssueRegistry(pathStr)
if exist(pathStr, "file") ~= 2
    issues = struct2table(repmat(localIssueRow(), 0, 1), "AsArray", true);
    return;
end
issues = readtable(pathStr, "VariableNamingRule", "preserve");
end

function issues = localMergeIssueTables(existing, additions)
issues = existing;
if isempty(additions)
    return;
end
issues = localAlignIssueColumns(issues);
additions = localAlignIssueColumns(additions);
keys = string(issues.issue_id) + "|" + string(issues.block_name) + "|" + string(issues.metric_name);
for i = 1:height(additions)
    key = string(additions.issue_id(i)) + "|" + string(additions.block_name(i)) + "|" + string(additions.metric_name(i));
    if any(keys == key)
        continue;
    end
    issues(end+1, :) = additions(i, :); %#ok<AGROW>
    keys(end+1, 1) = key; %#ok<AGROW>
end
end

function T = localAlignIssueColumns(T)
template = localIssueRow();
vars = string(fieldnames(template));
for i = 1:numel(vars)
    if ~ismember(vars(i), string(T.Properties.VariableNames))
        T.(vars(i)) = repmat(template.(vars(i)), height(T), 1);
    end
end
T = T(:, vars);
end

function row = localIssueRow(issueId, severity, issueStatus, issueCategory, direction, ueId, cellId, blockName, metricName, observedValue, expectedOrPolicy, evidenceArtifactRef, rootCauseHint, fixPlan, analyticsVisibleFlag)
if nargin == 0
    row = struct( ...
        "issue_id", "", ...
        "severity", "", ...
        "issue_status", "", ...
        "issue_category", "", ...
        "direction", "", ...
        "ue_id", NaN, ...
        "cell_id", NaN, ...
        "block_name", "", ...
        "metric_name", "", ...
        "observed_value", "", ...
        "expected_or_policy", "", ...
        "evidence_artifact_ref", "", ...
        "root_cause_hint", "", ...
        "fix_plan", "", ...
        "analytics_visible_flag", true);
        return;
    end
    row = struct( ...
        "issue_id", string(issueId), ...
        "severity", string(severity), ...
        "issue_status", string(issueStatus), ...
        "issue_category", string(issueCategory), ...
        "direction", string(direction), ...
        "ue_id", double(ueId), ...
        "cell_id", double(cellId), ...
        "block_name", string(blockName), ...
        "metric_name", string(metricName), ...
        "observed_value", string(observedValue), ...
        "expected_or_policy", string(expectedOrPolicy), ...
        "evidence_artifact_ref", string(evidenceArtifactRef), ...
        "root_cause_hint", string(rootCauseHint), ...
        "fix_plan", string(fixPlan), ...
        "analytics_visible_flag", logical(analyticsVisibleFlag));
end

function out = localSeverity(issueId)
issueId = upper(string(issueId));
if any(startsWith(issueId, ["RESULTS","TRUTH","CLAIM","REALPHY"])) || any(issueId == ["GRID-01","READBACK-01"])
    out = "critical";
elseif issueId == "PROFILE-01"
    out = "high";
else
    out = "medium";
end
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end

function s = localReadJSON(pathStr)
s = struct();
if exist(pathStr, "file") ~= 2
    return;
end
try
    s = jsondecode(fileread(pathStr));
catch
    s = struct();
end
end

function out = localTableText(T, idx, varName, defaultValue)
out = string(defaultValue);
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
out = string(T.(varName)(idx));
end

function out = localTableLogical(T, idx, varName, defaultValue)
out = logical(defaultValue);
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
try
    out = logical(T.(varName)(idx));
catch
    out = any(strcmpi(string(T.(varName)(idx)), ["true","1","yes","pass"]));
end
end
