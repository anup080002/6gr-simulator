function bits = sixgr_tb_bytes_to_bits_kernel(bytes)
% sixgr_tb_bytes_to_bits_kernel
% Convert uint8 bytes to int8 bit column (left-msb).
%#codegen

b = uint8(bytes(:));
n = numel(b);
bits = zeros(8*n, 1, 'int8');
if n <= 0
    return;
end

w = 1;
for i = 1:n
    bi = b(i);
    for k = 7:-1:0
        bits(w) = int8(bitand(bitshift(bi, -k), uint8(1)));
        w = w + 1;
    end
end
end
