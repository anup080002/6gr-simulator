function ok=testTDDSharedResearchPUSCHCSICompletion()
% Actual shared SRS/SSB/PDCCH/PDSCH/PUSCH, independent HARQ/CSI completion.
% This bounded 5 MHz case does not qualify full 400 MHz coordinator execution.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_four_port_research_pusch_csi_fixture.yaml');
resultsRoot=fullfile(root,'results','lls','shared_research_pusch_csi');
if ~isfolder(resultsRoot), mkdir(resultsRoot); end
for forgetProducer=[false true]
    outputRoot=tempname(resultsRoot);
    fprintf('SHARED_RESEARCH_PUSCH_CSI_ROOT=%s forget_producer=%d\n',outputRoot,forgetProducer);
    [ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
        outputRoot,fixture,false,true,forgetProducer,false,false,4);
    rows=sixgr.util.csvReadTable(fullfile(outputRoot,'received_pusch.csv'),'TextType','string', ...
        'ColumnTypes',struct('Modulation','string', ...
        'ExperimentalPUSCHTransport','double','CRCPass','double'));
    assert(height(rows)==1 && all(string(rows.Modulation)=="1024QAM") && ...
        all(rows.ExperimentalPUSCHTransport) && all(rows.CRCPass==1));
    assert(state.TestSRS.NumSRSPorts==4 && state.TestSRS.RI>=1 && state.TestSRS.RI<=4);
    if ~forgetProducer
        original=state.LatestDLFeedback;
    else
        assert(isequaln(original,state.LatestDLFeedback), ...
            'Experimental transport must not recover CSI from poisoned producer bookkeeping.');
    end
    clear state
end
fprintf('SHARED_RESEARCH_PUSCH_CSI_COMPLETION_PASS\n');
end
