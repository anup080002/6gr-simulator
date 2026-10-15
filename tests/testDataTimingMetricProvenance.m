function ok=testDataTimingMetricProvenance()
% Retain measured numbers; disclose their reference instead of relabeling
% an earliest-arrival displacement as correlation-peak acquisition error.
T=table(true(3,1),false(3,1),[16;16;16],[16;16;16],[-8;-15;NaN], ...
    ["prepared_tx_minus_rx_observation_origin_plus_executed_channel_filter_and_minimum_path_delay_plus_applied_RF_timing_offset"; ...
     "injected_RF_offset_not_channel_correlation_peak";""], ...
    'VariableNames',{'TimingEstimateUsed','UseIdealTimingSync', ...
    'EstimatedTimingOffset_PreCorrection_samples','AppliedTimingCorrection_samples', ...
    'TimingError_samples','TimingReferenceSource'});
out=sixgr.util.applyLLSRawTrialLifecycle(T);
assert(isequaln(out.TimingError_samples,T.TimingError_samples));
assert(isequal(out.AppliedTimingCorrection_samples,T.AppliedTimingCorrection_samples));
assert(out.TimingMetricRole(1)=="earliest_arrival_relative_alignment_not_correlation_peak_accuracy");
assert(out.TimingMetricRole(2)=="RF_offset_relative_alignment_not_channel_correlation_peak_accuracy");
assert(out.TimingMetricRole(3)=="reference_definition_unavailable_not_timing_qualification");
assert(all(out.TimingErrorDefinition=="declared_timing_reference_minus_applied_sample_correction"));
assert(out.TimingValueStatus(3)=="PARTIAL");
ok=true;
end
