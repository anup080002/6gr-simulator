function ok=testSlotCheckpointExternalArchives(longPath)
% Exact filesystem/MAT-state restore fixture, not a PHY performance result.
assert(ispc,'This focused test exercises the approved Windows junction route.');
if nargin<1, longPath=false; end
root=fullfile(pwd,'logs','lls_repairs',['external_checkpoint_' char(java.util.UUID.randomUUID)]);
if longPath
    while strlength(root)<=280
        root=fullfile(root,'long_archive_route');
    end
    assert(strlength(root)>260,'Exercise the actual long Windows run-path boundary.');
end
mkdir(fullfile(root,'meta')); mkdir(fullfile(root,'channel','mat'));
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'), ...
    struct('Scope','checkpoint_storage_fixture_not_phy'));
externalBase=string(getenv('SIXGR_TEST_ARCHIVE_ROOT'));
if strlength(externalBase)==0
    externalBase=fullfile(fileparts(root),'external_archive_storage_tests');
end
external=fullfile(externalBase,string(java.util.UUID.randomUUID));
name="channel_observation_"+string(repmat('a',1,64))+".mat";
% A real MAT payload permits an independent load after relocation/restore.
priorRNG=rng; rngCleanup=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
rng(81,'twister'); fixtureBytes=uint8(randi([0 255],1200000,1));
archive=fullfile(root,'channel','mat',name);
sixgr.util.matSave(archive,struct('StorageFixtureBytes',fixtureBytes), ...
    'UseArtifactStore',false,'ForceV73',true);
hash=sixgr.util.sha256File(archive);
scenario=struct('run_control',struct('runtime_checkpoint_keep',2),'seed',81);
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
payload=struct('RuntimeState',struct('CurrentSlot',5),'CompletedSlot',5, ...
    'RNG',rng,'ConfigHash',repmat('a',1,64));
checkpoint=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,source);
script=fullfile(pwd,'scripts','move_lls_channel_archives.ps1');
[status,message]=system(sprintf(['pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass ' ...
    '-File "%s" -RunFolder "%s" -ArchiveFolder "%s"'],script,root,external));
assert(status==0,'Storage relocation failed: %s',message);
localAssertRoute(root,hash,name);
% A later file belongs to the preserved attempt, not the restored prefix.
laterName="effch_"+string(repmat('d',1,64))+".mat";
sixgr.util.matSave(fullfile(root,'channel','mat',laterName),struct('AfterCheckpoint',true), ...
    'UseArtifactStore',false);
[restored,lineage]=sixgr.runtime.SlotCheckpoint.prepareResume(checkpoint,scenario,"");
assert(strcmp(restored,root));
localAssertRoute(root,hash,name);
assert(~isfile(fullfile(root,'channel','mat',laterName)) && ...
    isfile(fullfile(lineage.PreservedFailedAttempt,'channel','mat',laterName)), ...
    'Restore must exclude post-checkpoint archives without deleting their preserved evidence.');
saved=sixgr.util.loadVerifiedMAT(archive,hash,"StorageFixtureBytes");
assert(isequal(saved.StorageFixtureBytes,fixtureBytes));
% Checkpointing and restoring the linked run again must retain the route.
payload.RuntimeState.CurrentSlot=10; payload.CompletedSlot=10;
checkpoint2=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,source);
sixgr.runtime.SlotCheckpoint.prepareResume(checkpoint2,scenario,"");
localAssertRoute(root,hash,name);
assert(sixgr.util.sha256File(fullfile(lineage.PreservedFailedAttempt, ...
    'channel','mat',name))==hash,'Immutable preserved archive bytes changed.');
ok=true; disp('SLOT_CHECKPOINT_EXTERNAL_ARCHIVES_PASS');
end

function localAssertRoute(root,hash,name)
record=jsondecode(fileread(fullfile(root,'meta','channel_archive_storage.json')));
assert(string(record.Contract)=="LLSExternalChannelArchive/v1" && ...
    string(record.Status)=="verified" && string(record.RunFolder)==string(root) && ...
    ~record.ScientificDataChanged && ~record.SourceCodeMoved);
logical=java.io.File(fullfile(root,'channel','mat')).toPath();
external=java.io.File(char(record.ExternalFolder)).toPath();
assert(java.nio.file.Files.isSameFile(logical,external), ...
    'Checkpoint restore silently replaced the external route with a local copy.');
assert(sixgr.util.sha256File(fullfile(root,'channel','mat',name))==hash);
end
