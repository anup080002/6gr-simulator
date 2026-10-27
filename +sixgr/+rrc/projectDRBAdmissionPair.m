function receipts=projectDRBAdmissionPair(capsule,original,kind)
% Projection ONLY. Production callers must validate both private owners first.
id='sixgr:rrc:DRBOriginalAdmission';kind=string(kind);
assert(isscalar(kind)&&any(kind==["issued","received","complete"]),id,'Unknown original boundary.');
if kind=="issued"
    contract="issued_NR_DRB_reconfiguration/v1";
    fields=["TransmitComponentID","TransmitEnqueueReceiptSHA256","OriginalComponentSampleSHA256", ...
        "TransmitObservationSHA256","PhysicalTransmissionReceiptSHA256","ProtectedPDCPPDUSHA256", ...
        "SecurityContextID","IntegrityProtected","TransmitStartSample","TransmitEndSampleExclusive","IssuedAtSample"];
else
    if kind=="received",contract="received_NR_DRB_reconfiguration/v1";
    else,contract="received_NR_DRB_reconfiguration_complete/v1";end
    fields=["ReceiverObservationID","ReceiverObservationSHA256","ReceivedMACPayloadSHA256", ...
        "ProtectedPDCPPDUSHA256","SecurityContextID","IntegrityVerified", ...
        "ObservationStartSample","ObservationEndSampleExclusive","AvailableAtSample"];
end
assert(isstruct(original)&&isscalar(original)&&all(isfield(original,fields)),id,'Missing actual original transport operands.');
receipts=cell(1,2);directions=["DL","UL"];
for k=1:2
    r=capsule.directionalScope(directions(k));
    r.ContractVersion=contract;
    r.RRCTransactionID=capsule.OriginalMessage.Semantic.transaction_id;
    r.RRCReconfigurationSHA256=capsule.OriginalMessage.SHA256;
    r.ConnectionReceiptSHA256=capsule.Connection.ConnectionReceiptSHA256;
    for name=fields,r.(name)=original.(name);end
    if isfield(original,'EvidenceBoundary'),r.EvidenceBoundary=original.EvidenceBoundary;end
    if kind~="issued"
        issued=capsule.originalIssuedReceipt(directions(k));
        r.IssuedReconfigurationReceiptSHA256=issued.SHA256;
    end
    if kind=="complete",r.RRCReconfigurationCompleteSHA256=sixgr.protocol.ProtocolHash.bytes(original.Payload);end
    r.SHA256=sixgr.l2.mac.MACHash.of(r);receipts{k}=r;
end
end
