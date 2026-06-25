function calibration = calibrateOFDMNoiseTransform(carrier, varargin)
%CALIBRATEOFDMNOISETRANSFORM Measure the OFDM sample-to-grid noise gain.
%
%   CAL = sixgr.phy.waveform.calibrateOFDMNoiseTransform(CARRIER, ...)
%   runs deterministic reconstruction, impulse, and white-noise probes for
%   the same numerology/options used by the Toolbox OFDM wrappers.  The
%   calibrated contract is
%
%       sigma_grid^2 = CAL.SampleToGridNoiseVarianceGain * sigma_time^2
%
%   where sigma_time^2 is the complex sample-domain variance before OFDM
%   demodulation and sigma_grid^2 is the variance on occupied resource-grid
%   RE after CP removal and FFT.

[ofdmArgs, opt] = localSplitOptions(varargin{:});

persistent cache;
if isempty(cache)
    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
end

[modArgs, demodArgs, infoArgs] = localClassifyOFDMArgs(ofdmArgs);
baseInfo = localResolveOFDMInfo(carrier, infoArgs);
key = localCalibrationKey(carrier, baseInfo, opt.NumNoiseRE);
if logical(opt.UseCache) && ~logical(opt.ForceRecompute) && isKey(cache, key)
    calibration = cache(key);
    return;
end

calibration = localRunCalibration(carrier, modArgs, demodArgs, infoArgs, baseInfo, opt);
if logical(opt.UseCache)
    cache(key) = calibration;
end
end

function calibration = localRunCalibration(carrier, modArgs, demodArgs, infoArgs, baseInfo, opt)
K = localCarrierSubcarriers(carrier);
L = localSymbolsPerSlot(carrier, baseInfo);
if ~(isfinite(K) && K > 0 && isfinite(L) && L > 0)
    error("sixgr:phy:waveform:OFDMCalibrationInvalidCarrier", ...
        "Cannot calibrate OFDM noise transform for invalid carrier dimensions.");
end
K = round(K);
L = round(L);

zeroGrid = complex(zeros(K, L, 1));
[zeroWaveform, ofdmInfo] = nrOFDMModulate(carrier, zeroGrid, modArgs{:});
ofdmInfo = localResolveOFDMInfo(carrier, infoArgs, ofdmInfo);

nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
sampleRate = double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN));
cpLengths = double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", []));
symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
windowing = double(sixgr.util.structGet(ofdmInfo, "Windowing", NaN));
if ~(isfinite(nfft) && nfft > 0)
    error("sixgr:phy:waveform:OFDMCalibrationMissingNfft", ...
        "OFDM calibration requires finite Nfft metadata.");
end

refGrid = localDeterministicReferenceGrid(K, L);
[refWaveform, ~] = nrOFDMModulate(carrier, refGrid, modArgs{:});
rxGrid = nrOFDMDemodulate(carrier, refWaveform, demodArgs{:});
nRecon = min(numel(rxGrid), numel(refGrid));
if nRecon > 0
    reconErr = rxGrid(1:nRecon) - refGrid(1:nRecon);
    reconMaxAbs = max(abs(reconErr(:)));
    reconRMS = sqrt(mean(abs(reconErr(:)).^2, "omitnan"));
else
    reconMaxAbs = Inf;
    reconRMS = Inf;
end

[impulseEnergyMean, impulsePeak, impulseIndex] = localImpulseProbe(carrier, zeroWaveform, ...
    demodArgs, cpLengths, nfft);

noiseREPerColumn = K * L;
nColumns = max(1, ceil(double(opt.NumNoiseRE) / max(1, noiseREPerColumn)));
timeNoiseVariance = double(opt.TimeNoiseVariance);
oldRng = rng;
cleanup = onCleanup(@() rng(oldRng));
rng(double(opt.WhiteNoiseSeed), "twister");
noiseWaveform = sqrt(timeNoiseVariance / 2) .* ...
    (randn(size(zeroWaveform, 1), nColumns) + 1j * randn(size(zeroWaveform, 1), nColumns));
noiseGrid = nrOFDMDemodulate(carrier, noiseWaveform, demodArgs{:});
noiseRECount = numel(noiseGrid);
measuredGridVariance = mean(abs(noiseGrid(:)).^2, "omitnan");
measuredGain = double(measuredGridVariance(1)) ./ timeNoiseVariance;
validMeasuredGain = isscalar(measuredGain) && all(isfinite(measuredGain(:))) && all(measuredGain(:) > 0);
if ~validMeasuredGain
    error("sixgr:phy:waveform:OFDMCalibrationInvalidGain", ...
        "Measured OFDM sample-to-grid noise gain is invalid.");
end
derivedGain = double(nfft);
derivedPredictionError = 10 * log10(max(measuredGridVariance, realmin) ./ ...
    max(derivedGain * timeNoiseVariance, realmin));
