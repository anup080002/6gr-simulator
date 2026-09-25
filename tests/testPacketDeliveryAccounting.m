function ok=testPacketDeliveryAccounting()
T=table(["UL";"UL";"UL";"UL"],[1;1;2;1],[1;1;1;2], ...
    ["p1";"p1";"p1";"p1"],true(4,1), ...
    'VariableNames',{'Direction','UEId','SweepPointIndex','PacketId','DeliverySuccess'});
out=sixgr.kpi.packetDeliveryAccounting(T,T.PacketId,800*ones(4,1));
assert(out.Valid && out.DeliveredBits==2400 && out.FirstCount==3 && out.DuplicateCount==1);
bad=T; bad.PacketId(1)="";
out=sixgr.kpi.packetDeliveryAccounting(bad,bad.PacketId,800*ones(4,1));
assert(~out.Valid && isnan(out.DeliveredBits) && out.FailureReason=="delivered_packet_identity_missing");
out=sixgr.kpi.packetDeliveryAccounting(T,T.PacketId,[800;900;800;800]);
assert(~out.Valid && out.FailureReason=="duplicate_packet_payload_size_disagrees");
out=sixgr.kpi.packetDeliveryAccounting(T,T.PacketId,ones(3,1)); assert(~out.Valid);
bad=T; bad.DeliverySuccess=ones(4,1); bad.DeliverySuccess(1)=NaN;
out=sixgr.kpi.packetDeliveryAccounting(bad,bad.PacketId,800*ones(4,1)); assert(~out.Valid);
none=T; none.DeliverySuccess(:)=false; none.PacketId(:)="";
out=sixgr.kpi.packetDeliveryAccounting(none,none.PacketId,NaN(4,1));
assert(out.Valid && out.DeliveredBits==0 && out.FirstCount==0);
fprintf('PACKET_DELIVERY_ACCOUNTING_PASS\n'); ok=true;
end
