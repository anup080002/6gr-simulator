function hex = bitsToHex(bits)
%BITSTOHEX Convert MSB-first bits to uppercase hex text.
bits = int8(bits(:));
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
bytes = zeros(numel(bits)/8, 1, "uint8");
for i = 1:numel(bytes)
    value = uint8(0);
    for b = 1:8
        value = bitor(bitshift(value, 1), uint8(bits((i-1)*8+b) ~= 0));
    end
    bytes(i) = value;
end
hex = upper(string(reshape(dec2hex(bytes, 2).', 1, [])));
end
