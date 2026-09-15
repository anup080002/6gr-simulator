function assertBrowserMaterializationSucceeded(result)
% A failed producer is not a status/hash convergence failure. The caller
% must persist its publication receipt before raising this exact diagnostic.
assert(isstruct(result) && isscalar(result), ...
    'sixgr:artifact:InvalidMaterializationResult','One actual materializer result is required.');
ok=sixgr.util.structGet(result,'Ok',false);
code=sixgr.util.structGet(result,'Status',NaN);
if islogical(ok) && isscalar(ok) && ok && ...
        isnumeric(code) && isscalar(code) && isfinite(code) && code==0
    return;
end
identifier=string(sixgr.util.structGet(result,'Identifier',"materializer_result_unavailable"));
message=string(sixgr.util.structGet(result,'Message',"No successful materialization result was returned."));
assert(isscalar(identifier) && isscalar(message), ...
    'sixgr:artifact:InvalidMaterializationResult','Materializer diagnostics must be scalar text.');
error('sixgr:artifact:BrowserMaterializationFailed', ...
    'Browser materialization failed before terminal status convergence: %s | %s', ...
    identifier,message);
end
