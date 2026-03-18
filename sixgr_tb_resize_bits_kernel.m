function bitsOut = sixgr_tb_resize_bits_kernel(bitsIn, tbs)
%#codegen
% sixgr_tb_resize_bits_kernel
% Coder-friendly TB bit resize/pad/truncate kernel.

tbs = max(0, round(double(tbs)));
if tbs <= 0
    bitsOut = int8([]);
    return;
end

b = int8(bitsIn(:) ~= 0);
if numel(b) == tbs
    bitsOut = b;
    return;
end

if numel(b) > tbs
    bitsOut = b(1:tbs);
    return;
end

bitsOut = zeros(tbs,1, "int8");
bitsOut(1:numel(b)) = b;
end

