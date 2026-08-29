function status = applyProductionQualificationGate(status, runFolder)
%APPLYPRODUCTIONQUALIFICATIONGATE Reduce final persisted evidence fail closed.
%
% This reducer runs only after the runtime, Phase-7, artifact and browser
% finalizers have written their evidence.  Functional completion is kept
% separate from scientific qualification and publication readiness.  A
% missing final evidence artifact is NOT treated as a pass.

arguments
    status (1,1) struct
    runFolder {mustBeTextScalar}
end

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
persistedStatus = localRead(fullfile(layout.ReportCSVDir, ...
    "result_status_summary.csv"));

% The post-finalization reducer receives an in-memory scenario status plus
% the already-persisted strict root status.  Several lifecycle fields (most
% notably ExecutionCompleted) are owned only by the canonical root status.
% Resolve a missing in-memory value from that one-row artifact instead of
% silently defaulting it to false; an explicitly supplied in-memory value
% remains authoritative.
functionalOk = localResolvedLogical(status, persistedStatus, "ResultOk", false) && ...
    localResolvedLogical(status, persistedStatus, "ExecutionCompleted", false) && ...
    localResolvedLogical(status, persistedStatus, "RuntimeTruthContractOk", false) && ...
    localResolvedLogical(status, persistedStatus, "MandatorySubsystemsOk", false) && ...
    localResolvedLogical(status, persistedStatus, "KpiConsistencyOk", false);
scenarioObjectiveOk = localResolvedLogical(status, persistedStatus, ...
    "ScenarioObjectiveOk", false);

[phase7Ok, phase7Status, phase7Reason] = localScalarGate( ...
    fullfile(layout.ReportCSVDir, "phase7_truth_gates.csv"), ...
    ["Phase7Ok","ResultOk"], "phase7_truth_gates_missing_or_invalid");
[publicationOk, publicationStatus, publicationReason] = localScalarGate( ...
    fullfile(layout.ReportCSVDir, "publication_readiness_gate_summary.csv"), ...
    "TerminalPublicationGatesOk", ...
    "publication_readiness_gate_summary_missing_or_invalid");
[wiringOk, wiringStatus, wiringReason] = localRequiredRowsGate( ...
    fullfile(layout.ReportCSVDir, "phy_package_execution_evidence_gate.csv"), ...
    "Required", "Pass", "runtime_wiring_evidence_missing_or_invalid");
frcRequired = localReferenceQualificationRequired( ...
    status, persistedStatus, runFolder);
if frcRequired
    [frcOk, frcStatus, frcReason, frcEvidence] = ...
        localReferenceGate(runFolder);
else
    frcOk = false;
    frcStatus = "NOT_EVALUATED";
    frcReason = "";
    frcEvidence = "meta/scenario_config_resolved.json";
end
frcSatisfied = ~frcRequired || frcOk;

runClass = localResolvedRunClass(status, persistedStatus, runFolder);
referenceComparisonRequired = ismember(runClass, ...
    ["fixed_snr_sweep_lls","hybrid_validation"]);
referenceComparisonEvidence = "reports/csv/publication_readiness_gate_summary.csv";
if referenceComparisonRequired
    [referenceComparisonOk, referenceComparisonStatus, ...
        referenceComparisonReason] = localScalarGate( ...
        fullfile(layout.ReportCSVDir, ...
        "publication_readiness_gate_summary.csv"), ...
        "PublicationReferenceComparisonOk", ...
        "independent_reference_comparison_missing_or_invalid");
else
    referenceComparisonOk = false;
    referenceComparisonStatus = "NOT_EVALUATED";
    referenceComparisonReason = "";
end
referenceComparisonSatisfied = ~referenceComparisonRequired || ...
    referenceComparisonOk;

[statisticalOk, statisticalStatus, statisticalReason] = ...
    localProductionStatisticalGate(status, persistedStatus, layout);
scientificOk = functionalOk && scenarioObjectiveOk && phase7Ok && statisticalOk;
productionGradeOk = functionalOk && wiringOk && scientificOk && ...
    frcSatisfied && referenceComparisonSatisfied && publicationOk;

