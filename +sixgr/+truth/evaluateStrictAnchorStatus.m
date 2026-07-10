function root = evaluateStrictAnchorStatus(runFolder, scfg, cfg, verdict, dlTrials, ulTrials, opSummary)
%EVALUATESTRICTANCHORSTATUS Canonical root status gate for strict LLS outputs.
%
% This evaluator deliberately separates process lifecycle from result truth:
% a run may complete and write artifacts while still failing standards claims,
% scenario objectives, active issue gates, or configured/effective binding.

if nargin < 2
    scfg = struct();
end
if nargin < 3
    cfg = struct();
end
if nargin < 4 || ~isstruct(verdict)
    verdict = struct();
end
if nargin < 5 || ~istable(dlTrials)
    dlTrials = table();
end
if nargin < 6 || ~istable(ulTrials)
    ulTrials = table();
end
if nargin < 7 || ~isstruct(opSummary)
    opSummary = struct();
end

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
localEnsureRootDirs(layout);

meta = localMetadata(layout, scfg, cfg);
details = sixgr.util.structGet(verdict, "CheckDetails", struct());
preRootFailures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
preRootFailures = preRootFailures(:);
preRootFailures = preRootFailures(strlength(strtrim(preRootFailures)) > 0);

scenarioMode = localScenarioMode(scfg, cfg);
strictEligible = localStrictAnchorEligible(scfg, cfg, scenarioMode, meta);
required = localRequiredDirections(scfg, cfg);
runCompleted = localRunCompleted(layout);
artifactsWritten = double(sixgr.util.structGet(verdict, "CanonicalArtifactGapCount", 0)) == 0 && ...
    double(sixgr.util.structGet(verdict, "RequiredRuntimeEvidenceMissingCount", 0)) == 0 && ...
    double(sixgr.util.structGet(verdict, "RoundtripMismatchCount", 0)) == 0;
truthContractOk = isempty(preRootFailures);
runtimeTruthContractOk = truthContractOk;

runClassProfile = localResolveRunClassProfile(scfg, cfg, scenarioMode);
configuredGate = localConfiguredEffectiveGate(layout, meta, scfg, cfg, dlTrials, ulTrials, opSummary, required, scenarioMode, strictEligible, runClassProfile);
mandatoryGate = localMandatorySubsystemGate(details, required);
claimGate = localStandardsClaimGate(layout, meta, scfg, cfg, mandatoryGate, strictEligible);
conformanceGate = localConformanceRuntimeAudit(layout, meta, details, mandatoryGate, strictEligible);
runClassGate = localRunClassificationGate(layout, meta, required, configuredGate, runClassProfile);
bindingGate = localPDCCHGrantBindingGate(layout, cfg, dlTrials, ulTrials);

rootIssueRows = localRootIssueRows(meta, claimGate, configuredGate, mandatoryGate, conformanceGate, strictEligible);
issueRegistry = localMergeRootIssues(layout, rootIssueRows);
activeIssueGate = localActiveIssueGate(layout, meta, issueRegistry, rootIssueRows, strictEligible);

scenarioObjective = sixgr.util.structGet(details, "ScenarioObjective", struct("ScenarioObjectiveOk", true));
pdschObjective = sixgr.util.structGet(details, "PDSCHObjective", struct("ObjectivePass", true));
scenarioObjectiveOk = logical(sixgr.util.structGet(scenarioObjective, "ScenarioObjectiveOk", true)) && ...
    logical(sixgr.util.structGet(pdschObjective, "ObjectivePass", true)) && ...
    logical(configuredGate.ConfiguredEffectiveOk) && logical(runClassGate.ObjectiveGateOk) && ...
    logical(bindingGate.BindingGateOk) && ...
    ~(strictEligible && ~logical(claimGate.ClaimAllowed) && logical(claimGate.ObjectiveDependsOnClaim));

kpiGate = localKPIConsistencyGate(layout, meta, scfg, cfg, strictEligible);
kpiConsistencyOk = logical(kpiGate.KpiConsistencyOk);
visualArtifactGateOk = true;
duplicateArtifactGateOk = true;
standardsConformanceOk = logical(claimGate.ClaimAllowed) && logical(mandatoryGate.MandatorySubsystemsOk) && ...
    logical(conformanceGate.MandatoryMatrixOk) && logical(bindingGate.BindingGateOk) && ...
    ~logical(claimGate.ForbiddenBroadClaimRejected);

proxyEvidenceCount = double(sixgr.util.structGet(verdict, "StrictProxyGuardFailureCount", 0)) + ...
    double(sixgr.util.structGet(mandatoryGate, "ProxyEvidenceCount", 0));
skippedEvidenceCount = localFailureTokenCount(preRootFailures, ["skipped", "skip"]);
fallbackEvidenceCount = localFailureTokenCount(preRootFailures, ["fallback"]);

resultOk = logical(runCompleted) && logical(artifactsWritten) && logical(truthContractOk) && ...
    logical(runtimeTruthContractOk) && logical(standardsConformanceOk) && logical(scenarioObjectiveOk) && ...
    logical(configuredGate.ConfiguredEffectiveOk) && logical(mandatoryGate.MandatorySubsystemsOk) && ...
    logical(activeIssueGate.ActiveIssueGateOk) && logical(kpiConsistencyOk) && ...
    logical(visualArtifactGateOk) && logical(duplicateArtifactGateOk);

strictAnchorPass = ~strictEligible || resultOk;
failureReasons = localStatusFailureReasons(runCompleted, artifactsWritten, truthContractOk, ...
    standardsConformanceOk, scenarioObjectiveOk, configuredGate, runClassGate, bindingGate, mandatoryGate, activeIssueGate, ...
    kpiConsistencyOk, visualArtifactGateOk, duplicateArtifactGateOk);
resultReason = localResultReason(resultOk, failureReasons);

status = struct();
status.RunId = meta.RunId;
status.ScenarioName = meta.ScenarioName;
status.ScenarioClass = meta.ScenarioClass;
status.ScenarioMode = scenarioMode;
status.RunClass = runClassGate.RunClass;
status.ClaimProfile = claimGate.ClaimProfile;
status.ClaimStatus = claimGate.ClaimStatus;
status.ClaimAllowed = logical(claimGate.ClaimAllowed);
status.ClaimFailureReason = claimGate.ClaimFailureReason;
status.RunCompleted = logical(runCompleted);
status.RunCompletionReason = localRunCompletionReason(layout, runCompleted);
status.ArtifactsWritten = logical(artifactsWritten);
status.ArtifactCompletenessOk = logical(artifactsWritten);
status.TruthContractOk = logical(truthContractOk);
status.RuntimeTruthContractOk = logical(runtimeTruthContractOk);
status.StandardsConformanceOk = logical(standardsConformanceOk);
status.ScenarioObjectiveOk = logical(scenarioObjectiveOk);
status.ConfiguredEffectiveOk = logical(configuredGate.ConfiguredEffectiveOk);
status.RunClassGateOk = logical(runClassGate.ObjectiveGateOk);
status.PublicationLLSEligible = logical(runClassGate.PublicationLLSEligible);
status.PDCCHGrantBindingOk = logical(bindingGate.BindingGateOk);
status.PDCCHGrantBindingRequiredGrantCount = double(bindingGate.RequiredGrantCount);
status.PDCCHGrantBindingFailingGrantCount = double(bindingGate.FailingGrantCount);
status.MandatorySubsystemsOk = logical(mandatoryGate.MandatorySubsystemsOk);
status.ActiveIssueGateOk = logical(activeIssueGate.ActiveIssueGateOk);
status.KpiConsistencyOk = logical(kpiConsistencyOk);
status.VisualArtifactGateOk = logical(visualArtifactGateOk);
status.DuplicateArtifactGateOk = logical(duplicateArtifactGateOk);
status.ResultOk = logical(resultOk);
status.ResultStatusReason = resultReason;
status.ActiveCriticalIssueCount = double(activeIssueGate.ActiveCriticalIssueCount);
status.ActiveHighIssueCount = double(activeIssueGate.ActiveHighIssueCount);
status.ActiveMediumIssueCount = double(activeIssueGate.ActiveMediumIssueCount);
status.ActiveLowIssueCount = double(activeIssueGate.ActiveLowIssueCount);
status.ActiveMandatoryIssueCount = double(activeIssueGate.ActiveMandatoryIssueCount);
status.ActiveWaivedNonBlockingIssueCount = double(activeIssueGate.ActiveWaivedNonBlockingIssueCount);
status.ProxyEvidenceCount = double(proxyEvidenceCount);
status.SkippedEvidenceCount = double(skippedEvidenceCount);
status.FallbackEvidenceCount = double(fallbackEvidenceCount);
status.UnavailableMandatoryCount = double(mandatoryGate.UnavailableMandatoryCount);
status.PartialMandatoryCount = double(mandatoryGate.PartialMandatoryCount);
status.ReviewRequiredMandatoryCount = double(mandatoryGate.ReviewRequiredMandatoryCount);
status.DiagnosticOnlyMandatoryCount = double(mandatoryGate.DiagnosticOnlyMandatoryCount);
status.ConfiguredEffectiveMismatchCount = double(configuredGate.ConfiguredEffectiveMismatchCount);
status.StrictAnchorEligible = logical(strictEligible);
status.StrictAnchorPass = logical(strictAnchorPass);
status.RunClassReason = string(runClassGate.Reason);
status.StrictAnchorFailureReasons = string(strjoin(failureReasons, "; "));
status.ProducerModule = "sixgr.truth.evaluateStrictAnchorStatus";
status.GeneratedAt = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
status.SchemaVersion = "strict_anchor_status_v1";

statusT = localResultStatusTable(status);
sixgr.truth.validateResultStatusPayload(statusT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "result_status_summary.csv"), statusT);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "result_status_summary.json"), status);

sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "configured_effective_operating_point.csv"), configuredGate.Rows);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "configured_effective_operating_point_summary.json"), configuredGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "run_classification.csv"), runClassGate.Table);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "standards_claim_audit.csv"), claimGate.ClaimAudit);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "standards_claim_audit.json"), claimGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "public_output_claim_scan.csv"), claimGate.PublicClaimScan);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "public_output_claim_scan.json"), localTableJsonPayload(claimGate.PublicClaimScan));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "pdcch_grant_binding_evidence.csv"), bindingGate.Rows);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "pdcch_grant_binding_evidence.json"), bindingGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_objective_gates.csv"), ...
    localScenarioObjectiveGateTable(meta, status, configuredGate, runClassGate, claimGate, bindingGate, mandatoryGate, activeIssueGate));
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "scenario_objective_gates.json"), ...
    localTableJsonPayload(localScenarioObjectiveGateTable(meta, status, configuredGate, runClassGate, claimGate, bindingGate, mandatoryGate, activeIssueGate)));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "kpi_consistency_gate.csv"), kpiGate.Rows);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "kpi_consistency_gate.json"), kpiGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "active_issue_gate_summary.csv"), activeIssueGate.Rows);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "active_issue_gate_summary.json"), activeIssueGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "conformance_matrix_runtime_audit.csv"), conformanceGate.Rows);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "conformance_matrix_runtime_audit.json"), conformanceGate.Summary);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "strict_anchor_acceptance_report.csv"), ...
    localStrictAnchorAcceptanceTable(meta, status));
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "strict_anchor_acceptance_report.json"), ...
    localTableJsonPayload(localStrictAnchorAcceptanceTable(meta, status)));

localUpdateScenarioSummary(layout, status);

root = struct();
root.Status = status;
root.ConfiguredEffective = configuredGate;
root.RunClassification = runClassGate;
root.Claim = claimGate;
root.PDCCHGrantBinding = bindingGate;
root.MandatorySubsystems = mandatoryGate;
root.ActiveIssueGate = activeIssueGate;
root.ConformanceMatrix = conformanceGate;
root.KPIConsistency = kpiGate;
root.Failures = localRootFailures(status, claimGate, configuredGate, bindingGate, mandatoryGate, activeIssueGate, kpiGate);
end

function localEnsureRootDirs(layout)
sixgr.util.ensureDir(fullfile(layout.ReportCSVDir, ".keep"));
sixgr.util.ensureDir(fullfile(layout.ReportDir, "json", ".keep"));
end

function meta = localMetadata(layout, scfg, cfg)
scenarioName = localFirstNonBlankString([
    localScenarioGet(scfg, cfg, "scenario.name", "")
    localScenarioGet(scfg, cfg, "meta.scenario_name", "")
    localScenarioGet(scfg, cfg, "scenario_id", "")
    localScenarioGet(scfg, cfg, "meta.scenario_id", "")
    localScenarioGet(scfg, cfg, "scenario.id", "")
    ]);
scenarioId = localFirstNonBlankString([
    localScenarioGet(scfg, cfg, "scenario_id", "")
    localScenarioGet(scfg, cfg, "meta.scenario_id", "")
    localScenarioGet(scfg, cfg, "scenario.id", "")
    scenarioName
    ]);
runTag = localFirstNonBlankString([
    localScenarioGet(scfg, cfg, "run.runTag", "")
    localScenarioGet(scfg, cfg, "run_tag", "")
    scenarioId
    ]);
scenarioClass = localFirstNonBlankString([
    localScenarioGet(scfg, cfg, "scenario.class", "")
    localScenarioGet(scfg, cfg, "meta.scenario_group", "")
    localScenarioGet(scfg, cfg, "meta.maturity_tag", "")
    "lls_runtime"
    ]);
configHash = localFirstNonBlankString([
    localScenarioGet(scfg, cfg, "meta.configHash", "")
    localScenarioGet(scfg, cfg, "config_hash", "")
    ]);

summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
scenarioId = localFirstTableValue(scenarioId, summary, ["ScenarioID", "ScenarioId", "scenario_id"]);
runTag = localFirstTableValue(runTag, summary, ["RunTag", "run_tag"]);

meta = struct( ...
    "RunId", runTag, ...
    "ScenarioID", scenarioId, ...
    "ScenarioName", scenarioName, ...
    "ScenarioClass", scenarioClass, ...
    "ConfigHash", configHash);
end

