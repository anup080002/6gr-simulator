function result=decodeFormat2FlatShortUCI(carrier,pucch,grid,payloadBits,targetFalseAlarm,additionalHypotheses)
% Joint known-pilot/legal-codeword inference for an explicitly flat channel.
% Model: Y=s*h+Z, one unknown constant complex response per RX branch and
% common spatial/RE-white circular Gaussian variance. This mathematical
% helper does NOT establish that model or qualify physical reception.
% The independently scheduled payload width/resource never changes here.
validateattributes(payloadBits,{'numeric'},{'scalar','integer','>=',3,'<=',11});
validateattributes(additionalHypotheses,{'numeric'},{'scalar','integer','positive','finite'});
% Shared validation and pilot-only evidence; no transmitted payload is used.
pilot=sixgr.phy.pucch.detectFormat2DMRSPresence(carrier,pucch,grid,targetFalseAlarm,additionalHypotheses);
[dataIndices,allocation]=nrPUCCHIndices(carrier,pucch);
pilotIndices=nrPUCCHDMRSIndices(carrier,pucch); pilots=nrPUCCHDMRS(carrier,pucch);
assert(iscolumn(dataIndices) && isempty(intersect(dataIndices,pilotIndices)), ...
    'sixgr:phy:pucch:InvalidJointReference','Data and DM-RS must occupy distinct single-port REs.');
nwords=2^payloadBits;
messages=zeros(payloadBits,nwords,'int8');
for b=1:payloadBits, messages(b,:)=int8(bitget(uint16(0:nwords-1),b)); end
% TS 38.212 short-block coding and rate matching are linear. Derive the
% basis through the public encoder, not a private implementation or TX bits.
basis=zeros(double(allocation.G),payloadBits);
for b=1:payloadBits
    unit=zeros(payloadBits,1,'int8'); unit(b)=1;
    basis(:,b)=double(nrUCIEncode(unit,allocation.G));
end
coded=mod(basis*double(messages),2);
nid=pucch.NID; if isempty(nid), nid=carrier.NCellID; end
scrambled=mod(coded+double(nrPUCCHPRBS(nid,pucch.RNTI,allocation.G)),2);
symbols=reshape(nrSymbolModulate(int8(scrambled(:)),'QPSK'),[],nwords);
references=[symbols;repmat(pilots,1,nwords)];
branches=reshape(grid,[],size(grid,3)); y=branches([dataIndices;pilotIndices],:);
result=struct('Bits',int8([]),'CandidateCount',nwords,'PayloadBitCount',payloadBits, ...
    'PilotOnlyDecision',pilot,'JointPresenceDecision',struct(), ...
    'ConditionalWordPosterior',NaN,'UniqueMaximum',false, ...
    'Model',"constant_complex_response_per_RX_and_common_white_Gaussian_variance", ...
    'WordPrior',"uniform_legal_words_flat_channel_response_Jeffreys_variance_prior", ...
    'TransmittedPayloadUsed',false,'InjectedNoiseVarianceUsed',false, ...
    'LayoutHypothesesSearched',1,'NoiseModelEstablishedByThisFunction',false, ...
    'PhysicalQualificationPassed',false,'Status',"invalid_observation");
if any(~isfinite(y),'all'), return; end
scale=max(abs(y),[],'all');
if scale==0, result.Status="zero_received_energy"; return; end
y=y/scale; energy=sum(abs(y).^2,'all');
refEnergy=sum(abs(references).^2,1).';
assert(max(abs(refEnergy-refEnergy(1)))<=64*eps(refEnergy(1)), ...
    'sixgr:phy:pucch:UnequalJointReferenceEnergy','Legal Format-2 references must have equal energy.');
projection=references'*y;
coherence=sum(abs(projection).^2,2)./(refEnergy*energy);
assert(all(coherence>=0 & coherence<=1+64*eps), ...
    'sixgr:phy:pucch:InvalidJointCoherence','Cauchy-Schwarz must hold for every candidate.');
coherence=min(1,coherence); % Checked floating-point roundoff only.
[~,winner]=max(coherence);
result.UniqueMaximum=nnz(coherence==coherence(winner))==1;
result.Bits=messages(:,winner);
% Marginalize each unknown complex h and the common variance. Equal-energy
% candidate-independent constants cancel: p(Y|word) proportional to
% RSS^(-R*(N-1)). This is not a factorized, plug-in channel-estimate LLR.
rss=energy*(1-coherence);
if any(rss==0)
    weights=double(rss==0); % Exact noiseless limit, not an epsilon floor.
else
    logWeights=-size(y,2)*(size(y,1)-1)*log(rss);
    weights=exp(logWeights-max(logWeights));
end
result.ConditionalWordPosterior=weights(winner)/sum(weights);
result.JointPresenceDecision=sixgr.phy.trs.whiteNoiseCoherenceDecision( ...
    y,references(:,winner),targetFalseAlarm,additionalHypotheses*nwords);
result.Status="conditional_joint_inference_available_not_physical_qualification";
end
