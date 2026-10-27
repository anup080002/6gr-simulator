function ok=testOriginalDRBWaveformBridge()
% Component admission receipts + original codecs; no radio/RRC proof claim.
setup6GRSimToolkit('Verbose',false);
c=struct('enabled',true,'strict',true,'configuration_epoch',7);
c.mac=struct('bearer_configuration_authority',"original_received_RRC");
b=sixgr.protocol.WaveformProtocolBridge(c,1);
assert(~b.hasInstalledRuntime(1)&&~b.endpointAdmitted(1,'UL','TX'));
v=b.pendingTransmitBytes(1,'UL');assert(v.TotalBSRBytes==0&&~b.hasInstalledRuntime(1));
mustThrow(@()b.enqueuePacket(1,'UL','uninstalled',uint8(1:5),0),'sixgr:protocol:OriginalDRBRequired');
assert(~b.hasInstalledRuntime(1));
[ul,ui,ur]=owner('UL');[dl,di,dr,dc]=owner('DL');
connection=connectionOf(ui);
b.validateOriginalDRBBankAvailable(1,dl,ul);
assert(~b.hasInstalledRuntime(1));
mustThrow(@()b.installOriginalDRBPair(1,dl,ul,connection),'sixgr:protocol:DRBConnectionScope');
assert(~b.hasInstalledRuntime(1));
ul.admitIssuedReconfiguration(ui,20);dl.admitIssuedReconfiguration(di,20);
assert(isequaln(ul.originalIssuedReconfigurationReceipt(),ui));
% Same connection/bearer is insufficient if the two handles came from
% different original issued RRC transactions or protected transmissions.
for fault=1:3
    [mixed,mi]=owner('UL');
    if fault==1,mi.RRCTransactionID=2;
    elseif fault==2,mi.RRCReconfigurationSHA256=hash('other-message');
    else,mi.ProtectedPDCPPDUSHA256=hash('other-protected-PDU');end
    mi=seal(mi);mixed.admitIssuedReconfiguration(mi,20);
    mustThrow(@()b.installOriginalDRBPair(1,dl,mixed,connection),'sixgr:protocol:DRBConnectionScope');
    assert(~b.hasInstalledRuntime(1));
end
b.installOriginalDRBPair(1,dl,ul,connection);
assert(b.hasInstalledRuntime(1)&&b.endpointAdmitted(1,'UL','RX')&&~b.endpointAdmitted(1,'UL','TX'));
assert(~b.endpointAdmitted(1,'DL','RX')&&~b.endpointAdmitted(1,'DL','TX'));
before=ul.securityState();
mustThrow(@()b.enqueuePacket(1,'UL','before-received',uint8(1:5),.021),'sixgr:protocol:DRBEndpointNotAdmitted');
assert(isequaln(before,ul.securityState()));
ul.admitReceivedReconfiguration(ur,30);dl.admitReceivedReconfiguration(dr,30);
p=b.enqueuePacket(1,'UL','original-packet',uint8(1:35),.031);
assert(p.UEID==ui.UEID&&p.BearerID==ui.BearerID&&p.ConfigurationEpoch==7);
assert(ul.pendingTransmitBytes().TotalBSRBytes==39);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39);
% Reinstall exact handles must preserve COUNT and original queued bytes.
before=ul.securityState();b.installOriginalDRBPair(1,dl,ul,connection);
assert(isequaln(before,ul.securityState())&&b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39);
[other,oi]=owner('UL');other.admitIssuedReconfiguration(oi,20);
mustThrow(@()b.validateOriginalDRBBankAvailable(1,dl,other),'sixgr:protocol:DRBAlreadyInstalled');
mustThrow(@()b.installOriginalDRBPair(1,dl,other,connection),'sixgr:protocol:DRBAlreadyInstalled');
assert(isequaln(before,ul.securityState())&&b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39);
assert(~b.endpointAdmitted(1,'DL','TX'));
dl.admitReceivedReconfigurationComplete(dc,50);assert(b.endpointAdmitted(1,'DL','TX'));
mustThrow(@()b.maximumPayloadBytes(160,0),'sixgr:protocol:OriginalDRBQueuedPathRequired');
% Real queued original segments use the installed handles and exact codecs.
ids=strings(0,1);wires={};counts=[];
while b.pendingTransmitBytes(1,'UL').TotalBSRBytes>0
 k=numel(wires)+1;id="original-drb-tb-"+k;
 [wire,e]=b.prepareQueuedSegment(1,'UL',id,160,.051+k*.001,0);
 b.commitPreparedTransportBlock(id,.051+k*.001);
 ids(k,1)=id;wires{k}=wire;counts(k,1)=e.PayloadBits/8; %#ok<AGROW>