function required = localRequiredDirections(scfg, cfg)
direction = lower(strtrim(string(localScenarioGet(scfg, cfg, "simulation.link_direction", "both"))));
if strlength(direction) == 0 || direction == "all"
    direction = "both";
end
required = struct();
required.DL = any(direction == ["both", "dl", "downlink"]);
required.UL = any(direction == ["both", "ul", "uplink"]);
end

function mode = localScenarioMode(scfg, cfg)
explicit = lower(strtrim(localFirstNonBlankString([
    localScalarString(localScenarioGet(scfg, cfg, "scenario.scenario_mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "scenario.mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "validation.scenario_mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.operating_point_mode", ""))
    ])));
if any(explicit == ["fixed_anchor", "adaptive_link", "outage_study"])
    mode = explicit;
    return;
end
tokens = lower(strtrim(string([
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.fixed_or_amc", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pdsch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pusch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.dlPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.ulPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "mimo.rank_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.rankPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "scenario.objective", ""))
    ])));
tokens = tokens(strlength(tokens) > 0);
if any(contains(tokens, ["outage", "stress", "failure_study"]))
    mode = "outage_study";
elseif any(ismember(tokens, ["amc", "adaptive", "cqi", "cqi_driven", "actual_bler_based"]))
    mode = "adaptive_link";
elseif any(ismember(tokens, ["fixed", "fixed_mcs", "configured_fixed", "disabled", "off", "none", "false"]))
    mode = "fixed_anchor";
else
    mode = "nr_baseline_study";
end
end

function profile = localResolveRunClassProfile(scfg, cfg, scenarioMode)
explicit = localNormalizeRunClassToken(localFirstNonBlankString([
    localScalarString(localScenarioGet(scfg, cfg, "validation.RunClass", ""))
    localScalarString(localScenarioGet(scfg, cfg, "validation.run_class", ""))
    localScalarString(localScenarioGet(scfg, cfg, "validation.runClass", ""))
    ]));
configured = localConfiguredOperatingPoint(scfg, cfg);
fixedMCSActive = localRunClassFixedMCSActive(scfg, cfg);
rankFixed = localRunClassRankFixed(scfg, cfg);
layersFixed = localRunClassLayersFixed(configured);
modulationFixed = localRunClassModulationFixed(configured, fixedMCSActive);
adaptiveMode = localRunClassAdaptiveMode(scfg, cfg, scenarioMode);
fixedCampaignEnabled = localScenarioGetBool(scfg, cfg, "validation.fixed_link_campaign.enabled", false);

runClass = explicit;
if strlength(runClass) == 0
    if fixedCampaignEnabled && adaptiveMode
        runClass = "hybrid_validation";
    elseif fixedMCSActive && rankFixed && layersFixed && modulationFixed && ~adaptiveMode
        runClass = "fixed_lls_anchor";
    else
        % Bias away from publication-safe anchor claims unless the config proves them.
        runClass = "adaptive_system_diagnostic";
    end
end

profile = struct( ...
    "RunClass", string(runClass), ...
    "FixedMCSActive", logical(fixedMCSActive), ...
    "RankFixed", logical(rankFixed), ...
    "LayersFixed", logical(layersFixed), ...
    "ModulationFixed", logical(modulationFixed), ...
    "AdaptiveMode", logical(adaptiveMode), ...
    "FixedLinkCampaignEnabled", logical(fixedCampaignEnabled), ...
    "Configured", configured);
end

function gate = localRunClassificationGate(layout, meta, required, configuredGate, profile)
[exactRate, matchCount, eligibleCount] = localConfiguredExactMatchAggregate(configuredGate.Rows, required);
runClass = string(profile.RunClass);
publicationEligible = false;
objectiveGateOk = true;

switch runClass
    case "fixed_lls_anchor"
        publicationEligible = logical(configuredGate.ConfiguredEffectiveOk) && eligibleCount > 0;
        if publicationEligible
            reason = "fixed_lls_anchor exact configured/effective match rate " + ...
                string(matchCount) + "/" + string(eligibleCount) + " meets the >=0.99 publication threshold.";
        else
            reason = "fixed_lls_anchor exact configured/effective match rate " + ...
                string(matchCount) + "/" + string(eligibleCount) + " is below the >=0.99 publication threshold.";
        end
    case "adaptive_system_diagnostic"
        publicationEligible = false;
        reason = "adaptive_system_diagnostic permits configured/effective runtime divergence diagnostically; fixed-link publication claim is disabled.";
    case "hybrid_validation"
        [fixedCampaignOk, fixedCampaignReason] = localFixedLinkCampaignEvidenceStatus(layout, required);
        [adaptiveOutputsOk, adaptiveOutputsReason] = localAdaptiveScenarioOutputStatus(configuredGate.Rows, required);
        objectiveGateOk = fixedCampaignOk && adaptiveOutputsOk;
        publicationEligible = objectiveGateOk;
        if objectiveGateOk
            reason = "hybrid_validation has fixed-link campaign curves with confidence intervals and adaptive scenario outputs.";
        else
            reason = strjoin([fixedCampaignReason; adaptiveOutputsReason], "; ");
        end
    case "fixed_snr_sweep_lls"
        publicationEligible = false;
        objectiveGateOk = true;
        reason = "fixed_snr_sweep_lls is a dedicated fixed-link sweep validation mode; publication fixed-anchor claims remain disabled while the fixed-sweep audit provides the correctness gate.";
    case "ue_placement_geometry_lls"
        publicationEligible = false;
        objectiveGateOk = true;
        reason = "ue_placement_geometry_lls is a dedicated geometry and mobility validation mode; publication fixed-anchor claims remain disabled while geometry evidence gates provide the correctness gate.";
    otherwise
        publicationEligible = false;
        objectiveGateOk = false;
        reason = "unrecognized run_class '" + runClass + "'";
end

tableOut = table( ...
    string(runClass), ...
    logical(profile.FixedMCSActive), ...
    logical(profile.RankFixed), ...
    logical(profile.ModulationFixed), ...
    logical(profile.AdaptiveMode), ...
    localConfiguredDirectionalToken(profile.Configured, required, "MCS"), ...
    localConfiguredDirectionalToken(profile.Configured, required, "Modulation"), ...
    localConfiguredDirectionalToken(profile.Configured, required, "Rank"), ...
    localConfiguredDirectionalToken(profile.Configured, required, "Layers"), ...
    double(exactRate), ...
    logical(publicationEligible), ...
    string(reason), ...
    'VariableNames', {'RunClass','FixedMCSActive','RankFixed','ModulationFixed','AdaptiveMode', ...
    'ConfiguredMCS','ConfiguredModulation','ConfiguredRank','ConfiguredLayers', ...
    'ExactConfiguredEffectiveMatchRate','PublicationLLSEligible','Reason'});

gate = struct();
gate.RunClass = string(runClass);
gate.PublicationLLSEligible = logical(publicationEligible);
gate.ObjectiveGateOk = logical(objectiveGateOk);
gate.ExactConfiguredEffectiveMatchRate = double(exactRate);
gate.ExactMatchCount = double(matchCount);
gate.StrictEligibleCount = double(eligibleCount);
gate.Reason = string(reason);
gate.Table = tableOut;
gate.Meta = struct("RunId", meta.RunId, "ScenarioName", meta.ScenarioName);
end

function token = localConfiguredDirectionalToken(configured, required, fieldName)
values = strings(0, 1);
if logical(required.DL)
    values(end+1, 1) = "DL=" + localConfiguredValueToken(configured.DL, fieldName); %#ok<AGROW>
end
if logical(required.UL)
    values(end+1, 1) = "UL=" + localConfiguredValueToken(configured.UL, fieldName); %#ok<AGROW>
end
if isempty(values)
    token = localConfiguredValueToken(configured.DL, fieldName);
elseif numel(values) == 1
    token = extractAfter(values(1), 3);
elseif numel(values) == 2 && extractAfter(values(1), 3) == extractAfter(values(2), 3)
    token = extractAfter(values(1), 3);
else
    token = strjoin(values, "|");
end
end

function token = localConfiguredValueToken(directionCfg, fieldName)
value = directionCfg.(char(fieldName));
if isnumeric(value)
    if isfinite(double(value))
        token = string(sprintf("%.0f", double(value)));
    else
        token = "NaN";
    end
else
    token = string(value);
    if strlength(strtrim(token)) == 0
        token = "unspecified";
    end
end
end

function [rate, matchCount, eligibleCount] = localConfiguredExactMatchAggregate(rows, required)
rate = NaN;
matchCount = 0;
eligibleCount = 0;
if ~(istable(rows) && height(rows) > 0)
    return;
end
dir = upper(string(localColumnOrDefault(rows, "Direction", "")));
requiredMask = false(height(rows), 1);
if logical(required.DL)
    requiredMask = requiredMask | dir == "DL";
end
if logical(required.UL)
    requiredMask = requiredMask | dir == "UL";
end
if ~any(requiredMask)
    requiredMask = true(height(rows), 1);
end
eligible = requiredMask & localToLogical(localColumnOrDefault(rows, "StrictEligible", false));
eligibleCount = double(sum(eligible));
if eligibleCount <= 0
    return;
end
match = localToLogical(localColumnOrDefault(rows, "ExactOperatingPointMatch", false));
matchCount = double(sum(eligible & match));
rate = matchCount / eligibleCount;
end

function [ok, reason] = localFixedLinkCampaignEvidenceStatus(layout, required)
summaryPath = fullfile(layout.ReportCSVDir, "fixed_link_campaign_summary.csv");
summaryT = localReadTable(summaryPath);
if ~(istable(summaryT) && height(summaryT) > 0)
    ok = false;
    reason = "hybrid_validation is missing fixed-link campaign evidence in reports/csv/fixed_link_campaign_summary.csv";
    return;
end

direction = upper(string(localColumnOrDefault(summaryT, "Direction", "")));
mask = false(height(summaryT), 1);
if logical(required.DL)
    mask = mask | direction == "DL";
end
if logical(required.UL)
    mask = mask | direction == "UL";
end
if ~any(mask)
    mask = true(height(summaryT), 1);
end

curvePresent = localToLogical(localColumnOrDefault(summaryT(mask, :), "CurvePresent", false));
ciPresent = localToLogical(localColumnOrDefault(summaryT(mask, :), "ConfidenceIntervalsPresent", false));
ok = any(mask) && all(curvePresent & ciPresent);
if ok
    reason = "fixed-link campaign report summary confirms non-empty curves with confidence intervals.";
else
    reason = "hybrid_validation requires fixed-link campaign curves with confidence intervals in reports/csv/fixed_link_campaign_summary.csv";
end
end

function [ok, reason] = localAdaptiveScenarioOutputStatus(rows, required)
if ~(istable(rows) && height(rows) > 0)
    ok = false;
    reason = "hybrid_validation is missing adaptive scenario operating-point rows.";
    return;
end
dir = upper(string(localColumnOrDefault(rows, "Direction", "")));
mask = false(height(rows), 1);
if logical(required.DL)
    mask = mask | dir == "DL";
end
if logical(required.UL)
    mask = mask | dir == "UL";
end
if ~any(mask)
    mask = true(height(rows), 1);
end

strictEligible = localToLogical(localColumnOrDefault(rows, "StrictEligible", false));
adaptiveRows = localToLogical(localColumnOrDefault(rows, "AdaptiveMode", false));
ok = any(mask & strictEligible & adaptiveRows);
if ok
    reason = "adaptive scenario outputs are present in configured/effective operating-point rows.";
else
    reason = "hybrid_validation requires adaptive scenario outputs alongside the fixed-link campaign evidence.";
end
end

function tf = localRunClassFixedMCSActive(scfg, cfg)
tokens = lower(strtrim(string([
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.fixed_or_amc", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pdsch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pusch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.dlPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.ulPolicy", ""))
    ])));
tokens = tokens(strlength(tokens) > 0);
fixedTokens = localRunClassFixedTokens();
adaptiveTokens = localRunClassAdaptiveTokens();
tf = localScenarioGetBool(scfg, cfg, "pdsch6gr.FixedMCSActive", false) || ...
    (any(ismember(tokens, fixedTokens)) && ~any(ismember(tokens, adaptiveTokens)));
end

function tf = localRunClassRankFixed(scfg, cfg)
tokens = lower(strtrim(string([
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.rank_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "mimo.rank_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.rankPolicy", ""))
    ])));
tokens = tokens(strlength(tokens) > 0);
fixedTokens = localRunClassFixedTokens();
adaptiveTokens = localRunClassAdaptiveTokens();
tf = any(ismember(tokens, fixedTokens)) && ~any(ismember(tokens, adaptiveTokens));
end

function tf = localRunClassLayersFixed(configured)
dl = double(configured.DL.Layers);
ul = double(configured.UL.Layers);
tf = (isfinite(dl) && dl >= 1) || (isfinite(ul) && ul >= 1);
end

function tf = localRunClassModulationFixed(configured, fixedMCSActive)
mods = strtrim(string([configured.DL.Modulation; configured.UL.Modulation]));
mods = mods(strlength(mods) > 0);
tf = logical(fixedMCSActive) && ~isempty(mods);
end

function tf = localRunClassAdaptiveMode(scfg, cfg, scenarioMode)
tokens = lower(strtrim(string([
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.fixed_or_amc", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.mode", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pdsch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.pusch_link_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.dlPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.ulPolicy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "link_adaptation.rank_adaptation_policy", ""))
    localScalarString(localScenarioGet(scfg, cfg, "phy.linkAdaptation.rankPolicy", ""))
    string(scenarioMode)
    ])));
tokens = tokens(strlength(tokens) > 0);
tf = any(ismember(tokens, localRunClassAdaptiveTokens())) || scenarioMode == "adaptive_link";
end

function token = localNormalizeRunClassToken(raw)
token = lower(strtrim(string(raw)));
if any(token == ["fixed_lls_anchor", "adaptive_system_diagnostic", "hybrid_validation", ...
        "fixed_snr_sweep_lls", "ue_placement_geometry_lls"])
    return;
end
token = "";
end

function tokens = localRunClassFixedTokens()
tokens = ["fixed", "fixed_mcs", "configured_fixed", "disabled", "off", "none", "false"];
end

