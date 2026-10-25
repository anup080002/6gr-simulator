function cfg = restorePersistedExecutionIdentity(cfg, runFolder, recoveryOptions)
%RESTOREPERSISTEDEXECUTIONIDENTITY Bind report recovery to its original run.
% Rebuilding a runtime config from resolved YAML does not recreate the UUID
% assigned before waveform execution. Recover it before reading scoped RF
% evidence; never mint a new execution or rewrite retained evidence.
arguments
    cfg (1,1) struct
    runFolder {mustBeTextScalar}
    recoveryOptions.AllowUnscopedRecovery (1,1) logical = false
end
options = struct("ResumeCompletedRuntimeFinalization", true);
try
identity = sixgr.runtime.resolveExecutionIdentity(runFolder, ...
    string(sixgr.util.structGet(cfg,"run.runTag","")), ...
    string(sixgr.util.structGet(cfg,"meta.configHash","")), options);
catch cause
    % Older partial reports may have no execution-scoped evidence at all.
    % Only that exact absence is admissible; malformed/conflicting identity
    % and any scoped RF file remain failures. Never invent a replacement ID.
    layout=sixgr.report.resultLayout(runFolder);
    scopedRF=isfile(fullfile(layout.RFCSVDir,'rf_endpoint_execution_manifest.json')) || ...
        isfile(fullfile(layout.RFCSVDir,'rf_endpoint_execution_intervals.csv'));
    identityDocumentPresent=isfile(fullfile(runFolder,'meta','execution_identity.json'));
    suppliedRun=string(sixgr.util.structGet(cfg,'run.executionID',''));
    suppliedMeta=string(sixgr.util.structGet(cfg,'meta.executionID',''));
    noSupplied=isscalar(suppliedRun) && isscalar(suppliedMeta) && ...
        strlength(strtrim(suppliedRun))==0 && strlength(strtrim(suppliedMeta))==0;
    if recoveryOptions.AllowUnscopedRecovery && ...
            strcmp(cause.identifier,'sixgr:runtime:ResumeExecutionIdentityMissing') && ...
            ~scopedRF && ~identityDocumentPresent && noSupplied
        return;
    end
    rethrow(cause);
end
for path = ["run.executionID","meta.executionID"]
    supplied = strtrim(string(sixgr.util.structGet(cfg,path,"")));
    assert(isscalar(supplied) && (strlength(supplied)==0 || ...
        supplied==identity.ExecutionID), ...
        'sixgr:runtime:ExecutionIdentityMismatch', ...
        'Recovery configuration %s disagrees with retained execution identity.',path);
end
cfg.run.executionID = char(identity.ExecutionID);
cfg.meta.executionID = char(identity.ExecutionID);
end
