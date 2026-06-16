function hex = payloadBitsToHex(bits)
%PAYLOADBITSTOHEX Convert a DCI payload bit vector to deterministic hex.

bits = int8(bits(:) ~= 0);
if isempty(bits)
    hex = "";
    return;
end
pad = mod(4 - mod(numel(bits), 4), 4);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
nibble = reshape(bits, 4, []).';
vals = double(nibble(:, 1)) * 8 + double(nibble(:, 2)) * 4 + ...
    double(nibble(:, 3)) * 2 + double(nibble(:, 4));
alphabet = '0123456789ABCDEF';
hex = string(alphabet(vals + 1));
hex = join(hex(:).', "");
end
