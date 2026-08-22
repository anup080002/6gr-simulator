function audit = auditFixedSNRSweepRun(runFolder, varargin)
%AUDITFIXEDSNRSWEEPRUN Verify fixed-SNR sweep artifacts from executed evidence.
%
%   audit = sixgr.validation.auditFixedSNRSweepRun(runFolder)
%   reads the fixed-link sweep artifacts for a completed run and writes:
%     reports/csv/fixed_snr_sweep_audit.csv
%     reports/csv/fixed_snr_sweep_monotonicity_audit.csv
%     reports/csv/fixed_snr_sweep_required_outputs.csv
%     reports/json/fixed_snr_sweep_audit.json
%
%   The audit is fail-closed: it never fabricates curves, trial rows, or
%   audit pass states when runtime evidence is missing or inconsistent.

p = inputParser;
p.addParameter("Strict", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("WriteOutputs", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("GridTolerance", 1e-9, @(x)isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter("DefaultMaxSINRMinusSNR_dB", 3, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
p.parse(varargin{:});
opt = p.Results;

rootRunFolder = localResolveRootRunFolder(runFolder);
if exist(rootRunFolder, "dir") ~= 7
    error("sixgr:validation:auditFixedSNRSweepRun:RunFolderMissing", ...
        "Run folder does not exist: %s", rootRunFolder);
end

layout = sixgr.report.resultLayout(rootRunFolder);
reportJSONDir = fullfile(layout.ReportDir, "json");

art = localReadArtifacts(layout);
cfg = art.ResolvedConfig.Data;
req = localResolveRequirements(cfg, art, opt);

requiredOutputs = localBuildRequiredOutputsTable(art, req, rootRunFolder);
rows = repmat(localEmptyAuditRow(), 0, 1);
monotonicityRows = repmat(localEmptyMonotonicityRow(), 0, 1);

rows = [rows; localRequiredOutputAuditRows(requiredOutputs)]; %#ok<AGROW>
rows = [rows; localRunClassAuditRows(req)]; %#ok<AGROW>
rows = [rows; localConfiguredGridAuditRows(req, art.Campaign.Table, opt)]; %#ok<AGROW>
rows = [rows; localCampaignArtifactAuditRows(req, art)]; %#ok<AGROW>

for direction = ["DL", "UL"]
    enabled = localDirectionEnabled(req, direction);
    blerT = localDirectionCurveTable(art, direction, "BLER");
    berT = localDirectionCurveTable(art, direction, "BER");
    trialT = localDirectionTrialTable(art, direction);
    rows = [rows; localDirectionAuditRows(direction, enabled, req, blerT, berT, trialT)]; %#ok<AGROW>
    rows = [rows; localTargetCrossingAuditRows(direction, enabled, req, ...
        art.TargetCrossings.Table, blerT)]; %#ok<AGROW>
    monotonicityRows = [monotonicityRows; localMonotonicityAuditRows(direction, enabled, blerT)]; %#ok<AGROW>
end

rows = [rows; localMonotonicitySummaryAuditRows(monotonicityRows)]; %#ok<AGROW>
rows = [rows; localProxyEvidenceAuditRows(art)]; %#ok<AGROW>

auditTable = localRowsToTable(rows);
monotonicityTable = localMonotonicityTable(monotonicityRows);
requiredOutputsTable = requiredOutputs;

failMask = string(auditTable.Status) == "FAIL";
warnMask = string(auditTable.Status) == "WARN";

audit = struct();
audit.RootRunFolder = string(rootRunFolder);
audit.Ok = ~any(failMask);
audit.Status = localTernary(audit.Ok, "pass", "fail");
audit.Strict = logical(opt.Strict);
audit.RunClass = string(req.RunClass);
audit.FixedLinkCampaignOnly = logical(req.FixedLinkCampaignOnly);
audit.NoiseOperatingMode = string(req.NoiseOperatingMode);
audit.Direction = string(req.Direction);
audit.ConfiguredSNRGrid_dB = double(req.SNRGrid_dB(:)).';
audit.RowCount = height(auditTable);
audit.FailureCount = double(nnz(failMask));
audit.WarningCount = double(nnz(warnMask));
audit.FailureCodes = unique(string(auditTable.FailureCode(failMask)), "stable");
audit.WarningCodes = unique(string(auditTable.FailureCode(warnMask)), "stable");
audit.Table = auditTable;
audit.MonotonicityTable = monotonicityTable;
audit.RequiredOutputs = requiredOutputsTable;
audit.ArtifactInventory = localArtifactInventory(art, rootRunFolder);
audit.Options = opt;

if logical(opt.WriteOutputs)
    sixgr.util.ensureFolder(layout.ReportCSVDir);
    sixgr.util.ensureFolder(reportJSONDir);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_audit.csv"), auditTable);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_monotonicity_audit.csv"), monotonicityTable);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "fixed_snr_sweep_required_outputs.csv"), requiredOutputsTable);
    jsonAudit = audit;
    jsonAudit.Table = table2struct(auditTable);
    jsonAudit.MonotonicityTable = table2struct(monotonicityTable);
    jsonAudit.RequiredOutputs = table2struct(requiredOutputsTable);
    sixgr.util.jsonWrite(fullfile(reportJSONDir, "fixed_snr_sweep_audit.json"), jsonAudit);
end

if logical(opt.Strict) && ~audit.Ok
    error("sixgr:validation:auditFixedSNRSweepRun:AuditFailed", ...
        "Fixed SNR sweep audit failed with %d failure row(s): %s", ...
        audit.FailureCount, strjoin(audit.FailureCodes, ", "));
end
end

function art = localReadArtifacts(layout)
art = struct();
art.ResolvedConfig = localReadOptionalJSON(fullfile(layout.MetaDir, "scenario_config_resolved.json"));
art.RunClassification = localReadOptionalTable(fullfile(layout.ReportCSVDir, "run_classification.csv"));
art.Campaign = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "lls_fixed_link_campaign.csv"));
art.TaskPlan = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "fixed_link_campaign_task_plan.csv"));
art.DLTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_fixed_link_campaign_trials.csv"));
art.ULTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_fixed_link_campaign_trials.csv"));
art.DLBLER = localReadOptionalTable(fullfile(layout.ReportCSVDir, "dl_fixed_snr_bler_curve.csv"));
art.ULBLER = localReadOptionalTable(fullfile(layout.ReportCSVDir, "ul_fixed_snr_bler_curve.csv"));
art.DLBER = localReadOptionalTable(fullfile(layout.ReportCSVDir, "dl_fixed_snr_ber_curve.csv"));
art.ULBER = localReadOptionalTable(fullfile(layout.ReportCSVDir, "ul_fixed_snr_ber_curve.csv"));
art.TargetCrossings = localReadOptionalTable(fullfile(layout.ReportCSVDir, ...
    "fixed_snr_sweep_curve_crossing.csv"));
% Python is the sole raster authority. Its canonical lineage binds every
% plotted dataset CSV to the rendered PNG hash; the retired MATLAB
% fixed_snr_plot_lineage.csv must not be recreated as a second authority.
art.PlotLineage = localReadOptionalTable(fullfile(layout.ReportCSVDir, "contract_plot_lineage.csv"));
end

