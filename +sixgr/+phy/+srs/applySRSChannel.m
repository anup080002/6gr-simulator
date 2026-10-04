function rx = applySRSChannel(tx, srsCfg, varargin)
%APPLYSRSCHANNEL Apply waveform impairments/noise to strict SRS waveform.

p = inputParser;
p.FunctionName = "sixgr.phy.srs.applySRSChannel";
addRequired(p, "tx", @isstruct);
addRequired(p, "srsCfg", @isstruct);
addParameter(p, "SNRdB", srsCfg.HighSNRdB, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "TimingOffsetSamples", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "FaultMode", "normal", @(x) ischar(x) || isstring(x));
addParameter(p, "Seed", srsCfg.Seed, @(x) isnumeric(x) && isscalar(x));
parse(p, tx, srsCfg, varargin{:});
opt = p.Results;
rng(max(1, round(double(opt.Seed))), "twister");

wave = tx.Waveform;
faultMode = lower(strtrim(string(opt.FaultMode)));
assert(isscalar(faultMode) && ismember(faultMode,["normal","no_signal","corrupted_symbols"]), ...
    'sixgr:phy:srs:UnsupportedChannelFault','Unsupported SRS fault mode: %s',faultMode);
ofdmOptions = {'Nfft',double(tx.OFDMInfo.Nfft), ...
    'SampleRate',double(tx.OFDMInfo.SampleRate), ...
    'Windowing',double(tx.OFDMInfo.Windowing)};
faultModel = "none";
appliedChannelGain = complex(1, 0);
appliedChannelGainSource = "strict_srs_awgn_unit_channel";
if faultMode == "no_signal"
    wave = complex(zeros(size(wave), "like", wave));
    appliedChannelGain = complex(0, 0);
    appliedChannelGainSource = "strict_srs_no_signal_fault";
    faultModel = "no_transmitted_signal";
elseif faultMode == "corrupted_symbols"
    % Corrupt the actual reference symbols rather than scaling a disturbance
    % by a sparse waveform's average power. Independent per-RE phase errors
    % destroy the reference sequence without boosting or removing RE energy.
    blocks = cell(numel(tx.GridSlots),1);
    for ii=1:numel(tx.GridSlots)
        faultGrid = tx.GridSlots(ii).Grid;
        indices = tx.GridSlots(ii).Indices;
        phaseError = exp(1i*2*pi*rand(size(indices)));
        faultGrid(indices) = faultGrid(indices).*phaseError;
        faultCarrier = srsCfg.ToolboxCarrier;
        faultCarrier.NSlot = double(tx.GridSlots(ii).Slot);
        blocks{ii} = sixgr.phy.waveform.ofdmModulate( ...
            faultCarrier,faultGrid,ofdmOptions{:});
    end
    wave = vertcat(blocks{:});
    assert(isequal(size(wave),size(tx.Waveform)), ...
        'sixgr:phy:srs:CorruptionWaveformShape','SRS symbol corruption changed waveform dimensions.');
    faultModel = "independent_uniform_phase_per_occupied_srs_re_v1";
end
timingOffset = round(double(opt.TimingOffsetSamples));
if timingOffset > 0
    wave = [zeros(timingOffset, size(wave, 2), "like", wave); wave];
    wave = wave(1:size(tx.Waveform, 1), :);
elseif timingOffset < 0
    n = min(abs(timingOffset), size(wave, 1)-1);
    wave = [wave(n+1:end, :); zeros(n, size(wave, 2), "like", wave)];
end
snrDb = double(opt.SNRdB);
carrier = srsCfg.ToolboxCarrier;
% Define the anchor on the transmitted SRS REs, not on a mostly empty
% waveform's average power. Retain that reference also for no-signal and
% corrupted-symbol trials: the fault must not change the noise calibration.
referenceSymbols = vertcat(tx.GridSlots.Symbols);
referenceEnergy = mean(abs(double(referenceSymbols(:))).^2);
assert(isscalar(referenceEnergy) && isfinite(referenceEnergy) && referenceEnergy>0, ...
    'sixgr:phy:srs:MissingOccupiedREEnergy', ...
    'SRS noise calibration requires the actual transmitted reference symbols.');
[wave,noiseReference] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    wave,carrier,snrDb,'SignalEnergyPerOccupiedRE',referenceEnergy, ...
    'OFDMOptions',ofdmOptions);
nVar = double(noiseReference.SampleNoiseVariance);

slotLen = floor(size(wave, 1) / max(1, numel(srsCfg.ExpectedSlotSet)));
rxSlots = repmat(struct("Slot", NaN, "RxGrid", []), numel(srsCfg.ExpectedSlotSet), 1);
for ii = 1:numel(srsCfg.ExpectedSlotSet)
    carrier.NSlot = double(srsCfg.ExpectedSlotSet(ii));
    i0 = (ii - 1) * slotLen + 1;
    i1 = min(size(wave, 1), ii * slotLen);
    slotWave = wave(i0:i1, :);
    rxGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, slotWave, ...
        'Nfft',double(tx.OFDMInfo.Nfft),'SampleRate',double(tx.OFDMInfo.SampleRate));
    rxSlots(ii).Slot = double(carrier.NSlot);
    rxSlots(ii).RxGrid = rxGrid;
end
rx = struct();
rx.RxWaveform = wave;
rx.RxSlots = rxSlots;
rx.NoiseVariance = double(nVar);
rx.NoiseVarianceDomain = "sample_domain_complex_variance";
rx.GridNoiseVariance = double(noiseReference.GridNoiseVariance);
rx.NoiseReference = noiseReference;
rx.AppliedAWGNSNR_dB = double(snrDb);
rx.InjectedTimingOffsetSamples = double(timingOffset);
rx.FaultMode = string(faultMode);
rx.FaultModel = faultModel;
rx.ConfiguredChannelModel = string(srsCfg.ChannelModel);
rx.ChannelModel = "AWGN";
rx.ChannelFadingApplied = false;
rx.AppliedChannelGain = appliedChannelGain;
rx.AppliedChannelGainSource = appliedChannelGainSource;
end