end
for k=1:numel(wires),b.deliverDecoded(ids(k),wires{k},.1+k*.001);end
[bytes,sha]=b.reassembleDecodedApplication(ids,counts);
assert(isequal(bytes,uint8(1:35))&&sha==sixgr.protocol.ProtocolHash.bytes(uint8(1:35)));
assert(ul.pendingTransmitBytes().TotalBSRBytes==0);
% The received bearer owns its ARQ configuration. An absent/false old YAML
% field must not hide a real receiver-triggered STATUS in the reverse queue.
statusBridge=sixgr.protocol.WaveformProtocolBridge(c,1);
[su,si,sr]=owner('UL',true);[sd,di,dr,dc]=owner('DL',true);
su.admitIssuedReconfiguration(si,20);sd.admitIssuedReconfiguration(di,20);
statusBridge.installOriginalDRBPair(1,sd,su,connectionOf(si));
su.admitReceivedReconfiguration(sr,30);sd.admitReceivedReconfiguration(dr,30);
sd.admitReceivedReconfigurationComplete(dc,50);
statusBridge.enqueuePacket(1,'DL','polled-original',uint8(1:5),.051);
[wire,~]=statusBridge.prepareQueuedSegment(1,'DL','polled-TB',160,.052,0);
statusBridge.commitPreparedTransportBlock('polled-TB',.052);
statusBridge.deliverDecoded('polled-TB',wire,.053);
assert(sd.pendingReverseStatusBytes()>0&& ...
    statusBridge.pendingReverseStatusBytes(1,'UL')==sd.pendingReverseStatusBytes());
fprintf('ORIGINAL_DRB_BRIDGE_PASS original_codec_bytes=1 PHY_claim=0\n');ok=true;
end
function c=connectionOf(r)
names={'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch','ClockEpoch','SampleRateHz','ConnectionReceiptSHA256'};
c=struct();for k=1:numel(names),c.(names{k})=r.(names{k});end
end
function [runtime,i,r,c,cfg]=owner(direction,arq)
if nargin<2,arq=false;end
cfg=struct('UEID',"stable-ue-A",'BearerID',"DRB-1",'BearerType',"DRB", ...
    'Direction',string(direction),'DRBID',1,'LCID',4,'QFI',9,'PduSessionID',1, ...
    'ConfigurationEpoch',7,'SampleRateHz',1000,'ClockEpoch',2, ...
    'PDCPSNBits',18,'RLCSNBits',18,'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0", ...
    'ReorderingTime_s',.05);
if arq
    cfg.RLCARQEnabled=true;cfg.RLCPollRetransmit_s=.045;
    cfg.RLCReassembly_s=.005;cfg.RLCStatusProhibit_s=0;cfg.PollPDU=1;
