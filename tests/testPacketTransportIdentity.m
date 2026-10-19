function ok=testPacketTransportIdentity()
% Declared ledger fixture exercises production reservation and RX matching.
% No waveform/application-byte delivery is claimed by these metadata rows.
setup6GRSimToolkit('Verbose',false);
p=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'PacketId',"packet-ue1", ...
    'ApplicationPacketId',"packet-ue1",'OfferedBits',128,'RemainingBits',128, ...
    'ScheduledBits',0,'SegmentCount',0,'FirstGrantSlot',NaN,'FirstGrantTime_s',NaN, ...
    'DeliverySuccess',false,'Status',"queued");
packets=repmat(p,2,1); packets(2).UEIndex=2; packets(2).RNTI=1002;
% The complete owner key includes the UE, not just a packet label.
packets(2).PacketId=packets(1).PacketId;
packets(2).ApplicationPacketId=packets(1).ApplicationPacketId;
state=struct('NumUsers',2,'ProtocolWaveformEnabled',false, ...
    'PacketDeliveryLedgerTable',struct2table(packets), ...
    'PacketSDULedgerTable',table(),'DLQueueBits',[128;128], ...
    'DLTransmittedBits',[0;0],'MultiUser',struct('RNTIStart',1001), ...
    'CurrentSlot',16,'CurrentFrame',1,'SlotDuration_s',.5e-3, ...
    'DLGrantTraceTable',table(),'ULGrantTraceTable',table());
g=struct('TBSBits',64,'RNTI',1001,'UEIndex',1,'Slot',16,'Frame',1, ...
    'ServingCell',1,'TransportBlockId',"deliberately-reused-label", ...
    'TBId',"deliberately-reused-label",'GrantContextId',"attempt-ue1", ...
    'HARQ',struct('IsRetransmission',false,'HarqID',0,'NDI',1,'NDIEpoch',1,'RV',0));
state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',g);
other=g; other.UEIndex=2; other.RNTI=1002; other.GrantContextId="attempt-ue2";
state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,2,'DL',other);
T=state.PacketSDULedgerTable;
assert(height(T)==2 && all(T.NDIEpoch==1) && all(T.ServingCell==1));
assert(all(T.SegmentIndex==1),'sixgr:test:CrossUEFragmentNumbering', ...
    'Each UE must begin at fragment one even when packet labels coincide.');
assert(all(T.DeliveryEvidenceMode=="CRC_CONFIRMED_PACKET_MAPPING") && ...
    ~any(T.DeliverySuccess) && ~any(T.ProtocolDecodedBitExact));
assert(isequal(sixgr.truth.matchPacketTransportBlock(T,g,'DL',1),[true;false]));
assert(isequal(sixgr.truth.matchPacketTransportBlock(T,other,'DL',2),[false;true]));
% A retransmission has a different attempt, resource and RV, not a new TB.
retry=g; retry.Slot=20; retry.GrantContextId="retry-attempt";
retry.HARQ.IsRetransmission=true; retry.HARQ.RV=2;
assert(isequal(sixgr.truth.matchPacketTransportBlock(T,retry,'DL',1),[true;false]));
after=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',retry);
assert(isequaln(after.PacketSDULedgerTable,T) && isequal(after.DLQueueBits,state.DLQueueBits));
bad=g; bad.HARQ.NDIEpoch=2;
reject(@()sixgr.truth.matchPacketTransportBlock(T,bad,'DL',1),'sixgr:truth:PacketTransportIdentityMismatch');
bad=g; bad.RNTI=4660;
reject(@()sixgr.truth.matchPacketTransportBlock(T,bad,'DL',1),'sixgr:truth:PacketTransportIdentityMismatch');
reject(@()sixgr.truth.matchPacketTransportBlock(T,g,'DL',2),'sixgr:truth:PacketTransportOwnerMismatch');
bad=g; bad.HARQTBContext=struct('TBId',"another-block");
reject(@()sixgr.truth.resolveGrantTransportBlockIdentity(bad),'sixgr:truth:ConflictingGrantTransportBlockIdentity');
bad=rmfield(g,{'TransportBlockId','TBId'}); bad.MACSDUId="not-a-tb";
reject(@()sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',bad), ...
    'sixgr:truth:MissingRuntimeTransportBlockIdentity');
% Same process/NDI bit after reuse is a new explicit TB, not the old mapping.
fresh=g; fresh.TBId="new-block"; fresh.TransportBlockId="new-block";
fresh.HARQ.NDIEpoch=2;
assert(~any(sixgr.truth.matchPacketTransportBlock(T,fresh,'DL',1)));
ok=true;
end
function reject(f,id)
try, f(); catch ex, assert(string(ex.identifier)==id,ex.message); return; end
error('test:MissingIdentityRejection','Expected %s.',id);
end
