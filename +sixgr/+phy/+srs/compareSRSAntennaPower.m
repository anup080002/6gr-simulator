function result=compareSRSAntennaPower(grid,support,nfft,measuredW)
% Raw native FFT sqrt(mW) operands only; caller separately proves ownership,
% isolation, units and support. No reference availability is inferred here.
id='sixgr:srs:ReferencePowerOperands';
validateattributes(nfft,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(grid,{'single','double'},{'nonempty','finite'});
validateattributes(support,{'numeric'},{'2d','nonempty','real','finite','integer','nonnegative'});
K=size(grid,1); L=size(grid,2); R=size(grid,3);
assert(ndims(grid)<=3 && size(support,2)==2 && all(support(:,1)<K) && ...
    all(support(:,2)<L) && isequal(support,unique(support,'rows','sorted')),id, ...
    'Average the unique physical RE union once, never once per coincident SRS port.');
validateattributes(measuredW,{'numeric'},{'vector','real','finite','nonnegative','numel',R});
measuredW=double(measuredW(:).');
occupied=sub2ind([K L],support(:,1)+1,support(:,2)+1);
flat=reshape(grid,K*L,R);
referenceW=mean(abs(double(flat(occupied,:))/(double(nfft)*sqrt(1000))).^2,1);
[referenceMax,referenceBranch]=max(referenceW);
[measuredMax,measuredBranch]=max(measuredW);
valid=measuredW>0 & referenceW>0;
errors=nan(1,R); errors(valid)=10*log10(measuredW(valid)./referenceW(valid));
result=struct('ReferencePerBranch_W',referenceW,'MeasuredPerBranch_W',measuredW, ...
    'PerBranchError_dB',errors,'PerBranchErrorDefined',valid, ...
    'MeasuredSelectedBranch0',measuredBranch-1,'ReferenceSelectedBranch0',referenceBranch-1, ...
    'ReferenceAtMeasuredSelectedBranch_W',referenceW(measuredBranch), ...
    'MeasuredReported_W',measuredMax,'ReferenceReported_W',referenceMax, ...
    'ReportedError_dB',NaN,'ReferencePower_dBm',NaN, ...
    'ReportingAggregation',"separate_maximum_branch_selection_implementation_policy", ...
    'ReportedErrorDefinition',"measured_max_branch_dBm_minus_reference_max_branch_dBm");
if referenceMax>0
    result.ReferencePower_dBm=10*log10(referenceMax)+30;
end
if referenceMax>0 && measuredMax>0
    result.ReportedError_dB=(10*log10(measuredMax)+30)-result.ReferencePower_dBm;
end
end
