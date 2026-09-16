function ok=testTDDSharedPUSCHIndependentCSICompletion()
% Same shared DL produces real HARQ and CSI, then ordinary received UL DCI
% selects PUSCH. No isolated ACK donor or injected CSI value.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_pusch_independent_harq_csi_fixture.yaml');
logsRoot=fullfile(root,'logs','tdd_shared_pusch_independent_csi');
if ~isfolder(logsRoot), mkdir(logsRoot); end
for forgetProducer=[false true]
    outputRoot=tempname(logsRoot);
    fprintf('TDD_INDEPENDENT_SHARED_CSI_ARTIFACT_ROOT=%s forget_producer=%d\n',outputRoot,forgetProducer);
    [ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
        outputRoot,fixture,false,true,forgetProducer);
    if ~forgetProducer
        original=state.LatestDLFeedback;
    else
        assert(isequaln(original,state.LatestDLFeedback), ...
            'UE bookkeeping removal and poisoned TX CSI references cannot change received scheduler CSI.');
    end
end
end
