function sync = resolveSynchronizationState(varargin)
%RESOLVESYNCHRONIZATIONSTATE Shared timing/CFO sign and residual contract.
%
% CFO convention:
%   injected impairment applies exp(+j2*pi*f*n/Fs)
%   receiver correction applies exp(-j2*pi*f_hat*n/Fs)
%   residual = injected oscillator CFO - applied oscillator correction
%
% Timing convention:
%   raw acquisition timing is reported relative to the declared slot origin.
%   the applied data-alignment correction subtracts known implementation
%   delay before calling the waveform shifter.
%   residual = injected timing offset - applied timing correction.

ip = inputParser;
ip.addParameter("SampleRate_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("InjectedCFO_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("EstimatedCFO_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("AppliedCFOCorrection_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("ResidualCFOEstimate_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("EstimatedCommonFrequency_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("PhysicalDoppler_Hz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("PerPathDoppler_Hz", [], @(x) isnumeric(x) || isempty(x));
ip.addParameter("PerPathDopplerDeembeddingApplied", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("PerPathDopplerDeembeddingStatus", "", @(x) ischar(x) || isstring(x));
ip.addParameter("InjectedTimingOffset_samples", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("RawTimingEstimate_samples", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("KnownTimingDelay_samples", 0, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("AppliedTimingCorrection_samples", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("TimingEstimateUsed", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("TimingSource", "", @(x) ischar(x) || isstring(x));
ip.addParameter("FrequencySource", "", @(x) ischar(x) || isstring(x));
ip.addParameter("TrackingState", "", @(x) ischar(x) || isstring(x));
ip.addParameter("TrackingAgeSlots", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

sampleRate = localFiniteOrNaN(opt.SampleRate_Hz);
injectedCFO = localFiniteOrNaN(opt.InjectedCFO_Hz);
estimatedCFO = localFiniteOrNaN(opt.EstimatedCFO_Hz);
appliedCFO = localFiniteOrNaN(opt.AppliedCFOCorrection_Hz);
if ~isfinite(appliedCFO)
    appliedCFO = 0;
end
commonFrequency = localFiniteOrNaN(opt.EstimatedCommonFrequency_Hz);
physicalDoppler = localFiniteOrNaN(opt.PhysicalDoppler_Hz);
perPathDoppler = localFiniteVector(opt.PerPathDoppler_Hz);
residualCFO = NaN;
if isfinite(injectedCFO)
    residualCFO = injectedCFO - appliedCFO;
end

rawTiming = localFiniteOrNaN(opt.RawTimingEstimate_samples);
knownDelay = localFiniteOrZero(opt.KnownTimingDelay_samples);
timingForCorrection = NaN;
if isfinite(rawTiming)
    timingForCorrection = rawTiming - knownDelay;
end
appliedTiming = localFiniteOrNaN(opt.AppliedTimingCorrection_samples);
if ~isfinite(appliedTiming)
    appliedTiming = 0;
end
injectedTiming = localFiniteOrNaN(opt.InjectedTimingOffset_samples);
residualTiming = NaN;
if isfinite(injectedTiming)
    residualTiming = injectedTiming - appliedTiming;
end

sync = struct( ...
    "ContractVersion", "sixgr.phy.sync.SynchronizationState/v1", ...
    "SampleRate_Hz", double(sampleRate), ...
    "InjectedOscillatorCFO_Hz", double(injectedCFO), ...
    "EstimatedOscillatorCFO_Hz", double(estimatedCFO), ...
    "AppliedCFOCorrection_Hz", double(appliedCFO), ...
    "ResidualCFO_PostCorrection_Hz", double(residualCFO), ...
    "ResidualCFO_EstimatedPostCorrection_Hz", double(localFiniteOrNaN(opt.ResidualCFOEstimate_Hz)), ...
    "EstimatedCommonFrequency_Hz", double(commonFrequency), ...
    "PhysicalDoppler_Hz", double(physicalDoppler), ...
    "PerPathDoppler_Hz", double(perPathDoppler(:).'), ...
    "PerPathDopplerPathCount", double(numel(perPathDoppler)), ...
    "PerPathDopplerDeembeddingAvailable", ~isempty(perPathDoppler), ...
    "PerPathDopplerDeembeddingApplied", logical(opt.PerPathDopplerDeembeddingApplied), ...
    "PerPathDopplerDeembeddingStatus", char(string(opt.PerPathDopplerDeembeddingStatus)), ...
    "InjectedTimingOffset_samples", double(injectedTiming), ...
    "RawTimingEstimate_samples", double(rawTiming), ...
    "KnownTimingDelay_samples", double(knownDelay), ...
    "EstimatedTimingOffsetForCorrection_samples", double(timingForCorrection), ...
    "AppliedTimingCorrection_samples", double(appliedTiming), ...
    "ResidualTimingError_PostCorrection_samples", double(residualTiming), ...
    "TimingEstimateUsed", logical(opt.TimingEstimateUsed), ...
    "TimingSource", char(string(opt.TimingSource)), ...
    "FrequencySource", char(string(opt.FrequencySource)), ...
    "TrackingState", char(string(opt.TrackingState)), ...
    "TrackingAgeSlots", double(localFiniteOrNaN(opt.TrackingAgeSlots)), ...
    "CFOInjectionConvention", "tx_or_rx_impairment_applies_exp_plus_j2pi_f_n_over_fs", ...
    "CFOCorrectionConvention", "receiver_correction_applies_exp_minus_j2pi_fhat_n_over_fs", ...
    "CFOResidualDefinition", "residual_cfo_hz_equals_injected_oscillator_cfo_minus_applied_correction", ...
    "DopplerSeparationDefinition", "oscillator_cfo_correction_excludes_physical_doppler; optional_per_path_deembedding_operates_on_path_gain_tensors", ...
    "TimingReferenceDefinition", "applied_timing_correction_uses_raw_estimate_minus_known_channel_ofdm_filter_delay", ...
    "TimingResidualDefinition", "residual_timing_samples_equals_injected_timing_offset_minus_applied_correction");
end

function value = localFiniteOrNaN(raw)
value = double(raw);
if isempty(value) || ~isfinite(value(1))
    value = NaN;
else
    value = value(1);
end
end

function value = localFiniteVector(raw)
value = double(raw);
if isempty(value)
    value = zeros(1, 0);
    return;
end
value = value(:);
value = value(isfinite(value));
end

function value = localFiniteOrZero(raw)
value = double(raw);
if isempty(value) || ~isfinite(value(1))
    value = 0;
else
    value = value(1);
end
end
