function ok=testSlotCheckpointSchema1Compatibility()
% Explicit legacy storage fixture, not a claim about any historical PHY run.
root=tempname; mkdir(root);
base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
folder=fullfile(base,'after_slot_000001_legacy_fixture');
mkdir(fullfile(folder,'small_files'));
scenario=struct('run_control',struct('runtime_checkpoint_keep',3),'seed',17);
payload=struct('RuntimeState',struct('CurrentSlot',1,'ExactFixture',complex(1:20,20:-1:1)), ...
    'CompletedSlot',1,'RNG',rng,'ConfigHash',"schema1_fixture", ...
    'Scenario',scenario,'FullScenario',scenario);
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
path=fullfile(folder,'state.mat');
sixgr.util.matSave(path,struct('payload',payload),'UseArtifactStore',false,'ForceV73',true);
dep=fullfile(root,'measurement.csv');
sixgr.util.writeTextFile(dep,"Slot,Value"+newline+"1,7"+newline);
snapshot=fullfile('small_files','00000001.bin');
copyfile(dep,fullfile(folder,snapshot));
info=dir(dep);
receipt=struct('SchemaVersion',1,'Status','complete','Generation',1, ...
    'RunFolder',root,'CompletedSlotOneBased',1,'NextSlotOneBased',2, ...
    'MATLABVersion',version,'StateSHA256',sixgr.util.sha256File(path),'Source',source, ...
    'Files',struct('Path','measurement.csv','Bytes',info.bytes, ...
    'SHA256',sixgr.util.sha256File(dep),'Snapshot',snapshot));
sixgr.util.jsonWrite(fullfile(folder,'checkpoint.json'),receipt);
sixgr.util.writeTextFile(dep,'Later attempt must be preserved');
requested=scenario;
requested.run_control.checkpoint_first_slot=49;
requested.run_control.checkpoint_every_slots=3;
[restored,~]=sixgr.runtime.SlotCheckpoint.read(path,requested,"");
assert(isequaln(restored.RuntimeState,payload.RuntimeState) && isequaln(restored.RNG,payload.RNG));
[~,lineage]=sixgr.runtime.SlotCheckpoint.prepareResume(path,requested,"");
assert(contains(fileread(dep),'1,7') && ...
    contains(fileread(fullfile(lineage.PreservedFailedAttempt,'measurement.csv')),'Later attempt'));
assert(lineage.RequestedOperationalSettings.run_control.checkpoint_first_slot==49);
disp('SLOT_CHECKPOINT_SCHEMA1_COMPATIBILITY_PASS'); ok=true;
end
