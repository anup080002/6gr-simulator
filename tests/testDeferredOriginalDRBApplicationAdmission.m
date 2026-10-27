function ok=testDeferredOriginalDRBApplicationAdmission()
% Declared shared sample owner and authored endpoint receipts; no RF claim.
setup6GRSimToolkit('Verbose',false);
c=struct('enabled',true,'strict',true,'mac',struct('bearer_configuration_authority',"original_received_RRC"));
b=sixgr.protocol.WaveformProtocolBridge(c,1);
[ul,ui,ur]=owner('UL');[dl,di,dr,dc]=owner('DL');
seed=17;bytes=sixgr.protocol.applicationPayloadBytes(seed,"offered-1","UL",1,0,35);
T=table("application-1","offered-1",1,"UL",.005,280, ...
 sixgr.protocol.ProtocolHash.bytes(bytes),"","",NaN, ...
 'VariableNames',{'ApplicationPacketId','PacketId','UEIndex','Direction','EnqueueTime_s','OfferedBits', ...
 'OriginalApplicationPayloadSHA256','ProtocolUEID','ProtocolBearerID','ProtocolConfigurationEpoch'});
T.QFI=9;T.PduSessionID=1;
state=struct('ProtocolWaveformEnabled',true,'ProtocolBridge',b,'PacketDeliveryLedgerTable',T, ...
 'ProtocolPayloadSeed',seed,'SharedWaveformStream',struct('Events',struct('NextSampleIndex',10),'SampleRateHz',1000,'Physical',struct('ConfigurationEpoch',2)));
state=sixgr.truth.enqueueProtocolApplicationPackets(state,struct());
assert(isnan(state.PacketDeliveryLedgerTable.ProtocolAdmissionTime_s)&&isempty(state.ProtocolEnqueuedApplicationIDs));
assert(~b.hasInstalledRuntime(1)&&b.pendingTransmitBytes(1,'UL').TotalBSRBytes==0);
ul.admitIssuedReconfiguration(ui,20);dl.admitIssuedReconfiguration(di,20);
names={'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch','ClockEpoch','SampleRateHz','ConnectionReceiptSHA256'};
connection=struct();for k=1:numel(names),connection.(names{k})=ui.(names{k});end
b.installOriginalDRBPair(1,dl,ul,connection);
state.SharedWaveformStream.Events.NextSampleIndex=25;
state=sixgr.truth.enqueueProtocolApplicationPackets(state,struct());
assert(isnan(state.PacketDeliveryLedgerTable.ProtocolAdmissionTime_s)&&isempty(state.ProtocolEnqueuedApplicationIDs));
ul.admitReceivedReconfiguration(ur,30);dl.admitReceivedReconfiguration(dr,30);
state.SharedWaveformStream.Events.NextSampleIndex=35;
% Malformed or foreign execution clock must not consume an offered packet.
for fault=1:3
 bad=state;
 if fault==1,bad.SharedWaveformStream.SampleRateHz=2000;
 elseif fault==2,bad.SharedWaveformStream.Physical.ConfigurationEpoch=3;
 else,bad.SharedWaveformStream.Events.NextSampleIndex=35.5;end
 before=ul.securityState();volume=ul.pendingTransmitBytes();
 threw=false;try,sixgr.truth.enqueueProtocolApplicationPackets(bad,struct());catch,threw=true;end
 assert(threw&&isequaln(before,ul.securityState())&&isequaln(volume,ul.pendingTransmitBytes()));
 assert(isnan(state.PacketDeliveryLedgerTable.ProtocolAdmissionTime_s));
end
for fault=1:2
    bad=state;
    if fault==1,bad.PacketDeliveryLedgerTable.QFI=8;
    else,bad.PacketDeliveryLedgerTable.PduSessionID=2;end
    before=ul.securityState();volume=ul.pendingTransmitBytes();
    threw=false;
    try,sixgr.truth.enqueueProtocolApplicationPackets(bad,struct());
    catch e,threw=strcmp(e.identifier,'sixgr:protocol:ApplicationBearerMapping');end
    assert(threw&&isequaln(before,ul.securityState())&&isequaln(volume,ul.pendingTransmitBytes()));
end
state=sixgr.truth.enqueueProtocolApplicationPackets(state,struct());
a=state.PacketDeliveryLedgerTable;
assert(a.EnqueueTime_s==.005&&a.OfferedBits==280&&a.OriginalApplicationPayloadSHA256==T.OriginalApplicationPayloadSHA256);
assert(a.ProtocolAdmissionTime_s==.035&&a.ProtocolAdmissionSource=="original_DRB_endpoint_admitted_at_shared_sample");
assert(a.ProtocolUEID==ui.UEID&&a.ProtocolBearerID==ui.BearerID&&a.ProtocolConfigurationEpoch==7);
assert(isequal(state.ProtocolEnqueuedApplicationIDs,"application-1"));
[pdu,token]=ul.previewSegment(100,.036);
assert(pdu.EnqueueTime_s==.035&&pdu.PacketID=="application-1"&&pdu.PacketSHA256==T.OriginalApplicationPayloadSHA256);
ul.cancelPreparedSegment(token);
before=ul.securityState();volume=ul.pendingTransmitBytes();
state.SharedWaveformStream.Events.NextSampleIndex=40;
state=sixgr.truth.enqueueProtocolApplicationPackets(state,struct());
assert(isequaln(before,ul.securityState())&&isequaln(volume,ul.pendingTransmitBytes()));
assert(state.PacketDeliveryLedgerTable.ProtocolAdmissionTime_s==.035);
fprintf('DEFERRED_DRB_APPLICATION_PASS original_arrival_preserved=1 actual_L2_sample=35 PHY_claim=0\n');ok=true;
end
function [runtime,i,r,c,cfg]=owner(direction)
cfg=struct('UEID',"stable-ue-A",'BearerID',"DRB-1",'BearerType',"DRB", ...
    'Direction',string(direction),'DRBID',1,'LCID',4,'QFI',9,'PduSessionID',1, ...
    'ConfigurationEpoch',7,'SampleRateHz',1000,'ClockEpoch',2, ...
    'PDCPSNBits',18,'RLCSNBits',18,'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0", ...
    'ReorderingTime_s',.05);
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
