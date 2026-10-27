function ok=testProtocolOriginalSRBDelivery()
% Actual MAC/RLC/PDCP decode; radio transport is a declared component boundary.
base=struct('UEID',"cell1-42",'BearerID',"SRB-1",'BearerType',"SRB",'SRBID',1, ...
    'QFI',0,'LCID',1,'PDCPSNBits',12,'RLCSNBits',12,'ConfigurationEpoch',1, ...
    'Direction',"UL",'SampleRateHz',1000,'ClockEpoch',1,'ReorderingTime_s',.010);
for integrity=[false true]
    c=base;
    if integrity
        c.SecurityActive=true;c.CipherAlgorithm="NEA0";c.IntegrityAlgorithm="128-NIA2";
        c.IntegrityKey=uint8(0:15);
    end
    c.OriginalConnectionScope=scope(c);r=sixgr.protocol.ProtocolRuntime(c);
    payload=uint8([16 0 1 2 3 4]);p=r.transmit('original',payload,.001);p.TBID="declared-radio-TB";
    reject(@()r.originalReceivedSRBDelivery('original'),'sixgr:protocol:OriginalDeliveryMissing');
    [delivered,complete]=r.receive(p,.002);
    assert(delivered&&isequal(complete.Payload,payload));
    receipt=r.originalReceivedSRBDelivery('original');r.validateOriginalReceivedSRBDelivery(receipt);
    pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
    assert(receipt.ContractVersion=="original_PDCP_to_RRC_delivery/v1"&& ...
        receipt.ReceivedAtSample==2&&receipt.AvailableAtSample==2&&receipt.PDCPCount==0&& ...
        receipt.TransportBlockID==p.TBID&&receipt.OriginalMACSHA256==p.MACSHA256&& ...
        receipt.OriginalRLCEncodedSHA256==p.EncodedSHA256&& ...
        receipt.PDCPPDUSHA256==sixgr.protocol.ProtocolHash.bytes(pdcp.Payload)&& ...
        receipt.RRCPayloadSHA256==sixgr.protocol.ProtocolHash.bytes(payload)&& ...
        receipt.IntegrityVerified==integrity&&receipt.RXIntegrityActive==integrity&& ...
        receipt.Source=="original_RLC_PDCP_receiver_completion"&&~isfield(receipt,'PHYCRC'));
    bad=receipt;bad.AvailableAtSample=3;
    reject(@()r.validateOriginalReceivedSRBDelivery(bad),'sixgr:protocol:OriginalDeliveryMismatch');
    [delivered,complete]=r.receive(p,.003);assert(~delivered&&isempty(complete));
    assert(isequaln(receipt,r.originalReceivedSRBDelivery('original')));
end
% COUNT1 arrives first. Its receipt must retain its own arrival and TB identity
% after COUNT0 releases both packets at a later callback.
c=base;c.OriginalConnectionScope=scope(c);r=sixgr.protocol.ProtocolRuntime(c);
p0=r.transmit('count0',uint8([10 11]),.001);p0.TBID="original-TB0";
p1=r.transmit('count1',uint8([12 13]),.002);p1.TBID="original-TB1";
[delivered,complete]=r.receive(p1,.003);assert(~delivered&&isempty(complete));
reject(@()r.originalReceivedSRBDelivery('count1'),'sixgr:protocol:OriginalDeliveryMissing');
[delivered,complete]=r.receive(p0,.004);assert(delivered&&numel(complete)==2);
a=r.originalReceivedSRBDelivery('count0');b=r.originalReceivedSRBDelivery('count1');
assert(a.ReceivedAtSample==4&&a.AvailableAtSample==4&&b.ReceivedAtSample==3&& ...
    b.AvailableAtSample==4&&b.TransportBlockID==p1.TBID&&b.OriginalMACSHA256==p1.MACSHA256);
% Reserved RNTIs are rejected; the top two valid C-RNTIs remain usable.
for rnti=[65521 65522]
    c=base;c.OriginalConnectionScope=scope(c);c.OriginalConnectionScope.RNTI=rnti;
    valid=sixgr.protocol.ProtocolRuntime(c);assert(valid.UEID==base.UEID);
end
c.OriginalConnectionScope.RNTI=65523;
reject(@()sixgr.protocol.ProtocolRuntime(c),'sixgr:protocol:OriginalSubmissionScope');
fprintf('ORIGINAL_SRB_DELIVERY_PASS private_exact_bytes=1 original_receive_and_release_clocks=1 no_RF_claim=1\n');
ok=true;
end
function s=scope(c)
s=struct('ExecutionRunID',"declared-original-delivery",'UEID',c.UEID,'BearerID',c.BearerID, ...
    'ServingCell',1,'RNTI',42,'ConfigurationEpoch',1,'SampleRateHz',1000,'ClockEpoch',1, ...
    'ProtocolConfigurationSHA256',sixgr.l2.mac.MACHash.of(orderfields(c)));
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message);return;end
error('test:DeliveryGuard','Expected %s.',id);
end
