function [value, source] = receiverNoiseMeasurement(estimate, estimationInfo, measuredSource, varargin)
%RECEIVERNOISEMEASUREMENT Keep supplied/model noise out of measured exports.
% This classifies an existing estimator result; it does not calculate noise,
% alter receiver weighting, or replace unavailable measurements.
ip=inputParser;
ip.addParameter('UnitAWGNShortcut',false,@(x)islogical(x)&&isscalar(x));
ip.parse(varargin{:});
value=NaN;
source="unavailable_invalid_independent_dmrs_noise_estimate";
if ip.Results.UnitAWGNShortcut
    source="unavailable_unit_awgn_configured_noise_not_receiver_measurement";
elseif logical(sixgr.util.structGet(estimationInfo,'EstimatorUsesTrueChannel',false)) || ...
        logical(sixgr.util.structGet(estimationInfo,'OracleTestMode',false))
    source="unavailable_oracle_noise_not_receiver_measurement";
elseif logical(sixgr.util.structGet(estimationInfo,'FullCovarianceLMMSE',false)) || ...
        strcmpi(string(sixgr.util.structGet(estimationInfo,'Method',"")),"lmmse")
    % channelEstimate's full-covariance LMMSE branch accepts/configures nVar;
    % its returned nVar is not a newly measured pilot-noise statistic.
    source="unavailable_lmmse_supplied_noise_not_receiver_measurement";
elseif isnumeric(estimate) && isscalar(estimate) && isreal(estimate) && ...
        isfinite(estimate) && estimate>=0
    assert(isstring(measuredSource)&&isscalar(measuredSource)&& ...
        ~ismissing(measuredSource)&&strlength(measuredSource)>0, ...
        'sixgr:phy:rx:MissingMeasuredNoiseSource', ...
        'A measured noise value requires its executed estimator source.');
    value=double(estimate);
    source=measuredSource;
end
end
