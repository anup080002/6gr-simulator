function ok=testSetupExcludesLogSnapshots()
% Archived source under logs must not compete with the current codebase.
repoRoot=fileparts(fileparts(mfilename('fullpath')));
logsRoot=fullfile(repoRoot,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
snapshot=tempname(logsRoot); mkdir(snapshot);
setup6GRSimToolkit('Verbose',false);
% Explicitly contaminate a cached setup call, as a prior session could do.
addpath(snapshot);
setup6GRSimToolkit('Verbose',false);
parts=string(strsplit(path,pathsep));
assert(~any(strcmpi(parts,logsRoot) | startsWith(lower(parts),lower(string(logsRoot)+filesep))), ...
    'sixgr:tests:ArchivedSourceOnPath','Generated log snapshots must stay off the MATLAB path.');
assert(strcmpi(which('testCSIPhysicalKnowledgeConsumer'), ...
    fullfile(repoRoot,'tests','testCSIPhysicalKnowledgeConsumer.m')));
assert(strcmpi(which('testLLSPUSCHHARQACKRuntimeFeedback'), ...
    fullfile(repoRoot,'tests','testLLSPUSCHHARQACKRuntimeFeedback.m')));
assert(strcmpi(which('sixgr.truth.CoupledTruthRuntime'), ...
    fullfile(repoRoot,'+sixgr','+truth','CoupledTruthRuntime.m')));
fprintf('SETUP_LOG_SNAPSHOT_EXCLUSION_PASS cached_path_pruned=1 current_test_and_runtime_paths=1\n');
ok=true;
end