function req = localResolveRequirements(cfg, art, opt)
configuredRunClass = localFirstTextValue([
    localGetText(cfg, "validation.RunClass", "")
    localGetText(cfg, "validation.run_class", "")
    localGetText(cfg, "scenario.run_class", "")
    localGetText(cfg, "canonical_control.validation.run_class", "")
    ]);
artifactRunClass = localRunClassificationValue(art.RunClassification.Table);
runClass = configuredRunClass;
if strlength(runClass) == 0
    runClass = artifactRunClass;
end
direction = upper(localFirstTextValue([
    localGetText(cfg, "sweeps_and_matrix.fixed_link_calibration.direction", "")
    localGetText(cfg, "validation.fixed_link_campaign.direction", "")
    localGetText(cfg, "canonical_control.run.link_direction", "")
    localGetText(cfg, "simulation.link_direction", "")
    "both"
    ]));
if strlength(direction) == 0
    direction = "BOTH";
end

grid = localFirstNumericVector({
    localGetValue(cfg, "sweeps_and_matrix.fixed_link_calibration.snr_db", [])
    localGetValue(cfg, "validation.fixed_link_campaign.snr_db", [])
    localGetValue(cfg, "sweeps_and_matrix.snr_sweep.values_db", [])
    });
grid = grid(isfinite(grid));
grid = unique(grid(:).', "stable");

ciWidthTarget = localFirstFinite([
    localGetDouble(cfg, "sweeps_and_matrix.fixed_link_calibration.ci_width_target", NaN)
    2 * localGetDouble(cfg, "validation.fixed_link_campaign.max_ci_half_width", NaN)
    ]);

req = struct();
req.RunClass = string(runClass);
req.ConfiguredRunClass = string(configuredRunClass);
req.ArtifactRunClass = string(artifactRunClass);
req.RunClassConflict = strlength(configuredRunClass) > 0 && ...
    strlength(artifactRunClass) > 0 && ...
    lower(configuredRunClass) ~= lower(artifactRunClass);
req.FixedLinkCampaignOnly = localGetLogical(cfg, "sweeps_and_matrix.fixed_link_calibration.only", ...
    localGetLogical(cfg, "canonical_control.run.fixed_link_campaign_only", ...
    localGetLogical(cfg, "run.fixedLinkCampaignOnly", false)));
req.NoiseOperatingMode = localFirstTextValue([
    localGetText(cfg, "simulation.noise_operating_mode", "")
    localGetText(cfg, "run.noiseOperatingMode", "")
    localGetText(cfg, "channel.noiseOperatingMode", "")
    ]);
req.Direction = string(direction);
req.SNRGrid_dB = double(grid(:));
req.MinTrials = localFirstFinite([
    localGetDouble(cfg, "sweeps_and_matrix.fixed_link_calibration.min_trials", NaN)
    localGetDouble(cfg, "validation.fixed_link_campaign.min_tb_per_point", NaN)
    ]);
req.MaxTrials = localFirstFinite([
    localGetDouble(cfg, "sweeps_and_matrix.fixed_link_calibration.max_trials", NaN)
    localGetDouble(cfg, "validation.fixed_link_campaign.max_tb_per_point", NaN)
    ]);
req.CIWidthTarget = ciWidthTarget;
req.MaxSINRMinusSNR_dB = localFirstFinite([
    localGetDouble(cfg, "sweeps_and_matrix.fixed_link_calibration.max_sinr_snr_delta_db", NaN)
    opt.DefaultMaxSINRMinusSNR_dB
    ]);
req.FixedSNRSweepRequired = localGetLogical(cfg, "validation.fixed_snr_sweep_required", false);
req.MeasuredSINRRequired = logical(req.FixedSNRSweepRequired) && isfinite(req.MaxSINRMinusSNR_dB);
targetBLERs = localFirstNumericVector({
    localGetValue(cfg, "validation.fixed_link_campaign.target_bler", [])
    localGetValue(cfg, "sweeps_and_matrix.fixed_link_calibration.target_bler", [])
    });
targetBLERs = unique(double(targetBLERs(:)), "stable");
targetBLERs = targetBLERs(isfinite(targetBLERs) & targetBLERs > 0 & targetBLERs < 1);
req.TargetBLERs = targetBLERs;
req.TargetBLER = localFirstFinite(targetBLERs);
req.MaxTargetCrossingBracket_dB = localFirstFinite([
    localGetDouble(cfg, "validation.fixed_link_campaign.max_target_crossing_bracket_db", NaN)
    localGetDouble(cfg, "sweeps_and_matrix.fixed_link_calibration.max_target_crossing_bracket_db", NaN)
    2
    ]);
req.RunClassificationPresent = logical(art.RunClassification.Present);
end

function T = localBuildRequiredOutputsTable(art, req, rootRunFolder)
paths = {
    "meta/scenario_config_resolved.json", "global", true
    "reports/csv/run_classification.csv", "global", true
    "air_interface/csv/lls_fixed_link_campaign.csv", "global", true
    "air_interface/csv/fixed_link_campaign_task_plan.csv", "global", true
    "air_interface/csv/dl_fixed_link_campaign_trials.csv", "DL", localDirectionEnabled(req, "DL")
    "air_interface/csv/ul_fixed_link_campaign_trials.csv", "UL", localDirectionEnabled(req, "UL")
    "reports/csv/dl_fixed_snr_bler_curve.csv", "DL", localDirectionEnabled(req, "DL")
    "reports/csv/ul_fixed_snr_bler_curve.csv", "UL", localDirectionEnabled(req, "UL")
    "reports/csv/dl_fixed_snr_ber_curve.csv", "DL", localDirectionEnabled(req, "DL")
    "reports/csv/ul_fixed_snr_ber_curve.csv", "UL", localDirectionEnabled(req, "UL")
    "reports/csv/fixed_snr_sweep_curve_crossing.csv", "global", ~isempty(req.TargetBLERs)
    "reports/csv/contract_plot_lineage.csv", "global", true
    };

rows = repmat(struct( ...
    "ArtifactPath", "", ...
    "Direction", "", ...
    "Required", false, ...
    "Present", false, ...
    "Readable", false, ...
    "NonEmpty", false, ...
    "Status", "", ...
    "FailureCode", "", ...
    "Details", ""), 0, 1);

for i = 1:size(paths, 1)
    relPath = string(paths{i, 1});
    direction = string(paths{i, 2});
    required = logical(paths{i, 3});
    entry = localArtifactLookup(art, relPath);
    row = rowsTemplate();
    row.ArtifactPath = relPath;
    row.Direction = direction;
    row.Required = required;
    row.Present = logical(entry.Present);
    row.Readable = logical(entry.Readable);
    row.NonEmpty = logical(entry.NonEmpty);
    if ~required
        row.Status = "SKIP";
        row.Details = "direction_not_enabled";
    elseif ~row.Present
        row.Status = "FAIL";
        row.FailureCode = "required_output_missing";
        row.Details = string(entry.Reason);
    elseif ~row.Readable
        row.Status = "FAIL";
        row.FailureCode = "required_output_unreadable";
        row.Details = string(entry.Reason);
    elseif ~row.NonEmpty
        row.Status = "FAIL";
        row.FailureCode = "required_output_empty";
        row.Details = string(entry.Reason);
    else
        row.Status = "PASS";
        row.Details = localRelativePath(entry.Path, rootRunFolder);
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end

T = struct2table(rows, "AsArray", true);
end

function row = rowsTemplate()
row = struct( ...
    "ArtifactPath", "", ...
    "Direction", "", ...
    "Required", false, ...
    "Present", false, ...
    "Readable", false, ...
    "NonEmpty", false, ...
    "Status", "", ...
    "FailureCode", "", ...
    "Details", "");
end

function rows = localRequiredOutputAuditRows(requiredOutputs)
rows = repmat(localEmptyAuditRow(), 0, 1);
requiredMask = logical(requiredOutputs.Required);
failCount = sum(requiredMask & string(requiredOutputs.Status) == "FAIL");
rows(end + 1, 1) = localAuditRow( ...
    "required_outputs_present_and_nonempty", ...
    "reports/csv/fixed_snr_sweep_required_outputs.csv", ...
    sum(requiredMask), ...
    failCount, ...
    sum(requiredMask & string(requiredOutputs.Status) == "PASS"), ...
    "all required outputs present, readable, and non-empty", ...
    localStatusFromFailures(failCount), ...
    localFailureToken(failCount > 0, "required_output_missing_or_empty"), ...
    "Every required audit artifact for the fixed SNR sweep must exist and contain runtime data.");
end

function rows = localRunClassAuditRows(req)
rows = repmat(localEmptyAuditRow(), 0, 1);
bad = strlength(strtrim(string(req.ConfiguredRunClass))) == 0;
rows(end + 1, 1) = localAuditRow( ...
    "run_class_present_in_resolved_config", ...
    "meta/scenario_config_resolved.json", ...
    1, double(bad), double(~bad), "true", localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "run_class_missing_from_resolved_config"), ...
    "The resolved YAML snapshot must retain the operator-owned run class.");

