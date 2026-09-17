function ok=testSharedUnselectedCombinedPUCCHProducer()
% Actual combined HARQ/CSI/SR PUCCH survives an unconsumed UL command.
% This is transport/receiver ownership, not a physical DCI miss-rate test.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios','lls_tdd_pucch_independent_harq_csi_sr_fixture.yaml');
folder=fullfile(root,'logs','unselected_combined_pucch_producer');
if ~isfolder(folder), mkdir(folder); end
ok=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    tempname(folder),fixture,false,true,false,true);
end
