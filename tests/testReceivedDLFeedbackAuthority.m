function ok=testReceivedDLFeedbackAuthority(outputRoot)
% Isolated coded ACK/NACK donors, not a shared-channel or main-run claim.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve previous captures.');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
slots=[3 6]; variances=[1e-13 1e-4];
rows=table(); captures=cell(2,1);
for k=1:2
    [out,timing,a]=receivedDLFeedbackFixture(cfg,slots(k),k-1,variances(k));
    assert(a.Source=="received_dci_bits_plus_installed_connected_context" && ...
        a.DataAbsoluteSlot==slots(k)-1 && a.HARQProcess==k-1);
    assert(logical(out.TrialTable.CRCPass)==(k==1));
    assert(isa(out.ReceivedHARQState,'sixgr.link.ReceivedDLHARQState') && ...
        out.ReceivedHARQDecision.DecodeAttempted && ...
        out.ReceivedHARQDecision.ACK==(k==1) && ...
        out.ReceivedHARQState.Processes{k}.LastAssignmentDigest==a.AssignmentDigest);
    assert(out.HARQ.ReceivedAssignmentDigest==a.AssignmentDigest && ...
        out.HARQ.DecoderCRCInputDomain=="harq_combined_mother_code");
    g=out.HARQ.GrantSnapshot;
    assert(g.Slot==slots(k) && g.Frame==1 && g.ScheduledAbsoluteSlot==slots(k)-1);
    assert(timing.DataDecodeAvailableAtSample>0);
    captures{k}=struct('Assignment',a,'Timing',timing,'TrialTable',out.TrialTable);
    rows=[rows;table(slots(k),a.ControlAbsoluteSlot,a.DataAbsoluteSlot, ...
        a.HARQProcess,string(a.AssignmentDigest),logical(out.TrialTable.CRCPass), ...
        timing.DataDecodeAvailableAtSample, ...
        'VariableNames',{'Slot1','ControlSlot0','DataSlot0','HARQProcess', ...
        'ReceivedAssignmentSHA256','CRCPass','DecodeAvailableAtSample'})]; %#ok<AGROW>
end
mkdir(outputRoot);
save(fullfile(outputRoot,'received_control_capsules.mat'),'captures','-v7');
sixgr.util.csvWriteTable(fullfile(outputRoot,'received_control_capsules.csv'),rows,'PreserveSchema',true);
fprintf('RECEIVED_DL_FEEDBACK_AUTHORITY_PASS actual_ACK_NACK=1,0 slots=3,6 folder=%s\n',outputRoot);
ok=true;
end
