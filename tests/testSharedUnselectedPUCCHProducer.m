function ok=testSharedUnselectedPUCCHProducer()
% Actual shared DL reception/PUCCH transmission, with an explicitly
% unexecuted UE UL-control decoder. No invented missing-DCI/CRC outcome.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios','lls_tdd_pusch_independent_shared_harq_fixture.yaml');
folder=fullfile(root,'logs','unselected_pucch_producer');
if ~isfolder(folder), mkdir(folder); end
ok=testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true,false, ...
    tempname(folder),fixture,false,true,false,true);
end