function tokens = localRunClassAdaptiveTokens()
tokens = ["amc", "adaptive", "dynamic", "dynamic_link_adaptation", "cqi", "cqi_driven", ...
    "baseline", "actual_bler_based", "effective_sinr_driven", "adaptive_link"];
end

function tf = localStrictAnchorEligible(scfg, cfg, scenarioMode, meta)
honesty = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.honesty_mode", ""))));
profile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
text = lower(strjoin([meta.ScenarioName; meta.ScenarioID; meta.ScenarioClass; scenarioMode], " "));
tf = honesty == "strict" || contains(text, "strict") || contains(text, "anchor") || ...
    contains(text, "truth") || profile == "waveform_bundle" || scenarioMode == "fixed_anchor";
end

function tf = localRunCompleted(layout)
summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
tf = false;
if isempty(summary) || height(summary) == 0
    return;
end
status = lower(strtrim(string(localColumnOrDefault(summary, "RunCompletion", ""))));
if all(strlength(status) == 0)
    status = lower(strtrim(string(localColumnOrDefault(summary, "Status", ""))));
end
ok = localColumnOrDefault(summary, "ResultOk", false);
tf = any(ismember(status, ["completed", "completed_with_failures", "complete", "success", "finished", "true", "1"])) || any(localToLogical(ok));
end

function reason = localRunCompletionReason(layout, runCompleted)
summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
reason = "missing_scenario_summary";
if ~isempty(summary) && height(summary) > 0
    raw = string(localColumnOrDefault(summary, "RunCompletion", ""));
    raw = raw(1);
    if strlength(strtrim(raw)) > 0
        reason = raw;
    elseif runCompleted
        reason = "completed_inferred_from_legacy_resultok";
    else
        reason = "run_completion_not_terminal";
    end
end
end

function gate = localKPIConsistencyGate(layout, meta, scfg, cfg, strictEligible)
summaryPath = fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv");
reconPath = fullfile(layout.ReportCSVDir, "kpi_reconstruction_summary.csv");
summaryT = localReadTable(summaryPath);
reconT = localReadTable(reconPath);
kpiRequired = logical(strictEligible) && (isfile(summaryPath) || isfile(reconPath) || ...
    localScenarioGetBool(scfg, cfg, "kpi.required", false));

rows = localKpiGateRows(meta, kpiRequired, summaryPath, reconPath, summaryT, reconT);
failMask = localToLogical(localColumnOrDefault(rows, "Required", false)) & ...
    ~localToLogical(localColumnOrDefault(rows, "Pass", false));
gate = struct();
gate.Rows = rows;
gate.KpiConsistencyOk = ~any(failMask);
gate.KPIFailureCount = double(sum(failMask));
gate.FailureReasons = string(localColumnOrDefault(rows(failMask, :), "FailureReason", ""));
gate.Summary = struct( ...
    "RunId", meta.RunId, ...
    "ScenarioName", meta.ScenarioName, ...
    "Required", logical(kpiRequired), ...
    "KpiConsistencyOk", logical(gate.KpiConsistencyOk), ...
    "KPIFailureCount", double(gate.KPIFailureCount), ...
    "FailureReasons", string(strjoin(gate.FailureReasons, "; ")), ...
    "SummaryArtifact", "reports/csv/kpi_consistency_gate.csv");
end

function rows = localKpiGateRows(meta, required, summaryPath, reconPath, summaryT, reconT)
schemaNames = {'RunId','ScenarioName','GateName','Required','Pass','EvidenceArtifact','FailureCount','FailureReason'};
schemaTypes = {'string','string','string','logical','logical','string','double','string'};
rows = table('Size', [0 numel(schemaNames)], 'VariableTypes', schemaTypes, 'VariableNames', schemaNames);
rows = localAppendKpiGateRow(rows, meta, "kpi_summary_present", required, ...
    ~required || (istable(summaryT) && height(summaryT) > 0), summaryPath, 0, "missing_lls_kpi_summary");
rows = localAppendKpiGateRow(rows, meta, "kpi_reconstruction_present", required, ...
    ~required || (istable(reconT) && height(reconT) > 0), reconPath, 0, "missing_kpi_reconstruction_summary");
if ~(required && istable(summaryT) && height(summaryT) > 0)
    summaryOk = ~required;
    summaryFail = double(required && ~(istable(summaryT) && height(summaryT) > 0));
else
    summaryStrict = localOptionalBoolColumn(summaryT, "StrictOk", true);
    summaryRecon = localOptionalBoolColumn(summaryT, "KPIReconciliationPass", true);
    summaryStatus = lower(strtrim(string(localColumnOrDefault(summaryT, "Status", "pass"))));
    summaryReason = strtrim(string(localColumnOrDefault(summaryT, "FailureReason", "")));
    bad = ~summaryStrict | ~summaryRecon | ismember(summaryStatus, ["fail", "failed", "error"]) | ...
        (strlength(summaryReason) > 0 & ~ismissing(summaryReason));
    summaryOk = ~any(bad);
    summaryFail = double(sum(bad));
end
rows = localAppendKpiGateRow(rows, meta, "kpi_summary_strict_reconciled", required, ...
    summaryOk, summaryPath, summaryFail, "measured_sinr_kpi_summary_not_strict_or_reconciled");

if ~(required && istable(reconT) && height(reconT) > 0)
    reconOk = ~required;
    reconFail = double(required && ~(istable(reconT) && height(reconT) > 0));
else
    reconStrict = localOptionalBoolColumn(reconT, "StrictOk", true);
    reconPass = localOptionalBoolColumn(reconT, "ReconciliationPass", true);
    formula = localOptionalBoolColumn(reconT, "FormulaExecuted", true);
    schema = localOptionalBoolColumn(reconT, "SchemaValid", true);
    missingRaw = localOptionalBoolColumn(reconT, "MissingRawData", false);
    duration = lower(strtrim(string(localColumnOrDefault(reconT, "DurationSource", ""))));
    status = lower(strtrim(string(localColumnOrDefault(reconT, "Status", "pass"))));
    reason = strtrim(string(localColumnOrDefault(reconT, "FailureReason", "")));
    bad = ~reconStrict | ~reconPass | ~formula | ~schema | missingRaw | ...
        ismember(duration, ["", "unavailable", "nan", "<missing>"]) | ...
        ismember(status, ["fail", "failed", "error"]) | ...
        (strlength(reason) > 0 & ~ismissing(reason));
    reconOk = ~any(bad);
    reconFail = double(sum(bad));
end
rows = localAppendKpiGateRow(rows, meta, "kpi_reconstruction_rows_strict", required, ...
    reconOk, reconPath, reconFail, "measured_sinr_kpi_reconstruction_failed_formula_duration_or_reconciliation_rows");
end

function rows = localAppendKpiGateRow(rows, meta, name, required, pass, artifact, count, reason)
if pass
    reason = "";
    count = 0;
end
rows(end+1, :) = {meta.RunId, meta.ScenarioName, string(name), logical(required), ...
    logical(pass), string(localRelativeReportPath(meta, artifact)), double(count), string(reason)}; %#ok<AGROW>
end

function values = localOptionalBoolColumn(T, name, defaultValue)
if localHasColumn(T, name)
    values = localToLogical(T.(char(string(name))));
else
    values = repmat(logical(defaultValue), height(T), 1);
end
end

function rel = localRelativeReportPath(meta, pathValue) %#ok<INUSD>
pathText = char(string(pathValue));
idx = strfind(pathText, ['air_interface' filesep]);
if isempty(idx)
    idx = strfind(pathText, ['reports' filesep]);
