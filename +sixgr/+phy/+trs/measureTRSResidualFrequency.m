function out=measureTRSResidualFrequency(det,cfg,tx,receiverConfig,acquisition)
% Diagnostic after actual correction, using a DIFFERENT received observable.
% This is common phase/fading frequency, not separated oscillator CFO. No
% injected frequency or estimate-minus-applied tautology enters the result.
out=struct('ResidualCFO_EstimatedPostCorrection_Hz',NaN, ...
    'ResidualCFOEstimateAvailable',false,'ResidualCFOEstimateSource',"unavailable", ...
    'ResidualCFOEstimateRole',"received_common_frequency_not_separated_oscillator", ...
    'ResidualCFOReusesAcquisitionObservation',true, ...
    'ResidualFrequencyUsesDifferentObservable',false, ...
    'ResidualFrequencyStatus',"not_measured",'TRSResidualFrequencyEvidenceJSON',"");
if nargin==0, return; end
% Same capture, different statistic: CP acquisition is checked against the
% two TRS pilot times; pilot acquisition is checked against CP/tail pairs.
diagnostic=receiverConfig;
if contains(string(acquisition.FrequencyEstimatorSource),'cyclic_prefix')
    diagnostic.phy.impairments.cfoEstimationMethod='reference_symbol_phase_slope';
else
    diagnostic.phy.impairments.cfoEstimationMethod='cyclic_prefix';
end
residual=sixgr.phy.trs.estimateTRSFrequencyOffset(det,cfg,tx,struct(),diagnostic);
out.ResidualCFOEstimateAvailable=residual.EstimateAvailable;
out.ResidualCFO_EstimatedPostCorrection_Hz=residual.EstimatedCommonFrequency_Hz;
out.ResidualCFOEstimateSource=residual.FrequencyEstimatorSource+"_after_receiver_frequency_processing";
out.ResidualFrequencyUsesDifferentObservable=true;
out.TRSResidualFrequencyEvidenceJSON=string(jsonencode(table2struct(residual.Table)));
out.ResidualFrequencyStatus="unavailable_no_valid_independent_observable";
if residual.EstimateAvailable
    out.ResidualFrequencyStatus="measured_received_common_frequency_after_correction";
    if ~acquisition.CorrectionApplied
        out.ResidualFrequencyStatus="measured_received_common_frequency_correction_not_applied";
    end
end
end
