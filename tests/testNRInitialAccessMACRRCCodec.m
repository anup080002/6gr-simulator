function ok=testNRInitialAccessMACRRCCodec()
% Actual MAC/UPER wire codecs. PHY and received activation are separate tests.
request=sixgr.mac.ra.buildNRMsg3Payload("randomValue",7,"mo-Signalling");
assert(request.ContentionIdentity=="1000000000E6" && ...
    request.PayloadHex=="341000000000E6" && request.RRCSetupRequestPresent);
mac=sixgr.l2.mac.MACPDUAssembler.assemble("UL",request.MACSubPDUs,80);
received=sixgr.mac.ra.parseNRInitialAccessMACPDU("UL",mac.Bytes);
assert(received.Valid && received.ContentionIdentity==request.ContentionIdentity && ...
    received.MACDecodeEvidence.PaddingBytes==73 && ...
    received.RRCSetupRequest.identity_value==7 && ...
    isequal(received.PayloadBytes,mac.Bytes(:)));
% Contentious identity is the original CCCH, not a numeric UE ordinal.
other=sixgr.mac.ra.buildNRMsg3Payload("randomValue",8,"mo-Signalling");
assert(other.ContentionIdentity~=request.ContentionIdentity);
response=sixgr.mac.ra.buildNRMsg4ContentionResolution(received.ContentionIdentityBytes,2);
assert(response.RRCCodecEvidence.Hex=="3040002200040000" && isnan(response.FinalCRNTI));
mac=sixgr.l2.mac.MACPDUAssembler.assemble("DL",response.MACSubPDUs,96);
decoded=sixgr.mac.ra.parseNRInitialAccessMACPDU("DL",mac.Bytes);
assert(decoded.Valid && decoded.RRCSetup.TransactionID==2 && decoded.RRCSetup.SRB1LCID==1 && ...
    decoded.ContentionIdentity==request.ContentionIdentity && isnan(decoded.FinalCRNTI) && ...
    decoded.RRCCodecEvidence.Semantic.cell_group_id==0 && ...
    decoded.MACDecodeEvidence.PaddingBytes==79);
complete=sixgr.rrc.asn1.NRAccessMessageCodec.encode("setup_complete", ...
    struct('transaction_id',2,'selected_plmn_identity',1,'dedicated_nas_hex',"7E0041"));
assert(complete.Hex=="140000DF801040" && ~complete.NASValidated && ~complete.DedicatedDRBConfigured);
back=sixgr.rrc.asn1.NRAccessMessageCodec.decode("setup_complete",complete.Bytes);
assert(isequaln(back.Semantic,complete.Semantic));
reject(@()sixgr.rrc.asn1.NRAccessMessageCodec.decode("setup",[response.RRCCodecEvidence.Bytes uint8(0)]));
reject(@()sixgr.mac.ra.buildNRMsg3Payload("randomValue",2^39,"mo-Signalling"));
reject(@()sixgr.mac.ra.buildNRMsg4ContentionResolution([1 2 3 4 5 256],0));
duplicate=sixgr.l2.mac.MACPDUAssembler.assemble("DL",[response.MACSubPDUs;response.MACSubPDUs(1)],96);
reject(@()sixgr.mac.ra.parseNRInitialAccessMACPDU("DL",duplicate.Bytes));
assert(~decoded.MACRRCStandardsQualified,'A supported wire subset is not full protocol qualification.');
ok=true;
fprintf('NR_ACCESS_MAC_RRC_CODEC_PASS ULCCCH48=1 MCG0_SRB1=1 opaqueNAS=1 RFexecutions=0\n');
end
function reject(f)
try, f(); catch, return; end
error('test:NRAccessGuardMissing','Malformed/unsupported original access bytes must not be silently accepted.');
end
