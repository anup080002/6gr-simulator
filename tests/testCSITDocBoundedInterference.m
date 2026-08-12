function testCSITDocBoundedInterference()
%TESTCSITDOCBOUNDEDINTERFERENCE Real receiver covariance-age qualification.
[cfg,provenance]=sixgr.csi.loadTDocConfig( ...
    "simulator/configs/csi_tdoc/bounded_qualification.yaml");
out=sixgr.csi.runInterferenceHypothesisWaveforms(cfg,provenance);
T=out.Points;
assert(height(T)==2);
assert(all(T.EvidenceClass=="LLS_CONTROLLED"));
assert(all(T.ApproximationMode=="none"));
assert(all(T.InterferenceSource== ...
    "independent_transport_block_waveform_and_channel"));
assert(all(isfinite(T.MeasuredPreEqSINRdB)) && all(isfinite(T.PostEqSINRdB)));
assert(T.CovarianceSHA256(1)~=T.CovarianceSHA256(2));
assert(T.CovarianceSource(1)=="dmrs_pilot_residual_runtime_evidence");
assert(T.CovarianceSource(2)=="previous_occasion_dmrs_residual");
assert(all(T.CovarianceApplied) && all(T.CovarianceIncludesNoise));
assert(all(T.NoiseAddedExactlyOnce) && all(strlength(T.EqualizerType)>0));
assert(height(out.CQIError)==2 && all(isfinite(out.CQIError.CQIError)));
fprintf("testCSITDocBoundedInterference: PASS (two real PDSCH occasions, measured covariance replay)\n");
end
