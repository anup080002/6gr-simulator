function [out, info] = PDSCHModulator(input, varargin)
%PDSCHMODULATOR Exact NR square-QAM mapper and soft demapper.
%
%   SYMBOLS = PDSCHModulator(BITS,MODULATION)
%   LLR = PDSCHModulator(SYMBOLS,MODULATION,"Operation","soft-demap", ...
%       "NoiseVariance",NVAR)
%
% Supported modulation names are QPSK, 16QAM, 64QAM, 256QAM, and
% normative 1024QAM.  Soft outputs use positive LLR for bit zero.
%
if isstruct(input) && isempty(varargin)
    error("sixgr:pdsch:PDSCHModulator:LegacyMetadataForbidden", ...
        "PDSCH modulation requires materialized bits or symbols and an explicit modulation; TX-metadata inference is forbidden.");
end

if isempty(varargin)
    error("sixgr:pdsch:PDSCHModulator:MissingModulation", ...
        "A PDSCH modulation name is required.");
end
modulation = localNormalizeModulation(varargin{1});
options = localParseOptions(varargin(2:end));
[qm, normalizationSquared] = localModulationInfo(modulation);

switch options.Operation
    case {"map", "modulate"}
        localRequireBinary(input);
        if mod(numel(input), qm) ~= 0
            error("sixgr:pdsch:PDSCHModulator:BitCountNotDivisibleByQm", ...
                "Input bit count %d is not divisible by Qm=%d for %s.", ...
                numel(input), qm, modulation);
        end
        out = localMapBits(input(:), qm, normalizationSquared);
        algorithm = "exact_ts_38_211_gray_mapping";
    case {"soft-demap", "soft_demodulate", "demap", "demodulate"}
        localRequireSymbols(input);
        noiseVariance = localExpandNoiseVariance(options.NoiseVariance, numel(input));
        out = localSoftDemap(input(:), qm, normalizationSquared, ...
            noiseVariance, options.Algorithm);
        algorithm = options.Algorithm;
    case {"hard-demap", "hard_demodulate"}
        localRequireSymbols(input);
        out = localHardDemap(input(:), qm, normalizationSquared);
        algorithm = "minimum_euclidean_distance";
    otherwise
        error("sixgr:pdsch:PDSCHModulator:UnsupportedOperation", ...
            "Unsupported PDSCH modulation operation '%s'.", options.Operation);
end

info = struct();
info.Operation = options.Operation;
info.Modulation = modulation;
info.Qm = qm;
info.NormalizationDenominatorSquared = normalizationSquared;
info.Algorithm = algorithm;
info.LLRConvention = "positive_favours_bit_zero";
info.InputCount = numel(input);
info.OutputCount = numel(out);
end

function options = localParseOptions(nv)
options = struct("Operation", "map", "NoiseVariance", 1, "Algorithm", "log-map");
if mod(numel(nv), 2) ~= 0
    error("sixgr:pdsch:PDSCHModulator:BadNameValue", ...
        "PDSCH modulator options must be supplied as name-value pairs.");
end
for idx = 1:2:numel(nv)
    name = lower(strtrim(string(nv{idx})));
    switch name
        case "operation"
            options.Operation = lower(strtrim(string(nv{idx + 1})));
        case {"noisevariance", "noisevar"}
            options.NoiseVariance = nv{idx + 1};
        case {"algorithm", "llralgorithm"}
            options.Algorithm = lower(strtrim(string(nv{idx + 1})));
        otherwise
            error("sixgr:pdsch:PDSCHModulator:UnknownOption", ...
                "Unknown PDSCH modulator option '%s'.", name);
    end
end
if ~any(options.Algorithm == ["log-map", "max-log"])
    error("sixgr:pdsch:PDSCHModulator:UnsupportedLLRAlgorithm", ...
        "LLR algorithm must be 'log-map' or 'max-log'.");
end
end

function modulation = localNormalizeModulation(raw)
if isempty(raw) || (isstring(raw) && isscalar(raw) && ismissing(raw))
    error("sixgr:pdsch:PDSCHModulator:MissingModulation", ...
        "A PDSCH modulation name is required.");
end
if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    error("sixgr:pdsch:PDSCHModulator:MissingModulation", ...
        "A scalar PDSCH modulation name is required.");
end
modulation = upper(erase(erase(strtrim(string(raw)), "-"), " "));
if strlength(modulation) == 0
    error("sixgr:pdsch:PDSCHModulator:MissingModulation", ...
        "A PDSCH modulation name is required.");
end
if ~any(modulation == ["QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"])
    error("sixgr:pdsch:PDSCHModulator:UnsupportedNRModulation", ...
        "Unsupported strict-NR PDSCH modulation '%s'.", modulation);
