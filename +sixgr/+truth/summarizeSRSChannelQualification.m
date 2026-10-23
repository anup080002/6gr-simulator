function summary=summarizeSRSChannelQualification(T)
% Keep receiver usability, diagnostic numbers and independent reference
% authority separate. PASS text alone cannot qualify a channel comparison.
arguments
    T table
end
summary=struct('NMSE_dB',NaN,'MeasurementAvailable',false, ...
    'MeasuredTrials',0,'QualifiedTrials',0,'FailedTrials',0, ...
    'UnqualifiedTrials',height(T),'AnyQualifiedTrial',false, ...
    'AllTrialsQualified',false, ...
    'NMSEAggregation',"equal_trial_mean_linear_normalized_error", ...
    'ReferenceAvailableTrials',0,'UnreferencedNumericTrials',0);
vars=string(T.Properties.VariableNames);
status=strings(height(T),1);
if ismember('Status',vars)
    status=upper(strtrim(string(T.Status)));
    assert(isequal(size(status),[height(T),1]), ...
        'sixgr:truth:InvalidSRSStatusColumn','Each original trial needs one status.');
    summary.FailedTrials=nnz(status=="FAIL" | status=="CRASH");
end
if isempty(T) || ~ismember('NMSE_dB',vars), return; end
nmse=T.NMSE_dB;
assert(isnumeric(nmse) && isreal(nmse) && isequal(size(nmse),[height(T),1]), ...
    'sixgr:truth:InvalidSRSNMSEColumn','Each trial needs one real NMSE value.');
numericAvailable=isfinite(nmse) | nmse==-Inf; % Exact zero error is -Inf dB.
referenceAvailable=false(height(T),1);
if ismember('ChannelNMSEReferenceAvailable',vars)
    authority=T.ChannelNMSEReferenceAvailable;
    assert((islogical(authority)||isnumeric(authority))&&isreal(authority)&& ...
        isequal(size(authority),[height(T),1])&& ...
        all(authority==0|authority==1|isnan(authority)), ...
        'sixgr:truth:InvalidSRSReferenceAuthority', ...
        'Reference authority must be an explicit boolean per original trial.');
    referenceAvailable=authority==1;
end
summary.ReferenceAvailableTrials=nnz(referenceAvailable);
summary.UnreferencedNumericTrials=nnz(numericAvailable & ~referenceAvailable);
valid=numericAvailable & referenceAvailable;
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
qualified=false(height(T),1);
if ismember('ChannelNMSEThreshold_dB',vars)
    threshold=T.ChannelNMSEThreshold_dB;
    assert(isnumeric(threshold)&&isreal(threshold)&& ...
        isequal(size(threshold),[height(T),1]), ...
        'sixgr:truth:InvalidSRSNMSEThreshold', ...
        'Qualification requires one declared numeric threshold per trial.');
    qualified=valid & status=="PASS" & isfinite(threshold) & nmse<=threshold;
end
summary.QualifiedTrials=nnz(qualified);
summary.UnqualifiedTrials=height(T)-summary.QualifiedTrials;
summary.AnyQualifiedTrial=any(qualified);
summary.AllTrialsQualified=all(qualified);
end
