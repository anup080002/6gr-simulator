function hex = sha256Hex(data)
%SHA256HEX Return SHA-256 hex for uint8/bit-vector evidence.
if isempty(data)
    data = uint8([]);
elseif all(data(:) == 0 | data(:) == 1)
    data = uint8(data(:));
else
    data = uint8(data(:));
end
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(data);
    digest = typecast(md.digest(), "uint8");
    hex = lower(reshape(dec2hex(digest, 2).', 1, []));
catch
    % Deterministic non-cryptographic emergency path; normal MATLAB has Java.
    v = uint32(2166136261);
    for i = 1:numel(data)
        v = uint32(mod(double(bitxor(v, uint32(data(i)))) * 16777619, 2^32));
    end
    hex = sprintf("fnv32_%08x", v);
end
hex = string(hex);
end
