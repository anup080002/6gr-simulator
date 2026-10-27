function ok=testProtocolBearerRelease()
% Release returns only stored, already decoded DRB SDUs (38.323 5.1.3).
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"DL");
for srb=[false true]
    cfg=c;
    if srb
        cfg.BearerType="SRB";cfg.BearerID="SRB-1";cfg.SRBID=1;cfg.QFI=0;
        cfg.LCID=1;cfg.PDCPSNBits=12;cfg.RLCSNBits=12;
    end
    r=sixgr.protocol.ProtocolRuntime(cfg);
    p0=r.transmit("missing-packet",uint8([1 2]),0); %#ok<NASGU>
    p1=r.transmit("received-packet",uint8([3 4]),.001);
    [delivered,completed]=r.receive(p1,.002);assert(~delivered&&isempty(completed));
    completed=r.release(.010);
    if srb
        assert(isempty(completed)&&r.PacketsDelivered==0);
    else
        assert(numel(completed)==1 && completed.PacketID=="received-packet" && ...
            isequal(completed.Payload,uint8([3 4])) && completed.DeliveryTime_s==.010 && r.PacketsDelivered==1);
    end
    assert(isinf(r.nextTimerExpiry())&&isempty(r.advance(.020)));
end
ok=true;
end
