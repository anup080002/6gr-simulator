function ok=testProfiledLLSExecution()
% Existing physical-chain tests with the diagnostic profiler actually ON.
% Their PHY assertions remain unchanged; no synthetic performance outputs.
parent=fullfile(pwd,'logs','lls_repairs');
if ~isfolder(parent), mkdir(parent); end
root=tempname(parent); mkdir(root);
scope=sixgr.runtime.ExecutionStageProfiler.start(root,true);
sixgr.runtime.ExecutionStageProfiler.setSlot(1,1);
assert(testSharedWaveformPhysicalRuntime());
assert(testLLS_DL());
assert(testLLS_UL());
clear scope
T=readtable(fullfile(root,'reports','csv','execution_stage_profile.csv'),'TextType','string');
for stage=["channel","RF","hashing","decoding"]
    assert(any(T.Stage==stage & T.ScopeExitCount>0),'Executed stage was not profiled: %s',stage);
end
for operation=["PDSCH_LDPC_code_blocks","PUSCH_LDPC_code_blocks"]
    assert(any(T.Operation==operation & T.InclusiveSeconds>0),'Missing actual decoder timing: %s',operation);
end
fprintf('PROFILED_PHYSICAL_LLS_PASS profile=%s\n',fullfile(root,'reports','csv','execution_stage_profile.csv'));
ok=true;
end
