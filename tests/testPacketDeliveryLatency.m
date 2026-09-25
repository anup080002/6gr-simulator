function ok=testPacketDeliveryLatency()
T=table(["UL";"UL";"UL"],["p1";"p1";"p2"],[1;1;1], ...
    [0;0;.001],[.002;.001;.004],'VariableNames', ...
    {'Direction','PacketId','DeliverySuccess','EnqueueTime_s','DeliveryTime_s'});
out=sixgr.kpi.packetDeliveryLatency(T);
assert(out.Valid && out.Count==2 && out.Mean_ms==2 && out.Sum_ms==4);
assert(isequal(out.FirstDeliveryRows,[2;3]) && out.P95_ms==3);
typed=T; typed.DeliverySuccess=logical(typed.DeliverySuccess);
assert(sixgr.kpi.packetDeliveryLatency(typed).Valid);
% Equal packet counters at different UEs are not duplicates.
peer=T; peer.UEId=[1;2;1];
out=sixgr.kpi.packetDeliveryLatency(peer); assert(out.Valid && out.Count==3);
for field=["EnqueueTime_s","DeliveryTime_s"]
    bad=removevars(T,field); out=sixgr.kpi.packetDeliveryLatency(bad);
    assert(~out.Valid && isnan(out.Mean_ms));
    bad=T; bad.(field)(1)=NaN; out=sixgr.kpi.packetDeliveryLatency(bad);
    assert(~out.Valid && isnan(out.Mean_ms));
end
bad=T; bad.EnqueueTime_s(1)=.0001;
out=sixgr.kpi.packetDeliveryLatency(bad); assert(~out.Valid);
bad=T; bad.DeliverySuccess(1)=NaN; out=sixgr.kpi.packetDeliveryLatency(bad); assert(~out.Valid);
bad=T; bad.Latency_ms=[99;1;3]; out=sixgr.kpi.packetDeliveryLatency(bad); assert(~out.Valid);
none=removevars(T,{'EnqueueTime_s','DeliveryTime_s'}); none.DeliverySuccess(:)=0;
out=sixgr.kpi.packetDeliveryLatency(none);
assert(out.Valid && out.Count==0 && isnan(out.Mean_ms) && out.Status=="unavailable_no_successful_delivery");
fprintf('PACKET_DELIVERY_LATENCY_PASS\n'); ok=true;
end
