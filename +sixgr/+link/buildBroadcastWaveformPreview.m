function T=buildBroadcastWaveformPreview(tx,rx,snr,frame,slot,ue,cellID)
% Retain actual broadcast-window samples, independent of acquisition success.
% A window can contain SS/PBCH and system-information/control transmissions;
% these are antenna-domain traces, not data constellations or per-beam samples.
arguments
    tx (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    rx (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    snr (1,1) double
    frame (1,1) double
    slot (1,1) double
    ue (1,1) double
    cellID (1,1) double
end
assert(tx.StartSample==rx.StartSample && ...
    tx.EndSampleExclusive==rx.EndSampleExclusive && tx.SampleRateHz==rx.SampleRateHz, ...
    'sixgr:link:BroadcastPreviewClockMismatch', ...
    'Broadcast preview requires complete TX and receiver-input observations on one clock.');
x=tx.readComplete(); y=rx.readComplete();
T=table();
for branch=1:max(size(x,2),size(y,2))
    a=[]; b=[]; txIndex=NaN; rxIndex=NaN;
    if branch<=size(x,2), a=x(:,branch); txIndex=branch; end
    if branch<=size(y,2), b=y(:,branch); rxIndex=branch; end
    row=sixgr.link.buildWaveformPreviewTable('DL',snr,frame,slot,a,b,rx.SampleRateHz);
    n=height(row);
    row.AbsoluteSampleIndex=tx.StartSample+row.SampleIndex-1;
    row.Time_s=row.AbsoluteSampleIndex/rx.SampleRateHz;
    row.ObservationStartSample=repmat(rx.StartSample,n,1);
    row.ObservationEndSampleExclusive=repmat(rx.EndSampleExclusive,n,1);
    row.ObservationSampleRateHz=repmat(rx.SampleRateHz,n,1);
    row.TxAntennaIndex=repmat(txIndex,n,1);
    row.RxAntennaIndex=repmat(rxIndex,n,1);
    row.UEIndex=repmat(ue,n,1);
    row.ServingCell=repmat(cellID,n,1);
    row.ObservationKind=repmat("broadcast_window",n,1);
    row.EvidenceScope=repmat("shared_broadcast_observation_not_data_constellation",n,1);
    row.TxPlane=repmat("shared_transmitter_output_after_rf",n,1);
    row.RxPlane=repmat("broadcast_receiver_input",n,1);
    row.Source=repmat("completed_shared_waveform_observation_buffers",n,1);
    row.SNRValueRole=repmat("configured_reference_snr_not_receiver_measurement",n,1);
    T=[T;row]; %#ok<AGROW>
end
end
