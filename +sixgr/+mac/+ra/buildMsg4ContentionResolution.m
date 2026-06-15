function msg4 = buildMsg4ContentionResolution(contentionIdentity, varargin)
%BUILDMSG4CONTENTIONRESOLUTION Build Msg4 contention-resolution MAC bytes.
p = inputParser;
p.addParameter("FinalCRNTI", 4660, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
idBytes = localNormalizeIdentity(contentionIdentity);
payload = uint8([2; idBytes(:); localUInt16Bytes(uint16(p.Results.FinalCRNTI))]);
msg4 = struct();
msg4.PayloadBytes = payload(:);
msg4.PayloadBits = localBytesToBits(payload);
msg4.PayloadHex = upper(string(reshape(dec2hex(payload(:), 2).', 1, [])));
msg4.ContentionIdentityBytes = idBytes(:);
msg4.ContentionIdentity = upper(string(reshape(dec2hex(idBytes(:), 2).', 1, [])));
msg4.FinalCRNTI = double(p.Results.FinalCRNTI);
msg4.PayloadHash = sixgr.rrc.asn1.sha256Hex(payload);
end

function id = localNormalizeIdentity(raw)
if isstring(raw) || ischar(raw)
    txt = char(string(raw));
    txt = regexprep(txt, "[^0-9A-Fa-f]", "");
    if mod(numel(txt), 2) ~= 0
        txt = ["0" txt];
    end
    vals = uint8(sscanf(txt, "%2x"));
else
    vals = uint8(raw(:));
end
if numel(vals) < 6
    vals(end+1:6) = 0;
end
id = vals(1:6);
end

function bytes = localUInt16Bytes(v)
bytes = uint8([bitshift(v, -8); bitand(v, uint16(255))]);
end

function bits = localBytesToBits(bytes)
bytes = uint8(bytes(:));
bits = zeros(numel(bytes)*8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii-1)*8 + jj) = int8(bitand(bitshift(bytes(ii), -(8-jj)), 1));
    end
end
end
