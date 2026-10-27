function message=validateDRBOriginalSRBTransport(actor,srb,original,connection,kind)
% Both actual transport and original protocol private owners are mandatory.
id='sixgr:rrc:DRBOriginalAdmission';kind=string(kind);
assert(isa(srb,'sixgr.protocol.ProtocolRuntime')&&srb.BearerType=="SRB"&&srb.SRBID==1&&srb.LCID==1,id,'Require the original SRB1 Runtime.');
assert(isstruct(original)&&isscalar(original)&&all(isfield(original,{'ContractVersion','Payload'}))&&isa(original.Payload,'uint8')&&isrow(original.Payload)&&~isempty(original.Payload),id,'Require original UPER octets.');
if kind=="issued"
    assert(string(original.ContractVersion)=="original_authenticated_SRB1_transmission/v1",id,'Production requires original authenticated transmission authority.');
    actor.validateOriginalProtectedTransmission(original);
    protocol=original.ProtocolSubmissionReceipt;
    srb.validateOriginalLowerLayerSubmission(protocol);
    assert(string(protocol.ContractVersion)=="original_PDCP_to_RLC_submission/v1"&& ...
        protocol.TXIntegrityActive&&protocol.TXCipheringActive&&srb.Direction=="DL",id,'Require original protected DL submission.');
    decoded=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('SRB',12,protocol.PDCPPDU);
    assert(numel(decoded.Payload)>4&&isequal(decoded.Payload(1:end-4),original.Payload),id,'Original NEA0 PDCP bytes differ from issued UPER.');
    assert(string(original.ProtectedPDCPPDUSHA256)==string(protocol.PDCPPDUSHA256)&& ...
        protocol.SubmittedAtSample<=original.TransmitStartSample&& ...
        original.TransmitStartSample<original.TransmitEndSampleExclusive&& ...
        original.TransmitEndSampleExclusive<=original.IssuedAtSample,id,'Original transmission/support differs.');
    codecKind='reconfiguration';direction="DL";
else
    assert(string(original.ContractVersion)=="original_authenticated_SRB1_delivery/v1",id,'Production requires original authenticated delivery authority.');
    actor.validateOriginalProtectedDelivery(original);
    protocol=original.ProtocolDeliveryReceipt;
    srb.validateOriginalReceivedSRBDelivery(protocol);
    assert(string(protocol.ContractVersion)=="original_PDCP_to_RRC_delivery/v1"&& ...
        protocol.RXIntegrityActive&&protocol.RXCipheringActive&&protocol.IntegrityVerified&& ...
        string(protocol.IntegrityAlgorithm)=="128-NIA2"&& ...
        string(protocol.Source)=="original_RLC_PDCP_receiver_completion",id,'Require original protected SRB completion.');
    assert(isequal(protocol.Payload,original.Payload)&& ...
        string(protocol.RRCPayloadSHA256)==sixgr.protocol.ProtocolHash.bytes(original.Payload)&& ...
        string(original.ProtectedPDCPPDUSHA256)==string(protocol.PDCPPDUSHA256)&& ...
        original.ObservationStartSample<original.ObservationEndSampleExclusive&& ...
        original.ObservationEndSampleExclusive<=protocol.ReceivedAtSample&& ...
        protocol.ReceivedAtSample<=protocol.AvailableAtSample&& ...
        protocol.AvailableAtSample==original.AvailableAtSample,id,'Original capture/protocol delivery binding differs.');
    if kind=="received",codecKind='reconfiguration';direction="DL";
    else
        assert(kind=="complete",id,'Unsupported original receipt kind.');
        codecKind='reconfiguration_complete';direction="UL";
    end
end
assert(srb.Direction==direction&&string(protocol.Direction)==direction&&protocol.LCID==1,id,'Original SRB direction differs.');
for name=["ExecutionRunID","UEID","ServingCell","RNTI","ConfigurationEpoch","SampleRateHz","ClockEpoch"]
    assert(isequaln(original.(name),connection.(name))&&isequaln(protocol.(name),connection.(name)),id,'Original connection scope differs.');
end
message=sixgr.rrc.asn1.NRAccessMessageCodec.decode(codecKind,original.Payload);
end
