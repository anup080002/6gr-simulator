function bytes = sixgr_tb_bits_to_bytes_kernel(bits)
% sixgr_tb_bits_to_bytes_kernel
% Convert bit column (0/1) to uint8 bytes (left-msb), truncating extra bits.
%#codegen

v = uint8(bits(:) ~= 0);
n8 = floor(numel(v) / 8);
if n8 <= 0
    bytes = uint8([]);
    return;
end

bytes = zeros(n8, 1, 'uint8');
for i = 1:n8
    base = (i - 1) * 8;
    x = uint8(0);
    for k = 1:8
        x = bitor(x, bitshift(v(base + k), 8 - k));
    end
    bytes(i) = x;
end
end
