function ok=testRLCMaxRetransmissionIndication()
% Exact authored reverse STATUS/clock boundary; no RRC/RF outcome claim.
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"UL",'RLCARQEnabled',true, ...
    'SampleRateHz',1000,'ClockEpoch',1,'RLCPollRetransmit_s',.045, ...
    'RLCReassembly_s',.035,'RLCStatusProhibit_s',0,'MaxRetxThreshold',1);
r=sixgr.protocol.ProtocolRuntime(c);r.enqueuePacket("original",uint8(1:10),0);
[~,t]=r.previewSegment(64,.001);r.commitPreparedSegment(t,.001);
n=struct('NACKSN',0,'SOstart',[],'SOend',[],'NACKRange',[]);
s=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(18,1,n);
r.receiveReverseStatus(s.Bytes,'first-NACK',.002);
assert(isempty(r.takeUpperLayerIndications())); % First consideration has RETX_COUNT=0.
[~,t]=r.previewSegment(64,.003);r.commitPreparedSegment(t,.003);
r.receiveReverseStatus(s.Bytes,'second-NACK',.004);
rows=r.takeUpperLayerIndications();assert(isscalar(rows));
assert(rows.RLCFullCount==0&&rows.Sample==4&&rows.MaxRetxThreshold==1&& ...
    rows.UEID=="UE-001"&&rows.BearerID=="DRB-1"&&rows.Direction=="UL"&& ...
    rows.ApplicationBytesDropped==0&&rows.UpperLayerAction=="pending_RRC_consumer");
assert(r.PacketsDelivered==0&&r.pendingTransmitBytes().AMRetransmissionBytes>0);
r.receiveReverseStatus(s.Bytes,'second-NACK',.005); % Same original receipt.
r.receiveReverseStatus(s.Bytes,'third-NACK-still-pending',.006);
r.advance(.100);
assert(isempty(r.takeUpperLayerIndications())&&r.PacketsDelivered==0&& ...
    r.pendingTransmitBytes().AMRetransmissionBytes>0);
ok=true;
end
