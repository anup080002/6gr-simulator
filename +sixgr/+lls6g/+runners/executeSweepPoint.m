function receipt = executeSweepPoint(execute, errorPolicy)
%EXECUTESWEEPPOINT Record orchestration outcomes, never substitute PHY output.
% Configuration validation belongs before this boundary. A caught execution
% failure has no returned result and can never be counted as an accepted run.
arguments
    execute (1,1) function_handle
    errorPolicy (1,1) string {mustBeMember(errorPolicy, ...
        ["abort", "retain_failure_and_continue"])}
end
receipt = struct('Ok',false,'Returned',false,'ExecutionStatus',"execution_error", ...
    'ErrorIdentifier',"",'ErrorMessage',"",'ErrorReport',"");
try
    result = execute();
catch failure
    % Do not carry on after resource exhaustion or an explicit interruption.
    if errorPolicy == "abort" || any(string(failure.identifier) == ...
            ["MATLAB:nomem", "MATLAB:OperationTerminated", "MATLAB:ExecutionInterrupted"])
        rethrow(failure);
    end
    receipt.ErrorIdentifier = string(failure.identifier);
    receipt.ErrorMessage = string(failure.message);
    receipt.ErrorReport = string(getReport(failure,'extended','hyperlinks','off'));
    return;
end
% A malformed execution API is a programming error, not a physical outage.
assert(isstruct(result) && isscalar(result) && isfield(result,'Ok') && ...
    islogical(result.Ok) && isscalar(result.Ok), ...
    'sixgr:lls6g:runner:InvalidSweepPointResult', ...
    'A sweep execution must return a scalar struct with a logical scalar Ok.');
receipt.Returned = true;
receipt.Ok = result.Ok;
if result.Ok
    receipt.ExecutionStatus = "completed_pass";
else
    receipt.ExecutionStatus = "completed_fail";
end
end
