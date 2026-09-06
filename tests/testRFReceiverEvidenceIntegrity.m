function ok=testRFReceiverEvidenceIntegrity()
T=sixgr.rf.runtime.RFPhaseEvidenceBuilder.receiverDynamicRange();
assert(height(T)==100 && all(isfinite(T.QuantizationSQNR_dB)));
assert(all(isnan(T.SINR_dB)) && all(isnan(T.BLER)));
assert(all(T.Source=="standalone_agc_adc_quantization_samples"));
assert(all(strlength(T.UnavailableReason)>0));
assert(all(T.AGCGainValueRole=="next_sample_gain"));
assert(all(T.Status=="PARTIAL") && all(T.QuantizationStatus=="PASS"));
R=sixgr.rf.runtime.RFPhaseEvidenceBuilder.unavailableReceiverMetrics();
assert(istable(R) && isempty(R));
assert(all(ismember(["MeasuredSINR_dB","BLER","Source"],string(R.Properties.VariableNames))));
fprintf('RF_RECEIVER_EVIDENCE_INTEGRITY_PASS: no logistic BLER or invented joint receiver rows.\n');
ok=true;
end