verificationTolerance_dB = 0.05;
if abs(derivedPredictionError) <= verificationTolerance_dB
    sampleToGridGain = derivedGain;
    gainSource = "fft_length_transform_gain_verified_by_white_noise";
else
    sampleToGridGain = measuredGain;
    gainSource = "white_noise_measured_gain_after_fft_length_verification_failed";
end

usefulSamples = localUsefulSampleCount(cpLengths, nfft, L);
totalSamples = size(zeroWaveform, 1);
cpSamples = max(0, totalSamples - usefulSamples);
predictionError = 10 * log10(max(measuredGridVariance, realmin) ./ ...
    max(sampleToGridGain * timeNoiseVariance, realmin));
gainVsNfft = 10 * log10(max(sampleToGridGain, realmin) ./ max(nfft, realmin));

calibration = struct( ...
    "Version", "ofdm_noise_transform/v1", ...
    "Source", "deterministic_impulse_and_white_noise_toolbox_ofdm_calibration", ...
    "Equation", "sigma_grid2 = SampleToGridNoiseVarianceGain * sigma_time2", ...
    "Nfft", double(nfft), ...
    "SampleRate", double(sampleRate), ...
    "Windowing", double(windowing), ...
    "CyclicPrefixLengths", double(cpLengths(:).'), ...
    "SymbolLengths", double(symbolLengths(:).'), ...
    "SymbolsPerSlot", double(L), ...
    "ActiveSubcarrierCount", double(K), ...
    "FFTUnusedSubcarrierCount", double(max(0, nfft - K)), ...
    "TotalSampleCount", double(totalSamples), ...
    "UsefulSampleCount", double(usefulSamples), ...
    "CyclicPrefixSampleCount", double(cpSamples), ...
    "SampleToGridNoiseVarianceGain", double(sampleToGridGain), ...
    "SampleToGridNoiseVarianceGainSource", char(gainSource), ...
    "GridToSampleNoiseVarianceGain", double(1 ./ sampleToGridGain), ...
    "MeasuredSampleToGridNoiseVarianceGain", double(measuredGain), ...
    "DerivedFFTLengthNoiseVarianceGain", double(derivedGain), ...
    "FFTLengthVerificationTolerance_dB", double(verificationTolerance_dB), ...
    "FFTLengthVerificationError_dB", double(derivedPredictionError), ...
    "CalibrationTimeNoiseVariance", double(timeNoiseVariance), ...
    "MeasuredGridNoiseVariance", double(measuredGridVariance), ...
    "NoiseRECount", double(noiseRECount), ...
    "NoiseRxColumns", double(nColumns), ...
    "WhiteNoiseSeed", double(opt.WhiteNoiseSeed), ...
    "WhiteNoisePredictionError_dB", double(predictionError), ...
    "WhiteNoiseGainVsNfft_dB", double(gainVsNfft), ...
    "ImpulseProbeSampleIndex", double(impulseIndex), ...
    "ImpulseProbeMeanGridEnergy", double(impulseEnergyMean), ...
    "ImpulseProbePeakGridMagnitude", double(impulsePeak), ...
    "ModDemodReconstructionMaxAbsError", double(reconMaxAbs), ...
    "ModDemodReconstructionRMSError", double(reconRMS), ...
    "TimeDomainSignalPowerReference", "active_samples_excluding_cp", ...
    "FrequencyDomainSignalPowerReference", "occupied_resource_grid_RE", ...
    "CyclicPrefixExcludedFromTimeReference", true, ...
    "UnusedSubcarriersExcludedFromGridReference", true, ...
    "WindowingIncludedInCalibrationKey", true);
end

function [ofdmArgs, opt] = localSplitOptions(varargin)
opt = struct( ...
    "NumNoiseRE", 262144, ...
    "TimeNoiseVariance", 1e-6, ...
    "WhiteNoiseSeed", 314159, ...
    "UseCache", true, ...
    "ForceRecompute", false);
ofdmArgs = {};
i = 1;
while i <= numel(varargin)
    if i == numel(varargin) || ~(ischar(varargin{i}) || isstring(varargin{i}))
        error("sixgr:phy:waveform:OFDMCalibrationInvalidNV", ...
            "OFDM calibration inputs must be name-value pairs.");
    end
    name = char(string(varargin{i}));
    value = varargin{i+1};
    switch lower(strtrim(name))
        case {"numnoisere", "noiserecount", "numcalibrationnoisere"}
            opt.NumNoiseRE = max(1, round(double(value)));
        case {"timenoisevariance", "samplevariance", "calibrationtimenoisevariance"}
            opt.TimeNoiseVariance = double(value);
            if ~(isscalar(opt.TimeNoiseVariance) && isfinite(opt.TimeNoiseVariance) && opt.TimeNoiseVariance > 0)
                error("sixgr:phy:waveform:OFDMCalibrationInvalidNoiseVariance", ...
                    "Calibration time-domain noise variance must be positive.");
            end
        case {"whitenoiseseed", "seed"}
            opt.WhiteNoiseSeed = round(double(value));
        case "usecache"
            opt.UseCache = logical(value);
        case {"forcerecompute", "refresh"}
            opt.ForceRecompute = logical(value);
        otherwise
            ofdmArgs = [ofdmArgs, varargin(i:i+1)]; %#ok<AGROW>
    end
    i = i + 2;
end
end

function [modArgs, demodArgs, infoArgs] = localClassifyOFDMArgs(ofdmArgs)
modNames = ["carrierfrequency", "nfft", "samplerate", "windowing"];
demodNames = ["carrierfrequency", "nfft", "samplerate", "cyclicprefixfraction"];
infoNames = ["carrierfrequency", "nfft", "samplerate", "windowing"];
modArgs = localFilterArgs(ofdmArgs, modNames);
demodArgs = localFilterArgs(ofdmArgs, demodNames);
infoArgs = localFilterArgs(ofdmArgs, infoNames);
end

function out = localFilterArgs(args, allowedNames)
out = {};
i = 1;
while i <= numel(args)
    name = lower(strtrim(string(args{i})));
    if any(name == allowedNames)
        out = [out, args(i:i+1)]; %#ok<AGROW>
    end
    i = i + 2;
end
end

function info = localResolveOFDMInfo(carrier, infoArgs, fallback)
if nargin < 3
    fallback = struct();
end
try
    info = nrOFDMInfo(carrier, infoArgs{:});
catch
    info = fallback;
    if ~isstruct(info) || isempty(fieldnames(info))
        info = nrOFDMInfo(carrier);
    end
end
end

function key = localCalibrationKey(carrier, ofdmInfo, numNoiseRE)
cp = double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", []));
key = sprintf("nrb=%g;scs=%g;cp=%s;nfft=%g;fs=%.15g;win=%g;L=%g;cpLens=%s;noiseRE=%d", ...
    localCarrierValue(carrier, "NSizeGrid", NaN), ...
    localCarrierValue(carrier, "SubcarrierSpacing", NaN), ...
    char(string(localCarrierValue(carrier, "CyclicPrefix", ""))), ...
    double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN)), ...
    double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN)), ...
    double(sixgr.util.structGet(ofdmInfo, "Windowing", NaN)), ...
    double(sixgr.util.structGet(ofdmInfo, "SymbolsPerSlot", NaN)), ...
    mat2str(cp(:).'), round(double(numNoiseRE)));
end

function value = localCarrierValue(carrier, name, defaultValue)
value = defaultValue;
try
    if isobject(carrier) && isprop(carrier, char(name))
        value = carrier.(char(name));
    elseif isstruct(carrier) && isfield(carrier, char(name))
        value = carrier.(char(name));
    end
catch
    value = defaultValue;
end
end

function K = localCarrierSubcarriers(carrier)
K = 12 * double(localCarrierValue(carrier, "NSizeGrid", NaN));
end

function L = localSymbolsPerSlot(carrier, ofdmInfo)
L = double(sixgr.util.structGet(ofdmInfo, "SymbolsPerSlot", NaN));
if ~(isfinite(L) && L > 0)
    L = double(localCarrierValue(carrier, "SymbolsPerSlot", NaN));
end
if ~(isfinite(L) && L > 0)
    L = 14;
end
end

function grid = localDeterministicReferenceGrid(K, L)
idx = reshape(1:(K * L), K, L);
phase = 2 * pi * mod(37 .* idx, 1021) ./ 1021;
grid = complex(cos(phase), sin(phase));
end

function [meanEnergy, peakMagnitude, sampleIndex] = localImpulseProbe(carrier, zeroWaveform, demodArgs, cpLengths, nfft)
sampleIndex = 1;
if ~isempty(cpLengths) && isfinite(double(cpLengths(1))) && isfinite(nfft)
    sampleIndex = max(1, min(size(zeroWaveform, 1), round(double(cpLengths(1))) + floor(double(nfft) / 2)));
end
impulse = complex(zeros(size(zeroWaveform, 1), 1));
impulse(sampleIndex) = 1;
grid = nrOFDMDemodulate(carrier, impulse, demodArgs{:});
meanEnergy = mean(abs(grid(:)).^2, "omitnan");
peakMagnitude = max(abs(grid(:)));
end

function useful = localUsefulSampleCount(cpLengths, nfft, symbolsPerSlot)
if ~(isfinite(nfft) && nfft > 0)
    useful = NaN;
    return;
end
if isempty(cpLengths)
    useful = double(symbolsPerSlot) * double(nfft);
else
    useful = numel(cpLengths(:)) * double(nfft);
end
end
