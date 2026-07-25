function sequence = GoldSequenceSpec(cInit, outputLength)
%GOLDSEQUENCESPEC Independent TS 38.211 clause 5.2.1 Gold sequence.
%
% This oracle intentionally calls neither production code nor nr* helpers.

if ~(isnumeric(cInit) && isscalar(cInit) && isfinite(cInit) ...
        && cInit == fix(cInit) && cInit >= 0 && cInit < 2^31)
    error("sixgr:pdsch:oracle:GoldSequenceSpec:CInitOutOfRange", ...
        "Gold-sequence c_init must be an integer in [0,2^31-1].");
end
if ~(isnumeric(outputLength) && isscalar(outputLength) && isfinite(outputLength) ...
        && outputLength == fix(outputLength) && outputLength >= 0)
    error("sixgr:pdsch:oracle:GoldSequenceSpec:LengthOutOfRange", ...
        "Gold-sequence output length must be a nonnegative integer.");
end

nc = 1600;
stateLength = nc + outputLength + 31;
x1 = false(stateLength, 1);
x2 = false(stateLength, 1);
x1(1) = true;
for bitIndex = 0:30
    x2(bitIndex + 1) = bitget(uint32(cInit), bitIndex + 1) ~= 0;
end
for n = 0:(stateLength - 32)
    x1(n + 32) = xor(x1(n + 4), x1(n + 1));
    x2(n + 32) = xor(xor(x2(n + 4), x2(n + 3)), ...
        xor(x2(n + 2), x2(n + 1)));
end
sequence = int8(xor(x1(nc + (1:outputLength)), x2(nc + (1:outputLength))));
sequence = sequence(:);
end
