function verdict = evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, varargin)
%EVALUATELLSRUNTIMETRUTHCONTRACT Fail closed on missing honest-LLS evidence.

p = inputParser;
p.addParameter("Result", struct());
p.parse(varargin{:});

if nargin < 1 || strlength(string(runFolder)) == 0
    error("sixgr:truth:MissingRunFolder", "A run folder is required for runtime truth contract evaluation.");
end
if nargin < 2
    scfg = struct();
end
if nargin < 3
    cfg = struct();
end

layout = sixgr.report.resultLayout(runFolder);

verdict = struct();
verdict.Ok = true;
verdict.RuntimeTruthContractOk = true;
verdict.RoundtripMismatchCount = 0;
verdict.RequiredRuntimeEvidenceMissingCount = 0;
verdict.StrictTruthFailureCount = 0;
verdict.StrictProxyGuardFailureCount = 0;
verdict.CanonicalArtifactGapCount = 0;
verdict.RoundtripStatusDetails = strings(0, 1);
verdict.DLTrialCount = 0;
verdict.ULTrialCount = 0;
verdict.RequiredDL = false;
verdict.RequiredUL = false;
verdict.Failures = strings(0, 1);

[verdict.RequiredDL, verdict.RequiredUL] = localRequiredDirections(scfg, cfg);
strictTruthRequired = localRequiresStrictRuntimeTruthContract(scfg, cfg);

dlTrialsPath = fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv");
ulTrialsPath = fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv");
dlTrials = localReadTable(dlTrialsPath);
ulTrials = localReadTable(ulTrialsPath);
try
    opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials);
    verdict.DLTrialCount = localGetNestedDouble(opSummary, ["DL", "SampleCount"], height(dlTrials));
    verdict.ULTrialCount = localGetNestedDouble(opSummary, ["UL", "SampleCount"], height(ulTrials));
catch ME
    verdict.DLTrialCount = height(dlTrials);
    verdict.ULTrialCount = height(ulTrials);
    verdict = localAddFailure(verdict, "effective_trial_count_summary_failed:" + string(ME.identifier), "evidence");
end

requiredArtifacts = [
    fullfile(layout.ReportCSVDir, "scenario_summary.csv")
    fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv")
    fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv")
    fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv")
    fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv")
    fullfile(layout.ReportCSVDir, "value_source_audit.csv")
    ];
if verdict.RequiredDL
    requiredArtifacts(end + 1, 1) = dlTrialsPath;
    if strictTruthRequired
        requiredArtifacts(end + 1, 1) = fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv");
    end
end
if verdict.RequiredUL
    requiredArtifacts(end + 1, 1) = ulTrialsPath;
    if strictTruthRequired
        requiredArtifacts(end + 1, 1) = fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv");
    end
end

for ii = 1:numel(requiredArtifacts)
    artifactPath = string(requiredArtifacts(ii));
    if ~isfile(artifactPath)
        verdict.CanonicalArtifactGapCount = verdict.CanonicalArtifactGapCount + 1;
        verdict = localAddFailure(verdict, "missing_required_artifact:" + localRelativePath(runFolder, artifactPath), "artifact");
    elseif endsWith(lower(artifactPath), ".csv")
        artifactTable = localReadTable(artifactPath);
        if isempty(artifactTable) || height(artifactTable) == 0
            verdict.CanonicalArtifactGapCount = verdict.CanonicalArtifactGapCount + 1;
            verdict = localAddFailure(verdict, "empty_required_artifact:" + localRelativePath(runFolder, artifactPath), "artifact");
        end
    end
end

if verdict.RequiredDL && verdict.DLTrialCount <= 0
    verdict = localAddFailure(verdict, "effective_dl_trial_count=0", "evidence");
end
if verdict.RequiredUL && verdict.ULTrialCount <= 0
    verdict = localAddFailure(verdict, "effective_ul_trial_count=0", "evidence");
end

configuredUsers = localScenarioGetDouble(scfg, cfg, "users.n_users", NaN);
if isnan(configuredUsers)
    configuredUsers = localScenarioGetDouble(scfg, cfg, "topology.num_ues", NaN);
end
runtimeMode = localReadTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
if configuredUsers > 0
    if isempty(runtimeMode) || height(runtimeMode) == 0
        verdict = localAddFailure(verdict, "configured_users_missing_runtime_operating_mode_proof", "evidence");
    elseif localHasColumn(runtimeMode, "ConfiguredUsers")
        observedUsers = localTableMaxNumeric(runtimeMode, "ConfiguredUsers", NaN);
        if isnan(observedUsers) || observedUsers <= 0
            verdict = localAddFailure(verdict, "configured_users_runtime_proof_unavailable", "evidence");
        end
    else
        verdict = localAddFailure(verdict, "configured_users_runtime_proof_column_missing", "evidence");
    end
