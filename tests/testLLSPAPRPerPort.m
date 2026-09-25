function ok = testLLSPAPRPerPort()
%TESTLLSPAPRPERPORT Guard against flattening multi-port waveforms for PAPR.

setup6GRSimToolkit("Verbose", false);

tx = struct();
tx.Waveform = [ones(128, 1), 10 * ones(128, 1)];
rx = struct();
cfg = struct();

[metrics, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "DL");
assert(isfinite(double(metrics.PAPR_dB)), "PAPR must be finite for a non-empty waveform.");
assert(abs(double(metrics.PAPR_dB)) < 1e-9, ...
    "PAPR must be computed per RF port; inter-port power offsets must not look like time-domain peaks.");
evidence=jsondecode(metrics.PAPRMeasurementJSON);
assert(numel(evidence.PerPort)==2 && evidence.InputWaveformSampleCount==128);
assert(isequal([evidence.PerPort.MeanPower_InputAmplitudeSquared],[1 100]));
assert(all([evidence.PerPort.OversamplingFactor]==1));
assert(string(evidence.ReferenceDomain)=="all_supplied_waveform_samples");
assert(string(evidence.MeasurementPoint)=="unspecified_supplied_tx_waveform");
assertMeasuredPAPRTrialEvidence(table(metrics.PAPR_dB,metrics.PAPRMeasurementJSON, ...
    'VariableNames',{'PAPR_dB','PAPRMeasurementJSON'}));
% The CP policy must describe the samples actually measured, in DL and UL.
cpTx=struct('Waveform',[100;1;1;1;1;100;1;1;1;1], ...
    'OFDMInfo',struct('Nfft',4,'CyclicPrefixLengths',[1 1]), ...
    'PAPRMeasurementPoint',"post_node_rf_transmitter_composite_observation");
for direction=["DL","UL"]
    [cpMetrics,~]=sixgr.link.deriveModulationTrackingMetrics(cpTx,rx,cfg,direction);
    cpEvidence=jsondecode(cpMetrics.PAPRMeasurementJSON);
    assert(cpMetrics.PAPR_dB==0 && cpEvidence.PerPort.MeasuredSampleCount==8);
    assert(string(cpEvidence.ReferenceDomain)=="ofdm_useful_samples_CP_excluded");
    assert(string(cpEvidence.MeasurementPoint)==cpTx.PAPRMeasurementPoint);
end

cfg.waveform = struct("cfr_enabled", true, "cfr_target_papr_db", 1);
[metricsCFR, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "DL");
assert(double(metricsCFR.PeakClippingEvents) == 0, ...
    "CFR clipping-event accounting must use per-port average power thresholds.");

ok = true;
end
