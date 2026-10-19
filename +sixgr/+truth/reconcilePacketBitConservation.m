function state=reconcilePacketBitConservation(state)
% Disjoint application-range accounting from committed SDUs and real events.
% HARQ release is not an application-layer drop. Receiver CRC evidence and
% independently decoded protocol bytes remain separate authorities.
P=sixgr.util.structGet(state,'PacketDeliveryLedgerTable',table());
S=sixgr.util.structGet(state,'PacketSDULedgerTable',table());
if isempty(P), return; end
requireColumns(P,{'Direction','UEIndex','PacketId','ApplicationPacketId', ...
    'OfferedBits','ScheduledBits','RemainingBits','DeliveredBits','DeliverySuccess'});
assert(istable(S),'sixgr:protocol:InvalidPacketConservationInput','Require a typed SDU ledger.');
L=sixgr.truth.captureHARQTransmitterLifecycle(state);
H=sixgr.util.structGet(state,'HARQTimelineTable',table());
fields=["UnscheduledBits","ReservedInFlightBits","CRCConfirmedMappedBits", ...
    "BitVerifiedPendingReassemblyBits","CompletedApplicationBits", ...
    "HARQReleasedUndeliveredBits","UnresolvedReservedBits"];
for field=fields, P.(field)=zeros(height(P),1); end
P.HARQRetryLimitDroppedBits=zeros(height(P),1);
P.HARQObservedACKWithoutDecodeBits=zeros(height(P),1);
P.BitConservationErrorBits=nan(height(P),1);
P.BitConservationSchema=repmat("packet_bit_ranges/v1",height(P),1);
P.BitConservationStatus=strings(height(P),1);
if ~isempty(S)
    requireColumns(S,{'Direction','UEIndex','PacketId','ApplicationPacketId', ...
        'SegmentIndex','PayloadBits','DeliverySuccess','TransportBlockId', ...
        'RNTI','HARQProcessId','NDIEpoch','ScheduleSlot'});
    S.ApplicationRangeStartBit=nan(height(S),1);
    S.ApplicationRangeEndBitExclusive=nan(height(S),1);
    S.ApplicationRangeSource=strings(height(S),1);
    S.PacketBitState=strings(height(S),1);