end
if isempty(idx)
    rel = replace(string(pathText), "\", "/");
else
    rel = replace(string(pathText(idx(1):end)), "\", "/");
end
end

function gate = localConfiguredEffectiveGate(layout, meta, scfg, cfg, dlTrials, ulTrials, opSummary, required, scenarioMode, strictEligible, runClassProfile)
configured = localConfiguredOperatingPoint(scfg, cfg);
dlRows = localConfiguredEffectiveRows(meta, "DL", dlTrials, configured.DL, scenarioMode, runClassProfile.RunClass);
ulRows = localConfiguredEffectiveRows(meta, "UL", ulTrials, configured.UL, scenarioMode, runClassProfile.RunClass);
rows = [dlRows; ulRows];
threshold = localScenarioDouble(scfg, cfg, ["scenario.required_configured_match_rate", "validation.required_configured_match_rate"], 0.999);

[dlRate, dlCount] = localExactMatchRate(rows, "DL");
[ulRate, ulCount] = localExactMatchRate(rows, "UL");
if isstruct(opSummary)
    dlRate = localFirstFinite([dlRate; localNestedDouble(opSummary, ["DL", "ConfiguredMatchRate"], NaN)]);
    ulRate = localFirstFinite([ulRate; localNestedDouble(opSummary, ["UL", "ConfiguredMatchRate"], NaN)]);
end

fixed = runClassProfile.RunClass == "fixed_lls_anchor";
adaptive = any(runClassProfile.RunClass == ["adaptive_system_diagnostic", "hybrid_validation"]);
missing = strings(0, 1);
if fixed && required.DL && dlCount <= 0
    missing(end+1, 1) = "missing_dl_configured_effective_rows"; %#ok<AGROW>
end
if fixed && required.UL && ulCount <= 0
    missing(end+1, 1) = "missing_ul_configured_effective_rows"; %#ok<AGROW>
end
if fixed && required.DL && ~(isfinite(dlRate) && dlRate + eps >= threshold)
    missing(end+1, 1) = "dl_exact_match_rate_below_required:" + string(sprintf("%.6g", dlRate)); %#ok<AGROW>
end
if fixed && required.UL && ~(isfinite(ulRate) && ulRate + eps >= threshold)
    missing(end+1, 1) = "ul_exact_match_rate_below_required:" + string(sprintf("%.6g", ulRate)); %#ok<AGROW>
end

mismatchCount = 0;
if height(rows) > 0 && ismember("StrictEligible", string(rows.Properties.VariableNames))
    mismatchCount = sum(logical(rows.StrictEligible) & ~logical(rows.ExactOperatingPointMatch));
end
ok = ~fixed || isempty(missing);

summary = struct();
summary.RunId = meta.RunId;
summary.ScenarioName = meta.ScenarioName;
summary.ScenarioMode = scenarioMode;
summary.RunClass = runClassProfile.RunClass;
summary.FixedAnchor = logical(fixed);
summary.AdaptiveMode = logical(adaptive);
summary.RequiredConfiguredMatchRate = double(threshold);
summary.DLExactMatchRate = double(dlRate);
summary.ULExactMatchRate = double(ulRate);
summary.DLStrictEligibleRows = double(dlCount);
summary.ULStrictEligibleRows = double(ulCount);
summary.ConfiguredEffectiveMismatchCount = double(mismatchCount);
summary.ConfiguredEffectiveOk = logical(ok);
summary.FailureReason = string(strjoin(missing, "; "));
summary.StrictAnchorEligible = logical(strictEligible);
summary.Artifact = "reports/csv/configured_effective_operating_point.csv";

gate = struct();
gate.Rows = rows;
gate.Summary = summary;
gate.ConfiguredEffectiveOk = logical(ok);
gate.ConfiguredEffectiveMismatchCount = double(mismatchCount);
gate.RequiredConfiguredMatchRate = double(threshold);
gate.DLExactMatchRate = double(dlRate);
gate.ULExactMatchRate = double(ulRate);
gate.FailureReasons = missing;
end

function rows = localConfiguredEffectiveRows(meta, direction, T, configured, scenarioMode, runClass)
schema = localConfiguredEffectiveSchema();
if ~(istable(T) && height(T) > 0)
    rows = localEmptyTable(schema);
    return;
end
n = height(T);
strictEligible = ~localColumnBoolDefault(T, "IsWarmupFrame", false) & ~localColumnBoolDefault(T, "PartialRowFlag", false);
outage = false(n, 1);
if localHasColumn(T, "CRCPass")
    outage = ~localToLogical(T.CRCPass);
end
adaptive = repmat(any(string(runClass) == ["adaptive_system_diagnostic", "hybrid_validation"]), n, 1);

effectiveRank = localFirstNumericColumn(T, ["EffectiveRank", "Rank", "RankIndicator", "RI", "Layers", "NumLayers"]);
effectiveLayers = localFirstNumericColumn(T, ["EffectiveLayers", "Layers", "NumLayers", "NLayers"]);
effectiveMod = localFirstStringColumn(T, ["EffectiveModulation", "Modulation", "AppliedModulation", "SelectedModulation"]);
effectiveMCS = localFirstNumericColumn(T, ["EffectiveMCS", "EffectiveMCSIndex", "MCS", "MCSIndex", "SelectedMCS"]);
effectiveTable = localFirstStringColumn(T, ["EffectiveMCSTable", "MCSTable", "McsTable", "MCS_Table"]);
effectiveTBS = localFirstNumericColumn(T, ["EffectiveTBS", "TBS", "TBSBits", "TBSize_bits", "TBSizeBits"]);

scheduledRank = localFirstNumericColumn(T, ["ScheduledRank", "ScheduledRI", "ScheduledLayers"]);
scheduledLayers = localFirstNumericColumn(T, ["ScheduledLayers", "ScheduledNumLayers"]);
scheduledMod = localFirstStringColumn(T, ["ScheduledModulation", "ScheduledMod"]);
scheduledMCS = localFirstNumericColumn(T, ["ScheduledMCS", "ScheduledMCSIndex", "GrantMCSIndex"]);
scheduledTable = localFirstStringColumn(T, ["ScheduledMCSTable", "GrantMCSTable"]);
scheduledTBS = localFirstNumericColumn(T, ["ScheduledTBS", "ScheduledTBSBits", "GrantTBSBits"]);

transmittedRank = localFirstNumericColumn(T, ["TransmittedRank", "TxRank", "TransmittedLayers"]);
transmittedLayers = localFirstNumericColumn(T, ["TransmittedLayers", "TxLayers"]);
transmittedMod = localFirstStringColumn(T, ["TransmittedModulation", "TxModulation"]);
transmittedMCS = localFirstNumericColumn(T, ["TransmittedMCS", "TransmittedMCSIndex", "TxMCSIndex"]);
transmittedTable = localFirstStringColumn(T, ["TransmittedMCSTable", "TxMCSTable"]);
transmittedTBS = localFirstNumericColumn(T, ["TransmittedTBS", "TransmittedTBSBits", "TxTBSBits"]);

configuredRank = repmat(double(configured.Rank), n, 1);
configuredLayers = repmat(double(configured.Layers), n, 1);
configuredMod = repmat(string(configured.Modulation), n, 1);
configuredMCS = repmat(double(configured.MCS), n, 1);
configuredTable = repmat(string(configured.MCSTable), n, 1);
configuredTBS = repmat(double(configured.TBS), n, 1);

exact = true(n, 1);
mismatchFields = strings(n, 1);
mismatchCause = strings(n, 1);
for ii = 1:n
    fields = strings(0, 1);
    if isfinite(configuredRank(ii)) && isfinite(effectiveRank(ii)) && configuredRank(ii) ~= effectiveRank(ii)
        fields(end+1, 1) = "rank"; %#ok<AGROW>
    elseif isfinite(configuredRank(ii)) && ~isfinite(effectiveRank(ii))
        fields(end+1, 1) = "rank_missing"; %#ok<AGROW>
    end
    if isfinite(configuredLayers(ii)) && isfinite(effectiveLayers(ii)) && configuredLayers(ii) ~= effectiveLayers(ii)
        fields(end+1, 1) = "layers"; %#ok<AGROW>
    elseif isfinite(configuredLayers(ii)) && ~isfinite(effectiveLayers(ii))
        fields(end+1, 1) = "layers_missing"; %#ok<AGROW>
    end
    if strlength(configuredMod(ii)) > 0 && strlength(effectiveMod(ii)) > 0 && ~localModulationEqual(configuredMod(ii), effectiveMod(ii))
        fields(end+1, 1) = "modulation"; %#ok<AGROW>
    elseif strlength(configuredMod(ii)) > 0 && strlength(effectiveMod(ii)) == 0
        fields(end+1, 1) = "modulation_missing"; %#ok<AGROW>
    end
    if isfinite(configuredMCS(ii)) && isfinite(effectiveMCS(ii)) && configuredMCS(ii) ~= effectiveMCS(ii)
        fields(end+1, 1) = "mcs"; %#ok<AGROW>
    elseif isfinite(configuredMCS(ii)) && ~isfinite(effectiveMCS(ii))
        fields(end+1, 1) = "mcs_missing"; %#ok<AGROW>
    end
    if isempty(fields)
        mismatchFields(ii) = "";
        mismatchCause(ii) = "";
    else
        exact(ii) = false;
        mismatchFields(ii) = strjoin(fields, "|");
        mismatchCause(ii) = "configured_effective_mismatch";
    end
end

rows = table( ...
    repmat(meta.RunId, n, 1), repmat(meta.ScenarioName, n, 1), repmat(string(direction), n, 1), ...
    localFirstNumericColumn(T, ["CellId", "CellID", "Cell", "GNBId"]), ...
    localFirstNumericColumn(T, ["UEId", "UEID", "UEIndex", "RNTI"]), ...
    localFirstNumericColumn(T, ["Slot", "SlotIndex", "NSlot"]), ...
    localFirstStringOrNumericAsString(T, ["TrialId", "TrialID", "TBId", "TransportBlockId"]), ...
    repmat(string(scenarioMode), n, 1), repmat(string(runClass), n, 1), ...
    configuredRank, scheduledRank, transmittedRank, effectiveRank, ...
    configuredLayers, scheduledLayers, transmittedLayers, effectiveLayers, ...
    configuredMod, scheduledMod, transmittedMod, effectiveMod, ...
    configuredMCS, scheduledMCS, transmittedMCS, effectiveMCS, ...
    configuredTable, effectiveTable, configuredTBS, effectiveTBS, ...
    localFirstStringOrNumericAsString(T, ["GrantId", "GrantID", "SchedulerGrantId"]), ...
    localFirstStringOrNumericAsString(T, ["SchedulerDecisionId", "DecisionId"]), ...
    localFirstStringOrNumericAsString(T, ["TxEvidenceId", "TransmitEvidenceId"]), ...
    localFirstStringOrNumericAsString(T, ["RxEvidenceId", "ReceiverEvidenceId"]), ...
    strictEligible, strictEligible, outage, adaptive, ...
    localFirstStringOrNumericAsString(T, ["AdaptationEvidenceId", "CQIEvidenceId", "LinkAdaptationEvidenceId"]), ...
    exact, mismatchFields, mismatchCause, ...
    repmat("AUD-002", n, 1), ...
    'VariableNames', schema.Names);
rows.IssueIdIfFailed(rows.ExactOperatingPointMatch) = "";
end

function schema = localConfiguredEffectiveSchema()
schema.Names = {'RunId','ScenarioName','Direction','CellId','UEId','Slot','TrialId','ScenarioMode','RunClass', ...
    'ConfiguredRank','ScheduledRank','TransmittedRank','EffectiveRank', ...
    'ConfiguredLayers','ScheduledLayers','TransmittedLayers','EffectiveLayers', ...
    'ConfiguredModulation','ScheduledModulation','TransmittedModulation','EffectiveModulation', ...
    'ConfiguredMCS','ScheduledMCS','TransmittedMCS','EffectiveMCS', ...
    'ConfiguredMCSTable','EffectiveMCSTable','ConfiguredTBS','EffectiveTBS', ...
    'GrantId','SchedulerDecisionId','TxEvidenceId','RxEvidenceId', ...
    'StrictEligible','ObjectiveEligible','OutageRow','AdaptiveMode','AdaptationEvidenceId', ...
    'ExactOperatingPointMatch','MismatchFields','MismatchCause','IssueIdIfFailed'};
schema.Types = {'string','string','string','double','double','double','string','string','string', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'string','string','string','string', ...
    'double','double','double','double', ...
    'string','string','double','double', ...
    'string','string','string','string', ...
    'logical','logical','logical','logical','string', ...
    'logical','string','string','string'};
end

function configured = localConfiguredOperatingPoint(scfg, cfg)
layers = localScenarioDouble(scfg, cfg, ["mimo.n_layers", "pdsch.n_layers", "pusch.n_layers", "phy.mimo.nLayers"], NaN);
configured = struct();
configured.DL = struct( ...
    "Rank", localScenarioDouble(scfg, cfg, ["mimo.dl_rank", "pdsch.rank", "mimo.n_layers"], layers), ...
    "Layers", localScenarioDouble(scfg, cfg, ["mimo.dl_layers", "pdsch.n_layers", "mimo.n_layers"], layers), ...
    "Modulation", localConfiguredModulation(scfg, cfg, ["pdsch.modulation", "modulation.dl_modulation_order", "modulation_and_mapping.pdsch_modulation"]), ...
    "MCS", localScenarioDouble(scfg, cfg, ["modulation.dl_mcs_index", "pdsch.mcs_index", "pdsch.MCSIndex", "phy.dl.mcsIndex"], NaN), ...
    "MCSTable", string(localScenarioGet(scfg, cfg, "pdsch.mcs_table", localScenarioGet(scfg, cfg, "modulation.dl_mcs_table", ""))), ...
    "TBS", localScenarioDouble(scfg, cfg, ["pdsch.tbs", "pdsch.tbs_bits"], NaN));
configured.UL = struct( ...
    "Rank", localScenarioDouble(scfg, cfg, ["mimo.ul_rank", "pusch.rank", "mimo.n_layers"], layers), ...
    "Layers", localScenarioDouble(scfg, cfg, ["mimo.ul_layers", "pusch.n_layers", "mimo.n_layers"], layers), ...
    "Modulation", localConfiguredModulation(scfg, cfg, ["pusch.modulation", "modulation.ul_modulation_order", "modulation_and_mapping.pusch_modulation"]), ...
    "MCS", localScenarioDouble(scfg, cfg, ["modulation.ul_mcs_index", "pusch.mcs_index", "pusch.MCSIndex", "phy.ul.mcsIndex"], NaN), ...
    "MCSTable", string(localScenarioGet(scfg, cfg, "pusch.mcs_table", localScenarioGet(scfg, cfg, "modulation.ul_mcs_table", ""))), ...
    "TBS", localScenarioDouble(scfg, cfg, ["pusch.tbs", "pusch.tbs_bits"], NaN));
end

function modText = localConfiguredModulation(scfg, cfg, paths)
modText = "";
for ii = 1:numel(paths)
    raw = localScenarioGet(scfg, cfg, paths(ii), []);
    if isempty(raw)
        continue;
    end
    if isnumeric(raw)
        modText = localOrderToModulation(raw);
    else
        modText = strtrim(string(raw));
    end
    if strlength(modText) > 0
        return;
    end
end
end

function [rate, count] = localExactMatchRate(rows, direction)
rate = NaN;
count = 0;
if ~(istable(rows) && height(rows) > 0)
    return;
end
mask = string(rows.Direction) == string(direction) & logical(rows.StrictEligible);
count = sum(mask);
if count > 0
    rate = sum(mask & logical(rows.ExactOperatingPointMatch)) / count;
end
end

function gate = localMandatorySubsystemGate(details, required)
rows = strings(0, 6);
rows = localAddMandatoryRow(rows, "data_dl", required.DL, localNestedLogical(details, ["RawLifecycle", "RawLifecycleOk"], true) && required.DL, ...
    "air_interface/csv/dl_pdsch_trials.csv");
rows = localAddMandatoryRow(rows, "data_ul", required.UL, localNestedLogical(details, ["RawLifecycle", "RawLifecycleOk"], true) && required.UL, ...
    "air_interface/csv/ul_pusch_trials.csv");
rows = localAddMandatoryRow(rows, "sib1", localNestedLogical(details, ["SIB1", "SIB1Required"], false), ...
    localNestedLogical(details, ["SIB1", "SIB1StrictOk"], false), "reports/csv/sib1_conformance_summary.csv");
rows = localAddMandatoryRow(rows, "random_access", localNestedLogical(details, ["RandomAccess", "RARequired"], false), ...
    localNestedLogical(details, ["RandomAccess", "RAStrictOk"], false), "control/csv/ra_attempts.csv");
rows = localAddMandatoryRow(rows, "prach", localNestedLogical(details, ["PRACH", "PRACHRequired"], false), ...
    localNestedLogical(details, ["PRACH", "PRACHStrictOk"], false), "control/csv/prach_trials.csv");
rows = localAddMandatoryRow(rows, "pdcch", localNestedLogical(details, ["PDCCH", "PDCCHRequired"], false), ...
    localNestedLogical(details, ["PDCCH", "PDCCHStrictOk"], false), "control/csv/pdcch_trials.csv");
rows = localAddMandatoryRow(rows, "trs", localNestedLogical(details, ["TRS", "TRSRequired"], false), ...
    localNestedLogical(details, ["TRS", "TRSStrictOk"], false), "reference_signals/csv/trs_trials.csv");
rows = localAddMandatoryRow(rows, "srs", localNestedLogical(details, ["SRS", "SRSRequired"], false), ...
    localNestedLogical(details, ["SRS", "SRSStrictOk"], false), "reference_signals/csv/srs_trials.csv");
rows = localAddMandatoryRow(rows, "channel_rf", localNestedLogical(details, ["ChannelRF", "ChannelRFRequired"], false), ...
    localNestedLogical(details, ["ChannelRF", "ChannelRFStrictOk"], false), "channel/csv/channel_configured_vs_applied.csv");

requiredMask = rows(:, 2) == "required";
passMask = rows(:, 3) == "pass";
failRequired = requiredMask & ~passMask;
gate = struct();
gate.Rows = rows;
gate.MandatorySubsystemsOk = ~any(failRequired);
gate.UnavailableMandatoryCount = sum(failRequired & rows(:, 4) == "unavailable");
gate.PartialMandatoryCount = sum(failRequired & rows(:, 4) == "partial");
gate.ReviewRequiredMandatoryCount = sum(failRequired & rows(:, 4) == "review_required");
gate.DiagnosticOnlyMandatoryCount = sum(failRequired & rows(:, 4) == "diagnostic_only");
gate.ProxyEvidenceCount = sum(failRequired & rows(:, 4) == "proxy");
gate.FailureReasons = rows(failRequired, 1) + ":" + rows(failRequired, 4);
end

function rows = localAddMandatoryRow(rows, name, required, pass, artifact)
if required
    status = "required";
    if pass
        result = "pass";
        reason = "implemented";
    else
        result = "fail";
        reason = "unavailable";
    end
else
    status = "not_required";
    result = "pass";
    reason = "not_required";
end
rows(end+1, :) = [string(name), status, result, reason, string(artifact), "runtime_gate"]; %#ok<AGROW>
end

function gate = localStandardsClaimGate(layout, meta, scfg, cfg, mandatoryGate, strictEligible)
claimSources = localClaimSourceRows(layout, meta, scfg, cfg);
tokens = strings(0, 1);
for ii = 1:size(claimSources, 1)
    tokens = [tokens; localClaimTokens(claimSources(ii, 4))]; %#ok<AGROW>
end
tokens = unique(tokens(strlength(tokens) > 0), "stable");
profile = string(localScenarioGet(scfg, cfg, "scenario.claim_profile", localScenarioGet(scfg, cfg, "meta.claim_profile", "")));
profile = lower(strtrim(profile));
if strlength(profile) == 0
    profile = localInferClaimProfile(tokens, claimSources(:, 4));
end
forbiddenBroad = localHasForbiddenBroadClaim(tokens, claimSources(:, 4), profile);
mandatoryOk = logical(mandatoryGate.MandatorySubsystemsOk);
exactMappedProfile = profile == "standards_mapped_nr_profile";
claimAllowed = ~(forbiddenBroad && strictEligible && (~exactMappedProfile || ~mandatoryOk));
claimStatus = "claim_allowed";
failureReason = "";
if forbiddenBroad && strictEligible && ~claimAllowed
    claimStatus = "claim_rejected";
    failureReason = "AUD-001: broad 3GPP/6G/Rel-20/conformance wording lacks implemented, proxy-free mandatory proof.";
elseif any(tokens == "rel20" | tokens == "6g")
    claimStatus = "study_context_only";
elseif any(tokens == "anchor")
    claimStatus = "strict_anchor_internal";
end

scan = localPublicClaimScan(meta, claimSources, profile, claimAllowed, failureReason);
audit = localClaimAuditTable(meta, claimSources, tokens, profile, claimAllowed, claimStatus, mandatoryGate, failureReason);

gate = struct();
gate.ClaimProfile = profile;
gate.ClaimStatus = claimStatus;
gate.ClaimAllowed = logical(claimAllowed);
gate.ClaimFailureReason = string(failureReason);
gate.ForbiddenBroadClaimRejected = logical(~claimAllowed);
gate.ObjectiveDependsOnClaim = forbiddenBroad;
gate.ClaimAudit = audit;
gate.PublicClaimScan = scan;
gate.Summary = struct( ...
    "RunId", meta.RunId, ...
    "ScenarioName", meta.ScenarioName, ...
    "ClaimProfile", profile, ...
    "ClaimStatus", claimStatus, ...
    "ClaimAllowed", logical(claimAllowed), ...
    "ForbiddenBroadClaimRejected", logical(~claimAllowed), ...
    "ClaimFailureReason", string(failureReason), ...
    "StandardsClaimAuditArtifact", "reports/csv/standards_claim_audit.csv", ...
    "PublicClaimScanArtifact", "reports/csv/public_output_claim_scan.csv");
end

function sources = localClaimSourceRows(layout, meta, scfg, cfg)
sources = strings(0, 4);
sources(end+1, :) = ["config", "scenario", "ScenarioName", meta.ScenarioName];
sources(end+1, :) = ["config", "scenario", "ScenarioID", meta.ScenarioID];
sources(end+1, :) = ["config", "scenario", "ScenarioClass", meta.ScenarioClass];
sources(end+1, :) = ["config", "meta", "description", string(localScenarioGet(scfg, cfg, "meta.description", ""))];
sources(end+1, :) = ["config", "scenario", "notes", string(localScenarioGet(scfg, cfg, "scenario.notes", ""))];
summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
if istable(summary) && height(summary) > 0
    for name = ["ScenarioID", "ScenarioName", "ResultStatusReason", "FailureSummary"]
        if localHasColumn(summary, name)
            sources(end+1, :) = ["reports/csv/scenario_summary.csv", "csv", name, string(summary.(name)(1))]; %#ok<AGROW>
        end
    end
end
end

function profile = localInferClaimProfile(tokens, texts)
profile = "nr_baseline_study";
lowerText = lower(strjoin(string(texts(:)), " "));
if any(tokens == "rel20")
    profile = "rel20_study_context";
elseif any(tokens == "6g")
    profile = "experimental_6g_study";
elseif any(tokens == "anchor")
    profile = "strict_anchor_internal";
elseif contains(lowerText, "nr") || contains(lowerText, "5g")
    profile = "nr_baseline_study";
end
if localHasForbiddenBroadClaim(tokens, texts, profile)
    profile = "forbidden_broad_conformance_claim";
end
end

function tf = localHasForbiddenBroadClaim(tokens, texts, profile)
joined = lower(strjoin(string(texts(:)), " "));
tf = any(ismember(tokens, ["normative", "full_3gpp_conformance", "normative_6g_conformance", ...
    "rel20_6g_conformance", "6g_ran_conformance", "3gpp_rel20_anchor_ok", "conformance_ok", "standards_ok"]));
tf = tf || (contains(joined, "conformance") && (any(ismember(tokens, ["3gpp", "6g", "rel20", "anchor"])) || profile == "forbidden_broad_conformance_claim"));
tf = tf || contains(joined, "full 3gpp") || contains(joined, "normative 6g") || contains(joined, "standards conformance");
end

function tokens = localClaimTokens(text)
text = lower(strtrim(string(text)));
tokens = strings(0, 1);
if strlength(text) == 0
    return;
end
checks = {
    "3gpp", "3gpp";
    "rel20", "rel20";
    "rel-20", "rel20";
    "release 20", "rel20";
    "6g", "6g";
    "6gr", "6g";
    "anchor", "anchor";
    "conformance", "conformance";
    "standards", "standards";
    "normative", "normative";
    "full_3gpp_conformance", "full_3gpp_conformance";
    "normative_6g_conformance", "normative_6g_conformance";
    "rel20_6g_conformance", "rel20_6g_conformance";
    "6g_ran_conformance", "6g_ran_conformance";
    "3gpp_rel20_anchor_ok", "3gpp_rel20_anchor_ok";
    "conformance_ok", "conformance_ok";
    "standards_ok", "standards_ok"
    };
for ii = 1:size(checks, 1)
    if contains(text, checks{ii, 1})
        tokens(end+1, 1) = string(checks{ii, 2}); %#ok<AGROW>
    end
end
tokens = unique(tokens, "stable");
end

function scan = localPublicClaimScan(meta, sources, profile, claimAllowed, failureReason)
n = max(1, size(sources, 1));
if size(sources, 1) == 0
    sources = ["config", "scenario", "none", ""];
end
claimTokens = strings(n, 1);
pass = true(n, 1);
allowedReplacement = repmat(string(profile), n, 1);
issueId = strings(n, 1);
reason = strings(n, 1);
for ii = 1:n
    toks = localClaimTokens(sources(ii, 4));
    claimTokens(ii) = strjoin(toks, "|");
    broad = localHasForbiddenBroadClaim(toks, sources(ii, 4), profile);
    pass(ii) = ~(broad && ~claimAllowed);
    if ~pass(ii)
        issueId(ii) = "AUD-001";
        reason(ii) = string(failureReason);
        allowedReplacement(ii) = "rel20_study_context_or_experimental_6g_study";
    end
end
scan = table( ...
    repmat(meta.RunId, n, 1), sources(:, 1), sources(:, 3), repmat("", n, 1), sources(:, 4), ...
    claimTokens, allowedReplacement, pass, issueId, reason, ...
    'VariableNames', {'RunId','FilePath','FieldName','LineOrKey','ClaimText','ClaimToken','AllowedReplacement','Pass','IssueIdIfFailed','FailureReason'});
end

function audit = localClaimAuditTable(meta, sources, tokens, profile, claimAllowed, claimStatus, mandatoryGate, failureReason)
n = max(1, numel(tokens));
if isempty(tokens)
    tokens = "none";
end
implemented = double(mandatoryGate.MandatorySubsystemsOk);
partial = double(mandatoryGate.PartialMandatoryCount) + double(mandatoryGate.ReviewRequiredMandatoryCount);
unavailable = double(mandatoryGate.UnavailableMandatoryCount);
proxySkipped = double(mandatoryGate.ProxyEvidenceCount);
audit = table( ...
    repmat(meta.RunId, n, 1), repmat(meta.ScenarioName, n, 1), ...
    repmat("config/scenario/public_summary", n, 1), repmat("scenario_claim", n, 1), ...
    repmat(strjoin(string(sources(:, 4)), " | "), n, 1), string(tokens(:)), ...
    repmat(string(profile), n, 1), repmat(logical(claimAllowed), n, 1), repmat(string(claimStatus), n, 1), ...
    repmat("runtime_enabled_mandatory_subsystems", n, 1), ...
    repmat(implemented, n, 1), repmat(partial, n, 1), repmat(unavailable, n, 1), repmat(proxySkipped, n, 1), ...
    repmat(logical(claimAllowed) && logical(mandatoryGate.MandatorySubsystemsOk), n, 1), ...
    repmat(string(ternary(claimAllowed, "", "AUD-001")), n, 1), repmat(string(failureReason), n, 1), ...
    'VariableNames', {'RunId','ScenarioName','OutputFile','OutputField','ClaimText','ClaimToken','ClaimProfile', ...
    'ClaimAllowed','ClaimStatus','MandatoryFeatureSet','MandatoryFeaturesImplemented','MandatoryFeaturesPartial', ...
    'MandatoryFeaturesUnavailable','MandatoryFeaturesProxyOrSkipped','StandardsConformanceOk','IssueIdIfFailed','FailureReason'});
end

function gate = localConformanceRuntimeAudit(layout, meta, details, mandatoryGate, strictEligible)
rows0 = mandatoryGate.Rows;
n = max(1, size(rows0, 1));
if size(rows0, 1) == 0
    rows0 = ["reporting", "required", "pass", "implemented", "reports/csv/result_status_summary.csv", "runtime_gate"];
end
subsystem = rows0(:, 1);
configured = rows0(:, 2) == "required";
pass = rows0(:, 3) == "pass";
matrixStatus = rows0(:, 4);
strictAllowed = pass | ~configured;
issueId = repmat("", n, 1);
issueId(configured & ~pass) = "AUD-001";
reason = repmat("", n, 1);
reason(configured & ~pass) = "mandatory runtime evidence is not implemented/proxy-free/evidence-backed";
rows = table( ...
    repmat(meta.RunId, n, 1), subsystem, subsystem, configured, configured, matrixStatus, ...
    repmat(false, n, 1), strictAllowed, pass, repmat(false, n, 1), ~pass & configured, ~pass & configured, ...
    pass, pass, pass | ~configured, issueId, reason, ...
    'VariableNames', {'RunId','Subsystem','Feature','ConfiguredInScenario','MandatoryForScenario','MatrixStatus', ...
    'ProxyAllowed','StrictAnchorAllowed','RuntimeEvidenceFound','RuntimeProxyUsed','RuntimeSkipped','RuntimeUnavailable', ...
    'TestEvidenceFound','ArtifactEvidenceFound','Pass','IssueIdIfFailed','FailureReason'});
gate = struct();
gate.Rows = rows;
gate.MandatoryMatrixOk = all(pass | ~configured) || ~strictEligible;
gate.Summary = struct( ...
    "RunId", meta.RunId, ...
    "MandatoryMatrixOk", logical(gate.MandatoryMatrixOk), ...
    "MandatoryRows", double(sum(configured)), ...
    "FailingRows", double(sum(configured & ~pass)), ...
    "Artifact", "reports/csv/conformance_matrix_runtime_audit.csv");
end

function rootRows = localRootIssueRows(meta, claimGate, configuredGate, mandatoryGate, conformanceGate, strictEligible)
rootRows = localEmptyIssueTable();
if strictEligible && ~logical(claimGate.ClaimAllowed)
    rootRows = [rootRows; localIssueRow(meta, "AUD-001", "critical", "standards_claim", "result_status", ...
        "Strict anchor claim rejected because broad conformance wording lacks mandatory proof.", ...
        claimGate.ClaimStatus, claimGate.ClaimFailureReason)];
end
if strictEligible && ~logical(configuredGate.ConfiguredEffectiveOk)
    rootRows = [rootRows; localIssueRow(meta, "AUD-002", "critical", "configured_effective_binding", "scenario_objective", ...
        "Fixed-anchor configured operating point does not match effective runtime operating point.", ...
        "configured_effective_mismatch", strjoin(configuredGate.FailureReasons, "; "))];
end
if strictEligible && ~logical(mandatoryGate.MandatorySubsystemsOk) && isempty(rootRows)
    rootRows = [rootRows; localIssueRow(meta, "AUD-001", "critical", "standards_claim", "mandatory_subsystems", ...
        "Mandatory subsystem evidence is partial/unavailable for strict anchor.", ...
        "mandatory_subsystems_incomplete", strjoin(mandatoryGate.FailureReasons, "; "))];
end
if strictEligible && ~logical(conformanceGate.MandatoryMatrixOk) && isempty(rootRows)
    rootRows = [rootRows; localIssueRow(meta, "AUD-001", "critical", "standards_claim", "conformance_matrix", ...
        "Conformance matrix runtime audit has mandatory failing rows.", ...
        "mandatory_conformance_matrix_incomplete", "runtime conformance matrix audit failed")];
end
end

function T = localIssueRow(meta, issueId, severity, area, category, summary, runtimeStatus, reason)
T = table( ...
    string(issueId), string(severity), string(area), string(category), string(summary), ...
    "active", string(runtimeStatus), true, "not_waivable_critical", "", true, ...
    "sixgr.truth.evaluateStrictAnchorStatus", "", "reports/csv/result_status_summary.csv", ...
    "active", meta.RunId, string(reason), ...
    'VariableNames', {'IssueId','Severity','Area','Category','Summary','FixStatus','RuntimeStatus', ...
    'MandatoryForScenario','WaiverStatus','WaiverJustification','BlocksStrictAnchor','IssueSource', ...
    'RegressionTest','VerificationArtifact','Status','RunId','FailureReason'});
end

function merged = localMergeRootIssues(layout, rootRows)
registryPath = fullfile(layout.ReportCSVDir, "result_issue_registry.csv");
existing = localReadIssueTable(registryPath);
if istable(existing) && height(existing) > 0
    selfGenerated = string(existing.IssueSource) == "sixgr.truth.evaluateStrictAnchorStatus" & ...
        ismember(string(existing.IssueId), ["AUD-001", "AUD-002"]);
    existing = existing(~selfGenerated, :);
end
merged = existing;
if istable(rootRows) && height(rootRows) > 0
    merged = localIssueUnion(existing, rootRows);
end
if height(merged) > 0
    sixgr.util.csvWriteTable(registryPath, localIssueRegistryExportTable(merged));
end
end

function gate = localActiveIssueGate(layout, meta, issueT, rootRows, strictEligible)
if nargin < 4 || ~istable(rootRows)
    rootRows = localEmptyIssueTable();
end
issueT = localIssueUnion(issueT, rootRows);
severity = lower(strtrim(string(localColumnOrDefault(issueT, "Severity", ""))));
runtime = lower(strtrim(string(localColumnOrDefault(issueT, "RuntimeStatus", localColumnOrDefault(issueT, "Status", "")))));
fixStatus = lower(strtrim(string(localColumnOrDefault(issueT, "FixStatus", ""))));
waiver = lower(strtrim(string(localColumnOrDefault(issueT, "WaiverStatus", ""))));
mandatory = localToLogical(localColumnOrDefault(issueT, "MandatoryForScenario", false));
blocking = localToLogical(localColumnOrDefault(issueT, "BlocksStrictAnchor", false));
issueId = string(localColumnOrDefault(issueT, "IssueId", localColumnOrDefault(issueT, "issue_id", "")));

active = localActiveIssueMask(runtime, fixStatus);
critical = severity == "critical";
high = severity == "high";
medium = severity == "medium";
low = severity == "low";
criticalWaiverAttempt = critical & (contains(waiver, "waiv") | contains(runtime, "waiv") | contains(fixStatus, "waiv"));
blockMask = strictEligible & active & (blocking | mandatory) & (critical | high | criticalWaiverAttempt);
blockMask = blockMask | (strictEligible & criticalWaiverAttempt);

gate = struct();
gate.ActiveCriticalIssueCount = sum(active & critical);
gate.ActiveHighIssueCount = sum(active & high);
gate.ActiveMediumIssueCount = sum(active & medium);
gate.ActiveLowIssueCount = sum(active & low);
gate.ActiveMandatoryIssueCount = sum(active & mandatory);
gate.ActiveWaivedNonBlockingIssueCount = sum(active & contains(waiver, "waived_non_blocking"));
gate.ActiveIssueGateOk = ~any(blockMask);
gate.BlockingIssueIds = unique(issueId(blockMask), "stable");
gate.Rows = localActiveIssueGateRows(meta, issueT, active, blockMask, criticalWaiverAttempt);
gate.Summary = struct( ...
    "RunId", meta.RunId, ...
    "ActiveIssueGateOk", logical(gate.ActiveIssueGateOk), ...
    "ActiveCriticalIssueCount", double(gate.ActiveCriticalIssueCount), ...
    "ActiveHighIssueCount", double(gate.ActiveHighIssueCount), ...
    "ActiveMediumIssueCount", double(gate.ActiveMediumIssueCount), ...
    "ActiveMandatoryIssueCount", double(gate.ActiveMandatoryIssueCount), ...
    "BlockingIssueIds", strjoin(gate.BlockingIssueIds, "|"), ...
    "Artifact", "reports/csv/active_issue_gate_summary.csv");
end

function mask = localActiveIssueMask(runtimeStatus, fixStatus)
status = runtimeStatus;
status(strlength(status) == 0) = fixStatus(strlength(status) == 0);
resolved = ["", "ok", "fixed", "verified", "closed", "resolved", "not_applicable", ...
    "waived_non_blocking", "non_blocking", "informational", "info"];
mask = ~ismember(status, resolved);
end

function rows = localActiveIssueGateRows(meta, issueT, active, blockMask, criticalWaiverAttempt)
schemaNames = {'RunId','IssueId','Severity','Area','Category','Summary','FixStatus','RuntimeStatus', ...
    'MandatoryForScenario','WaiverStatus','WaiverJustification','BlocksStrictAnchor','IssueSource', ...
    'RegressionTest','VerificationArtifact','Status'};
schemaTypes = {'string','string','string','string','string','string','string','string', ...
    'logical','string','string','logical','string','string','string','string'};
if ~(istable(issueT) && height(issueT) > 0)
    rows = table('Size', [0 numel(schemaNames)], 'VariableTypes', schemaTypes, 'VariableNames', schemaNames);
    return;
end
n = height(issueT);
runtimeStatus = string(localColumnOrDefault(issueT, "RuntimeStatus", localColumnOrDefault(issueT, "Status", "")));
status = repmat("resolved_or_not_blocking", n, 1);
status(active) = "active_non_blocking";
status(blockMask) = "blocking";
status(criticalWaiverAttempt) = "critical_waiver_rejected";
rows = table( ...
    repmat(meta.RunId, n, 1), ...
    string(localColumnOrDefault(issueT, "IssueId", localColumnOrDefault(issueT, "issue_id", ""))), ...
    string(localColumnOrDefault(issueT, "Severity", localColumnOrDefault(issueT, "severity", ""))), ...
    string(localColumnOrDefault(issueT, "Area", localColumnOrDefault(issueT, "area", ""))), ...
    string(localColumnOrDefault(issueT, "Category", localColumnOrDefault(issueT, "category", ""))), ...
    string(localColumnOrDefault(issueT, "Summary", localColumnOrDefault(issueT, "summary", ""))), ...
    string(localColumnOrDefault(issueT, "FixStatus", localColumnOrDefault(issueT, "fix_status", ""))), ...
    runtimeStatus, ...
    localToLogical(localColumnOrDefault(issueT, "MandatoryForScenario", true)), ...
    string(localColumnOrDefault(issueT, "WaiverStatus", "")), ...
    string(localColumnOrDefault(issueT, "WaiverJustification", "")), ...
    localToLogical(localColumnOrDefault(issueT, "BlocksStrictAnchor", false)), ...
    string(localColumnOrDefault(issueT, "IssueSource", "result_issue_registry.csv")), ...
    string(localColumnOrDefault(issueT, "RegressionTest", "")), ...
    string(localColumnOrDefault(issueT, "VerificationArtifact", "")), ...
    status, ...
    'VariableNames', schemaNames);
end

function reasons = localStatusFailureReasons(runCompleted, artifactsWritten, truthOk, standardsOk, scenarioObjectiveOk, configuredGate, runClassGate, bindingGate, mandatoryGate, activeIssueGate, kpiOk, visualOk, duplicateOk)
reasons = strings(0, 1);
if ~runCompleted
    reasons(end+1, 1) = "run_not_completed"; %#ok<AGROW>
end
if ~artifactsWritten
    reasons(end+1, 1) = "required_artifacts_missing_or_incomplete"; %#ok<AGROW>
end
if ~truthOk
    reasons(end+1, 1) = "runtime_truth_contract_failed"; %#ok<AGROW>
end
if ~standardsOk
    reasons(end+1, 1) = "standards_claim_or_mandatory_conformance_failed"; %#ok<AGROW>
end
if ~scenarioObjectiveOk
    reasons(end+1, 1) = "scenario_objective_failed"; %#ok<AGROW>
end
if ~logical(configuredGate.ConfiguredEffectiveOk)
    reasons(end+1, 1) = "configured_effective_operating_point_failed"; %#ok<AGROW>
end
if isstruct(runClassGate) && ~logical(sixgr.util.structGet(runClassGate, "ObjectiveGateOk", true))
    reasons(end+1, 1) = "run_classification_gate_failed"; %#ok<AGROW>
end
if isstruct(bindingGate) && ~logical(sixgr.util.structGet(bindingGate, "BindingGateOk", true))
    reasons(end+1, 1) = "pdcch_grant_binding_gate_failed"; %#ok<AGROW>
end
if ~logical(mandatoryGate.MandatorySubsystemsOk)
    reasons(end+1, 1) = "mandatory_subsystem_gate_failed"; %#ok<AGROW>
end
if ~logical(activeIssueGate.ActiveIssueGateOk)
    reasons(end+1, 1) = "active_issue_gate_failed"; %#ok<AGROW>
end
if ~kpiOk
    reasons(end+1, 1) = "kpi_consistency_gate_failed"; %#ok<AGROW>
end
if ~visualOk
    reasons(end+1, 1) = "visual_artifact_gate_failed"; %#ok<AGROW>
end
if ~duplicateOk
    reasons(end+1, 1) = "duplicate_artifact_gate_failed"; %#ok<AGROW>
end
if isempty(reasons)
    reasons = "all_required_root_gates_passed";
end
end

function reason = localResultReason(resultOk, failureReasons)
if resultOk
    reason = "all_required_root_gates_passed";
else
    reason = strjoin(failureReasons, "; ");
end
end

function T = localResultStatusTable(status)
T = struct2table(status, "AsArray", true);
required = ["RunId","ScenarioName","ScenarioClass","ScenarioMode","ClaimProfile","ClaimStatus","ClaimAllowed", ...
    "RunCompleted","ArtifactsWritten","TruthContractOk","RuntimeTruthContractOk","StandardsConformanceOk", ...
    "ScenarioObjectiveOk","ConfiguredEffectiveOk","RunClass","RunClassGateOk","PublicationLLSEligible","MandatorySubsystemsOk","ActiveIssueGateOk","KpiConsistencyOk", ...
    "VisualArtifactGateOk","DuplicateArtifactGateOk","ResultOk","ActiveCriticalIssueCount","ActiveHighIssueCount", ...
    "ActiveMediumIssueCount","ActiveMandatoryIssueCount","ProxyEvidenceCount","SkippedEvidenceCount","FallbackEvidenceCount", ...
    "UnavailableMandatoryCount","PartialMandatoryCount","ReviewRequiredMandatoryCount","ConfiguredEffectiveMismatchCount", ...
    "PDCCHGrantBindingOk","PDCCHGrantBindingRequiredGrantCount","PDCCHGrantBindingFailingGrantCount", ...
    "StrictAnchorEligible","StrictAnchorPass","RunClassReason","ResultStatusReason","StrictAnchorFailureReasons","ProducerModule","GeneratedAt","SchemaVersion"];
for name = required
    if ~ismember(name, string(T.Properties.VariableNames))
        T.(name) = "";
    end
end
end

function T = localScenarioObjectiveGateTable(meta, status, configuredGate, runClassGate, claimGate, bindingGate, mandatoryGate, activeIssueGate)
names = {'RunId','ScenarioName','ObjectiveName','ObjectiveType','Mandatory','ScenarioMode','RequiredValue','ObservedValue','Threshold','Pass','IssueIdIfFailed','FailureReason','SourceCsv','SourceRowCount','SourceHash'};
T = table( ...
    repmat(meta.RunId, 7, 1), repmat(meta.ScenarioName, 7, 1), ...
    ["runtime_truth_contract"; "standards_claim"; "configured_effective_operating_point"; "run_classification"; "pdcch_grant_binding"; "mandatory_subsystems"; "active_issue_gate"], ...
    ["truth"; "claim"; "operating_point"; "classification"; "control_binding"; "mandatory_evidence"; "issue_registry"], ...
    true(7, 1), repmat(string(status.ScenarioMode), 7, 1), ...
    ["true"; "claim_allowed_and_mandatory_proof"; "exact_match_threshold"; "run_class_specific_publication_gate"; "all_required_grants_bound_to_decoded_dci"; "all_required_pass"; "no_active_blockers"], ...
    [string(status.RuntimeTruthContractOk); string(status.StandardsConformanceOk); string(configuredGate.ConfiguredEffectiveOk); string(status.RunClassGateOk); string(status.PDCCHGrantBindingOk); string(mandatoryGate.MandatorySubsystemsOk); string(activeIssueGate.ActiveIssueGateOk)], ...
    [""; ""; string(configuredGate.RequiredConfiguredMatchRate); ""; string(bindingGate.RequiredGrantCount); ""; ""], ...
    [status.RuntimeTruthContractOk; status.StandardsConformanceOk; configuredGate.ConfiguredEffectiveOk; status.RunClassGateOk; status.PDCCHGrantBindingOk; mandatoryGate.MandatorySubsystemsOk; activeIssueGate.ActiveIssueGateOk], ...
    ["", ternary(status.StandardsConformanceOk, "", "AUD-001"), ternary(configuredGate.ConfiguredEffectiveOk, "", "AUD-002"), "", "", ternary(mandatoryGate.MandatorySubsystemsOk, "", "AUD-001"), ""].', ...
    ["", claimGate.ClaimFailureReason, strjoin(configuredGate.FailureReasons, "; "), string(runClassGate.Reason), strjoin(bindingGate.FailureReasons, "; "), strjoin(mandatoryGate.FailureReasons, "; "), strjoin(activeIssueGate.BlockingIssueIds, "|")].', ...
    ["reports/csv/truth_contract_summary.csv"; "reports/csv/standards_claim_audit.csv"; "reports/csv/configured_effective_operating_point.csv"; "reports/csv/run_classification.csv"; "reports/csv/pdcch_grant_binding_evidence.csv"; "reports/csv/conformance_matrix_runtime_audit.csv"; "reports/csv/active_issue_gate_summary.csv"], ...
    [1; height(claimGate.ClaimAudit); height(configuredGate.Rows); height(runClassGate.Table); height(bindingGate.Rows); size(mandatoryGate.Rows, 1); height(activeIssueGate.Rows)], ...
    repmat("", 7, 1), ...
    'VariableNames', names);
end

function gate = localPDCCHGrantBindingGate(layout, cfg, dlTrials, ulTrials)
controlTrials = localReadTable(fullfile(layout.ControlCSVDir, "pdcch_trials.csv"));
controlRows = localPDCCHGrantBindingRowsFromControlTrials(controlTrials, cfg);
dataRows = localPDCCHGrantBindingRowsFromDataTrials(dlTrials, ulTrials, cfg);

if height(controlRows) > 0 && height(dataRows) > 0
    controlKeys = localPDCCHGrantBindingEvidenceKeys(controlRows);
    dataKeys = localPDCCHGrantBindingEvidenceKeys(dataRows);
    dataRows = dataRows(~ismember(dataKeys, controlKeys), :);
end
rows = [controlRows; dataRows];
if ~(istable(rows) && height(rows) > 0)
    rows = localEmptyPDCCHGrantBindingEvidenceTable();
end
rows = localEnforcePDCCHGrantBindingEvidenceCompleteness(rows);

requiredDirections = strings(0, 1);
if sixgr.control.isPDCCHGrantBindingRequired(cfg, "DL")
    requiredDirections(end+1, 1) = "DL"; %#ok<AGROW>
end
if sixgr.control.isPDCCHGrantBindingRequired(cfg, "UL")
    requiredDirections(end+1, 1) = "UL"; %#ok<AGROW>
end
boundMask = lower(strtrim(string(localColumnOrDefault(rows, "BindingStatus", "")))) == "bound";
failingMask = ~boundMask;
failureReasons = unique(string(localColumnOrDefault(rows(failingMask, :), "FailureCode", "")), "stable");
failureReasons = failureReasons(strlength(strtrim(failureReasons)) > 0);
if isempty(failureReasons) && any(failingMask)
    failureReasons = "grant_binding_failed";
end

gate = struct();
gate.Required = ~isempty(requiredDirections);
gate.RequiredDirections = requiredDirections;
gate.RequiredGrantCount = double(height(rows));
gate.FailingGrantCount = double(nnz(failingMask));
gate.BindingGateOk = gate.RequiredGrantCount == 0 || gate.FailingGrantCount == 0;
gate.FailureReasons = failureReasons(:);
gate.Rows = rows;
gate.Summary = struct( ...
    "Required", logical(gate.Required), ...
    "RequiredDirections", requiredDirections, ...
    "RequiredGrantCount", double(gate.RequiredGrantCount), ...
    "FailingGrantCount", double(gate.FailingGrantCount), ...
    "BindingGateOk", logical(gate.BindingGateOk), ...
    "FailureReasons", gate.FailureReasons, ...
    "EvidenceSource", "reports/csv/pdcch_grant_binding_evidence.csv");
end

function T = localEnforcePDCCHGrantBindingEvidenceCompleteness(T)
if ~(istable(T) && height(T) > 0)
    return;
end

bindingStatus = lower(strtrim(string(localColumnOrDefault(T, "BindingStatus", ""))));
failureCode = string(localColumnOrDefault(T, "FailureCode", ""));
grantIds = localFirstStringOrNumericAsString(T, ["GrantId"]);
dciIds = localFirstStringOrNumericAsString(T, ["DCIId"]);
dciHashes = localFirstStringOrNumericAsString(T, ["DCIFieldsHash"]);
grantHashes = localFirstStringOrNumericAsString(T, ["GrantFieldsHash"]);
decodedCrcOk = localColumnBoolDefault(T, "DecodedPDCCHCRCOK", false);

for ii = 1:height(T)
    failures = localSplitBindingFailureCodes(failureCode(ii));
    if strlength(strtrim(grantIds(ii))) == 0
        failures(end+1, 1) = "grant_id_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(dciIds(ii))) == 0
        failures(end+1, 1) = "decoded_dci_missing"; %#ok<AGROW>
    end
    if ~decodedCrcOk(ii)
        failures(end+1, 1) = "decoded_dci_crc_failed"; %#ok<AGROW>
    end
    if strlength(strtrim(dciHashes(ii))) == 0
        failures(end+1, 1) = "decoded_dci_fields_hash_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(grantHashes(ii))) == 0
        failures(end+1, 1) = "grant_fields_hash_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(dciHashes(ii))) > 0 && strlength(strtrim(grantHashes(ii))) > 0 && ...
            string(dciHashes(ii)) ~= string(grantHashes(ii))
        failures(end+1, 1) = "dci_grant_fields_hash_mismatch"; %#ok<AGROW>
    end

    failures = unique(failures(strlength(strtrim(failures)) > 0), "stable");
    if isempty(failures)
        if strlength(bindingStatus(ii)) == 0
            bindingStatus(ii) = "bound";
        end
        if bindingStatus(ii) ~= "bound"
            failures = "grant_binding_failed";
        end
    end
    if ~isempty(failures)
        bindingStatus(ii) = "failed";
        failureCode(ii) = strjoin(failures, "|");
    end
end

T.BindingStatus = bindingStatus;
T.FailureCode = failureCode;
end

function failures = localSplitBindingFailureCodes(raw)
raw = strtrim(string(raw));
if strlength(raw) == 0
    failures = strings(0, 1);
else
    failures = split(raw, "|");
    failures = failures(strlength(strtrim(failures)) > 0);
end
failures = string(failures(:));
end

function T = localPDCCHGrantBindingRowsFromControlTrials(controlT, cfg)
T = localEmptyPDCCHGrantBindingEvidenceTable();
if ~(istable(controlT) && height(controlT) > 0)
    return;
end

directions = upper(localFirstStringColumn(controlT, ["LinkedPDSCHOrPUSCH", "Direction"]));
grantIds = localFirstStringOrNumericAsString(controlT, ["GrantContextId", "LinkedGrantId", "GrantId"]);
requiredMask = localPDCCHGrantBindingRequiredMask(cfg, directions, localColumnBoolDefault(controlT, "GrantBindingRequired", false));
bindingOk = localColumnBoolDefault(controlT, "GrantBindingOk", false);
bindingStatus = localFirstStringOrNumericAsString(controlT, ["GrantBindingStatus"]);
bindingStatus(bindingOk & strlength(strtrim(bindingStatus)) == 0) = "bound";
bindingStatus(~bindingOk & strlength(strtrim(bindingStatus)) == 0) = "failed";
failureCode = localFirstStringOrNumericAsString(controlT, ["GrantBindingFailureCode"]);
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) == 0) = "grant_id_missing";
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) > 0) = "grant_binding_failed";

