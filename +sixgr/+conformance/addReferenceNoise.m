function [rxWaveform, provenance] = addReferenceNoise(txWaveform, carrier, snr_dB, varargin)
%ADDREFERENCENOISE Add FRC AWGN using an occupied-grid Es/N0 reference.
%
%   [Y, INFO] = sixgr.conformance.addReferenceNoise(X, CARRIER, SNR_DB)
%   adds independent circular complex time-domain AWGN to every receive
%   column in X. SNR_DB is Es/N0 for unit-energy QAM symbols on occupied
%   resource-grid REs. The waveform power, cyclic prefix, and unused FFT
%   bins are deliberately excluded from the SNR definition.
%
%   [...] = sixgr.conformance.addReferenceNoise(..., "Seed", SEED) uses a
%   deterministic local Twister stream without changing the caller's RNG
%   state.
%
%   [...] = sixgr.conformance.addReferenceNoise(...,
%   "SignalEnergyPerOccupiedRE", ES) applies the same Es/N0 definition to a
%   waveform whose occupied data REs have been scaled to energy ES (for
%   example by a physical transmit-power context). The default remains one.
%
%   The variance contract is
%
%       gridNoiseVariance   = 10^(-SNR_DB/10)
%       sampleNoiseVariance = gridNoiseVariance / G
%
%   where G is the calibrated OFDM sample-to-grid noise-variance gain.

ip = inputParser;
ip.FunctionName = "sixgr.conformance.addReferenceNoise";
ip.addRequired("txWaveform", @localValidWaveform);
ip.addRequired("carrier");
ip.addRequired("snr_dB", ...
    @(v) isnumeric(v) && isreal(v) && isscalar(v) && isfinite(v));
ip.addParameter("Seed", [], @localValidSeed);
ip.addParameter("SignalEnergyPerOccupiedRE", 1, ...
    @(v) isnumeric(v) && isreal(v) && isscalar(v) && isfinite(v) && v > 0);
ip.parse(txWaveform, carrier, snr_dB, varargin{:});
opt = ip.Results;

calibration = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier);
sampleToGridGain = double(calibration.SampleToGridNoiseVarianceGain);
if ~(isscalar(sampleToGridGain) && isfinite(sampleToGridGain) && ...
        sampleToGridGain > 0)
    error("sixgr:conformance:InvalidOFDMNoiseGain", ...
        "The calibrated OFDM sample-to-grid noise-variance gain must be positive and finite.");
end

requestedEsN0_dB = double(snr_dB);
signalEnergyPerOccupiedRE = double(opt.SignalEnergyPerOccupiedRE);
gridNoiseVariance = signalEnergyPerOccupiedRE .* 10.^(-requestedEsN0_dB / 10);
sampleNoiseVariance = gridNoiseVariance / sampleToGridGain;
if ~(isscalar(gridNoiseVariance) && isfinite(gridNoiseVariance) && ...
        gridNoiseVariance > 0 && isscalar(sampleNoiseVariance) && ...
        isfinite(sampleNoiseVariance) && sampleNoiseVariance > 0)
    error("sixgr:conformance:InvalidReferenceNoiseVariance", ...
        "The requested Es/N0 produces a nonpositive or nonfinite noise variance.");
end

seed = opt.Seed;
if ~isempty(seed)
    previousRng = rng;
    restoreRng = onCleanup(@() rng(previousRng));
    rng(double(seed), "twister");
end

realNoise = randn(size(txWaveform), "like", real(txWaveform));
imagNoise = randn(size(txWaveform), "like", real(txWaveform));
noise = sqrt(sampleNoiseVariance / 2) .* complex(realNoise, imagNoise);
rxWaveform = txWaveform + noise;

provenance = struct( ...
    "Version", "frc_reference_noise/v1", ...
    "Source", "sixgr.conformance.addReferenceNoise", ...
    "NoiseKind", "independent_zero_mean_circular_complex_time_domain_awgn", ...
    "RequestedEsN0_dB", requestedEsN0_dB, ...
    "SNRDefinition", ...
        "Es/N0 for the disclosed QAM-symbol energy on occupied grid RE; N0 is complex grid-domain noise variance after OFDM demodulation", ...
    "SignalEnergyPerOccupiedRE", signalEnergyPerOccupiedRE, ...
    "GridNoiseVariance", gridNoiseVariance, ...
    "SampleNoiseVariance", sampleNoiseVariance, ...
    "ComplexVarianceDefinition", "E[abs(n)^2]", ...
    "SampleToGridNoiseVarianceGain", sampleToGridGain, ...
    "SampleToGridNoiseVarianceGainSource", ...
        string(calibration.SampleToGridNoiseVarianceGainSource), ...
    "VarianceEquation", ...
        "sampleNoiseVariance = SignalEnergyPerOccupiedRE*10^(-RequestedEsN0_dB/10) / SampleToGridNoiseVarianceGain", ...
    "WaveformPowerUsed", false, ...
    "CyclicPrefixPowerUsed", false, ...
    "UnusedFFTBinPowerUsed", false, ...
    "NumTimeSamples", size(txWaveform, 1), ...
    "NumRxColumns", size(txWaveform, 2), ...
    "SeedApplied", ~isempty(seed), ...
    "Seed", localSeedValue(seed), ...
    "OFDMCalibrationVersion", string(calibration.Version));
end

function tf = localValidWaveform(value)
tf = isnumeric(value) && isfloat(value) && ismatrix(value) && ...
    ~isempty(value) && size(value, 1) > 0 && all(isfinite(value), "all");
end

function tf = localValidSeed(value)
tf = isempty(value) || (isnumeric(value) && isreal(value) && ...
    isscalar(value) && isfinite(value) && value == fix(value) && ...
    value >= 0 && value <= 2^32 - 1);
end

function value = localSeedValue(seed)
if isempty(seed)
    value = NaN;
else
    value = double(seed);
end
end
