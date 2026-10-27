function ok=testProtocolOriginalSubmission()
% Original PDCP/RLC enqueue boundary; no MAC/PHY transmission is implied.
base=struct('UEID',"cell1-42",'BearerID',"SRB-1",'BearerType',"SRB",'SRBID',1, ...
    'QFI',0,'LCID',1,'PDCPSNBits',12,'RLCSNBits',12,'ConfigurationEpoch',1, ...
    'Direction',"UL",'SampleRateHz',1000,'ClockEpoch',1);
scope=struct('ExecutionRunID',"declared-connection-test",'UEID',base.UEID,'BearerID',base.BearerID, ...
    'ServingCell',1,'RNTI',42,'ConfigurationEpoch',1,'SampleRateHz',1000,'ClockEpoch',1, ...
    'ProtocolConfigurationSHA256',sixgr.l2.mac.MACHash.of(orderfields(base)));
cfg=base;cfg.OriginalConnectionScope=scope;r=sixgr.protocol.ProtocolRuntime(cfg);
before=r.securityState();
reject(@()r.enqueuePacket('fractional',uint8(1),.00025),'sixgr:protocol:OriginalSubmissionScope');
assert(isequaln(before,r.securityState()));
payload=uint8([0 7 8 9]);packet=r.enqueuePacket('original',payload,.001);
receipt=r.originalLowerLayerSubmission('original');r.validateOriginalLowerLayerSubmission(receipt);
assert(receipt.ContractVersion=="original_PDCP_to_RLC_submission/v1"&& ...
    receipt.SubmittedAtSample==1&&receipt.PDCPCount==0&&receipt.RLCQueueID==packet.RLCQueueID&& ...
    receipt.PDCPPDUSHA256==packet.PDCPPDUSHA256&& ...
    receipt.PDCPPDUSHA256==sixgr.protocol.ProtocolHash.bytes(receipt.PDCPPDU)&& ...
    receipt.Source=="original_RLCEntity_addSDU_handoff"&& ...
    ~receipt.TXIntegrityActive&&~receipt.TXCipheringActive);
header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('SRB',12,receipt.PDCPPDU);
assert(isequal(header.Payload(1:end-4),payload)&&all(header.Payload(end-3:end)==0));
volume=r.pendingTransmitBytes();assert(volume.RLCPayloadBytes==numel(receipt.PDCPPDU));
bad=receipt;bad.SubmittedAtSample=2;
reject(@()r.validateOriginalLowerLayerSubmission(bad),'sixgr:protocol:OriginalSubmissionMismatch');
reject(@()r.originalLowerLayerSubmission('not-submitted'),'sixgr:protocol:OriginalSubmissionMissing');
r.enqueuePacket('original',payload,.002);after=r.securityState();
assert(isequaln(receipt,r.originalLowerLayerSubmission('original'))&&after.TXCount==1&& ...
    isequaln(volume,r.pendingTransmitBytes()));
unscoped=sixgr.protocol.ProtocolRuntime(base);unscoped.enqueuePacket('unscoped',payload,0);
reject(@()unscoped.originalLowerLayerSubmission('unscoped'),'sixgr:protocol:OriginalSubmissionMissing');
cfg.OriginalConnectionScope.ProtocolConfigurationSHA256=string(repmat('f',1,64));
reject(@()sixgr.protocol.ProtocolRuntime(cfg),'sixgr:protocol:OriginalSubmissionScope');
fprintf('ORIGINAL_PDCP_RLC_SUBMISSION_PASS exact_original_bytes_COUNT_clock=1 private_receipt=1 no_MAC_or_RF_claim=1\n');
ok=true;
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message);return;end
error('test:SubmissionGuard','Expected %s.',id);
end
