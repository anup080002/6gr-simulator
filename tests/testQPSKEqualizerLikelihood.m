function ok=testQPSKEqualizerLikelihood()
% Four-point likelihood enumeration independently checks the demapper formula.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
stream=RandStream('mt19937ar','Seed',p.seed);
labels=int8([0 0;0 1;1 0;1 1]);
ref=nrSymbolModulate(reshape(labels.',[],1),'QPSK');
n=p.demapper_symbol_count; cases=0;
for r=reshape(p.demapper_receive_branches,1,[])
    for snr=reshape(p.demapper_snr_db,1,[])
        bits=int8(randi(stream,[0 1],2*n,1));
        symbols=nrSymbolModulate(bits,'QPSK');
        channel=(randn(stream,n,r)+1i*randn(stream,n,r))/sqrt(2*r);
        variance=10^(-snr/10);
        received=channel.*symbols+sqrt(variance/2)*(randn(stream,n,r)+1i*randn(stream,n,r));
        [~,~,eq]=sixgr.phy.rx.equalizeMMSE(received,reshape(channel,n,r,1),variance);
        result=eq.EqualizerResult;
        [llr,evidence]=sixgr.phy.rx.demapQPSKEqualizerOutput(result);
        expected=zeros(n,2);
        for k=1:n
            logp=-abs(result.EqualizedSymbols(k)-result.EffectiveResponseWH(k)*ref).^2/ ...
                real(result.OutputNoiseInterferenceCovariance(k));
            for b=1:2
                p0=logp(labels(:,b)==0); p1=logp(labels(:,b)==1);
                expected(k,b)=max(p0)+log(sum(exp(p0-max(p0))))- ...
                    max(p1)-log(sum(exp(p1-max(p1))));
            end
        end
        assert(max(abs(llr-reshape(expected.',[],1)))<1e-10);
        assert(~evidence.MeanVarianceUsed && ~evidence.NoiseAdded && ...
            ~evidence.TransmittedBitsUsed && ~evidence.PhysicalQualificationPassed);
        % Arbitrary complex output gain changes no likelihood when its
        % response and covariance are transformed consistently.
        phase=exp(1i*rand(stream,n,1)); scale=(.1+rand(stream,n,1)).*phase;
        changed=result;
        changed.EqualizedSymbols=result.EqualizedSymbols.*scale;
        changed.EffectiveResponseWH=result.EffectiveResponseWH.*scale;
        changed.OutputNoiseInterferenceCovariance=result.OutputNoiseInterferenceCovariance.*abs(scale).^2;
        other=sixgr.phy.rx.demapQPSKEqualizerOutput(changed);
        assert(max(abs(other-llr))<1e-10);
        cases=cases+1;
    end
end
zero=result; zero.EffectiveResponseWH(:)=0;
[llr,evidence]=sixgr.phy.rx.demapQPSKEqualizerOutput(zero);
assert(all(llr==0) && evidence.ZeroResponseRECount==n);
for failure=["zero_variance","missing_gain","multiple_layers","nonfinite_symbol"]
    bad=result;
    switch failure
        case "zero_variance", bad.OutputNoiseInterferenceCovariance(1)=0;
        case "missing_gain", bad=rmfield(bad,'EffectiveResponseWH');
        case "multiple_layers", bad.NumTxPorts=2;
        case "nonfinite_symbol", bad.EqualizedSymbols(1)=NaN;
    end
    rejected=false;
    try
        sixgr.phy.rx.demapQPSKEqualizerOutput(bad);
    catch err
        rejected=startsWith(string(err.identifier),'sixgr:phy:rx:');
    end
    assert(rejected,'test:MalformedQPSKLLREvidenceAccepted','Reject malformed equalizer evidence.');
end
ok=true;
fprintf('QPSK_EQUALIZER_LIKELIHOOD_PASS cases=%d physical_qualification=0\n',cases);
end