end

[proxyFailureCount, proxyFailures] = localRuntimeModeFailures(runtimeMode, scfg, cfg);
verdict.StrictProxyGuardFailureCount = verdict.StrictProxyGuardFailureCount + proxyFailureCount;
for ii = 1:numel(proxyFailures)
    verdict = localAddFailure(verdict, proxyFailures(ii), "proxy");
end

roundtripFiles = [
    fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"), "ConsistencyStatus", "consistent"
    fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv"), "ConsistencyStatus", "consistent"
    fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv"), "ConsistencyStatus", "consistent"
    ];
if strictTruthRequired
    roundtripFiles = [roundtripFiles; fullfile(layout.ReportCSVDir, "value_source_audit.csv"), "ConsistencyStatus", "observed"];
end
for ii = 1:size(roundtripFiles, 1)
    artifactPath = roundtripFiles(ii, 1);
    T = localReadTable(artifactPath);
    [badCount, detailText] = localCountBadStatuses(T, roundtripFiles(ii, 2), roundtripFiles(ii, 3));
    verdict.RoundtripMismatchCount = verdict.RoundtripMismatchCount + badCount;
    if badCount > 0
        verdict.RoundtripStatusDetails(end + 1, 1) = localRelativePath(runFolder, artifactPath) + ":" + detailText;
    end
end
if verdict.RoundtripMismatchCount > 0
    verdict = localAddFailure(verdict, "roundtrip_mismatch_count=" + string(verdict.RoundtripMismatchCount), "roundtrip");
end

[rawLifecycleStats, rawLifecycleFailures] = localRawLifecycleStats(dlTrials, ulTrials, ...
    verdict.RequiredDL && strictTruthRequired, verdict.RequiredUL && strictTruthRequired);
for ii = 1:numel(rawLifecycleFailures)
    verdict = localAddFailure(verdict, rawLifecycleFailures(ii), "evidence");
end

[ferStats, ferFailures] = localFERScopeStats(layout);
for ii = 1:numel(ferFailures)
    verdict = localAddFailure(verdict, ferFailures(ii), "evidence");
end

[amcStats, amcFailures] = localAMCNamingStats(runtimeMode, dlTrials, ulTrials);
for ii = 1:numel(amcFailures)
    verdict = localAddFailure(verdict, amcFailures(ii), "evidence");
end

hiddenDefaultStats = localHiddenDefaultStats(layout);
if double(hiddenDefaultStats.DangerousHiddenFallbackCount) > 0
    verdict = localAddFailure(verdict, "dangerous_hidden_default_count=" + string(hiddenDefaultStats.DangerousHiddenFallbackCount), "evidence");
end

proxyStats = localProxySummaryStats(runtimeMode);

verdict.CheckDetails = struct( ...
    "RawLifecycle", rawLifecycleStats, ...
    "FER", ferStats, ...
    "AMC", amcStats, ...
    "HiddenDefaults", hiddenDefaultStats, ...
    "Proxy", proxyStats);
verdict.StrictTruthFailureCount = numel(verdict.Failures);
verdict.Ok = verdict.StrictTruthFailureCount == 0;
verdict.RuntimeTruthContractOk = verdict.Ok;
localWriteTruthContractArtifacts(layout, runFolder, scfg, cfg, verdict);
end

function [requiredDL, requiredUL] = localRequiredDirections(scfg, cfg)
direction = lower(strtrim(string(localScenarioGet(scfg, cfg, "simulation.link_direction", "both"))));
if strlength(direction) == 0 || direction == "all"
    direction = "both";
end
requiredDL = any(direction == ["both", "dl", "downlink"]);
requiredUL = any(direction == ["both", "ul", "uplink"]);
end

function tf = localRequiresStrictRuntimeTruthContract(scfg, cfg)
execModel = lower(strtrim(string(localScenarioGet(scfg, cfg, "users.execution_model", ""))));
honestyMode = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.honesty_mode", ""))));
scenarioGroup = lower(strtrim(string(localScenarioGet(scfg, cfg, "meta.scenario_group", ""))));
tags = lower(string(localScenarioGet(scfg, cfg, "meta.tags", strings(0, 1))));
if iscell(tags)
    tags = lower(string(tags(:)));
end
tags = tags(:);
tf = execModel == "slot_coupled_truth" || honestyMode == "strict" || ...
    any(ismember(tags, ["no-proxy", "truth", "strict_truth", "coupled_truth"])) || ...
    any(contains(scenarioGroup, "truth"));
end

function [failureCount, failures] = localRuntimeModeFailures(runtimeMode, scfg, cfg)
failureCount = 0;
failures = strings(0, 1);
if isempty(runtimeMode) || height(runtimeMode) == 0
    failures(end + 1, 1) = "runtime_operating_mode_missing";
    failureCount = failureCount + 1;
    return;