mask = requiredMask & (strlength(strtrim(grantIds)) > 0 | bindingOk | strlength(strtrim(bindingStatus)) > 0 | strlength(strtrim(failureCode)) > 0);
if ~any(mask)
    return;
end

cellId = localFirstNumericColumn(controlT, ["BaseStationID", "ServingCell"]);
ueId = localFirstNumericColumn(controlT, ["UEID", "UEIndex"]);
canonicalSlot = localFirstNumericColumn(controlT, ["GrantSlot", "Slot", "ControlSlot"]);
harqProcessId = localFirstNumericColumn(controlT, ["HARQProcessId", "HARQProcess"]);
rnti = localFirstNumericColumn(controlT, ["PDCCHDCICrcRNTI", "RNTI"]);
searchSpaceId = localFirstNumericColumn(controlT, ["SearchSpaceId"]);
coresetId = localFirstNumericColumn(controlT, ["CORESETId"]);
aggregationLevel = localFirstNumericColumn(controlT, ["AggregationLevel"]);
candidateIndex = localFirstNumericColumn(controlT, ["CandidateIndex", "PDCCHCandidateIndex"]);
dciFormat = localFirstStringOrNumericAsString(controlT, ["DCIFormat"]);
dciFieldsHash = localFirstStringOrNumericAsString(controlT, ["DCIFieldsHash"]);
grantFieldsHash = localFirstStringOrNumericAsString(controlT, ["GrantFieldsHash"]);
dciId = localFirstStringOrNumericAsString(controlT, ["DCIId", "PayloadHash"]);
decodedCrcOk = localColumnBoolDefault(controlT, "DCICrcPass", false);

