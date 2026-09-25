function ok=testPUCCHShortUCIConfidenceCompatibility()
% Verify reuse of short-codeword confidence, without changing PUCCH policy.
% Independent full-length likelihood enumeration; not a noise/ACK campaign.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
policy=struct('algorithm',string(p.candidate_word_algorithm), ...
    'minimumPosterior',p.candidate_word_minimum_posterior);
stream=RandStream('mt19937ar','Seed',p.seed);
cases=0;
for a=reshape(p.codec_payload_bits,1,[])
    for e=reshape(p.codec_coded_lengths,1,[])
        bits=int8(randi(stream,[0 1],a,1));
        coded=nrUCIEncode(bits,e); % PUCCH's public coding path, not PUSCH wrapper.
        strong=p.strong_llr_magnitude*(1-2*double(coded));
        decoded=sixgr.phy.pucch.UCIDecoder.decode(strong,a);
        evidence=sixgr.phy.ul.pusch.shortUCICodewordConfidence( ...
            strong,decoded.Bits,a,"QPSK",policy);
        assert(isequal(bits,decoded.Bits) && evidence.Accepted && ~decoded.CRCApplicable);
        assert(~evidence.SignalPresenceQualified);
        llr=randn(stream,e,1);
        decoded=sixgr.phy.pucch.UCIDecoder.decode(llr,a);
        evidence=sixgr.phy.ul.pusch.shortUCICodewordConfidence( ...
            llr,decoded.Bits,a,"QPSK",policy);
        % Compare against public full-length coding, opposite bit enumeration
        % and log-sigmoid probabilities. No folded-period helper under test.
        words=int8(dec2bin(0:2^a-1,a)-'0');
        logLikelihood=zeros(2^a,1);
        for k=1:2^a
            code=nrUCIEncode(words(k,:).',e);
            signed=(1-2*double(code)).*llr;
            logLikelihood(k)=-sum(max(-signed,0)+log1p(exp(-abs(signed))));
        end
        probabilities=exp(logLikelihood-max(logLikelihood));
        probabilities=probabilities/sum(probabilities);
        selected=find(all(words==decoded.Bits.',2));
        assert(isscalar(selected) && ...
            abs(evidence.SelectedPosterior-probabilities(selected))<1e-11 && ...
            abs(evidence.MaximumPosterior-max(probabilities))<1e-11);
        weak=sixgr.phy.ul.pusch.shortUCICodewordConfidence( ...
            p.weak_llr_scale*llr,decoded.Bits,a,"QPSK",policy);
        assert(~weak.Accepted);
        zero=sixgr.phy.ul.pusch.shortUCICodewordConfidence( ...
            zeros(e,1),decoded.Bits,a,"QPSK",policy);
        assert(~zero.Accepted && ~zero.UniqueMaximum && ...
            abs(zero.SelectedPosterior-2^-a)<1e-12);
        cases=cases+1;
    end
end
fprintf('PUCCH_SHORT_UCI_CONFIDENCE_COMPATIBILITY_PASS cases=%d runtime_policy_changed=0 physical_qualification=0\n',cases);
ok=true;
end
