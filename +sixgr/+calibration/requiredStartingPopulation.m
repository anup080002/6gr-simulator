function [required,lower,probability]=requiredStartingPopulation(reached,starts,target,confidence,reachProbability,cap)
% Plan a FIXED independent population, not stop-at-N-errors collection.
% One-sided exact binomial lower bound for preceding-failure probability.
validateattributes(starts,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(reached,{'numeric'},{'scalar','integer','>=',0,'<=',starts});
validateattributes(target,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(cap,{'numeric'},{'scalar','integer','>=',target,'finite'});
validateattributes(confidence,{'numeric'},{'scalar','>',0,'<',1});
validateattributes(reachProbability,{'numeric'},{'scalar','>',0,'<',1});
lower=0; required=Inf; probability=0;
if reached==0 || starts==0, return; end
lower=betaincinv(1-confidence,reached,starts-reached+1);
% P[Binomial(n,p)>=target], including the n==target edge.
tail=@(n)betainc(lower,target,n-target+1);
if tail(cap)<reachProbability, return; end
lo=target; hi=cap;
while lo<hi
    mid=floor((lo+hi)/2);
    if tail(mid)>=reachProbability, hi=mid; else, lo=mid+1; end
end
required=lo; probability=tail(required);
end
