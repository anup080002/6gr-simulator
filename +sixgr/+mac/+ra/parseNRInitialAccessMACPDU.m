function message=parseNRInitialAccessMACPDU(direction,bytes)
% Parse the complete decoded MAC TB, including its received padding extent.
% Never use a transmitted payload length or intended RNTI to delimit it.
direction=string(direction); bytes=sixgr.l2.mac.requireMACOctets(bytes);
assert(any(direction==["DL","UL"]),'sixgr:mac:ra:InvalidAccessDirection','Specify DL or UL.');
mac=sixgr.l2.mac.MACPDUDemultiplexer.decode(direction,bytes);
rows=mac.SubPDUs;
if direction=="UL"
    assert(numel(rows)==1 && rows.LCID==52 && rows.PayloadLength==6, ...
        'sixgr:mac:ra:UnsupportedNRMsg3MAC','This access profile requires one original UL-CCCH48 SDU.');
    rrc=sixgr.rrc.asn1.NRAccessMessageCodec.decode("setup_request",rows.Payload);
    identity=rrc.Bytes;
    message=struct('RRCSetupRequestPresent',true,'RRCSetupRequest',rrc.Semantic, ...
        'RRCSetupRequestSHA256',rrc.SHA256);
else
    assert(numel(rows)==2 && nnz([rows.LCID]==62)==1 && nnz([rows.LCID]==0)==1, ...
        'sixgr:mac:ra:UnsupportedNRMsg4MAC','Require one original contention CE and one original DL-CCCH SDU.');
    identity=rows([rows.LCID]==62).Payload;
    assert(numel(identity)==6,'sixgr:mac:ra:InvalidNRContentionIdentity','Contention identity is exactly6 octets.');
    rrc=sixgr.rrc.asn1.NRAccessMessageCodec.decode("setup",rows([rows.LCID]==0).Payload);
    message=struct('RRCSetupPresent',true,'FinalCRNTI',NaN, ...
        'RRCSetup',struct('MessageType',"RRCSetup", ...
        'TransactionID',rrc.Semantic.transaction_id,'SRB1LCID',rrc.Semantic.srb1_lcid), ...
        'RRCSetupSHA256',rrc.SHA256);
end
message.PayloadBytes=bytes(:); message.PayloadHex=localHex(bytes);
message.PayloadHash=string(sixgr.l2.mac.MACHash.of(bytes));
message.ContentionIdentityBytes=identity(:); message.ContentionIdentity=localHex(identity);
message.RRCCodecEvidence=rrc; message.MACDecodeEvidence=mac;
message.EncodingProfile="nr_rrc_access_base_srb1_uper_v1";
message.Valid=true; message.MACRRCStandardsQualified=false;
message.Scope="supported_MAC_and_UPER_decode_not_complete_protocol_qualification";
end
function value=localHex(bytes)
value=upper(string(reshape(dec2hex(bytes,2).',1,[])));
end