bad = logical(req.RunClassConflict);
rows(end + 1, 1) = localAuditRow( ...
    "run_class_config_matches_runtime_classification", ...
    "meta/scenario_config_resolved.json|reports/csv/run_classification.csv", ...
    1, double(bad), double(~bad), "true", localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "run_class_config_runtime_mismatch"), ...
    "Resolved YAML and canonical runtime classification must name the same run class.");

bad = req.RunClass ~= "fixed_snr_sweep_lls";
rows(end + 1, 1) = localAuditRow( ...
    "run_class_fixed_snr_sweep_lls", ...
    "reports/csv/run_classification.csv", ...
    1, double(bad), NaN, "fixed_snr_sweep_lls", localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "run_class_not_fixed_snr_sweep_lls"), ...
    "run_classification.csv must classify the run as fixed_snr_sweep_lls.");

bad = ~logical(req.FixedLinkCampaignOnly);
rows(end + 1, 1) = localAuditRow( ...
    "fixed_link_campaign_only_true", ...
    "meta/scenario_config_resolved.json", ...
    1, double(bad), double(logical(req.FixedLinkCampaignOnly)), "true", ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "fixed_link_campaign_only_false"), ...
    "Fixed SNR sweep runs must execute in fixed_link_campaign_only mode.");

bad = lower(strtrim(string(req.NoiseOperatingMode))) ~= "standalone_awgn_snr_argument";
rows(end + 1, 1) = localAuditRow( ...
    "noise_operating_mode_standalone_awgn", ...
    "meta/scenario_config_resolved.json", ...
    1, double(bad), NaN, "standalone_awgn_snr_argument", ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "noise_operating_mode_not_standalone_awgn"), ...
    "Fixed SNR sweep runs must resolve to standalone_awgn_snr_argument noise mode.");
end

function value = localRunClassificationValue(T)
value = "";
if ~(istable(T) && ~isempty(T) && ...
        ismember("RunClass", string(T.Properties.VariableNames)))
    return;
end
tokens = strtrim(string(T.RunClass));
tokens = tokens(~ismissing(tokens) & strlength(tokens) > 0);
if isempty(tokens)
    return;
end
uniqueTokens = unique(lower(tokens), "stable");
if numel(uniqueTokens) ~= 1
    % Preserve an unmistakable conflict token.  The regular fixed-sweep
    % class check will fail closed and the source CSV remains available for
    % diagnosis; no arbitrary row is selected as authority.
    value = "conflicting_runtime_run_classes";
    return;
end
value = uniqueTokens(1);
end

function rows = localConfiguredGridAuditRows(req, campaignT, opt)
rows = repmat(localEmptyAuditRow(), 0, 1);
grid = double(req.SNRGrid_dB(:));
grid = grid(isfinite(grid));
bad = numel(grid) < 2;
rows(end + 1, 1) = localAuditRow( ...
    "configured_snr_grid_has_at_least_two_points", ...
    "meta/scenario_config_resolved.json", ...
    numel(grid), double(bad), double(numel(grid)), ">=2", ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "configured_snr_grid_missing_or_short"), ...
    "The configured fixed-link SNR grid must contain at least two finite points.");

observed = unique(localNumericColumn(campaignT, ["SNR_dB", "ConfiguredSNR_dB"], NaN(height(campaignT), 1)));
observed = observed(isfinite(observed));
observed = sort(observed(:));
expected = sort(grid(:));
bad = numel(observed) ~= numel(expected) || any(abs(observed - expected) > opt.GridTolerance);
rows(end + 1, 1) = localAuditRow( ...
    "campaign_summary_snr_grid_matches_config", ...
    "air_interface/csv/lls_fixed_link_campaign.csv", ...
    numel(observed), double(bad), double(numel(observed)), string(expected.'), ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "campaign_snr_grid_mismatch"), ...
    "Observed campaign SNR points must match the configured grid within tolerance.");
end

function rows = localCampaignArtifactAuditRows(req, art)
rows = repmat(localEmptyAuditRow(), 0, 1);
expectedPoints = numel(req.SNRGrid_dB);
campaignT = art.Campaign.Table;
taskPlanT = art.TaskPlan.Table;

campaignRows = height(campaignT);
bad = campaignRows ~= expectedPoints;
rows(end + 1, 1) = localAuditRow( ...
    "campaign_summary_has_one_row_per_snr_point", ...
    "air_interface/csv/lls_fixed_link_campaign.csv", ...
    campaignRows, double(bad), double(campaignRows), double(expectedPoints), ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "campaign_summary_point_count_mismatch"), ...
    "lls_fixed_link_campaign.csv must contain exactly one row per configured SNR point.");

taskRows = height(taskPlanT);
bad = taskRows <= 0;
rows(end + 1, 1) = localAuditRow( ...
    "task_plan_nonempty", ...
    "air_interface/csv/fixed_link_campaign_task_plan.csv", ...
    taskRows, double(bad), double(taskRows), ">=1", ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "task_plan_missing_or_empty"), ...
    "The fixed-link campaign task plan must exist and contain at least one executed plan row.");
