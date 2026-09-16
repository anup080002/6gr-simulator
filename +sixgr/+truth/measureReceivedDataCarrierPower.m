function fields=measureReceivedDataCarrierPower(prepared,context,timing)
% Per-branch carrier power over actual received data symbols, with explicit units.
% This allocation-window diagnostic is NOT the UE SMTC/CSI NR-RSSI report.
% Never turn receiver-normalized amplitudes or a configured SNR into watts.
rx=context.Observation; pre=context.PhysicalMeasurementObservation;
e=sixgr.truth.receivedDataSymbolTiming(prepared,rx,timing,rx.EndSampleExclusive);
prepared.readObservation(pre,rx.NumReceiveAntennas,'receiver');
assert(pre.StartSample==rx.StartSample && pre.EndSampleExclusive==rx.EndSampleExclusive && ...
    pre.SampleRateHz==rx.SampleRateHz,'sixgr:truth:PhysicalPowerClockMismatch', ...
    'Physical and digital observations must share the same complete receiver interval.');
raw=pre.readComplete();
aligned=raw(timing.AppliedTimingCorrectionSamples+(1:timing.DemodulatedSampleCount),:);
carrier=prepared.Tx.Carrier;
[grid,info]=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned,'SampleRate',prepared.SampleRateHz);
assert(size(grid,1)==12*carrier.NSizeGrid && size(grid,2)==carrier.SymbolsPerSlot && ...
    size(grid,3)==rx.NumReceiveAntennas,'sixgr:truth:PhysicalPowerGridMismatch', ...
    'Retain the full executed carrier grid and all physical receive branches.');
symbols=e.SymbolAllocation(1)+(0:e.SymbolAllocation(2)-1);
powerEvidence=sixgr.truth.measureDataCarrierGridPower(grid,double(info.Nfft),symbols,prepared.InputConfig);
for name=string(fieldnames(powerEvidence)).'
    e.(name)=powerEvidence.(name);
end
e.Scope="received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report";
e.FrequencyAlignment="nominal_carrier_no_oracle_CFO_correction";
e.CPIncluded=false; e.CyclicPrefixFraction=double(info.CyclicPrefixFraction);
e.Nfft=double(info.Nfft); e.NumRB=double(carrier.NSizeGrid);
e.FirstPRB0Based=double(carrier.NStartGrid);
e.SubcarrierSpacing_kHz=double(carrier.SubcarrierSpacing);
e.Bandwidth_Hz=12*e.NumRB*e.SubcarrierSpacing_kHz*1000;
e.SymbolIndices0Based=symbols; e.NumReceiveAntennas=rx.NumReceiveAntennas;
e.PhysicalObservationSHA256=sixgr.phy.waveform.WaveformHash.numeric(raw);
fields=struct('AllocationCarrierPowerMeasurementJSON',string(jsonencode(e)), ...
    'AllocationCarrierRSSIPerReceiveAntenna_dBm',"", ...
    'AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es',"");
if isfield(e,'RSSIPerAntenna_dBm')
    fields.AllocationCarrierRSSIPerReceiveAntenna_dBm=string(jsonencode(e.RSSIPerAntenna_dBm));
else
    fields.AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es= ...
        string(jsonencode(e.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es));
end
end
