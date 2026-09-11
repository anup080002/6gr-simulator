function row=bindTRSFrequencyEvidence(row,out)
% Preserve receiver domain and scoring separately in the main-run adapter.
row.EstimatedCommonFrequency_Hz=double(sixgr.util.structGet(out,'EstimatedCommonFrequency_Hz',NaN));
row.EstimatedCFO_Hz=double(sixgr.util.structGet(out,'EstimatedCFO_Hz',NaN));
row.EstimatedCFO_PreCorrection_Hz=row.EstimatedCFO_Hz;
row.EstimatedOscillatorCFO_Hz=double(sixgr.util.structGet(out,'EstimatedOscillatorCFO_Hz',NaN));
row.FrequencyEstimateDomain=string(sixgr.util.structGet(out,'FrequencyEstimateDomain',""));
row.FrequencyUnambiguousHalfRange_Hz=double(sixgr.util.structGet(out,'FrequencyUnambiguousHalfRange_Hz',NaN));
row.InjectedCFO_Hz=double(sixgr.util.structGet(out,'InjectedCFO_Hz',NaN));
row.TrueCFO_Hz=NaN;
row.ResidualCFO_PostCorrection_Hz=NaN; % This receiver has not measured a corrected waveform.
row.CFOError_Hz=double(sixgr.util.structGet(out,'FrequencyError_Hz',NaN));
row.CFOErrorDefinition="common_frequency_estimate_minus_independent_scoring_reference_not_post_correction_residual";
row.CFOEstimateSource=string(sixgr.util.structGet(out,'CFOEstimateSource',""));
row.TRSCFOEstimateAvailable=logical(sixgr.util.structGet(out,'TRSCFOEstimateAvailable',false));
row.TRSEstimatedCFO_Hz=row.EstimatedCFO_Hz;
row.CFOEstimateAvailability="missing"; row.CFOValueStatus="NOT_AVAILABLE";
if row.TRSCFOEstimateAvailable
    assert(row.FrequencyEstimateDomain=="received_TRS_common_phase_frequency" && ...
        isfinite(row.EstimatedCommonFrequency_Hz) && ...
        row.EstimatedCommonFrequency_Hz==row.EstimatedCFO_Hz && isnan(row.EstimatedOscillatorCFO_Hz), ...
        'sixgr:truth:TRSFrequencyEvidenceDomain','Do not change the measured frequency domain at the runtime boundary.');
    row.CFOEstimateAvailability="available";
    row.CFOValueStatus="MEASURED_NO_INDEPENDENT_ERROR_REFERENCE";
    if isfinite(row.CFOError_Hz), row.CFOValueStatus="MEASURED_WITH_INDEPENDENT_SCORING"; end
end
end
