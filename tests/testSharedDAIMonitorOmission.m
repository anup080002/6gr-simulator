function ok=testSharedDAIMonitorOmission(outputRoot)
% Actual shared HARQ/CSI + declared omission of one UE control admission.
% Original omitted control is physically transmitted/captured/decoded for
% diagnostics, but NOT admitted to the UE assignment owner. No RF miss claim.
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<1
    parent=fullfile(root,'logs','shared_dai_monitor_omission');
    if ~isfolder(parent),mkdir(parent);end
    outputRoot=fullfile(parent,char(java.util.UUID.randomUUID()));
end
fixture=fullfile(root,'simulator','configs','validation','lls_shared_dai_monitor_omission.yaml');
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    outputRoot,fixture,false,true,false,false,false,2,false,false,false,false,false,false,false,true);
assert(ok && state.TestDAIMonitorOmission && state.TestOmittedDataCaptured);
assert(state.TestOmittedControl.OriginalDecoderResult.Ok, ...
    'The omission boundary must not be represented as an RF decoder failure.');
assert(numel(state.SharedUEHARQACKEvents)==1 && height(state.SharedGNBUCIHARQTable)==2);
assert(numel(state.SharedPUSCHHARQFeedbackReceipts)==1);
assert(state.TestCSISource.CSIRSTrialTable.Slot==6 && height(state.SharedGNBCSIReportTable)==1);
fprintf('SHARED_DAI_MONITOR_OMISSION_PASS scheduled_DL=2 UE_received_events=1 RF_miss_claimed=0\n');
end
