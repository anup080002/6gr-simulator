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
if ~ismember('DiscardedUnscheduledBits',P.Properties.VariableNames)
    P.DiscardedUnscheduledBits=zeros(height(P),1);
end
fields=[fields "DiscardedUnscheduledBits"];
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
    S.RecoveredViaRLC=false(height(S),1);
    S.RLCRecoverySourceTBIDsJSON=strings(height(S),1);
end
owned=false(height(S),1);
for p=1:height(P)
    counts=double([P.OfferedBits(p),P.ScheduledBits(p),P.RemainingBits(p),P.DeliveredBits(p)]);
    discarded=double(P.DiscardedUnscheduledBits(p));
    assert(all(isfinite(counts) & counts>=0 & counts==fix(counts)) && ...
        isfinite(discarded)&&discarded>=0&&discarded==fix(discarded)&& ...
        counts(1)==counts(2)+counts(3)+discarded, ...
        'sixgr:protocol:PacketBitConservationFailure', ...
        'Offered bits must equal scheduled, still queued and actual unsent-discarded bits.');
    if discarded>0
        validatePDCPDiscard(state,P(p,:));
        assert(discarded==counts(1)&&all(counts(2:4)==0), ...
            'sixgr:protocol:PacketBitConservationFailure','Only wholly unsubmitted packets can enter this discard partition.');
    end
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
    assert(all(isfinite(lengths) & lengths>=0 & lengths==fix(lengths)) && ...
        sum(lengths)==counts(2),'sixgr:protocol:PacketBitConservationFailure', ...
        'Committed SDU ranges must reconcile with scheduled application bits.');
    for z=reshape(idx(lengths==0),1,[])
        requireColumns(S,{'ProtocolMACPDUBytes','ProtocolMACSHA256','ProtocolEncodedRLC_SHA256'});
        assert(flag(S,z,'ProtocolPayloadSameWaveformTruth') && ...
            isfinite(S.ProtocolMACPDUBytes(z)) && S.ProtocolMACPDUBytes(z)>0 && ...
            strlength(string(S.ProtocolMACSHA256(z)))==64 && ...
            strlength(string(S.ProtocolEncodedRLC_SHA256(z)))==64, ...
            'sixgr:protocol:PacketBitConservationFailure','Zero application bytes require actual original protocol/header-bearing MAC evidence.');
    end
    starts=[0;cumsum(lengths)];
    appDelivered=flag(P,p,'DeliverySuccess');
    recovery=[];
    if ismember('RLCApplicationRecoveryEvidenceJSON',P.Properties.VariableNames) && ...
            strlength(string(P.RLCApplicationRecoveryEvidenceJSON(p)))>0
        recovery=validateRecovery(state,P(p,:),S);
        assert(appDelivered,'sixgr:protocol:InvalidApplicationDeliveryEvidence','Recovery receipt requires actual whole application release.');
    end
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
        if ~flag(S,j,'DeliverySuccess') && ~isempty(recovery) && protocol
            category="CompletedApplicationBits";
            S.RecoveredViaRLC(j)=true;
            start=starts(n)/8;stop=starts(n+1)/8;
            hit=recovery.Offsets<stop & recovery.Offsets+recovery.Lengths>start;
            S.RLCRecoverySourceTBIDsJSON(j)=string(jsonencode(recovery.TBIDs(hit)));
        elseif flag(S,j,'DeliverySuccess')
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
    if discarded>0
        P.BitConservationSchema(p)="packet_bit_ranges_with_PDCP_unsent_discard/v2";
        P.BitConservationStatus(p)="conserved_actual_PDCP_and_RLC_unsent_discard";
    end
    if P.UnresolvedReservedBits(p)>0
        P.BitConservationStatus(p)="conserved_ranges_unresolved_receiver_or_lifecycle_evidence";
    end
    if ~isempty(recovery)
        P.BitConservationSchema(p)="packet_bit_ranges_with_RLC_recovery/v2";
        P.BitConservationStatus(p)="conserved_original_ranges_with_actual_RLC_recovery";
    end
