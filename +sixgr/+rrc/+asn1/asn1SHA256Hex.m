function hex = asn1SHA256Hex(data)
%SHA256HEX Return SHA-256 hex for uint8/bit-vector evidence.
if isempty(data)
    data = uint8([]);
elseif all(data(:) == 0 | data(:) == 1)
    data = uint8(data(:));
else
    data = uint8(data(:));
end
hex = sixgr.util.sha256Hex(data);
end
