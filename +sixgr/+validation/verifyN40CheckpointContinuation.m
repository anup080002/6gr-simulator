function receipt=verifyN40CheckpointContinuation(referenceFolder,diagnosticFolder,options)
% Resume the criteria-selected native interval, preserving the complete baseline.
% This executes the production continuation. Never call concurrently with a run.
arguments
    referenceFolder {mustBeTextScalar}
    diagnosticFolder {mustBeTextScalar}
    options.CriteriaPath {mustBeTextScalar} = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'simulator','configs','validation','n40_integration_gate.yaml')
end
criteria=sixgr.lls6g.config.readConfigFile(options.CriteriaPath);
startSlot=double(criteria.continuation_start_slot); endSlot=double(criteria.completed_slots);
assert(string(criteria.contract)=="sixgr.n40.integration_gate/v1" && ...
    isscalar(startSlot)&&isscalar(endSlot)&&isfinite(startSlot)&&isfinite(endSlot)&& ...
    startSlot==fix(startSlot)&&endSlot==fix(endSlot)&&startSlot>0&&startSlot<endSlot&& ...
    criteria.checkpoint_slot==endSlot, ...
    'sixgr:validation:ContinuationWindow','Require configured prefix < terminal checkpoint = completed horizon.');
referenceFolder=string(sixgr.util.canonicalPath(referenceFolder));
diagnosticFolder=string(sixgr.util.canonicalPath(diagnosticFolder));
assert(isfolder(referenceFolder)&&~isfolder(diagnosticFolder)&& ...
    ~startsWith(lower(diagnosticFolder),lower(referenceFolder)+filesep), ...
    'sixgr:validation:ContinuationOutput','Use a new diagnostic folder outside the original run.');
if ispc
    assert(extractBefore(lower(referenceFolder),3)==extractBefore(lower(diagnosticFolder),3), ...
        'sixgr:validation:ContinuationOutput','Use the same volume for recoverable directory renames.');
end
assert(~isfile(fullfile(referenceFolder,'meta','checkpoint_resume.json')), ...
    'sixgr:validation:ContinuationBaseline','Require an uninterrupted original baseline, not an earlier resume.');
base=sixgr.runtime.SlotCheckpoint.storageRoot(referenceFolder);
[prefixCheckpoint,prefixReceipt]=findCheckpoint(base,startSlot,"");
[baselineEndpoint,endpointReceipt]=latestEndpoint(referenceFolder,base,endSlot,"");
assert(string(prefixReceipt.RunFolder)==referenceFolder&&string(endpointReceipt.RunFolder)==referenceFolder&& ...
    string(prefixReceipt.Source.SHA256)==string(endpointReceipt.Source.SHA256), ...
    'sixgr:validation:ContinuationIdentity','Require the same original run and source.');
% Strict verify rejects changed sources; a repair reason never bypasses this gate.
sixgr.runtime.SlotCheckpoint.verify(prefixCheckpoint,"");
sixgr.runtime.SlotCheckpoint.verify(baselineEndpoint,"");
identityPath=fullfile(referenceFolder,'meta','execution_identity.json');
identity=jsondecode(fileread(identityPath));
assert(all(isfield(identity,{'RunID','ExecutionID','ConfigHash'}))&& ...
    all(strlength(string({identity.RunID,identity.ExecutionID,identity.ConfigHash}))>0), ...
    'sixgr:validation:ContinuationIdentity','Require original execution identity.');
mkdir(diagnosticFolder);
inventory=inventoryFolder(referenceFolder);
inventoryPath=fullfile(diagnosticFolder,'baseline_inventory.csv');
sixgr.util.csvWriteTable(inventoryPath,inventory,'PreserveSchema',true);
baseline=projection(baselineEndpoint,endpointReceipt,endSlot);
assert(string(baseline.ConfigHash)==string(identity.ConfigHash), ...
    'sixgr:validation:ContinuationIdentity','Native checkpoint/config identity differs.');