end

assert(all(owned),'sixgr:protocol:UnownedPacketSegment','Every committed segment requires an application owner.');
state.PacketDeliveryLedgerTable=P; state.PacketSDULedgerTable=S;
end

function validatePDCPDiscard(state,p)
id='sixgr:protocol:InvalidPDCPDiscardLedger';
requireColumns(p,{'DiscardReceiptID','ProtocolUEID','ProtocolBearerID','ProtocolConfigurationEpoch', ...
    'OriginalApplicationPayloadSHA256'});
T=sixgr.util.structGet(state,'ProtocolDiscardEventsTable',table());
assert(~isempty(T)&&ismember('ReceiptID',T.Properties.VariableNames),id,'Actual protocol discard event ledger required.');
hit=string(T.ReceiptID)==string(p.DiscardReceiptID);
assert(nnz(hit)==1,id,'Discard must join exactly one original protocol event.');
r=table2struct(T(hit,:));
bridge=sixgr.util.structGet(state,'ProtocolBridge',[]);
assert(isa(bridge,'sixgr.protocol.WaveformProtocolBridge')&& ...
    isequaln(r,bridge.originalDiscardReceipt(r.ReceiptID)),id,'Original private discard receipt changed.');
assert(r.UEIndex==p.UEIndex&&r.Direction==string(p.Direction)&& ...
    r.PacketID==string(p.ApplicationPacketId)&&r.UEID==string(p.ProtocolUEID)&& ...
    r.BearerID==string(p.ProtocolBearerID)&&r.ConfigurationEpoch==p.ProtocolConfigurationEpoch&& ...
    r.PayloadSHA256==string(p.OriginalApplicationPayloadSHA256)&& ...
    r.PacketizationMode=="queued_packet"&&r.Source=="original_PDCP_TX_discard_timer"&& ...
    r.LowerLayerDisposition=="discarded_wholly_unsubmitted"&&r.ObservedAtSample>=r.DeadlineSample&& ...
    r.ApplicationBytesDropped==r.PacketBytes&&8*r.ApplicationBytesDropped==p.DiscardedUnscheduledBits&& ...
    ~p.DeliverySuccess,id,'Only the original expired and wholly unsent packet can be counted as discarded.');
end

function result=validateRecovery(state,p,S)
id='sixgr:protocol:InvalidRLCRecoveryLedger';
requireColumns(p,{'RLCApplicationRecoveryEvidenceSHA256','OriginalApplicationPayloadSHA256'});
r=jsondecode(char(p.RLCApplicationRecoveryEvidenceJSON));
assert(isfield(r,'SHA256')&&string(r.SHA256)==string(p.RLCApplicationRecoveryEvidenceSHA256)&& ...
    sixgr.l2.mac.MACHash.of(orderfields(rmfield(r,'SHA256')))==string(r.SHA256),id,'Original private recovery receipt hash changed.');
assert(string(r.ContractVersion)=="sixgr.protocol.original_RLC_application_recovery/v1" && ...
    string(r.Owner.Direction)==string(p.Direction)&& ...
    string(r.Owner.PacketID)==string(p.PacketId)&&r.Owner.PayloadBytes*8==p.OfferedBits&& ...
    string(r.Owner.PayloadSHA256)==string(p.OriginalApplicationPayloadSHA256)&& ...
    string(r.DecodedApplicationPayloadSHA256)==string(p.OriginalApplicationPayloadSHA256)&& ...
    r.UniqueCoveredApplicationBytes*8==p.OfferedBits,id,'Recovery changed original application owner or byte extent.');
