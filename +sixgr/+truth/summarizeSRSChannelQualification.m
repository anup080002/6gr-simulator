function summary=summarizeSRSChannelQualification(T)
% Keep measurement availability separate from channel qualification.
arguments
    T table
end
summary=struct('NMSE_dB',NaN,'MeasurementAvailable',false, ...
    'MeasuredTrials',0,'QualifiedTrials',0,'FailedTrials',0, ...
    'UnqualifiedTrials',height(T),'AnyQualifiedTrial',false, ...
    'AllTrialsQualified',false, ...
    'NMSEAggregation',"equal_trial_mean_linear_normalized_error");
vars=string(T.Properties.VariableNames);
if isempty(T) || ~ismember('NMSE_dB',vars), return; end
nmse=T.NMSE_dB;
assert(isnumeric(nmse) && isreal(nmse) && size(nmse,2)==1, ...
    'sixgr:truth:InvalidSRSNMSEColumn','Each trial needs one real NMSE value.');
valid=isfinite(nmse) | nmse==-Inf; % Exact zero error is -Inf dB.
summary.MeasuredTrials=nnz(valid);
summary.MeasurementAvailable=any(valid);
if any(valid)
    values=double(nmse(valid)); peak=max(values);
    summary.NMSE_dB=peak;
    if isfinite(peak)
        summary.NMSE_dB=peak+10*log10(mean(10.^((values-peak)/10)));
    end
end
if ~ismember('Status',vars), return; end
status=upper(strtrim(string(T.Status)));
qualified=valid & status=="PASS";
if ismember('ChannelNMSEThreshold_dB',vars)
    threshold=double(T.ChannelNMSEThreshold_dB);
    qualified=qualified & isfinite(threshold) & nmse<=threshold;
end
summary.QualifiedTrials=nnz(qualified);
summary.FailedTrials=nnz(status=="FAIL" | status=="CRASH");
summary.UnqualifiedTrials=height(T)-summary.QualifiedTrials;
summary.AnyQualifiedTrial=any(qualified);
summary.AllTrialsQualified=all(qualified);
end
