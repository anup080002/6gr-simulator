function ok=testDRBEndpointAdmission()
% Authored typed receipts at a component boundary, NOT actual PHY/PDCP proof.
% Physical adapters must independently validate their original private owners.
setup6GRSimToolkit('Verbose',false);
for direction=["UL","DL"]
    s=scope(direction);a=sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required');
    issued=txReceipt(s);received=rxReceipt(s,issued,false);complete=rxReceipt(s,issued,true);
    mustThrow(@()a.require('TX'),'sixgr:protocol:DRBEndpointNotAdmitted');
    mustThrow(@()a.require('RX'),'sixgr:protocol:DRBEndpointNotAdmitted');
    mustThrow(@()a.admitComplete(complete,50),'sixgr:protocol:DRBIssuedReconfigurationRequired');
    a=a.admitIssued(issued,20);
    assert(a.RXEnabled==(direction=="UL")&&~a.TXEnabled);
    assert(isequaln(a,a.admitIssued(issued,20)));
    snapshot=a;beforeRejected=[a.TXEnabled,a.RXEnabled,a.LastSample];beforeIssued=a.IssuedReceipt;
    % Independent gNB knowledge: Complete can be received while the simulator
    % has not recorded any UE-local ReceivedReceipt on this value owner.
    a=a.admitComplete(complete,50);
    assert(isempty(fieldnames(a.ReceivedReceipt))&&a.TXEnabled==(direction=="DL")&&a.RXEnabled==(direction=="UL"));
    assert(isequaln(a,a.admitComplete(complete,50)));
    a=a.admitReceived(received,51);
    assert(a.TXEnabled&&a.RXEnabled);a.require('TX');a.require('RX');
    assert(isequaln(a,a.admitReceived(received,51)));
    % The other legal processing order: UE receives first; gNB DL waits for
    % its own Complete, not simulator-private UE activation knowledge.
    other=snapshot.admitReceived(received,30);
    assert(other.TXEnabled==(direction=="UL")&&other.RXEnabled);
    other=other.admitComplete(complete,50);assert(other.TXEnabled&&other.RXEnabled);
    late=snapshot.admitComplete(complete,1000);
    assert(late.LastSample==1000&&isempty(fieldnames(late.ReceivedReceipt)));
    mustThrow(@()late.admitReceived(received,999),'sixgr:protocol:DRBAdmissionClock');
    bad=complete;bad.RRCTransactionID=3;bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionConflict');
    bad=complete;bad.RRCReconfigurationSHA256=hash('other-config-message');bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionConflict');
    bad=complete;bad.ConnectionReceiptSHA256=hash('other-connection');bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionConflict');
    for name=["ExecutionRunID","UEID","BearerID","Direction"]
        bad=complete;bad.(name)="foreign";bad=seal(bad);
        mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionScope');
    end
    for name=["ServingCell","RNTI","DRBID","LCID","ConfigurationEpoch","ClockEpoch","SampleRateHz"]
        bad=complete;bad.(name)=bad.(name)+1;bad=seal(bad);
        mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionScope');
    end
    bad=complete;bad.ProtocolConfigurationSHA256=hash('other-protocol');bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionScope');
    bad=complete;bad.AvailableAtSample=51;bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionClock');
    bad=complete;bad.ObservationStartSample=19;bad.ObservationEndSampleExclusive=19;bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionClock');
    bad=complete;bad.IntegrityVerified=false;bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionProtection');
    bad=complete;bad.IntegrityVerified=1;bad=seal(bad);
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionProtection');
    bad=complete;bad.SHA256=hash('changed-digest');
    mustThrow(@()snapshot.admitComplete(bad,50),'sixgr:protocol:DRBAdmissionDigest');
    bad=received;bad.ProtectedPDCPPDUSHA256=hash('different-transmitted-PDCP');bad=seal(bad);
    mustThrow(@()snapshot.admitReceived(bad,30),'sixgr:protocol:DRBAdmissionConflict');
    % Same scope/transaction but a different observation cannot replace the
    % original admitted result. It must not silently refresh admission.
    bad=complete;bad.ReceiverObservationID="different-observation";bad=seal(bad);
    mustThrow(@()a.admitComplete(bad,52),'sixgr:protocol:DRBAdmissionConflict');
    bad=issued;bad.TransmitComponentID="different-TX";bad=seal(bad);
    mustThrow(@()a.admitIssued(bad,52),'sixgr:protocol:DRBAdmissionConflict');
    assert(isequal([snapshot.TXEnabled,snapshot.RXEnabled,snapshot.LastSample],beforeRejected)&& ...
        isequaln(snapshot.IssuedReceipt,beforeIssued)&&isempty(fieldnames(snapshot.CompleteReceipt)));
end
for rnti=[1 65522]
    s=scope('UL');s.RNTI=rnti;sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required');
end
for rnti=[0 65523 65535]
    s=scope('UL');s.RNTI=rnti;
    mustThrow(@()sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required'),'sixgr:protocol:DRBAdmissionScope');
end
for name=["DRBID","LCID"]
    s=scope('UL');s.(name)=33;
    mustThrow(@()sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required'),'sixgr:protocol:DRBAdmissionScope');
end
s=scope('UL');s.LCID=3;
mustThrow(@()sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required'),'sixgr:protocol:DRBAdmissionScope');
s=scope('UL');s.DRBID=0;
mustThrow(@()sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required'),'sixgr:protocol:DRBAdmissionScope');
s=scope('UL');s.DRBID=32;s.LCID=32;
sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required');
s=scope('UL');s.UEID=1;
mustThrow(@()sixgr.protocol.DRBEndpointAdmission(s,'original_reconfiguration_required'),'sixgr:protocol:DRBAdmissionScope');
fprintf('DRB_ENDPOINT_ADMISSION_PASS declared_receipts=1 actual_PHY_claim=0 independent_gNB_complete=1\n');
ok=true;
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
