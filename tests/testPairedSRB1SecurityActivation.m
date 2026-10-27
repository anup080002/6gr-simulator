function ok=testPairedSRB1SecurityActivation()
% Actual original MAC/RLC/PDCP bytes; declared RRC/transport adapter boundary.
% No shared RF, ASN.1 validation, NAS, or completed main-run access is claimed.
[dl,cd]=runtime('DL',1);[ul,cu]=runtime('UL',0);
badClock=cu;badClock.SampleRateHz=2000;
reject(@()ul.stageSecurityContext('TX',badClock),'sixgr:protocol:SecurityActivationClock');
command=uint8([32 1 2 3 4]);
issued=receipt(cd,'TX','security_command_issued',command,uint8([]),0,0);
dl.activateTransmitIntegrity(cd.ContextID,issued);
p=dl.transmit('original-command',command,0);
[~,done,~,status,observed]=dl.receive(p,.001);
assert(isempty(done)&&status=="authenticated_RRC_validation_pending");
pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
rx=receipt(cd,'RX','security_command_verified',command,pdcp.Payload,0,1);
tx=receipt(cu,'TX','security_command_verified',command,pdcp.Payload,0,1);
d0=dl.securityState();u0=ul.securityState();
bad=tx;bad.RRCTransactionID=2;
reject(@()dl.commitReceivedSecurityCommand(observed.Token,rx,ul,cu.ContextID,bad), ...
    'sixgr:protocol:SecurityPairScope');
assert(isequaln(dl.securityState(),d0)&&isequaln(ul.securityState(),u0));
reject(@()dl.commitReceivedSecurityCommand(observed.Token,rx,ul,'wrong-context',tx), ...
    'sixgr:pdcp:SecurityActivation');
assert(isequaln(dl.securityState(),d0)&&isequaln(ul.securityState(),u0));
other=cu;other.IntegrityKey=uint8(16:31);ul.stageSecurityContext('TX',other);
reject(@()dl.commitReceivedSecurityCommand(observed.Token,rx,ul,cu.ContextID,tx), ...
    'sixgr:pdcp:SecurityPairScope');
assert(isequaln(dl.securityState(),d0)&&isequaln(ul.securityState(),u0));
ul.stageSecurityContext('TX',cu);
completed=dl.commitReceivedSecurityCommand(observed.Token,rx,ul,cu.ContextID,tx);
originalCommand=dl.originalReceivedSRBDelivery('original-command');
assert(originalCommand.SecurityContextID==cd.ContextID&&originalCommand.IntegrityVerified);
d=dl.securityState();u=ul.securityState();
assert(isscalar(completed)&&isequal(completed.Payload,command)&& ...
    d.RXIntegrityActive&&u.TXIntegrityActive&&~u.RXIntegrityActive&& ...
    ~d.RXCipheringActive&&~u.TXCipheringActive&&d.TXCount==1&&u.TXCount==0);
reject(@()dl.commitReceivedSecurityCommand(observed.Token,rx,ul,cu.ContextID,tx), ...
    'sixgr:pdcp:SecurityReplay');
complete=uint8([48 1]);q=ul.transmit('original-complete',complete,.002);
qpdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(q.Bytes,12);
header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('SRB',12,qpdcp.Payload);
assert(isequal(header.Payload(1:end-4),complete),'Complete must be unciphered.');
tx=receipt(cu,'TX','security_complete_submitted',complete,qpdcp.Payload,0,2);
rx=receipt(cd,'RX','security_complete_submitted',complete,qpdcp.Payload,0,2);
d0=dl.securityState();u0=ul.securityState();bad=rx;bad.AtSample=3;
reject(@()ul.activateSubmittedSecurityComplete(cu.ContextID,tx,dl,cd.ContextID,bad), ...
    'sixgr:protocol:SecurityPairScope');
assert(isequaln(dl.securityState(),d0)&&isequaln(ul.securityState(),u0));
ul.activateSubmittedSecurityComplete(cu.ContextID,tx,dl,cd.ContextID,rx);
d=dl.securityState();u=ul.securityState();
assert(d.RXCipheringActive&&u.TXCipheringActive&&~d.TXCipheringActive&&~u.RXCipheringActive);
[~,done,~,status,observed]=ul.receive(q,.003);
assert(isempty(done)&&status=="authenticated_RRC_validation_pending");
rx=receipt(cu,'RX','security_complete_verified',complete,qpdcp.Payload,0,3);
tx=receipt(cd,'TX','security_complete_verified',complete,qpdcp.Payload,0,3);
d0=dl.securityState();u0=ul.securityState();bad=tx;bad.RRCPayloadSHA256=string(repmat('f',1,64));
reject(@()ul.commitReceivedSecurityComplete(observed.Token,rx,dl,cd.ContextID,bad), ...
    'sixgr:protocol:SecurityPairScope');
assert(isequaln(dl.securityState(),d0)&&isequaln(ul.securityState(),u0));
completed=ul.commitReceivedSecurityComplete(observed.Token,rx,dl,cd.ContextID,tx);
originalComplete=ul.originalReceivedSRBDelivery('original-complete');
assert(originalComplete.SecurityContextID==cu.ContextID&&originalComplete.IntegrityVerified);
d=dl.securityState();u=ul.securityState();
assert(isscalar(completed)&&isequal(completed.Payload,complete)&& ...
    d.TXCipheringActive&&u.RXCipheringActive&&d.TXCount==1&&u.TXCount==1);
