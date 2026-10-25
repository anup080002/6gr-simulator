function ok=testN40ContinuationArchiveRestore()
% Declared filesystem-only fixture; no checkpoint/PHY equivalence claim.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'logs','lls_repairs', ...
    "continuation_archive_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
source=fileread(which('sixgr.validation.verifyCheckpoint60Continuation'));
first=strfind(source,'function diagnostic=restoreBaseline(');
last=strfind(source,'function [path,receipt]=findCheckpoint(');
inventoryStart=strfind(source,'function T=inventoryFolder(');
assert(isscalar(first)&&isscalar(last)&&isscalar(inventoryStart));
body=replace(string(source(first:last-1)), ...
    'function diagnostic=restoreBaseline(','function diagnostic=n40ArchiveHarness(');
sixgr.util.writeTextFile(fullfile(folder,'n40ArchiveHarness.m'), ...
    body+newline+string(source(inventoryStart:end)));
addpath(folder); cleanup=onCleanup(@()rmpath(folder)); %#ok<NASGU>
root=string(sixgr.util.canonicalPath(fullfile(folder,'original')));
diagnostic=string(sixgr.util.canonicalPath(fullfile(folder,'diagnostic')));
mkdir(root); mkdir(diagnostic); mkdir(fullfile(root,'meta'));
base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
preserved=fullfile(base,'recovery_declared_filesystem_fixture'); mkdir(preserved);
sixgr.util.writeTextFile(fullfile(preserved,'original.txt'),"original bytes");
info=dir(fullfile(preserved,'original.txt'));
inventory=table("original.txt",double(info.bytes), ...
    string(sixgr.util.sha256File(fullfile(preserved,'original.txt'))), ...
    'VariableNames',{'RelativePath','Bytes','SHA256'});
checkpoint=string(fullfile(base,'declared_state_not_executed.mat'));
sixgr.util.jsonWrite(fullfile(root,'meta','checkpoint_resume.json'), ...
    struct('Checkpoint',checkpoint,'PreservedFailedAttempt',preserved));
sixgr.util.writeTextFile(fullfile(root,'diagnostic.txt'),"diagnostic bytes");
% A changed baseline cannot be restored as if it were the original.
bad=inventory; bad.SHA256="wrong";
try
    n40ArchiveHarness(root,diagnostic,bad,checkpoint);
    error('test:ExpectedFailure','Expected preserved-byte rejection.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:validation:ContinuationRestoreIntegrity'));
end
assert(isfile(fullfile(root,'diagnostic.txt'))&&isfolder(preserved));
archive=n40ArchiveHarness(root,diagnostic,inventory,checkpoint);
assert(isfile(fullfile(root,'original.txt'))&&~isfile(fullfile(root,'diagnostic.txt'))&& ...
    isfile(fullfile(archive,'diagnostic.txt'))&&~isfolder(preserved));
assert(string(sixgr.util.sha256File(fullfile(root,'original.txt')))==inventory.SHA256);
assert(n40ArchiveHarness(root,diagnostic,inventory,checkpoint)==archive, ...
    'Failure cleanup must be idempotent after restoration.');
ok=true;
fprintf('N40_CONTINUATION_ARCHIVE_PASS declared_filesystem_fixture_only=1 root=%s\n',folder);
end
