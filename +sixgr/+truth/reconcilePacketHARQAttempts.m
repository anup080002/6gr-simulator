function state = reconcilePacketHARQAttempts(state)
% Count completed receiver attempts, not fragments, feedback or app delivery.
% This reducer consumes the runtime's validated HARQ timeline. A committed
% transmission still awaiting reception is not a completed receiver attempt.
% It never changes payload/queue/delivery bits or credits application bytes.
if ~isfield(state,'PacketDeliveryLedgerTable') || isempty(state.PacketDeliveryLedgerTable)
    return;
end
P=state.PacketDeliveryLedgerTable;
owner={'Direction','UEIndex','PacketId','ApplicationPacketId'};
requireColumns(P,owner);
keys=P(:,owner); keys.Direction=upper(string(keys.Direction));
assert(height(unique(keys,'rows'))==height(keys), ...
    'sixgr:protocol:AmbiguousApplicationIdentity','Application owner keys must be unique.');
P.HARQAttemptCount=nan(height(P),1);
P.HARQAttemptCountDefinition=repmat( ...
    "unique_receiver_completed_TB_attempts_not_feedback_or_fragment_count",height(P),1);
P.HARQAttemptCountStatus=repmat("missing_packet_segment_ledger",height(P),1);
if ~isfield(state,'PacketSDULedgerTable') || ~istable(state.PacketSDULedgerTable)
    state.PacketDeliveryLedgerTable=P;
    return;
end
S=state.PacketSDULedgerTable;
if isempty(S)
    P.HARQAttemptCount(:)=0;
    P.HARQAttemptCountStatus(:)="no_committed_packet_segments";
    state.PacketDeliveryLedgerTable=P;
    return;
end
requireColumns(S,[owner {'TransportBlockId','RNTI','HARQProcessId','NDIEpoch','ScheduleSlot'}]);
segmentOwner=zeros(height(S),1);
for k=1:height(S)
    match=upper(string(P.Direction))==upper(string(S.Direction(k))) & ...
        double(P.UEIndex)==double(S.UEIndex(k)) & ...
        string(P.PacketId)==string(S.PacketId(k)) & ...
        string(P.ApplicationPacketId)==string(S.ApplicationPacketId(k));
    assert(nnz(match)==1,'sixgr:protocol:UnownedPacketSegment', ...
        'Every segment must match exactly one direction/UE/application owner.');
    segmentOwner(k)=find(match);
end
S.HARQAttemptCount=nan(height(S),1);
S.HARQAttemptCountDefinition=repmat( ...
    "unique_receiver_completed_TB_attempts_not_feedback_or_fragment_count",height(S),1);
S.HARQAttemptCountStatus=repmat("missing_receiver_attempt_timeline",height(S),1);
P.HARQAttemptCountStatus(:)="missing_receiver_attempt_timeline";
if ~isfield(state,'HARQTimelineTable') || ~istable(state.HARQTimelineTable)
    state.PacketDeliveryLedgerTable=P; state.PacketSDULedgerTable=S;
    return;
end
H=state.HARQTimelineTable;
if ~isempty(H)
    requireColumns(H,{'Direction','UEIndex','RNTI','HarqID','NDIEpoch', ...
        'TBId','PHYGrantContextId','Slot'});
    for field=["TBId","PHYGrantContextId"]
        ids=string(H.(field));
        assert(all(~ismissing(ids) & strlength(strtrim(ids))>0), ...
            'sixgr:protocol:MissingPacketAttemptIdentity', ...
            'Receiver attempt identity must be retained; never infer it from a count.');
    end
    % Exact repeated observations are idempotent. Conflicting outcomes or
    % times under one immutable attempt identity must not be silently merged.
    attemptKeys=H(:,{'Direction','UEIndex','TBId','PHYGrantContextId'});
    attemptKeys.Direction=upper(string(attemptKeys.Direction));
    [~,first,group]=unique(attemptKeys,'rows','stable');
    for k=1:height(H)
        assert(isequaln(H(k,:),H(first(group(k)),:)), ...
            'sixgr:protocol:ConflictingPacketAttemptEvidence', ...
            'One receiver attempt has contradictory retained evidence.');
    end
    H=H(first,:);
end
% Store only actual associations; do not allocate all packets x all trials.
packetAttempts=cell(height(P),1);
for k=1:height(S)
    id=string(S.TransportBlockId(k));
    numbers=[S.UEIndex(k),S.RNTI(k),S.HARQProcessId(k),S.NDIEpoch(k),S.ScheduleSlot(k)];
    assert(isscalar(id) && ~ismissing(id) && strlength(strtrim(id))>0 && ...
        all(isfinite(numbers) & numbers==fix(numbers)) && ...
        all(numbers([1 2 5])>0) && all(numbers([3 4])>=0), ...
        'sixgr:protocol:MissingPacketAttemptIdentity', ...
        'Packet-to-TB binding must preserve UE, RNTI, process, epoch and schedule slot.');
    match=false(height(H),1);
    if ~isempty(H)
        match=upper(string(H.Direction))==upper(string(S.Direction(k))) & ...
            double(H.UEIndex)==double(S.UEIndex(k)) & string(H.TBId)==id;
        assert(all(double(H.RNTI(match))==double(S.RNTI(k)) & ...
            double(H.HarqID(match))==double(S.HARQProcessId(k)) & ...
            double(H.NDIEpoch(match))==double(S.NDIEpoch(k)) & ...
            isfinite(double(H.Slot(match))) & ...
            double(H.Slot(match))>=double(S.ScheduleSlot(k))), ...
            'sixgr:protocol:PacketAttemptOwnerMismatch', ...
            'A logical TB label must not alias another radio identity or epoch.');
        if ismember('SweepPointIndex',H.Properties.VariableNames) && any(match)
            points=unique(double(H.SweepPointIndex(match)));
            assert(isscalar(points),'sixgr:protocol:AmbiguousPacketAttemptSweep', ...
                'A logical TB cannot be reused across independent sweep points.');
        end
    end
    S.HARQAttemptCount(k)=nnz(match);
    S.HARQAttemptCountStatus(k)="receiver_attempt_timeline_reconciled";
    p=segmentOwner(k);
    packetAttempts{p}=[packetAttempts{p};find(match)];
end
P.HARQAttemptCount=cellfun(@(rows)numel(unique(rows)),packetAttempts);
P.HARQAttemptCountStatus(:)="receiver_attempt_timeline_reconciled";
state.PacketDeliveryLedgerTable=P;
state.PacketSDULedgerTable=S;
end

function requireColumns(T,names)
assert(istable(T) && all(ismember(names,T.Properties.VariableNames)), ...
    'sixgr:protocol:IncompletePacketAttemptSchema', ...
    'Packet/HARQ reconciliation requires explicit source identity columns.');
end