status.FunctionalRunOk = logical(functionalOk);
status.ScenarioObjectiveQualificationOk = logical(scenarioObjectiveOk);
status.WiringCoverageOk = logical(wiringOk);
status.WiringCoverageStatus = wiringStatus;
status.NumericalValidationOk = logical(phase7Ok);
status.NumericalValidationStatus = phase7Status;
status.IndependentFRCQualificationOk = logical(frcOk);
status.IndependentFRCQualificationRequiredForProduction = logical(frcRequired);
status.IndependentFRCQualificationStatus = frcStatus;
status.IndependentFRCQualificationEvidenceArtifact = string(frcEvidence);
% Compatibility aliases retained for downstream readers of schema v4.
status.ReferenceQualificationOk = logical(frcOk);
status.ReferenceQualificationRequiredForProduction = logical(frcRequired);
status.ReferenceQualificationStatus = frcStatus;
status.ReferenceQualificationEvidenceArtifact = string(frcEvidence);
status.IndependentReferenceComparisonOk = logical(referenceComparisonOk);
status.IndependentReferenceComparisonRequiredForProduction = ...
    logical(referenceComparisonRequired);
status.IndependentReferenceComparisonStatus = referenceComparisonStatus;
status.IndependentReferenceComparisonEvidenceArtifact = ...
    string(referenceComparisonEvidence);
status.StatisticalQualificationOk = logical(statisticalOk);
status.StatisticalQualificationStatus = statisticalStatus;
status.ScientificQualificationOk = logical(scientificOk);
status.ScientificQualificationStatus = localState(scientificOk, ...
    phase7Status == "NOT_EVALUATED" || ...
    statisticalStatus == "NOT_EVALUATED");
status.TerminalPublicationGatesOk = logical(publicationOk);
status.TerminalPublicationGateStatus = publicationStatus;
status.ProductionGradeOk = logical(productionGradeOk);
status.PublicationReady = logical(productionGradeOk);
status.PublicationQualified = logical(productionGradeOk) && ...
    localResolvedLogical(status, persistedStatus, ...
    "PublicationLLSEligible", false);
status.PublicationQualificationStatus = localState(status.PublicationQualified, ...
    ~functionalOk || any([phase7Status, statisticalStatus, publicationStatus, ...
    wiringStatus] == "NOT_EVALUATED") || ...
    (frcRequired && frcStatus == "NOT_EVALUATED") || ...
    (referenceComparisonRequired && ...
    referenceComparisonStatus == "NOT_EVALUATED"));
status.OverallQualificationStatus = localOverallStatus(functionalOk, productionGradeOk);
status.ProductionQualificationFailureReasons = strjoin(localReasons( ...
    functionalOk, scenarioObjectiveOk, wiringOk, phase7Ok, statisticalOk, ...
    frcSatisfied, referenceComparisonSatisfied, publicationOk, ...
    wiringReason, phase7Reason, statisticalReason, frcReason, ...
    referenceComparisonReason, publicationReason), "; ");
status.ProductionQualificationProducer = "sixgr.truth.applyProductionQualificationGate";
status.ProductionQualificationSchemaVersion = "production_qualification_status_v5";

