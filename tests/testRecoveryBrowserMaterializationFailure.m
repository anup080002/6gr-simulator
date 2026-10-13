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
for field=["MissingTableCount","MissingChartCount"]
    for count=[NaN 1 -1]
        malformed=passed; malformed.(field)=count;
        reject(malformed,"");
    end
    malformed=rmfield(passed,field); reject(malformed,"");
    malformed=passed; malformed.(field)="0"; reject(malformed,"");
    malformed=passed; malformed.(field)=[0 0]; reject(malformed,"");
end
malformed=passed; malformed.BrowserMaterialized=false; reject(malformed,"");
reject(struct(),"No successful materialization result was returned.");
wrapper=fileread(which('sixgr.artifact.materializeBrowserContractArtifacts'));
for backend=["filesystem","database"]
    coverage=strfind(wrapper,"if ~localMaterializationCoverageComplete("+backend+"Result)");
    if backend=="filesystem", persisted=strfind(wrapper,'out.FilesystemPersisted = true;');
    else, persisted=strfind(wrapper,'out.DatabasePersisted = true;'); end
    assert(isscalar(coverage) && isscalar(persisted) && coverage<persisted, ...
        'Unparsed or nonzero coverage cannot become persisted browser success.');
end
source=fileread(which('sixgr.truth.recoverLLSRunArtifacts'));
guard=strfind(source,'sixgr.artifact.assertBrowserMaterializationSucceeded(contractMaterialization);');
receiptWrite=strfind(source,'reportBundle.BrowserPublicationReceipt = browserReceipt;');
loop=strfind(source,'for terminalPass = 1:3');
assert(isscalar(guard) && receiptWrite(1)<guard && guard<loop(1), ...
    'The normal recovery path must preserve the receipt and fail before retrying status convergence.');
% Wiring guard only: actual publication is separately verified on retained
% receiver evidence. Both first publication and terminal rechecks must use
% the same explicit mode; disabling bulk replacement is not disabling audits.
for producer=["materializeBrowserContractArtifacts","sealBrowserArtifactClosure"]
    pattern=['sixgr\.artifact\.' char(producer) ...
        '\([^;]*"ReplaceExistingRastersFromCSV",\s*p\.Results\.ReplaceExistingRastersFromCSV'];
    assert(~isempty(regexp(source,pattern,'once')), ...
        'Recovery must forward its raster-replacement mode to %s.',producer);
end
closure=fileread(which('sixgr.artifact.sealBrowserArtifactClosure'));
guard=strfind(closure,'sixgr.artifact.assertBrowserMaterializationSucceeded(materialization);');
receiptWrite=strfind(closure,'sixgr.artifact.writeBrowserPublicationReceipt(');
assert(isscalar(guard) && receiptWrite(1)<guard && ...
    contains(closure,'if options.Required'), ...
    'Terminal closure must preserve the failed producer receipt and not repeatedly retry invalid source data.');
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