T = table( ...
    directions(mask), ...
    cellId(mask), ...
    ueId(mask), ...
    canonicalSlot(mask), ...
    grantIds(mask), ...
    dciId(mask), ...
    harqProcessId(mask), ...
    rnti(mask), ...
    searchSpaceId(mask), ...
    coresetId(mask), ...
    aggregationLevel(mask), ...
    candidateIndex(mask), ...
    dciFormat(mask), ...
    dciFieldsHash(mask), ...
    grantFieldsHash(mask), ...
    decodedCrcOk(mask), ...
    bindingStatus(mask), ...
    failureCode(mask), ...
    'VariableNames', localPDCCHGrantBindingEvidenceVariableNames());
end

function T = localPDCCHGrantBindingRowsFromDataTrials(dlTrials, ulTrials, cfg)
dlRows = localPDCCHGrantBindingRowsFromDataTrialTable(dlTrials, cfg, "DL");
ulRows = localPDCCHGrantBindingRowsFromDataTrialTable(ulTrials, cfg, "UL");
T = [dlRows; ulRows];
if ~(istable(T) && height(T) > 0)
    T = localEmptyPDCCHGrantBindingEvidenceTable();
end
end

function T = localPDCCHGrantBindingRowsFromDataTrialTable(trialT, cfg, defaultDirection)
T = localEmptyPDCCHGrantBindingEvidenceTable();
if ~(istable(trialT) && height(trialT) > 0)
    return;
