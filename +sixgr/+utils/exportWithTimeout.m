function varargout = exportWithTimeout(fn, stageName, timeoutSeconds, runDir)
%EXPORTWITHTIMEOUT Run an export stage and record elapsed-time guard status.
%
% MATLAB cannot safely interrupt arbitrary synchronous code without changing
% the execution model. This helper therefore fails loudly after the stage if
% elapsed time exceeds the declared guard, and records the stage outcome.

arguments
    fn (1,1) function_handle
    stageName {mustBeTextScalar}
    timeoutSeconds (1,1) double {mustBePositive} = 120
    runDir {mustBeTextScalar} = ""
end

stageName = string(stageName);
runDir = string(runDir);
t = tic;
status = "started";
message = "";
try
    if nargout > 0
        [varargout{1:nargout}] = fn();
    else
        fn();
    end
    elapsed = toc(t);
    if elapsed > timeoutSeconds
        status = "timeout_exceeded";
        message = sprintf("stage exceeded %.3f s guard with %.3f s elapsed", timeoutSeconds, elapsed);
        localWriteStage(runDir, stageName, status, elapsed, timeoutSeconds, message);
        error("sixgr:utils:exportWithTimeout:TimeoutExceeded", "%s", message);
    end
    status = "ok";
    localWriteStage(runDir, stageName, status, elapsed, timeoutSeconds, message);
catch ME
    elapsed = toc(t);
    if status ~= "timeout_exceeded"
        status = "failed";
        message = string(ME.identifier) + ": " + string(ME.message);
        localWriteStage(runDir, stageName, status, elapsed, timeoutSeconds, message);
    end
    rethrow(ME);
end
end

function localWriteStage(runDir, stageName, status, elapsed, timeoutSeconds, message)
if strlength(strtrim(runDir)) == 0
    return;
end
path = fullfile(runDir, "reports", "csv", "export_stage_status.csv");
row = table(stageName, status, elapsed, timeoutSeconds, string(message), sixgr.util.utcNowISO8601(), ...
    'VariableNames', {'StageName','Status','Elapsed_s','Timeout_s','Message','GeneratedAt'});
if exist(path, "file") == 2
    try
        old = readtable(path, "TextType", "string", "VariableNamingRule", "preserve");
        row = [old; row]; %#ok<AGROW>
    catch
    end
end
sixgr.analytics.writeAnalysisTable(path, row);
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:utils:exportWithTimeout:BadType", "Value must be a char vector or string scalar.");
end
end
