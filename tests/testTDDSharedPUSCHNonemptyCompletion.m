function ok=testTDDSharedPUSCHNonemptyCompletion()
% Real shared DL receiver -> UE Type-2 book -> PUSCH -> common gNB commit.
% No isolated ACK donor, injected bit decision or full-run qualification.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_pusch_independent_shared_harq_fixture.yaml');
logsRoot=fullfile(root,'logs','tdd_shared_pusch_nonempty_completion');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputRoot=tempname(logsRoot);
fprintf('TDD_NONEMPTY_SHARED_HARQ_ARTIFACT_ROOT=%s\n',outputRoot);
ok=testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true,false,outputRoot,fixture,false,true);
end
