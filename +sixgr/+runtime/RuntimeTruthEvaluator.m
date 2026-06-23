classdef RuntimeTruthEvaluator
%RUNTIMETRUTHEVALUATOR Authoritative Phase-1 root status composition.

    methods (Static)
        function status = evaluate(flags)
            if nargin < 1 || ~isstruct(flags)
                flags = struct();
            end
            gateNames = sixgr.runtime.RuntimeTruthEvaluator.rootGateNames();
            status = struct();
            for i = 1:numel(gateNames)
                name = gateNames(i);
                status.(char(name)) = logical(sixgr.util.structGet(flags, char(name), false));
            end
            resultOk = true;
            failureCodes = strings(0, 1);
            for i = 1:numel(gateNames)
                name = gateNames(i);
                ok = logical(status.(char(name)));
                resultOk = resultOk && ok;
                if ~ok
                    failureCodes(end+1, 1) = name + "_false"; %#ok<AGROW>
                end
            end
            status.ResultOk = logical(resultOk);
            status.FailureCodes = failureCodes;
            status.PrimaryFailureCode = localPrimaryFailure(failureCodes);
            status.WarningCodes = string(sixgr.util.structGet(flags, "WarningCodes", strings(0, 1)));
            status.RunCompletion = localRunCompletion(status);
            status.GeneratedAt = sixgr.util.utcNowISO8601();
            status.ProducerModule = "sixgr.runtime.RuntimeTruthEvaluator";
        end

        function names = rootGateNames()
            names = [ ...
                "RuntimeExecutionOk"
                "RuntimeJournalOk"
                "WorkerShutdownOk"
                "ReportingPipelineOk"
                "ArtifactValidationOk"
                "InfrastructureAuditOk"
                "MandatoryPhyEvidenceOk"
                "KpiConsistencyOk"
                "ScenarioObjectiveOk"
                "StrictConformanceOk"];
        end

        function T = table(status)
            T = struct2table(status, "AsArray", true);
        end
    end
end

function code = localPrimaryFailure(failureCodes)
if isempty(failureCodes)
    code = "";
else
    code = string(failureCodes(1));
end
end

function completion = localRunCompletion(status)
if logical(status.ResultOk)
    completion = "completed_success";
elseif ~logical(status.RuntimeExecutionOk)
    completion = "failed_during_runtime";
elseif ~logical(status.ReportingPipelineOk)
    completion = "completed_with_reporting_failure";
elseif ~logical(status.ArtifactValidationOk)
    completion = "completed_with_artifact_failure";
elseif ~logical(status.RuntimeJournalOk) || ~logical(status.WorkerShutdownOk) || ~logical(status.InfrastructureAuditOk)
    completion = "infrastructure_failure";
else
    completion = "completed_with_validation_failures";
end
end
