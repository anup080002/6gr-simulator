function ok=testRecoveryBrowserMaterializationFailure()
% Exact producer diagnostics and fail-closed receipts, not full recovery.
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
passed=struct('Ok',true,'Status',0,'Identifier',"filesystem_browser_contract_verification_ok", ...
    'Message',"",'FilesystemPersisted',true,'BrowserMaterialized',true, ...
    'MissingTableCount',0,'MissingChartCount',0,'PublicationBackend',"filesystem", ...
    'RunID',"unit_failed_materialization",'GeneratedAtUTC',"2026-09-15T16:00:00Z");
sixgr.artifact.assertBrowserMaterializationSucceeded(passed);
reason="Run folder contains header-only or empty authority CSVs: air_interface/csv/ul_pusch_trials.csv";
failed=passed; failed.Ok=false; failed.Status=1;
failed.Identifier="browser_contract_materialization_failed"; failed.Message=reason;
failed.FilesystemPersisted=false; failed.BrowserMaterialized=false;
failed.MissingTableCount=NaN; failed.MissingChartCount=NaN;
receipt=sixgr.artifact.writeBrowserPublicationReceipt(folder,failed);
before=fileread(receipt.Path);
reject(failed,reason);
assert(strcmp(before,fileread(receipt.Path)) && receipt.Status=="FAIL" && ...
    ~receipt.BrowserMaterialized && isnan(receipt.MissingRequiredTableCount), ...
    'Fail-fast diagnostics must not alter failed receipts or invent missing coverage counts.');
for code=[1 NaN]
    malformed=passed; malformed.Status=code;
    reject(malformed,"");
end
reject(struct(),"No successful materialization result was returned.");
source=fileread(which('sixgr.truth.recoverLLSRunArtifacts'));
guard=strfind(source,'sixgr.artifact.assertBrowserMaterializationSucceeded(contractMaterialization);');
receiptWrite=strfind(source,'reportBundle.BrowserPublicationReceipt = browserReceipt;');
loop=strfind(source,'for terminalPass = 1:3');
assert(isscalar(guard) && receiptWrite(1)<guard && guard<loop(1), ...
    'The normal recovery path must preserve the receipt and fail before retrying status convergence.');
fprintf('RECOVERY_MATERIALIZER_FAILURE_PASS exact_cause_preserved=1 failed_receipt_unchanged=1 folder=%s\n',folder);
ok=true;
end
function reject(result,message)
try, sixgr.artifact.assertBrowserMaterializationSucceeded(result); catch cause
    assert(strcmp(cause.identifier,'sixgr:artifact:BrowserMaterializationFailed'));
    assert(contains(string(cause.message),message));
    return;
end
error('test:MissingFailure','An unsuccessful materializer result must fail closed.');
end
