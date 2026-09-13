function ok=testSharedDLHARQExpectation(outputRoot)
% Real shared TX/owner/commit, no control reception or UCI decoding claimed.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot); rows={};
for mode=["TDD","FDD"]
    [passed,state]=testSharedDataPhysicalQueue(mode);
    assert(passed && numel(state.SharedDLHARQExpectations)==2);
    expectations=state.SharedDLHARQExpectations; ledger=state.SharedDataTXLedger;
    save(fullfile(outputRoot,"expectations_"+mode+".mat"),'expectations','ledger');
    for k=1:numel(ledger)
        tx=ledger{k}; e=expectations{k};
        assert(e.TransmissionID==tx.Identity.TransmissionID && ...
            e.TXCommittedAtSample==tx.CommittedAtSample && ...
            e.HARQProcess==tx.Grant.HARQ.HarqID && ...
            e.FeedbackAbsoluteSlot0==tx.Grant.TimingDecision.FeedbackAbsoluteSlot);
        assert(~isfield(tx.Grant,'ControlDecodeOk') && ~isfield(tx.Grant,'PDCCHGrantBindingOk'), ...
            'The retained TX contract must not claim UE control reception.');
        changed=tx.Grant; changed.ControlDecodeOk=true; changed.PDCCHGrantBindingOk=true;
        changed.CRCPass=true; changed.DecodedBits=int8([1;0]);
        same=sixgr.truth.scheduledDLHARQExpectation(changed,tx.Identity,tx.CommittedAtSample);
        assert(isequaln(e,same),'Receiver/scoring fields must not alter the gNB scheduled expectation.');
        assert(~any(isfield(e,{'Ack','ExpectedAck','DecodeOk','DecodedBits','CRCPass','UCIBitCount'})));
        changed=tx.Grant; changed.HARQFeedbackAbsoluteSlot=changed.HARQFeedbackAbsoluteSlot+1;
        localReject(@()sixgr.truth.scheduledDLHARQExpectation(changed,tx.Identity,tx.CommittedAtSample), ...
            'sixgr:phy:grant:TimingIdentityMismatch');
        changed=tx.Identity; changed.RNTI=changed.RNTI+1;
        localReject(@()sixgr.truth.scheduledDLHARQExpectation(tx.Grant,changed,tx.CommittedAtSample), ...
            'sixgr:truth:DLFeedbackExpectationIdentity');
        localReject(@()sixgr.truth.scheduledDLHARQExpectation(tx.Grant,tx.Identity,tx.Identity.StartSample), ...
            'sixgr:truth:DLFeedbackExpectationBeforeTX');
        rows{end+1}=struct('Duplex',mode,'TransmissionID',e.TransmissionID, ...
            'DataAbsoluteSlot0',e.DataAbsoluteSlot0,'FeedbackAbsoluteSlot0',e.FeedbackAbsoluteSlot0, ...
            'HARQProcess',e.HARQProcess,'ScheduledPRI',e.ScheduledPRI, ...
            'TXCommittedAtSample',e.TXCommittedAtSample,'Source',e.Source, ...
            'Status',e.Status,'UEControlReceptionClaimed',false,'UCIObservationClaimed',false); %#ok<AGROW>
    end
end
results=struct2table(vertcat(rows{:}));
writetable(results,fullfile(outputRoot,'gnb_scheduled_expectations.csv')); disp(results);
ok=true; disp('SHARED_DL_HARQ_EXPECTATION_PASS');
end
function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
