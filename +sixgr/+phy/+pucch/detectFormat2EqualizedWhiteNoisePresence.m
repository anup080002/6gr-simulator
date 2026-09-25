function decision=detectFormat2EqualizedWhiteNoisePresence(carrier,pucch,result,payloadBits,targetFalseAlarm,searchCount)
% Conditional data-only short-UCI presence test, NOT physical qualification.
% H0 requires spatial/RE-white circular Gaussian input noise and an equalizer
% estimated from disjoint pilots, not from these data REs. For each fixed
% acquisition hypothesis, y_k=W_k*n_k has variance sigma^2*||W_k||^2.
% Dividing by ||W_k|| makes the data noise white without knowing sigma^2.
% Reference templates retain WH, including unequal per-RE effective gains.
% A caller must establish these assumptions and count ALL acquisition/resource
% searches. This helper neither chooses a receiver model nor changes UCI layout.
assert(isa(carrier,'nrCarrierConfig') && isscalar(carrier) && ...
    isa(pucch,'nrPUCCH2Config') && isscalar(pucch) && ...
    ~(isprop(pucch,'Interlacing') && pucch.Interlacing), ...
    'sixgr:phy:pucch:UnsupportedWhitenedPresenceResource', ...
    'Require one independently installed non-interlaced Format-2 resource.');
validateattributes(payloadBits,{'numeric'},{'scalar','integer','>=',3,'<=',11});
validateattributes(searchCount,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(targetFalseAlarm,{'numeric'},{'scalar','real','finite','>',0,'<',1});
[indices,allocation]=nrPUCCHIndices(carrier,pucch); n=numel(indices);
assert(isstruct(result) && isscalar(result) && ...
    all(isfield(result,{'EqualizedSymbols','EffectiveResponseWH','W','NumTxPorts','NumRxAnt'})) && ...
    result.NumTxPorts==1 && result.NumRxAnt>=1 && ...
    size(result.EqualizedSymbols,1)==n && size(result.EqualizedSymbols,2)==1 && ...
    numel(result.EffectiveResponseWH)==n && size(result.W,1)==n && ...
    size(result.W,2)==1 && numel(result.W)==n*result.NumRxAnt, ...
    'sixgr:phy:pucch:InvalidWhitenedPresenceEqualizer', ...
    'Use the actual single-layer equalizer for this exact receive allocation.');
y=result.EqualizedSymbols(:); g=result.EffectiveResponseWH(:);
W=reshape(result.W,n,result.NumRxAnt);
decision=struct('Detected',false,'Correlation',NaN,'CorrelationThreshold',NaN, ...
    'SearchFalseAlarmBound',NaN,'HypothesisCount',searchCount*2^payloadBits, ...
    'CandidateCount',2^payloadBits,'LayoutHypothesesSearched',1, ...
    'TargetFalseAlarmProbability',double(targetFalseAlarm), ...
    'NumDataRE',n,'NumUsableDataRE',0,'Status',"invalid_equalizer_observation", ...
    'Source',"conditional_data_only_equalizer_whitening_codebook_projection", ...
    'NoiseAssumption',"pilot_independent_equalizer_spatial_RE_white_circular_Gaussian_input", ...
    'InjectedNoiseVarianceUsed',false,'TransmittedPayloadUsed',false, ...
    'PhysicalQualificationPassed',false,'NoiseModelEstablishedByThisFunction',false);
if any(~isfinite(y)) || any(~isfinite(g)) || any(~isfinite(W),'all'), return; end
% Row-scaled norms avoid squaring tiny/large equalizer coefficients. No
% physical noise floor is introduced. Zero W carries no data information.
rowScale=max(abs(W),[],2); usable=rowScale>0;
decision.NumUsableDataRE=nnz(usable);
if nnz(usable)<2, decision.Status="insufficient_nonzero_equalizer_rows"; return; end
normScaled=sqrt(sum(abs(W(usable,:)./rowScale(usable)).^2,2));
z=(y(usable)./rowScale(usable))./normScaled;
response=(g(usable)./rowScale(usable))./normScaled;
if any(~isfinite(z)) || any(~isfinite(response)), return; end
zScale=max(abs(z)); responseScale=max(abs(response));
if zScale==0, decision.Status="zero_received_energy"; return; end
if responseScale==0, decision.Status="zero_effective_reference_response"; return; end
z=z/zScale; response=response/responseScale;
% Enumerate legal words for the ONE scheduled width. This is the ordinary
% short-codebook search, not a search over HARQ/CSI/SR ownership hypotheses.
words=zeros(payloadBits,2^payloadBits,'int8');
for b=1:payloadBits, words(b,:)=int8(bitget(uint16(0:2^payloadBits-1),b)); end
basis=zeros(double(allocation.G),payloadBits);
for b=1:payloadBits
    unit=zeros(payloadBits,1,'int8'); unit(b)=1;
    basis(:,b)=double(nrUCIEncode(unit,allocation.G));
end
bits=mod(basis*double(words),2);
nid=pucch.NID; if isempty(nid), nid=carrier.NCellID; end
bits=mod(bits+double(nrPUCCHPRBS(nid,pucch.RNTI,allocation.G)),2);
symbols=reshape(nrSymbolModulate(int8(bits(:)),'QPSK'),n,[]);
templates=response.*symbols(usable,:);
score=abs(templates'*z).^2./sum(abs(templates).^2,1).';
[~,winner]=max(score);
% Under the stated conditional null, one complex projection has Beta(1,N-1)
% normalized energy. The union bound does not assume independent codewords
% or independent timing searches; count both before accepting the maximum.
tail=sixgr.phy.trs.whiteNoiseCoherenceDecision( ...
    z,templates(:,winner),targetFalseAlarm,decision.HypothesisCount);
decision.Detected=tail.Detected;
decision.Correlation=tail.Correlation;
decision.CorrelationThreshold=tail.CorrelationThreshold;
decision.SearchFalseAlarmBound=tail.SearchFalseAlarmBound;
decision.SingleHypothesisTailProbability=tail.SingleHypothesisTailProbability;
decision.Status="conditional_whitened_data_decision_not_physical_qualification";
end
