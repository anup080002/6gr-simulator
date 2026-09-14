function [text,diagnostic]=formatExceptionDiagnostic(cause,formatter)
% Preserve the original failure if optional extended-report rendering fails.
% This is diagnostic degradation, never a successful test or PHY result.
% It cannot guarantee progress under total memory exhaustion or failed I/O.
assert(isa(cause,'MException') && isscalar(cause), ...
    'sixgr:diagnostic:InvalidException','Provide the original scalar MException.');
if nargin<2
    formatter=@(exception)getReport(exception,'extended','hyperlinks','off');
end
assert(isa(formatter,'function_handle') && isscalar(formatter), ...
    'sixgr:diagnostic:InvalidFormatter','Extended rendering requires a function handle.');
text=cause.message;
diagnostic=struct('OriginalIdentifier',cause.identifier, ...
    'OriginalMessage',cause.message,'ExtendedReportAvailable',false, ...
    'RenderingErrorIdentifier','','RenderingErrorMessage','');
try
    extended=formatter(cause);
    assert((ischar(extended) && isrow(extended) && ~isempty(extended)) || ...
        (isstring(extended) && isscalar(extended) && ~ismissing(extended) && strlength(extended)>0), ...
        'sixgr:diagnostic:InvalidExtendedReport','Extended report must be nonempty scalar text.');
    text=char(extended);
    diagnostic.ExtendedReportAvailable=true;
catch renderingFailure
    diagnostic.RenderingErrorIdentifier=renderingFailure.identifier;
    diagnostic.RenderingErrorMessage=renderingFailure.message;
end
end