gateT = table( ...
    ["FunctionalRun";"ScenarioObjective";"RuntimeWiringCoverage";"Phase7NumericalValidation"; ...
     "StatisticalQualification";"IndependentFRCQualification"; ...
     "IndependentReferenceComparison"; ...
     "TerminalPublicationEvidence";"ProductionGrade"], ...
    [true;true;true;true;true;frcRequired;referenceComparisonRequired;true;true], ...
    [functionalOk;scenarioObjectiveOk;wiringOk;phase7Ok;statisticalOk;frcOk; ...
     referenceComparisonOk;publicationOk;productionGradeOk], ...
    [localState(functionalOk,false);localState(scenarioObjectiveOk,false);wiringStatus;phase7Status; ...
     statisticalStatus;frcStatus;referenceComparisonStatus;publicationStatus; ...
     localState(productionGradeOk,~functionalOk)], ...
    ["reports/csv/result_status_summary.csv"; ...
     "reports/csv/scenario_objective_gates.csv"; ...
     "reports/csv/phy_package_execution_evidence_gate.csv"; ...
     "reports/csv/phase7_truth_gates.csv"; ...
     "reports/csv/statistical_qualification_gate.csv"; ...
     frcEvidence; ...
     referenceComparisonEvidence; ...
     "reports/csv/publication_readiness_gate_summary.csv"; ...
     "reports/csv/production_qualification_gate.csv"], ...
    [localReason(functionalOk,"functional_runtime_gate_failed"); ...
     localReason(scenarioObjectiveOk,"scenario_objective_gate_failed"); ...
     localReason(wiringOk,wiringReason);localReason(phase7Ok,phase7Reason); ...
     localReason(statisticalOk,statisticalReason); ...
     localRequiredReason(frcRequired,frcOk,frcReason); ...
     localRequiredReason(referenceComparisonRequired,referenceComparisonOk, ...
     referenceComparisonReason); ...
     localReason(publicationOk,publicationReason); ...
     localReason(productionGradeOk,status.ProductionQualificationFailureReasons)], ...
    'VariableNames', {'Gate','Required','Pass','Status','EvidenceArtifact','FailureReason'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "production_qualification_gate.csv"), gateT, "PreserveSchema", true);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", ...
    "production_qualification_gate.json"), struct( ...
    "FunctionalRunOk", logical(functionalOk), ...
    "ScenarioObjectiveQualificationOk", logical(scenarioObjectiveOk), ...
    "WiringCoverageOk", logical(wiringOk), ...
    "NumericalValidationOk", logical(phase7Ok), ...
    "StatisticalQualificationOk", logical(statisticalOk), ...
    "IndependentFRCQualificationRequiredForProduction", logical(frcRequired), ...
    "IndependentFRCQualificationOk", logical(frcOk), ...
    "IndependentFRCQualificationEvidenceArtifact", string(frcEvidence), ...
    "IndependentReferenceComparisonRequiredForProduction", ...
    logical(referenceComparisonRequired), ...
    "IndependentReferenceComparisonOk", logical(referenceComparisonOk), ...
    "IndependentReferenceComparisonEvidenceArtifact", ...
    string(referenceComparisonEvidence), ...
    "ReferenceQualificationRequiredForProduction", logical(frcRequired), ...
    "ReferenceQualificationOk", logical(frcOk), ...
    "ReferenceQualificationEvidenceArtifact", string(frcEvidence), ...
    "TerminalPublicationGatesOk", logical(publicationOk), ...
    "ProductionGradeOk", logical(productionGradeOk), ...
    "FailureReasons", string(status.ProductionQualificationFailureReasons), ...
    "SchemaVersion", "production_qualification_status_v5"));
end

function required = localReferenceQualificationRequired(status, persistedStatus, runFolder)
% Independent-reference qualification remains fail closed by default.  A
% run may opt out only through explicit persisted scenario authority; the
% absence of evidence or an unreadable configuration never disables it.
fieldNames = ["IndependentFRCQualificationRequiredForProduction", ...
    "ReferenceQualificationRequiredForProduction", ...
    "IndependentReferenceQualificationRequiredForProduction"];
for idx = 1:numel(fieldNames)
    name = fieldNames(idx);
    if isfield(status, char(name)) && ~isempty(status.(char(name)))
        required = localToLogical(status.(char(name)));
        return;
    end
    if istable(persistedStatus) && height(persistedStatus) == 1 && ...
            ismember(name, string(persistedStatus.Properties.VariableNames))
        required = localToLogical(persistedStatus.(char(name))(1));
        return;
    end
end

