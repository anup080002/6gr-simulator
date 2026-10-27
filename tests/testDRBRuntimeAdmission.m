function ok=testDRBRuntimeAdmission()
% Actual Runtime codecs with authored admission receipts at component boundary.
% No emitted/captured radio or real protected RRC delivery is claimed here.
setup6GRSimToolkit('Verbose',false);
[ul,ui,ur,uc,ulCfg]=owner('UL');[dl,di,dr,dc]=owner('DL'); %#ok<ASGLU>
initialUL=ul.securityState();initialDL=dl.securityState();
mustThrow(@()ul.transmit('blocked',uint8([1 2]),.01),'sixgr:protocol:DRBEndpointNotAdmitted');
mustThrow(@()dl.transmit('blocked',uint8([1 2]),.01),'sixgr:protocol:DRBEndpointNotAdmitted');
mustThrow(@()ul.receive(struct(),.01),'sixgr:protocol:DRBEndpointNotAdmitted');
mustThrow(@()dl.receive(struct(),.01),'sixgr:protocol:DRBEndpointNotAdmitted');
assert(isequaln(initialUL,ul.securityState())&&isequaln(initialDL,dl.securityState()));
% Failed second peer preflight must leave BOTH original Runtime handles off.
u0=ul.endpointAdmissionState();d0=dl.endpointAdmissionState();
bad=di;bad.RNTI=di.RNTI+1;bad=seal(bad);
mustThrow(@()pairIssued(ul,dl,ui,bad,20),'sixgr:protocol:DRBAdmissionScope');
assert(isequaln(u0,ul.endpointAdmissionState())&&isequaln(d0,dl.endpointAdmissionState())&& ...
    isequaln(initialUL,ul.securityState())&&isequaln(initialDL,dl.securityState()));
pairIssued(ul,dl,ui,di,20);
u=ul.endpointAdmissionState();v=dl.endpointAdmissionState();
assert(u.RXEnabled&&~u.TXEnabled&&~v.RXEnabled&&~v.TXEnabled);
assert(isequaln(ul.endpointAdmissionScope(),uiScope(ui)));
mustThrow(@()ul.transmit('still-blocked',uint8(3),.021),'sixgr:protocol:DRBEndpointNotAdmitted');
% A separately labeled component transmitter provides original encoded bytes
% for the issued-gNB UL RX endpoint; it is not evidence UE learned config.
donorCfg=rmfield(ulCfg,{'EndpointAdmissionMode','EndpointAdmissionScope'});
donor=sixgr.protocol.ProtocolRuntime(donorCfg);
pdu=donor.transmit('component-UL-observation',uint8([9 8 7]),0);
[delivered,rows]=ul.receive(pdu,.021);
assert(delivered&&isscalar(rows)&&isequal(rows.Payload,uint8([9 8 7])));
% The original receiver event advanced the runtime clock; admission cannot
% backdate it even when the value-class LastSample remains20.
mustThrow(@()ul.validateReceivedReconfiguration(ur,20),'sixgr:protocol:DRBAdmissionClock');
beforeUL=ul.endpointAdmissionState();beforeDL=dl.endpointAdmissionState();
bad=dr;bad.ProtocolConfigurationSHA256=hash('wrong-config');bad=seal(bad);
mustThrow(@()pairReceived(ul,dl,ur,bad,30),'sixgr:protocol:DRBAdmissionScope');
assert(isequaln(beforeUL,ul.endpointAdmissionState())&&isequaln(beforeDL,dl.endpointAdmissionState()));
pairReceived(ul,dl,ur,dr,30);
u=ul.endpointAdmissionState();v=dl.endpointAdmissionState();
assert(u.TXEnabled&&u.RXEnabled&&v.RXEnabled&&~v.TXEnabled);
ul.transmit('now-authorized-UL',uint8([4 5]),.031);
mustThrow(@()dl.transmit('DL-before-complete',uint8(4),.031),'sixgr:protocol:DRBEndpointNotAdmitted');
securityBefore=dl.securityState();
bad=dc;bad.RRCTransactionID=3;bad=seal(bad);
mustThrow(@()dl.admitReceivedReconfigurationComplete(bad,50),'sixgr:protocol:DRBAdmissionConflict');
assert(isequaln(securityBefore,dl.securityState()));
dl.admitReceivedReconfigurationComplete(dc,50);
pdu=dl.transmit('original-DL',uint8([11 12 13 14]),.051);
[delivered,rows]=dl.receive(pdu,.052);
assert(delivered&&isscalar(rows)&&isequal(rows.Payload,uint8([11 12 13 14])));
% Independent gNB-only event order: no UE admission method is called.
[g,gi,~,gc]=owner('DL');g.admitIssuedReconfiguration(gi,20);
g.admitReceivedReconfigurationComplete(gc,50);q=g.endpointAdmissionState();
assert(q.TXEnabled&&~q.RXEnabled);
g.transmit('gNB-independent-complete',uint8([21 22]),.051);
mustThrow(@()g.receive(struct(),.052),'sixgr:protocol:DRBEndpointNotAdmitted');
% Delayed Complete is lawful only on the unchanged original generation.
[late,li,~,lc]=owner('DL');late.admitIssuedReconfiguration(li,20);
late.admitReceivedReconfigurationComplete(lc,500);q=late.endpointAdmissionState();assert(q.TXEnabled&&~q.RXEnabled);
[foreign,fi,~,fc]=owner('DL');foreign.admitIssuedReconfiguration(fi,20);
fc.ConfigurationEpoch=fc.ConfigurationEpoch+1;fc=seal(fc);
mustThrow(@()foreign.admitReceivedReconfigurationComplete(fc,500),'sixgr:protocol:DRBAdmissionScope');
q=foreign.endpointAdmissionState();assert(~q.TXEnabled&&~q.RXEnabled);
% Constructor binds the exact original protocol configuration, not a caller's
% copied configuration hash from a different runtime.
badCfg=ulCfg;badCfg.RLCSNBits=12;
mustThrow(@()sixgr.protocol.ProtocolRuntime(badCfg),'sixgr:protocol:DRBAdmissionScope');
fprintf('DRB_RUNTIME_ADMISSION_PASS paired_preflight_atomic=1 original_codec_bytes=1 PHY_claim=0\n');
ok=true;
end
function pairIssued(ul,dl,u,d,t)
ul.validateIssuedReconfiguration(u,t);dl.validateIssuedReconfiguration(d,t);
ul.admitIssuedReconfiguration(u,t);dl.admitIssuedReconfiguration(d,t);
end
function pairReceived(ul,dl,u,d,t)
ul.validateReceivedReconfiguration(u,t);dl.validateReceivedReconfiguration(d,t);
ul.admitReceivedReconfiguration(u,t);dl.admitReceivedReconfiguration(d,t);
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
