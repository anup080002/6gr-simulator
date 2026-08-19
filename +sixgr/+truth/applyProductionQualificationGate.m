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
[referenceOk, referenceStatus, referenceReason] = localReferenceGate(runFolder);

[statisticalOk, statisticalStatus, statisticalReason] = ...
    localProductionStatisticalGate(status, persistedStatus, layout);
scientificOk = functionalOk && scenarioObjectiveOk && phase7Ok && statisticalOk;
productionGradeOk = functionalOk && wiringOk && scientificOk && ...
    referenceOk && publicationOk;

status.FunctionalRunOk = logical(functionalOk);
status.ScenarioObjectiveQualificationOk = logical(scenarioObjectiveOk);
status.WiringCoverageOk = logical(wiringOk);
status.WiringCoverageStatus = wiringStatus;
status.NumericalValidationOk = logical(phase7Ok);
status.NumericalValidationStatus = phase7Status;
status.ReferenceQualificationOk = logical(referenceOk);
status.ReferenceQualificationStatus = referenceStatus;
status.StatisticalQualificationOk = logical(statisticalOk);
status.StatisticalQualificationStatus = statisticalStatus;
status.ScientificQualificationOk = logical(scientificOk);
status.ScientificQualificationStatus = localState(scientificOk, ...
    phase7Status == "NOT_EVALUATED" || ...
    statisticalStatus == "NOT_EVALUATED" || ...
    referenceStatus == "NOT_EVALUATED");
status.TerminalPublicationGatesOk = logical(publicationOk);
status.TerminalPublicationGateStatus = publicationStatus;
status.ProductionGradeOk = logical(productionGradeOk);
status.PublicationReady = logical(productionGradeOk);
status.PublicationQualified = logical(productionGradeOk) && ...
    localResolvedLogical(status, persistedStatus, ...
    "PublicationLLSEligible", false);
status.PublicationQualificationStatus = localState(status.PublicationQualified, ...
    ~functionalOk || any([phase7Status, statisticalStatus, publicationStatus, ...
    wiringStatus, referenceStatus] == "NOT_EVALUATED"));
status.OverallQualificationStatus = localOverallStatus(functionalOk, productionGradeOk);
status.ProductionQualificationFailureReasons = strjoin(localReasons( ...
    functionalOk, scenarioObjectiveOk, wiringOk, phase7Ok, statisticalOk, referenceOk, publicationOk, ...
    wiringReason, phase7Reason, statisticalReason, referenceReason, publicationReason), "; ");
status.ProductionQualificationProducer = "sixgr.truth.applyProductionQualificationGate";
status.ProductionQualificationSchemaVersion = "production_qualification_status_v2";

gateT = table( ...
    ["FunctionalRun";"ScenarioObjective";"RuntimeWiringCoverage";"Phase7NumericalValidation"; ...
     "StatisticalQualification";"IndependentReferenceQualification"; ...
     "TerminalPublicationEvidence";"ProductionGrade"], ...
    [true;true;true;true;true;true;true;true], ...
    [functionalOk;scenarioObjectiveOk;wiringOk;phase7Ok;statisticalOk;referenceOk;publicationOk;productionGradeOk], ...
    [localState(functionalOk,false);localState(scenarioObjectiveOk,false);wiringStatus;phase7Status; ...
     statisticalStatus;referenceStatus;publicationStatus; ...
     localState(productionGradeOk,~functionalOk)], ...
    ["reports/csv/result_status_summary.csv"; ...
     "reports/csv/scenario_objective_gates.csv"; ...
     "reports/csv/phy_package_execution_evidence_gate.csv"; ...
     "reports/csv/phase7_truth_gates.csv"; ...
     "reports/csv/statistical_qualification_gate.csv"; ...
     "reports/csv/frc_reference_qualification.csv"; ...
     "reports/csv/publication_readiness_gate_summary.csv"; ...
     "reports/csv/production_qualification_gate.csv"], ...
    [localReason(functionalOk,"functional_runtime_gate_failed"); ...
     localReason(scenarioObjectiveOk,"scenario_objective_gate_failed"); ...
     localReason(wiringOk,wiringReason);localReason(phase7Ok,phase7Reason); ...
     localReason(statisticalOk,statisticalReason); ...
     localReason(referenceOk,referenceReason); ...
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
    "ReferenceQualificationOk", logical(referenceOk), ...
    "TerminalPublicationGatesOk", logical(publicationOk), ...
    "ProductionGradeOk", logical(productionGradeOk), ...
    "FailureReasons", string(status.ProductionQualificationFailureReasons), ...
    "SchemaVersion", "production_qualification_status_v2"));
end

function [ok, state, reason] = localProductionStatisticalGate(status, persistedStatus, layout)
% Production qualification may not inherit a component-level
% NOT_APPLICABLE statistical pass.  Fixed-SNR and geometry campaigns own
% their sample adequacy in the Phase-7 campaign evidence.
runClass = localResolvedString(status, persistedStatus, "RunClass", "");
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

function [ok, state, reason] = localReferenceGate(runFolder)
path = fullfile(runFolder, "reports", "csv", "frc_reference_qualification.csv");
T = localRead(path);
if isempty(T)
    ok = false; state = "NOT_EVALUATED";
    reason = "independent_frc_reference_qualification_missing";
    return;
end
[ok, failure, details] = ...
    sixgr.conformance.validateReferenceQualificationTable(T);
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

function reasons = localReasons(functionalOk, scenarioObjectiveOk, wiringOk, phase7Ok, statisticalOk, referenceOk, publicationOk, wiringReason, phase7Reason, statisticalReason, referenceReason, publicationReason)
reasons = strings(0,1);
if ~functionalOk, reasons(end+1,1) = "functional_runtime_gate_failed"; end %#ok<AGROW>
if ~scenarioObjectiveOk, reasons(end+1,1) = "scenario_objective_gate_failed"; end %#ok<AGROW>
if ~wiringOk, reasons(end+1,1) = wiringReason; end %#ok<AGROW>
if ~phase7Ok, reasons(end+1,1) = phase7Reason; end %#ok<AGROW>
if ~statisticalOk, reasons(end+1,1) = statisticalReason; end %#ok<AGROW>
if ~referenceOk, reasons(end+1,1) = referenceReason; end %#ok<AGROW>
if ~publicationOk, reasons(end+1,1) = publicationReason; end %#ok<AGROW>
reasons = unique(reasons(strlength(strtrim(reasons)) > 0), "stable");
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
    T = readtable(path, "VariableNamingRule", "preserve", "TextType", "string");
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
