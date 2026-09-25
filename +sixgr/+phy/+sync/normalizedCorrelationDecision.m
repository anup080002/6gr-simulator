function out=normalizedCorrelationDecision(metric,n,hypotheses,nRx,alpha,minimumThreshold)
%NORMALIZEDCORRELATIONDECISION Explicit detection, not an argmax hypothesis.
% For one fixed reference and N independent circular complex Gaussian noise
% samples, rho^2=|s'*x|^2/(||s||^2||x||^2) has tail (1-rho^2)^(N-1).
% See Develter et al., ICASSP 2022, doi:10.1109/ICASSP43922.2022.9746620, (6).
% With independent receive-branch noise, each squared correlation is
% stochastically bounded by Exp(rate=N-1): (1-u)^(N-1) <= exp(-(N-1)*u).
% Their sum is therefore bounded by Gamma(shape=NRx,scale=1/(N-1)).
% Both the mean amplitude and RMS amplitude are <= sqrt(mean(rho.^2)).
% Use the tighter of this branch-combining bound and the original branch
% union bound. Union over ALL searched hypotheses still requires no
% independence between overlapping timing/CFO/sequence hypotheses.
% This is a white-noise nominal bound, not empirical RF qualification.
validateattributes(n,{'numeric'},{'real','scalar','finite','integer','>=',2});
validateattributes(hypotheses,{'numeric'},{'real','scalar','finite','integer','positive'});
validateattributes(nRx,{'numeric'},{'real','scalar','finite','integer','positive'});
validateattributes(alpha,{'numeric'},{'real','scalar','finite','>',0,'<',1});
validateattributes(minimumThreshold,{'numeric'},{'real','scalar','finite','nonnegative'});
logPerHypothesisAlpha=log(double(alpha))-log(double(hypotheses))-log(double(nRx));
nominalThreshold=sqrt(-expm1(logPerHypothesisAlpha/(double(n)-1)));
branchUnionThreshold=nominalThreshold;
if nRx>1
    combinedThreshold=sqrt(gammaincinv(double(alpha)/double(hypotheses), ...
        double(nRx),'upper')/(double(nRx)*(double(n)-1)));
    nominalThreshold=min(branchUnionThreshold,combinedThreshold);
end
threshold=max(nominalThreshold,double(minimumThreshold));
valid=isnumeric(metric) && isreal(metric) && isscalar(metric) && ...
    isfinite(metric) && metric>=0 && metric<=1+64*eps;
out=struct('Detected',logical(valid && metric>threshold),'MetricValid',logical(valid), ...
    'NormalizedMetric',double(metric),'Threshold',threshold, ...
    'NominalThreshold',nominalThreshold,'MinimumThreshold',double(minimumThreshold), ...
    'ReferenceLength',double(n),'HypothesisCount',double(hypotheses), ...
    'NumReceiveBranches',double(nRx),'TargetFalseAlarmProbability',double(alpha), ...
    'BranchUnionThreshold',branchUnionThreshold, ...
    'Source',"normalized_correlation_independent_branch_gamma_bound", ...
    'NullModel',"circular_white_gaussian_samples_independent_across_receive_branches", ...
    'EmpiricallyQualified',false);
end
