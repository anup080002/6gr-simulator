function ok=testSlotCheckpointLongPath()
% Exact filesystem checkpoint mechanics, not a PHY performance population.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'logs','lls_repairs', ...
    ['checkpoint_path_' char(java.util.UUID.randomUUID)]);
while strlength(string(root))<235
    root=fullfile(root,'long_checkpoint_directory');
end
mkdir(root);
scenario=struct('run_control',struct('runtime_checkpoint_keep',2));
identity=struct('RunId',"long_path_checkpoint_fixture", ...
    'ExecutionID',"explicit_persistence_fixture",'ConfigHash',"fixture_hash");
sixgr.runtime.RuntimeCallLedger.configure(root,identity);
cleanup=onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
sixgr.runtime.RuntimeCallLedger.record(mfilename,'CHECKPOINT_TEST','DL',struct('Slot',5));
prefix=sixgr.runtime.RuntimeCallLedger.snapshot();
payload=struct('RuntimeState',struct('CurrentSlot',5, ...
    'IQ',complex(reshape(1:24,6,4),reshape(24:-1:1,6,4)), ...
    'UnavailableMeasurement',NaN),'CompletedSlot',5,'RNG',rng, ...
    'ConfigHash',identity.ConfigHash);
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
checkpoint=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,source);
assert(strlength(string(checkpoint))>285,'Regression must exercise a long absolute MAT path.');
[saved,receipt]=sixgr.runtime.SlotCheckpoint.read(checkpoint,scenario,"");
assert(isequaln(saved.RuntimeState,payload.RuntimeState) && isequal(saved.RNG,payload.RNG));
assert(receipt.RuntimeCallLedgerRequired && receipt.CompletedSlotOneBased==5 && ...
    receipt.NextSlotOneBased==6 && ~receipt.SourceChanged && ~receipt.PrimaryStudyEligible);
assert(~isfile(fullfile(fileparts(checkpoint),'state.partial.mat')), ...
    'Committed checkpoint must not leave an incomplete MAT payload.');
sixgr.runtime.RuntimeCallLedger.record(mfilename,'CHECKPOINT_TEST','DL',struct('Slot',6));
sixgr.runtime.RuntimeCallLedger.flush();
[restoredRoot,lineage]=sixgr.runtime.SlotCheckpoint.prepareResume(checkpoint,scenario,"",true);
assert(strcmp(restoredRoot,root) && isfolder(lineage.PreservedFailedAttempt));
identity.PreserveExisting=true;
sixgr.runtime.RuntimeCallLedger.configure(root,identity);
assert(isequaln(sixgr.runtime.RuntimeCallLedger.snapshot(),prefix), ...
    'Long-path restore must preserve exactly the recorded call prefix.');
assert(strcmp(receipt.StateSHA256,sixgr.util.sha256File(checkpoint)));
fprintf('SLOT_CHECKPOINT_LONG_PATH_PASS path_characters=%d\n',strlength(string(checkpoint)));
ok=true;
end
