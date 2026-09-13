function [rows,mapping]=prepareScheduledHARQFeedback(state,cfg,ue,targetSlot,observed)
% Read-only preflight of independently mapped DL HARQ feedback.
% The receive owner must separately validate actual UCI IQ, clock, assignment,
% transport, duplicate-occasion guard and normalized decode evidence.
% No entity, decoder buffer, scheduler, feedback ledger or primary row mutates.
mapping=sixgr.truth.buildScheduledHARQACKMapping(state,cfg,ue,targetSlot);
rows=sixgr.truth.mapScheduledHARQFeedback(mapping,observed);
harq=state.DLHarq;
assert(isa(harq,'sixgr.l2.mac.HARQEntity') && isscalar(harq) && ...
    strcmpi(harq.Direction,'DL'),'sixgr:truth:MissingScheduledFeedbackHARQ', ...
    'Retain the actual DL HARQ entity for these scheduling obligations.');
attempts=[[rows.RNTI].',[rows.HARQProcess].',[rows.SourceSlot].'];
assert(size(unique(attempts,'rows'),1)==numel(rows), ...
    'sixgr:truth:DuplicateScheduledFeedbackAttempt', ...
    'One physical process attempt cannot consume two independent feedback bits.');
ledger=state.SharedDataTXLedger;
for k=1:numel(rows)
    row=rows(k);
    hit=find(cellfun(@(record)string(record.Identity.TransmissionID)==string(row.TransmissionID),ledger));
    assert(isscalar(hit),'sixgr:truth:MissingScheduledFeedbackGrant', ...
        'Each scheduled bit needs exactly one physically committed DL grant.');
    grant=ledger{hit}.Grant;
    actualBits=ledger{hit}.TransportBlockBits;
    assert(isnumeric(actualBits) && isvector(actualBits) && ~isempty(actualBits) && ...
        all(actualBits(:)==0 | actualBits(:)==1) && ...
        isscalar(grant.TBSBits) && grant.TBSBits==numel(actualBits) && ...
        mod(grant.TBSBits,8)==0, ...
        'sixgr:truth:ScheduledFeedbackTBSMismatch', ...
        'Feedback TBS must be the retained actual transport-block size.');
    ui=find(harq.UEList==row.RNTI); pid=row.HARQProcess+1;
    assert(isscalar(ui) && pid>=1 && pid<=numel(harq.UEProcs{ui}), ...
        'sixgr:truth:MissingScheduledFeedbackHARQ', ...
        'Validate every scheduled process before any feedback is applied.');
    process=harq.UEProcs{ui}(pid);
    assert(~process.AwaitingFeedback || process.LastTxSlot~=row.SourceSlot || ...
        process.NDI==row.NDI,'sixgr:truth:InconsistentScheduledHARQNDI', ...
        'A same-slot pending process cannot change its scheduled NDI.');
    stale=~process.AwaitingFeedback || process.LastTxSlot~=row.SourceSlot || process.NDI~=row.NDI;
    rows(k).HarqID=row.HARQProcess;
    rows(k).ServingCell=double(grant.ServingCell);
    rows(k).TBSBits=double(grant.TBSBits);
    rows(k).RV=double(grant.HARQ.RV);
    rows(k).Direction="DL";
    rows(k).FeedbackForDirection="DL";
    rows(k).DueSlot=targetSlot;
    rows(k).IsRetransmission=logical(grant.HARQ.IsRetransmission);
    rows(k).StaleFeedbackIgnored=logical(stale);
    rows(k).FeedbackDispositionPrevalidated=true;
    rows(k).HARQFeedbackApplied=false; % Preflight has made no state change.
    rows(k).StateChangeApplied=false;
end
end
