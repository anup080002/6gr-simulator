function msg3 = buildMsg3Payload(varargin)
%BUILDMSG3PAYLOAD Build CCCH SDU style Msg3 contention identity bytes.
p = inputParser;
p.addParameter("UEId", 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter("ContentionIdentity", [], @(x)isempty(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

if isempty(opt.ContentionIdentity)
    seed = uint64(1125899906842597) + uint64(round(double(opt.UEId)));
    bytes = zeros(6, 1, "uint8");
    for ii = 1:6
        seed = uint64(mod(double(seed) * 6364136223846793005 + 1, 2^53));
        bytes(ii) = uint8(mod(double(bitshift(seed, -8)), 256));
    end
else
    raw = uint8(opt.ContentionIdentity(:));
    if numel(raw) < 6
        raw(end+1:6) = 0;
    end
    bytes = raw(1:6);
end
payload = uint8([1; 6; bytes(:)]);
msg3 = struct();
msg3.PayloadBytes = payload(:);
msg3.PayloadBits = localBytesToBits(payload);
msg3.PayloadHex = upper(string(reshape(dec2hex(payload(:), 2).', 1, [])));
msg3.ContentionIdentityBytes = bytes(:);
msg3.ContentionIdentity = upper(string(reshape(dec2hex(bytes(:), 2).', 1, [])));
msg3.PayloadHash = sixgr.rrc.asn1.sha256Hex(payload);
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
