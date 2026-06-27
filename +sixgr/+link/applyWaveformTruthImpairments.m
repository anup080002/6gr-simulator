function [y, replay, state] = applyWaveformTruthImpairments(x, snr_dB, state, cfg, tx, txInfo)
%APPLYWAVEFORMTRUTHIMPAIRMENTS Apply the authoritative waveform impairment path.

fs = double(sixgr.util.structGet(state, "SampleRate_Hz", localResolveSampleRate(tx, txInfo)));
truthMode = string(sixgr.util.structGet(state, "TruthMode", sixgr.link.resolveTruthMode(cfg)));
y = x;

replay = struct( ...
    "RawWaveform", x, ...
    "CorrectedWaveform", x, ...
    "InjectedCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "InjectedTimingOffset_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "ResidualTimingError_PostCorrection_samples", NaN, ...
    "SampleRate_Hz", fs, ...
    "CFOCorrectionApplied", false, ...
    "InjectedNoiseVariance", NaN, ...
    "LargeScaleGain_dB", double(sixgr.util.structGet(state, "LargeScaleGain_dB", 0)), ...
    "Pathloss_dB", double(sixgr.util.structGet(state, "Pathloss_dB", NaN)), ...
    "ShadowFading_dB", double(sixgr.util.structGet(state, "ShadowFading_dB", NaN)), ...
    "O2ILoss_dB", double(sixgr.util.structGet(state, "O2ILoss_dB", NaN)), ...
    "LOS", double(sixgr.util.structGet(state, "LOS", NaN)), ...
    "InterferenceSIR_dB", double(sixgr.util.structGet(state, "InterferenceSIR_dB", NaN)), ...
    "InjectedInterferenceVariance", NaN, ...
    "PhaseNoiseConfigured", localPhaseNoiseConfigured(cfg), ...
    "PhaseNoiseApplied", false, ...
    "PhaseNoiseBackend", "disabled", ...
    "PhaseNoiseTruthClassification", "disabled", ...
    "PhaseNoiseExecutionStatus", "not_configured");

if isstruct(state)
    [y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state);
    chFields = fieldnames(channelReplay);
    for chIdx = 1:numel(chFields)
        replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
    end
end

gain_dB = double(sixgr.util.structGet(state, "LargeScaleGain_dB", 0));
if isfinite(gain_dB) && gain_dB ~= 0
    y = y .* cast(10 .^ (gain_dB / 20), "like", y);
end

timingOffset = localResolveInjectedTimingOffsetSamples(cfg);
replay.InjectedTimingOffset_samples = timingOffset;
if timingOffset ~= 0
    y = localApplyTimingOffset(y, timingOffset);
end

cfoHz = localResolveInjectedCFOHz(cfg);
replay.InjectedCFO_Hz = cfoHz;
if isfinite(cfoHz) && cfoHz ~= 0
    y = localApplyCFO(y, fs, cfoHz);
end
if localPhaseNoiseConfigured(cfg)
    [y, replay] = localApplyPhaseNoise(y, replay, cfg, fs);
end
replay.RawWaveform = y;

estCfoHz = localEstimateWaveformCFO(x, y, fs, timingOffset);
replay.EstimatedCFO_PreCorrection_Hz = estCfoHz;
if localShouldCorrectCFO(cfg, truthMode) && isfinite(estCfoHz) && estCfoHz ~= 0
    y = localApplyCFO(y, fs, -estCfoHz);
    replay.CFOCorrectionApplied = true;
    replay.ResidualCFO_PostCorrection_Hz = localEstimateWaveformCFO(x, y, fs, timingOffset);
else
    replay.ResidualCFO_PostCorrection_Hz = estCfoHz;
end
replay.CorrectedWaveform = y;

