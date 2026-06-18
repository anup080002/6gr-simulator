function [cfoHz, info] = estimateCFOFromCyclicPrefix(rxWaveform, ofdmInfo, sampleRateHz)
%estimateCFOFromCyclicPrefix Estimate carrier-frequency offset from OFDM CP.
%
% The cyclic prefix repeats the last samples of the useful OFDM symbol. A
% carrier-frequency offset creates a phase rotation over the Nfft-sample
% separation between those two copies:
%   CFO_Hz = angle(sum(conj(CP) .* tail)) * Fs / (2*pi*Nfft)

info = struct( ...
    "EstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "Status", "not_computed", ...
    "NumSymbolsUsed", 0, ...
    "Nfft", NaN, ...
    "SampleRate_Hz", NaN, ...
    "CorrelationMagnitude", NaN);
cfoHz = NaN;

if isempty(rxWaveform) || ~isnumeric(rxWaveform)
    info.Status = "empty_or_non_numeric_waveform";
    return;
end
sampleRateHz = double(sampleRateHz);
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = localFirstFinite(ofdmInfo, ["SampleRate","SampleRate_Hz"], NaN);
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    info.Status = "sample_rate_unavailable";
    return;
end

nfft = round(localFirstFinite(ofdmInfo, ["Nfft","FFTLength","NFFT"], NaN));
if ~(isfinite(nfft) && nfft > 0)
    info.Status = "nfft_unavailable";
    return;
end

cpLens = localFirstVector(ofdmInfo, ["CyclicPrefixLengths","CyclicPrefixLength","CPLengths"], []);
if isempty(cpLens)
    info.Status = "cyclic_prefix_lengths_unavailable";
    return;
end
cpLens = round(double(cpLens(:)));
cpLens = cpLens(isfinite(cpLens) & cpLens > 0);
if isempty(cpLens)
    info.Status = "cyclic_prefix_lengths_invalid";
    return;
end

x = double(rxWaveform);
if isvector(x)
    x = x(:);
end
nSamples = size(x, 1);
pos = 1;
corrSum = complex(0, 0);
numUsed = 0;
for sym = 1:numel(cpLens)
    cpLen = min(cpLens(sym), nfft);
    symLen = cpLen + nfft;
    if pos + symLen - 1 > nSamples
        break;
    end
    cp = x(pos:pos+cpLen-1, :);
    tailStart = pos + cpLen + nfft - cpLen;
    tail = x(tailStart:tailStart+cpLen-1, :);
    mask = isfinite(real(cp)) & isfinite(imag(cp)) & isfinite(real(tail)) & isfinite(imag(tail));
    if any(mask(:))
        corrSum = corrSum + sum(conj(cp(mask)) .* tail(mask), "all");
        numUsed = numUsed + 1;
    end
    pos = pos + symLen;
end

info.NumSymbolsUsed = double(numUsed);
info.Nfft = double(nfft);
info.SampleRate_Hz = double(sampleRateHz);
info.CorrelationMagnitude = abs(corrSum);
if numUsed < 1 || ~(isfinite(real(corrSum)) && isfinite(imag(corrSum))) || abs(corrSum) <= eps
    info.Status = "insufficient_cp_correlation";
    return;
end

cfoHz = angle(corrSum) * double(sampleRateHz) / (2 * pi * double(nfft));
if ~isfinite(cfoHz)
    info.Status = "cfo_estimate_nonfinite";
    cfoHz = NaN;
    return;
end

info.EstimateAvailable = true;
info.EstimatedCFO_Hz = double(cfoHz);
info.Status = "OK";
end

function value = localFirstFinite(s, names, defaultValue)
value = defaultValue;
if ~(isstruct(s) || isobject(s))
    return;
end
for name = string(names(:)).'
    try
        raw = s.(char(name));
    catch
        raw = [];
    end
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function values = localFirstVector(s, names, defaultValue)
values = defaultValue;
if ~(isstruct(s) || isobject(s))
    return;
end
for name = string(names(:)).'
    try
        raw = s.(char(name));
    catch
        raw = [];
    end
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    values = double(raw(:));
    return;
end
end
