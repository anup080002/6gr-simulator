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
if faultMode == "no_signal"
    wave = complex(zeros(size(wave), "like", wave));
end
timingOffset = round(double(opt.TimingOffsetSamples));
if timingOffset > 0
    wave = [zeros(timingOffset, size(wave, 2), "like", wave); wave];
    wave = wave(1:size(tx.Waveform, 1), :);
elseif timingOffset < 0
    n = min(abs(timingOffset), size(wave, 1)-1);
    wave = [wave(n+1:end, :); zeros(n, size(wave, 2), "like", wave)];
end
if faultMode == "corrupted_symbols"
    wave = wave + 4 .* std(abs(wave(:)), 0, "omitnan") .* ...
        (randn(size(wave), "like", real(wave)) + 1i .* randn(size(wave), "like", real(wave)));
end
snrDb = double(opt.SNRdB);
signalPower = mean(abs(double(wave(:))).^2, "omitnan");
if ~(isfinite(signalPower) && signalPower > 0)
    nVar = 10^(-snrDb / 10);
else
    nVar = signalPower / max(10.^(snrDb / 10), eps);
end
if isfinite(nVar) && nVar > 0
    wave = wave + sqrt(nVar / 2) .* (randn(size(wave), "like", real(wave)) + 1i .* randn(size(wave), "like", real(wave)));
end

carrier = srsCfg.ToolboxCarrier;
slotLen = floor(size(wave, 1) / max(1, numel(srsCfg.ExpectedSlotSet)));
rxSlots = repmat(struct("Slot", NaN, "RxGrid", []), numel(srsCfg.ExpectedSlotSet), 1);
for ii = 1:numel(srsCfg.ExpectedSlotSet)
    carrier.NSlot = double(srsCfg.ExpectedSlotSet(ii));
    i0 = (ii - 1) * slotLen + 1;
    i1 = min(size(wave, 1), ii * slotLen);
    slotWave = wave(i0:i1, :);
    try
        rxGrid = nrOFDMDemodulate(carrier, slotWave);
    catch
        rxGrid = complex(zeros(carrier.NSizeGrid * 12, carrier.SymbolsPerSlot, max(1, round(srsCfg.NumSRSPorts))));
    end
    rxSlots(ii).Slot = double(carrier.NSlot);
    rxSlots(ii).RxGrid = rxGrid;
end
rx = struct();
rx.RxWaveform = wave;
rx.RxSlots = rxSlots;
rx.NoiseVariance = double(nVar);
rx.AppliedAWGNSNR_dB = double(snrDb);
rx.InjectedTimingOffsetSamples = double(timingOffset);
rx.FaultMode = string(faultMode);
rx.ChannelModel = string(srsCfg.ChannelModel);
rx.ChannelFadingApplied = false;
end