end

if localHasColumn(runtimeMode, "ProxyPHYActive") && any(localColumnBool(runtimeMode, "ProxyPHYActive"))
    failures(end + 1, 1) = "proxy_phy_active_in_runtime_operating_mode";
end
if localHasColumn(runtimeMode, "FallbackUsed") && any(localColumnBool(runtimeMode, "FallbackUsed"))
    failures(end + 1, 1) = "fallback_used_in_runtime_operating_mode";
end
if localHasColumn(runtimeMode, "WaveformPHYActive") && ~all(localColumnBool(runtimeMode, "WaveformPHYActive"))
    failures(end + 1, 1) = "waveform_phy_not_active_for_all_runtime_rows";
end

proxyTokens = ["abstract", "proxy", "lut", "bler", "sinr_to_bler", "fallback"];
for col = ["ExecutionBackend", "PHYMode", "InterferenceMode", "ApproximationMode", "E2EAirModel"]
    if localHasColumn(runtimeMode, col)
        values = lower(string(runtimeMode.(col)));
        values(ismissing(values)) = "";
        for token = proxyTokens
            if any(contains(values, token))
                failures(end + 1, 1) = lower(col) + "_contains_proxy_token:" + token;
                break;
            end
        end
    end
end

interCellEnabled = localScenarioGetBool(scfg, cfg, "interference.inter_cell_interference_enable", false) || ...
    localScenarioGetBool(scfg, cfg, "interference.inter_cell_interference_flag", false);
if interCellEnabled
    if ~localHasColumn(runtimeMode, "InterferenceMode")
        failures(end + 1, 1) = "inter_cell_interference_enabled_but_interference_mode_missing";
    else
        modes = lower(strtrim(string(runtimeMode.InterferenceMode)));
        modes(ismissing(modes)) = "";
        acceptable = modes == "full_per_link_channel_waveform_sum";
        if any(~acceptable)
            failures(end + 1, 1) = "inter_cell_interference_not_waveform_backed";
        end
    end
end

failures = unique(failures, "stable");
failureCount = numel(failures);
end

function T = localReadTable(pathValue)
pathValue = string(pathValue);
if ~isfile(pathValue)
    T = table();
    return;
