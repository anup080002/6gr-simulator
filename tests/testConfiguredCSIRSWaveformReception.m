function ok=testConfiguredCSIRSWaveformReception()
% Actual CSI-only OFDM with unknown capture offset, no PDSCH/DCI authority.
% Cover the 5 MHz and 400 MHz carrier grids, including the higher-numerology
% short-CP slot. These remain receiver components, not scenario acceptance.
cases=[15 25;120 264];
for index=1:size(cases,1)
    localCase(cases(index,1),cases(index,2));
end
ok=true;
end

function localCase(scs,nPRB)
[passed,fixture]=testConfiguredCSIRSGridReception(scs,nPRB); assert(passed);
carrier=fixture.Carrier; cfg=fixture.Config;
if scs==120 && nPRB==264
    ofdm=nrOFDMInfo(carrier);
    assert(ofdm.Nfft==4096 && fixture.SampleRateHz==491.52e6);
end
delay=37; searchEnd=73;
signal=[zeros(delay,2);fixture.Waveform;zeros(searchEnd-delay,2)];
capture=sixgr.phy.waveform.addOccupiedREAWGN(signal,carrier,20, ...
    'Seed',924522,'SignalEnergyPerOccupiedRE',1);
rx=sixgr.phy.refsig.receiveCSIRSWaveform(carrier,cfg,capture,capture,[0 searchEnd],struct());
assert(rx.ReceiveTiming.TimingOffsetSamples==delay && ...
    ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
assert(rx.CSIRSObservation.Observed && rx.CSIRSObservation.ChannelEstimateAvailable && ...
    rx.CSIRSObservation.CSIMeasurementStateAvailable && ~rx.PDSCHDecodeAttempted);
assert(~rx.ReceiverTrackingCorrection.CFOCorrectionApplied && ...
    isnan(rx.ReceiverTrackingCorrection.EstimatedCFO_Hz));
poison=cfg; poison.phy.pdsch=struct('enable',false,'numLayers',99,'mcsIndex',99);
same=sixgr.phy.refsig.receiveCSIRSWaveform(carrier,poison,capture,capture,[0 searchEnd],struct());
assert(isequaln(rx.CSIRSChannelEstimate,same.CSIRSChannelEstimate) && ...
    rx.CSIMeasurementState.Digest==same.CSIMeasurementState.Digest);
% A known injected CFO is scoring-only: neither it nor the known delay is
% passed to the receiver. Its cyclic-prefix estimator observes real samples.
frequency=700;
offsetSignal=signal.*exp(1i*2*pi*frequency*(0:size(signal,1)-1).'/fixture.SampleRateHz);
cfg.phy.rx.cfoCorrectionEnabled=true;
cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
tracked=sixgr.phy.refsig.receiveCSIRSWaveform( ...
    carrier,cfg,offsetSignal,offsetSignal,[0 searchEnd],struct());
assert(tracked.ReceiverTrackingCorrection.CFOCorrectionApplied && ...
    abs(tracked.ReceiverTrackingCorrection.EstimatedCFO_Hz-frequency)<1, ...
    'The CSI-only receiver must estimate CFO, never copy its configured value.');
assert(tracked.ReceiveTiming.TimingOffsetSamples==delay);
% The installed two-symbol method must not silently become CP estimation
% when this resource has only one pilot-bearing OFDM symbol.
cfg.phy.impairments.cfoEstimationMethod='reference_symbol_phase_slope';
limited=sixgr.phy.refsig.receiveCSIRSWaveform( ...
    carrier,cfg,offsetSignal,offsetSignal,[0 searchEnd],struct());
assert(~limited.ReceiverTrackingCorrection.CFOEstimateAvailable && ...
    ~limited.ReceiverTrackingCorrection.CFOCorrectionApplied && ...
    isnan(limited.ReceiverTrackingCorrection.EstimatedCFO_Hz));
fprintf('CONFIGURED_CSIRS_WAVEFORM_PASS scs=%g PRB=%g fs=%g timing=%g independent_reference=1 no_PDSCH=1 measured_CFO=%g\n', ...
    scs,nPRB,fixture.SampleRateHz,rx.ReceiveTiming.TimingOffsetSamples, ...
    tracked.ReceiverTrackingCorrection.EstimatedCFO_Hz);
end
