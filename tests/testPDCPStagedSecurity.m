function ok=testPDCPStagedSecurity()
% Exact NIA2/NEA2 and original PDCP bytes at a declared RRC adapter boundary.
% No ASN.1, shared RF, NAS/AKA, or completed AS procedure is claimed here.
setup6GRSimToolkit('Verbose',false);
cfg=config();initialCfg=cfg;initialCfg.CipherAlgorithm="NEA0";initialCfg.IntegrityAlgorithm="NIA0";
e=sixgr.l2.pdcp18.PDCPBearerEntity(initialCfg);
initial=uint8([1 2 3]);p=e.transmit(initial,0);[s,c]=e.receive(p,0);
assert(isequal(s,{initial})&&c==0&&e.TX.current()==1);
context=securityContext(cfg);
e.stageSecurityContext('TX',context);e.stageSecurityContext('RX',context);
command=uint8([32 1 2 3 4 5]);r=receipt(context,'TX','security_command_issued',command,uint8([]),1,1);
e.activateTransmitIntegrity(context.ContextID,r);
assert(e.TXIntegrityActive&&~e.RXIntegrityActive&&~e.SecurityActive);
p=e.transmit(command,.001);
header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('SRB',12,p);
assert(header.SN==1&&isequal(header.Payload(1:end-4),command));
expected=sixgr.l2.pdcp18.PDCPSecurity128.nia2(context.IntegrityKey,1,0,1,p(1:end-4),8*(numel(p)-4));
assert(isequal(p(end-3:end),expected));
before=e.RX.snapshot();bad=p;bad(end)=bitxor(bad(end),uint8(1));
expectError(@()e.previewInitialIntegrityReceive(bad,.002),'sixgr:pdcp:IntegrityFailure');
assert(isequaln(before,e.RX.snapshot())&&~e.RXIntegrityActive);
expectError(@()e.receive(p,.002),'sixgr:pdcp:InitialSecurityVerificationRequired');
[payload,token]=e.previewInitialIntegrityReceive(p,.002);
assert(isequal(payload,command)&&isequaln(before,e.RX.snapshot()));
r=receipt(context,'RX','security_command_verified',command,p,1,2);
badReceipt=r;badReceipt.RRCPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(uint8(7));
expectError(@()e.commitInitialIntegrityReceive(token,badReceipt),'sixgr:pdcp:SecurityActivation');
assert(isequaln(before,e.RX.snapshot())&&~e.RXIntegrityActive);
[s,c]=e.commitInitialIntegrityReceive(token,r);
assert(isequal(s,{command})&&c==1&&e.RXIntegrityActive&&~e.RXCipheringActive&&e.TX.current()==2);
expectError(@()e.commitInitialIntegrityReceive(token,r),'sixgr:pdcp:SecurityReplay');
% Ciphering uses a separate original Complete lower-layer/receiver boundary.
complete=uint8([48 1]);r=receipt(context,'TX','security_complete_submitted',complete,uint8(1),1,3);
wrong=r;wrong.RRCTransactionID=2;
expectError(@()e.activateCiphering('TX',context.ContextID,wrong),'sixgr:pdcp:SecurityActivation');
wrong=r;wrong.AtSample=0;
expectError(@()e.activateCiphering('TX',context.ContextID,wrong),'sixgr:pdcp:SecurityActivation');
assert(~e.TXCipheringActive);
e.activateCiphering('TX',context.ContextID,r);
post=uint8([64 7 8 9]);p=e.transmit(post,.003);
assert(~isequal(p(3:end-4),post));before=e.RX.snapshot();
expectError(@()e.receive(p,.004),'sixgr:pdcp:IntegrityFailure');
assert(isequaln(before,e.RX.snapshot()));
r=receipt(context,'RX','security_complete_verified',complete,uint8(1),1,3);
e.activateCiphering('RX',context.ContextID,r);
[s,c]=e.receive(p,.004);assert(isequal(s,{post})&&c==2&&e.SecurityActive);
% A failed authenticated receive after t-Reordering expiry must not swallow
% unrelated original buffered deliveries. The explicit timer event owns them.
q=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);q.activateSecurity();
q.transmit(uint8(1),0);p1=q.transmit(uint8(2),0);p2=q.transmit(uint8(3),0);
assert(isempty(q.receive(p1,.001)));before=q.RX.snapshot();
p2(end)=bitxor(p2(end),uint8(1));
expectError(@()q.receive(p2,.004),'sixgr:pdcp:IntegrityFailure');
assert(isequaln(q.RX.snapshot(),before));
[s,c]=q.advance(.004);assert(isequal(s,{uint8(2)})&&c==1&&isempty(q.advance(.004)));
% A timer advance invalidates a previously authenticated but uncommitted token.
z=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);z.stageSecurityContext('RX',context);
sender=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);sender.stageSecurityContext('TX',context);
sender.activateTransmitIntegrity(context.ContextID,receipt(context,'TX','security_command_issued',command,uint8([]),0,0));
p=sender.transmit(command,0);[~,token]=z.previewInitialIntegrityReceive(p,.001);
z.advance(.0005);r=receipt(context,'RX','security_command_verified',command,p,0,1);
expectError(@()z.commitInitialIntegrityReceive(token,r),'sixgr:pdcp:StaleSecurityObservation');
before=z.RX.snapshot();z.cancelInitialIntegrityReceive(token);
assert(isequaln(before,z.RX.snapshot())&&~z.RXIntegrityActive);
expectError(@()z.cancelInitialIntegrityReceive(token),'sixgr:pdcp:SecurityReplay');
gap=sixgr.l2.pdcp18.PDCPBearerEntity(cfg);gap.stageSecurityContext('RX',context);
p=sender.transmit(command,.002); % Original COUNT1, with COUNT0 never received.
before=gap.RX.snapshot();
expectError(@()gap.previewInitialIntegrityReceive(p,.003),'sixgr:pdcp:InitialSecurityNotDeliverable');
assert(isequaln(before,gap.RX.snapshot())&&~gap.RXIntegrityActive);
missing=rmfield(cfg,'IntegrityKey');m=sixgr.l2.pdcp18.PDCPBearerEntity(missing);
expectError(@()m.activateSecurity(),'sixgr:pdcp:SecurityContextMissing');
exerciseRuntime();
fprintf('PDCP_STAGED_SECURITY_PASS NIA2=1 NEA2=1 endpoints_separate=1 original_COUNT_preserved=1 bad_integrity_atomic=1 RRC_adapter_component=1 RF=0\n');
ok=true;
end
function exerciseRuntime()
cfg=config();cfg.CipherAlgorithm="NEA0";c=securityContext(cfg);
rCfg=struct('UEID',cfg.UEID,'BearerID',cfg.BearerID,'BearerType',"SRB",'SRBID',1,'QFI',0, ...
 'LCID',1,'PDCPSNBits',12,'RLCSNBits',12,'ConfigurationEpoch',1,'Direction',"DL", ...
 'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0", ...
 'CipherKey',cfg.CipherKey,'IntegrityKey',cfg.IntegrityKey);