end
try
    T = readtable(pathValue, ...
        "FileType", "text", ...
        "Delimiter", ",", ...
        "ReadVariableNames", true, ...
        "TextType", "string", ...
        "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function verdict = localAddFailure(verdict, failureText, failureClass)
failureText = string(failureText);
if strlength(failureText) == 0
    return;
end
if ~any(verdict.Failures == failureText)
    verdict.Failures(end + 1, 1) = failureText;
end
if failureClass == "evidence"
    verdict.RequiredRuntimeEvidenceMissingCount = verdict.RequiredRuntimeEvidenceMissingCount + 1;
elseif failureClass == "proxy"
    verdict.StrictProxyGuardFailureCount = verdict.StrictProxyGuardFailureCount + 1;
end
end

function [count, detailText] = localCountBadStatuses(T, statusColumn, expectedPrefix)
count = 0;
detailText = "rows=0";
if isempty(T) || height(T) == 0
    return;
end
statusColumn = string(statusColumn);
if ~localHasColumn(T, statusColumn)
    statusColumn = localResolveStatusColumnAlias(T, statusColumn);
    if strlength(statusColumn) == 0
        count = height(T);
        detailText = "missing_status_column rows=" + string(height(T));
        return;
    end
end
statuses = lower(strtrim(string(T.(statusColumn))));
statuses(ismissing(statuses)) = "";
expectedPrefix = lower(string(expectedPrefix));
if expectedPrefix == "consistent"
    ok = startsWith(statuses, "consistent");
elseif expectedPrefix == "observed"
    ok = statuses == "observed";
else
    ok = statuses == expectedPrefix;
end
count = sum(~ok);
detailText = "status_column=" + statusColumn + " bad=" + string(count) + "/" + string(height(T)) + ...
    " statuses=" + localStatusCountsText(statuses);
end

function text = localStatusCountsText(statuses)
statuses = string(statuses(:));
if isempty(statuses)
    text = "";
    return;
end
values = unique(statuses, "stable");
parts = strings(numel(values), 1);
for ii = 1:numel(values)
    label = values(ii);
    if strlength(label) == 0
        label = "<empty>";
    end
    parts(ii) = label + "=" + string(sum(statuses == values(ii)));
end
text = strjoin(parts, ",");
end

function statusColumn = localResolveStatusColumnAlias(T, requestedColumn)
requestedColumn = lower(string(requestedColumn));
candidates = strings(0, 1);
if requestedColumn == "consistencystatus"
    candidates = ["Status"; "status"; "Consistency"; "consistency_status"];
elseif requestedColumn == "status"
    candidates = ["ConsistencyStatus"; "consistency_status"];
end
statusColumn = "";
if isempty(T) || isempty(candidates)
    return;
end
names = string(T.Properties.VariableNames);
lowerNames = lower(names);
for ii = 1:numel(candidates)
    idx = find(lowerNames == lower(candidates(ii)), 1, "first");
    if ~isempty(idx)
        statusColumn = names(idx);
        return;
    end
end
end

function tf = localHasColumn(T, columnName)
tf = ~isempty(T) && any(string(T.Properties.VariableNames) == string(columnName));
end

function values = localColumnBool(T, columnName)
raw = T.(string(columnName));
if islogical(raw)
    values = raw;
elseif isnumeric(raw)
    values = raw ~= 0 & ~isnan(raw);
else
    values = lower(strtrim(string(raw)));
    values = values == "1" | values == "true" | values == "yes";
end
values = values(:);
end

function [stats, failures] = localRawLifecycleStats(dlTrials, ulTrials, requiredDL, requiredUL)
stats = struct( ...
    "DLRows", height(dlTrials), ...
    "ULRows", height(ulTrials), ...
    "DLFinalizedRows", 0, ...
    "ULFinalizedRows", 0, ...
    "DLPartialRows", 0, ...
    "ULPartialRows", 0, ...
    "DLPrimaryOKRows", 0, ...
    "ULPrimaryOKRows", 0, ...
    "DLPrimaryOKNotFinalizedRows", 0, ...
    "ULPrimaryOKNotFinalizedRows", 0, ...
    "RawLifecycleOk", true);
failures = strings(0, 1);
[stats.DLFinalizedRows, stats.DLPartialRows, stats.DLPrimaryOKRows, stats.DLPrimaryOKNotFinalizedRows, dlFailures] = ...
    localDirectionLifecycleStats(dlTrials, "DL", requiredDL);
[stats.ULFinalizedRows, stats.ULPartialRows, stats.ULPrimaryOKRows, stats.ULPrimaryOKNotFinalizedRows, ulFailures] = ...
    localDirectionLifecycleStats(ulTrials, "UL", requiredUL);
failures = [dlFailures(:); ulFailures(:)];
stats.RawLifecycleOk = isempty(failures);
end

function [finalizedRows, partialRows, primaryOKRows, primaryOKNotFinalizedRows, failures] = localDirectionLifecycleStats(T, direction, requiredFlag)
finalizedRows = 0;
partialRows = 0;
primaryOKRows = 0;
primaryOKNotFinalizedRows = 0;
failures = strings(0, 1);
direction = string(direction);
if isempty(T) || height(T) == 0
    if requiredFlag
        failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_no_rows";
    end
    return;
end
requiredColumns = ["RowLifecycleState", "FinalizedFlag", "PartialRowFlag", "PrimaryTruthValueStatus"];
missing = requiredColumns(~arrayfun(@(name) localHasColumn(T, name), requiredColumns));
if ~isempty(missing)
    failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_columns_missing:" + strjoin(missing, "|");
    return;
end
finalized = localColumnBool(T, "FinalizedFlag");
partial = localColumnBool(T, "PartialRowFlag");
primaryOK = strcmpi(strtrim(string(T.PrimaryTruthValueStatus)), "OK");
state = lower(strtrim(string(T.RowLifecycleState)));
finalizedRows = sum(finalized | state == "finalized");
partialRows = sum(partial | state == "partial");
primaryOKRows = sum(primaryOK);
primaryOKNotFinalizedRows = sum(primaryOK & ~(finalized | state == "finalized"));
if requiredFlag && finalizedRows <= 0
    failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_no_finalized_rows";
end
if primaryOKNotFinalizedRows > 0
    failures(end + 1, 1) = lower(direction) + "_primary_truth_rows_not_finalized=" + string(primaryOKNotFinalizedRows);
end
end

function [stats, failures] = localFERScopeStats(layout)
stats = struct( ...
    "FERSummaryRows", 0, ...
    "FERRunScopeRows", 0, ...
    "FERRunScopeIdentityLeakCount", 0, ...
    "FERRunScopeIdentityOk", false, ...
    "FERScopeStatus", "missing");
failures = strings(0, 1);
pathValue = fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv");
T = localReadTable(pathValue);
if isempty(T) || height(T) == 0
    failures(end + 1, 1) = "fer_summary_missing_or_empty";
    return;
end
stats.FERSummaryRows = height(T);
if ~localHasColumn(T, "Scope")
    failures(end + 1, 1) = "fer_summary_scope_column_missing";
    stats.FERScopeStatus = "scope_column_missing";
    return;
end
runMask = strcmpi(strtrim(string(T.Scope)), "run");
stats.FERRunScopeRows = sum(runMask);
if stats.FERRunScopeRows == 0
    failures(end + 1, 1) = "fer_run_scope_rows_missing";
    stats.FERScopeStatus = "run_scope_rows_missing";
    return;
end
identityLeak = false(height(T), 1);
for col = ["UEID", "UEIndex", "RNTI"]
    if localHasColumn(T, col)
        identityLeak = identityLeak | (runMask & localColumnHasFiniteIdentity(T, col));
    end
end
stats.FERRunScopeIdentityLeakCount = sum(identityLeak);
stats.FERRunScopeIdentityOk = stats.FERRunScopeIdentityLeakCount == 0;
stats.FERScopeStatus = string(ternary(stats.FERRunScopeIdentityOk, "ok", "identity_leak"));
if stats.FERRunScopeIdentityLeakCount > 0
    failures(end + 1, 1) = "fer_run_scope_identity_leak_count=" + string(stats.FERRunScopeIdentityLeakCount);
end
end

function values = localColumnHasFiniteIdentity(T, columnName)
raw = T.(string(columnName));
if isnumeric(raw)
    values = isfinite(double(raw));
else
    text = strtrim(string(raw));
    nums = str2double(text);
    values = strlength(text) > 0 & ~strcmpi(text, "nan") & isfinite(nums);
end
values = values(:);
end

function [stats, failures] = localAMCNamingStats(runtimeMode, dlTrials, ulTrials)
stats = struct( ...
    "AMCNamingOk", true, ...
    "RuntimeModeRows", height(runtimeMode), ...
    "DLTrialRows", height(dlTrials), ...
    "ULTrialRows", height(ulTrials), ...
    "PolicyBooleanCollapseCount", 0, ...
    "AppliedAuthorityMissingCount", 0, ...
    "RawAuthorityMissingCount", 0);
failures = strings(0, 1);
if isempty(runtimeMode) || height(runtimeMode) == 0
    failures(end + 1, 1) = "amc_runtime_mode_missing";
    stats.AMCNamingOk = false;
    return;
end
for col = ["ConfiguredMCSSelectionPolicy", "ActualMCSSelectionMode", "RequestedOperatingPointSource", "AppliedOperatingPointSource"]
    if ~localHasColumn(runtimeMode, col)
        failures(end + 1, 1) = "amc_runtime_mode_column_missing:" + col;
    end
end
if localHasColumn(runtimeMode, "ConfiguredMCSSelectionPolicy")
    policy = lower(strtrim(string(runtimeMode.ConfiguredMCSSelectionPolicy)));
    badPolicy = ismember(policy, ["0", "1", "true", "false", "yes", "no"]);
    stats.PolicyBooleanCollapseCount = sum(badPolicy);
    if any(badPolicy)
        failures(end + 1, 1) = "amc_policy_collapsed_to_boolean";
    end
end
if localHasColumn(runtimeMode, "AppliedOperatingPointSource")
    applied = strtrim(string(runtimeMode.AppliedOperatingPointSource));
    stats.AppliedAuthorityMissingCount = sum(strlength(applied) == 0);
    if stats.AppliedAuthorityMissingCount > 0
        failures(end + 1, 1) = "amc_applied_operating_point_source_missing";
    end
end
stats.RawAuthorityMissingCount = localRawAMCMissingCount(dlTrials) + localRawAMCMissingCount(ulTrials);
if stats.RawAuthorityMissingCount > 0
    failures(end + 1, 1) = "raw_trial_amc_authority_missing_count=" + string(stats.RawAuthorityMissingCount);
end
failures = unique(failures, "stable");
stats.AMCNamingOk = isempty(failures);
end

function count = localRawAMCMissingCount(T)
count = 0;
if isempty(T) || height(T) == 0
    return;
end
for col = ["MCSAuthority", "ModulationAuthority", "AppliedOperatingPointSource", "ConfiguredMCSSelectionPolicy"]
    if ~localHasColumn(T, col)
        count = count + height(T);
    else
        count = count + sum(strlength(strtrim(string(T.(col)))) == 0);
    end
end
end

function stats = localHiddenDefaultStats(layout)
stats = struct( ...
    "HardcodedAuditRows", 0, ...
    "HistoricalDangerousHiddenFallbackRows", 0, ...
    "DangerousHiddenFallbackCount", 0, ...
    "HiddenDefaultAuditStatus", "missing");
T = localReadTable(fullfile(layout.ReportCSVDir, "hardcoded_parameter_audit.csv"));
if isempty(T) || height(T) == 0
    return;
end
stats.HardcodedAuditRows = height(T);
classification = lower(strtrim(string(localOptionalColumn(T, "Classification", ""))));
statusAfter = lower(strtrim(string(localOptionalColumn(T, "StatusAfterPatch", ""))));
actionTaken = lower(strtrim(string(localOptionalColumn(T, "ActionTaken", ""))));
dangerous = contains(classification, "dangerous") | contains(classification, "hidden_fallback") | ...
    contains(statusAfter, "dangerous") | contains(statusAfter, "hidden_fallback_unresolved") | ...
    contains(actionTaken, "dangerous_hidden_fallback");
stats.HistoricalDangerousHiddenFallbackRows = sum(dangerous);

resolvedTokens = ["removed", "config_owned", "derived", "explicit", "justified", ...
    "kept_legitimate", "standard_constant", "internal", "resolved", "owned"];
resolved = false(size(statusAfter));
for token = resolvedTokens
    resolved = resolved | contains(statusAfter, token);
end
actionResolvedTokens = ["removed", "moved", "explicit", "derived", "config", "resolved", "yaml"];
for token = actionResolvedTokens
    resolved = resolved | contains(actionTaken, token);
end
unresolvedStatusTokens = ["unresolved", "pending", "todo", "missing", "not_removed", "still_hidden"];
unresolved = false(size(statusAfter));
for token = unresolvedStatusTokens
    unresolved = unresolved | contains(statusAfter, token);
end
unresolvedActionTokens = ["unresolved", "pending", "todo", "not removed", "not_removed", "still hidden", "still_hidden"];
for token = unresolvedActionTokens
    unresolved = unresolved | contains(actionTaken, token);
end

unresolvedDangerous = dangerous & (~resolved | unresolved);
stats.DangerousHiddenFallbackCount = sum(unresolvedDangerous);
if stats.DangerousHiddenFallbackCount == 0
    stats.HiddenDefaultAuditStatus = string(ternary(stats.HistoricalDangerousHiddenFallbackRows == 0, ...
        "no_dangerous_hidden_fallback_rows", "historical_dangerous_hidden_fallbacks_resolved"));
else
    stats.HiddenDefaultAuditStatus = "unresolved_dangerous_hidden_fallback_rows_present";
end
end

function stats = localProxySummaryStats(runtimeMode)
stats = struct( ...
    "RuntimeModeRows", height(runtimeMode), ...
    "ProxyPHYActiveRows", 0, ...
    "FallbackUsedRows", 0, ...
    "NonWaveformPHYRows", 0, ...
    "SyntheticBLERFallbackTokenRows", 0, ...
    "NoProxyPHYOk", false, ...
    "SyntheticBLERFallbackOk", false);
if isempty(runtimeMode) || height(runtimeMode) == 0
    return;
end
if localHasColumn(runtimeMode, "ProxyPHYActive")
    stats.ProxyPHYActiveRows = sum(localColumnBool(runtimeMode, "ProxyPHYActive"));
end
if localHasColumn(runtimeMode, "FallbackUsed")
    stats.FallbackUsedRows = sum(localColumnBool(runtimeMode, "FallbackUsed"));
end
if localHasColumn(runtimeMode, "WaveformPHYActive")
    stats.NonWaveformPHYRows = sum(~localColumnBool(runtimeMode, "WaveformPHYActive"));
end
stats.SyntheticBLERFallbackTokenRows = localTokenRowCount(runtimeMode, ...
    ["ExecutionBackend", "PHYMode", "ApproximationMode", "E2EAirModel"], ...
    ["bler_lut", "bler_db", "sinr_to_bler", "synthetic_bler"]);
stats.NoProxyPHYOk = stats.ProxyPHYActiveRows == 0 && stats.FallbackUsedRows == 0 && stats.NonWaveformPHYRows == 0;
stats.SyntheticBLERFallbackOk = stats.SyntheticBLERFallbackTokenRows == 0;
end

function count = localTokenRowCount(T, columns, tokens)
count = 0;
if isempty(T) || height(T) == 0
    return;
end
mask = false(height(T), 1);
for col = columns
    if ~localHasColumn(T, col)
        continue;
    end
    values = lower(string(T.(col)));
    values(ismissing(values)) = "";
    for token = tokens
        mask = mask | contains(values, lower(string(token)));
    end
end
count = sum(mask);
end

function localWriteTruthContractArtifacts(layout, runFolder, scfg, cfg, verdict)
summaryPath = fullfile(layout.ReportCSVDir, "truth_contract_summary.csv");
failuresPath = fullfile(layout.ReportCSVDir, "truth_contract_failures.csv");
details = sixgr.util.structGet(verdict, "CheckDetails", struct());
raw = sixgr.util.structGet(details, "RawLifecycle", struct());
fer = sixgr.util.structGet(details, "FER", struct());
amc = sixgr.util.structGet(details, "AMC", struct());
hidden = sixgr.util.structGet(details, "HiddenDefaults", struct());
proxy = sixgr.util.structGet(details, "Proxy", struct());
failures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
failures = failures(:);
[scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg);

summaryT = table( ...
    scenarioID, ...
    runTag, ...
    configHash, ...
    "truth_contract_v1", ...
    "sixgr.truth.evaluateLLSRuntimeTruthContract", ...
    logical(verdict.RuntimeTruthContractOk), ...
    logical(verdict.Ok), ...
    double(verdict.StrictTruthFailureCount), ...
    double(verdict.StrictProxyGuardFailureCount), ...
    double(verdict.CanonicalArtifactGapCount), ...
    double(verdict.RoundtripMismatchCount), ...
    double(verdict.RequiredRuntimeEvidenceMissingCount), ...
    logical(sixgr.util.structGet(proxy, "NoProxyPHYOk", false)), ...
    logical(sixgr.util.structGet(proxy, "SyntheticBLERFallbackOk", false)), ...
    logical(sixgr.util.structGet(raw, "RawLifecycleOk", false)), ...
    double(sixgr.util.structGet(raw, "DLFinalizedRows", NaN)), ...
    double(sixgr.util.structGet(raw, "ULFinalizedRows", NaN)), ...
    double(sixgr.util.structGet(raw, "DLPartialRows", NaN)), ...
    double(sixgr.util.structGet(raw, "ULPartialRows", NaN)), ...
    logical(sixgr.util.structGet(fer, "FERRunScopeIdentityOk", false)), ...
    double(sixgr.util.structGet(fer, "FERRunScopeIdentityLeakCount", NaN)), ...
    logical(sixgr.util.structGet(amc, "AMCNamingOk", false)), ...
    double(sixgr.util.structGet(amc, "PolicyBooleanCollapseCount", NaN)), ...
    string(sixgr.util.structGet(hidden, "HiddenDefaultAuditStatus", "")), ...
    double(sixgr.util.structGet(hidden, "HistoricalDangerousHiddenFallbackRows", NaN)), ...
    double(sixgr.util.structGet(hidden, "DangerousHiddenFallbackCount", NaN)), ...
    string(strjoin(failures, "; ")), ...
    string(localRelativePath(runFolder, summaryPath)), ...
    string(localRelativePath(runFolder, failuresPath)), ...
    'VariableNames', {'ScenarioID','RunTag','ConfigHash','TruthContractVersion','StatusAuthority', ...
    'RuntimeTruthContractOk','ResultOk','StrictTruthFailureCount','StrictProxyGuardFailureCount', ...
    'CanonicalArtifactGapCount','RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'NoProxyPHYOk','SyntheticBLERFallbackOk','RawLifecycleOk','DLFinalizedRows','ULFinalizedRows', ...
    'DLPartialRows','ULPartialRows','FERRunScopeIdentityOk','FERRunScopeIdentityLeakCount', ...
    'AMCNamingOk','AMCPolicyBooleanCollapseCount','HiddenDefaultAuditStatus','HistoricalDangerousHiddenFallbackRows','DangerousHiddenFallbackCount', ...
    'FailureSummary','TruthContractSummaryArtifact','TruthContractFailuresArtifact'});
sixgr.util.csvWriteTable(summaryPath, summaryT);

failureT = localBuildTruthContractFailureTable(failures, verdict, scfg, cfg, layout);
sixgr.util.csvWriteTable(failuresPath, failureT);
end

function T = localBuildTruthContractFailureTable(failures, verdict, scfg, cfg, layout)
varNames = {'ScenarioID','RunTag','ConfigHash','FailureIndex','FailureCode','FailureCategory','FailureSeverity','StatusAuthority','RequiredFailureCountContribution','FailureDefinition'};
varTypes = {'string','string','string','double','string','string','string','string','double','string'};
[scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg);
statusAuthority = "sixgr.truth.evaluateLLSRuntimeTruthContract";
failures = string(failures(:));
failures = failures(strlength(failures) > 0);
if isempty(failures)
    T = table('Size', [0 numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
    return;
end
n = numel(failures);
categories = strings(n, 1);
for ii = 1:n
    categories(ii) = localClassifyFailure(failures(ii));
end
T = table( ...
    repmat(scenarioID, n, 1), ...
    repmat(runTag, n, 1), ...
    repmat(configHash, n, 1), ...
    (1:n).', ...
    failures, ...
    categories, ...
    repmat("required_truth_contract_gate", n, 1), ...
    repmat(statusAuthority, n, 1), ...
    ones(n, 1), ...
    repmat("Run-level success is blocked until this required truth-contract failure is resolved.", n, 1), ...
    'VariableNames', varNames);
end

function category = localClassifyFailure(failure)
failure = lower(string(failure));
if contains(failure, "proxy") || contains(failure, "fallback") || contains(failure, "abstract") || contains(failure, "bler")
    category = "proxy_or_fallback";
elseif contains(failure, "roundtrip") || contains(failure, "consistent")
    category = "roundtrip";
elseif contains(failure, "artifact")
    category = "canonical_artifact";
elseif contains(failure, "fer")
    category = "fer_scope";
elseif contains(failure, "amc")
    category = "amc_labeling";
elseif contains(failure, "lifecycle") || contains(failure, "finalized")
    category = "raw_lifecycle";
else
    category = "runtime_evidence";
end
end

function [scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg)
scenarioID = string(localScenarioGet(scfg, cfg, "scenario_id", localScenarioGet(scfg, cfg, "scenario.id", "")));
runTag = string(localScenarioGet(scfg, cfg, "run.runTag", sixgr.util.structGet(cfg, "run.runTag", "")));
configHash = string(localScenarioGet(scfg, cfg, "meta.configHash", sixgr.util.structGet(cfg, "meta.configHash", "")));

runtimeMode = localReadTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
roundtrip = localReadTable(fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"));
summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
scenarioID = localFirstNonBlank(scenarioID, runtimeMode, roundtrip, summary, ["ScenarioID", "ScenarioId", "scenario_id"]);
runTag = localFirstNonBlank(runTag, runtimeMode, roundtrip, summary, ["RunTag", "run_tag"]);
configHash = localFirstNonBlank(configHash, runtimeMode, roundtrip, summary, ["ConfigHash", "config_hash"]);
end

function value = localFirstNonBlank(value, varargin)
value = string(value);
if ~ismissing(value) && strlength(strtrim(value)) > 0
    return;
end
if numel(varargin) < 2
    return;
end
columnNames = string(varargin{end});
tables = varargin(1:end-1);
for tt = 1:numel(tables)
    T = tables{tt};
    if isempty(T) || height(T) == 0
        continue;
    end
    for cc = 1:numel(columnNames)
        col = columnNames(cc);
        if localHasColumn(T, col)
            raw = string(T.(col));
            raw = raw(~ismissing(raw) & strlength(strtrim(raw)) > 0);
            if ~isempty(raw)
                value = raw(1);
                return;
            end
        end
    end
end
end

function value = localOptionalColumn(T, name, defaultValue)
n = height(T);
if localHasColumn(T, name)
    value = T.(string(name));
    return;
end
if isstring(defaultValue) || ischar(defaultValue)
    value = repmat(string(defaultValue), n, 1);
elseif islogical(defaultValue)
    value = repmat(logical(defaultValue), n, 1);
else
    value = repmat(defaultValue, n, 1);
end
end

function out = ternary(condition, a, b)
if condition
    out = a;
else
    out = b;
end
end

function value = localTableMaxNumeric(T, columnName, defaultValue)
value = defaultValue;
if ~localHasColumn(T, columnName)
    return;
end
raw = T.(string(columnName));
if isnumeric(raw)
    nums = raw;
else
    nums = str2double(string(raw));
end
nums = nums(~isnan(nums));
if ~isempty(nums)
    value = max(nums);
end
end

function value = localGetNestedDouble(S, pathParts, defaultValue)
value = defaultValue;
try
    tmp = S;
    for ii = 1:numel(pathParts)
        key = char(pathParts(ii));
        tmp = tmp.(key);
    end
    value = double(tmp);
catch
    value = defaultValue;
end
end

function value = localScenarioGetDouble(scfg, cfg, pathValue, defaultValue)
raw = localScenarioGet(scfg, cfg, pathValue, defaultValue);
if isnumeric(raw) && isscalar(raw)
    value = double(raw);
else
    value = str2double(string(raw));
    if isnan(value)
        value = defaultValue;
    end
end
end

function value = localScenarioGetBool(scfg, cfg, pathValue, defaultValue)
raw = localScenarioGet(scfg, cfg, pathValue, defaultValue);
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = raw ~= 0;
else
    text = lower(strtrim(string(raw)));
    value = text == "true" || text == "1" || text == "yes" || text == "on";
end
if isempty(value)
    value = defaultValue;
end
end

function value = localScenarioGet(scfg, cfg, pathValue, defaultValue)
value = defaultValue;
try
    if isobject(scfg) && ismethod(scfg, "get")
        value = scfg.get(pathValue, defaultValue);
        return;
    end
catch
end
try
    value = sixgr.util.structGet(scfg, pathValue, defaultValue);
    if ~isequal(value, defaultValue)
        return;
    end
catch
end
try
    value = sixgr.util.structGet(cfg, pathValue, defaultValue);
catch
    value = defaultValue;
end
end

function rel = localRelativePath(rootFolder, artifactPath)
rootFolder = string(rootFolder);
artifactPath = string(artifactPath);
rootWithSep = rootFolder;
if ~endsWith(rootWithSep, filesep)
    rootWithSep = rootWithSep + filesep;
end
if startsWith(artifactPath, rootWithSep)
    rel = extractAfter(artifactPath, strlength(rootWithSep));
else
    rel = artifactPath;
end
rel = replace(rel, "\", "/");
end
