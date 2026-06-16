function out = applyRFImpairmentChain(x, cfg, varargin)
%APPLYRFIMPAIRMENTCHAIN Apply configured RF impairments to samples with evidence.

p = inputParser;
p.addParameter("SampleRateHz", double(sixgr.util.structGet(cfg, "channel_rf.sampleRateHz", 30.72e6)));
p.addParameter("RunId", "channel_rf_strict");
p.addParameter("Direction", "downlink");
p.addParameter("MeasurementPoint", "rx_input");
p.parse(varargin{:});

fs = double(p.Results.SampleRateHz);
if ~(isfinite(fs) && fs > 0)
    error("sixgr:rf:BadSampleRate", "RF impairment chain requires a positive sample rate.");
end
x = double(x);
y = x;
beforeHash = sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(y));

cfoHz = double(sixgr.util.structGet(cfg, "rf.cfo_Hz", ...
    sixgr.util.structGet(cfg, "phy.impairments.cfoHz", 0)));
iqEnabled = logical(sixgr.util.structGet(cfg, "rf.iqImbalance.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.iqImbalanceEnabled", false)));
gainImb = double(sixgr.util.structGet(cfg, "rf.iqImbalance.gainImbalance_dB", ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.ampImb_dB", ...
    sixgr.util.structGet(cfg, "lls6g.impairments.iq_amplitude_imbalance_dB", 0))));
phaseImb = double(sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImbalance_deg", ...
    sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImb_deg", ...
    sixgr.util.structGet(cfg, "lls6g.impairments.iq_phase_imbalance_deg", 0))));
paEnabled = logical(sixgr.util.structGet(cfg, "rf.pa.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)));
paBackoff = double(sixgr.util.structGet(cfg, "rf.pa.backoff_dB", ...
    sixgr.util.structGet(cfg, "lls6g.impairments.pa_output_backoff_dB", 3)));
timingOffset = double(sixgr.util.structGet(cfg, "rf.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", 0)));
adcBits = double(sixgr.util.structGet(cfg, "rf.adcBits", ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationBits", 12)));
dacBits = double(sixgr.util.structGet(cfg, "rf.dacBits", ...
    sixgr.util.structGet(cfg, "phy.impairments.dacQuantizationBits", 12)));
quantEnabled = isfinite(adcBits) && adcBits > 0 && adcBits < 16;

if cfoHz ~= 0
    n = (0:size(y, 1)-1).';
    y = y .* exp(1j * 2 * pi * cfoHz / fs .* n);
end

if iqEnabled
    g = 10.^(gainImb/20);
    phi = phaseImb * pi / 180;
    alpha = 0.5 * (1 + g * exp(-1j * phi));
    beta = 0.5 * (1 - g * exp(1j * phi));
    y = alpha .* y + beta .* conj(y);
end

if paEnabled
    xin = y .* 10.^(-paBackoff/20);
    r = abs(xin);
    sat = max(eps, localPercentile(r(:), 95));
    y = xin ./ sqrt(1 + (r ./ sat).^4);
end

if timingOffset ~= 0
    shift = round(timingOffset);
    if shift > 0
        y = [zeros(shift, size(y, 2)); y(1:end-shift, :)];
    elseif shift < 0
        shift = abs(shift);
        y = [y(shift+1:end, :); zeros(shift, size(y, 2))];
    end
end

if quantEnabled
    y = localQuantizeComplex(y, adcBits);
end

afterHash = sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(y));
evm = localEVM(x, y);
out = struct();
out.Waveform = y;
out.Row = struct( ...
    "RunId", string(p.Results.RunId), ...
    "TrialId", "positive_rf_impairment", ...
    "RFImpairmentChainId", "rf_" + extractBefore(afterHash, 13), ...
    "Direction", string(p.Results.Direction), ...
    "TxOrRxSide", string(p.Results.MeasurementPoint), ...
    "CFOEnabled", cfoHz ~= 0, ...
    "CFOHzConfigured", cfoHz, ...
    "CFOHzApplied", cfoHz, ...
    "PhaseNoiseEnabled", false, ...
    "PhaseNoiseProfileId", "disabled", ...
    "PhaseNoiseLevelApplied", NaN, ...
    "IQImbalanceEnabled", iqEnabled, ...
    "AmplitudeImbalanceDb", gainImb, ...
    "PhaseImbalanceDeg", phaseImb, ...
    "PAEnabled", paEnabled, ...
    "PAModel", localString(paEnabled, "repo_memoryless_soft_limiter", "disabled"), ...
    "BackoffDb", paBackoff, ...
    "TimingOffsetEnabled", timingOffset ~= 0, ...
    "TimingOffsetSamplesConfigured", timingOffset, ...
    "TimingOffsetSamplesApplied", round(timingOffset), ...
    "SampleClockOffsetEnabled", false, ...
    "SampleClockOffsetPpm", 0, ...
    "QuantizationEnabled", quantEnabled, ...
    "ADCBits", adcBits, ...
    "DACBits", dacBits, ...
    "WaveformBeforeHash", beforeHash, ...
    "WaveformAfterHash", afterHash, ...
    "WaveformChanged", beforeHash ~= afterHash, ...
    "EVMMeasuredDb", evm.EVMDb, ...
    "EVMMeasuredPercent", evm.EVMPercent, ...
    "StrictOk", beforeHash ~= afterHash, ...
    "TruthStatus", "real_lls_evidence", ...
    "FailureReason", localString(beforeHash ~= afterHash, "", "rf_configured_waveform_unchanged"));
out.Measurement = evm;
end

function y = localQuantizeComplex(x, bits)
levels = 2^max(1, round(bits));
scale = max(max(abs([real(x(:)); imag(x(:))])), eps);
yr = round((real(x) ./ scale) * (levels/2 - 1)) ./ (levels/2 - 1) .* scale;
yi = round((imag(x) ./ scale) * (levels/2 - 1)) ./ (levels/2 - 1) .* scale;
y = complex(yr, yi);
end

function evm = localEVM(ref, meas)
err = meas - ref;
den = sqrt(mean(abs(ref(:)).^2));
num = sqrt(mean(abs(err(:)).^2));
evmPct = 100 * num / max(den, eps);
evm = struct("EVMPercent", evmPct, "EVMDb", 20 * log10(max(evmPct / 100, eps)));
end

function p = localPercentile(x, pct)
x = sort(double(x(isfinite(x))));
if isempty(x)
    p = NaN;
    return;
end
idx = 1 + (numel(x) - 1) * max(0, min(100, pct)) / 100;
lo = floor(idx);
hi = ceil(idx);
if lo == hi
    p = x(lo);
else
    p = x(lo) + (idx - lo) * (x(hi) - x(lo));
end
end

function payload = localWaveformHashPayload(x)
payload = struct("Real", real(x(:).'), "Imag", imag(x(:).'), "Size", size(x));
end

function s = localString(cond, a, b)
if cond
    s = string(a);
else
    s = string(b);
end
end
