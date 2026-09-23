function out=normalizedCorrelationDecision(metric,n,hypotheses,nRx,alpha,minimumThreshold)
%NORMALIZEDCORRELATIONDECISION Explicit detection, not an argmax hypothesis.
% For one fixed reference and N independent circular complex Gaussian noise
% samples, rho^2=|s'*x|^2/(||s||^2||x||^2) has tail (1-rho^2)^(N-1).
% See Develter et al., ICASSP 2022, doi:10.1109/ICASSP43922.2022.9746620, (6).
% A mean or RMS of branch correlations >= t implies at least one branch
% correlation >= t. A union bound over ALL hypotheses and branches then
% bounds false alarm without assuming independent overlapping hypotheses.
% This is a white-noise nominal bound, not empirical RF qualification.
validateattributes(n,{'numeric'},{'real','scalar','finite','integer','>=',2});
validateattributes(hypotheses,{'numeric'},{'real','scalar','finite','integer','positive'});
validateattributes(nRx,{'numeric'},{'real','scalar','finite','integer','positive'});
validateattributes(alpha,{'numeric'},{'real','scalar','finite','>',0,'<',1});
validateattributes(minimumThreshold,{'numeric'},{'real','scalar','finite','nonnegative'});
logPerHypothesisAlpha=log(double(alpha))-log(double(hypotheses))-log(double(nRx));
nominalThreshold=sqrt(-expm1(logPerHypothesisAlpha/(double(n)-1)));
threshold=max(nominalThreshold,double(minimumThreshold));
valid=isnumeric(metric) && isreal(metric) && isscalar(metric) && ...
    isfinite(metric) && metric>=0 && metric<=1+64*eps;
out=struct('Detected',logical(valid && metric>threshold),'MetricValid',logical(valid), ...
    'NormalizedMetric',double(metric),'Threshold',threshold, ...
    'NominalThreshold',nominalThreshold,'MinimumThreshold',double(minimumThreshold), ...
    'ReferenceLength',double(n),'HypothesisCount',double(hypotheses), ...
    'NumReceiveBranches',double(nRx),'TargetFalseAlarmProbability',double(alpha), ...
    'Source',"normalized_correlation_beta_tail_union_bound", ...
    'NullModel',"independent_circular_white_gaussian_samples_per_branch", ...
    'EmpiricallyQualified',false);
end