end

function rows = localDirectionAuditRows(direction, enabled, req, blerT, berT, trialT)
rows = repmat(localEmptyAuditRow(), 0, 1);
scopePrefix = lower(char(direction));
expectedPoints = numel(req.SNRGrid_dB);

if ~enabled
    rows(end + 1, 1) = localAuditRow( ...
        scopePrefix + "_direction_disabled", ...
        "meta/scenario_config_resolved.json", ...
        0, 0, NaN, "direction disabled", "SKIP", "", ...
        char(direction) + " fixed-link sweep direction is disabled by configuration.");
    return;
end

blerRows = height(blerT);
bad = blerRows ~= expectedPoints;
rows(end + 1, 1) = localAuditRow( ...
    scopePrefix + "_bler_curve_has_one_row_per_snr_point", ...
    "reports/csv/" + scopePrefix + "_fixed_snr_bler_curve.csv", ...
    blerRows, double(bad), double(blerRows), double(expectedPoints), ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, lower(direction) + "_curve_missing_or_empty"), ...
    char(direction) + " BLER curve must contain one row per configured SNR point.");

berRows = height(berT);
bad = berRows ~= expectedPoints;
rows(end + 1, 1) = localAuditRow( ...
    scopePrefix + "_ber_curve_has_one_row_per_snr_point", ...
    "reports/csv/" + scopePrefix + "_fixed_snr_ber_curve.csv", ...
    berRows, double(bad), double(berRows), double(expectedPoints), ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, lower(direction) + "_ber_curve_missing_or_empty"), ...
    char(direction) + " BER curve must contain one row per configured SNR point.");

trialRows = height(trialT);
bad = trialRows <= 0;
rows(end + 1, 1) = localAuditRow( ...
    scopePrefix + "_trial_table_nonempty", ...
    "air_interface/csv/" + scopePrefix + "_fixed_link_campaign_trials.csv", ...
    trialRows, double(bad), double(trialRows), ">=1", ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, lower(direction) + "_trials_missing_or_empty"), ...
    char(direction) + " trial table must contain executed waveform rows.");

rows = [rows; localPerPointTrialAuditRows(direction, blerT, req)]; %#ok<AGROW>
rows = [rows; localProbabilityAuditRows(direction, blerT, "BLER")]; %#ok<AGROW>
rows = [rows; localProbabilityAuditRows(direction, berT, "BER")]; %#ok<AGROW>
rows = [rows; localMeasuredSINRAuditRows(direction, blerT, req)]; %#ok<AGROW>
rows = [rows; localHighSNRSanityAuditRows(direction, blerT, req)]; %#ok<AGROW>
rows = [rows; localEffectiveCodeRateAuditRows(direction, trialT)]; %#ok<AGROW>
end

function rows = localTargetCrossingAuditRows(direction, enabled, req, crossingT, blerT)
% Recompute every YAML-requested crossing from the measured curve.  The
% exported crossing table is evidence, not an oracle: it must agree with
% the independent reducer and an unresolved bracket is a hard failure.
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~enabled || isempty(req.TargetBLERs)
    return;
end

scope = "reports/csv/fixed_snr_sweep_curve_crossing.csv";
direction = upper(strtrim(string(direction)));
mcsValues = unique(localNumericColumn(blerT, ["MCS", "MCSIndex"], ...
    NaN(height(blerT), 1)), "stable");
mcsValues = mcsValues(isfinite(mcsValues));
if isempty(mcsValues)
    rows(end + 1, 1) = localAuditRow( ...
        lower(direction) + "_target_crossing_mcs_identity_available", ...
        scope, height(blerT), 1, NaN, "finite MCS identity", "FAIL", ...
        "target_crossing_mcs_unavailable", ...
        "A target-BLER crossing cannot be qualified without the executed MCS identity.");
    return;
end

crossDirection = upper(strtrim(localTextColumn(crossingT, "Direction", "", height(crossingT))));
crossMCS = localNumericColumn(crossingT, ["MCS", "MCSIndex"], NaN(height(crossingT), 1));
crossTarget = localNumericColumn(crossingT, "TargetBLER", NaN(height(crossingT), 1));
crossStatus = lower(strtrim(localTextColumn(crossingT, ...
    ["TargetCrossingStatus", "CrossingStatus"], "", height(crossingT))));
crossSNR = localNumericColumn(crossingT, ...
    ["TargetCrossingSNR_dB", "CrossingSNR_dB"], NaN(height(crossingT), 1));
exportStatus = lower(strtrim(localTextColumn(crossingT, "Status", "", height(crossingT))));
exportFailure = lower(strtrim(localTextColumn(crossingT, "FailureCode", "", height(crossingT))));

curveMCS = localNumericColumn(blerT, ["MCS", "MCSIndex"], NaN(height(blerT), 1));
curveSNR = localNumericColumn(blerT, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(blerT), 1));
curveBLER = localNumericColumn(blerT, "BLER", NaN(height(blerT), 1));
qualifiedStates = ["crossing_observed_exact_point", "crossing_observed_interpolated"];

for mcs = reshape(double(mcsValues), 1, [])
    curveMask = abs(curveMCS - mcs) <= 1e-9;
    for target = reshape(double(req.TargetBLERs), 1, [])
        [expectedStatus, expectedSNR] = sixgr.validation.qualifyObservedBLERCrossing( ...
            curveSNR(curveMask), curveBLER(curveMask), target, ...
            double(req.MaxTargetCrossingBracket_dB));
        match = crossDirection == direction & abs(crossMCS - mcs) <= 1e-9 & ...
            abs(crossTarget - target) <= max(1e-12, eps(target) * 8);
        nMatch = nnz(match);
        observedSNR = NaN;
        failureCode = "";
        details = "Measured crossing is uniquely exported and independently qualified.";
        bad = false;
        if nMatch ~= 1
            bad = true;
            failureCode = localTernary(nMatch == 0, ...
                "target_crossing_row_missing", "target_crossing_row_duplicate");
            details = "Expected exactly one crossing row for the YAML direction/MCS/target identity.";
        else
            idx = find(match, 1, "first");
            observedSNR = crossSNR(idx);
            if ~ismember(expectedStatus, qualifiedStates)
                bad = true;
                failureCode = expectedStatus;
                details = "The measured BLER curve does not resolve this configured target inside the maximum SNR bracket.";
            elseif crossStatus(idx) ~= expectedStatus
                bad = true;
                failureCode = "target_crossing_classification_mismatch";
                details = "Exported crossing classification disagrees with the independently reduced measured curve.";
            elseif ~isfinite(observedSNR) || abs(observedSNR - expectedSNR) > 1e-9
                bad = true;
                failureCode = "target_crossing_snr_missing_or_mismatch";
                details = "Exported target-crossing SNR is missing or differs from the independently reduced value.";
            elseif exportStatus(idx) ~= "qualified" || strlength(exportFailure(idx)) > 0
                bad = true;
                failureCode = "target_crossing_export_not_qualified";
                details = "The crossing row must be explicitly qualified with an empty failure code.";
            end
        end
        checkName = lower(direction) + "_target_crossing_mcs_" + string(mcs) + ...
            "_bler_" + replace(string(target), ".", "p");
        rows(end + 1, 1) = localAuditRow( ... %#ok<AGROW>
            checkName, scope, nMatch, double(bad), observedSNR, ...
            "resolved crossing; max bracket " + string(req.MaxTargetCrossingBracket_dB) + " dB", ...
            localStatusFromFailures(double(bad)), failureCode, details);
    end