next=uint8([64 8 9 10]);wire=dl.transmit('after-complete',next,.004);
encoded=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(wire.Bytes,12);
assert(~isequal(encoded.Payload(3:end-4),next));
[delivered,completed]=dl.receive(wire,.005);
assert(delivered&&isscalar(completed)&&isequal(completed.Payload,next));
rejectMalformedLineage();rejectLateSubmission();
fprintf('PAIRED_SRB1_SECURITY_PASS no_partial_activation=1 original_COUNT_preserved=1 Complete_unciphered=1 configured_RRC_adapter=1 RF=0\n');
ok=true;
end
function [r,c]=runtime(direction,numericDirection)
cfg=struct('UEID',"cell1-42",'BearerID',"SRB-1",'BearerType',"SRB",'SRBID',1, ...
    'LCID',1,'QFI',0,'PDCPSNBits',12,'RLCSNBits',12,'Direction',string(direction), ...
    'ConfigurationEpoch',1,'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0", ...
    'SampleRateHz',1000,'ClockEpoch',1);
scope=struct('ExecutionRunID',"declared-paired-security",'UEID',cfg.UEID,'BearerID',cfg.BearerID, ...
    'ServingCell',1,'RNTI',42,'ConfigurationEpoch',1,'SampleRateHz',1000,'ClockEpoch',1, ...
    'ProtocolConfigurationSHA256',sixgr.l2.mac.MACHash.of(orderfields(cfg)));
cfg.OriginalConnectionScope=scope;r=sixgr.protocol.ProtocolRuntime(cfg);
c=struct('ContractVersion',"PDCP_endpoint_security/v1",'ContextID',"core-"+string(direction), ...
    'UEID',cfg.UEID,'BearerID',cfg.BearerID,'Direction',numericDirection,'ConfigurationEpoch',1, ...
    'CipherAlgorithm',"128-NEA2",'IntegrityAlgorithm',"128-NIA2", ...
    'CipherKey',uint8(16:31),'IntegrityKey',uint8(0:15),'SampleRateHz',1000,'ClockEpoch',1, ...
    'KeySource',"configured_preestablished_core_key");
r.stageSecurityContext('TX',c);r.stageSecurityContext('RX',c);
end
function rejectMalformedLineage()
[dl,cd]=runtime('DL',1);[ul,cu]=runtime('UL',0);payload=uint8([32 1 2]);
dl.activateTransmitIntegrity(cd.ContextID,receipt(cd,'TX','security_command_issued',payload,uint8([]),0,0));
p=dl.transmit('original-valid-integrity',payload,0);p.PacketSHA256=string(repmat('f',1,64));
[~,~,~,status,o]=dl.receive(p,.001);assert(status=="authenticated_RRC_validation_pending");
pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
rx=receipt(cd,'RX','security_command_verified',payload,pdcp.Payload,0,1);
tx=receipt(cu,'TX','security_command_verified',payload,pdcp.Payload,0,1);
d0=dl.securityState();u0=ul.securityState();
reject(@()dl.commitReceivedSecurityCommand(o.Token,rx,ul,cu.ContextID,tx),'sixgr:protocol:LineageViolation');
assert(isequaln(d0,dl.securityState())&&isequaln(u0,ul.securityState())&&dl.PacketsDelivered==0);
% Failed preflight retains the original private token; cancellation is explicit.
dl.cancelInitialIntegrityReceive(o.Token);
reject(@()dl.cancelInitialIntegrityReceive(o.Token),'sixgr:pdcp:SecurityReplay');
end
function rejectLateSubmission()
[dl,cd]=runtime('DL',1);[ul,cu]=runtime('UL',0);payload=uint8([32 3 2]);
dl.activateTransmitIntegrity(cd.ContextID,receipt(cd,'TX','security_command_issued',payload,uint8([]),0,0));
p=dl.transmit('command-before-late-submission',payload,0);[~,~,~,~,o]=dl.receive(p,.001);
pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
rx=receipt(cd,'RX','security_command_verified',payload,pdcp.Payload,0,1);
tx=receipt(cu,'TX','security_command_verified',payload,pdcp.Payload,0,1);
dl.commitReceivedSecurityCommand(o.Token,rx,ul,cu.ContextID,tx);
payload=uint8([48 1]);p=ul.transmit('complete-before-later-packet',payload,.002);
pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
tx=receipt(cu,'TX','security_complete_submitted',payload,pdcp.Payload,0,2);
rx=receipt(cd,'RX','security_complete_submitted',payload,pdcp.Payload,0,2);
ul.transmit('later-original-packet',uint8([64 2]),.003);
d0=dl.securityState();u0=ul.securityState();
reject(@()ul.activateSubmittedSecurityComplete(cu.ContextID,tx,dl,cd.ContextID,rx), ...
    'sixgr:protocol:SecurityActivationClock');
assert(isequaln(d0,dl.securityState())&&isequaln(u0,ul.securityState())&& ...
    ~d0.RXCipheringActive&&~u0.TXCipheringActive);
end
function r=receipt(c,endpoint,purpose,payload,pdu,count,sample)
r=struct('ContractVersion',"validated_RRC_security_boundary/v1",'ContextID',c.ContextID, ...
    'UEID',c.UEID,'BearerID',c.BearerID,'Direction',c.Direction,'ConfigurationEpoch',c.ConfigurationEpoch, ...
    'Endpoint',string(endpoint),'Purpose',string(purpose),'RRCTransactionID',1, ...
    'RRCPayloadSHA256',sixgr.protocol.ProtocolHash.bytes(payload), ...
    'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdu), ...
    'OriginalObservationSHA256',sixgr.protocol.ProtocolHash.bytes(uint8([pdu payload])), ...
    'PDCPCount',count,'AtSample',sample,'SampleRateHz',1000,'ClockEpoch',1,'EvidenceBoundary',"declared_component");
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message);return;end
error('test:PairedSecurityGuard','Expected %s.',id);
end
