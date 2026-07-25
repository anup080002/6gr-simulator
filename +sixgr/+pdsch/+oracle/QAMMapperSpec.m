function [symbols, info] = QAMMapperSpec(bits, modulation)
%QAMMAPPERSPEC Independent TS 38.211 square-QAM mapping oracle.
%
% This oracle intentionally calls neither production code nor nr* helpers.

token = localModulation(modulation);
[qm, normSquared] = localInfo(token);
if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) ...
        && all(isfinite(double(bits(:)))) && all(bits(:) == 0 | bits(:) == 1))
    error("sixgr:pdsch:oracle:QAMMapperSpec:NonBinaryInput", ...
        "QAM oracle input must contain only zero and one.");
end
if mod(numel(bits), qm) ~= 0
    error("sixgr:pdsch:oracle:QAMMapperSpec:BitCountNotDivisibleByQm", ...
        "Input bit count must be divisible by Qm=%d.", qm);
end

groups = reshape(double(bits(:)), qm, []).';
axisBitCount = qm / 2;
symbols = complex(zeros(size(groups, 1), 1));
for idx = 1:size(groups, 1)
    iAmplitude = localPAM(groups(idx, 1:2:qm), axisBitCount);
    qAmplitude = localPAM(groups(idx, 2:2:qm), axisBitCount);
    symbols(idx) = complex(iAmplitude, qAmplitude) / sqrt(normSquared);
end
info = struct("Modulation", token, "Qm", qm, ...
    "NormalizationDenominatorSquared", normSquared);
end

function token = localModulation(raw)
if isempty(raw) || (isstring(raw) && isscalar(raw) && ismissing(raw)) ...
        || ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    error("sixgr:pdsch:oracle:QAMMapperSpec:MissingModulation", ...
        "A modulation name is required.");
end
token = upper(erase(erase(strtrim(string(raw)), "-"), " "));
if strlength(token) == 0
    error("sixgr:pdsch:oracle:QAMMapperSpec:MissingModulation", ...
        "A modulation name is required.");
end
if ~any(token == ["QPSK","16QAM","64QAM","256QAM","1024QAM"])
    error("sixgr:pdsch:oracle:QAMMapperSpec:UnsupportedNRModulation", ...
        "Unsupported strict-NR modulation '%s'.", token);
end
end

function [qm, normSquared] = localInfo(token)
switch token
    case "QPSK"
        qm = 2; normSquared = 2;
    case "16QAM"
        qm = 4; normSquared = 10;
    case "64QAM"
        qm = 6; normSquared = 42;
    case "256QAM"
        qm = 8; normSquared = 170;
    case "1024QAM"
        qm = 10; normSquared = 682;
end
end

function amplitude = localPAM(bits, bitCount)
if bitCount == 1
    amplitude = 1 - 2 * bits(1);
    return;
end
accumulator = 2 - (1 - 2 * bits(bitCount));
for idx = (bitCount - 1):-1:2
    accumulator = 2^(bitCount - idx + 1) ...
        - (1 - 2 * bits(idx)) * accumulator;
end
amplitude = (1 - 2 * bits(1)) * accumulator;
end