end
s=scope(direction);s.SampleRateHz=cfg.SampleRateHz;
s.ProtocolConfigurationSHA256=sixgr.l2.mac.MACHash.of(orderfields(cfg));
cfg.EndpointAdmissionMode="original_reconfiguration_required";cfg.EndpointAdmissionScope=s;
runtime=sixgr.protocol.ProtocolRuntime(cfg);i=txReceipt(s);r=rxReceipt(s,i,false);c=rxReceipt(s,i,true);
end
function s=uiScope(r)
names={'ExecutionRunID','UEID','BearerID','ServingCell','RNTI','DRBID','LCID','Direction', ...
    'ConfigurationEpoch','ClockEpoch','SampleRateHz','ProtocolConfigurationSHA256'};
s=struct();for k=1:numel(names),s.(names{k})=r.(names{k});end
end
function s=scope(direction)
s=struct('ExecutionRunID',"component-run",'UEID',"stable-ue-A",'BearerID',"DRB-1", ...
    'ServingCell',1,'RNTI',4660,'DRBID',1,'LCID',4,'Direction',string(direction), ...
    'ConfigurationEpoch',7,'ClockEpoch',2,'SampleRateHz',30720000, ...
    'ProtocolConfigurationSHA256',hash('original-protocol'));
end
function r=txReceipt(s)
r=s;r.ContractVersion="issued_NR_DRB_reconfiguration/v1";r.RRCTransactionID=1;
r.RRCReconfigurationSHA256=hash('original-reconfiguration');r.ConnectionReceiptSHA256=hash('original-connection');
r.TransmitComponentID="original-tx";r.TransmitEnqueueReceiptSHA256=hash('enqueue');
r.OriginalComponentSampleSHA256=hash('samples');r.TransmitObservationSHA256=hash('tx-observation');
r.PhysicalTransmissionReceiptSHA256=hash('physical-tx-receipt');
r.ProtectedPDCPPDUSHA256=hash('protected-downlink-reconfiguration');
r.SecurityContextID="original-DL-security-context";r.IntegrityProtected=true;
r.TransmitStartSample=10;r.TransmitEndSampleExclusive=18;r.IssuedAtSample=20;
r.EvidenceBoundary="declared_component_receipt_not_physical_proof";r=seal(r);
end
function r=rxReceipt(s,i,isComplete)
r=s;r.ContractVersion="received_NR_DRB_reconfiguration/v1";
r.RRCTransactionID=i.RRCTransactionID;r.RRCReconfigurationSHA256=i.RRCReconfigurationSHA256;
r.ConnectionReceiptSHA256=i.ConnectionReceiptSHA256;r.IssuedReconfigurationReceiptSHA256=i.SHA256;
r.ReceiverObservationID="UE-original-reconfiguration";r.ReceiverObservationSHA256=hash('rx-observation');
r.ReceivedMACPayloadSHA256=hash('actual-decoded-MAC');r.ProtectedPDCPPDUSHA256=i.ProtectedPDCPPDUSHA256;
r.SecurityContextID="original-DL-security-context";r.IntegrityVerified=true;
r.ObservationStartSample=9;r.ObservationEndSampleExclusive=25;r.AvailableAtSample=30;
if isComplete
    r.ContractVersion="received_NR_DRB_reconfiguration_complete/v1";
    r.RRCReconfigurationCompleteSHA256=hash('original-complete');
    r.ReceiverObservationID="gNB-original-complete";r.ProtectedPDCPPDUSHA256=hash('protected-uplink-complete');
    r.SecurityContextID="original-UL-security-context";
    r.ObservationStartSample=35;r.ObservationEndSampleExclusive=45;r.AvailableAtSample=50;
end
r.EvidenceBoundary="declared_component_receipt_not_physical_proof";r=seal(r);
end
function r=seal(r)
if isfield(r,'SHA256'),r=rmfield(r,'SHA256');end
r.SHA256=sixgr.l2.mac.MACHash.of(r);
end
function h=hash(x)
h=string(sixgr.util.sha256Hex(char(x)));
end
function mustThrow(f,id)
try,f();catch ex,assert(strcmp(ex.identifier,id),'Unexpected %s (expected %s).',ex.identifier,id);return;end
error('test:ExpectedError','Expected %s.',id);
end
