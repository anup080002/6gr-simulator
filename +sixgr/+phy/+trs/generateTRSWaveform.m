function tx = generateTRSWaveform(cfg)
%GENERATETRSWAVEFORM OFDM-modulate strict TRS/NZP-CSI-RS slots.

mapped = sixgr.phy.trs.mapTRSToResourceGrid(cfg);
slots = mapped.GridSlots;
slotNumbers = double([slots.Slot]);
if isempty(slotNumbers) || any(~isfinite(slotNumbers)) || ...
        any(slotNumbers < 0 | slotNumbers ~= fix(slotNumbers)) || ...
        any(diff(slotNumbers) <= 0)
    error("sixgr:phy:trs:InvalidSlotTimeline", ...
        "TRS waveform slots must be nonnegative, unique and chronological.");
end
% Keep the actual elapsed time between configured resources. Zero grids here
% are this transmitter's idle contribution, not fabricated receive samples.
firstSlot = slotNumbers(1);
numSlots = slotNumbers(end)-firstSlot+1;
carrier = slots(1).Carrier;
symbolsPerSlot = double(carrier.SymbolsPerSlot);
portGrid = zeros(size(slots(1).Grid,1),numSlots*symbolsPerSlot, ...
    size(slots(1).Grid,3),"like",slots(1).Grid);
for ii = 1:numel(slots)
    symbolRange = (slotNumbers(ii)-firstSlot)*symbolsPerSlot+(1:symbolsPerSlot);
    portGrid(:,symbolRange,:) = slots(ii).Grid;
end
[wave,info] = sixgr.phy.waveform.ofdmModulate(carrier,portGrid);
sampleRate = double(info.SampleRate);
% Toolbox symbol lengths use the IFFT clock and cover a subframe. Select
% the actual starting slot's CP pattern; high numerologies need not have
% equal sample counts in every slot.
pattern = double(info.SymbolLengths(:).');
cpPattern = double(info.CyclicPrefixLengths(:).');
symbols = mod(firstSlot*symbolsPerSlot+(0:size(portGrid,2)-1),numel(pattern))+1;
sampleScale = sampleRate/(double(info.Nfft)*double(carrier.SubcarrierSpacing)*1000);
boundaries = [0 cumsum(pattern(symbols))*sampleScale];
if any(abs(boundaries-round(boundaries)) > 1e-7) || ...
        round(boundaries(end)) ~= size(wave,1)
    error("sixgr:phy:trs:SampleTimelineMismatch", ...
        "TRS slot boundaries must match the actual OFDM sample clock and waveform extent.");
end
boundaries = round(boundaries);
info.SymbolLengths = pattern(symbols);
info.CyclicPrefixLengths = cpPattern(symbols);
slotRows = repmat(localSlotRow(), numel(slots), 1);
slotWaveforms = cell(numel(slots), 1);
for ii = 1:numel(slots)
    firstSymbol = (slotNumbers(ii)-firstSlot)*symbolsPerSlot;
    startSample = boundaries(firstSymbol+1)+1;
    endSample = boundaries(firstSymbol+symbolsPerSlot+1);
    slotWave = wave(startSample:endSample,:);
    slotWaveforms{ii} = slotWave;
    slotRows(ii) = localSlotRow();
    slotRows(ii).RunId = string(cfg.RunId);
    slotRows(ii).ConfigHash = string(cfg.ConfigHash);
    slotRows(ii).Slot = double(slots(ii).Slot);
    slotRows(ii).StartSample1Based = double(startSample);
    slotRows(ii).EndSample1Based = double(endSample);
    slotRows(ii).NumSamples = double(size(slotWave, 1));
    slotRows(ii).NRE = double(slots(ii).NRE);
    slotRows(ii).SampleRateHz = double(sampleRate);
end

tx = struct();
tx.Config = cfg;
tx.Waveform = wave;
tx.SignalPower = mean(abs(double(wave(:))).^2, "omitnan");
tx.SampleRateHz = double(sampleRate);
tx.FirstSlot0Based = firstSlot;
tx.PortGrid = portGrid;
tx.OFDM = info;
tx.SampleTimelineSource = "configured_slots_actual_ofdm_symbol_lengths";
tx.GridSlots = slots;
tx.SlotResources = mapped.SlotResources;
tx.SlotWaveforms = slotWaveforms;
tx.SlotTable = struct2table(slotRows, "AsArray", true);
tx.ResourceMappingTable = mapped.ResourceMappingTable;
tx.TruthStatus = "real_lls_evidence";
end

function row = localSlotRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, "StartSample1Based", NaN, ...
    "EndSample1Based", NaN, "NumSamples", NaN, "NRE", NaN, "SampleRateHz", NaN);
end
