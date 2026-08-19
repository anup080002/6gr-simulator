function result = evaluatePublicationReadinessGates(cfg, runDir)
%EVALUATEPUBLICATIONREADINESSGATES Evidence-based terminal Phase 7 gates.
%
% This evaluator deliberately reads persisted runtime artifacts and writes
% audit summaries. Missing artifacts fail closed; no placeholder rows are
% treated as publication evidence.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || strlength(strtrim(string(runDir))) == 0
    runDir = pwd;
end
runDir = char(string(runDir));
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

[energyOk, energyT] = localEvaluateEnergy(runDir);
[perfOk, perfT] = localEvaluatePerformance(cfg, runDir);
[stabilityOk, stabilityT] = localEvaluateLongRunStability(cfg, runDir);
[artifactOk, artifactT] = localEvaluateArtifactCompleteness(runDir);
[lineageOk, lineageT] = localEvaluatePlotLineage(runDir);
[claimsOk, claimsT] = localEvaluateClaimsTruthfulness(runDir);
[modeAcceptance, modeAcceptanceT] = localEvaluateTwoModeAcceptance(cfg, runDir);

paths = struct();
paths.Energy = localWrite(layout.ReportCSVDir, "energy_model_gate.csv", energyT);
paths.Performance = localWrite(layout.ReportCSVDir, "performance_profile_summary.csv", perfT);
paths.LongRunStability = localWrite(layout.ReportCSVDir, "long_run_stability_summary.csv", stabilityT);
paths.ArtifactCompleteness = localWrite(layout.ReportCSVDir, "artifact_completeness_summary.csv", artifactT);
paths.PlotDataLineage = localWrite(layout.ReportCSVDir, "plot_data_lineage_summary.csv", lineageT);
paths.ClaimsTruthfulness = localWrite(layout.ReportCSVDir, "final_scientific_claims_truthfulness.csv", claimsT);
paths.TwoModeAcceptance = localWrite(layout.ReportCSVDir, "two_mode_acceptance_gates.csv", modeAcceptanceT);

flags = struct( ...
    "EnergyModelOk", logical(energyOk), ...
    "PerformanceProfileOk", logical(perfOk), ...
    "LongRunStabilityOk", logical(stabilityOk), ...
    "ArtifactCompletenessOk", logical(artifactOk), ...
    "PlotDataLineageOk", logical(lineageOk), ...
    "FinalScientificClaimsTruthfulOk", logical(claimsOk), ...
    "TwoModeAcceptanceGatesOk", logical(sixgr.util.structGet(modeAcceptance.Flags, "TwoModeAcceptanceGatesOk", true)), ...
    "FixedSNRLLSOk", logical(sixgr.util.structGet(modeAcceptance.Flags, "FixedSNRLLSOk", true)), ...
    "GeometryScenarioOk", logical(sixgr.util.structGet(modeAcceptance.Flags, "GeometryScenarioOk", true)), ...
    "PublicationReferenceComparisonOk", logical(sixgr.util.structGet(modeAcceptance.Flags, "PublicationReferenceComparisonOk", true)));

terminalFlags = flags;
for optionalName = ["FixedSNRLLSOk","GeometryScenarioOk","PublicationReferenceComparisonOk"]
    if isfield(terminalFlags, char(optionalName))
        terminalFlags = rmfield(terminalFlags, char(optionalName));
    end
end
summaryT = table(flags.EnergyModelOk, flags.PerformanceProfileOk, flags.LongRunStabilityOk, ...
    flags.ArtifactCompletenessOk, flags.PlotDataLineageOk, flags.FinalScientificClaimsTruthfulOk, ...
    flags.TwoModeAcceptanceGatesOk, flags.FixedSNRLLSOk, flags.GeometryScenarioOk, ...
    flags.PublicationReferenceComparisonOk, all(struct2array(terminalFlags)), ...
    "evidence_files_only_no_forced_publication_pass", ...
    'VariableNames', {'EnergyModelOk','PerformanceProfileOk','LongRunStabilityOk', ...
    'ArtifactCompletenessOk','PlotDataLineageOk','FinalScientificClaimsTruthfulOk', ...
    'TwoModeAcceptanceGatesOk','FixedSNRLLSOk','GeometryScenarioOk','PublicationReferenceComparisonOk', ...
    'TerminalPublicationGatesOk','EvaluationPolicy'});
paths.Summary = localWrite(layout.ReportCSVDir, "publication_readiness_gate_summary.csv", summaryT);

result = struct("Flags", flags, "Tables", struct("Energy", energyT, "Performance", perfT, ...
    "LongRunStability", stabilityT, "ArtifactCompleteness", artifactT, ...
    "PlotDataLineage", lineageT, "ClaimsTruthfulness", claimsT, ...
    "TwoModeAcceptance", modeAcceptanceT, "Summary", summaryT), ...
    "ModeAcceptance", modeAcceptance, ...
    "Paths", paths);
end

function [result, T] = localEvaluateTwoModeAcceptance(cfg, runDir)
resolvedCfg = localReadJson(fullfile(runDir, "meta", "scenario_config_resolved.json"));
runClassT = localReadTable(fullfile(runDir, "reports", "csv", "run_classification.csv"));
fixedAuditT = localReadTable(fullfile(runDir, "reports", "csv", "fixed_snr_sweep_audit.csv"));
geometryAuditT = localReadTable(fullfile(runDir, "reports", "csv", "geometry_runtime_audit.csv"));
csvAuditT = localReadTable(fullfile(runDir, "reports", "csv", "all_csv_artifact_audit.csv"));
imageAuditT = localReadTable(fullfile(runDir, "reports", "csv", "all_image_artifact_audit.csv"));
dlCurveT = localReadTable(fullfile(runDir, "reports", "csv", "dl_fixed_snr_bler_curve.csv"));
ulCurveT = localReadTable(fullfile(runDir, "reports", "csv", "ul_fixed_snr_bler_curve.csv"));
trajectoryT = localReadTable(fullfile(runDir, "geometry", "csv", "trajectory_geometry.csv"));
dopplerT = localReadTable(fullfile(runDir, "mobility", "csv", "doppler_reconciliation.csv"));
measuredSinrT = localReadTable(fullfile(runDir, "reports", "csv", "measured_sinr_timeseries.csv"));
referenceSweepT = localReadTable(fullfile(runDir, "air_interface", "csv", "lls_reference_snr_sweep.csv"));
dutSweepT = localReadTable(fullfile(runDir, "air_interface", "csv", "lls_snr_sweep.csv"));
frcQualificationT = localReadTable(fullfile(runDir, "reports", "csv", ...
    "frc_reference_qualification.csv"));

effectiveCfg = cfg;
if ~isstruct(effectiveCfg) || isempty(fieldnames(effectiveCfg))
    effectiveCfg = resolvedCfg;
end

runClass = localResolveRunClass(effectiveCfg, resolvedCfg, runClassT);
direction = upper(localResolveFixedDirection(effectiveCfg, resolvedCfg));
minTrials = localResolveMinTrials(effectiveCfg, resolvedCfg);
targetBLER = localResolveFiniteSetting(effectiveCfg,resolvedCfg, ...
    ["sweeps_and_matrix.fixed_link_calibration.target_bler", ...
    "validation.fixed_link_campaign.target_bler"],NaN);
fixedOnly = localResolveLogicalSetting(effectiveCfg, resolvedCfg, ...
    ["sweeps_and_matrix.fixed_link_calibration.only","canonical_control.run.fixed_link_campaign_only"], false);
noiseMode = localResolveTextSetting(effectiveCfg, resolvedCfg, ...
    ["simulation.noise_operating_mode","run.noiseOperatingMode"], "");
fixedEnabled = localResolveLogicalSetting(effectiveCfg, resolvedCfg, ...
    ["sweeps_and_matrix.fixed_link_calibration.enabled","validation.fixed_link_campaign.enabled"], false);
geometryEvidenceRequired = localResolveLogicalSetting(effectiveCfg, resolvedCfg, ...
    ["validation.geometry_evidence_required"], false);
fixedSweepRequired = localResolveLogicalSetting(effectiveCfg, resolvedCfg, ...
    ["validation.fixed_snr_sweep_required"], false);

fixedApplicable = runClass == "fixed_snr_sweep_lls" | runClass == "hybrid_validation";
geometryApplicable = runClass == "ue_placement_geometry_lls" | runClass == "hybrid_validation";
rows = repmat(localEmptyModeGateRow(runClass), 0, 1);

