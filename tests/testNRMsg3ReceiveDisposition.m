function ok=testNRMsg3ReceiveDisposition()
% Actual native coded PUSCH, explicit unit-channel capture (no shared RF).
% CRC and supported MAC/RRC semantics remain separate receiver outcomes.
cfg=raStrictAnchorConfig();ra=sixgr.mac.ra.RAConfig(cfg);
ra.RRCEncodingProfile="nr_rrc_access_base_srb1_uper_v1";
grant=sixgr.mac.ra.buildRARULGrant(ra);
original=sixgr.mac.ra.buildNRMsg3Payload("randomValue",2^38+7,"mo-Signalling");
for valid=[true false]
    msg=original;
    if ~valid
        msg.MACSubPDUs=struct('LCID',1,'Payload',uint8([1 2 3]),'OwnerID',"declared_unsupported_Msg3_LCID");
    end
    tx=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,grant,msg);
    rx=sixgr.phy.ra.receiveMsg3PUSCHPhysical(tx.Waveform,cfg,ra,grant);
    assert(rx.Ok,'Original unit-channel coded PUSCH must actually decode; do not author CRC.');
    bits=rx.TransportBlock;
    bytes=uint8(reshape(double(bits),8,[]).'*(2.^(7:-1:0)).');
    inspected=sixgr.mac.ra.inspectNRMsg3MACPDU(bytes);
    assert(inspected.Accepted==valid && ...
        inspected.OriginalMACSHA256==string(sixgr.l2.mac.MACHash.of(bytes)));
    if valid
        assert(inspected.Message.ContentionIdentity==original.ContentionIdentity && ...
            inspected.Message.RRCSetupRequest.identity_value==2^38+7);
    else
        assert(inspected.Status=="received_MAC_outside_UL_CCCH48_profile" && ...
            isempty(fieldnames(inspected.Message)));
    end
end
malformed=sixgr.mac.ra.inspectNRMsg3MACPDU(uint8([52 0]));
assert(~malformed.Accepted && malformed.ErrorIdentifier=="sixgr:mac:MACPDULengthOverrun");
unsupported=sixgr.mac.ra.inspectNRMsg3MACPDU(uint8(33));
assert(~unsupported.Accepted&&unsupported.ErrorIdentifier=="sixgr:mac:ReservedLCID");
truncated=sixgr.rrc.asn1.NRAccessMessageCodec.inspectReceived("setup_request",uint8([0 0]));
assert(~truncated.Accepted&&truncated.Status=="received_UPER_decode_rejected");
ok=true;fprintf('NR_MSG3_RECEIVE_DISPOSITION_PASS actual_native_PUSCH=2 original_CRC1_preserved=2 unsupported_MAC_not_activation=1 sharedRF=0\n');
end
