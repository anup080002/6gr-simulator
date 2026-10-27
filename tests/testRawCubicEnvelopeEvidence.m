function ok=testRawCubicEnvelopeEvidence()
% Analytic envelope moments plus the actual link-metric JSON producer.
x=[0;0;0;2];
T=sixgr.phy.waveform.PAPRMeasurement.measure([x 1e-20*x ones(4,1) zeros(4,1)],1);
assert(max(abs(T.NormalizedEnvelopeSixthMoment(1:3)-[16;16;1]))<1e-12);
assert(max(abs(T.RawCubicEnvelope_dB(1:3)-10*log10([16;16;1])))<1e-12);
assert(isnan(T.RawCubicEnvelope_dB(4))&&T.MeasurementStatus(4)=="undefined_zero_power");
assert(~any(T.CalibratedCubicMetricAvailable|T.RFConformanceQualified));
tx=struct('Waveform',[x ones(4,1)],'Modulation','QPSK');
metrics=sixgr.link.deriveModulationTrackingMetrics(tx,struct(),struct(),'DL');
payload=jsondecode(metrics.PAPRMeasurementJSON); e=payload.PerPort;
assert(numel(e)==2&&isequal([e.NormalizedEnvelopeSixthMoment],[16 1]));
assert(~any([e.CalibratedCubicMetricAvailable]));
assert(all(strlength(string({e.InputWaveformSHA256}))==64));
ok=true; fprintf('RAW_CUBIC_ENVELOPE_EVIDENCE_PASS\n');
end
