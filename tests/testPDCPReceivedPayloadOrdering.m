function ok=testPDCPReceivedPayloadOrdering()
% Original decoded bytes, full COUNT, security order and actual expiry clock.
setup6GRSimToolkit('Verbose',false);
for snBits=[12 18]
    modulus=2^snBits; cfg=config(snBits,modulus-2);
    tx=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);
    rx=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);
    tx.activateSecurity(); rx.activateSecurity();
    bytes={uint8([137 1 2 3]),uint8([137 10 20 30]),uint8([137 4 5 6])};
    pdus=cellfun(@(b) tx.transmit(b),bytes,'UniformOutput',false);
    % Independently assemble plaintext integrity then cipher data+MAC-I;
    % the original SDAP header is clear. A round trip alone hides this bug.
    header=sixgr.l2.pdcp18.PDCPHeaderCodec.encode('DRB',snBits,modulus-2);
    mac=sixgr.l2.pdcp18.PDCPSecurity128.nia2(cfg.IntegrityKey,modulus-2, ...
        cfg.Bearer,cfg.Direction,[header bytes{1}],8*numel([header bytes{1}]));
    tail=sixgr.l2.pdcp18.PDCPSecurity128.nea2(cfg.CipherKey,modulus-2, ...
        cfg.Bearer,cfg.Direction,[bytes{1}(2:end) mac],8*(numel(bytes{1})-1+4));
    assert(isequal(pdus{1},uint8([header bytes{1}(1) tail])));
    assert(isempty(rx.receive(pdus{2},.001)));
    assert(isempty(rx.receive(pdus{3},.002)));
    [released,counts]=rx.receive(pdus{1},.003);
    assert(isequal(released,bytes) && isequal(counts,modulus-2:modulus));
    assert(rx.RX.RX_DELIV==modulus+1 && rx.RX.RX_NEXT==modulus+1);
    assert(isempty(rx.receive(pdus{2},.004)) && rx.DuplicateCount==1);
    assert(~rx.RX.TimerRunning);
end

cfg=config(12,0); cfg.ReorderingTime_s=.005;
tx=sixgr.l2.pdcp18.PDCPBearerEntity(cfg); rx=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);
tx.activateSecurity(); rx.activateSecurity();
p0=tx.transmit(uint8([137 1])); p1=tx.transmit(uint8([137 2]));
bad=p1; bad(end)=bitxor(bad(end),uint8(1));
mustThrow(@() rx.receive(bad,0),'sixgr:pdcp:IntegrityFailure');
assert(rx.RX.RX_NEXT==0 && isempty(rx.RX.Buffered));
assert(isempty(rx.receive(p1,.001)));
assert(isempty(rx.advance(.0059)));
[received,counts]=rx.advance(.006);
assert(isequal(received,{uint8([137 2])}) && isequal(counts,1));
assert(rx.RX.RX_DELIV==2 && isempty(rx.receive(p0,.007)));
mustThrow(@() rx.advance(.006),'sixgr:pdcp:ReorderingClockViolation');

% Receiver COUNT authority handles the exact half-window asymmetry.
s=sixgr.l2.pdcp18.PDCPReorderingState(12,4096);
assert(s.inferCount(4095)==4095 && s.inferCount(0)==4096);
assert(s.inferCount(2048)==2048);
s=sixgr.l2.pdcp18.PDCPReorderingState(12,0,0);
assert(isequal(s.receive(1,0),1) && s.RX_DELIV==2 && ~s.TimerRunning);

% Real SDAP/PDCP/RLC/MAC owners release the earlier buffered packet with
% its own identity, not the identity of the PDU closing the gap.
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',12,'RLCSNBits',12, ...
    'ConfigurationEpoch',1,'Direction',"UL",'ReorderingTime_s',.01);
runtime=sixgr.protocol.ProtocolRuntime(c);
a=runtime.transmit("packet-a",uint8([1 2 3]),0);
b=runtime.transmit("packet-b",uint8([4 5 6]),.001);
[delivered,records]=runtime.receive(b,.002);
assert(~delivered && isempty(records) && runtime.PacketsDelivered==0);
[delivered,records]=runtime.receive(a,.003);
assert(delivered && isequal(string({records.PacketID}),["packet-a" "packet-b"]));
assert(isequal(records(1).Payload,uint8([1 2 3])) && isequal(records(2).Payload,uint8([4 5 6])));
assert(all([records.DeliveryTime_s]==.003) && runtime.PacketsDelivered==2);
assert(~runtime.receive(b,.004) && runtime.PacketsDelivered==2);
ok=true;
end
function c=config(snBits,count)
c=struct('UEID',"UE-1",'BearerID',"DRB-1",'Bearer',1, ...
    'Direction',0,'BearerType',"DRB",'SNBits',snBits,'ConfigurationEpoch',1, ...
    'CipherAlgorithm',"128-NEA2",'IntegrityAlgorithm',"128-NIA2", ...
    'CipherKey',uint8(0:15),'IntegrityKey',uint8(16:31), ...
    'InitialCount',count,'ReorderingTime_s',.05,'SDAPHeaderPresent',true);
end
function mustThrow(f,id)
try, f(); catch e, assert(strcmp(e.identifier,id),'Unexpected failure: %s',e.identifier); return; end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