end
owned=false(height(S),1);
for p=1:height(P)
    counts=double([P.OfferedBits(p),P.ScheduledBits(p),P.RemainingBits(p),P.DeliveredBits(p)]);
    assert(all(isfinite(counts) & counts>=0 & counts==fix(counts)) && ...
        counts(1)==counts(2)+counts(3), ...
        'sixgr:protocol:PacketBitConservationFailure', ...
        'Offered bits must equal committed scheduled bits plus unscheduled bits.');
    P.UnscheduledBits(p)=counts(3);
    idx=[];
    if ~isempty(S)
        mask=upper(string(S.Direction))==upper(string(P.Direction(p))) & ...
            double(S.UEIndex)==double(P.UEIndex(p)) & ...
            string(S.PacketId)==string(P.PacketId(p)) & ...
            string(S.ApplicationPacketId)==string(P.ApplicationPacketId(p));
        assert(~any(owned & mask),'sixgr:protocol:AmbiguousApplicationIdentity', ...
            'A segment cannot belong to two application owner rows.');
        owned=owned | mask;
        idx=find(mask);
        [sequence,order]=sort(double(S.SegmentIndex(idx))); idx=idx(order);
        % Queued applications legitimately own no segments, even after a
        % different application's first SDU is committed. Scalar indexing
        % can return a 0-by-0 empty; compare ordered values, not orientation.
        assert(isequal(sequence(:),(1:numel(idx)).'), ...
            'sixgr:protocol:InvalidPacketSegmentRanges', ...
            'Committed segment indices must identify each application range exactly once.');
    end
    lengths=zeros(0,1);
    if ~isempty(idx), lengths=double(S.PayloadBits(idx)); end
    assert(all(isfinite(lengths) & lengths>0 & lengths==fix(lengths)) && ...
        sum(lengths)==counts(2),'sixgr:protocol:PacketBitConservationFailure', ...
        'Committed SDU ranges must reconcile with scheduled application bits.');
    starts=[0;cumsum(lengths)];
    appDelivered=flag(P,p,'DeliverySuccess');
    assert((~appDelivered && counts(4)==0) || ...
        (appDelivered && counts(4)==counts(1) && counts(3)==0 && ~isempty(idx)), ...
        'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
        'This bounded application profile completes whole packets, not CRC sums.');
    for n=1:numel(idx)
        j=idx(n); bits=lengths(n);
        S.ApplicationRangeStartBit(j)=starts(n);
        S.ApplicationRangeEndBitExclusive(j)=starts(n+1);
        protocol=flag(S,j,'ProtocolPayloadSameWaveformTruth');
        S.ApplicationRangeSource(j)="ordered_committed_packet_mapping_not_decoded_application_bytes";
        if protocol
            requireColumns(S,{'ProtocolPayloadOffsetBits'});
            assert(double(S.ProtocolPayloadOffsetBits(j))==starts(n), ...
                'sixgr:protocol:InvalidPacketSegmentRanges', ...
                'Same-waveform payload offsets must match the committed range.');
            S.ApplicationRangeSource(j)="frozen_protocol_payload_offset";
        end
        if flag(S,j,'DeliverySuccess')
            if protocol
                requireDecodedProof(S(j,:));
                category="BitVerifiedPendingReassemblyBits";
                if appDelivered, category="CompletedApplicationBits"; end
            else
                assert(~appDelivered,'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
                    'CRC-mapped segments cannot establish application delivery.');
                category="CRCConfirmedMappedBits";
            end
        else
            assert(~appDelivered,'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
                'A completed application cannot contain an undelivered segment.');
            [category,reason]=unreceivedRangeState(S(j,:),L,H);
            if reason=="retry_limit_release"
                P.HARQRetryLimitDroppedBits(p)=P.HARQRetryLimitDroppedBits(p)+bits;
            elseif reason=="observed_ack_release"
                P.HARQObservedACKWithoutDecodeBits(p)=P.HARQObservedACKWithoutDecodeBits(p)+bits;
            end
        end
        P.(category)(p)=P.(category)(p)+bits;
        S.PacketBitState(j)=category;
    end
    partition=0;
    for field=fields, partition=partition+P.(field)(p); end
    P.BitConservationErrorBits(p)=counts(1)-partition;
    assert(P.BitConservationErrorBits(p)==0,'sixgr:protocol:PacketBitConservationFailure', ...
        'The disjoint bit-state partition must equal offered application bits.');
    P.BitConservationStatus(p)="conserved_disjoint_committed_ranges";
    if P.UnresolvedReservedBits(p)>0
        P.BitConservationStatus(p)="conserved_ranges_unresolved_receiver_or_lifecycle_evidence";
    end
end
assert(all(owned),'sixgr:protocol:UnownedPacketSegment','Every committed segment requires an application owner.');
state.PacketDeliveryLedgerTable=P; state.PacketSDULedgerTable=S;
end

function [category,reason]=unreceivedRangeState(s,L,H)
category="UnresolvedReservedBits"; reason="";
if isempty(L), return; end
requireColumns(L,{'Direction','RNTI','HARQProcessId','TBId','AttemptSlot', ...
    'PHYGrantContextId','TransmitterTerminal','TransmitterTerminalReason','TerminalAtSlot','Source'});
mask=upper(string(L.Direction))==upper(string(s.Direction)) & ...
    double(L.RNTI)==double(s.RNTI) & double(L.HARQProcessId)==double(s.HARQProcessId) & ...
    string(L.TBId)==string(s.TransportBlockId);
tx=L(mask,:);
if isempty(tx), return; end
assert(all(string(tx.Source)=="transmitter_HARQ_state_not_receiver_CRC") && ...
    min(double(tx.AttemptSlot))==double(s.ScheduleSlot), ...
    'sixgr:protocol:PacketLifecycleOwnerMismatch','Require the actual original TX owner and first slot.');
if ismember('SweepPointIndex',tx.Properties.VariableNames)
    assert(numel(unique(tx.SweepPointIndex))==1, ...
        'sixgr:protocol:PacketLifecycleOwnerMismatch','A TB cannot alias independent sweep lifecycles.');
end
ids=string(tx.PHYGrantContextId);
assert(all(~ismissing(ids) & strlength(strtrim(ids))>0) && ...
    numel(unique(ids))==height(tx),'sixgr:protocol:AmbiguousPacketLifecycleAttempt', ...
    'Every actual TX must have a distinct retained grant identity.');
terminal=double(tx.TransmitterTerminal);
assert(all(isfinite(terminal) & (terminal==0 | terminal==1)) && nnz(terminal)<=1, ...
    'sixgr:protocol:InvalidPacketTerminalEvidence','A TB has at most one terminal transmitter event.');
if ~any(terminal)
    category="ReservedInFlightBits";
    return;
end
terminalSlot=double(tx.TerminalAtSlot(logical(terminal)));
assert(isfinite(terminalSlot) && terminalSlot>=max(double(tx.AttemptSlot)), ...
    'sixgr:protocol:InvalidPacketTerminalEvidence','The release must follow every actual TX of this TB.');
% An ACK/NACK/DTX is not a data decode. To classify terminal undelivered
% ranges, every actual TX must have a matching completed receiver outcome.
if isempty(H), return; end
requireColumns(H,{'Direction','UEIndex','RNTI','HarqID','TBId', ...
    'PHYGrantContextId','NDIEpoch','Slot','CombinedDecodeOK'});
for k=1:height(tx)
    hit=upper(string(H.Direction))==upper(string(s.Direction)) & ...
        double(H.UEIndex)==double(s.UEIndex) & double(H.RNTI)==double(s.RNTI) & ...
        double(H.HarqID)==double(s.HARQProcessId) & ...
        double(H.NDIEpoch)==double(s.NDIEpoch) & ...
        string(H.TBId)==string(s.TransportBlockId) & ...
        string(H.PHYGrantContextId)==ids(k) & double(H.Slot)==double(tx.AttemptSlot(k));
    observed=double(H.CombinedDecodeOK(hit));
    if isempty(observed), return; end
    assert(all(isfinite(observed) & (observed==0 | observed==1)) && ...
        numel(unique(observed))==1,'sixgr:protocol:ConflictingPacketAttemptEvidence', ...
        'Retained observations must agree on one actual receiver CRC outcome.');
    if observed(1)==1
        % For example CRC passed but strict protocol delivery was rejected.
        % Do not convert that receiver/application boundary gap into a drop.
        return;
    end
end
reason=string(tx.TransmitterTerminalReason(logical(terminal)));
assert(any(reason==["retry_limit_release","observed_ack_release"]), ...
    'sixgr:protocol:InvalidPacketTerminalEvidence','Require the actual transmitter release reason.');
category="HARQReleasedUndeliveredBits";
end

function requireDecodedProof(s)
requireColumns(s,{'ProtocolDecodedBitExact','ProtocolDecodedBitCount','ProtocolMACPDUBytes', ...
    'ProtocolDecodedMACSHA256','ProtocolMACSHA256','ProtocolDecodedRLC_SHA256', ...
    'ProtocolEncodedRLC_SHA256','ProtocolReceiverEvidenceSource','ProtocolDeliveryStatus'});
assert(isequal(s.ProtocolDecodedBitExact,true) && ...
    isfinite(s.ProtocolDecodedBitCount) && s.ProtocolDecodedBitCount>0 && ...
    s.ProtocolDecodedBitCount==8*s.ProtocolMACPDUBytes && ...
    strlength(string(s.ProtocolMACSHA256))==64 && ...
    string(s.ProtocolDecodedMACSHA256)==string(s.ProtocolMACSHA256) && ...
    strlength(string(s.ProtocolEncodedRLC_SHA256))==64 && ...
    string(s.ProtocolDecodedRLC_SHA256)==string(s.ProtocolEncodedRLC_SHA256) && ...
    string(s.ProtocolDeliveryStatus)=="delivered_after_exact_phy_decode" && ...
    string(s.ProtocolReceiverEvidenceSource)== ...
        "actual_phy_decoder_bits_demuxed_through_strict_mac_rlc_pdcp_sdap", ...
    'sixgr:protocol:InvalidApplicationDeliveryEvidence', ...
    'Verified payload ranges require exact retained decoder MAC/RLC proof.');
end

function value=flag(T,row,name)
value=false;
if ismember(name,T.Properties.VariableNames)
    v=double(T.(name)(row));
    assert(isscalar(v) && isfinite(v) && any(v==[0 1]), ...
        'sixgr:protocol:InvalidPacketConservationInput','Evidence flags must be exactly zero or one.');
    value=logical(v);
end
end

function requireColumns(T,names)
assert(istable(T) && all(ismember(names,T.Properties.VariableNames)), ...
    'sixgr:protocol:IncompletePacketConservationSchema','Required conservation source columns are missing.');
end
