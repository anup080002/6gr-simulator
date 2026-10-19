function ok=testPacketHARQAttemptAccounting()
% Deterministic metadata reducer fixtures, not additional PHY observations.
% Runtime call-site integration is checked by the dedicated binding test.
setup6GRSimToolkit('Verbose',false);
state=fixture(); before=state;
state=sixgr.truth.reconcilePacketHARQAttempts(state);
assert(isequal(state.PacketDeliveryLedgerTable.HARQAttemptCount,[2;1;0]));
assert(isequal(state.PacketSDULedgerTable.HARQAttemptCount,[2;2;1]));
assert(isequaln(state.PacketDeliveryLedgerTable(:, ...
    {'OfferedBits','ScheduledBits','RemainingBits','DeliveredBits','DeliverySuccess'}), ...
    before.PacketDeliveryLedgerTable(:, ...
    {'OfferedBits','ScheduledBits','RemainingBits','DeliveredBits','DeliverySuccess'})), ...
    'Attempt reconciliation must not invent completed application bytes.');
assert(isequaln(sixgr.truth.reconcilePacketHARQAttempts(state),state));
ul=before; ul.PacketDeliveryLedgerTable.Direction(:)="UL";
ul.PacketSDULedgerTable.Direction(:)="UL"; ul.HARQTimelineTable.Direction(:)="UL";
ul=sixgr.truth.reconcilePacketHARQAttempts(ul);
assert(isequal(ul.PacketDeliveryLedgerTable.HARQAttemptCount,[2;1;0]));
% One actual TB owns two segments: 2 attempts, not 2 times 2 fragments.
duplicate=before;
duplicate.HARQTimelineTable=[duplicate.HARQTimelineTable;duplicate.HARQTimelineTable(1,:)];
duplicate=sixgr.truth.reconcilePacketHARQAttempts(duplicate);
assert(isequal(duplicate.PacketDeliveryLedgerTable.HARQAttemptCount,[2;1;0]));
% Completed applications must also retain later actual attempt counts (e.g.
% ACK loss). No generic DeliverySuccess short circuit may suppress the audit.
done=before; done.PacketDeliveryLedgerTable.DeliverySuccess(1)=true;
done.PacketDeliveryLedgerTable.DeliveredBits(1)=1000;
done=sixgr.truth.reconcilePacketHARQAttempts(done);
assert(done.PacketDeliveryLedgerTable.HARQAttemptCount(1)==2 && ...
    done.PacketDeliveryLedgerTable.DeliveredBits(1)==1000);
% A known empty current runtime ledger is zero; a missing ledger is unknown.
empty=before; empty.HARQTimelineTable=empty.HARQTimelineTable([],:);
empty=sixgr.truth.reconcilePacketHARQAttempts(empty);
assert(all(empty.PacketDeliveryLedgerTable.HARQAttemptCount==0));
missing=rmfield(before,'HARQTimelineTable');
missing=sixgr.truth.reconcilePacketHARQAttempts(missing);
assert(all(isnan(missing.PacketDeliveryLedgerTable.HARQAttemptCount)));
% Same local TB/packet label in the other UE must not share attempts.
wrong=before; wrong.HARQTimelineTable.RNTI(1)=4660;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:PacketAttemptOwnerMismatch');
wrong=before; wrong.HARQTimelineTable.NDIEpoch(1)=2;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:PacketAttemptOwnerMismatch');
wrong=before; wrong.HARQTimelineTable.Slot(1)=0;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:PacketAttemptOwnerMismatch');
wrong=before; wrong.PacketSDULedgerTable.UEIndex(1)=17;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:UnownedPacketSegment');
wrong=before; wrong.HARQTimelineTable.PHYGrantContextId(1)="";
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:MissingPacketAttemptIdentity');
wrong=before; wrong.HARQTimelineTable=[wrong.HARQTimelineTable;wrong.HARQTimelineTable(1,:)];
wrong.HARQTimelineTable.CombinedDecodeOK(end)=true;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:ConflictingPacketAttemptEvidence');
wrong=before; wrong.HARQTimelineTable.SweepPointIndex(2)=2;
reject(@()sixgr.truth.reconcilePacketHARQAttempts(wrong), ...
    'sixgr:protocol:AmbiguousPacketAttemptSweep');
ok=true;
end

function state=fixture()
p=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'PacketId',"packet", ...
    'ApplicationPacketId',"app",'OfferedBits',1000,'ScheduledBits',400, ...
    'RemainingBits',600,'DeliveredBits',0,'DeliverySuccess',false,'HARQAttemptCount',0);
packets=repmat(p,3,1); packets(2).UEIndex=2; packets(2).RNTI=1002;
packets(3).PacketId="not-scheduled"; packets(3).ApplicationPacketId="not-scheduled";
packets(3).ScheduledBits=0; packets(3).RemainingBits=1000;
s=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'PacketId',"packet", ...
    'ApplicationPacketId',"app",'TransportBlockId',"local-TB", ...
    'HARQProcessId',0,'NDIEpoch',1,'ScheduleSlot',1,'SegmentIndex',1, ...
    'PayloadBits',200,'HARQAttemptCount',99);
segments=repmat(s,3,1); segments(2).SegmentIndex=2;
segments(3).UEIndex=2; segments(3).RNTI=1002; segments(3).PayloadBits=400;
h=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'HarqID',0, ...
    'NDIEpoch',1,'TBId',"local-TB",'PHYGrantContextId',"attempt-1", ...
    'Slot',1,'CombinedDecodeOK',false,'SweepPointIndex',1);
attempts=repmat(h,3,1); attempts(2).PHYGrantContextId="attempt-2";
attempts(2).Slot=3; attempts(2).CombinedDecodeOK=true;
attempts(3).UEIndex=2; attempts(3).RNTI=1002;
state=struct('PacketDeliveryLedgerTable',struct2table(packets), ...
    'PacketSDULedgerTable',struct2table(segments),'HARQTimelineTable',struct2table(attempts));
end

function reject(call,id)
try, call(); catch ex, assert(string(ex.identifier)==id,ex.message); return; end
error('test:MissingPacketAttemptRejection','Expected %s.',id);
end