end
end

function rows = localPerPointTrialAuditRows(direction, curveT, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(istable(curveT) && ~isempty(curveT))
    return;
end

trialCount = localNumericColumn(curveT, "TrialCount", NaN(height(curveT), 1));
incomplete = localLogicalColumn(curveT, "Incomplete", false(height(curveT), 1));
stopReason = upper(strtrim(localTextColumn(curveT, "StopReason", "", height(curveT))));
ciWidth = localNumericColumn(curveT, "BLER_CI_Width", NaN(height(curveT), 1));
snr = localNumericColumn(curveT, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(curveT), 1));

bad = isfinite(trialCount) & trialCount < double(req.MinTrials) & ~incomplete;
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_complete_points_meet_min_trials", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
    nnz(isfinite(trialCount)), nnz(bad), localMinOrNaN(trialCount), double(req.MinTrials), ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), "trial_count_below_minimum"), ...
    char(direction) + " complete curve points must meet the configured min_trials threshold.");

ciTargetMiss = stopReason == "MAX_TRIALS_REACHED_INCOMPLETE" & ...
    ((isfinite(req.CIWidthTarget) & (~isfinite(ciWidth) | ciWidth > req.CIWidthTarget + 1e-12)));
% Rows that hit the cap and still missed the CI target remain audit failures.
bad = ciTargetMiss;
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_ci_target_met_before_or_at_max_trials", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
    nnz(stopReason == "MAX_TRIALS_REACHED_INCOMPLETE"), nnz(bad), localMaxOrNaN(ciWidth(ciTargetMiss)), ...
    localTernary(isfinite(req.CIWidthTarget), string(req.CIWidthTarget), "finite CI width"), ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), "ci_target_missed_at_max_trials"), ...
    char(direction) + " points that stop at max_trials must not miss the BLER CI target.");

bad = ciTargetMiss & ~incomplete;
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_max_trials_ci_miss_marked_incomplete", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
    nnz(ciTargetMiss), nnz(bad), localMaxOrNaN(snr(ciTargetMiss)), "Incomplete=true", ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), "ci_target_missed_but_not_marked_incomplete"), ...
    char(direction) + " points that miss the CI target at max_trials must be flagged incomplete.");
end

function rows = localProbabilityAuditRows(direction, curveT, metricName)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(istable(curveT) && ~isempty(curveT))
    return;
end

values = localNumericColumn(curveT, metricName, NaN(height(curveT), 1));
low = localNumericColumn(curveT, metricName + "_CI_Low", NaN(height(curveT), 1));
high = localNumericColumn(curveT, metricName + "_CI_High", NaN(height(curveT), 1));
width = localNumericColumn(curveT, metricName + "_CI_Width", NaN(height(curveT), 1));
status = lower(strtrim(localTextColumn(curveT, "Status", "", height(curveT))));
failure = lower(strtrim(localTextColumn(curveT, "FailureCode", "", height(curveT))));

bad = ~isfinite(values) | values < -1e-12 | values > 1 + 1e-12;
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_" + lower(metricName) + "_within_unit_interval", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_" + lower(metricName) + "_curve.csv", ...
    numel(values), nnz(bad), localMaxOrNaN(values), "[0,1]", ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), lower(metricName) + "_out_of_range"), ...
    char(direction) + " " + metricName + " values must remain within [0,1].");

ciMask = isfinite(values) | isfinite(low) | isfinite(high);
allowedUnavailable = contains(status, "unavailable") | contains(failure, "unavailable");
bad = ciMask & (~isfinite(low) | ~isfinite(high) | low > values + 1e-9 | high < values - 1e-9 | low > high + 1e-9);
bad = bad | ((~isfinite(width) | width < 0) & ciMask & ~allowedUnavailable);
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_" + lower(metricName) + "_confidence_intervals_valid", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_" + lower(metricName) + "_curve.csv", ...
    nnz(ciMask), nnz(bad), localMaxOrNaN(width), "CI low <= metric <= CI high", ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), lower(metricName) + "_ci_invalid"), ...
    char(direction) + " " + metricName + " confidence intervals must be finite, ordered, and contain the point estimate unless explicitly unavailable.");
end

function rows = localMeasuredSINRAuditRows(direction, curveT, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(istable(curveT) && ~isempty(curveT))
    return;
end

measured = localNumericColumn(curveT, "MeanMeasuredSINR_dB", NaN(height(curveT), 1));
configured = localNumericColumn(curveT, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(curveT), 1));
finiteMask = isfinite(measured) & isfinite(configured);

if ~any(finiteMask)
    status = localTernary(req.MeasuredSINRRequired, "FAIL", "WARN");
    rows(end + 1, 1) = localAuditRow( ...
        lower(char(direction)) + "_measured_sinr_available", ...
        "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
        0, 1, NaN, "finite MeanMeasuredSINR_dB", status, "measured_sinr_unavailable", ...
        char(direction) + " curve rows did not expose finite measured SINR values.");
    return;
end

delta = abs(measured(finiteMask) - configured(finiteMask));
bad = delta > double(req.MaxSINRMinusSNR_dB) + 1e-12;
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_measured_sinr_matches_configured_snr", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
    nnz(finiteMask), nnz(bad), localMaxOrNaN(delta), double(req.MaxSINRMinusSNR_dB), ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), "measured_sinr_snr_delta_exceeded"), ...
    char(direction) + " measured SINR must stay within the configured delta threshold from configured SNR.");
end

function rows = localHighSNRSanityAuditRows(direction, curveT, req)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(istable(curveT) && height(curveT) >= 2)
    return;
end

[snr, order] = sort(localNumericColumn(curveT, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(curveT), 1)));
bler = localNumericColumn(curveT, "BLER", NaN(height(curveT), 1));
low = localNumericColumn(curveT, "BLER_CI_Low", NaN(height(curveT), 1));
high = localNumericColumn(curveT, "BLER_CI_High", NaN(height(curveT), 1));
incomplete = localLogicalColumn(curveT,"Incomplete", ...
    false(height(curveT),1));
bler = bler(order);
low = low(order);
high = high(order);
incomplete = incomplete(order);
finiteMask = isfinite(snr) & isfinite(bler);
snr = snr(finiteMask);
bler = bler(finiteMask);
low = low(finiteMask);
high = high(finiteMask);
incomplete = incomplete(finiteMask);
if numel(bler) < 2
    return;
end
trendPass = bler(end) <= bler(1) + 1e-12;
if isfinite(high(1)) && isfinite(low(end))
    trendPass = trendPass || low(end) <= high(1);
end
objectivePass = true;
if isfinite(req.TargetBLER)
    objectivePass = isfinite(high(end)) && high(end) <= req.TargetBLER;
