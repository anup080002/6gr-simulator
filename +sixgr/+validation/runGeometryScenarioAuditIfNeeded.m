function audit = runGeometryScenarioAuditIfNeeded(runFolder, scfg, cfg)
%RUNGEOMETRYSCENARIOAUDITIFNEEDED Same evidence audit for normal/failed runs.
audit = struct("Required", false, "Executed", false, "Ok", true, ...
    "Status", "not_required", "FailureCount", 0, "WarningCount", 0, ...
    "FailureCodes", strings(0,1), "WarningCodes", strings(0,1), ...
    "Identifier", "", "Message", "");
audit.Required = sixgr.validation.geometryEvidenceRequired(scfg, cfg);
if ~audit.Required, return; end
try
    audit = sixgr.validation.auditGeometryScenarioRun(runFolder, ...
        "Strict", false, "WriteOutputs", true);
    audit.Required = true;
    audit.Executed = true;
catch ME
    audit.Required = true;
    audit.Executed = false;
    audit.Ok = false;
    audit.Status = "error";
    audit.FailureCount = 1;
    audit.WarningCount = 0;
    audit.FailureCodes = "geometry_scenario_audit_error";
    audit.WarningCodes = strings(0,1);
    audit.Identifier = string(ME.identifier);
    audit.Message = string(ME.message);
end
end