projectionPath=fullfile(diagnosticFolder,'baseline_projection.mat');
sixgr.util.matSave(projectionPath,struct('baseline',baseline),'UseArtifactStore',false,'ForceV73',true);
clear baseline
requestPath=fullfile(diagnosticFolder,'continuation_request.yaml');
request=struct('contract','sixgr_checkpoint_continuation/v1','checkpoint',prefixCheckpoint, ...
    'state_sha256',prefixReceipt.StateSHA256,'config_hash',identity.ConfigHash, ...
    'repair_reason','same-source exact configured continuation equivalence diagnostic');
sixgr.util.jsonWrite(requestPath,struct('checkpoint_continuation',request));
plan=struct('CheckpointPath',prefixCheckpoint,'BaselineEndpointCheckpoint',baselineEndpoint, ...
    'CheckpointSlot',startSlot,'FinalCompletedSlot',endSlot, ...
    'CheckpointStateSHA256',prefixReceipt.StateSHA256,'BaselineStateSHA256',endpointReceipt.StateSHA256, ...
    'ReferenceFolder',referenceFolder,'BaselineInventoryPath',inventoryPath, ...
    'BaselineInventorySHA256',sixgr.util.sha256File(inventoryPath), ...
    'BaselineProjectionSHA256',sixgr.util.sha256File(projectionPath), ...
    'Identity',identity,'SourceSHA256',prefixReceipt.Source.SHA256);
sixgr.util.jsonWrite(fullfile(diagnosticFolder,'continuation_plan.json'),plan);
% Existing prepareResume/lease/archive machinery owns the only native restore.
try
runOutput=sixgr.lls6g.runners.runSingle(requestPath);
resumedAcceptance=sixgr.validation.evaluateN40IntegrationGate( ...
    referenceFolder,'RequireContinuation',false,'CriteriaPath',options.CriteriaPath);
acceptanceDocument=resumedAcceptance;
acceptanceDocument.Checks=table2struct(resumedAcceptance.Checks);
acceptanceDocument.RadioOutcomes=table2struct(resumedAcceptance.RadioOutcomes);
acceptanceDocument.RunOutputOk=isfield(runOutput,'Ok')&&isequal(runOutput.Ok,true);
acceptancePath=fullfile(diagnosticFolder,'resumed_acceptance.json');
sixgr.util.jsonWrite(acceptancePath,acceptanceDocument);
lineage=jsondecode(fileread(fullfile(referenceFolder,'meta','checkpoint_resume.json')));
preserved=string(lineage.PreservedFailedAttempt);
assert(isfolder(preserved)&&string(lineage.Checkpoint)==prefixCheckpoint, ...
    'sixgr:validation:ContinuationLineage','Require the actual native archive receipt.');
[resumedEndpoint,resumedReceipt]=latestEndpoint(referenceFolder,base,endSlot,baselineEndpoint);
sixgr.runtime.SlotCheckpoint.verify(resumedEndpoint,"");
resumed=projection(resumedEndpoint,resumedReceipt,endSlot);
saved=sixgr.util.loadVerifiedMAT(projectionPath,plan.BaselineProjectionSHA256,"baseline");
checks=sixgr.validation.compareN40ContinuationProjections(saved.baseline,resumed, ...
    'StartSlot',startSlot,'EndSlot',endSlot);
checks(end+1,:)={"ResumedFinalReports", ...
    acceptanceDocument.RunOutputOk&&resumedAcceptance.Ok, ...
    "production_return_Ok_and_required_final_report_acceptance"};
