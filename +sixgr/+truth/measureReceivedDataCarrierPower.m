function fields=measureReceivedDataCarrierPower(prepared,context,timing)
% Physical per-branch carrier power over actual received data symbols.
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
% Repository antenna-plane samples carry sqrt(mW); Toolbox FFT is not
% unitary. Per-RE physical watts are abs(grid/Nfft)^2/1000.
gridW=double(grid)/(double(info.Nfft)*sqrt(1000));
power=reshape(sum(abs(gridW(:,symbols+1,:)).^2,1),numel(symbols),rx.NumReceiveAntennas);
branch=mean(power,1);
assert(all(isfinite(power(:))) && all(branch>0),'sixgr:truth:UnavailablePhysicalCarrierPower', ...
    'Do not fill unavailable or zero-energy receive branches with finite power.');
rssi=10*log10(branch)+30;
e.ContractVersion="received_data_carrier_power/v1";
e.Scope="received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report";
e.PowerReferencePlane="receiver_antenna_connector_pre_composite_front_end";
e.Source="actual_physical_received_IQ_OFDM_carrier_energy";
e.InputAmplitudeUnit="sqrt_mW"; e.GridAmplitudeUnit="sqrt_W";
e.FrequencyAlignment="nominal_carrier_no_oracle_CFO_correction";
e.CPIncluded=false; e.CyclicPrefixFraction=double(info.CyclicPrefixFraction);
e.Nfft=double(info.Nfft); e.NumRB=double(carrier.NSizeGrid);
e.FirstPRB0Based=double(carrier.NStartGrid);
e.SubcarrierSpacing_kHz=double(carrier.SubcarrierSpacing);
e.Bandwidth_Hz=12*e.NumRB*e.SubcarrierSpacing_kHz*1000;
e.SymbolIndices0Based=symbols; e.NumReceiveAntennas=rx.NumReceiveAntennas;
e.SymbolPowerPerAntenna_W=power; e.RSSIPerAntenna_dBm=rssi;
e.PhysicalObservationSHA256=sixgr.phy.waveform.WaveformHash.numeric(raw);
fields=struct('AllocationCarrierPowerMeasurementJSON',string(jsonencode(e)), ...
    'AllocationCarrierRSSIPerReceiveAntenna_dBm',string(jsonencode(rssi)));
end
