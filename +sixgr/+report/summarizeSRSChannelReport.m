function [statistics,diagnostics]=summarizeSRSChannelReport(T)
% Reference-qualified descriptive SRS error statistics, not trial inference.
% The p95 is the empirical inverse CDF (nearest rank) of normalized error
% POWER. Sorting its dB representation is exactly equivalent, including
% zero error (-Inf); there is no interpolation in logarithmic units.
arguments
    T table
end
for field=["NMSE_dB","ChannelNMSEReferenceAvailable","ChannelNMSEThreshold_dB"]
    if ismember(field,string(T.Properties.VariableNames))
        values=T.(field);
        assert(size(values,2)==1,'sixgr:report:InvalidSRSMeasurementColumn', ...
            '%s must retain one scalar per original trial.',field);
        T.(field)=sixgr.truth.numericMeasurementColumn(values,field);
    end
end
statistics=sixgr.truth.summarizeSRSChannelQualification(T);
statistics.MinNMSE_dB=NaN;
statistics.P95NMSE_dB=NaN;
statistics.MaxNMSE_dB=NaN;
statistics.P95Definition="empirical_inverse_CDF_of_normalized_error_power_rank_ceil_0p95_N";
statistics.StatisticalIndependenceClaimed=false;
statistics.ConfidenceIntervalAvailable=false;
if statistics.MeasurementAvailable
    valid=(isfinite(T.NMSE_dB)|T.NMSE_dB==-Inf)&T.ChannelNMSEReferenceAvailable==1;
    values=sort(double(T.NMSE_dB(valid)));
    statistics.MinNMSE_dB=values(1);
    statistics.P95NMSE_dB=values(ceil(.95*numel(values)));
    statistics.MaxNMSE_dB=values(end);
end
% This is a separate diagnostic population, never a replacement NMSE row
% or additional evidence of metric coverage. Qualification uses each
% original threshold/status; failed referenced measurements remain measured.
diagnostics=rmfield(statistics,{'NMSE_dB','MinNMSE_dB','P95NMSE_dB','MaxNMSE_dB'});
diagnostics.SourceTrialCount=height(T);
diagnostics.SourceArtifact="air_interface/csv/srs_trials.csv";
diagnostics.Scope="reference_authority_and_threshold_diagnostics_not_independent_trials";
diagnostics.CountsTowardCoverage=false;
end
