function ok=testTRSFrequencyExportDomain
out=struct('EstimatedCommonFrequency_Hz',251,'EstimatedCFO_Hz',251, ...
    'EstimatedOscillatorCFO_Hz',NaN,'FrequencyEstimateDomain', ...
    "received_TRS_common_phase_frequency",'TRSCFOEstimateAvailable',true, ...
    'FrequencyUnambiguousHalfRange_Hz',1750,'InjectedCFO_Hz',120, ...
    'CFOEstimateSource',"received_two_symbol_TRS_correlation");
row=sixgr.truth.bindTRSFrequencyEvidence(struct(),out);
assert(row.EstimatedCommonFrequency_Hz==251 && isnan(row.CFOError_Hz) && ...
    isnan(row.TrueCFO_Hz) && isnan(row.EstimatedOscillatorCFO_Hz) && ...
    isnan(row.ResidualCFO_PostCorrection_Hz));
changed=out; changed.InjectedCFO_Hz=-9000;
other=sixgr.truth.bindTRSFrequencyEvidence(struct(),changed);
assert(other.EstimatedCFO_Hz==row.EstimatedCFO_Hz && isnan(other.CFOError_Hz));
out.FrequencyError_Hz=1;
scored=sixgr.truth.bindTRSFrequencyEvidence(struct(),out);
assert(scored.CFOError_Hz==1 && isnan(scored.ResidualCFO_PostCorrection_Hz));
out.CFOCorrectionEnabled=true; out.CFOCorrectionApplied=true;
out.CFOCorrectionApplied_Hz=251; out.CFOCorrectionSampleOrigin=430080;
out.CFOCorrectionSource="received_TRS_window_cyclic_prefix_frequency_estimator_on_absolute_received_sample_clock";
out.TRSFrequencyEvidenceJSON="received_sample_evidence";
corrected=sixgr.truth.bindTRSFrequencyEvidence(struct(),out);
assert(corrected.CFOCorrectionApplied && corrected.CFOCorrectionApplied_Hz==251 && ...
    corrected.CFOCorrectionSampleOrigin==430080 && ...
    corrected.TRSFrequencyEvidenceJSON==out.TRSFrequencyEvidenceJSON && ...
    isnan(corrected.ResidualCFO_PostCorrection_Hz), ...
    'An applied correction is not an independently measured residual CFO.');
path=[tempname '.csv']; writetable(struct2table([row;scored]),path);
saved=readtable(path,'TextType','string');
assert(all(saved.EstimatedCommonFrequency_Hz==251) && ...
    all(isnan(saved.EstimatedOscillatorCFO_Hz)) && ...
    all(isnan(saved.ResidualCFO_PostCorrection_Hz)) && ...
    all(saved.FrequencyEstimateDomain==out.FrequencyEstimateDomain));
bad=out; bad.EstimatedOscillatorCFO_Hz=251;
try
    sixgr.truth.bindTRSFrequencyEvidence(struct(),bad);
    error('test:MissingFailure','Common frequency was accepted as oscillator CFO.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:truth:TRSFrequencyEvidenceDomain'));
end
source=fileread(fullfile('+sixgr','+truth','runWaveformLinkBundle.m'));
assert(contains(source,'r = sixgr.truth.bindTRSFrequencyEvidence(r,out);'));
fprintf('TRS_FREQUENCY_EXPORT_DOMAIN_PASS: common frequency, unavailable oscillator/residual, CSV lineage.\n');
ok=true;
end