r=sixgr.protocol.ProtocolRuntime(rCfg);r.stageSecurityContext('TX',c);r.stageSecurityContext('RX',c);
payload=uint8([32 4 3 2 1]);r.activateTransmitIntegrity(c.ContextID,receipt(c,'TX','security_command_issued',payload,uint8([]),0,0));
p=r.transmit('original-security-message',payload,0);
[delivered,complete,~,status,observed]=r.receive(p,.002);
snapshot=r.securityState();
assert(~delivered&&isempty(complete)&&status=="authenticated_RRC_validation_pending"&& ...
 isequal(observed.Payload,payload)&&snapshot.RXState.RX_DELIV==0);
pdcp=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
boundary=receipt(c,'RX','security_command_verified',payload,pdcp.Payload,0,2);
bad=boundary;bad.PDCPPDUSHA256=sixgr.protocol.ProtocolHash.bytes(uint8(4));
expectError(@()r.commitInitialIntegrityReceive(observed.Token,bad),'sixgr:pdcp:SecurityActivation');
snapshot=r.securityState();assert(r.PacketsDelivered==0&&~snapshot.RXIntegrityActive);
complete=r.commitInitialIntegrityReceive(observed.Token,boundary);
snapshot=r.securityState();
assert(numel(complete)==1&&isequal(complete.Payload,payload)&&r.PacketsDelivered==1&& ...
 snapshot.RXIntegrityActive&&snapshot.TXCount==1);
expectError(@()r.commitInitialIntegrityReceive(observed.Token,boundary),'sixgr:pdcp:SecurityReplay');
end
function cfg=config()
cfg=struct('UEID',"cell1-1001",'BearerID',"SRB-1",'Bearer',0,'Direction',1,'BearerType',"SRB", ...
 'SNBits',12,'ConfigurationEpoch',1,'CipherAlgorithm',"128-NEA2",'IntegrityAlgorithm',"128-NIA2", ...
 'CipherKey',uint8(16:31),'IntegrityKey',uint8(0:15),'ReorderingTime_s',.002);
end
function c=securityContext(cfg)
c=struct('ContractVersion',"PDCP_endpoint_security/v1",'ContextID',"core-context-1", ...
 'UEID',cfg.UEID,'BearerID',cfg.BearerID,'Direction',cfg.Direction,'ConfigurationEpoch',cfg.ConfigurationEpoch, ...
 'CipherAlgorithm',cfg.CipherAlgorithm,'IntegrityAlgorithm',cfg.IntegrityAlgorithm, ...
 'CipherKey',cfg.CipherKey,'IntegrityKey',cfg.IntegrityKey,'SampleRateHz',1000,'ClockEpoch',1, ...
 'KeySource',"configured_preestablished_core_key");
end
function r=receipt(c,endpoint,purpose,sdu,pdu,count,sample)
r=struct('ContractVersion',"validated_RRC_security_boundary/v1",'ContextID',c.ContextID, ...
 'UEID',c.UEID,'BearerID',c.BearerID,'Direction',c.Direction,'ConfigurationEpoch',c.ConfigurationEpoch, ...
 'Endpoint',string(endpoint),'Purpose',string(purpose),'RRCTransactionID',1, ...
 'RRCPayloadSHA256',sixgr.protocol.ProtocolHash.bytes(sdu),'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdu), ...
 'OriginalObservationSHA256',sixgr.protocol.ProtocolHash.bytes(uint8([pdu sdu])), ...
 'PDCPCount',count,'AtSample',sample,'SampleRateHz',c.SampleRateHz,'ClockEpoch',c.ClockEpoch, ...
 'EvidenceBoundary',"declared_component");
end
function expectError(f,id)
try,f();catch ex,assert(string(ex.identifier)==id,ex.message);return;end
error('sixgr:test:MissingSecurityRejection','Expected %s.',id);
end
