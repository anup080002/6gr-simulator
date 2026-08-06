function ok = testLLSSupplementalValidatorFailureIsolation()
%TESTLLSSUPPLEMENTALVALIDATORFAILUREISOLATION Guard typed fail-closed capture.

setup6GRSimToolkit("Verbose", false);

failed = sixgr.lls6g.runners.executeSupplementalValidator( ...
    "PRACH_StrictValidation", @localThrowTypedFailure);
assert(~failed.Ok && ~failed.StrictOk, ...
    "A thrown supplemental validator must be captured as a failure.");
assert(string(failed.ExceptionIdentifier) == "sixgr:test:FocusedSupplementalFailure", ...
    "The original typed error identifier must be preserved.");
assert(contains(string(failed.FailureReason), "focused validator failure"), ...
    "The original error message must be preserved in fail-closed evidence.");

secondExecuted = false;
passed = sixgr.lls6g.runners.executeSupplementalValidator( ...
    "SRS_StrictValidation", @localSuccess);
secondExecuted = true;
assert(secondExecuted && passed.Ok && passed.StrictOk, ...
    "A prior independent validator failure must not prevent the next validator from executing.");

invalid = sixgr.lls6g.runners.executeSupplementalValidator( ...
    "InvalidResult", @() 42);
assert(~invalid.StrictOk && ...
    string(invalid.ExceptionIdentifier) == "sixgr:lls6g:SupplementalValidatorInvalidResult", ...
    "Invalid validator return types must fail closed with a typed contract error.");

ok = true;
end

function out = localThrowTypedFailure()
error("sixgr:test:FocusedSupplementalFailure", "focused validator failure");
out = struct(); %#ok<UNRCH>
end

function out = localSuccess()
out = struct("Ok", true, "StrictOk", true, "FailureReason", "");
end
