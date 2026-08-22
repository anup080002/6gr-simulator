function msg3 = parseMsg3Payload(bitsOrBytes)
%PARSEMSG3PAYLOAD Parse recovered Msg3 CCCH payload.
bytes = localNormalizeBytes(bitsOrBytes);
if numel(bytes) < 8 || bytes(1) ~= uint8(1) || bytes(2) ~= uint8(6)
    error("sixgr:mac:ra:InvalidMsg3Payload", "Msg3 payload does not contain the anchor CCCH contention identity.");
end
id = bytes(3:8);
msg3 = struct();
msg3.PayloadBytes = bytes(1:8);
msg3.PayloadHex = upper(string(reshape(dec2hex(bytes(1:8), 2).', 1, [])));
msg3.ContentionIdentityBytes = id(:);
msg3.ContentionIdentity = upper(string(reshape(dec2hex(id(:), 2).', 1, [])));
msg3.RRCSetupRequestPresent = false;
msg3.RRCSetupRequest = struct();
msg3.RRCSetupRequestSHA256 = "";
consumed = 8;
if numel(bytes) > consumed
    if numel(bytes) < consumed + 2 || bytes(consumed + 1) ~= uint8(49)
        error("sixgr:mac:ra:InvalidRRCSetupRequest", ...
            "Msg3 contains an invalid bounded RRCSetupRequest discriminator.");
    end
    identityLength = double(bytes(consumed + 2));
    requestEnd = consumed + 2 + identityLength;
    if identityLength < 1 || numel(bytes) < requestEnd
        error("sixgr:mac:ra:InvalidRRCSetupRequest", ...
            "Msg3 RRCSetupRequest UE identity is missing or truncated.");
    end
    identityBytes = bytes(consumed + 3:requestEnd);
    ueIdentity = string(native2unicode(identityBytes(:).', "UTF-8"));
    msg3.PayloadBytes = bytes(1:requestEnd);
    msg3.PayloadHex = upper(string(reshape( ...
        dec2hex(msg3.PayloadBytes, 2).', 1, [])));
    msg3.RRCSetupRequestPresent = true;
    msg3.RRCSetupRequest = struct( ...
        "MessageType", "RRCSetupRequest", ...
        "UEIdentity", ueIdentity, ...
        "EstablishmentCause", "mo-Signalling");
    msg3.RRCSetupRequestSHA256 = sixgr.rrc.asn1.asn1SHA256Hex( ...
        bytes(consumed + 1:requestEnd));
end
msg3.Valid = true;
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
