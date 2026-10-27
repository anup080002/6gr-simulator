function ok=testSRB1EndpointAdmission()
% Declared receipt fixtures exercise the gate, not physical acquisition.
h=string(repmat('a',1,64));
scope=struct('ExecutionRunID',"run-A",'UEID',"connection-A",'ServingCell',1, ...
    'RNTI',42,'SRBID',1,'LCID',1,'Direction',"UL",'ConfigurationEpoch',1, ...
    'ClockEpoch',1,'SampleRateHz',1000,'ProtocolConfigurationSHA256',h);
for name=["SampleRateHz","ClockEpoch","ConfigurationEpoch","ServingCell","RNTI"]
    bad=scope;bad.(name)=NaN;
    reject(@()sixgr.protocol.SRB1EndpointAdmission(bad,"original_setup_required"));
end
for name=["ExecutionRunID","UEID","ProtocolConfigurationSHA256"]
    bad=scope;bad.(name)="";
    reject(@()sixgr.protocol.SRB1EndpointAdmission(bad,"original_setup_required"));
end
bad=scope;bad.RNTI=65535;
reject(@()sixgr.protocol.SRB1EndpointAdmission(bad,"original_setup_required"));
owner=sixgr.protocol.SRB1EndpointAdmission(scope,"original_setup_required");
reject(@()owner.require('RX'));reject(@()owner.require('TX'));
r=scope;r.ContractVersion="issued_NR_SRB1_setup/v1";r.RRCTransactionID=0;
r.RRCSetupSHA256=h;r.TransmitComponentID="actual-component-fixture";
for name=["TransmitEnqueueReceiptSHA256","OriginalComponentSampleSHA256", ...
        "TransmitObservationSHA256","PhysicalTransmissionReceiptSHA256"]
    r.(name)=h;
end
r.TransmitStartSample=10;r.TransmitEndSampleExclusive=20;r.IssuedAtSample=20;r=seal(r);
reject(@()owner.admitIssued(r,19));
issued=owner.admitIssued(r,20);issued.require('RX');reject(@()issued.require('TX'));
assert(isequaln(issued.admitIssued(r,20),issued));
q=scope;q.ContractVersion="received_NR_SRB1_setup/v1";q.RRCTransactionID=0;
q.RRCSetupSHA256=h;q.IssuedSetupReceiptSHA256=r.SHA256;q.ReceiverObservationID="original-rx-fixture";
for name=["ReceiverObservationSHA256","ReceivedMACPayloadSHA256", ...
        "OriginalRARObservationSHA256","OriginalContentionObservationSHA256"]
    q.(name)=h;
end
q.ObservationStartSample=11;q.ObservationEndSampleExclusive=22;q.AvailableAtSample=23;q=seal(q);
reject(@()owner.admitReceived(q,23));reject(@()issued.admitReceived(q,22));
for name=["ExecutionRunID","UEID","ProtocolConfigurationSHA256"]
    wrong=q;wrong.(name)="wrong";wrong=seal(wrong);reject(@()issued.admitReceived(wrong,23));
end
for name=["ServingCell","RNTI","ConfigurationEpoch","ClockEpoch","SampleRateHz"]
    wrong=q;wrong.(name)=wrong.(name)+1;wrong=seal(wrong);reject(@()issued.admitReceived(wrong,23));
end
active=issued.admitReceived(q,23);active.require('TX');active.require('RX');
assert(isequaln(active.admitReceived(q,23),active));
wrong=q;wrong.ReceiverObservationID="replacement";wrong=seal(wrong);
reject(@()active.admitReceived(wrong,24));
wrong=q;wrong.SHA256=h;reject(@()issued.admitReceived(wrong,23));
component=sixgr.protocol.SRB1EndpointAdmission(struct(),"component_preconfigured_both");
component.require('RX');component.require('TX');reject(@()component.admitIssued(r,20));
% The isolated value owner contains no PDCP/RLC state to reset. Runtime
% integration must separately prove live entity/counter preservation.
assert(~owner.RXEnabled&&~owner.TXEnabled&&issued.RXEnabled&&~issued.TXEnabled);
ok=true;
end
function r=seal(r)
if isfield(r,'SHA256'),r=rmfield(r,'SHA256');end
r.SHA256=sixgr.l2.mac.MACHash.of(r);
end
function reject(f)
try,f();catch e
    assert(startsWith(string(e.identifier),'sixgr:protocol:SRB1'));return;
end
error('test:SRB1AdmissionAcceptedInvalid','Expected typed admission rejection.');
end
