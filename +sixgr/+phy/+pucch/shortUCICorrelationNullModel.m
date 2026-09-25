function model=shortUCICorrelationNullModel(symbolCount,payloadBits,threshold,searchCount,targetProbability)
%SHORTUCICORRELATIONNULLMODEL Design bound, NOT a physical detector decision.
% For an isotropic circular complex Gaussian vector of N symbols, squared
% normalized correlation with one fixed nonzero reference is Beta(1,N-1).
% A-bit short UCI searches 2^A references. Bonferroni accounts for additional
% searches without assuming independent codewords or independent searches.
% This law does NOT automatically apply after channel estimation, MMSE,
% timing selection or colored interference. Establish/whiten that null first.
% No received metric, transmitted bits, channel or runtime policy is changed.
validateattributes(symbolCount,{'numeric'},{'scalar','real','finite','integer','>',1});
validateattributes(payloadBits,{'numeric'},{'scalar','real','finite','integer','>=',3,'<=',11});
validateattributes(threshold,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
validateattributes(searchCount,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(targetProbability,{'numeric'},{'scalar','real','finite','>',0,'<',1});
n=double(symbolCount); a=double(payloadBits); t=double(threshold);
h=2^a*double(searchCount);
assert(h<=flintmax,'sixgr:phy:pucch:InexactNullHypothesisCount', ...
    'The total reference/search hypothesis count must be exactly representable.');
logTail=(n-1)*log1p(-t^2);
tail=exp(logTail);
searchBound=exp(min(0,log(h)+logTail));
designThreshold=sqrt(-expm1((log(double(targetProbability))-log(h))/(n-1)));
model=struct('SymbolCount',n,'PayloadBits',a,'ReferenceHypothesisCount',2^a, ...
    'AdditionalSearchCount',double(searchCount),'TotalHypothesisCount',h, ...
    'CorrelationThreshold',t,'SingleReferenceTailProbability',tail, ...
    'SearchFalseDetectionUpperBound',searchBound, ...
    'TargetModelProbability',double(targetProbability), ...
    'UnionBoundDesignThreshold',designThreshold, ...
    'NoiseAssumption',"isotropic_circular_complex_gaussian_symbol_vector", ...
    'Scope',"analytical_design_only_not_post_equalization_or_physical_qualification", ...
    'DetectorQualified',false);
end