sir_dB = double(sixgr.util.structGet(state, "InterferenceSIR_dB", NaN));
if isfinite(sir_dB)
    sigPow = mean(abs(y(:)).^2, "omitnan");
    if isfinite(sigPow) && sigPow > 0
        interfVar = sigPow ./ max(10 .^ (sir_dB / 10), eps);
        interf = sqrt(interfVar / 2) .* (randn(size(y), "like", real(y)) + 1i * randn(size(y), "like", real(y)));
        y = y + cast(interf, "like", y);
        replay.InjectedInterferenceVariance = double(interfVar);
    end
end

effectiveSnr_dB = double(snr_dB) + gain_dB;
[y, replay.InjectedNoiseVariance] = localAddAwgnAtEffectiveSNR(y, effectiveSnr_dB);
end

function [y, nVar] = localAddAwgnAtEffectiveSNR(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
    fs = 30.72e6;
else
    fs = double(fs);
end
end

function tf = localShouldCorrectCFO(cfg, truthMode)
tf = logical(sixgr.util.structGet(cfg, "phy.rx.cfoCompensation", false));
if truthMode == "abstract_fast"
    tf = false;
end
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0)));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function y = localApplyTimingOffset(x, timingOffset)
y = sixgr.util.applyFractionalSampleDelay(x, timingOffset);
end

function y = localApplyCFO(x, sampleRateHz, cfoHz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
y = y .* cast(rot, "like", y);
end

function tf = localPhaseNoiseConfigured(cfg)
tf = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "impairments.phase_noise_enabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "lls6g.resolvedConfig.impairments.phase_noise_enabled", false));
end

function [y, replay] = localApplyPhaseNoise(x, replay, cfg, fs)
y = x;
if ~(isfinite(double(fs)) && double(fs) > 0)
    replay.PhaseNoiseExecutionStatus = "configured_but_sample_rate_unavailable";
    return;
end
seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 3001;
pn = sixgr.rf.PhaseNoiseModel(cfg, double(fs), seed);
if ~logical(pn.Enable)
    replay.PhaseNoiseExecutionStatus = "disabled";
    return;
end
y = pn.apply(x, double(fs));
replay.PhaseNoiseApplied = true;
replay.PhaseNoiseBackend = char(pn.Backend);
replay.PhaseNoiseTruthClassification = char(pn.TruthClassification);
replay.PhaseNoiseExecutionStatus = "applied_sample_domain_phase_noise";
end

function estCFO_Hz = localEstimateWaveformCFO(txWave, rxWave, sampleRateHz, timingOffset)
estCFO_Hz = NaN;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0) || isempty(txWave) || isempty(rxWave)
    return;
end

txRef = localCollapseAntennas(txWave);
rxRef = localCollapseAntennas(rxWave);
startTx = 1;
startRx = 1;
if timingOffset > 0
    startRx = 1 + timingOffset;
elseif timingOffset < 0
    startTx = 1 + abs(timingOffset);
end
if startTx > numel(txRef) || startRx > numel(rxRef)
    estCFO_Hz = 0;
    return;
end

N = min(numel(txRef) - startTx + 1, numel(rxRef) - startRx + 1);
if N < 16
    estCFO_Hz = 0;
    return;
end
txRef = double(txRef(startTx:startTx+N-1));
rxRef = double(rxRef(startRx:startRx+N-1));
prodSig = rxRef .* conj(txRef);
mask = isfinite(real(prodSig)) & isfinite(imag(prodSig));
prodSig = prodSig(mask);
if numel(prodSig) < 16
    estCFO_Hz = 0;
    return;
end

n = (0:numel(prodSig)-1).';
phase = unwrap(angle(prodSig(:)));
if numel(phase) < 16
    estCFO_Hz = 0;
    return;
end
try
    p = polyfit(double(n) ./ double(sampleRateHz), double(phase), 1);
    estCFO_Hz = double(p(1)) / (2 * pi);
catch
    estCFO_Hz = 0;
end
if ~isfinite(estCFO_Hz)
    estCFO_Hz = 0;
end
end

function y = localCollapseAntennas(x)
if isempty(x)
    y = zeros(0, 1);
    return;
end
if isvector(x)
    y = x(:);
else
    y = mean(x, 2, "omitnan");
end
end
