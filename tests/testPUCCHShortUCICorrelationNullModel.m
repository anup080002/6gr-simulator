function ok=testPUCCHShortUCICorrelationNullModel()
% Mathematical/component guard only; never count these as physical trials.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
stream=RandStream('mt19937ar','Seed',p.seed);
cases=0;
for n=reshape(p.symbol_counts,1,[])
    thresholds=reshape(p.thresholds,1,[]);
    hits=zeros(size(thresholds));
    remaining=p.noise_episodes_per_symbol_count;
    while remaining>0
        count=min(remaining,p.noise_batch_size);
        y=randn(stream,n,count)+1i*randn(stream,n,count);
        % A fixed unit reference; no maximization, known channel or decoded bits.
        metric=abs(sum(y,1))./sqrt(n*sum(abs(y).^2,1));
        hits=hits+sum(metric(:)>=thresholds,1);
        remaining=remaining-count;
    end
    for a=reshape(p.payload_bits,1,[])
        for searchCount=reshape(p.additional_search_counts,1,[])
            for j=1:numel(thresholds)
                t=thresholds(j);
                m=sixgr.phy.pucch.shortUCICorrelationNullModel( ...
                    n,a,t,searchCount,p.target_model_probability);
                expectedTail=betainc(t^2,1,n-1,'upper');
                assert(abs(m.SingleReferenceTailProbability-expectedTail)<1e-12);
                assert(abs(m.SearchFalseDetectionUpperBound- ...
                    min(1,2^a*searchCount*expectedTail))<1e-12);
                probe=sixgr.phy.pucch.shortUCICorrelationNullModel( ...
                    n,a,m.UnionBoundDesignThreshold,searchCount,p.target_model_probability);
                assert(abs(probe.SearchFalseDetectionUpperBound-p.target_model_probability)<1e-12);
                assert(~m.DetectorQualified && contains(m.Scope,'not_post_equalization'));
                expectedCount=p.noise_episodes_per_symbol_count*expectedTail;
                sigma=sqrt(p.noise_episodes_per_symbol_count*expectedTail*(1-expectedTail));
                assert(abs(hits(j)-expectedCount)<=p.null_count_sigma_limit*sigma+1, ...
                    'test:ShortUCINullLawMismatch','Independent Gaussian observations violate the declared null law.');
                cases=cases+1;
            end
        end
    end
    fprintf('SHORT_UCI_SINGLE_REFERENCE_NULL N=%d episodes=%d hits=%s\n', ...
        n,p.noise_episodes_per_symbol_count,mat2str(hits));
end
invalid={ {1,11,.2,1,.01},{64,2,.2,1,.01},{64,12,.2,1,.01}, ...
    {64,11,NaN,1,.01},{64,11,-.1,1,.01},{64,11,1.1,1,.01}, ...
    {64,11,.2,0,.01},{64,11,.2,1,0},{64,11,.2,1,1}, ...
    {64,11,.2,flintmax,.01} };
for k=1:numel(invalid)
    rejected=false;
    args=invalid{k};
    try
        sixgr.phy.pucch.shortUCICorrelationNullModel(args{:});
    catch
        rejected=true;
    end
    assert(rejected,'test:InvalidNullModelAccepted','Malformed model input must be rejected.');
end
fprintf('PUCCH_SHORT_UCI_NULL_MODEL_PASS cases=%d physical_qualification=0\n',cases);
ok=true;
end
