function msg4 = parseMsg4ContentionResolution(bitsOrBytes)
%PARSEMSG4CONTENTIONRESOLUTION Parse recovered Msg4 contention identity.
bytes = localNormalizeBytes(bitsOrBytes);
if numel(bytes) < 9 || bytes(1) ~= uint8(2)
    error("sixgr:mac:ra:InvalidMsg4Payload", "Msg4 payload does not contain the anchor contention-resolution identity.");
end
id = bytes(2:7);
final = double(bytes(8)) * 256 + double(bytes(9));
msg4 = struct();
msg4.PayloadBytes = bytes(1:9);
msg4.PayloadHex = upper(string(reshape(dec2hex(bytes(1:9), 2).', 1, [])));
msg4.ContentionIdentityBytes = id(:);
msg4.ContentionIdentity = upper(string(reshape(dec2hex(id(:), 2).', 1, [])));
msg4.FinalCRNTI = final;
msg4.RRCSetupPresent = false;
msg4.RRCSetup = struct();
msg4.RRCSetupSHA256 = "";
msg4.EncodingProfile = "legacy_bounded_not_NR_MAC_RRC";
if numel(bytes) > 9 && any(bytes(10:end)~=0)
    if numel(bytes) < 12 || bytes(10) ~= uint8(50) || ...
            bytes(11) > uint8(3) || bytes(12) < uint8(1) || ...
            bytes(12) > uint8(32)
        error("sixgr:mac:ra:InvalidRRCSetup", ...
            "Msg4 contains an invalid bounded RRCSetup message.");
    end
    msg4.PayloadBytes = bytes(1:12);
    msg4.PayloadHex = upper(string(reshape( ...
        dec2hex(msg4.PayloadBytes, 2).', 1, [])));
    msg4.RRCSetupPresent = true;
    msg4.RRCSetup = struct( ...
        "MessageType", "RRCSetup", ...
        "TransactionID", double(bytes(11)), ...
        "SRB1LCID", double(bytes(12)));
    msg4.RRCSetupSHA256 = sixgr.rrc.asn1.asn1SHA256Hex(bytes(10:12));
    assert(all(bytes(13:end)==0),'sixgr:mac:ra:InvalidMsg4Padding', ...
        'The bounded Msg4 payload has unexpected nonzero trailing bytes.');
end
msg4.Valid = true;
end

function bytes = localNormalizeBytes(raw)
raw = raw(:);
if all(raw == 0 | raw == 1) && numel(raw) > 8
    bytes = localBitsToBytes(int8(raw));
else
    bytes = uint8(raw);
end
end

function bytes = localBitsToBytes(bits)
bits = int8(bits(:) ~= 0);
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
bytes = zeros(numel(bits)/8, 1, "uint8");
for ii = 1:numel(bytes)
    v = uint8(0);
    for jj = 1:8
        v = bitor(bitshift(v, 1), uint8(bits((ii-1)*8 + jj)));
    end
    bytes(ii) = v;
end
end