end

warmupMask = localColumnBoolDefault(trialT, "IsWarmupFrame", false);
directions = upper(localFirstStringColumn(trialT, ["Direction"]));
directions(strlength(strtrim(directions)) == 0) = string(defaultDirection);
grantIds = localFirstStringOrNumericAsString(trialT, ["GrantContextId", "GrantId"]);
requiredMask = localPDCCHGrantBindingRequiredMask(cfg, directions, localColumnBoolDefault(trialT, "PDCCHGrantBindingRequired", false));
bindingOk = localColumnBoolDefault(trialT, "PDCCHGrantBindingOk", false);
bindingStatus = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantBindingStatus"]);
bindingStatus(bindingOk & strlength(strtrim(bindingStatus)) == 0) = "bound";
bindingStatus(~bindingOk & strlength(strtrim(bindingStatus)) == 0) = "failed";
failureCode = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantBindingFailureCode"]);
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) == 0) = "grant_id_missing";
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) > 0) = "grant_binding_failed";

mask = requiredMask & ~warmupMask;
if ~any(mask)
    return;
end

cellId = localFirstNumericColumn(trialT, ["BaseStationID", "ServingCell"]);
ueId = localFirstNumericColumn(trialT, ["UEID", "UEIndex"]);
canonicalSlot = localFirstNumericColumn(trialT, ["Slot"]);
harqProcessId = localFirstNumericColumn(trialT, ["HARQProcessId", "HARQProcess"]);
rnti = localFirstNumericColumn(trialT, ["RNTI"]);
searchSpaceId = localFirstNumericColumn(trialT, ["PDCCHGrantSearchSpaceId"]);
coresetId = localFirstNumericColumn(trialT, ["PDCCHGrantCORESETId"]);
aggregationLevel = localFirstNumericColumn(trialT, ["PDCCHGrantAggregationLevel"]);
candidateIndex = localFirstNumericColumn(trialT, ["PDCCHGrantCandidateIndex"]);
dciFormat = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIFormat"]);
dciFieldsHash = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIFieldsHash"]);
grantFieldsHash = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantFieldsHash"]);
dciId = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIId"]);
decodedCrcOk = localColumnBoolDefault(trialT, "DCICrcPass", false);

T = table( ...
    directions(mask), ...
    cellId(mask), ...
    ueId(mask), ...
    canonicalSlot(mask), ...
    grantIds(mask), ...
    dciId(mask), ...
    harqProcessId(mask), ...
    rnti(mask), ...
    searchSpaceId(mask), ...
    coresetId(mask), ...
    aggregationLevel(mask), ...
    candidateIndex(mask), ...
    dciFormat(mask), ...
    dciFieldsHash(mask), ...
    grantFieldsHash(mask), ...
    decodedCrcOk(mask), ...
    bindingStatus(mask), ...
    failureCode(mask), ...
    'VariableNames', localPDCCHGrantBindingEvidenceVariableNames());
end

function mask = localPDCCHGrantBindingRequiredMask(cfg, directions, explicitRequired)
directions = upper(strtrim(string(directions(:))));
mask = logical(explicitRequired(:));
for ii = 1:numel(mask)
    if mask(ii)
        continue;
    end
    direction = directions(ii);
    if strlength(direction) == 0
        mask(ii) = sixgr.control.isPDCCHGrantBindingRequired(cfg, "");
    else
        mask(ii) = sixgr.control.isPDCCHGrantBindingRequired(cfg, direction);
    end
end
end

function keys = localPDCCHGrantBindingEvidenceKeys(T)
if ~(istable(T) && height(T) > 0)
    keys = strings(0, 1);
    return;
end
keys = localFirstStringOrNumericAsString(T, ["Direction"]) + "|" + ...
    localFirstStringOrNumericAsString(T, ["GrantId"]) + "|" + ...
    localFirstStringOrNumericAsString(T, ["CanonicalSlot"]);
end

function T = localEmptyPDCCHGrantBindingEvidenceTable()
names = localPDCCHGrantBindingEvidenceVariableNames();
types = {'string','double','double','double','string','string','double','double','double','double','double','double','string','string','string','logical','string','string'};
T = table('Size', [0 numel(names)], 'VariableTypes', types, 'VariableNames', names);
end

function names = localPDCCHGrantBindingEvidenceVariableNames()
names = {'Direction','CellId','UeId','CanonicalSlot','GrantId','DCIId','HARQProcessId','RNTI', ...
    'SearchSpaceId','CORESETId','AggregationLevel','CandidateIndex','DCIFormat','DCIFieldsHash', ...
    'GrantFieldsHash','DecodedPDCCHCRCOK','BindingStatus','FailureCode'};
end

function T = localStrictAnchorAcceptanceTable(meta, status)
gateNames = ["RunCompleted"; "ArtifactsWritten"; "RuntimeTruthContractOk"; "StandardsConformanceOk"; ...
    "ScenarioObjectiveOk"; "ConfiguredEffectiveOk"; "RunClassGateOk"; "PDCCHGrantBindingOk"; "MandatorySubsystemsOk"; "ActiveIssueGateOk"; ...
    "KpiConsistencyOk"; "VisualArtifactGateOk"; "DuplicateArtifactGateOk"; "ResultOk"];
passes = [status.RunCompleted; status.ArtifactsWritten; status.RuntimeTruthContractOk; status.StandardsConformanceOk; ...
    status.ScenarioObjectiveOk; status.ConfiguredEffectiveOk; status.RunClassGateOk; status.PDCCHGrantBindingOk; status.MandatorySubsystemsOk; status.ActiveIssueGateOk; ...
    status.KpiConsistencyOk; status.VisualArtifactGateOk; status.DuplicateArtifactGateOk; status.ResultOk];
n = numel(gateNames);
issueIds = repmat("", n, 1);
issueIds(~passes & gateNames == "StandardsConformanceOk") = "AUD-001";
issueIds(~passes & gateNames == "ConfiguredEffectiveOk") = "AUD-002";
T = table( ...
    repmat(meta.RunId, n, 1), repmat(meta.ScenarioName, n, 1), gateNames, true(n, 1), passes, ~passes, issueIds, ...
    repmat("reports/csv/result_status_summary.csv", n, 1), ...
    repmat(string(status.ResultStatusReason), n, 1), ...
    'VariableNames', {'RunId','ScenarioName','GateName','Required','Pass','Blocking','IssueIds','EvidenceArtifacts','FailureReason'});
end

function failures = localRootFailures(status, claimGate, configuredGate, bindingGate, mandatoryGate, activeIssueGate, kpiGate)
failures = strings(0, 1);
if ~logical(status.ResultOk) && ~logical(claimGate.ClaimAllowed)
    failures(end+1, 1) = "aud_001_standards_claim_gate_failed:" + string(claimGate.ClaimFailureReason); %#ok<AGROW>
