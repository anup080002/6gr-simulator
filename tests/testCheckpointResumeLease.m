function ok=testCheckpointResumeLease()
% Explicit object-load/storage fixtures; physical continuation is tested by
% testSlotCheckpoint using native CDL/RF and a real HARQ decoder soft buffer.
root=fullfile(pwd,'logs','lls_repairs',"resume_lease_"+string(java.util.UUID.randomUUID));
mkdir(root);
scenario=struct('run_control',struct('runtime_checkpoint_keep',3),'seed',57);
probe=MatSaveLoadProbe(complex(1:32,32:-1:1));
payload=struct('RuntimeState',struct('CurrentSlot',1,'Probe',probe,'SameOwner',probe), ...
    'CompletedSlot',1,'RNG',rng,'ConfigHash',repmat('a',1,64));
path=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario, ...
    sixgr.runtime.SlotCheckpoint.sourceIdentity());
MatSaveLoadProbe.loadCount("reset");
beforeRNG=rng;
[~,lineage,lease]=sixgr.runtime.SlotCheckpoint.prepareResume(path,scenario,"");
assert(MatSaveLoadProbe.loadCount("get")==1, ...
    'Preflight must deserialize the shared native object exactly once.');
assert(isequaln(beforeRNG,rng),'Preflight must not consume the scientific RNG.');
different=scenario; different.seed=58;
reject(@()lease.take(path,different,""),'sixgr:checkpoint:ScenarioChanged');
reject(@()lease.take(path+"_different",scenario,""),'sixgr:checkpoint:ResumeLeasePath');
reject(@()lease.saveobj(),'sixgr:checkpoint:ResumeLeaseNotSerializable');
[restored,receipt]=lease.take(path,scenario,"");
assert(MatSaveLoadProbe.loadCount("get")==1, ...
    'PHY ownership handoff must not invoke loadobj a second time.');
assert(restored.RuntimeState.Probe==restored.RuntimeState.SameOwner && ...
    isequaln(restored.RuntimeState.Probe.Samples,probe.Samples) && isequaln(restored.RNG,payload.RNG));
assert(receipt.ResumePreparationTiming.HandoffNativeDeserializations==0 && ...
    lineage.ResumePreparationTiming.NativeDeserializations==1 && ~receipt.PrimaryStudyEligible);
reject(@()lease.take(path,scenario,""),'sixgr:checkpoint:ResumeLeaseConsumed');

% Hash checking must not be traded away for avoiding deserialization.
[~,~,lease]=sixgr.runtime.SlotCheckpoint.prepareResume(path,scenario,"");
loads=MatSaveLoadProbe.loadCount("get");
receiptPath=fullfile(fileparts(path),'checkpoint.json');
savedReceipt=fileread(receiptPath);
sixgr.util.writeTextFile(receiptPath,string(savedReceipt)+newline);
reject(@()lease.take(path,scenario,""),'sixgr:checkpoint:ResumeLeaseReceiptChanged');
sixgr.util.writeTextFile(receiptPath,savedReceipt);
backup=fullfile(fileparts(path),'state_fixture_backup.mat'); copyfile(path,backup);
fid=fopen(path,'a'); assert(fid>=0); fwrite(fid,uint8(17),'uint8'); fclose(fid);
reject(@()lease.take(path,scenario,""),'sixgr:checkpoint:StateIntegrity');
assert(MatSaveLoadProbe.loadCount("get")==loads, ...
    'Mutation rejection must happen without reconstructing the state.');
copyfile(backup,path,'f');
lease.release();
reject(@()lease.take(path,scenario,""),'sixgr:checkpoint:ResumeLeaseConsumed');
ok=true; disp('CHECKPOINT_RESUME_LEASE_PASS');
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
