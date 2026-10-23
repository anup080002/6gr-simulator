function ok=testCheckpointFileStore()
% Storage mechanics only: identical versions share one object, mutation
% creates another, and corrupt immutable objects are never silently repaired.
root=tempname; mkdir(root); source=fullfile(root,'mutable.csv');
sixgr.util.writeTextFile(source,"Slot,Value"+newline+"46,1"+newline);
[a,ha,reused]=sixgr.runtime.CheckpointFileStore.capture(root,source);
assert(~reused);
[b,hb,reused]=sixgr.runtime.CheckpointFileStore.capture(root,source);
assert(reused && a==b && ha==hb);
sixgr.util.writeTextFile(source,"Slot,Value"+newline+"46,2"+newline);
[c,hc,reused]=sixgr.runtime.CheckpointFileStore.capture(root,source);
assert(~reused && c~=a && hc~=ha);
old=sixgr.runtime.CheckpointFileStore.resolve(root,a);
assert(contains(fileread(old),'46,1') && numel(dir(fullfile(root,'objects','*.bin')))==2);
reject(@()sixgr.runtime.CheckpointFileStore.resolve(root,"@objects/../escape"), ...
    'sixgr:checkpoint:SnapshotObjectPath');
sixgr.util.writeTextFile(old,'tampered');
sixgr.util.writeTextFile(source,"Slot,Value"+newline+"46,1"+newline);
reject(@()sixgr.runtime.CheckpointFileStore.capture(root,source), ...
    'sixgr:checkpoint:SnapshotObjectIntegrity');
ok=true; disp('CHECKPOINT_FILE_STORE_PASS');
end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier); return;
end
error('test:ExpectedFailure','Expected %s',id);
end
