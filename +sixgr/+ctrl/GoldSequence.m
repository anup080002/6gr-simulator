function c = GoldSequence(Nout, cInit)
%GOLDSEQUENCE Generate the NR Gold sequence bits from TS 38.211 section 5.2.1.

Nout = max(0, round(double(Nout)));
if Nout == 0
    c = int8(zeros(0, 1));
    return;
end

Nc = 1600;
M = Nout + Nc;
x1 = false(1, M + 31);
x2 = false(1, M + 31);
x1(1) = true;

cInit = uint32(mod(double(cInit), 2^31));
for n = 1:31
    x2(n) = bitget(cInit, n) ~= 0;
end

for n = 1:M
    x1(n + 31) = xor(x1(n + 3), x1(n));
    x2(n + 31) = xor(xor(x2(n + 3), x2(n + 2)), xor(x2(n + 1), x2(n)));
end

c = int8(xor(x1(Nc + 1:Nc + Nout), x2(Nc + 1:Nc + Nout)).');
end
