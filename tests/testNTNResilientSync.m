function ok=testNTNResilientSync()
%TESTNTNRESILIENTSYNC Run focused resilient synchronization invariants.
setup6GRSimToolkit('Verbose',false);
root=fileparts(mfilename('fullpath'));
suite=testsuite(fullfile(root,'ntn_resilient_sync'),'IncludeSubfolders',true);
results=run(suite);
assert(~isempty(results),'No resilient synchronization tests were discovered.');
assert(all([results.Passed]),'%d resilient synchronization test(s) failed.',sum(~[results.Passed]));
ok=true;
end
