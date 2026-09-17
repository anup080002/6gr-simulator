function ok=testTDDSharedPUCCHIndependentCombinedCompletion()
% Reuse actual shared DL/CSI/PUCCH execution; no isolated ACK or CSI donor.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_pucch_independent_harq_csi_sr_fixture.yaml');
folder=fullfile(root,'logs','tdd_shared_pucch_independent_combined');
if ~isfolder(folder), mkdir(folder); end
ok=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    tempname(folder),fixture,false,true,false,false,true);
end