R=sixgr.util.structGet(state,'RLCRecoveryTransportLedgerTable',table());
columns={'Direction','UEIndex','PacketId','ApplicationPacketId','TransportBlockId', ...
    'ProtocolRLCFullCount','ProtocolBearerID','ProtocolUEID','ProtocolConfigurationEpoch','PayloadBits','ProtocolPayloadOffsetBits', ...
    'DeliverySuccess','ProtocolPayloadSameWaveformTruth','ProtocolDecodedBitExact','ProtocolDecodedBitCount', ...
    'ProtocolMACPDUBytes','ProtocolDecodedMACSHA256','ProtocolMACSHA256','ProtocolDecodedRLC_SHA256', ...
    'ProtocolEncodedRLC_SHA256','ProtocolReceiverEvidenceSource','ProtocolDeliveryStatus', ...
    'ProtocolPayloadSHA256','ProtocolDecodedPayloadSHA256'};
requireColumns(S,columns);T=S(:,columns);
original=string(S.Direction)==string(p.Direction)&S.UEIndex==p.UEIndex& ...
    string(S.PacketId)==string(p.PacketId)&string(S.ApplicationPacketId)==string(p.ApplicationPacketId);
assert(any(original)&&all(S.ProtocolRLCFullCount(original)==r.Owner.RLCFullCount)&& ...
    all(string(S.ProtocolBearerID(original))==string(r.Owner.BearerID))&& ...
    all(string(S.ProtocolUEID(original))==string(r.Owner.UEID))&& ...
    all(S.ProtocolConfigurationEpoch(original)==r.Owner.ConfigurationEpoch),id, ...
    'Recovered original ranges must retain the same private RLC bearer/count owner.');
if ~isempty(R),requireColumns(R,columns);T=[T;R(:,columns)];end
ids=string(r.ContributorTransportBlockIDs(:));offsets=double(r.ContributorOffsetsBytes(:));lens=double(r.ContributorLengthsBytes(:));
assert(numel(unique(ids))==numel(ids)&&numel(ids)==numel(offsets)&&numel(ids)==numel(lens),id,'Invalid contributor population.');
covered=false(1,p.OfferedBits/8);
for k=1:numel(ids)
    hit=string(T.TransportBlockId)==ids(k)&string(T.Direction)==string(p.Direction)&T.UEIndex==p.UEIndex& ...
        string(T.PacketId)==string(p.PacketId)&string(T.ApplicationPacketId)==string(p.ApplicationPacketId);
    assert(nnz(hit)==1,id,'Recovery must join exactly one original transport ledger owner.');s=T(hit,:);
    assert(flag(s,1,'DeliverySuccess')&&flag(s,1,'ProtocolPayloadSameWaveformTruth'),id,'Unreceived original TB cannot gain recovery decode evidence.');
    requireDecodedProof(s);
    mac=string(r.ContributorDecodedMACSHA256);rlc=string(r.ContributorDecodedRLCSHA256);fragment=string(r.ContributorFragmentSHA256);
    assert(s.ProtocolRLCFullCount==r.Owner.RLCFullCount&&string(s.ProtocolBearerID)==string(r.Owner.BearerID)&& ...
        string(s.ProtocolUEID)==string(r.Owner.UEID)&& ...
        s.ProtocolConfigurationEpoch==r.Owner.ConfigurationEpoch&&s.ProtocolPayloadOffsetBits==offsets(k)*8&& ...
        s.PayloadBits==lens(k)*8&&string(s.ProtocolDecodedMACSHA256)==mac(k)&& ...
        string(s.ProtocolDecodedRLC_SHA256)==rlc(k)&&string(s.ProtocolPayloadSHA256)==fragment(k)&& ...
        string(s.ProtocolDecodedPayloadSHA256)==fragment(k),id,'Original contributor scope, interval or decoded hashes disagree.');
    assert(isfinite(offsets(k))&&offsets(k)>=0&&offsets(k)==fix(offsets(k))&& ...
        isfinite(lens(k))&&lens(k)>=0&&lens(k)==fix(lens(k))&&offsets(k)+lens(k)<=numel(covered),id,'Invalid original coverage interval.');
    covered(offsets(k)+(1:lens(k)))=true;
end
assert(all(covered),id,'Recovery receipt leaves original application bytes uncovered.');
result=struct('TBIDs',ids,'Offsets',offsets,'Lengths',lens);
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
