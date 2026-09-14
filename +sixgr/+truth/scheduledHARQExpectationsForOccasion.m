function selected=scheduledHARQExpectationsForOccasion(state,ue,targetSlot)
% A complete gNB schedule snapshot, including a verifiable empty occasion.
% Absence here is not evidence of a received waveform, DTX or successful UCI.
% Never use UE events/pending ACK rows to decide whether DL was transmitted.
validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(targetSlot,{'numeric'},{'scalar','real','finite','integer','positive'});
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
assert(isa(owner,'sixgr.truth.CoupledWaveformStream') && isscalar(owner), ...
    'sixgr:truth:HARQMappingPhysicalOwnerRequired','Use the actual shared physical owner.');
assert(ue<=state.NumUsers,'sixgr:truth:HARQMappingUEIdentityMismatch', ...
    'An unconfigured UE is not an empty scheduled feedback occasion.');
physical=owner.DataTransmissions;
ledger=sixgr.util.structGet(state,'SharedDataTXLedger',{});
expectations=sixgr.util.structGet(state,'SharedDLHARQExpectations',{});
assert(iscell(ledger) && iscell(expectations), ...
    'sixgr:truth:HARQMappingScheduleMismatch','Retain the physical TX and feedback ledgers.');
% Check every physical DL attempt for this UE, not just surviving expectation
% rows. Otherwise deleting a ledger entry could masquerade as zero HARQ.
actualIDs=strings(0,1); expectedIDs=strings(0,1); selected=cell(0,1);
for tx=reshape(physical,1,[])
    if tx.Identity.Direction~="DL" || tx.Identity.UEIndex~=ue, continue; end
    id=string(tx.Identity.TransmissionID);
    hit=find(cellfun(@(r)string(r.Identity.TransmissionID)==id,ledger));
    assert(isscalar(hit),'sixgr:truth:HARQMappingUnexecutedSchedule', ...
        'Every actual DL transmission needs one retained grant, even on an empty feedback occasion.');
    retained=ledger{hit};
    assert(isequaln(retained.Identity,tx.Identity) && ...
        retained.CommittedAtSample==tx.CommittedAtSample && ...
        tx.CommittedAtSample<=owner.Events.NextSampleIndex, ...
        'sixgr:truth:HARQMappingScheduleMismatch','Retained and physical transmission identities differ.');
    actualIDs(end+1,1)=id; %#ok<AGROW>
    e=sixgr.truth.scheduledDLHARQExpectation(retained.Grant,tx.Identity,tx.CommittedAtSample);
    matched=find(cellfun(@(r)string(r.TransmissionID)==id,expectations));
    if isempty(e)
        assert(isempty(matched),'sixgr:truth:HARQMappingScheduleMismatch', ...
            'A grant without HARQ feedback cannot acquire an expectation.');
        continue;
    end
    assert(isscalar(matched),'sixgr:truth:IncompleteScheduledHARQExpectations', ...
        'An actual HARQ-requiring DL transmission needs exactly one expectation.');
    assert(isequaln(expectations{matched},e),'sixgr:truth:HARQMappingScheduleMismatch', ...
        'The expectation must equal the one derived from the actual transmitted grant.');
    expectedIDs(end+1,1)=id; %#ok<AGROW>
    if e.FeedbackAbsoluteSlot0+1==targetSlot
        selected{end+1,1}=e; %#ok<AGROW>
    end
end
assert(numel(unique(actualIDs))==numel(actualIDs), ...
    'sixgr:truth:DuplicateScheduledHARQMapping','Actual DL transmission identities must be unique.');
for k=1:numel(ledger)
    r=ledger{k};
    if r.Identity.Direction=="DL" && r.Identity.UEIndex==ue
        assert(any(actualIDs==string(r.Identity.TransmissionID)), ...
            'sixgr:truth:HARQMappingUnexecutedSchedule','A retained DL grant needs its physical transmission.');
    end
end
for k=1:numel(expectations)
    e=expectations{k};
    if e.UEIndex==ue
        assert(any(expectedIDs==string(e.TransmissionID)), ...
            'sixgr:truth:HARQMappingUnexecutedSchedule','An expectation needs an actual HARQ-requiring DL attempt.');
    end
end
end
