function rx = applyTRSChannel(tx, cfg, varargin)
%APPLYTRSCHANNEL Apply measured strict TRS channel/noise impairments.

p = inputParser;
p.FunctionName = "sixgr.phy.trs.applyTRSChannel";
addRequired(p, "tx", @isstruct);
addRequired(p, "cfg", @isstruct);
addParameter(p, "SNRdB", double(sixgr.util.structGet(cfg, "HighSNRdB", 35)), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "TimingOffsetSamples", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "CFOHz", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "FaultMode", "normal", @(x) ischar(x) || isstring(x));
addParameter(p, "Seed", 240617, @(x) isnumeric(x) && isscalar(x));
parse(p, tx, cfg, varargin{:});
opt = p.Results;

faultMode = lower(strtrim(string(opt.FaultMode)));
rng(round(double(opt.Seed)), "twister");
[wave, gridSlots] = localFaultedWaveform(tx, faultMode);
if faultMode == "no_signal"
    wave = zeros(size(wave), "like", wave);
end
timingOffset = round(double(opt.TimingOffsetSamples));
wave = localApplyTimingOffset(wave, timingOffset);
sampleRate = double(tx.SampleRateHz);
cfoHz = double(opt.CFOHz);
if isfinite(cfoHz) && cfoHz ~= 0
    n = (0:size(wave, 1)-1).';
    wave = wave .* exp(1j * 2 * pi * cfoHz .* n ./ max(sampleRate, eps));
end
[rxWave, nVar, noiseWave] = localAddNoise(wave, double(opt.SNRdB), double(tx.SignalPower));

rx = struct();
rx.Waveform = rxWave;
rx.NoiselessWaveform = wave;
rx.NoiseOnlyWaveform = noiseWave;
rx.NoiseVariance = double(nVar);
rx.AppliedAWGNSNR_dB = double(opt.SNRdB);
rx.InjectedTimingOffset_samples = double(timingOffset);
rx.InjectedCFO_Hz = double(cfoHz);
rx.FrequencyReferenceForScoring_Hz = double(cfoHz);
rx.FrequencyReferenceForScoringSource = "explicit_scalar_rotation_in_standalone_AWGN_fixture_scoring_only";
rx.FaultMode = faultMode;
rx.SampleRateHz = sampleRate;
rx.GridSlots = gridSlots;
rx.TruthStatus = "real_lls_evidence";
end

function [wave, gridSlots] = localFaultedWaveform(tx, faultMode)
gridSlots = tx.GridSlots;
if faultMode == "corrupted_symbols" || faultMode == "missing_resource_subset"
    for ii = 1:numel(gridSlots)
        ind = gridSlots(ii).Indices(:);
        if faultMode == "missing_resource_subset"
            drop = ind(1:2:end);
            gridSlots(ii).Grid(drop) = 0;
        else
            n = numel(ind);
            gridSlots(ii).Grid(ind) = (randn(n, 1) + 1i * randn(n, 1)) ./ sqrt(2);
        end
    end
    wave = [];
    for ii = 1:numel(gridSlots)
        slotWave = sixgr.phy.waveform.ofdmModulate(gridSlots(ii).Carrier, gridSlots(ii).Grid);
        wave = [wave; slotWave]; %#ok<AGROW>
    end
else
    wave = tx.Waveform;
end
end

function y = localApplyTimingOffset(x, d)
y = x;
if d > 0
    keep = max(0, size(x, 1) - d);
    if keep > 0
        y = [zeros(d, size(x, 2), "like", x); x(1:keep, :)];
    else
        y = zeros(size(x), "like", x);
    end
elseif d < 0
    dAbs = abs(d);
    keepStart = min(size(x, 1) + 1, 1 + dAbs);
    y = [x(keepStart:end, :); zeros(min(dAbs, size(x, 1)), size(x, 2), "like", x)];
end
end

function [y, nVar, noise] = localAddNoise(x, snrDb, referencePower)
if ~(isfinite(referencePower) && referencePower > 0)
    referencePower = mean(abs(double(x(:))).^2, "omitnan");
end
if ~(isfinite(referencePower) && referencePower > 0)
    referencePower = 1;
end
nVar = referencePower ./ 10.^(double(snrDb) / 10);
noise = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
y = x + noise;
end
