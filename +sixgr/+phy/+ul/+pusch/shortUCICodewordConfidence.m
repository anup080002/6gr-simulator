function evidence=shortUCICodewordConfidence(llr,bits,count,modulation,policy)
% Exact legal-codeword posterior under uniform-prior, factorized bit LLRs.
% NOT a probability that a PUSCH transmission exists. Correlated/calibrated
% demapper LLRs and physical false/missed-ACK rates require separate validation.
validateattributes(count,{'numeric'},{'scalar','integer','>=',1,'<=',11});
validateattributes(llr,{'single','double'},{'vector','real','nonempty','nonnan'});
policy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(policy);
evidence=struct('Algorithm',policy.algorithm,'PolicySource',policy.Source, ...
    'MinimumPosterior',policy.minimumPosterior, ...
    'Model',"uniform_codewords_factorized_bit_LLR_conditional_on_transmission", ...
    'SignalPresenceQualified',false,'CandidateCount',2^count, ...
    'SelectedBits',bits(:),'SelectedPosterior',NaN,'MaximumPosterior',NaN, ...
    'UniqueMaximum',false,'DecoderMatchesMaximum',false,'Accepted',false, ...
    'Reason',"unusable_decoder_word");
% Base periods are TS 38.212 coding structure, not configurable PHY policy.
if count>2
    period=32;
else
    names=["pi/2-BPSK","QPSK","16QAM","64QAM","256QAM"];
    orders=[1 2 4 6 8]; index=find(names==string(modulation));
    assert(isscalar(index),'sixgr:pusch:UnsupportedShortUCIModulation', ...
        'Short UCI requires a modulation supported by nrUCIEncode/nrUCIDecode.');
    period=orders(index);
    if count==2, period=3*period; end
end
messages=zeros(2^count,count,'int8');
for b=1:count, messages(:,b)=int8(bitget(uint16((0:2^count-1).'),b)); end
codebook=zeros(period,2^count);
for k=1:2^count
    coded=nrUCIEncode(messages(k,:).',period,char(modulation));
    % Public NR encoder placeholders in the descrambled decoder domain.
    coded(coded==-1)=1;
    repeat=find(coded==-2); coded(repeat)=coded(repeat-1);
    codebook(:,k)=1-2*double(coded);
end
% Candidate-independent terms cancel exactly. This also removes fixed filler
% positions whose LLRs may legitimately be infinite after descrambling.
informative=any(codebook~=codebook(:,1),2);
position=mod((0:numel(llr)-1).',period)+1;
keep=informative(position);
observed=double(llr(keep));
if any(~isfinite(observed))
    evidence.Reason="nonfinite_informative_LLR"; return;
end
folded=accumarray(position(keep),observed,[period 1],@sum,0);
scores=0.5*(codebook(informative,:).'*folded(informative));
if any(~isfinite(scores))
    evidence.Reason="nonfinite_codeword_score"; return;
end
weights=exp(scores-max(scores));
posterior=weights/sum(weights);
[evidence.MaximumPosterior,winner]=max(posterior);
evidence.UniqueMaximum=nnz(scores==max(scores))==1;
if numel(bits)~=count || ~all(ismember(bits,int8([0 1]))), return; end
selected=find(all(messages==reshape(bits,1,[]),2));
evidence.SelectedPosterior=posterior(selected);
evidence.DecoderMatchesMaximum=selected==winner && evidence.UniqueMaximum;
evidence.Accepted=evidence.DecoderMatchesMaximum && ...
    evidence.SelectedPosterior>=policy.minimumPosterior;
if evidence.Accepted
    evidence.Reason="conditional_codeword_confidence_pass";
elseif ~evidence.DecoderMatchesMaximum
    evidence.Reason="ambiguous_or_nonmaximum_decoder_word";
else
    evidence.Reason="insufficient_conditional_codeword_confidence";
end
end
