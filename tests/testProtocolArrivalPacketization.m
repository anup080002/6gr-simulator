function ok=testProtocolArrivalPacketization()
p=struct('traffic',struct('sessions',struct('flow_id',"data", ...
    'qfi',9,'pdu_session_id',3,'direction',"BIDIR",'packet_bytes',1500)));
for bits=[0 8 12000 12008 2000000 3000000]
    [sizes,m]=sixgr.protocol.packetizeApplicationArrival(bits,p,'UL');
    assert(sum(sizes)==bits && all(sizes>0 & sizes<=12000 & mod(sizes,8)==0));
    assert(m.QFI==9 && m.FlowID=="data"&&m.PduSessionID==3);
end
for bad=[0 9000 NaN 1.5]
    q=p; q.traffic.sessions.packet_bytes=bad; thrown=false;
    try, sixgr.protocol.packetizeApplicationArrival(12000,q,'DL');
    catch e, thrown=strcmp(e.identifier,'sixgr:protocol:InvalidApplicationPacketSize'); end
    assert(thrown);
end
ok=true;
end
