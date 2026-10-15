function P = bindRuntimeHARQTerminalEvidence(P, L)
% Join actual TX lifecycle, never substitute feedback bits for receiver CRC.
% Missing identity remains unavailable; duplicate exact identities fail closed.
n=height(P);
P.TransmitterLifecycleBound=false(n,1);
P.TransmitterTerminal=false(n,1);
P.TransmitterTerminalReason=strings(n,1);
P.TerminalAtSlot=nan(n,1);
P.LifecycleAttemptCount=nan(n,1);
P.HARQPacketReceiverPopulationComplete=false(n,1);
if ~(istable(L) && ~isempty(L)), return; end
required=["Direction","RNTI","HARQProcessId","TBId","SweepPointIndex", ...
    "AttemptSlot","PHYGrantContextId","TransmitterTerminal", ...
    "TransmitterTerminalReason","TerminalAtSlot","Source"];
assert(all(ismember(required,string(L.Properties.VariableNames))), ...
    'sixgr:truth:IncompleteHARQTerminalEvidence','Lifecycle identity and terminal fields are required.');
assert(all(string(L.Source)=="transmitter_HARQ_state_not_receiver_CRC"), ...
    'sixgr:truth:HARQTerminalSourceMismatch','Only actual transmitter lifecycle evidence may terminate a packet.');
matched=zeros(n,1);
for i=1:n
    p=P(i,:);
    ids=[string(p.TBId),string(p.PHYGrantContextId)];
    numeric=[double(p.RNTI),double(p.HARQProcess),double(p.SweepPointIndex),double(p.Slot)];
    if any(ismissing(ids)) || any(strlength(strtrim(ids))==0) || any(~isfinite(numeric))
        continue;
    end
    sameTB=string(L.Direction)==string(p.Direction) & double(L.RNTI)==p.RNTI & ...
        double(L.HARQProcessId)==p.HARQProcess & string(L.TBId)==string(p.TBId) & ...
        double(L.SweepPointIndex)==p.SweepPointIndex;
    exact=find(sameTB & double(L.AttemptSlot)==p.Slot & ...
        string(L.PHYGrantContextId)==string(p.PHYGrantContextId));
    assert(numel(exact)<=1,'sixgr:truth:AmbiguousHARQTerminalAttempt', ...
        'More than one lifecycle row matches this physical HARQ attempt.');
    if isempty(exact), continue; end
    matched(i)=exact;
    P.TransmitterLifecycleBound(i)=true;
    P.LifecycleAttemptCount(i)=nnz(sameTB);
    terminal=double(L.TransmitterTerminal(exact));
    assert(isscalar(terminal) && any(terminal==[0 1]), ...
        'sixgr:truth:InvalidHARQTerminalFlag','Terminal flag must be exactly zero or one.');
    if terminal==1
        reason=string(L.TransmitterTerminalReason(exact));
        at=double(L.TerminalAtSlot(exact));
        assert(any(reason==["observed_ack_release","retry_limit_release"]) && ...
            isfinite(at) && at>=p.Slot,'sixgr:truth:InvalidHARQTerminalEvent', ...
            'Terminal reason and time must come from a causal transmitter release.');
        P.TransmitterTerminal(i)=true;
        P.TransmitterTerminalReason(i)=reason;
        P.TerminalAtSlot(i)=at;
        P.StopCondition(i)=reason;
    else
        P.StopCondition(i)="pending_transmitter_lifecycle";
    end
end
for direction=unique(string(P.Direction),'stable').'
    for id=unique(double(P.PacketID(string(P.Direction)==direction)),'stable').'
        idx=find(string(P.Direction)==direction & double(P.PacketID)==id);
        actual=matched(idx);
        valid=all(actual>0) && numel(unique(actual))==numel(actual) && ...
            all(P.LifecycleAttemptCount(idx)==numel(idx));
        crc=double(P.CombinedDecodeOK(idx));
        % Full delivery-failure claims require the original and every actual
        % transmission's receiver outcome, not a run-end or ACK inference.
        original=double(P.IsRetransmission(idx(1)))==0;
        P.HARQPacketReceiverPopulationComplete(idx)=valid && original && ...
            all(isfinite(crc) & (crc==0 | crc==1));
    end
end
end
