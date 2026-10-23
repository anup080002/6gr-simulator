function ok=testSlotCheckpointPolicy()
% Storage/identity negative fixtures only; no physical qualification claim.
root=fullfile(pwd,'logs','lls_repairs',['checkpoint_policy_' char(java.util.UUID.randomUUID)]);
mkdir(root);
scenario=struct('run_control',struct('runtime_checkpoint_keep',2),'seed',19);
scenario.config_inheritance=struct('parents',{{'original.yaml'}}, ...
    'merge_policy','deep_merge_last_writer_wins','locked_fields',{{}}, ...
    'provenance',struct('source_files',{{'original.yaml'}}, ...
    'config_path','original.yaml','resolved_at_loader',true));
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
sourceFile=fullfile(root,'wide_trials.csv');
original=repmat("1,2,3"+newline,200000,1);
sixgr.util.writeTextFile(sourceFile,join(original,""));
originalHash=sixgr.util.sha256File(sourceFile);
% Published live snapshots are immutable dependencies, unlike primary CSVs.
% A repeated checkpoint must retain their checksum without copying the same
% sample-volume CSV into every small_files directory.
snapshotRel=fullfile('reports','live_measurements',repmat('b',1,64), ...
    'sources','air_interface','csv','paired_samples.csv');
snapshotFile=fullfile(root,snapshotRel);
mkdir(fileparts(snapshotFile));
copyfile(sourceFile,snapshotFile);
snapshotHash=sixgr.util.sha256File(snapshotFile);
paths=strings(1,3);
sharedVersion="";
for k=1:3
    payload=struct('RuntimeState',struct('CurrentSlot',5*k), ...
        'CompletedSlot',5*k,'RNG',rng,'ConfigHash',repmat('a',1,64));
    paths(k)=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,source);
    record=jsondecode(fileread(fullfile(fileparts(paths(k)),'checkpoint.json')));
    immutable=record.Files(string({record.Files.Path})==string(snapshotRel));
    mutable=record.Files(string({record.Files.Path})=="wide_trials.csv");
    assert(isscalar(immutable) && strlength(string(immutable.Snapshot))==0 && ...
        string(immutable.SHA256)==snapshotHash, ...
        'Immutable live samples must retain exact checksums without repeated full copies.');
    assert(isscalar(mutable) && strlength(string(mutable.Snapshot))>0, ...
        'Mutable primary CSVs still require recoverable snapshots.');
    assert(record.SchemaVersion==2 && startsWith(string(mutable.Snapshot),"@objects/"));
    if k==1, sharedVersion=string(mutable.Snapshot); end
    assert(string(mutable.Snapshot)==sharedVersion, ...
        'Unchanged large captures/tables must reuse an immutable version across checkpoints.');
end
assert(~isfile(paths(1)) && isfile(paths(2)) && isfile(paths(3)) && isfile(sourceFile), ...
    'Rolling retention must remove only old generated checkpoint snapshots.');
restart=scenario;
restart.config_inheritance.parents={'original.yaml','restart.yaml'};
restart.config_inheritance.provenance.source_files={'original.yaml','restart.yaml'};
restart.config_inheritance.provenance.config_path='restart.yaml';
[~,restartReceipt]=sixgr.runtime.SlotCheckpoint.read(paths(3),restart,"");
assert(isequaln(restartReceipt.RequestedConfigInheritance,restart.config_inheritance));
% A different YAML location is not permission to alter physics or seeds.
changed=restart; changed.seed=20;
try
    sixgr.runtime.SlotCheckpoint.read(paths(3),changed,"");
    error('test:ScientificGuardMissing','Changed seed was accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:checkpoint:ScenarioChanged'));
end
legacy=scenario; % persisted v1 payloads include these generated fields
assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(legacy), ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(restart)));
sixgr.util.writeTextFile(sourceFile,'changed after checkpoint');
[~,lineage]=sixgr.runtime.SlotCheckpoint.prepareResume(paths(3),scenario,"");
assert(sixgr.util.sha256File(snapshotFile)==snapshotHash && ...
    sixgr.util.sha256File(fullfile(lineage.PreservedFailedAttempt,snapshotRel))==snapshotHash, ...
    'Preserved and restored live samples must retain the exact checkpoint bytes.');
assert(sixgr.util.sha256File(sourceFile)==originalHash && ...
    strcmp(fileread(fullfile(lineage.PreservedFailedAttempt,'wide_trials.csv')), ...
    'changed after checkpoint'),'Large mutable CSV must restore exactly, preserving failed output.');
receiptPath=fullfile(fileparts(paths(3)),'checkpoint.json');
receipt=jsondecode(fileread(receiptPath));
receipt.Source.SHA256=repmat('0',1,64); % explicitly mismatched identity fixture
sixgr.util.jsonWrite(receiptPath,receipt);
try
    sixgr.runtime.SlotCheckpoint.read(paths(3),scenario,"");
    error('test:SourceGuardMissing','Changed source was accepted without a repair declaration.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:checkpoint:SourceChanged'));
end
[~,repaired]=sixgr.runtime.SlotCheckpoint.read(paths(3),scenario,'explicit identity-guard unit fixture');
assert(repaired.SourceChanged && ~repaired.PrimaryStudyEligible);
ok=true; disp('SLOT_CHECKPOINT_POLICY_PASS');
end
