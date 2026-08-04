function status = applyCompletedRefinalizationVerdict(status, verdict, finalizationMode)
%APPLYCOMPLETEDREFINALIZATIONVERDICT Reduce a completed-run recovery verdict.
%
% Failed/aborted recovery remains fail-closed. Only the explicit
% completed_run_refinalization mode may promote a run, and only when both
% the runtime truth contract and canonical root status pass.

if nargin < 3 || lower(strtrim(string(finalizationMode))) ~= ...
        "completed_run_refinalization"
    return;
end

rootStatus = sixgr.util.structGet(verdict, "ResultStatus", struct());
rootOk = logical(sixgr.util.structGet(rootStatus, "ResultOk", false));
truthOk = logical(sixgr.util.structGet(verdict, "RuntimeTruthContractOk", ...
    sixgr.util.structGet(verdict, "Ok", false)));
failures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
failures = failures(strlength(strtrim(failures)) > 0);

if truthOk && rootOk
    status.RunCompletion = "completed";
    status.ResultOk = true;
    status.PartialOk = false;
    status.RequiredFailureCount = 0;
    status.RequiredFailedCases = strings(0, 1);
    status.FailingCaseCount = 0;
    status.CaseOk = true;
    status.ErrorSource = "";
    status.ErrorIdentifier = "";
    status.ErrorMessage = "";
    status.StatusAuthority = "completed_run_refinalization_truth_contract";
    status.AuthoritativeStatusSource = "runtime_truth_contract_after_resumable_finalization";
    status.StatusNotes = "Completed waveform evidence was re-finalized and passed every canonical root gate.";
else
    status.RunCompletion = "completed_with_failures";
    status.ResultOk = false;
    status.PartialOk = true;
    status.RequiredFailureCount = max(1, numel(failures));
    if isempty(failures)
        reason = string(sixgr.util.structGet(rootStatus, ...
            "ResultStatusReason", "completed_run_refinalization_failed"));
        failures = reason;
    end
    status.RequiredFailedCases = failures(:);
    status.FailingCaseCount = numel(failures);
    status.CaseOk = false;
    status.StatusAuthority = "completed_run_refinalization_truth_contract";
    status.AuthoritativeStatusSource = "runtime_truth_contract_after_resumable_finalization";
end
end
