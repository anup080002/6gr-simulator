function ok=testPacketBitConservation()
% Real production reservation/HARQ state with DECLARED MAC outcome fixtures.
% These events are not waveform trials, measured BLER or protocol byte proof.
setup6GRSimToolkit('Verbose',false);
publicationRoot=fullfile(pwd,'logs','lls_repairs', ...
    ['packet_bit_publication_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
for direction=["DL","UL"]
    verifySingleCommittedRangeWithQueuedOwners(direction);
    [state,h]=fixture(direction);
    proposal=h.allocate(321,1,100);
    g=grant(direction,proposal.HARQ,1);
    before=state.PacketDeliveryLedgerTable;
    state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
        state,g,direction,'DCINotIssued',true);
    assert(isequaln(before,state.PacketDeliveryLedgerTable) && isempty(state.PacketSDULedgerTable));
    state=sixgr.truth.reconcilePacketBitConservation(state);
    p=state.PacketDeliveryLedgerTable;
    assert(p.UnscheduledBits==1600 && p.ReservedInFlightBits==0 && ...
        p.CompletedApplicationBits==0 && p.BitConservationErrorBits==0);
    proposal=h.allocate(321,1,100);
    g=grant(direction,proposal.HARQ,1);
    state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,direction,g);
    h.onTx(321,0,uint8(mod((1:800)',2)),g,1);
    state=sixgr.truth.reconcilePacketBitConservation(state);
    p=state.PacketDeliveryLedgerTable;
    assert(p.UnscheduledBits==800 && p.ReservedInFlightBits==800 && ...
        p.HARQReleasedUndeliveredBits==0 && p.UnresolvedReservedBits==0 && ...
        p.CompletedApplicationBits==0 && p.BitConservationErrorBits==0);
    assert(state.PacketSDULedgerTable.ApplicationRangeStartBit==0 && ...
        state.PacketSDULedgerTable.ApplicationRangeEndBitExclusive==800);
    assert(h.onFeedback(321,0,"NACK",'SourceSlot',1,'FeedbackSlot',2));
    state.HARQTimelineTable=receiverFixture(direction,g,false);
    retry=h.allocate(321,3,100,'NewData',false);
    r=grant(direction,retry.HARQ,3);
    old=state.PacketSDULedgerTable;
    state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
        state,r,direction,'DCINotIssued',true);
    assert(isequaln(old,state.PacketSDULedgerTable) && h.hasPendingRetx(321));
    state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,direction,r);
    assert(isequaln(old,state.PacketSDULedgerTable), ...
        'Retransmission must not reserve another application range.');
    h.onTx(321,0,uint8(mod((1:800)',2)),r,3);
    state.HARQTimelineTable=[state.HARQTimelineTable;receiverFixture(direction,r,false)];
    assert(h.onFeedback(321,0,"DTX",'SourceSlot',3,'FeedbackSlot',4));
    state=sixgr.truth.reconcilePacketBitConservation(state);
    p=state.PacketDeliveryLedgerTable;
    assert(p.HARQReleasedUndeliveredBits==800 && p.HARQRetryLimitDroppedBits==800 && ...
        p.ReservedInFlightBits==0 && p.UnscheduledBits==800 && ...
        p.CompletedApplicationBits==0 && p.BitConservationErrorBits==0);
    before=state;
    % Final feedback can happen without another RX callback. The production
    % publisher must refresh stale in-flight counters from the real owner.
    stale=before;
    stale.PacketDeliveryLedgerTable.ReservedInFlightBits=800;
    stale.PacketDeliveryLedgerTable.HARQReleasedUndeliveredBits=0;
    [published,paths]=sixgr.truth.publishPacketDeliveryLedgers(stale,fullfile(publicationRoot,direction));
    exported=sixgr.util.csvReadTable(paths.Application);
    exportedSDU=sixgr.util.csvReadTable(paths.SDU);
    assert(exported.ReservedInFlightBits==0 && exported.HARQReleasedUndeliveredBits==800 && ...
        exported.HARQAttemptCount==2 && exported.CompletedApplicationBits==0 && ...
        exported.BitConservationErrorBits==0 && exportedSDU.ApplicationRangeEndBitExclusive==800);
    assert(published.PacketDeliveryLedgerTable.HARQAttemptCount==2 && ...
        published.PacketSDULedgerTable.HARQAttemptCount==2);
    sixgr.util.csvWriteTable(fullfile(publicationRoot,direction,'harq','csv', ...
        'runtime_harq_process_timeline.csv'),stale.HARQTimelineTable,'PreserveSchema',true);
    assert(~h.onFeedback(321,0,"ACK",'SourceSlot',3,'FeedbackSlot',5));
    state=sixgr.truth.reconcilePacketBitConservation(state);
    assert(isequaln(state.PacketDeliveryLedgerTable,before.PacketDeliveryLedgerTable));
    assert(isequaln(state.PacketSDULedgerTable,before.PacketSDULedgerTable));
    % A release with incomplete receiver coverage is NOT a measured drop.
    missing=before; missing.HARQTimelineTable=missing.HARQTimelineTable(1,:);
    missing=sixgr.truth.reconcilePacketBitConservation(missing);
    assert(missing.PacketDeliveryLedgerTable.UnresolvedReservedBits==800 && ...
        missing.PacketDeliveryLedgerTable.HARQReleasedUndeliveredBits==0);
    % Lost ACK cannot erase an earlier successful receiver observation.
    success=before; success.PacketSDULedgerTable.DeliverySuccess=true;
    success.PacketSDULedgerTable.FirstSuccessDelivery=true;
    success.PacketSDULedgerTable.TBCrcPass=false; % later failed attempt
    success=sixgr.truth.reconcilePacketBitConservation(success);
    assert(success.PacketDeliveryLedgerTable.CRCConfirmedMappedBits==800 && ...
        success.PacketDeliveryLedgerTable.HARQReleasedUndeliveredBits==0 && ...
        success.PacketDeliveryLedgerTable.CompletedApplicationBits==0);
    bad=before; bad.PacketDeliveryLedgerTable.RemainingBits=801;
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:protocol:PacketBitConservationFailure');
    bad=before; bad.CurrentSweepPointIndex=0;
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:truth:HARQLifecycleSweepIdentityMissing');
    bad=before; bad.PacketSDULedgerTable=[bad.PacketSDULedgerTable;bad.PacketSDULedgerTable];
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:protocol:InvalidPacketSegmentRanges');
    bad=before; bad.PacketSDULedgerTable.ProtocolPayloadSameWaveformTruth=true;
    bad.PacketSDULedgerTable.ProtocolPayloadOffsetBits=8;
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:protocol:InvalidPacketSegmentRanges');
    bad=success; bad.PacketDeliveryLedgerTable.OfferedBits=800;
    bad.PacketDeliveryLedgerTable.RemainingBits=0;
    bad.PacketDeliveryLedgerTable.DeliveredBits=800;
    bad.PacketDeliveryLedgerTable.DeliverySuccess=true;
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:protocol:InvalidApplicationDeliveryEvidence');
    bad=before;
    bad.HARQTransmitterLifecycleArchive=sixgr.truth.captureHARQTransmitterLifecycle(bad);
    bad=rmfield(bad,direction+"Harq");
    bad.HARQTransmitterLifecycleArchive.TerminalAtSlot(end)=0;
    reject(@()sixgr.truth.reconcilePacketBitConservation(bad), ...
        'sixgr:protocol:InvalidPacketTerminalEvidence');
    % A declared false ACK releases TX state but cannot invent a good RX.
    [falseAck,ackOwner]=fixture(direction);
    proposal=ackOwner.allocate(321,1,100);
    a=grant(direction,proposal.HARQ,1);
    falseAck=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(falseAck,1,direction,a);
    ackOwner.onTx(321,0,uint8(mod((1:800)',2)),a,1);
    falseAck.HARQTimelineTable=receiverFixture(direction,a,false);
    assert(ackOwner.onFeedback(321,0,"ACK",'SourceSlot',1,'FeedbackSlot',2));
    falseAck=sixgr.truth.reconcilePacketBitConservation(falseAck);
    assert(falseAck.PacketDeliveryLedgerTable.HARQReleasedUndeliveredBits==800 && ...
        falseAck.PacketDeliveryLedgerTable.HARQObservedACKWithoutDecodeBits==800 && ...
        falseAck.PacketDeliveryLedgerTable.CompletedApplicationBits==0 && ...
        falseAck.PacketDeliveryLedgerTable.CRCConfirmedMappedBits==0);
end
fprintf('PACKET_BIT_PUBLICATION_FIXTURE=%s declared_MAC_only=1\n',publicationRoot);
ok=true;
end

function verifySingleCommittedRangeWithQueuedOwners(direction)
% The first real grant leaves other applications unscheduled. A scalar
% SDU column indexed by find(false) can have a different empty orientation
% from (1:0).'; this must not be mistaken for duplicate/missing segments.
[state,h]=fixture(direction);
queued=state.PacketDeliveryLedgerTable([1;1;1],:);
queued.PacketId(1)="queued-packet";
queued.ApplicationPacketId(2)="queued-application";
otherDirection="UL";
if direction=="UL", otherDirection="DL"; end
queued.Direction(3)=otherDirection;
proposal=h.allocate(321,1,100);
g=grant(direction,proposal.HARQ,1);
state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,direction,g);
h.onTx(321,0,uint8(mod((1:800)',2)),g,1);
assert(height(state.PacketSDULedgerTable)==1);
committed=state.PacketDeliveryLedgerTable;
for committedFirst=[true,false]
    candidate=state;
    candidate.PacketDeliveryLedgerTable=[committed;queued];
    if ~committedFirst
        candidate.PacketDeliveryLedgerTable=[queued;committed];
    end
    actual=sixgr.truth.refreshApplicationPacketDeliveries(candidate);
    P=actual.PacketDeliveryLedgerTable;
    pending=P.ScheduledBits==0;
    assert(nnz(pending)==3 && all(P.UnscheduledBits(pending)==1600) && ...
        all(P.ReservedInFlightBits(pending)==0) && ...
        all(P.CompletedApplicationBits==0) && all(~P.DeliverySuccess) && ...
        all(P.BitConservationErrorBits==0));
    assert(nnz(~pending)==1 && P.UnscheduledBits(~pending)==800 && ...
        P.ReservedInFlightBits(~pending)==800 && ...
        actual.PacketSDULedgerTable.ApplicationRangeStartBit==0 && ...
        actual.PacketSDULedgerTable.ApplicationRangeEndBitExclusive==800);
    % Shape normalization must retain genuine sequence and orphan guards.
    invalid=candidate; invalid.PacketSDULedgerTable.SegmentIndex(1)=2;
    reject(@()sixgr.truth.reconcilePacketBitConservation(invalid), ...
        'sixgr:protocol:InvalidPacketSegmentRanges');
    invalid=candidate; invalid.PacketSDULedgerTable.PacketId(1)="no-owner";
    reject(@()sixgr.truth.reconcilePacketBitConservation(invalid), ...
        'sixgr:protocol:PacketBitConservationFailure');
end
end

function [state,h]=fixture(direction)
h=sixgr.l2.mac.HARQEntity(struct(),'Direction',direction,'NumProcesses',1,'MaxRetx',1);
p=struct('Direction',direction,'UEIndex',1,'RNTI',321,'PacketId',"packet", ...
    'ApplicationPacketId',"app",'OfferedBits',1600,'ScheduledBits',0, ...
    'RemainingBits',1600,'DeliveredBits',0,'DeliverySuccess',false,'HARQAttemptCount',0, ...
    'SegmentCount',0,'FirstGrantSlot',NaN,'FirstGrantTime_s',NaN,'Status',"queued", ...
    'PacketizationSource',"declared_MAC_component_fixture_not_measured_waveform_result");
state=struct('NumUsers',1,'CurrentSlot',1,'CurrentFrame',1,'CurrentSweepPointIndex',1, ...
    'CurrentSNR_dB',20,'SlotDuration_s',.001,'ProtocolWaveformEnabled',false, ...
    'PacketDeliveryLedgerTable',struct2table(p),'PacketSDULedgerTable',table(), ...
    'DLGrantTraceTable',table(),'ULGrantTraceTable',table(),'HARQTimelineTable',table());
state.(direction+"Harq")=h;
state.(direction+"QueueBits")=1600;
state.(direction+"TransmittedBits")=0;
end

function g=grant(direction,harq,slot)
layout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',harq.RV, ...
    'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
g=struct('RNTI',321,'UEIndex',1,'ServingCell',1,'Slot',slot,'Frame',1, ...
    'HARQ',harq,'TBSBits',800,'Direction',direction,'Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout, ...
    'TBId',direction+"-TB-1",'TransportBlockId',direction+"-TB-1", ...
    'GrantContextId',direction+"-attempt-"+slot, ...
    'PHYGrantContextId',direction+"-attempt-"+slot);
end

function T=receiverFixture(direction,g,crc)
T=struct2table(struct('Direction',direction,'UEIndex',1,'RNTI',321, ...
    'HarqID',g.HARQ.HarqID,'NDIEpoch',g.HARQ.NDIEpoch,'TBId',g.TBId, ...
    'PHYGrantContextId',g.PHYGrantContextId,'Slot',g.Slot,'CombinedDecodeOK',crc, ...
    'Source',"declared_MAC_component_fixture_not_waveform_result"));
end

function reject(call,id)
try, call(); catch ex
    assert(string(ex.identifier)==id,'test:UnexpectedPacketConservationError', ...
        'Expected %s; received %s: %s',id,ex.identifier,ex.message);
    return;
end
error('test:MissingPacketConservationRejection','Expected %s.',id);
end
