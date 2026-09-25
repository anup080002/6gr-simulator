function result=whiteNoiseCoherenceDecision(received,reference,targetFalseAlarm,hypothesisCount)
% Coherent reference projection, noncoherent across receive branches.
% Under spatially/RE-white circular Gaussian H0 with equal RX variances,
% projection energy ~ Gamma(R,1), orthogonal energy ~ Gamma(R*(N-1),1).
% Their normalized ratio therefore has Beta(R,R*(N-1)) distribution.
% The union bound accounts for ALL searched timing/frequency/reference
% hypotheses, without assuming independent searches. A selected timing
% estimate cannot be treated as one fixed, prespecified observation.
% This is an explicit receiver implementation, not a 3GPP detector rule.
% Callers must establish the white-noise hypothesis; this does not qualify
% colored/correlated interference or a fading-channel estimate.
reference=reference(:);
assert(ismatrix(received) && size(received,1)==numel(reference) && ...
    size(received,1)>1 && size(received,2)>=1, ...
    'sixgr:phy:trs:CoherenceShape','Use N>1 reference REs and every physical RX branch.');
validateattributes(targetFalseAlarm,{'numeric'},{'scalar','real','finite','>',0,'<',1});
validateattributes(hypothesisCount,{'numeric'},{'scalar','real','finite','integer','positive'});
n=size(received,1); r=size(received,2);
threshold=betaincinv(targetFalseAlarm/hypothesisCount,r,r*(n-1),'upper');
result=struct('Detected',false,'SquaredCoherence',NaN,'Correlation',NaN, ...
    'CorrelationThreshold',sqrt(threshold),'SingleHypothesisTailProbability',NaN, ...
    'SearchFalseAlarmBound',NaN,'TargetFalseAlarmProbability',double(targetFalseAlarm), ...
    'HypothesisCount',double(hypothesisCount),'NumReferenceRE',n,'NumReceiveAntennas',r, ...
    'Status',"invalid_received_or_reference_samples", ...
    'NoiseAssumption',"equal_variance_spatial_and_RE_white_circular_Gaussian", ...
    'Source',"received_reference_projection_beta_tail_search_union_bound");
if any(~isfinite(received),'all') || any(~isfinite(reference)), return; end
refScale=max(abs(reference)); rxScale=max(abs(received),[],'all');
if refScale==0, result.Status="zero_energy_reference"; return; end
if rxScale==0
    result.SquaredCoherence=0; result.Correlation=0;
    result.SingleHypothesisTailProbability=1; result.SearchFalseAlarmBound=1;
    result.Status="zero_received_energy"; return;
end
% Conditioning cancels algebraically. It does not alter physical samples,
% transmit power or the channel, and avoids a scale-dependent epsilon floor.
y=received/rxScale; s=reference/refScale;
projection=sum(y.*conj(s),1);
stat=sum(abs(projection).^2)/(sum(abs(s).^2)*sum(abs(y).^2,'all'));
assert(stat>=0 && stat<=1+32*eps, ...
    'sixgr:phy:trs:InvalidCoherence','Projection ratio must satisfy Cauchy-Schwarz.');
stat=min(1,stat); % Roundoff only, after the mathematical bound was checked.
tail=betainc(stat,r,r*(n-1),'upper');
bound=min(1,hypothesisCount*tail);
result.SquaredCoherence=stat; result.Correlation=sqrt(stat);
result.SingleHypothesisTailProbability=tail; result.SearchFalseAlarmBound=bound;
result.Detected=bound<=targetFalseAlarm;
result.Status="white_noise_model_decision_available_not_physical_qualification";
end
