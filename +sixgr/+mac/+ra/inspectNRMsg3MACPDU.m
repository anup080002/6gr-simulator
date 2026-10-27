function disposition=inspectNRMsg3MACPDU(bytes)
% Original decoded TB semantics, independent of CRC.
bytes=sixgr.l2.mac.requireMACOctets(bytes);
disposition=struct('Accepted',false,'Status',"not_inspected", ...
    'OriginalMACBytes',bytes,'OriginalMACSHA256',string(sixgr.l2.mac.MACHash.of(bytes)), ...
    'ErrorIdentifier',"",'ErrorMessage',"",'MAC',struct(),'RRC',struct(),'Message',struct());
try
    mac=sixgr.l2.mac.MACPDUDemultiplexer.decode("UL",bytes);
catch problem
    % These arise only from received subheader/length fields after octet and
    % direction validation. The registry is bounded, so do not call every
    % unsupported LCID invalid NR. Never catch external-codec or other bugs.
    if ~any(string(problem.identifier)==["sixgr:mac:ReservedLCID", ...
            "sixgr:mac:MACPDULengthOverrun","sixgr:mac:TruncatedMACPDU", ...
            "sixgr:mac:ZeroLengthLogicalChannelSDU"])
        rethrow(problem);
    end
    disposition.Status="received_MAC_outside_supported_schema_or_extent";
    disposition.ErrorIdentifier=string(problem.identifier);disposition.ErrorMessage=string(problem.message);
    return;
end
disposition.MAC=mac;rows=mac.SubPDUs;
if numel(rows)~=1 || rows.LCID~=52 || rows.PayloadLength~=6
    disposition.Status="received_MAC_outside_UL_CCCH48_profile";
    disposition.ErrorIdentifier="sixgr:mac:ra:UnsupportedNRMsg3MAC";
    disposition.ErrorMessage="The supported initial Msg3 profile requires one original UL-CCCH48 SDU.";
    return;
end
rrc=sixgr.rrc.asn1.NRAccessMessageCodec.inspectReceived("setup_request",rows.Payload);
disposition.RRC=rrc;
if ~rrc.Accepted
    disposition.Status=rrc.Status;disposition.ErrorIdentifier=rrc.RejectionClass;
    disposition.ErrorMessage=rrc.RejectionMessage;return;
end
% Reuse the original canonical successful semantic representation; decoding
% is bounded codec work only, not another RF or PUSCH execution.
message=sixgr.mac.ra.parseNRInitialAccessMACPDU("UL",bytes);
assert(isequaln(message.RRCCodecEvidence,rrc.Decoded), ...
    'sixgr:mac:ra:ReceivedMsg3SemanticChanged','Original received bytes must produce the same supported semantics.');
disposition.Message=message;disposition.Accepted=true;
disposition.Status="received_UL_CCCH48_and_supported_RRCSetupRequest";
end
