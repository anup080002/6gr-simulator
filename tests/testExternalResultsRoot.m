function ok = testExternalResultsRoot()
% Explicit external evidence root must reach the real run-folder writer.
setup6GRSimToolkit('Verbose',false);
repoRoot=fileparts(fileparts(mfilename('fullpath')));
priorResults=getenv('SIXGR_RESULTS_ROOT');
priorScratch=getenv('SIXGR_REGRESSION_SCRATCH_ROOT');
ownedRoot=char(java.io.File([tempname '_sixgr_output']).getCanonicalPath());
assert(~isfolder(ownedRoot));
cleanup=onCleanup(@() localRestore(priorResults,priorScratch,ownedRoot)); %#ok<NASGU>
setenv('SIXGR_REGRESSION_SCRATCH_ROOT','');
setenv('SIXGR_RESULTS_ROOT',ownedRoot);
assert(strcmpi(sixgr.report.resolveResultsRoot(ownedRoot),ownedRoot), ...
    'Explicit production output root was silently redirected.');
child=fullfile(ownedRoot,'lls','external_probe');
assert(strcmpi(sixgr.report.resolveResultsRoot(child),child));
assert(strcmpi(sixgr.report.resolveResultsRoot(fullfile(ownedRoot,'nested','..')),ownedRoot));
for outside={ [ownedRoot '_sibling'], fullfile(ownedRoot,'..','outside_probe') }
    assert(strcmpi(sixgr.report.resolveResultsRoot(outside{1}),fullfile(repoRoot,'results')), ...
        'External-root opt-in must not admit siblings or dot-segment escapes.');
end
assert(strcmpi(sixgr.report.resolveResultsRoot('results'),fullfile(repoRoot,'results')), ...
    'Opt-in must not silently relocate legacy relative results.');
assert(strcmpi(sixgr.report.resolveResultsRoot(fullfile(repoRoot,'logs')),fullfile(repoRoot,'logs')));
actual=sixgr.report.defaultRunFolder(ownedRoot,'Bucket','lls','Profile', ...
    'external_probe','Leaf','routing_check','CleanExisting',false);
assert(strcmpi(actual,fullfile(child,'routing_check')) && isfolder(actual));
sixgr.util.jsonWrite(fullfile(actual,'routing_probe.json'),struct('ExternalRoot',ownedRoot));
assert(isfile(fullfile(child,'routing_check','routing_probe.json')));
% Ambiguous/broad allowlists cannot authorize run-leaf cleanup.
volumeRoot=char(java.io.File(ownedRoot).toPath().getRoot().toString());
for invalid={ 'relative_results', repoRoot, fileparts(repoRoot), volumeRoot }
    setenv('SIXGR_RESULTS_ROOT',invalid{1});
    try
        sixgr.report.resolveResultsRoot(ownedRoot);
        error('sixgr:test:MissingRootGuard','Invalid external root was accepted.');
    catch err
        assert(strcmp(err.identifier,'sixgr:report:InvalidExternalResultsRoot'), ...
            'Wrong error for invalid output root: %s',err.identifier);
    end
end
setenv('SIXGR_RESULTS_ROOT','');
assert(strcmpi(sixgr.report.resolveResultsRoot(ownedRoot),fullfile(repoRoot,'results')));
ok=true;
end
function localRestore(priorResults,priorScratch,ownedRoot)
setenv('SIXGR_RESULTS_ROOT',priorResults);
setenv('SIXGR_REGRESSION_SCRATCH_ROOT',priorScratch);
% Only remove the unique test-owned child of the system temp directory.
tempRoot=char(java.io.File(tempdir).getCanonicalPath());
assert(startsWith(lower(ownedRoot),lower([tempRoot filesep])));
if isfolder(ownedRoot), rmdir(ownedRoot,'s'); end
end
