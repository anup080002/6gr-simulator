function identity=receivedMsg4Identity(message,pdcchOK,pdschOK,expectedContentionIdentity)
%RECEIVEDMSG4IDENTITY Install identity only from accepted decoded Msg4 bytes.
% The bounded Msg4 codec is not an NR MAC/RRC encoding qualification. This
% boundary deliberately takes neither TX payload nor configured final RNTI.
arguments
    message (1,1) struct
    pdcchOK (1,1) logical
    pdschOK (1,1) logical
    expectedContentionIdentity (1,1) string
end
assert(pdcchOK && pdschOK && logical(sixgr.util.structGet(message,'Valid',false)), ...
    'sixgr:mac:ra:UnacceptedMsg4Identity','Both received control/data and the decoded Msg4 payload must be accepted.');
assert(strlength(expectedContentionIdentity)>0 && ...
    string(sixgr.util.structGet(message,'ContentionIdentity',""))==expectedContentionIdentity, ...
    'sixgr:mac:ra:Msg4IdentityMismatch','Decoded contention identity must match this UE request.');
rnti=double(sixgr.util.structGet(message,'FinalCRNTI',NaN));
% TS 38.321 V18.6.0 Table 7.1-1: C-RNTI range 0001..FFF2.
assert(isscalar(rnti) && isreal(rnti) && isfinite(rnti) && rnti==fix(rnti) && rnti>=1 && rnti<=65522, ...
    'sixgr:mac:ra:InvalidReceivedCRNTI','Decoded C-RNTI must be an integer in 0001..FFF2, not a reserved/common RNTI.');
profile=string(sixgr.util.structGet(message,'EncodingProfile',""));
assert(profile=="legacy_bounded_not_NR_MAC_RRC", ...
    'sixgr:mac:ra:UnsupportedMsg4IdentityEncoding','Identity installation requires the explicitly supported received codec.');
identity=struct('RNTI',rnti,'Source',"decoded_msg4_payload_after_contention_match", ...
    'EncodingProfile',profile,'MACRRCStandardsQualified',false);
end
