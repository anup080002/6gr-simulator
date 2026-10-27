function ok=testSRB1RuntimeAdmission()
% Declared original-receipt component boundary, not a physical Setup claim.
for direction=["UL","DL"]
base=struct('UEID',"cell1-42",'BearerID',"SRB-1",'BearerType',"SRB",'SRBID',1, ...
 'QFI',0,'LCID',1,'PDCPSNBits',12,'RLCSNBits',12,'ConfigurationEpoch',1, ...
 'Direction',direction,'SampleRateHz',1000,'ClockEpoch',1);
scope=struct('ExecutionRunID',"component-run",'UEID',base.UEID,'ServingCell',1, ...
 'RNTI',42,'SRBID',1,'LCID',1,'Direction',direction,'ConfigurationEpoch',1, ...
 'SampleRateHz',1000,'ClockEpoch',1,'ProtocolConfigurationSHA256',sixgr.l2.mac.MACHash.of(orderfields(base)));
cfg=base;cfg.EndpointAdmissionMode="original_setup_required";cfg.EndpointAdmissionScope=scope;
r=sixgr.protocol.ProtocolRuntime(cfg);before=r.securityState();volume=r.pendingTransmitBytes();
expectError(@()r.enqueuePacket('early',uint8(1),0),'sixgr:protocol:SRB1EndpointNotAdmitted');
expectError(@()r.receive(struct(),0),'sixgr:protocol:SRB1EndpointNotAdmitted');
assert(isequaln(r.securityState(),before)&&isequaln(r.pendingTransmitBytes(),volume));
[issued,received]=receipts(scope);
r.admitIssuedSetup(issued,20);admission=r.endpointAdmissionState();
assert(admission.RXEnabled==(direction=="UL")&&admission.TXEnabled==(direction=="DL")&& ...
    isequaln(r.securityState(),before));
if direction=="UL"
    expectError(@()r.enqueuePacket('still-early',uint8(1),.020),'sixgr:protocol:SRB1EndpointNotAdmitted');
else
    expectError(@()r.receive(struct(),.020),'sixgr:protocol:SRB1EndpointNotAdmitted');
end
r.advance(.022);
expectError(@()r.admitReceivedSetup(received,21),'sixgr:protocol:SRB1AdmissionClock');
before=r.securityState();r.admitReceivedSetup(received,23);
assert(isequaln(r.securityState(),before));
payload=uint8([16 2 3 4 5]);r.enqueuePacket('actual-UL-DCCH-fixture',payload,.024);
p=r.prepareSegment(128,.025);m=sixgr.l2.mac.MACPDUAssembler.assemble(direction, ...
 struct('LCID',1,'Payload',p.Bytes,'OwnerID',p.PacketID),numel(p.Bytes)+3);
p.MACBytes=m.Bytes;p.MACSHA256=m.SHA256;
[delivered,completed]=r.receive(p,.027);
assert(delivered&&isequal(completed.Payload,payload));
before=r.securityState();r.admitReceivedSetup(received,27);
assert(isequaln(before,r.securityState())&&before.TXCount==1);
r.enqueuePacket('next-original-message',uint8(7),.028);after=r.securityState();
assert(after.TXCount==2,'Setup activation must preserve the original COUNT sequence.');
r.release(.029);
expectError(@()r.admitReceivedSetup(received,30),'sixgr:protocol:ReleasedBearer');
end
fprintf('SRB1_RUNTIME_ADMISSION_PASS UL_and_DL_opposite_endpoint_gates=1 original_COUNT_preserved=1 codec_boundary=1 RF=0\n');
ok=true;
end
function [r,q]=receipts(scope)
h=sixgr.protocol.ProtocolHash.bytes(uint8([1 2 3]));
r=scope;r.ContractVersion="issued_NR_SRB1_setup/v1";r.RRCTransactionID=0;r.RRCSetupSHA256=h;
r.TransmitComponentID="declared-original-setup";
for name=["TransmitEnqueueReceiptSHA256","OriginalComponentSampleSHA256","TransmitObservationSHA256","PhysicalTransmissionReceiptSHA256"]
 r.(name)=h;
end
r.TransmitStartSample=10;r.TransmitEndSampleExclusive=20;r.IssuedAtSample=20;r=seal(r);
q=scope;q.ContractVersion="received_NR_SRB1_setup/v1";q.RRCTransactionID=0;q.RRCSetupSHA256=h;
q.IssuedSetupReceiptSHA256=r.SHA256;q.ReceiverObservationID="declared-original-receiver";
for name=["ReceiverObservationSHA256","ReceivedMACPayloadSHA256","OriginalRARObservationSHA256","OriginalContentionObservationSHA256"]
 q.(name)=h;
end
q.ObservationStartSample=11;q.ObservationEndSampleExclusive=22;q.AvailableAtSample=23;q=seal(q);
end
function r=seal(r)
r.SHA256=sixgr.l2.mac.MACHash.of(r);
end
function expectError(f,id)
try,f();catch ex,assert(string(ex.identifier)==id,ex.message);return;end
error('sixgr:test:MissingRuntimeAdmissionGuard','Expected %s.',id);
end