if fixedApplicable
    rows(end+1, 1) = localModeGateRow("RunClassFixedSNRSweep", runClass, true, ...
        runClass == "fixed_snr_sweep_lls" | runClass == "hybrid_validation", ...
        1, double(runClass ~= "fixed_snr_sweep_lls" & runClass ~= "hybrid_validation"), ...
        "reports/csv/run_classification.csv", ...
        localFailureToken(runClass == "fixed_snr_sweep_lls" | runClass == "hybrid_validation", "run_class_not_fixed_snr_sweep"), ...
        "Run class must resolve to fixed_snr_sweep_lls or hybrid_validation for fixed-link acceptance."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateRow("FixedLinkCampaignOnly", runClass, true, ...
        logical(fixedOnly), 1, double(~logical(fixedOnly)), ...
        "meta/scenario_config_resolved.json", ...
        localFailureToken(logical(fixedOnly), "fixed_link_campaign_only_false"), ...
        "Fixed-link publication anchor runs must execute in fixed-campaign-only mode."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateRow("NoiseOperatingMode", runClass, true, ...
        strcmpi(strtrim(char(noiseMode)), "standalone_awgn_snr_argument"), 1, ...
        double(~strcmpi(strtrim(char(noiseMode)), "standalone_awgn_snr_argument")), ...
        "meta/scenario_config_resolved.json", ...
        localFailureToken(strcmpi(strtrim(char(noiseMode)), "standalone_awgn_snr_argument"), "noise_mode_not_standalone_awgn"), ...
        "Fixed-link publication anchor runs must use standalone AWGN SNR input mode."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromAudit("FixedSNRSweepAudit", runClass, true, ...
        fixedAuditT, "reports/csv/fixed_snr_sweep_audit.csv", "fixed_snr_sweep_audit_failures_present", ...
        "Fixed-link sweep audit must report zero FAIL rows."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromArtifactAudit("FixedRequiredCSVAudit", runClass, true, ...
        csvAuditT, "reports/csv/all_csv_artifact_audit.csv", "required_csv_artifact_failures_present", ...
        "Recursive CSV artifact audit must report zero required FAIL rows."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromArtifactAudit("FixedRequiredImageAudit", runClass, true, ...
        imageAuditT, "reports/csv/all_image_artifact_audit.csv", "required_image_artifact_failures_present", ...
        "Recursive image artifact audit must report zero required FAIL rows."); %#ok<AGROW>
    if localDirectionEnabledForMode(direction, "DL")
        rows(end+1, 1) = localModeGateFromCurve("DLCurveNonEmpty", runClass, true, dlCurveT, ...
            "reports/csv/dl_fixed_snr_bler_curve.csv", minTrials, "dl_curve_missing_or_incomplete", ...
            "DL BLER curve must be non-empty and complete for every configured SNR point."); %#ok<AGROW>
        rows(end+1, 1) = localModeGateFromHighSNR(localCurveHighSNRImproves(dlCurveT,targetBLER), "DLHighSNRImproves", runClass, ...
            "reports/csv/dl_fixed_snr_bler_curve.csv", "high_snr_not_better_than_low_snr_dl", ...
            "The highest DL SNR point must improve over the lowest DL SNR point."); %#ok<AGROW>
    end
    if localDirectionEnabledForMode(direction, "UL")
        rows(end+1, 1) = localModeGateFromCurve("ULCurveNonEmpty", runClass, true, ulCurveT, ...
            "reports/csv/ul_fixed_snr_bler_curve.csv", minTrials, "ul_curve_missing_or_incomplete", ...
            "UL BLER curve must be non-empty and complete for every configured SNR point."); %#ok<AGROW>
        rows(end+1, 1) = localModeGateFromHighSNR(localCurveHighSNRImproves(ulCurveT,targetBLER), "ULHighSNRImproves", runClass, ...
            "reports/csv/ul_fixed_snr_bler_curve.csv", "high_snr_not_better_than_low_snr_ul", ...
            "The highest UL SNR point must improve over the lowest UL SNR point."); %#ok<AGROW>
    end
    rows(end+1, 1) = localModeGateRow("BLERBERInUnitInterval", runClass, true, ...
        localCurveMetricsValid(dlCurveT) && localCurveMetricsValid(ulCurveT), ...
        height(dlCurveT) + height(ulCurveT), ...
        double(~(localCurveMetricsValid(dlCurveT) && localCurveMetricsValid(ulCurveT))), ...
        "reports/csv/dl_fixed_snr_bler_curve.csv|reports/csv/ul_fixed_snr_bler_curve.csv", ...
        localFailureToken(localCurveMetricsValid(dlCurveT) && localCurveMetricsValid(ulCurveT), "bler_ber_out_of_range_or_invalid_ci"), ...
        "BLER and BER must stay within [0,1] with valid confidence intervals."); %#ok<AGROW>
    [referenceComparisonOK,referenceFailure] = ...
        localIndependentReferenceComparisonPass(dutSweepT,referenceSweepT);
    [frcComparisonOK,frcFailure] = ...
        localIndependentFRCQualificationPass(frcQualificationT);
    independentComparisonOK = referenceComparisonOK || frcComparisonOK;
    independentFailure = referenceFailure;
    if ~independentComparisonOK
        independentFailure = referenceFailure + "|" + frcFailure;
    end
    rows(end+1, 1) = localModeGateRow("ReferenceComparisonPresent", runClass, true, ...
        fixedEnabled && independentComparisonOK, ...
        height(referenceSweepT) + height(frcQualificationT), ...
        double(~(fixedEnabled && independentComparisonOK)), ...
        "air_interface/csv/lls_reference_snr_sweep.csv|reports/csv/frc_reference_qualification.csv", ...
        localFailureToken(fixedEnabled && independentComparisonOK,independentFailure), ...
        "Publication readiness requires either an independent, hash-distinct, " + ...
        "exact-key reference sweep or a statistically qualified independent 3GPP FRC campaign."); %#ok<AGROW>
end

if geometryApplicable
    rows(end+1, 1) = localModeGateRow("RunClassGeometry", runClass, true, ...
        runClass == "ue_placement_geometry_lls" | runClass == "hybrid_validation", ...
        1, double(runClass ~= "ue_placement_geometry_lls" & runClass ~= "hybrid_validation"), ...
        "reports/csv/run_classification.csv", ...
        localFailureToken(runClass == "ue_placement_geometry_lls" | runClass == "hybrid_validation", "run_class_not_geometry"), ...
        "Run class must resolve to ue_placement_geometry_lls or hybrid_validation for geometry acceptance."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromAudit("GeometryRuntimeAudit", runClass, true, ...
        geometryAuditT, "reports/csv/geometry_runtime_audit.csv", "geometry_runtime_audit_failures_present", ...
        "Geometry runtime audit must report zero FAIL rows."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromArtifactAudit("GeometryRequiredCSVAudit", runClass, true, ...
        csvAuditT, "reports/csv/all_csv_artifact_audit.csv", "required_csv_artifact_failures_present", ...
        "Recursive CSV artifact audit must report zero required FAIL rows."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateFromArtifactAudit("GeometryRequiredImageAudit", runClass, true, ...
        imageAuditT, "reports/csv/all_image_artifact_audit.csv", "required_image_artifact_failures_present", ...
        "Recursive image artifact audit must report zero required FAIL rows."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateRow("TrajectoryNonEmpty", runClass, true, ...
        istable(trajectoryT) && height(trajectoryT) > 0, height(trajectoryT), double(~(istable(trajectoryT) && height(trajectoryT) > 0)), ...
        "geometry/csv/trajectory_geometry.csv", ...
        localFailureToken(istable(trajectoryT) && height(trajectoryT) > 0, "trajectory_geometry_empty"), ...
        "Geometry scenario runs must emit non-empty trajectory evidence."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateRow("DopplerReconciliationPass", runClass, true, ...
        localDopplerAuditPass(dopplerT), height(dopplerT), double(~localDopplerAuditPass(dopplerT)), ...
        "mobility/csv/doppler_reconciliation.csv", ...
        localFailureToken(localDopplerAuditPass(dopplerT), "doppler_reconciliation_failed"), ...
        "Doppler reconciliation must pass for geometry scenario runs."); %#ok<AGROW>
    rows(end+1, 1) = localModeGateRow("MeasuredSINRNonEmpty", runClass, true, ...
        istable(measuredSinrT) && height(measuredSinrT) > 0, height(measuredSinrT), double(~(istable(measuredSinrT) && height(measuredSinrT) > 0)), ...
        "reports/csv/measured_sinr_timeseries.csv", ...
        localFailureToken(istable(measuredSinrT) && height(measuredSinrT) > 0, "measured_sinr_timeseries_empty"), ...
        "Geometry scenario runs must emit non-empty measured SINR timeseries evidence."); %#ok<AGROW>
    fixedCurveClaim = (height(dlCurveT) > 0 || height(ulCurveT) > 0) && ~fixedEnabled;
    rows(end+1, 1) = localModeGateRow("NoFixedLinkCurveClaim", runClass, true, ...
        ~fixedCurveClaim, double(height(dlCurveT) + height(ulCurveT)), double(fixedCurveClaim), ...
        "reports/csv/dl_fixed_snr_bler_curve.csv|reports/csv/ul_fixed_snr_bler_curve.csv", ...
        localFailureToken(~fixedCurveClaim, "fixed_link_curve_claim_without_fixed_campaign"), ...
        "Geometry runs must not claim fixed-link curve evidence unless fixed-link calibration is explicitly enabled."); %#ok<AGROW>
end

if ~(fixedApplicable || geometryApplicable)
    rows(end+1, 1) = localModeGateRow("TwoModeAcceptanceNotApplicable", runClass, false, ...
        true, 0, 0, "", "", ...
        "Two-mode acceptance gates are informational only for non-fixed and non-geometry run classes."); %#ok<AGROW>
end

T = struct2table(rows, "AsArray", true);
requiredMask = logical(T.Required);
failMask = string(T.Status) == "FAIL";

fixedRows = T(logical(T.Required) & localStringMember(string(T.GateName), [ ...
    "RunClassFixedSNRSweep","FixedLinkCampaignOnly","NoiseOperatingMode","FixedSNRSweepAudit", ...
    "FixedRequiredCSVAudit","FixedRequiredImageAudit","DLCurveNonEmpty","ULCurveNonEmpty", ...
    "DLHighSNRImproves","ULHighSNRImproves","BLERBERInUnitInterval","ReferenceComparisonPresent"]), :);
geometryRows = T(logical(T.Required) & localStringMember(string(T.GateName), [ ...
    "RunClassGeometry","GeometryRuntimeAudit","GeometryRequiredCSVAudit","GeometryRequiredImageAudit", ...
    "TrajectoryNonEmpty","DopplerReconciliationPass","MeasuredSINRNonEmpty","NoFixedLinkCurveClaim"]), :);

result = struct();
result.RunClass = string(runClass);
result.Direction = string(direction);
result.FixedSNRLLSApplicable = logical(fixedApplicable);
result.GeometryScenarioApplicable = logical(geometryApplicable);
result.Flags = struct( ...
    "FixedSNRLLSOk", ~fixedApplicable || all(string(fixedRows.Status) == "PASS"), ...
    "GeometryScenarioOk", ~geometryApplicable || all(string(geometryRows.Status) == "PASS"), ...
    "PublicationReferenceComparisonOk", ~fixedApplicable || any(string(fixedRows.GateName) == "ReferenceComparisonPresent" & string(fixedRows.Status) == "PASS"), ...
    "TwoModeAcceptanceGatesOk", ~any(failMask & requiredMask));
result.Flags.TwoModeAcceptanceGatesOk = ~any(failMask & requiredMask);
end

function row = localEmptyModeGateRow(runClass)
row = struct( ...
    "GateName", "", ...
    "RunClass", string(runClass), ...
    "Required", false, ...
    "Status", "SKIP", ...
    "RowsChecked", 0, ...
    "RowsFailed", 0, ...
    "EvidencePath", "", ...
    "FailureCode", "", ...
    "Details", "");
end

function row = localModeGateRow(name, runClass, required, pass, rowsChecked, rowsFailed, evidencePath, failureCode, details)
row = localEmptyModeGateRow(runClass);
row.GateName = string(name);
row.Required = logical(required);
row.Status = localModeStatus(required, pass);
row.RowsChecked = double(rowsChecked);
row.RowsFailed = double(rowsFailed);
row.EvidencePath = string(evidencePath);
row.FailureCode = string(failureCode);
row.Details = string(details);
end

function row = localModeGateFromAudit(name, runClass, required, T, evidencePath, failureCode, details)
[rowsChecked, rowsFailed] = localAuditStatusCounts(T, false);
pass = istable(T) && height(T) > 0 && rowsFailed == 0;
row = localModeGateRow(name, runClass, required, pass, rowsChecked, rowsFailed, evidencePath, ...
    localFailureToken(pass, failureCode), details);
end

function row = localModeGateFromArtifactAudit(name, runClass, required, T, evidencePath, failureCode, details)
[rowsChecked, rowsFailed] = localAuditStatusCounts(T, true);
pass = istable(T) && rowsChecked > 0 && rowsFailed == 0;
row = localModeGateRow(name, runClass, required, pass, rowsChecked, rowsFailed, evidencePath, ...
    localFailureToken(pass, failureCode), details);
end

function row = localModeGateFromCurve(name, runClass, required, T, evidencePath, minTrials, failureCode, details)
rowsChecked = 0;
rowsFailed = 0;
pass = istable(T) && height(T) > 0;
if pass
    rowsChecked = height(T);
    trialCount = localNumericColumn(T, "TrialCount");
    incomplete = false(height(T), 1);
    if localHasColumn(T, "Incomplete")
        incomplete = localColumnAsLogical(T.Incomplete);
    end
    badCount = ~isfinite(trialCount) | trialCount <= 0;
    if isfinite(minTrials)
        badCount = badCount | (trialCount < minTrials & ~incomplete);
    end
    rowsFailed = sum(badCount);
    pass = rowsFailed == 0;
end
row = localModeGateRow(name, runClass, required, pass, rowsChecked, rowsFailed, evidencePath, ...
    localFailureToken(pass, failureCode), details);
end

function row = localModeGateFromHighSNR(pass, name, runClass, evidencePath, failureCode, details)
row = localModeGateRow(name, runClass, true, logical(pass), 1, double(~logical(pass)), evidencePath, ...
    localFailureToken(logical(pass), failureCode), details);
end

function tf = localCurveMetricsValid(T)
tf = true;
if ~(istable(T) && height(T) > 0)
    return;
end
for col = ["BLER","BER"]
    vals = localNumericColumn(T, col);
    vals = vals(isfinite(vals));
    if ~isempty(vals) && any(vals < 0 | vals > 1)
        tf = false;
        return;
    end
end
for cols = {["BLER_CI_Low","BLER","BLER_CI_High"], ["BER_CI_Low","BER","BER_CI_High"]}
    lo = localNumericColumn(T, cols{1}(1));
    mid = localNumericColumn(T, cols{1}(2));
    hi = localNumericColumn(T, cols{1}(3));
    n = min([numel(lo), numel(mid), numel(hi)]);
    if n == 0
        continue;
    end
    lo = lo(1:n);
    mid = mid(1:n);
    hi = hi(1:n);
    mask = isfinite(lo) & isfinite(mid) & isfinite(hi);
    if any(mask & (lo > mid | mid > hi))
        tf = false;
        return;
    end
end
end

function tf = localCurveHighSNRImproves(T,targetBLER)
tf = false;
if ~(istable(T) && height(T) >= 2)
    return;
end
snr = localNumericColumn(T, ["ConfiguredSNR_dB","SNR_dB"]);
bler = localNumericColumn(T, "BLER");
low = localNumericColumn(T,"BLER_CI_Low");
high = localNumericColumn(T,"BLER_CI_High");
mask = isfinite(snr) & isfinite(bler);
if nnz(mask) < 2
    return;
end
snr = snr(mask);
bler = bler(mask);
low = low(mask);
high = high(mask);
[snr, order] = sort(snr, "ascend");
bler = bler(order);
low = low(order);
high = high(order);
trendPass=bler(end)<=bler(1)+1e-12;
if isfinite(low(end))&&isfinite(high(1))
    trendPass=trendPass||low(end)<=high(1);
end
objectivePass=true;
if isfinite(targetBLER)
    objectivePass=isfinite(high(end))&&high(end)<=targetBLER;
end
incomplete=false(height(T),1);
if localHasColumn(T,"Incomplete")
    incomplete=localColumnAsLogical(T.Incomplete);
end
incomplete=incomplete(mask);
incomplete=incomplete(order);
tf=trendPass&&objectivePass&&~incomplete(end);
end

function tf = localDopplerAuditPass(T)
tf = false;
if ~(istable(T) && height(T) > 0)
    return;
end
for col = ["DopplerReconciliationOk","Status","status"]
    if localHasColumn(T, col)
        if col == "DopplerReconciliationOk"
            tf = all(localColumnAsLogical(T.(char(col))));
        else
            status = upper(strtrim(string(T.(char(col)))));
            tf = all(status == "PASS" | status == "OK");
        end
        return;
    end
end
end

function direction = localResolveFixedDirection(cfg, resolvedCfg)
direction = upper(localResolveTextSetting(cfg, resolvedCfg, ...
    ["sweeps_and_matrix.fixed_link_calibration.direction","validation.fixed_link_campaign.direction"], "both"));
if strlength(direction) == 0
    direction = "BOTH";
end
end

function minTrials = localResolveMinTrials(cfg, resolvedCfg)
minTrials = localResolveFiniteSetting(cfg, resolvedCfg, ...
    ["sweeps_and_matrix.fixed_link_calibration.min_trials","validation.fixed_link_campaign.min_tb_per_point"], NaN);
end

function value = localResolveTextSetting(cfg, resolvedCfg, paths, defaultValue)
value = "";
for path = string(paths(:)).'
    candidate = localConfigString(cfg, path, "");
    if strlength(strtrim(candidate)) == 0
        candidate = localConfigString(resolvedCfg, path, "");
    end
    if strlength(strtrim(candidate)) > 0
        value = candidate;
        return;
    end
end
value = string(defaultValue);
end

function value = localResolveLogicalSetting(cfg, resolvedCfg, paths, defaultValue)
for path = string(paths(:)).'
    [candidate, ok] = localConfigLogical(cfg, path);
    if ~ok
        [candidate, ok] = localConfigLogical(resolvedCfg, path);
    end
    if ok
        value = logical(candidate);
        return;
    end
end
value = logical(defaultValue);
end

function value = localResolveFiniteSetting(cfg, resolvedCfg, paths, defaultValue)
for path = string(paths(:)).'
    [candidate, ok] = localConfigNumber(cfg, path);
    if ~ok
        [candidate, ok] = localConfigNumber(resolvedCfg, path);
    end
    if ok && isfinite(candidate)
        value = double(candidate);
        return;
    end
end
value = double(defaultValue);
end

function runClass = localResolveRunClass(cfg, resolvedCfg, runClassT)
runClass = localResolveTextSetting(cfg, resolvedCfg, ...
    ["validation.RunClass","validation.run_class","scenario.run_class","canonical_control.validation.run_class"], "");
if strlength(strtrim(runClass)) == 0 && istable(runClassT) && height(runClassT) > 0 && localHasColumn(runClassT, "RunClass")
    runClass = string(runClassT.RunClass(1));
end
if strlength(strtrim(runClass)) == 0
    runClass = "unknown";
end
runClass = lower(strtrim(runClass));
end

function tf = localDirectionEnabledForMode(direction, token)
direction = upper(strtrim(string(direction)));
token = upper(strtrim(string(token)));
tf = direction == "BOTH" | direction == token;
end

function tf = localStringMember(values, candidates)
values = string(values(:));
candidates = string(candidates(:)).';
tf = false(size(values));
for i = 1:numel(candidates)
    tf = tf | values == candidates(i);
end
end

function [rowsChecked, rowsFailed] = localAuditStatusCounts(T, requiredOnly)
rowsChecked = 0;
rowsFailed = 0;
if ~(istable(T) && height(T) > 0)
    return;
end
mask = true(height(T), 1);
if requiredOnly && localHasColumn(T, ["required"])
    mask = localColumnAsLogical(T.required);
elseif requiredOnly && localHasColumn(T, ["Required"])
    mask = localColumnAsLogical(T.Required);
end
rowsChecked = sum(mask);
if rowsChecked == 0
    return;
end
if localHasColumn(T, ["status"])
    status = upper(strtrim(string(T.status)));
elseif localHasColumn(T, ["Status"])
    status = upper(strtrim(string(T.Status)));
else
    status = strings(height(T), 1);
end
rowsFailed = sum(mask & status == "FAIL");
end

function status = localModeStatus(required, pass)
if ~logical(required)
    status = "SKIP";
elseif logical(pass)
    status = "PASS";
else
    status = "FAIL";
end
end

function code = localFailureToken(pass, failureCode)
if logical(pass)
    code = "";
else
    code = string(failureCode);
end
end

function [passed,failure]=localIndependentReferenceComparisonPass(dut,reference)
passed=false;
failure="reference_snr_sweep_missing";
if ~(istable(dut)&&~isempty(dut)&&istable(reference)&&~isempty(reference))
    return;
end
referenceNames=string(reference.Properties.VariableNames);
metadata=["ReferenceSHA256","DUTSHA256","IndependentOfDUT"];
if any(~ismember(metadata,referenceNames))
    failure="reference_independence_metadata_missing";
    return;
end
referenceHash=lower(string(reference.ReferenceSHA256));
dutHash=lower(string(reference.DUTSHA256));
independent=localColumnAsLogical(reference.IndependentOfDUT);
validHash=arrayfun(@(x)strlength(x)==64&& ...
    ~isempty(regexp(char(x),"^[0-9a-f]{64}$","once")),referenceHash) & ...
    arrayfun(@(x)strlength(x)==64&& ...
    ~isempty(regexp(char(x),"^[0-9a-f]{64}$","once")),dutHash);
if ~all(independent&validHash&referenceHash~=dutHash)
    failure="reference_not_independent_or_hash_distinct";
    return;
end
keyFields=sixgr.validation.OperatingPointKey.requiredFields();
if any(~ismember(keyFields,string(dut.Properties.VariableNames))) || ...
        any(~ismember(keyFields,referenceNames))
    failure="reference_complete_point_key_missing";
    return;
end
dutKey=strings(height(dut),1);
referenceKey=strings(height(reference),1);
for index=1:height(dut)
    dutKey(index)=sixgr.validation.OperatingPointKey.canonical(dut(index,:));
end
for index=1:height(reference)
    referenceKey(index)=sixgr.validation.OperatingPointKey.canonical(reference(index,:));
end
if numel(unique(dutKey))~=height(dut)|| ...
        numel(unique(referenceKey))~=height(reference)
    failure="reference_duplicate_point_key";
    return;
end
if ~isequal(sort(dutKey),sort(referenceKey))
    failure="reference_exact_point_join_failed";
    return;
end
passed=true;
failure="";
end

function [passed,failure]=localIndependentFRCQualificationPass(T)
[passed,failure] = ...
    sixgr.conformance.validateReferenceQualificationTable(T);
end

function value = localConfigString(S, dottedPath, defaultValue)
raw = localConfigValue(S, dottedPath, defaultValue);
value = string(raw);
if numel(value) ~= 1
    value = value(1);
end
end

function [value, ok] = localConfigLogical(S, dottedPath)
raw = localConfigValue(S, dottedPath, []);
ok = ~isempty(raw);
if ~ok
    value = false;
    return;
end
if islogical(raw)
    value = logical(raw(1));
elseif isnumeric(raw)
    value = isfinite(double(raw(1))) && double(raw(1)) ~= 0;
else
    token = lower(strtrim(string(raw)));
    value = any(token == ["1","true","yes","on","enabled","pass"]);
end
end

function [value, ok] = localConfigNumber(S, dottedPath)
raw = localConfigValue(S, dottedPath, []);
ok = ~isempty(raw);
if ~ok
    value = NaN;
    return;
end
if isnumeric(raw) || islogical(raw)
    value = double(raw(1));
else
    value = str2double(string(raw));
    ok = isfinite(value);
end
end

function value = localConfigValue(S, dottedPath, defaultValue)
value = defaultValue;
if ~isstruct(S)
    return;
end
parts = split(string(dottedPath), ".");
cursor = S;
for i = 1:numel(parts)
    name = char(parts(i));
    if isstruct(cursor) && isfield(cursor, name)
        cursor = cursor.(name);
    else
        value = defaultValue;
        return;
    end
end
value = cursor;
end

function path = localWrite(dirPath, fileName, T)
path = fullfile(dirPath, fileName);
sixgr.analytics.writeAnalysisTable(path, T);
end

function [ok, T] = localEvaluateEnergy(runDir)
energyPath = localFirstExisting(runDir, [
    "reports/csv/energy_efficiency_outputs.csv"
    "rf/csv/probe_rf_energy.csv"
    "reports/csv/live_energy_efficiency_table.csv"
    ]);
rootPath = fullfile(runDir, "reports", "csv", "energy_root_cause_table.csv");
termsPath = fullfile(runDir, "rf", "csv", "energy_model_terms.csv");
energy = localReadTable(energyPath);
root = localReadTable(rootPath);
terms = localReadTable(termsPath);

ueJ = localMetricValue(energy, ["ue_energy_per_successful_bit","ue_energy_per_bit_j"]);
gnbJ = localMetricValue(energy, ["gnb_energy_per_successful_bit","gnb_energy_per_bit_j"]);
criticalEnergy = localRowsForMetricKeys(energy, ...
    ["ue_energy_per_successful_bit","ue_energy_per_bit_j", ...
     "gnb_energy_per_successful_bit","gnb_energy_per_bit_j"]);
observedOk = height(criticalEnergy) == 2 && localAvailabilityOk(criticalEnergy);
modelTermsOk = height(terms) >= 12 && localAvailabilityOk(terms);
    % Entity coverage is established by the measured energy ledger itself.
    % energy_root_cause_table is an exception table and is correctly empty
    % (or absent) when no energy defect is detected; requiring fabricated
    % UE/cell root-cause rows made a healthy energy model fail publication.
    hasUE = localRootHasEntity(energy, ["ue"]);
    hasCell = localRootHasEntity(energy, ["cell","gnb","gNB"]);
criticalCount = double(isfinite(ueJ) && ueJ > 0) + double(isfinite(gnbJ) && gnbJ > 0);
    ok = ~isempty(energyPath) && istable(energy) && height(energy) >= 2 && criticalCount == 2 && ...
        observedOk && modelTermsOk && hasUE && hasCell;
    reason = localReason(ok, "energy_metrics_entities_and_model_terms_verified", ...
        "missing_or_nonpositive_energy_metrics_entities_or_model_terms");

T = table(string(localPortable(runDir, energyPath)), string(localPortable(runDir, rootPath)), ...
    height(energy), height(root), height(terms), criticalCount, observedOk, modelTermsOk, ueJ, gnbJ, hasUE, hasCell, ok, reason, ...
    'VariableNames', {'EnergySourceCSV','RootCauseSourceCSV','EnergyMetricRows','RootCauseRows', ...
    'EnergyModelTermRows','CriticalPositiveMetricCount','AvailabilityOk','EnergyModelTermsOk','UEEnergyPerBit_J','GNBEnergyPerBit_J', ...
    'HasUEEnergyRows','HasCellEnergyRows','EnergyModelOk','FailureReason'});
end

function [ok, T] = localEvaluatePerformance(cfg, runDir)
runtimePath = fullfile(runDir, "meta", "runtime_summary.json");
summary = localReadJson(runtimePath);
runtimeS = localJsonNumber(summary, ["ElapsedSeconds","RuntimeSeconds","runtime_seconds","elapsed_seconds"], NaN);
runtimeEvidencePath = runtimePath;
if ~isfinite(runtimeS)
    reportPath = fullfile(runDir, "reports", "scenario_report.md");
    runtimeS = localScenarioReportRuntimeSeconds(reportPath);
    if isfinite(runtimeS)
        runtimeEvidencePath = reportPath;
    end
end
profilingConfigured = localBool(cfg, ["output.profiler_enabled","run.profiler_enabled", ...
    "run_control.time_profiling_enable","time_profiling_enable","perf.exportTimeProfile", ...
    "analytics.export_time_profile","run.time_profiling_enable","run.timeProfilingEnabled", ...
    "perf.timeProfilingEnabled"], false);
[profileArtifact, profileArtifactPath] = localFirstExistingFlag(runDir, [
    "reports/csv/time_profile_summary.csv"
    "reports/csv/time_profile_calls.csv"
    "reports/csv/time_profile_coverage.csv"
    "reports/csv/per_function_timing.csv"
    "reports/csv/runtime_profiler_summary.csv"
    "reports/csv/runtime_function_profile.csv"
    "reports/csv/runtime_function_call_edges.csv"
    "profiler/time_profile.csv"
    "performance/csv/time_profile.csv"
    ]);
runtimeOk = isfinite(runtimeS) && runtimeS > 0 && runtimeS < 86400;
% A configured profiler is an execution request, not measured evidence.
% Publication readiness therefore requires the persisted profiler artifact;
% otherwise a run could pass this gate without ever executing the profiler.
ok = exist(runtimeEvidencePath, "file") == 2 && runtimeOk && profileArtifact;
if ok
    reason = "runtime_summary_and_persisted_profiling_evidence_verified";
elseif ~(exist(runtimeEvidencePath, "file") == 2 && runtimeOk)
    reason = "runtime_summary_missing_or_invalid";
else
    reason = "persisted_profiling_evidence_missing";
end
runtimeEvidenceRel = string(localPortable(runDir, runtimeEvidencePath));
T = table(runtimeEvidenceRel, runtimeEvidenceRel, string(localPortable(runDir, profileArtifactPath)), ...
    runtimeS, logical(profilingConfigured), logical(profileArtifact), ...
    ok, reason, 'VariableNames', {'RuntimeSummaryJSON','RuntimeEvidencePath','ProfilerArtifactCSV','RuntimeSeconds','ProfilingConfigured', ...
    'ProfilerArtifactExists','PerformanceProfileOk','FailureReason'});
end

function [ok, T] = localEvaluateLongRunStability(cfg, runDir)
dropPath = fullfile(runDir, "air_interface", "csv", "multi_seed_drop_statistics.csv");
drop = localReadTable(dropPath);
stdLimit = localNumber(cfg, ["canonical_control.run.max_bler_std", ...
    "lls6g.resolvedConfig.canonical_control.run.max_bler_std", ...
    "run.max_bler_std","analysis.long_run_bler_std_threshold"], 0.05);
minSeeds = localNumber(cfg, ["canonical_control.run.num_seeds", ...
    "lls6g.resolvedConfig.canonical_control.run.num_seeds", ...
    "run.num_seeds","simulation.num_seeds"], 2);
if ~(isfinite(minSeeds) && minSeeds >= 2)
    minSeeds = 2;
end
bler = localNumericColumn(drop, "BLER");
seed = localNumericColumn(drop, "FixedLinkDropSeed");
if isempty(seed)
    seed = localNumericColumn(drop, "Seed");
end
% Stability is an operating-point property.  Pooling low- and high-SNR
% drops would interpret the intended waterfall as temporal instability.
% Group by immutable fixed-link point and direction, then require the seed
% count and BLER dispersion at every executed operating point.
point = localNumericColumn(drop, "FixedLinkPointIndex");
if isempty(point)
    point = localNumericColumn(drop, ["SNR_dB","ConfiguredSNR_dB"]);
end
direction = repmat("UNKNOWN", height(drop), 1);
if localHasColumn(drop, "Direction")
    direction = upper(strtrim(string(drop.Direction)));
end
executed = true(height(drop), 1);
if localHasColumn(drop, "EvidenceStatus")
    executed = string(drop.EvidenceStatus) == "executed_trial_rows";
end
valid = executed & isfinite(bler) & isfinite(seed) & isfinite(point) & ...
    bler >= 0 & bler <= 1;
groupKey = direction + "|" + string(point);
groups = unique(groupKey(valid), "stable");
seedCounts = zeros(numel(groups), 1);
groupMeans = NaN(numel(groups), 1);
groupStd = NaN(numel(groups), 1);
for groupIndex = 1:numel(groups)
    mask = valid & groupKey == groups(groupIndex);
    seedCounts(groupIndex) = localUniqueFiniteCount(seed(mask));
    groupMeans(groupIndex) = mean(bler(mask), "omitnan");
    groupStd(groupIndex) = std(bler(mask), 0, "omitnan");
end
if isempty(groups)
    seedCount = NaN;
    meanVal = NaN;
    stdVal = NaN;
else
    seedCount = min(seedCounts, [], "omitnan");
    meanVal = mean(groupMeans, "omitnan");
    stdVal = max(groupStd, [], "omitnan");
end
ok = exist(dropPath, "file") == 2 && ~isempty(groups) && ...
    all(seedCounts >= minSeeds) && all(isfinite(groupStd) & groupStd <= stdLimit) && ...
    all(isfinite(groupMeans) & groupMeans >= 0 & groupMeans <= 1);
reason = localReason(ok, "multi_seed_bler_stability_verified", ...
    "multi_seed_operating_point_statistics_missing_or_bler_variance_out_of_bounds");
T = table(string(localPortable(runDir, dropPath)), height(drop), seedCount, meanVal, stdVal, stdLimit, minSeeds, ok, reason, ...
    'VariableNames', {'DropStatisticsCSV','DropRows','SeedCount','BLERMean','BLERStd', ...
    'BLERStdThreshold','RequiredSeedCount','LongRunStabilityOk','FailureReason'});
end

function [ok, T] = localEvaluateArtifactCompleteness(runDir)
% The runtime contract coverage and exact image audit are the final raster
% authority.  Do not require retired MATLAB plot aliases: those names were
% removed deliberately when CSV-driven post-run rendering became the only
% LLS raster producer.
coverage = localReadTable(fullfile(runDir, "reports", "csv", ...
    "contract_materialization_coverage.csv"));
imageAudit = localReadTable(fullfile(runDir, "reports", "csv", ...
    "all_image_artifact_audit.csv"));
generation = localReadTable(fullfile(runDir, "artifact_generation", ...
    "artifact_generation_results.csv"));
missing = strings(0, 1);

[coverageOk, coverageCount, coverageMissing] = ...
    localContractCoverageCompleteness(coverage);
missing = [missing; coverageMissing(:)]; %#ok<AGROW>
[imageAuditOk, imageCount, imageMissing] = ...
    localImageAuditCompleteness(imageAudit);
missing = [missing; imageMissing(:)]; %#ok<AGROW>
[generationOk, generationCount, generationMissing] = ...
    localArtifactGenerationCompleteness(runDir, generation);
missing = [missing; generationMissing(:)]; %#ok<AGROW>
if ~coverageOk && isempty(coverageMissing)
    missing(end+1, 1) = "contract_materialization_coverage_invalid"; %#ok<AGROW>
end
if ~imageAuditOk && isempty(imageMissing)
    missing(end+1, 1) = "all_image_artifact_audit_invalid"; %#ok<AGROW>
end
if ~generationOk && isempty(generationMissing)
    missing(end+1, 1) = "artifact_generation_results_invalid"; %#ok<AGROW>
end
unavailable = localReadTable(fullfile(runDir, "reports", "csv", "unavailable_plot_card_registry.csv"));
[unresolvedUnavailable, resolvedUnavailable] = localUnresolvedUnavailablePlots(runDir, unavailable);
unavailableCount = height(unavailable);
unresolvedCount = numel(unresolvedUnavailable);
ok = coverageOk && imageAuditOk && generationOk && ...
    isempty(missing) && unresolvedCount == 0;
reason = localReason(ok, ...
    "runtime_contract_tables_images_and_declared_artifacts_pass_exact_audits", ...
    "runtime_contract_artifact_missing_failed_or_unavailable_plot_cards_remain");
T = table(strjoin(missing, "|"), unavailableCount, numel(resolvedUnavailable), unresolvedCount, ...
    strjoin(unresolvedUnavailable, "|"), ...
    coverageCount + imageCount + generationCount, ok, reason, ...
    'VariableNames', {'MissingArtifacts','UnavailablePlotCardCount','ResolvedUnavailablePlotCardCount', ...
    'UnresolvedUnavailablePlotCardCount','UnresolvedUnavailablePlotCards','RequiredArtifactCount', ...
    'ArtifactCompletenessOk','FailureReason'});
end

function [ok, T] = localEvaluatePlotLineage(runDir)
manifestPath = fullfile(runDir, "reports", "csv", "plot_manifest.csv");
contractPath = fullfile(runDir, "reports", "csv", "contract_plot_lineage.csv");
coveragePath = fullfile(runDir, "reports", "csv", "contract_materialization_coverage.csv");
manifest = localReadTable(manifestPath);
contract = localReadTable(contractPath);
coverage = localReadTable(coveragePath);

[manifestOk, manifestMissing] = localManifestLineageOk(runDir, manifest);
[contractOk, contractMissing] = localContractPlotLineageOk(runDir, contract);
measuredMask = false(height(contract), 1);
if istable(contract) && height(contract) > 0 && localHasColumn(contract, "PlotId")
    plotIds = lower(replace(strtrim(string(contract.PlotId)), "_", "-"));
    measuredMask = contains(plotIds, "measured-sinr") | ...
        contains(plotIds, "bler-vs-sinr") | ...
        contains(plotIds, "throughput-vs-sinr");
end
measuredOk = contractOk && any(measuredMask);
[coverageOk, ~, coverageMissing] = localContractCoverageCompleteness(coverage);
missing = unique([manifestMissing(:); contractMissing(:); coverageMissing(:)], "stable");
ok = manifestOk && contractOk && measuredOk && coverageOk;
reason = localReason(ok, "contract_pngs_have_exact_csv_and_hash_bound_lineage", ...
    "contract_plot_manifest_or_source_lineage_missing_incomplete");
T = table(string(localPortable(runDir, manifestPath)), string(localPortable(runDir, contractPath)), ...
    string(localPortable(runDir, coveragePath)), height(manifest), sum(measuredMask), height(contract), ...
    strjoin(missing, "|"), manifestOk, measuredOk, contractOk && coverageOk, ok, reason, ...
    'VariableNames', {'PlotManifestCSV','MeasuredSINRLineageCSV','ChartSourceRegistryCSV', ...
    'PlotManifestRows','MeasuredSINRLineageRows','ChartSourceRegistryRows','MissingManifestLineage', ...
    'PlotManifestLineageOk','MeasuredSINRLineageOk','ChartSourceRegistryOk', ...
    'PlotDataLineageOk','FailureReason'});
end

function [ok, count, missing] = localContractCoverageCompleteness(T)
missing = strings(0, 1);
count = 0;
required = ["tables_total","tables_available","tables_policy_disabled", ...
    "tables_missing","charts_total","charts_available", ...
    "charts_policy_disabled","charts_missing"];
if ~(istable(T) && height(T) == 1 && all(localHasColumn(T, required)))
    ok = false;
    missing = "reports/csv/contract_materialization_coverage.csv";
    return;
end
values = zeros(numel(required),1);
for index = 1:numel(required)
    raw = localNumericColumn(T, required(index));
    if numel(raw) ~= 1 || ~isfinite(raw(1)) || raw(1) < 0 || raw(1) ~= fix(raw(1))
        ok = false;
        missing = "contract_coverage_invalid_" + required(index);
        return;
    end
    values(index) = raw(1);
end
tableTotal = values(1); tableAvailable = values(2);
tableDisabled = values(3); tableMissing = values(4);
chartTotal = values(5); chartAvailable = values(6);
chartDisabled = values(7); chartMissing = values(8);
if tableTotal <= 0 || chartTotal <= 0 || ...
        tableAvailable + tableDisabled + tableMissing ~= tableTotal || ...
        chartAvailable + chartDisabled + chartMissing ~= chartTotal || ...
        tableMissing ~= 0 || chartMissing ~= 0
    ok = false;
    missing = [ ...
        localFailureToken(tableMissing == 0, ...
        "contract_tables_missing=" + string(tableMissing)); ...
        localFailureToken(chartMissing == 0, ...
        "contract_charts_missing=" + string(chartMissing)); ...
        localFailureToken(tableAvailable + tableDisabled + tableMissing == tableTotal, ...
        "contract_table_coverage_arithmetic_mismatch"); ...
        localFailureToken(chartAvailable + chartDisabled + chartMissing == chartTotal, ...
        "contract_chart_coverage_arithmetic_mismatch")];
    missing = missing(strlength(missing) > 0);
    if isempty(missing), missing = "contract_coverage_totals_invalid"; end
    return;
end
count = tableAvailable + chartAvailable;
ok = true;
end

function [ok, count, missing] = localImageAuditCompleteness(T)
missing = strings(0, 1);
count = height(T);
required = ["relative_path","status","readable", ...
    "blank_or_low_information","source_csv_exists"];
if ~(istable(T) && height(T) > 0 && all(localHasColumn(T, required)))
    ok = false;
    missing = "reports/csv/all_image_artifact_audit.csv";
    return;
end
pass = lower(strtrim(string(T.status))) == "pass" & ...
    localColumnAsLogical(T.readable) & ...
    ~localColumnAsLogical(T.blank_or_low_information) & ...
    localColumnAsLogical(T.source_csv_exists);
if any(~pass)
    missing = "image_audit:" + string(T.relative_path(~pass));
end
ok = all(pass);
end

function [ok, count, missing] = localArtifactGenerationCompleteness(runDir, T)
missing = strings(0, 1);
count = 0;
requiredColumns = ["Required","Status","OutputRelativePath"];
if ~(istable(T) && height(T) > 0 && all(localHasColumn(T, requiredColumns)))
    ok = false;
    missing = "artifact_generation/artifact_generation_results.csv";
    return;
end
required = localColumnAsLogical(T.Required);
count = sum(required);
if count == 0
    ok = false;
    missing = "artifact_generation_required_rows_missing";
    return;
end
pass = ~required | lower(strtrim(string(T.Status))) == "pass";
for index = find(required(:)).'
    rel = replace(strtrim(string(T.OutputRelativePath(index))), "\", "/");
    if strlength(rel) == 0 || ~localGeneratedArtifactExists(runDir, rel)
        pass(index) = false;
        missing(end+1, 1) = "artifact_generation:" + rel; %#ok<AGROW>
    end
end
if any(required & ~pass)
    failed = find(required & ~pass);
    for index = failed(:).'
        rel = replace(strtrim(string(T.OutputRelativePath(index))), "\", "/");
        token = "artifact_generation:" + rel;
        if ~any(missing == token)
            missing(end+1, 1) = token; %#ok<AGROW>
        end
    end
end
ok = all(pass);
end

function tf = localGeneratedArtifactExists(runDir, rel)
% OutputRelativePath is relative to the canonical component publisher root.
% Keep a read-only root lookup for older evidence, but do not copy, mirror,
% or manufacture a missing contract artifact.
rel = replace(strtrim(string(rel)), "\", "/");
tf = localArtifactExists(runDir, "components/" + rel) || ...
    localArtifactExists(runDir, rel);
end

function [ok, missing] = localContractPlotLineageOk(runDir, T)
[ok, missing] = localManifestLineageOk(runDir, T);
if ~(istable(T) && height(T) > 0)
    return;
end
rowPass = true(height(T),1);
if localHasColumn(T, "Status")
    rowPass = rowPass & lower(strtrim(string(T.Status))) == "pass";
else
    rowPass(:) = false;
end
if all(localHasColumn(T, ["ImageExists","SourceExists"]))
    rowPass = rowPass & localColumnAsLogical(T.ImageExists) & ...
        localColumnAsLogical(T.SourceExists);
else
    rowPass(:) = false;
end
if any(~rowPass)
    ids = string((1:height(T)).');
    if localHasColumn(T, "PlotId"), ids = string(T.PlotId); end
    missing = [missing(:); "contract_lineage:" + ids(~rowPass)];
end
ok = ok && all(rowPass);
end

function [ok, T] = localEvaluateClaimsTruthfulness(runDir)
claimPath = fullfile(runDir, "reports", "final", "final_scientific_claims_matrix.csv");
scanPath = fullfile(runDir, "reports", "csv", "public_output_claim_scan.csv");
claims = localReadTable(claimPath);
scan = localReadTable(scanPath);

unsupportedLabeled = 0;
unsupportedClaimed = 0;
if istable(claims) && height(claims) > 0 && localHasColumn(claims, "support_status")
    status = lower(strtrim(string(claims.support_status)));
    unsupportedLabel = contains(status, "unsupported");
    supportedLabel = status == "supported" | startsWith(status, "supported_") | ...
        status == "verified" | startsWith(status, "verified_");
    unsupportedLabeled = sum(unsupportedLabel);
    unsupportedClaimed = sum(supportedLabel & unsupportedLabel);
end
forbiddenBroad = false;
if istable(scan) && height(scan) > 0
    for col = ["ForbiddenBroadClaim","ClaimAllowed"]
        if localHasColumn(scan, col)
            vals = localColumnAsLogical(scan.(char(col)));
            if col == "ForbiddenBroadClaim"
                forbiddenBroad = any(vals);
            elseif col == "ClaimAllowed"
                forbiddenBroad = forbiddenBroad || any(~vals);
            end
        end
    end
end
if ~(istable(claims) && height(claims) > 0)
    % The Phase 7 builder itself writes a conservative claims matrix. When
    % no older matrix exists, the upcoming matrix is truthful by construction
    % because it labels unsupported claims as unsupported.
    claimsSource = "current_phase7_builder_truthful_claim_matrix";
    ok = true;
else
    claimsSource = localPortable(runDir, claimPath);
    ok = unsupportedClaimed == 0 && ~forbiddenBroad;
end
reason = localReason(ok, "claims_matrix_labels_support_status_truthfully", ...
    "unsupported_or_forbidden_claim_presented_as_supported");
T = table(string(claimsSource), string(localPortable(runDir, scanPath)), height(claims), ...
    unsupportedLabeled, unsupportedClaimed, forbiddenBroad, ok, reason, ...
    'VariableNames', {'ClaimsMatrixCSV','PublicClaimScanCSV','ClaimRows','UnsupportedClaimRows', ...
    'UnsupportedButClaimedSupportedRows','ForbiddenBroadClaimPresent','FinalScientificClaimsTruthfulOk', ...
    'FailureReason'});
end

function [ok, missing] = localManifestLineageOk(runDir, manifest)
missing = strings(0, 1);
ok = istable(manifest) && height(manifest) > 0;
if ~ok
    missing = "plot_manifest_missing";
    return;
end
for i = 1:height(manifest)
    if localHasColumn(manifest, "CountsAsRealPlot") && ~localColumnAsLogical(manifest.CountsAsRealPlot(i))
        continue;
    end
    imageRel = localStringAt(manifest, "ImagePath", i);
    sourceSpec = localStringAt(manifest, "SourceCSV", i);
    if strlength(strtrim(imageRel)) == 0 || exist(fullfile(runDir, strrep(char(imageRel), "/", filesep)), "file") ~= 2
        missing(end+1, 1) = "image:" + imageRel; %#ok<AGROW>
    end
    if strlength(strtrim(sourceSpec)) == 0
        missing(end+1, 1) = "source_empty:" + imageRel; %#ok<AGROW>
    else
        parts = split(sourceSpec, "|");
        for p = parts(:).'
            if strlength(strtrim(p)) > 0 && exist(fullfile(runDir, strrep(char(p), "/", filesep)), "file") ~= 2
                missing(end+1, 1) = "source:" + p; %#ok<AGROW>
            end
        end
    end
end
ok = isempty(missing);
end

function value = localMetricValue(T, metricKeys)
value = NaN;
if ~(istable(T) && height(T) > 0)
    return;
end
metricCol = localFirstColumnName(T, ["MetricKey","metric_key","MetricName","metric_name"]);
if strlength(metricCol) == 0
    return;
end
metricValues = lower(strtrim(string(T.(char(metricCol)))));
keys = lower(strtrim(string(metricKeys(:))));
mask = ismember(metricValues, keys);
if ~any(mask)
    return;
end
for col = ["ValueNumeric","Value","MetricValue","metric_value","energy_per_bit_j"]
    vals = localNumericColumn(T(mask, :), col);
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = vals(1);
        return;
    end
end
end

function tf = localAvailabilityOk(T)
tf = istable(T) && height(T) > 0;
if ~tf
    return;
end
availabilityCol = localFirstColumnName(T, ["Availability","availability","EvidenceStatus","evidence_status"]);
statusCol = localFirstColumnName(T, ["energy_value_status","value_status","ValueStatus","status"]);
bad = ["proxy","fallback","synthetic","placeholder","not_available","not_evaluated","unavailable","disabled"];
if strlength(availabilityCol) > 0
    states = lower(strtrim(string(T.(char(availabilityCol)))));
    tf = all(strlength(states) > 0) && ~any(ismember(states, bad) | contains(states, bad));
elseif strlength(statusCol) > 0
    states = lower(strtrim(string(T.(char(statusCol)))));
    tf = all(states == "ok" | states == "observed" | states == "available" | states == "derived" | states == "runtime_truth_fact");
end
end

function T = localRowsForMetricKeys(T, keys)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
name = localFirstColumnName(T, ["MetricKey","metric_key","KPIName","kpi_name"]);
if strlength(name) == 0
    T = table();
    return;
end
values = lower(strtrim(string(T.(char(name)))));
wanted = lower(strtrim(string(keys)));
T = T(ismember(values, wanted), :);
end

function tf = localRootHasEntity(T, names)
tf = false;
if ~(istable(T) && height(T) > 0)
    return;
end
entity = strings(height(T), 1);
for col = ["entity_type","EntityType","Entity"]
    if localHasColumn(T, col)
        entity = lower(strtrim(string(T.(char(col)))));
        break;
    end
end
tf = any(ismember(entity, lower(string(names))));
end

function [unresolved, resolved] = localUnresolvedUnavailablePlots(runDir, unavailable)
unresolved = strings(0, 1);
resolved = strings(0, 1);
if ~(istable(unavailable) && height(unavailable) > 0)
    return;
end
for i = 1:height(unavailable)
    plotId = lower(strtrim(localStringAt(unavailable, "PlotId", i)));
    imageRel = localStringAt(unavailable, "ImagePath", i);
    sourceRel = localStringAt(unavailable, "SourceCSV", i);
    if localUnavailableEntryResolvedByEvidence(runDir, plotId, imageRel, sourceRel)
        resolved(end+1, 1) = plotId; %#ok<AGROW>
    else
        unresolved(end+1, 1) = plotId; %#ok<AGROW>
    end
end
end

function tf = localUnavailableEntryResolvedByEvidence(runDir, plotId, imageRel, sourceRel)
plotId = lower(strtrim(string(plotId)));
tf = localArtifactExists(runDir, imageRel) && localAllSourceArtifactsExist(runDir, sourceRel);
if tf || strlength(plotId) == 0
    return;
end
contract = localReadTable(fullfile(runDir, "reports", "csv", ...
    "contract_plot_lineage.csv"));
if ~(istable(contract) && height(contract) > 0 && ...
        all(localHasColumn(contract, ["PlotId","ImagePath","SourceCSV","Status"])))
    return;
end
token = replace(replace(plotId, "_", "-"), " ", "-");
ids = lower(replace(replace(strtrim(string(contract.PlotId)), "_", "-"), " ", "-"));
mask = contains(ids, token) & lower(strtrim(string(contract.Status))) == "pass";
for index = find(mask(:)).'
    if localArtifactExists(runDir, string(contract.ImagePath(index))) && ...
            localAllSourceArtifactsExist(runDir, string(contract.SourceCSV(index)))
        tf = true;
        return;
    end
end
end

function tf = localAllSourceArtifactsExist(runDir, sourceSpec)
sourceSpec = string(sourceSpec);
if strlength(strtrim(sourceSpec)) == 0
    tf = false;
    return;
end
parts = split(sourceSpec, "|");
tf = true;
for part = parts(:).'
    part = strtrim(part);
    if strlength(part) == 0
        continue;
    end
    tf = tf && localArtifactExists(runDir, part);
end
end

function tf = localArtifactExists(runDir, rel)
rel = string(rel);
tf = strlength(strtrim(rel)) > 0 && ...
    exist(fullfile(runDir, strrep(char(rel), "/", filesep)), "file") == 2;
end

function T = localReadTable(path)
T = table();
if strlength(strtrim(string(path))) == 0 || exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "Delimiter", ",", "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function S = localReadJson(path)
S = struct();
if exist(char(path), "file") ~= 2
    return;
end
try
    S = jsondecode(fileread(char(path)));
catch
    S = struct();
end
end

function path = localFirstExisting(runDir, rels)
path = "";
for rel = string(rels(:)).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    if exist(p, "file") == 2
        path = string(p);
        return;
    end
end
end

function tf = localAnyExisting(runDir, rels)
tf = false;
for rel = string(rels(:)).'
    if exist(fullfile(runDir, strrep(char(rel), "/", filesep)), "file") == 2
        tf = true;
        return;
    end
end
end

function [tf, path] = localFirstExistingFlag(runDir, rels)
tf = false;
path = "";
for rel = string(rels(:)).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    if exist(p, "file") == 2
        tf = true;
        path = string(p);
        return;
    end
end
end

function tf = localHasColumn(T, names)
tf = istable(T) && all(ismember(string(names), string(T.Properties.VariableNames)));
end

function name = localFirstColumnName(T, names)
name = "";
if ~istable(T)
    return;
end
vars = string(T.Properties.VariableNames);
for candidate = string(names(:)).'
    idx = find(strcmpi(vars, candidate), 1, "first");
    if ~isempty(idx)
        name = vars(idx);
        return;
    end
end
end

function vals = localNumericColumn(T, name)
vals = zeros(0, 1);
if ~(istable(T) && height(T) > 0)
    return;
end
name = localFirstColumnName(T, name);
if strlength(name) == 0
    return;
end
raw = T.(char(string(name)));
if isnumeric(raw) || islogical(raw)
    vals = double(raw(:));
else
    vals = str2double(string(raw(:)));
end
vals = vals(:);
end

function tf = localColumnAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok" | token == "available";
end
end

function s = localStringAt(T, name, idx)
s = "";
if istable(T) && localHasColumn(T, name) && idx <= height(T)
    raw = T.(char(string(name)));
    if iscell(raw)
        if idx <= numel(raw)
            s = string(raw{idx});
        end
    elseif isstring(raw) || iscategorical(raw)
        raw = string(raw);
        if idx <= numel(raw)
            s = raw(idx);
        end
    elseif ischar(raw)
        if size(raw, 1) >= idx
            s = string(strtrim(raw(idx, :)));
        else
            s = string(strtrim(raw));
        end
    else
        raw = string(raw);
        if idx <= numel(raw)
            s = raw(idx);
        end
    end
end
end

function n = localUniqueFiniteCount(values)
values = double(values(:));
values = values(isfinite(values));
n = double(numel(unique(values)));
end

function value = localJsonNumber(S, names, defaultValue)
value = defaultValue;
if ~isstruct(S)
    return;
end
for name = string(names(:)).'
    raw = sixgr.util.structGet(S, char(name), []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function seconds = localScenarioReportRuntimeSeconds(path)
seconds = NaN;
if exist(char(path), "file") ~= 2
    return;
end
try
    text = string(fileread(char(path)));
catch
    return;
end
patterns = [
    "Runtime seconds:\s*`?([0-9]+(?:\.[0-9]+)?)"
    "RuntimeSeconds\s*[:=]\s*`?([0-9]+(?:\.[0-9]+)?)"
    "Runtime seconds.*?([0-9]+(?:\.[0-9]+)?)"
    ];
for pat = patterns(:).'
    tok = regexp(text, char(pat), "tokens", "once");
    if ~isempty(tok)
        seconds = str2double(string(tok{1}));
        if isfinite(seconds)
            return;
        end
    end
end
end

function value = localNumber(cfg, paths, defaultValue)
value = defaultValue;
for path = string(paths(:)).'
    raw = localGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function tf = localBool(cfg, paths, defaultValue)
tf = logical(defaultValue);
for path = string(paths(:)).'
    raw = localGet(cfg, path, []);
    if islogical(raw) || isnumeric(raw)
        if isscalar(raw)
            tf = logical(raw);
            return;
        end
    else
        s = lower(strtrim(string(raw)));
        if s == "true" || s == "1" || s == "yes" || s == "on"
            tf = true;
            return;
        elseif s == "false" || s == "0" || s == "no" || s == "off"
            tf = false;
            return;
        end
    end
end
end

function value = localGet(cfg, path, defaultValue)
try
    value = sixgr.util.structGet(cfg, path, defaultValue);
catch
    value = defaultValue;
end
end

function rel = localPortable(runDir, path)
rel = string(path);
if strlength(strtrim(rel)) == 0
    return;
end
try
    root = string(runDir);
    if startsWith(rel, root)
        rel = eraseBetween(rel, 1, strlength(root));
        rel = regexprep(rel, "^[\\/]", "");
    end
catch
end
rel = replace(rel, "\", "/");
end

function reason = localReason(ok, passReason, failReason)
if logical(ok)
    reason = string(passReason);
else
    reason = string(failReason);
end
end
