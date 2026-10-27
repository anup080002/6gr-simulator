function ok=testSelectedPUSCHRetainedSSBRecovery(outputRoot)
% Actual shared recovery; original measured CSI age is retained, not reset.
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<1
    parent=fullfile(root,'logs','selected_pusch_recovery');
    if ~isfolder(parent),mkdir(parent);end
    outputRoot=fullfile(parent,char(java.util.UUID.randomUUID()));
end
fixture=fullfile(root,'simulator','configs','validation','lls_selected_pusch_retained_ssb_recovery.yaml');
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    outputRoot,fixture,false,true,false,false,true,2,false,false,false,false,false,false,true,false,true);
assert(ok && state.TestSelectedPUSCHRecoveryReceipt.RecoverySlot==15);
end