end
end

function [qm, normalizationSquared] = localModulationInfo(modulation)
switch modulation
    case "QPSK"
        qm = 2;
        normalizationSquared = 2;
    case "16QAM"
        qm = 4;
        normalizationSquared = 10;
    case "64QAM"
        qm = 6;
        normalizationSquared = 42;
    case "256QAM"
        qm = 8;
        normalizationSquared = 170;
    case "1024QAM"
        qm = 10;
        normalizationSquared = 682;
end
end

function localRequireBinary(bits)
if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) ...
        && all(isfinite(double(bits(:)))) && all(bits(:) == 0 | bits(:) == 1))
    error("sixgr:pdsch:PDSCHModulator:NonBinaryInput", ...
        "PDSCH modulation input must contain only binary values zero and one.");
end
end

function localRequireSymbols(symbols)
if ~(isnumeric(symbols) && all(isfinite(real(symbols(:)))) ...
        && all(isfinite(imag(symbols(:)))))
    error("sixgr:pdsch:PDSCHModulator:InvalidSymbolInput", ...
        "PDSCH demodulation input must contain finite numeric symbols.");
end
end

function symbols = localMapBits(bits, qm, normalizationSquared)
bits = double(bits(:));
groups = reshape(bits, qm, []).';
axisBits = qm / 2;
inPhase = zeros(size(groups, 1), 1);
quadrature = zeros(size(groups, 1), 1);
for symbolIndex = 1:size(groups, 1)
    inPhase(symbolIndex) = localAxisAmplitude(groups(symbolIndex, 1:2:qm), axisBits);
    quadrature(symbolIndex) = localAxisAmplitude(groups(symbolIndex, 2:2:qm), axisBits);
end
symbols = complex(inPhase, quadrature) / sqrt(normalizationSquared);
end

function amplitude = localAxisAmplitude(bits, axisBitCount)
if axisBitCount == 1
    amplitude = 1 - 2 * bits(1);
    return;
end
inner = 2 - (1 - 2 * bits(axisBitCount));
for idx = (axisBitCount - 1):-1:2
    weight = 2^(axisBitCount - idx + 1);
    inner = weight - (1 - 2 * bits(idx)) * inner;
end
amplitude = (1 - 2 * bits(1)) * inner;
end

function [points, labels] = localConstellation(qm, normalizationSquared)
indices = uint16((0:(2^qm - 1)).');
labels = zeros(numel(indices), qm);
for bitIndex = 1:qm
    labels(:, bitIndex) = bitget(indices, qm - bitIndex + 1);
end
points = localMapBits(labels.', qm, normalizationSquared);
end

function llr = localSoftDemap(symbols, qm, normalizationSquared, noiseVariance, algorithm)
[points, labels] = localConstellation(qm, normalizationSquared);
llrMatrix = zeros(numel(symbols), qm);
for symbolIndex = 1:numel(symbols)
    metric = -abs(symbols(symbolIndex) - points).^2 / noiseVariance(symbolIndex);
    for bitIndex = 1:qm
        metric0 = metric(labels(:, bitIndex) == 0);
        metric1 = metric(labels(:, bitIndex) == 1);
        if algorithm == "max-log"
            llrMatrix(symbolIndex, bitIndex) = max(metric0) - max(metric1);
        else
            llrMatrix(symbolIndex, bitIndex) = ...
                localLogSumExp(metric0) - localLogSumExp(metric1);
        end
    end
end
llr = reshape(llrMatrix.', [], 1);
end

function bits = localHardDemap(symbols, qm, normalizationSquared)
[points, labels] = localConstellation(qm, normalizationSquared);
bitMatrix = zeros(numel(symbols), qm, "int8");
for symbolIndex = 1:numel(symbols)
    [~, index] = min(abs(symbols(symbolIndex) - points).^2);
    bitMatrix(symbolIndex, :) = int8(labels(index, :));
end
bits = reshape(bitMatrix.', [], 1);
end

function value = localLogSumExp(values)
peak = max(values);
value = peak + log(sum(exp(values - peak)));
end

function noiseVariance = localExpandNoiseVariance(raw, symbolCount)
if ~(isnumeric(raw) && isreal(raw) && all(isfinite(raw(:))) ...
        && all(raw(:) > 0) && (isscalar(raw) || numel(raw) == symbolCount))
    error("sixgr:pdsch:PDSCHModulator:InvalidNoiseVariance", ...
        "NoiseVariance must be positive, finite, and scalar or one value per symbol.");
end
if isscalar(raw)
    noiseVariance = repmat(double(raw), symbolCount, 1);
else
    noiseVariance = double(raw(:));
end
end