end
if ~logical(configuredGate.ConfiguredEffectiveOk)
    failures(end+1, 1) = "aud_002_configured_effective_gate_failed:" + strjoin(configuredGate.FailureReasons, "; "); %#ok<AGROW>
end
if isfield(status, "RunClassGateOk") && ~logical(status.RunClassGateOk)
    failures(end+1, 1) = "run_classification_gate_failed:" + string(sixgr.util.structGet(status, "RunClassReason", "")); %#ok<AGROW>
end
if nargin >= 4 && isstruct(bindingGate) && ~logical(sixgr.util.structGet(bindingGate, "BindingGateOk", true))
    failures(end+1, 1) = "pdcch_grant_binding_gate_failed:" + ...
        strjoin(string(sixgr.util.structGet(bindingGate, "FailureReasons", strings(0, 1))), "; "); %#ok<AGROW>
end
if ~logical(mandatoryGate.MandatorySubsystemsOk) && isempty(failures)
    failures(end+1, 1) = "mandatory_subsystem_gate_failed:" + strjoin(mandatoryGate.FailureReasons, "; "); %#ok<AGROW>
end
if ~logical(activeIssueGate.ActiveIssueGateOk)
    failures(end+1, 1) = "active_issue_gate_failed:" + strjoin(activeIssueGate.BlockingIssueIds, "|"); %#ok<AGROW>
end
if nargin >= 6 && isstruct(kpiGate) && ~logical(sixgr.util.structGet(kpiGate, "KpiConsistencyOk", true))
    failures(end+1, 1) = "kpi_consistency_gate_failed:" + ...
        strjoin(string(sixgr.util.structGet(kpiGate, "FailureReasons", strings(0, 1))), "; "); %#ok<AGROW>
end
failures = failures(strlength(strtrim(failures)) > 0);
end

function localUpdateScenarioSummary(layout, status)
summaryPath = fullfile(layout.ReportCSVDir, "scenario_summary.csv");
T = localReadTable(summaryPath);
if isempty(T) || height(T) == 0
    T = table(status.ScenarioName, 'VariableNames', {'ScenarioID'});
end
n = height(T);
updates = {
    "RunCompleted", status.RunCompleted;
    "RunCompletion", string(ternary(status.RunCompleted, "completed", "not_completed"));
    "ResultOk", status.ResultOk;
    "RuntimeTruthContractOk", status.RuntimeTruthContractOk;
    "StandardsConformanceOk", status.StandardsConformanceOk;
    "ScenarioObjectiveOk", status.ScenarioObjectiveOk;
    "ConfiguredEffectiveOk", status.ConfiguredEffectiveOk;
    "RunClass", status.RunClass;
    "RunClassGateOk", status.RunClassGateOk;
    "PublicationLLSEligible", status.PublicationLLSEligible;
    "RunClassReason", status.RunClassReason;
    "MandatorySubsystemsOk", status.MandatorySubsystemsOk;
    "ActiveIssueGateOk", status.ActiveIssueGateOk;
    "ClaimProfile", status.ClaimProfile;
    "ClaimStatus", status.ClaimStatus;
    "ClaimAllowed", status.ClaimAllowed;
    "PDCCHGrantBindingOk", status.PDCCHGrantBindingOk;
    "PDCCHGrantBindingEvidenceArtifact", "reports/csv/pdcch_grant_binding_evidence.csv";
    "ResultStatusReason", status.ResultStatusReason;
    "StrictAnchorEligible", status.StrictAnchorEligible;
    "StrictAnchorPass", status.StrictAnchorPass;
    "StatusAuthority", status.ProducerModule;
    "ResultStatusSummaryArtifact", "reports/csv/result_status_summary.csv";
    "RunClassificationArtifact", "reports/csv/run_classification.csv"
    };
for ii = 1:size(updates, 1)
    name = char(updates{ii, 1});
    value = updates{ii, 2};
    if islogical(value)
        T.(name) = repmat(logical(value), n, 1);
    elseif isnumeric(value)
        T.(name) = repmat(double(value), n, 1);
    else
        T.(name) = repmat(string(value), n, 1);
    end
end
sixgr.util.csvWriteTable(summaryPath, T);
end

function T = localReadTable(pathValue)
T = table();
if exist(pathValue, "file") ~= 2
    return;
end
try
    T = readtable(pathValue, "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function T = localReadIssueTable(pathValue)
raw = localReadTable(pathValue);
T = localEmptyIssueTable();
if ~(istable(raw) && height(raw) > 0)
    return;
end
n = height(raw);
T = table( ...
    string(localColumnOrDefault(raw, "IssueId", localColumnOrDefault(raw, "issue_id", ""))), ...
    string(localColumnOrDefault(raw, "Severity", localColumnOrDefault(raw, "severity", ""))), ...
    string(localColumnOrDefault(raw, "Area", localColumnOrDefault(raw, "area", ""))), ...
    string(localColumnOrDefault(raw, "Category", localColumnOrDefault(raw, "category", ""))), ...
    string(localColumnOrDefault(raw, "Summary", localColumnOrDefault(raw, "summary", ""))), ...
    string(localColumnOrDefault(raw, "FixStatus", localColumnOrDefault(raw, "fix_status", ""))), ...
    string(localColumnOrDefault(raw, "RuntimeStatus", localColumnOrDefault(raw, "issue_status", localColumnOrDefault(raw, "status", "")))), ...
    localToLogical(localColumnOrDefault(raw, "MandatoryForScenario", localColumnOrDefault(raw, "mandatory_for_scenario", true))), ...
    string(localColumnOrDefault(raw, "WaiverStatus", localColumnOrDefault(raw, "waiver_status", ""))), ...
    string(localColumnOrDefault(raw, "WaiverJustification", localColumnOrDefault(raw, "waiver_justification", ""))), ...
    localToLogical(localColumnOrDefault(raw, "BlocksStrictAnchor", localColumnOrDefault(raw, "blocks_strict_anchor", localColumnOrDefault(raw, "blocking", true)))), ...
    string(localColumnOrDefault(raw, "IssueSource", localColumnOrDefault(raw, "issue_source", localColumnOrDefault(raw, "source", "result_issue_registry.csv")))), ...
    string(localColumnOrDefault(raw, "RegressionTest", localColumnOrDefault(raw, "regression_test", ""))), ...
    string(localColumnOrDefault(raw, "VerificationArtifact", localColumnOrDefault(raw, "verification_artifact", ""))), ...
    string(localColumnOrDefault(raw, "Status", localColumnOrDefault(raw, "issue_status", ""))), ...
    string(localColumnOrDefault(raw, "RunId", "")), ...
    string(localColumnOrDefault(raw, "FailureReason", localColumnOrDefault(raw, "root_cause_hint", ""))), ...
    'VariableNames', T.Properties.VariableNames);
if height(T) ~= n
    error("sixgr:truth:IssueTableNormalizeFailed", "Normalized issue table row count mismatch.");
end
end

function T = localEmptyIssueTable()
T = table('Size', [0 17], 'VariableTypes', {'string','string','string','string','string','string','string','logical','string','string','logical','string','string','string','string','string','string'}, ...
    'VariableNames', {'IssueId','Severity','Area','Category','Summary','FixStatus','RuntimeStatus','MandatoryForScenario','WaiverStatus','WaiverJustification','BlocksStrictAnchor','IssueSource','RegressionTest','VerificationArtifact','Status','RunId','FailureReason'});
end

function out = localIssueUnion(a, b)
if ~(istable(a) && height(a) > 0)
    out = b;
    return;
end
if ~(istable(b) && height(b) > 0)
    out = a;
    return;
end
out = [a; b];
[~, idx] = unique(string(out.IssueId) + "|" + string(out.IssueSource) + "|" + string(out.RuntimeStatus), "stable");
out = out(sort(idx), :);
end

function T = localIssueRegistryExportTable(issueT)
T = table( ...
    issueT.IssueId, issueT.Severity, issueT.RuntimeStatus, issueT.Category, ...
    repmat("", height(issueT), 1), NaN(height(issueT), 1), NaN(height(issueT), 1), ...
    issueT.Area, repmat("ResultOk", height(issueT), 1), issueT.Status, ...
    issueT.Summary, issueT.VerificationArtifact, issueT.FailureReason, ...
    repmat("resolve underlying root gate failure", height(issueT), 1), true(height(issueT), 1), ...
    issueT.IssueSource, issueT.MandatoryForScenario, issueT.BlocksStrictAnchor, issueT.WaiverStatus, ...
    'VariableNames', {'issue_id','severity','issue_status','issue_category','direction','ue_id','cell_id', ...
    'block_name','metric_name','observed_value','expected_or_policy','evidence_artifact_ref', ...
    'root_cause_hint','fix_plan','analytics_visible_flag','issue_source','mandatory_for_scenario','blocks_strict_anchor','waiver_status'});
end

function payload = localTableJsonPayload(T)
payload = struct();
payload.RowCount = height(T);
payload.Rows = table2struct(T);
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

function value = localScenarioDouble(scfg, cfg, paths, defaultValue)
value = defaultValue;
for pathValue = string(paths(:)).'
    raw = localScenarioGet(scfg, cfg, pathValue, []);
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
        value = nums(1);
        return;
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
    value = ismember(text, ["true", "1", "yes", "on", "pass", "ok"]);
end
if isempty(value)
    value = defaultValue;
else
    value = logical(value(1));
end
end

function value = localFirstNonBlankString(values)
values = string(values(:));
values = values(~ismissing(values) & strlength(strtrim(values)) > 0);
if isempty(values)
    value = "";
else
    value = strtrim(values(1));
end
end

function value = localScalarString(raw)
value = "";
if isempty(raw)
    return;
end
vals = string(raw(:));
if ~isempty(vals)
    value = vals(1);
end
end

function value = localFirstTableValue(value, T, names)
value = string(value);
if strlength(strtrim(value)) > 0 || ~(istable(T) && height(T) > 0)
    return;
end
for name = string(names(:)).'
    if localHasColumn(T, name)
        raw = string(T.(name));
        raw = raw(~ismissing(raw) & strlength(strtrim(raw)) > 0);
        if ~isempty(raw)
            value = raw(1);
            return;
        end
    end
end
end

function values = localColumnOrDefault(T, name, defaultValue)
if istable(T) && localHasColumn(T, name)
    values = T.(char(string(name)));
    return;
end
n = 0;
if istable(T)
    n = height(T);
end
if isstring(defaultValue) || ischar(defaultValue)
    values = localExpandDefaultColumn(string(defaultValue), n);
elseif islogical(defaultValue)
    values = localExpandDefaultColumn(logical(defaultValue), n);
else
    values = localExpandDefaultColumn(defaultValue, n);
end
end

function values = localExpandDefaultColumn(defaultValue, n)
if n <= 0
    values = defaultValue([]);
    values = values(:);
    return;
end
if ischar(defaultValue)
    values = repmat(string(defaultValue), n, 1);
    return;
end
if isscalar(defaultValue)
    values = repmat(defaultValue, n, 1);
    return;
end
if numel(defaultValue) == n
    values = defaultValue(:);
    return;
end
values = repmat(defaultValue(1), n, 1);
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function values = localToLogical(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = raw(:) ~= 0;
else
    text = lower(strtrim(string(raw(:))));
    values = ismember(text, ["true", "1", "yes", "on", "pass", "ok", "completed", "success"]);
end
end

function values = localColumnBoolDefault(T, name, defaultValue)
if localHasColumn(T, name)
    values = localToLogical(T.(char(string(name))));
else
    values = repmat(logical(defaultValue), height(T), 1);
end
end

function values = localFirstNumericColumn(T, names)
values = NaN(height(T), 1);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw)
        nums = double(raw);
    else
        nums = str2double(string(raw));
    end
    mask = isnan(values) & isfinite(nums);
    values(mask) = nums(mask);
end
end

function values = localFirstStringColumn(T, names)
values = repmat("", height(T), 1);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = strtrim(string(T.(char(name))));
    mask = strlength(values) == 0 & strlength(raw) > 0 & ~ismissing(raw);
    values(mask) = raw(mask);
end
end

function values = localFirstStringOrNumericAsString(T, names)
values = localFirstStringColumn(T, names);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw)
        text = string(raw);
    else
        text = strtrim(string(raw));
    end
    mask = strlength(values) == 0 & strlength(text) > 0 & ~ismissing(text);
    values(mask) = text(mask);
end
end

function tf = localModulationEqual(a, b)
tf = localModToken(a) == localModToken(b);
end

function token = localModToken(value)
token = upper(strtrim(string(value)));
token = replace(token, "-", "");
token = replace(token, " ", "");
end

function modStr = localOrderToModulation(order)
order = round(double(order));
if any(order == 2)
    modStr = "QPSK";
elseif any(order == 4)
    modStr = "16QAM";
elseif any(order == 6)
    modStr = "64QAM";
elseif any(order == 8)
    modStr = "256QAM";
elseif any(order == 10)
    modStr = "1024QAM";
else
    modStr = "";
end
end

function value = localNestedDouble(S, pathParts, defaultValue)
value = defaultValue;
try
    tmp = S;
    for ii = 1:numel(pathParts)
        tmp = tmp.(char(pathParts(ii)));
    end
    value = double(tmp);
catch
end
end

function value = localNestedLogical(S, pathParts, defaultValue)
value = defaultValue;
try
    tmp = S;
    for ii = 1:numel(pathParts)
        tmp = tmp.(char(pathParts(ii)));
    end
    value = localToLogical(tmp);
    value = value(1);
catch
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

function count = localFailureTokenCount(failures, tokens)
failures = lower(string(failures(:)));
count = 0;
for token = string(tokens(:)).'
    count = count + sum(contains(failures, lower(token)));
end
end

function T = localEmptyTable(schema)
T = table('Size', [0 numel(schema.Names)], 'VariableTypes', schema.Types, 'VariableNames', schema.Names);
end

function out = ternary(condition, a, b)
if condition
    out = a;
else
    out = b;
end
end