configPath = fullfile(runFolder, "meta", "scenario_config_resolved.json");
if isfile(configPath)
    try
        cfg = sixgr.util.jsonRead(configPath);
        raw = sixgr.util.structGet(cfg, ...
            "validation.independent_reference_qualification.required_for_production", []);
        if ~isempty(raw)
            required = localToLogical(raw);
            return;
        end
    catch
        % Invalid persisted authority must not silently waive qualification.
    end
end
required = true;
end

function [ok, state, reason] = localProductionStatisticalGate(status, persistedStatus, layout)
% Production qualification may not inherit a component-level
% NOT_APPLICABLE statistical pass.  Fixed-SNR and geometry campaigns own
% their sample adequacy in the Phase-7 campaign evidence.
runClass = localResolvedRunClass(status, persistedStatus, layout.Root);
phase7Path = fullfile(layout.ReportCSVDir, "phase7_truth_gates.csv");
phase7 = localRead(phase7Path);
campaignRunClasses = ["fixed_snr_sweep_lls","ue_placement_geometry_lls", ...
    "hybrid_validation"];
if ismember(runClass, campaignRunClasses)
    requiredColumns = ["SeedHierarchyOk","CampaignDesignOk", ...
        "CampaignCompletionOk","MultiSeedDropStatisticsOk", ...
        "ConfidenceIntervalsOk","SampleAdequacyOk","SweepDataQualityOk"];
    if height(phase7) ~= 1 || ...
            any(~ismember(requiredColumns, string(phase7.Properties.VariableNames)))
        ok = false;
        state = "NOT_EVALUATED";
        reason = "production_statistical_campaign_evidence_missing_or_invalid";
        return;
    end
    passes = false(numel(requiredColumns), 1);
    for idx = 1:numel(requiredColumns)
        passes(idx) = localToLogical(phase7.(char(requiredColumns(idx)))(1));
    end
    ok = all(passes);
    state = localState(ok, false);
    if ok
        reason = "";
    else
        reason = "production_statistical_campaign_gates_failed:" + ...
            strjoin(requiredColumns(~passes), "|");
    end
    return;
end

ok = localResolvedLogical(status, persistedStatus, ...
    "StatisticalQualificationOk", false);
qualificationState = localResolvedString(status, persistedStatus, ...
    "StatisticalQualificationStatus", "");
if qualificationState == "NOT_APPLICABLE"
    ok = false;
    state = "NOT_EVALUATED";
    reason = "production_statistical_qualification_not_applicable";
elseif ok && qualificationState == "PASS"
    state = "PASS";
    reason = "";
elseif strlength(qualificationState) == 0
    ok = false;
    state = "NOT_EVALUATED";
    reason = "production_statistical_qualification_status_missing";
else
    ok = false;
    state = "FAIL";
    reason = "production_statistical_qualification_not_passed";
end
end

function [ok, state, reason] = localScalarGate(path, columns, missingReason)
T = localRead(path);
columns = string(columns(:));
if height(T) ~= 1
    ok = false; state = "NOT_EVALUATED"; reason = string(missingReason); return;
end
column = columns(find(ismember(columns, string(T.Properties.VariableNames)), 1));
if isempty(column)
    ok = false; state = "NOT_EVALUATED"; reason = string(missingReason); return;
end
ok = localToLogical(T.(char(column))(1));
state = localState(ok, false);
reason = localReason(ok, string(column) + "_false");
end

function [ok, state, reason] = localRequiredRowsGate(path, requiredColumn, passColumn, missingReason)
T = localRead(path);
if isempty(T) || ~all(ismember([requiredColumn,passColumn], string(T.Properties.VariableNames)))
    ok = false; state = "NOT_EVALUATED"; reason = string(missingReason); return;
end
required = arrayfun(@localToLogical, T.(char(requiredColumn)));
pass = arrayfun(@localToLogical, T.(char(passColumn)));
ok = any(required) && all(~required | pass);
state = localState(ok, false);
reason = localReason(ok, "required_runtime_wiring_gate_failed");
end

