function ok=testPRACHRepetitionBackground()
% Independent normalization, signal cancellation, and impairment semantics.
setup6GRSimToolkit('Verbose',false); old=rng; cleanup=onCleanup(@()rng(old)); rng(71901);
n=256; tones=139; reps=12; refFFT=zeros(n,1);
refFFT(1:tones)=exp(1i*2*pi*rand(tones,1)); ref=ifft(refFFT);
for nrx=[1 2 4]
    sigma2=0.037;
    noise=sqrt(sigma2/2)*(randn(n,reps,nrx)+1i*randn(n,reps,nrx));
    % Unknown multi-producer signal cancels, including a delayed component.
    signal=ref*(1:nrx)+circshift(ref,3)*(0.3i*(nrx:-1:1));
    y=repmat(reshape(signal,n,1,nrx),1,reps,1)+noise;
    normValue=19.7;
    a=sixgr.rach.measurePRACHRepetitionBackground(reshape(y,n,[]),ref,reps,normValue);
    b=sixgr.rach.measurePRACHRepetitionBackground(reshape(noise,n,[]),ref,reps,normValue);
    assert(abs(a.NoiseFloor-b.NoiseFloor)<1e-12);
    d=(y(:,2:2:end,:)-y(:,1:2:end,:))/sqrt(2);
    % Direct time-domain matched filters, independent of production Parseval.
    direct=0;
    for antenna=1:nrx
        for pair=1:reps/2
            for lag=0:n-1
                direct=direct+abs(circshift(ref,lag)'*d(:,pair,antenna))^2;
            end
        end
    end
    direct=direct/n*2/normValue;
    assert(abs(a.NoiseFloor-direct)<1e-12);
    expected=reps*nrx*sigma2*sum(abs(ref).^2)/normValue;
    assert(abs(a.NoiseFloor/expected-1)<0.12);
    assert(abs(a.SampleEquivalentVariance/sigma2-1)<0.12);
    assert(a.PairCount==6 && a.RxAntennaCount==nrx);
    noiseless=repmat(reshape(signal,n,1,nrx),1,reps,1);
    z=sixgr.rach.measurePRACHRepetitionBackground(reshape(noiseless,n,[]),ref,reps,normValue);
    assert(z.NoiseFloor==0 && z.SampleEquivalentVariance==0);
    varied=noiseless.*reshape(exp(1i*(0:reps-1)*0.2),1,reps,1);
    v=sixgr.rach.measurePRACHRepetitionBackground(reshape(varied,n,[]),ref,reps,normValue);
    assert(v.NoiseFloor>0 && contains(v.Definition,'inter_repetition_variation'));
end
missing=sixgr.rach.measurePRACHRepetitionBackground(ref,ref,1,1);
assert(isnan(missing.NoiseFloor) && startsWith(missing.Status,'unavailable'));
ok=true; disp('PRACH_REPETITION_BACKGROUND_PASS: direct normalization, 1/2/4 RX, signal cancellation, variation and unavailable guard.');
end