clear saved resumed
after=inventoryFolder(preserved);
checks(end+1,:)={"PreservedOriginalBytes",isequaln(inventory,after),"every_original_file_relative_path_size_SHA256"};
checks(end+1,:)={"SameSource",string(resumedReceipt.Source.SHA256)==string(prefixReceipt.Source.SHA256),"native_checkpoint_source_SHA256"};
currentIdentity=jsondecode(fileread(identityPath));
checks(end+1,:)={"SameExecutionIdentity",isequaln(identity,currentIdentity),"original_execution_identity"};
% Parent sweep indexes still bind the original canonical child's bytes.
% Archive the diagnostic as completed evidence; never rebase its native state.
resumedArchive=restoreBaseline(referenceFolder,diagnosticFolder,inventory,prefixCheckpoint);
checks(end+1,:)={"RestoredOriginalBytes",isequaln(inventory,inventoryFolder(referenceFolder)), ...
    "original_canonical_publication_restored_before_audit_receipt"};
checksPath=fullfile(diagnosticFolder,'continuation_checks.csv');
sixgr.util.csvWriteTable(checksPath,checks,'PreserveSchema',true);
receipt=struct('ContractVersion',"sixgr.n40.checkpoint_continuation/v1", ...
    'Ok',all(checks.Passed),'Compared',true,'Equivalent',all(checks.Passed), ...
    'CheckpointSlot',startSlot,'NextSlot',startSlot+1,'FinalCompletedSlot',endSlot, ...
    'RunID',identity.RunID,'ExecutionID',identity.ExecutionID,'ConfigHash',identity.ConfigHash, ...
    'SourceSHA256',prefixReceipt.Source.SHA256,'CheckpointStateSHA256',prefixReceipt.StateSHA256, ...
    'CheckpointPath',prefixCheckpoint,'BaselineEndpointCheckpoint',baselineEndpoint, ...
    'ResumedEndpointCheckpoint',resumedEndpoint,'BaselineEndpointStateSHA256',endpointReceipt.StateSHA256, ...
    'ResumedEndpointStateSHA256',resumedReceipt.StateSHA256, ...
    'ReferenceFolder',referenceFolder,'ResumedFolder',resumedArchive, ...
    'OriginalRecoveryArchive',preserved,'NativeLineageRunFolder',referenceFolder, ...
    'RelocatedDiagnosticResumeSupported',false, ...
    'ChecksPath',checksPath,'ChecksSHA256',sixgr.util.sha256File(checksPath), ...
    'ResumedAcceptancePath',acceptancePath,'ResumedAcceptanceSHA256',sixgr.util.sha256File(acceptancePath), ...
    'BaselineInventoryPath',inventoryPath,'BaselineInventorySHA256',plan.BaselineInventorySHA256, ...
    'StateCoverageLimits',"Exact global RNG, pending UL grants, full retained scheduler/grant/HARQ/TB tables, physical clocks and original channel/RF execution receipts through the configured endpoint, including exact scheduler MCS transition state. Private native CDL/RF/HARQ memory is restored by production serialization but not independently byte-compared; future behavior beyond the configured endpoint and standards conformance are not qualified.");
receipt.Path=fullfile(referenceFolder,'meta','n40_checkpoint_continuation.json');
assert(~isfile(receipt.Path),'sixgr:validation:ContinuationReceiptExists','Never overwrite prior continuation evidence.');
sixgr.util.jsonWrite(receipt.Path,receipt);
assert(receipt.Ok,'sixgr:validation:ContinuationMismatch', ...
    'Continuation failed; inspect preserved evidence and %s.',checksPath);
catch cause
    % A receiver/finalization failure may occur after the native archive was
    % created. Restore the baseline even when no equivalence receipt exists.
    try
        restoreBaseline(referenceFolder,diagnosticFolder,inventory,prefixCheckpoint);
    catch restoreError
        cause=addCause(cause,restoreError);
    end
    failure=struct('Ok',false,'ErrorIdentifier',cause.identifier, ...
        'ErrorReport',getReport(cause,'extended','hyperlinks','off'), ...
        'ReferenceFolder',referenceFolder,'DiagnosticFolder',diagnosticFolder, ...
        'CheckpointPath',prefixCheckpoint,'NoPrimaryScienceRepublication',true);
    sixgr.util.jsonWrite(fullfile(diagnosticFolder,'continuation_failure.json'),failure);
    rethrow(cause);