function [ok, state, reason, evidence] = localReferenceGate(runFolder)
qualificationRel = "reports/csv/frc_reference_qualification.csv";
diagnosticRel = "reports/csv/frc_reference_diagnostic.csv";
qualificationPath = fullfile(runFolder, strrep(char(qualificationRel), "/", filesep));
diagnosticPath = fullfile(runFolder, strrep(char(diagnosticRel), "/", filesep));
T = localRead(qualificationPath);
evidence = qualificationRel;
if isempty(T)
    diagnosticT = localRead(diagnosticPath);
    if isempty(diagnosticT)
        ok = false; state = "NOT_EVALUATED";
        reason = "independent_frc_reference_evidence_missing";
        return;
    end
    evidence = diagnosticRel;
    [validationArgs, ~] = localReferenceValidationArguments(runFolder);
    [~, diagnosticFailure, diagnosticDetails] = ...
        sixgr.conformance.validateReferenceQualificationTable( ...
        diagnosticT, validationArgs{:});
    ok = false;
    if logical(diagnosticDetails.Evaluated)
        state = "FAIL";
        reason = "independent_frc_reference_diagnostic_not_qualification_evidence:" + ...
            string(diagnosticFailure);
    else
        state = "NOT_EVALUATED";
        reason = "independent_frc_reference_diagnostic_invalid:" + ...
            string(diagnosticFailure);
    end
    return;
end
[validationArgs, bindingFailure] = ...
    localReferenceValidationArguments(runFolder);
if strlength(bindingFailure) > 0
    ok = false;
    state = "NOT_EVALUATED";
    reason = bindingFailure;
    evidence = "meta/scenario_config_resolved.json";
    return;
end
[ok, failure, details] = ...
    sixgr.conformance.validateReferenceQualificationTable( ...
    T, validationArgs{:});
if ok
    state = "PASS";
    reason = "";
elseif ~logical(details.Evaluated)
    state = "NOT_EVALUATED";
    reason = "independent_" + string(failure);
else
    state = "FAIL";
    reason = "independent_frc_reference_point_failed";
end
end

function [args, failure] = localReferenceValidationArguments(runFolder)
args = {};
failure = "";
configPath = fullfile(runFolder, "meta", "scenario_config_resolved.json");
if ~isfile(configPath)
    failure = "independent_frc_resolved_config_missing";
    return;
end
try
    cfg = sixgr.util.jsonRead(configPath);
    expected = strtrim(string(sixgr.util.structGet(cfg, ...
        "validation.independent_reference_qualification.entry_ids", ...
        strings(0,1))));
    expected = expected(:);
    expected = expected(strlength(expected) > 0);
    if isempty(expected) || numel(unique(expected)) ~= numel(expected)
        failure = "independent_frc_expected_entry_set_missing_or_invalid";
        return;
    end
    catalog = sixgr.conformance.frcCatalog();
    catalogEntryIds = localCatalogEntryIds(catalog);
    catalogDigest = sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(catalog), "UTF-8")));
    args = {"ExpectedEntryIds", expected, ...
        "CatalogEntryIds", catalogEntryIds, ...
        "ExpectedCatalogSHA256", catalogDigest};
catch
    failure = "independent_frc_catalog_or_config_binding_failed";
end
end

function ids = localCatalogEntryIds(catalog)
entries = catalog.entries;
ids = strings(numel(entries), 1);
for index = 1:numel(entries)
    if iscell(entries)
        entry = entries{index};
    else
        entry = entries(index);
    end
    ids(index) = strtrim(string(entry.id));
end
if any(strlength(ids) == 0) || numel(unique(ids)) ~= numel(ids)
    error("sixgr:conformance:FRCatalogEntryIdentityInvalid", ...
        "The active FRC catalog must contain unique nonempty entry ids.");
end
end

function reasons = localReasons(functionalOk, scenarioObjectiveOk, wiringOk, ...
        phase7Ok, statisticalOk, frcOk, referenceComparisonOk, publicationOk, ...
        wiringReason, phase7Reason, statisticalReason, frcReason, ...
        referenceComparisonReason, publicationReason)