end
pointStatePass = ~incomplete(end);
bad = ~(trendPass && objectivePass && pointStatePass);
rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_high_snr_objective_with_uncertainty", ...
    "reports/csv/" + lower(char(direction)) + "_fixed_snr_bler_curve.csv", ...
    numel(bler), double(bad), high(end), ...
    localTernary(isfinite(req.TargetBLER),string(req.TargetBLER), ...
    "nondegradation_with_uncertainty"), ...
    localStatusFromFailures(double(bad)), ...
    localFailureToken(bad, "high_snr_objective_or_uncertainty_failed"), ...
    char(direction) + " highest-SNR point must be complete/censored, " + ...
    "nondegraded within uncertainty, and meet the objective upper bound.");
end

function rows = localEffectiveCodeRateAuditRows(direction, trialT)
rows = repmat(localEmptyAuditRow(), 0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    return;
end

tbs = localNumericColumn(trialT, "TBSizeBits", NaN(height(trialT), 1));
rateMatchedBits = localNumericColumn(trialT, "RateMatchedBits", NaN(height(trialT), 1));
isRetx = localLogicalColumn(trialT, "IsRetransmission", false(height(trialT), 1));
mask = ~isRetx & isfinite(tbs) & isfinite(rateMatchedBits) & rateMatchedBits > 0;
codeRate = NaN(height(trialT), 1);
codeRate(mask) = tbs(mask) ./ rateMatchedBits(mask);
bad = mask & (~isfinite(codeRate) | codeRate > 1 + 1e-9 | codeRate <= 0);

rows(end + 1, 1) = localAuditRow( ...
    lower(char(direction)) + "_new_tb_effective_code_rate_feasible", ...
    "air_interface/csv/" + lower(char(direction)) + "_fixed_link_campaign_trials.csv", ...
    nnz(mask), nnz(bad), localMaxOrNaN(codeRate(mask)), "(0,1]", ...
    localStatusFromFailures(nnz(bad)), ...
    localFailureToken(any(bad), "effective_code_rate_invalid"), ...
    char(direction) + " new transport blocks must have finite effective code rate within (0,1].");
end

function rows = localProxyEvidenceAuditRows(art)
rows = repmat(localEmptyAuditRow(), 0, 1);
artifacts = {
    "air_interface/csv/lls_fixed_link_campaign.csv", art.Campaign.Table
    "air_interface/csv/dl_fixed_link_campaign_trials.csv", art.DLTrials.Table
    "air_interface/csv/ul_fixed_link_campaign_trials.csv", art.ULTrials.Table
    "reports/csv/dl_fixed_snr_bler_curve.csv", art.DLBLER.Table
    "reports/csv/ul_fixed_snr_bler_curve.csv", art.ULBLER.Table
    "reports/csv/dl_fixed_snr_ber_curve.csv", art.DLBER.Table
    "reports/csv/ul_fixed_snr_ber_curve.csv", art.ULBER.Table
    "reports/csv/fixed_snr_sweep_curve_crossing.csv", art.TargetCrossings.Table
    "reports/csv/contract_plot_lineage.csv", art.PlotLineage.Table
    };
for i = 1:size(artifacts, 1)
    relPath = string(artifacts{i, 1});
    T = artifacts{i, 2};
    [rowsChecked, badRows] = localForbiddenEvidenceRows(T);
    rows(end + 1, 1) = localAuditRow( ...
        "no_proxy_or_placeholder_markers:" + relPath, ...
        relPath, rowsChecked, badRows, double(badRows), "0", ...
        localStatusFromFailures(badRows), ...
        localFailureToken(badRows > 0, "proxy_evidence_marker_detected"), ...
        "Primary fixed-sweep evidence must not contain proxy/oracle/placeholder markers.");
end
end

function rows = localMonotonicityAuditRows(direction, enabled, curveT)
rows = repmat(localEmptyMonotonicityRow(), 0, 1);
if ~enabled || ~(istable(curveT) && height(curveT) >= 2)
    if enabled
        rows(end + 1, 1) = localMonotonicityRow(direction, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "SKIP", "", "insufficient_points");
    end
    return;
end

[snr, order] = sort(localNumericColumn(curveT, ["ConfiguredSNR_dB", "SNR_dB"], NaN(height(curveT), 1)));
bler = localNumericColumn(curveT, "BLER", NaN(height(curveT), 1));
low = localNumericColumn(curveT, "BLER_CI_Low", NaN(height(curveT), 1));
high = localNumericColumn(curveT, "BLER_CI_High", NaN(height(curveT), 1));
bler = bler(order);
low = low(order);
high = high(order);
finiteMask = isfinite(snr) & isfinite(bler);
snr = snr(finiteMask);
bler = bler(finiteMask);
low = low(finiteMask);
high = high(finiteMask);
for i = 2:numel(snr)
    delta = bler(i) - bler(i - 1);
    overlap = isfinite(low(i - 1)) && isfinite(high(i - 1)) && isfinite(low(i)) && isfinite(high(i)) && ...
        ~(high(i - 1) < low(i) || high(i) < low(i - 1));
    strong = delta > 0.15 && ~overlap;
    status = "PASS";
    failureCode = "";
    details = "bler_nonincreasing_or_ci_overlap";
    if strong
        status = "FAIL";
        failureCode = "strong_bler_non_monotonicity";
        details = "bler_increase_gt_0p15_without_ci_overlap";
    elseif delta > 0
        status = "WARN";
        failureCode = "minor_bler_increase";
        details = "local_bler_increase_allowed_due_to_small_delta_or_ci_overlap";
    end
    rows(end + 1, 1) = localMonotonicityRow(direction, snr(i - 1), snr(i), bler(i - 1), bler(i), ...
        low(i - 1), high(i - 1), low(i), high(i), overlap, status, failureCode, details); %#ok<AGROW>
end
end

function T = localMonotonicityTable(rows)
if isempty(rows)
    T = struct2table(repmat(localEmptyMonotonicityRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end
end

function rows = localMonotonicitySummaryAuditRows(monotonicityRows)
rows = repmat(localEmptyAuditRow(), 0, 1);
if isempty(monotonicityRows)
    return;
end
T = localMonotonicityTable(monotonicityRows);
directions = unique(string(T.Direction), "stable");
directions = directions(strlength(directions) > 0);
for direction = reshape(directions, 1, [])
    sub = T(string(T.Direction) == direction, :);
    failCount = nnz(string(sub.Status) == "FAIL");
    warnCount = nnz(string(sub.Status) == "WARN");
    observed = localMaxOrNaN(double(sub.CurrentBLER) - double(sub.PreviousBLER));
    details = "BLER should generally decrease as SNR increases; one small CI-overlapped rise is tolerated.";
    if failCount > 0
        details = details + " Strong non-monotonicity was observed.";
    elseif warnCount > 0
        details = details + " Only minor increases with overlap/tolerance were observed.";
    end
    rows(end + 1, 1) = localAuditRow( ...
        lower(char(direction)) + "_bler_monotonicity", ...
        "reports/csv/fixed_snr_sweep_monotonicity_audit.csv", ...
        height(sub), failCount, observed, "no strong BLER increases", ...
        localStatusFromFailures(failCount), ...
        localFailureToken(failCount > 0, "strong_bler_non_monotonicity"), ...
        details); %#ok<AGROW>
end
end

function row = localEmptyMonotonicityRow()
row = struct( ...
    "Direction", "", ...
    "PreviousSNR_dB", NaN, ...
    "CurrentSNR_dB", NaN, ...
    "PreviousBLER", NaN, ...
    "CurrentBLER", NaN, ...
    "PreviousCI_Low", NaN, ...
    "PreviousCI_High", NaN, ...
    "CurrentCI_Low", NaN, ...
    "CurrentCI_High", NaN, ...
    "CIOverlap", false, ...
    "Status", "", ...
    "FailureCode", "", ...
    "Details", "");
end

function row = localMonotonicityRow(direction, prevSNR, currSNR, prevBLER, currBLER, prevLow, prevHigh, currLow, currHigh, overlap, status, failureCode, details)
row = struct( ...
    "Direction", string(direction), ...
    "PreviousSNR_dB", double(prevSNR), ...
    "CurrentSNR_dB", double(currSNR), ...
    "PreviousBLER", double(prevBLER), ...
    "CurrentBLER", double(currBLER), ...
    "PreviousCI_Low", double(prevLow), ...
    "PreviousCI_High", double(prevHigh), ...
    "CurrentCI_Low", double(currLow), ...
    "CurrentCI_High", double(currHigh), ...
    "CIOverlap", logical(overlap), ...
    "Status", string(status), ...
    "FailureCode", string(failureCode), ...
    "Details", string(details));
end

function row = localEmptyAuditRow()
row = struct( ...
    "CheckName", "", ...
    "Scope", "", ...
    "RowsChecked", NaN, ...
    "RowsFailed", NaN, ...
    "ObservedValue", NaN, ...
    "ExpectedValue", "", ...
    "Status", "", ...
    "FailureCode", "", ...
    "Details", "");
end

function row = localAuditRow(checkName, scope, rowsChecked, rowsFailed, observedValue, expectedValue, status, failureCode, details)
row = struct( ...
    "CheckName", string(checkName), ...
    "Scope", string(scope), ...
    "RowsChecked", double(rowsChecked), ...
    "RowsFailed", double(rowsFailed), ...
    "ObservedValue", double(observedValue), ...
    "ExpectedValue", localScalarText(expectedValue), ...
    "Status", string(status), ...
    "FailureCode", string(failureCode), ...
    "Details", string(details));
end

function T = localRowsToTable(rows)
if isempty(rows)
    T = struct2table(repmat(localEmptyAuditRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end
end

function tf = localDirectionEnabled(req, direction)
mode = upper(strtrim(string(req.Direction)));
direction = upper(strtrim(string(direction)));
tf = any(mode == ["BOTH", direction]);
end

function T = localDirectionCurveTable(art, direction, metric)
direction = upper(string(direction));
metric = upper(string(metric));
switch direction + "_" + metric
    case "DL_BLER"
        T = art.DLBLER.Table;
    case "UL_BLER"
        T = art.ULBLER.Table;
    case "DL_BER"
        T = art.DLBER.Table;
    case "UL_BER"
        T = art.ULBER.Table;
    otherwise
        T = table();
end
end

function T = localDirectionTrialTable(art, direction)
if upper(string(direction)) == "UL"
    T = art.ULTrials.Table;
else
    T = art.DLTrials.Table;
end
end

function inventory = localArtifactInventory(art, rootRunFolder)
names = fieldnames(art);
inventory = struct();
for i = 1:numel(names)
    entry = art.(names{i});
    row = struct();
    row.Path = localRelativePath(entry.Path, rootRunFolder);
    row.Present = logical(entry.Present);
    row.Readable = logical(entry.Readable);
    row.NonEmpty = logical(entry.NonEmpty);
    row.Reason = string(entry.Reason);
    if isfield(entry, "Table") && istable(entry.Table)
        row.RowCount = double(height(entry.Table));
    else
        row.RowCount = NaN;
    end
    inventory.(names{i}) = row;
end
end

function [rowsChecked, badRows] = localForbiddenEvidenceRows(T)
rowsChecked = 0;
badRows = 0;
if ~(istable(T) && ~isempty(T))
    return;
end
nameMask = false(1, numel(T.Properties.VariableNames));
for token = ["source", "status", "failure", "reason", "mode", "role", "authority", "notes", "evidence"]
    nameMask = nameMask | contains(lower(string(T.Properties.VariableNames)), token);
end
names = string(T.Properties.VariableNames);
names = names(nameMask);
if isempty(names)
    return;
end
rowsChecked = height(T);
badMask = false(height(T), 1);
for i = 1:height(T)
    tokens = strings(0, 1);
    for name = reshape(names, 1, [])
        value = T.(char(name))(i);
        tokens(end + 1, 1) = lower(strtrim(string(value))); %#ok<AGROW>
    end
    joined = strjoin(tokens, " | ");
    if any(contains(joined, ["proxy", "oracle", "configured_snr_as_result", "placeholder", "fallback_success", "synthetic_perfect", "perfect_channel_estimate"]))
        if ~(contains(joined, "reference-only") || contains(joined, "reference_only") || contains(joined, "non_primary"))
            badMask(i) = true;
        end
    end
end
badRows = nnz(badMask);
end

function entry = localArtifactLookup(art, relPath)
switch string(relPath)
    case "meta/scenario_config_resolved.json"
        entry = art.ResolvedConfig;
    case "reports/csv/run_classification.csv"
        entry = art.RunClassification;
    case "air_interface/csv/lls_fixed_link_campaign.csv"
        entry = art.Campaign;
    case "air_interface/csv/fixed_link_campaign_task_plan.csv"
        entry = art.TaskPlan;
    case "air_interface/csv/dl_fixed_link_campaign_trials.csv"
        entry = art.DLTrials;
    case "air_interface/csv/ul_fixed_link_campaign_trials.csv"
        entry = art.ULTrials;
    case "reports/csv/dl_fixed_snr_bler_curve.csv"
        entry = art.DLBLER;
    case "reports/csv/ul_fixed_snr_bler_curve.csv"
        entry = art.ULBLER;
    case "reports/csv/dl_fixed_snr_ber_curve.csv"
        entry = art.DLBER;
    case "reports/csv/ul_fixed_snr_ber_curve.csv"
        entry = art.ULBER;
    case "reports/csv/fixed_snr_sweep_curve_crossing.csv"
        entry = art.TargetCrossings;
    case "reports/csv/contract_plot_lineage.csv"
        entry = art.PlotLineage;
    otherwise
        entry = struct("Path", string(relPath), "Present", false, "Readable", false, "NonEmpty", false, "Reason", "unknown_artifact");
end
end

function out = localReadOptionalJSON(pathValue)
out = struct("Path", string(pathValue), "Present", false, "Readable", false, "NonEmpty", false, ...
    "Reason", "", "Data", struct(), "Table", table());
out.Present = exist(pathValue, "file") == 2;
if ~out.Present
    out.Reason = "artifact_missing";
    return;
end
try
    out.Data = sixgr.util.jsonRead(pathValue);
    out.Readable = true;
    out.NonEmpty = ~isempty(fieldnames(out.Data));
    if ~out.NonEmpty
        out.Reason = "artifact_empty";
    end
catch ME
    out.Reason = string(ME.identifier) + ":" + string(ME.message);
end
end

function out = localReadOptionalTable(pathValue)
out = struct("Path", string(pathValue), "Present", false, "Readable", false, "NonEmpty", false, ...
    "Reason", "", "Table", table());
out.Present = exist(pathValue, "file") == 2;
if ~out.Present
    out.Reason = "artifact_missing";
    return;
end
try
    out.Table = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
    out.Readable = true;
    out.NonEmpty = height(out.Table) > 0;
    if ~out.NonEmpty
        out.Reason = "artifact_empty";
    end
catch ME
    out.Reason = string(ME.identifier) + ":" + string(ME.message);
end
end

function value = localGetValue(S, pathValue, defaultValue)
if nargin < 3
    defaultValue = [];
end
try
    value = sixgr.util.structGet(S, pathValue, defaultValue);
catch
    value = defaultValue;
end
end

function value = localGetDouble(S, pathValue, defaultValue)
raw = localGetValue(S, pathValue, defaultValue);
if isnumeric(raw) && isscalar(raw)
    value = double(raw);
else
    value = str2double(string(raw));
    if ~isfinite(value)
        value = defaultValue;
    end
end
end

function value = localGetLogical(S, pathValue, defaultValue)
raw = localGetValue(S, pathValue, defaultValue);
if islogical(raw)
    value = logical(raw);
elseif isnumeric(raw)
    value = raw ~= 0;
else
    token = lower(strtrim(string(raw)));
    value = any(token == ["true", "1", "yes", "on"]);
end
end

function value = localGetText(S, pathValue, defaultValue)
raw = localGetValue(S, pathValue, defaultValue);
value = string(raw);
if isempty(value)
    value = string(defaultValue);
elseif all(ismissing(value) | strlength(strtrim(value)) == 0)
    value = string(defaultValue);
else
    value = value(1);
end
end

function value = localFirstTextValue(values)
values = string(values(:));
mask = ~ismissing(values) & strlength(strtrim(values)) > 0;
if any(mask)
    value = values(find(mask, 1, "first"));
else
    value = "";
end
end

function value = localFirstNumericVector(candidates)
value = [];
for i = 1:numel(candidates)
    raw = candidates{i};
    if isempty(raw)
        continue;
    end
    if isnumeric(raw)
        nums = double(raw(:));
    else
        nums = str2double(string(raw(:)));
    end
    nums = nums(isfinite(nums));
    if ~isempty(nums)
        value = nums;
        return;
    end
end
end

function value = localFirstFinite(values)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = NaN;
else
    value = values(idx);
end
end

function value = localFirstLogical(values)
values = logical(values(:));
if isempty(values)
    value = false;
else
    value = values(1);
end
end

function values = localNumericColumn(T, candidates, fallback)
if ischar(candidates) || (isstring(candidates) && isscalar(candidates))
    candidates = string(candidates);
else
    candidates = string(candidates(:));
end
if istable(T)
    n = height(T);
else
    n = numel(fallback);
end
values = localExpandFallback(fallback, n);
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(candidates, 1, [])
    idx = find(strcmpi(string(T.Properties.VariableNames), name), 1, "first");
    if isempty(idx)
        continue;
    end
    raw = T.(T.Properties.VariableNames{idx});
    if isnumeric(raw) || islogical(raw)
        values = double(raw);
    else
        values = str2double(string(raw));
    end
    values = reshape(values, n, 1);
    return;
end
end

function values = localLogicalColumn(T, candidates, fallback)
if ischar(candidates) || (isstring(candidates) && isscalar(candidates))
    candidates = string(candidates);
else
    candidates = string(candidates(:));
end
if istable(T)
    n = height(T);
else
    n = numel(fallback);
end
values = logical(localExpandFallback(fallback, n));
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(candidates, 1, [])
    idx = find(strcmpi(string(T.Properties.VariableNames), name), 1, "first");
    if isempty(idx)
        continue;
    end
    raw = T.(T.Properties.VariableNames{idx});
    if islogical(raw)
        values = logical(raw);
    elseif isnumeric(raw)
        values = raw ~= 0;
    else
        token = lower(strtrim(string(raw)));
        values = any(token == ["true", "1", "yes", "on", "pass", "passed"], 2);
    end
    values = reshape(values, n, 1);
    return;
end
end

function values = localTextColumn(T, candidates, fallback, n)
if nargin < 4
    if istable(T)
        n = height(T);
    else
        n = 0;
    end
end
if ischar(candidates) || (isstring(candidates) && isscalar(candidates))
    candidates = string(candidates);
else
    candidates = string(candidates(:));
end
values = repmat(string(fallback), n, 1);
if ~(istable(T) && n > 0)
    return;
end
for name = reshape(candidates, 1, [])
    idx = find(strcmpi(string(T.Properties.VariableNames), name), 1, "first");
    if isempty(idx)
        continue;
    end
    values = string(T.(T.Properties.VariableNames{idx}));
    values = reshape(values, n, 1);
    return;
end
end

function values = localExpandFallback(fallback, n)
if isscalar(fallback)
    values = repmat(double(fallback), n, 1);
else
    values = double(fallback(:));
    if numel(values) ~= n
        values = repmat(values(1), n, 1);
    end
end
end

function value = localMinOrNaN(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = min(values);
end
end

function value = localMaxOrNaN(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function status = localStatusFromFailures(failureCount)
if failureCount > 0
    status = "FAIL";
else
    status = "PASS";
end
end

function token = localFailureToken(condition, value)
if condition
    token = string(value);
else
    token = "";
end
end

function out = localTernary(condition, a, b)
if condition
    out = a;
else
    out = b;
end
end

function value = localScalarText(raw)
if isstring(raw)
    values = raw(:);
elseif ischar(raw)
    values = string(raw);
elseif isnumeric(raw) || islogical(raw)
    values = string(raw(:));
else
    values = string(raw);
    values = values(:);
end
values = values(~ismissing(values));
if isempty(values)
    value = "";
elseif numel(values) == 1
    value = values(1);
else
    value = "[" + strjoin(values.', ", ") + "]";
end
end

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
parent = fileparts(rootRunFolder);
[~, leaf] = fileparts(rootRunFolder);
leaf = lower(string(leaf));
if any(leaf == ["air_interface", "reports", "control", "packet_flow", "system", "harq"])
    rootRunFolder = parent;
end
end

function rel = localRelativePath(pathValue, rootRunFolder)
pathValue = replace(string(pathValue), "\", "/");
rootRunFolder = replace(string(rootRunFolder), "\", "/");
if startsWith(pathValue, rootRunFolder + "/")
    rel = extractAfter(pathValue, strlength(rootRunFolder) + 1);
else
    rel = pathValue;
end
end
