function ok=testISAC1083Stage1()
%TESTISAC1083STAGE1 Mandatory 10.8.3 physical gates and artifact contract.
root=string(tempname); mkdir(root); cleanup=onCleanup(@() localRemove(root)); %#ok<NASGU>
result=sixgr.isac.run1083Stage1( ...
    "configs/isac/joint_isac_tdoc_master.yaml", ...
    "OutputRoot",root,"RunId","focused_stage1");
assert(result.Passed && height(result.GateTable)==5 && all(result.GateTable.Pass));
assert(max(result.CPSafe.EVMRMS(result.CPSafe.IsIntegerDelay))<1e-8);
assert(any(result.PunctureState.DeltaQ(result.PunctureState.AfterFirstPuncture)~=0));
assert(result.PunctureReceiver.ReferenceCoherentGain(1)> ...
    result.PunctureReceiver.ReferenceCoherentGain(2));
for stem=["WFig17_linear_convolution_validation", ...
        "WFig18_absolute_vs_transmitted_counter","WFig19_cross_symbol_coherence"]
    for extension=[".mat",".fig",".png",".pdf"]
        assert(exist(fullfile(result.RunFolder,"figures",stem+extension),"file")==2);
    end
end
assert(exist(fullfile(result.RunFolder,"run_manifest.json"),"file")==2);
assert(exist(fullfile(result.RunFolder,"report","10_8_3_validation_report.md"),"file")==2);
fprintf("testISAC1083Stage1: PASS (%d gates)\n",height(result.GateTable));
ok=true;
end

function localRemove(path)
if exist(path,"dir")==7, rmdir(path,"s"); end
end
