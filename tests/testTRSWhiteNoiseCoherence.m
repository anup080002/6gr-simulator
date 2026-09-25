function ok=testTRSWhiteNoiseCoherence()
% Independent mathematical distributions; NOT primary PHY campaign rows.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'trs_coherence_math_candidate.yaml'));
stream=RandStream('mt19937ar','Seed',p.seed);
n=p.num_reference_re;
s=exp(1i*pi/2*randi(stream,[0 3],n,1));
for r=reshape(p.receive_branches,1,[])
    hits=0; episodes=p.noise_episodes_per_branch_count;
    for k=1:episodes
        y=randn(stream,n,r)+1i*randn(stream,n,r);
        result=sixgr.phy.trs.whiteNoiseCoherenceDecision(y,s,p.noise_probability_probe,1);
        hits=hits+result.Detected;
        if k<=16
            rotated=1e-100*y(:,end:-1:1).*exp(1i*(1:r));
            other=sixgr.phy.trs.whiteNoiseCoherenceDecision(rotated,s,p.noise_probability_probe,1);
            assert(abs(result.SquaredCoherence-other.SquaredCoherence)<1e-12);
            if r==1
                expected=(1-result.SquaredCoherence)^(n-1);
                assert(abs(result.SingleHypothesisTailProbability-expected)<1e-12);
            end
        end
    end
    meanCount=episodes*p.noise_probability_probe;
    sigma=sqrt(episodes*p.noise_probability_probe*(1-p.noise_probability_probe));
    assert(abs(hits-meanCount)<=p.null_count_sigma_limit*sigma, ...
        'The independent white-noise event count disagrees with the declared Beta law.');
    fprintf('TRS_COHERENCE_NULL branches=%d events=%d episodes=%d expected=%g\n',r,hits,episodes,meanCount);
end
r=p.signal_receive_branches;
for snr=reshape(p.signal_snr_db,1,[])
    hits=0;
    for k=1:p.signal_episodes_per_point
        gain=exp(1i*2*pi*rand(stream,1,r));
        y=s*gain+sqrt(10^(-snr/10)/2)*(randn(stream,n,r)+1i*randn(stream,n,r));
        result=sixgr.phy.trs.whiteNoiseCoherenceDecision(y,s, ...
            p.runtime_candidate_probability,p.timing_hypothesis_count);
        hits=hits+result.Detected;
    end
    rate=hits/p.signal_episodes_per_point;
    fprintf('TRS_COHERENCE_SIGNAL per_branch_re_snr=%g detected=%d episodes=%d timing_hypotheses=%d\n', ...
        snr,hits,p.signal_episodes_per_point,p.timing_hypothesis_count);
    if snr==max(p.signal_snr_db), assert(rate>=p.high_snr_detection_probability_min); end
end
zero=sixgr.phy.trs.whiteNoiseCoherenceDecision(zeros(n,r),s,p.runtime_candidate_probability,1);
assert(~zero.Detected && zero.SearchFalseAlarmBound==1);
bad=zeros(n,r); bad(1,1)=NaN;
invalid=sixgr.phy.trs.whiteNoiseCoherenceDecision(bad,s,p.runtime_candidate_probability,1);
assert(~invalid.Detected && isnan(invalid.SearchFalseAlarmBound));
ok=true; disp('TRS_COHERENCE_MATH_PASS_NOT_PHYSICAL_QUALIFICATION');
end
