function [blockWithCRC, crcBits] = CRCSpec(bits, crcType)
%CRCSPEC Independent TS 38.212 CRC-16/24A/24B attachment oracle.
%
% This oracle intentionally calls neither production code nor nr* helpers.

if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) ...
        && all(isfinite(double(bits(:)))) && all(bits(:) == 0 | bits(:) == 1))
    error("sixgr:pdsch:oracle:CRCSpec:NonBinaryInput", ...
        "CRC oracle input must contain only zero and one.");
end
token = upper(erase(strtrim(string(crcType)), "CRC"));
switch token
    case "16"
        exponents = [16 12 5 0];
    case "24A"
        exponents = [24 23 18 17 14 11 10 7 6 5 4 3 1 0];
    case "24B"
        exponents = [24 23 6 5 1 0];
    otherwise
        error("sixgr:pdsch:oracle:CRCSpec:UnsupportedCRC", ...
            "CRC type must be 16, 24A, or 24B.");
end

degree = exponents(1);
polynomial = false(1, degree + 1);
polynomial(degree - exponents + 1) = true;
work = [logical(bits(:).'), false(1, degree)];
for idx = 1:numel(bits)
    if work(idx)
        work(idx:(idx + degree)) = xor( ...
            work(idx:(idx + degree)), polynomial);
    end
end
crcBits = int8(work(end - degree + 1:end).');
blockWithCRC = [int8(bits(:)); crcBits];
end
