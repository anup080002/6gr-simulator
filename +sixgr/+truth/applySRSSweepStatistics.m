function row=applySRSSweepStatistics(row,measurements)
% Publish only independently referenced SRS NMSE. Correlated runtime
% observations (or one fixed-point measurement) do not establish a CI.
arguments
    row (1,1) struct
    measurements
end
if isstruct(measurements)
    assert(isscalar(measurements),'sixgr:truth:InvalidSRSSweepMeasurement', ...
        'Supply one actual receiver output or its original trial table.');
    fields={'NMSE_dB','ChannelNMSEReferenceAvailable'};
    if all(isfield(measurements,fields))
        measurements=table(measurements.NMSE_dB,measurements.ChannelNMSEReferenceAvailable, ...
            'VariableNames',fields);
    else
        measurements=table(); % No original reference authority, no primary metric.
    end
end
assert(istable(measurements),'sixgr:truth:InvalidSRSSweepMeasurement', ...
    'Use actual SRS trial rows, not synthesized performance samples.');
summary=sixgr.truth.summarizeSRSChannelQualification(measurements);
row.SRS_NMSE_dB=summary.NMSE_dB;
row.SRS_TrialCount=double(summary.MeasuredTrials);
row.SRS_NMSE_CI_Low=NaN;
row.SRS_NMSE_CI_High=NaN;
end
