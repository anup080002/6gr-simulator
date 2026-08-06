function result = executeSupplementalValidator(caseName, runner)
%EXECUTESUPPLEMENTALVALIDATOR Run one independent strict validator fail-closed.
%
% A supplemental evidence producer must not prevent later independent
% producers from running.  Exceptions are converted into typed failure
% evidence; they are never converted into a pass or placeholder evidence.

arguments
    caseName (1,1) string
    runner (1,1) function_handle
end

try
    result = runner();
    if ~(isstruct(result) && isscalar(result))
        error("sixgr:lls6g:SupplementalValidatorInvalidResult", ...
            "Supplemental validator '%s' returned %s instead of a scalar struct.", ...
            caseName, class(result));
    end
catch cause
    identifier = string(cause.identifier);
    if strlength(identifier) == 0
        identifier = "MATLAB:unidentifiedError";
    end
    message = string(cause.message);
    result = struct( ...
        "Ok", false, ...
        "StrictOk", false, ...
        "FailureReason", identifier + " | " + message, ...
        "ExceptionIdentifier", identifier, ...
        "ExceptionMessage", message, ...
        "CaseName", caseName, ...
        "FailureClassification", "strict_validator_exception");
end

if ~isfield(result, "Ok")
    result.Ok = logical(sixgr.util.structGet(result, "StrictOk", false));
end
if ~isfield(result, "StrictOk")
    result.StrictOk = logical(sixgr.util.structGet(result, "Ok", false));
end
if ~logical(result.StrictOk) && ~isfield(result, "FailureReason")
    result.FailureReason = caseName + ":strict_validator_returned_failure_without_reason";
end
end
