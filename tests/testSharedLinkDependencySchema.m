function ok=testSharedLinkDependencySchema()
% Missing historical metadata is not missing physical state or permission
% to fabricate installation evidence. Exercise the exact append migration.
setup6GRSimToolkit('Verbose',false);
old=struct('ID',{'old_a','old_b'},'State',{struct('Sample',17),struct('Sample',39)});
actual=sixgr.truth.normalizeSharedLinkDependencyMetadata(old);
assert(isequaln(rmfield(actual,'SignalDependency'),old));
assert(all(arrayfun(@(v)isempty(fieldnames(v.SignalDependency)),actual)));
fresh=struct('ID','fresh','State',struct('Sample',0), ...
    'SignalDependency',struct('Available',true,'Source','original_installation'));
actual(end+1)=fresh;
assert(isequaln(actual(3),fresh));
assert(isequaln(sixgr.truth.normalizeSharedLinkDependencyMetadata(actual),actual));
for shape={[0 0],[0 1],[1 0],[0 2]}
    emptyOld=repmat(old(1),shape{1});
    migrated=sixgr.truth.normalizeSharedLinkDependencyMetadata(emptyOld);
    assert(isequal(size(migrated),size(emptyOld))&&isfield(migrated,'SignalDependency'));
    assert(isequaln(rmfield(migrated,'SignalDependency'),emptyOld));
end
emptyOld=repmat(old(1),0,1);
migrated=sixgr.truth.normalizeSharedLinkDependencyMetadata(emptyOld);
migrated(end+1)=fresh;
assert(isequaln(migrated,fresh));
fprintf('SHARED_LINK_DEPENDENCY_SCHEMA_PASS original_state_preserved=1 history_fabricated=0\n');
ok=true;
end