end
end

function diagnostic=restoreBaseline(root,folder,inventory,checkpoint)
root=string(sixgr.util.canonicalPath(root));
folder=string(sixgr.util.canonicalPath(folder));
diagnostic=string(sixgr.util.canonicalPath(fullfile(folder,'resumed_run')));
assert(startsWith(lower(diagnostic),lower(folder)+filesep)&&diagnostic~=root&& ...
    ~startsWith(lower(folder),lower(root)+filesep), ...
    'sixgr:validation:ContinuationMovePath','Diagnostic must stay within the declared separate directory.');
lineagePath=fullfile(root,'meta','checkpoint_resume.json');
if ~isfile(lineagePath)
    % No native mutation yet, or the original baseline is already restored.
    assert(isfolder(root),'sixgr:validation:ContinuationRestore','Original canonical directory is missing.');
    return;
end
lineage=jsondecode(fileread(lineagePath));
preserved=string(sixgr.util.canonicalPath(lineage.PreservedFailedAttempt));
base=string(sixgr.util.canonicalPath(sixgr.runtime.SlotCheckpoint.storageRoot(root)));
[parent,leaf]=fileparts(preserved);
assert(string(sixgr.util.canonicalPath(lineage.Checkpoint))==checkpoint&& ...
    parent==base&&startsWith(leaf,"recovery_")&&isfolder(preserved)&& ...
    ~isfolder(diagnostic)&&~isfile(diagnostic), ...
    'sixgr:validation:ContinuationMovePath','Require the exact native recovery archive and a new diagnostic destination.');
assert(isequaln(inventory,inventoryFolder(preserved)), ...
    'sixgr:validation:ContinuationRestoreIntegrity','The preserved original differs; do not replace canonical state.');
movefile(root,diagnostic);
try
    movefile(preserved,root);
catch cause
    if ~isfolder(root), movefile(diagnostic,root); end
    rethrow(cause);
end
end

function [path,receipt]=findCheckpoint(base,slot,excluded)
entries=dir(fullfile(base,sprintf('after_slot_%06d_*',slot),'checkpoint.json'));
paths=strings(0,1); records=cell(0,1);
for k=1:numel(entries)
    candidate=string(fullfile(entries(k).folder,'state.mat'));
    if candidate==excluded, continue; end
    record=jsondecode(fileread(fullfile(entries(k).folder,entries(k).name)));
    if string(record.Status)=="complete"
        assert(record.CompletedSlotOneBased==slot&&record.NextSlotOneBased==slot+1, ...
            'sixgr:validation:EndpointCheckpoint','Checkpoint receipt must name its actual completed slot.');
        paths(end+1)=candidate; records{end+1}=record; %#ok<AGROW>
    end
end
assert(numel(paths)==1,'sixgr:validation:AmbiguousCheckpoint', ...
    'Require exactly one original completed checkpoint at slot%d.',slot);
path=paths(1); receipt=records{1};
end

function [path,receipt]=latestEndpoint(root,base,slot,excluded)
pointer=jsondecode(fileread(fullfile(root,'meta','latest_slot_checkpoint.json')));
path=string(sixgr.util.canonicalPath(pointer.Checkpoint));
entries=dir(fullfile(base,sprintf('after_slot_%06d_*',slot),'checkpoint.json'));
candidates=strings(numel(entries),1);
for k=1:numel(entries)
    candidates(k)=string(sixgr.util.canonicalPath(fullfile(entries(k).folder,'state.mat')));
end
assert(any(path==candidates)&&path~=excluded&& ...
    pointer.CompletedSlotOneBased==slot&&pointer.NextSlotOneBased==slot+1, ...
    'sixgr:validation:EndpointCheckpoint','Latest run pointer must bind the actual required endpoint generation.');
