function ok=testExceptionDiagnosticPreservation()
% Diagnostic failure stimuli only; no radio samples or acceptance outcomes.
original=MException('sixgr:test:OriginalFailure','Original rejection remains failed.');
[text,d]=sixgr.util.formatExceptionDiagnostic(original);
assert(d.ExtendedReportAvailable && contains(text,original.message));
assert(strcmp(d.OriginalIdentifier,original.identifier) && strcmp(d.OriginalMessage,original.message));
assert(isempty(d.RenderingErrorIdentifier));
for formatter={@localRenderingFailure,@(~)strings(2,1),@(~)""}
    [text,d]=sixgr.util.formatExceptionDiagnostic(original,formatter{1});
    assert(~d.ExtendedReportAvailable && strcmp(text,original.message));
    assert(strcmp(d.OriginalIdentifier,original.identifier) && strcmp(d.OriginalMessage,original.message));
    assert(~isempty(d.RenderingErrorIdentifier));
end
[~,d]=sixgr.util.formatExceptionDiagnostic(original,@localRenderingFailure);
assert(strcmp(d.RenderingErrorIdentifier,'MATLAB:nomem'));
assert(strcmp(original.identifier,'sixgr:test:OriginalFailure'));
assert(strcmp(original.message,'Original rejection remains failed.'));
% A supplied formatter receives this exact original error, not a replacement.
[text,d]=sixgr.util.formatExceptionDiagnostic(original,@localCheckedRendering);
assert(d.ExtendedReportAvailable && strcmp(text,'rendered original failure'));
ok=true;
fprintf('EXCEPTION_DIAGNOSTIC_PRESERVATION_PASS: formatter rejection cannot replace original error.\n');
end

function text=localRenderingFailure(~)
error('MATLAB:nomem','Declared diagnostic-renderer failure; no memory pressure is induced.');
text=''; %#ok<UNRCH>
end

function text=localCheckedRendering(cause)
assert(strcmp(cause.identifier,'sixgr:test:OriginalFailure'));
text='rendered original failure';
end