reasons = strings(0,1);
if ~functionalOk, reasons(end+1,1) = "functional_runtime_gate_failed"; end %#ok<AGROW>
if ~scenarioObjectiveOk, reasons(end+1,1) = "scenario_objective_gate_failed"; end %#ok<AGROW>
if ~wiringOk, reasons(end+1,1) = wiringReason; end %#ok<AGROW>
if ~phase7Ok, reasons(end+1,1) = phase7Reason; end %#ok<AGROW>
if ~statisticalOk, reasons(end+1,1) = statisticalReason; end %#ok<AGROW>
if ~frcOk, reasons(end+1,1) = frcReason; end %#ok<AGROW>
if ~referenceComparisonOk
    reasons(end+1,1) = referenceComparisonReason; %#ok<AGROW>
end
if ~publicationOk, reasons(end+1,1) = publicationReason; end %#ok<AGROW>
reasons = unique(reasons(strlength(strtrim(reasons)) > 0), "stable");
end

function runClass = localResolvedRunClass(status, persistedStatus, runFolder)
runClass = lower(strtrim(localResolvedString(status, persistedStatus, ...
    "RunClass", "")));
if strlength(runClass) > 0
    return;
end
configPath = fullfile(char(string(runFolder)), "meta", ...
    "scenario_config_resolved.json");
if ~isfile(configPath)
    return;
end
try
    cfg = sixgr.util.jsonRead(configPath);
    raw = sixgr.util.structGet(cfg, "validation.RunClass", []);
    if isempty(raw)
        raw = sixgr.util.structGet(cfg, "validation.run_class", []);
    end
    if ~isempty(raw)
        runClass = lower(strtrim(string(raw(1))));
    end
catch
    runClass = "";
end
end

function state = localOverallStatus(functionalOk, productionOk)
if productionOk
    state = "PRODUCTION_QUALIFIED";
elseif functionalOk
    state = "FUNCTIONAL_ONLY_NOT_PRODUCTION_QUALIFIED";
else
    state = "FAILED";
end
end

function state = localState(ok, notEvaluated)
if ok
    state = "PASS";
elseif notEvaluated
    state = "NOT_EVALUATED";
else
    state = "FAIL";
end
end

function reason = localReason(ok, reason)
if ok, reason = ""; else, reason = string(reason); end
end

function reason = localRequiredReason(required, ok, reason)
if ~required || ok
    reason = "";
else
    reason = string(reason);
end
end

function value = localLogical(s, name, defaultValue)
value = localToLogical(sixgr.util.structGet(s, name, defaultValue));
end

function value = localResolvedLogical(status, persistedStatus, name, defaultValue)
if isfield(status, char(name)) && ~isempty(status.(char(name)))
    value = localLogical(status, name, defaultValue);
    return;
end
if istable(persistedStatus) && height(persistedStatus) == 1 && ...
        ismember(string(name), string(persistedStatus.Properties.VariableNames))
    value = localToLogical(persistedStatus.(char(name))(1));
    return;
end
value = logical(defaultValue);
end

function value = localResolvedString(status, persistedStatus, name, defaultValue)
if isfield(status, char(name)) && ~isempty(status.(char(name)))
    value = string(status.(char(name)));
    value = value(1);
    return;
end
if istable(persistedStatus) && height(persistedStatus) == 1 && ...
        ismember(string(name), string(persistedStatus.Properties.VariableNames))
    value = string(persistedStatus.(char(name))(1));
    return;
end
value = string(defaultValue);
end

function value = localToLogical(raw)
if islogical(raw), value = logical(raw(1));
elseif isnumeric(raw), value = isfinite(raw(1)) && raw(1) ~= 0;
else, value = ismember(lower(strtrim(string(raw(1)))), ["1","true","pass","yes"]); end
end

function T = localRead(path)
if ~isfile(path), T = table(); return; end
try
    T = sixgr.util.csvReadTable(path, "TextType", "string");
catch
    T = table();
end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:truth:ProductionQualificationBadRunFolder", ...
        "runFolder must be a character vector or string scalar.");
end
end
