function tx = generateTRSWaveform(cfg)
%GENERATETRSWAVEFORM OFDM-modulate strict TRS/NZP-CSI-RS slots.

mapped = sixgr.phy.trs.mapTRSToResourceGrid(cfg);
slots = mapped.GridSlots;
wave = [];
slotRows = repmat(localSlotRow(), numel(slots), 1);
slotWaveforms = cell(numel(slots), 1);
sampleRate = NaN;
for ii = 1:numel(slots)
    [slotWave, info] = sixgr.phy.waveform.ofdmModulate(slots(ii).Carrier, slots(ii).Grid);
    if isfield(info, "SampleRate")
        sampleRate = double(info.SampleRate);
    end
    startSample = size(wave, 1) + 1;
    wave = [wave; slotWave]; %#ok<AGROW>
    endSample = size(wave, 1);
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
