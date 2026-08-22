function message = parseRRCSetupComplete(bitsOrBytes)
%PARSERRCSETUPCOMPLETE Parse a decoded bounded UL-DCCH SRB1 SDU.
bytes = localNormalizeBytes(bitsOrBytes);
if numel(bytes) < 5 || bytes(1) ~= uint8(51) || ...
        bytes(2) > uint8(3) || bytes(3) < uint8(1) || ...
        bytes(3) > uint8(32)
    error("sixgr:mac:ra:InvalidRRCSetupComplete", ...
        "Decoded UL-DCCH does not contain a valid RRCSetupComplete.");
end
identityLength = double(bytes(4));
last = 4 + identityLength;
if identityLength < 1 || numel(bytes) < last
    error("sixgr:mac:ra:InvalidRRCSetupComplete", ...
        "Decoded RRCSetupComplete UE identity is missing or truncated.");
end
bytes = bytes(1:last);
identity = string(native2unicode(bytes(5:last).', "UTF-8"));
message = struct( ...
    "MessageType", "RRCSetupComplete", ...
    "TransactionID", double(bytes(2)), ...
    "SRB1LCID", double(bytes(3)), ...
    "UEIdentity", identity, ...
    "PayloadBytes", bytes(:), ...
    "PayloadHex", upper(string(reshape(dec2hex(bytes(:), 2).', 1, []))), ...
    "PayloadHash", sixgr.rrc.asn1.asn1SHA256Hex(bytes), ...
    "Valid", true);
end

function bytes = localNormalizeBytes(raw)
raw = raw(:);
if all(raw == 0 | raw == 1) && numel(raw) > 8
    bits = int8(raw ~= 0);
    pad = mod(8 - mod(numel(bits), 8), 8);
    if pad > 0
        bits = [bits; zeros(pad, 1, "int8")]; %#ok<AGROW>
    end
    bytes = zeros(numel(bits) / 8, 1, "uint8");
    for ii = 1:numel(bytes)
        value = uint8(0);
        for jj = 1:8
            value = bitor(bitshift(value, 1), ...
                uint8(bits((ii - 1) * 8 + jj)));
        end
        bytes(ii) = value;
    end
else
    bytes = uint8(raw);
end
end