receipt=jsondecode(fileread(fullfile(fileparts(path),'checkpoint.json')));
assert(string(receipt.Status)=="complete"&&receipt.CompletedSlotOneBased==slot&& ...
    receipt.NextSlotOneBased==slot+1, ...
    'sixgr:validation:EndpointCheckpoint','Endpoint receipt and run pointer disagree.');
end

function out=projection(path,receipt,endSlot)
saved=sixgr.util.loadVerifiedMAT(path,string(receipt.StateSHA256),"payload");
p=saved.payload; s=p.RuntimeState;
assert(p.CompletedSlot==endSlot&&s.CurrentSlot==endSlot, ...
    'sixgr:validation:EndpointCheckpoint','Require the configured completed endpoint native checkpoint.');
out=struct();
for name=["CompletedSlot","ConfigHash","RNG","PendingULGrants","DLTrials","ULTrials"]
    assert(isfield(p,name),'sixgr:validation:MissingContinuationEvidence','Missing payload %s.',name);
    out.(name)=p.(name);
end
for name=["SlotTraceTable","SchedulerDecisionTable","DLGrantTraceTable","ULGrantTraceTable","HARQTimelineTable"]
    assert(isfield(s,name)&&istable(s.(name)), ...
        'sixgr:validation:MissingContinuationEvidence','Missing runtime table %s.',name);
    out.(name)=s.(name);
end
out.SchedulerMCSTransitionState=struct();
for direction=["DL","UL"]
    field=direction+"Schedulers";
    assert(isfield(s,field)&&iscell(s.(field))&&~isempty(s.(field)), ...
        'sixgr:validation:MissingContinuationEvidence','Missing native %s.',field);
    schedulers=s.(field); states=cell(size(schedulers));
    for cellIndex=1:numel(schedulers)
        scheduler=schedulers{cellIndex};
        assert(isa(scheduler,'sixgr.l2.mac.SchedulerBase')&&ismethod(scheduler,'getMCSTransitionState'), ...
            'sixgr:validation:MissingContinuationEvidence','Missing native scheduler policy state.');
        states{cellIndex}=struct('SchedulerClass',string(class(scheduler)), ...
            'State',scheduler.getMCSTransitionState());
    end
    out.SchedulerMCSTransitionState.(direction)=states;
end
owner=s.SharedWaveformStream;
assert(isa(owner,'sixgr.truth.CoupledWaveformStream')&& ...
    owner.Events.ProcessorState==owner.Physical&&~owner.Physical.Faulted&&~owner.Events.Faulted, ...
    'sixgr:validation:NativeContinuationOwner','Require the original shared native owner.');
out.PhysicalClock=struct('SampleRateHz',owner.SampleRateHz, ...
    'EventsNextSampleIndex',owner.Events.NextSampleIndex, ...
    'PhysicalNextSampleIndex',owner.Physical.NextSampleIndex, ...
    'ConfigurationEpoch',owner.Physical.ConfigurationEpoch);
out.PhysicalExecutionTrace=owner.Events.ExecutionTrace;
out.RFExecutionLedger=owner.Physical.readRFExecutionLedger();
end

function T=inventoryFolder(folder)
entries=dir(fullfile(folder,'**','*')); entries=entries(~[entries.isdir]);
relative=strings(numel(entries),1); hashes=relative; bytes=zeros(numel(entries),1);
for k=1:numel(entries)
    path=string(fullfile(entries(k).folder,entries(k).name));
    relative(k)=replace(extractAfter(path,strlength(string(folder))+1),'\','/');
    bytes(k)=entries(k).bytes; hashes(k)=sixgr.util.sha256File(path);
end
T=table(relative,bytes,hashes,'VariableNames',{'RelativePath','Bytes','SHA256'});
T=sortrows(T,'RelativePath');
end
