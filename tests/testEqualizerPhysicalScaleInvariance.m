function ok = testEqualizerPhysicalScaleInvariance()
% Same physical link in different amplitude units must not change its SINR.
% These are numerical matrix fixtures, not measured waveform observations.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
state=rng; restore=onCleanup(@()rng(state));
rng(261013,'twister');
cases=0; nRE=5; variance=.03;
for dimensions=[1 1;2 1;4 2;64 4].'
    nRx=dimensions(1); nLayers=dimensions(2);
    h0=(randn(nRx,nLayers)+1i*randn(nRx,nLayers))/sqrt(nRx);
    h0(1:nLayers,:)=h0(1:nLayers,:)+eye(nLayers);
    rx=randn(nRE,nRx)+1i*randn(nRE,nRx);
    interference=diag(linspace(.01,.04,nRx));
    for variable=[false true]
        H=repmat(reshape(h0,1,nRx,nLayers),nRE,1,1);
        if variable
            for k=1:nRE
                H(k,:,:)=H(k,:,:)*(1+.05*k)*exp(.1i*k);
            end
        end
        for mode=["white","static","per_re"]
            R=variance*eye(nRx);
            args={};
            if mode~="white"
                R=R+interference;
                supplied=interference;
                if mode=="per_re"
                    supplied=repmat(reshape(supplied,1,nRx,nRx),nRE,1,1);
                end
                args={'Rint',supplied,'RIncludesNoise',false};
            end
            for algorithm=["MMSE","IRC","ZF"]
                [reference,referenceGamma]=directReference(rx,H,R,algorithm);
                for amplitude=[1e-12 1e-8 1e-4 1 1e4]
                    scaledArgs=args;
                    if ~isempty(scaledArgs), scaledArgs{2}=amplitude^2*args{2}; end
                    [symbols,reliability,info]=sixgr.phy.rx.equalizeMMSE( ...
                        amplitude*rx,amplitude*H,amplitude^2*variance, ...
                        'Algorithm',algorithm,scaledArgs{:});
                    result=info.EqualizerResult;
                    near(symbols,reference,2e-10,'Equalized symbols changed with amplitude units.');
                    near(result.PostEqSINRLinear,referenceGamma,2e-10,'Physical SINR changed with amplitude units.');
                    near(reliability,referenceGamma./(1+referenceGamma),2e-10,'Reliability changed with amplitude units.');
                    assert(result.PreEqualizationNoiseVariance==amplitude^2*variance);
                    assert(~result.PhysicalCovarianceModifiedForSolve);
                    for k=1:nRE
                        W=reshape(result.W(k,:,:),nLayers,nRx);
                        actual=reshape(result.OutputNoiseInterferenceCovariance(k,:,:),nLayers,nLayers);
                        near(actual,W*(amplitude^2*R)*W',2e-12, ...
                            'Numerical stabilization must not become physical noise.');
                    end
                    if variable && mode~="per_re" && algorithm~="ZF" && nRx>1
                        assert(info.CovarianceFactorizationCount==1);
                        assert(string(info.EngineUsed)=="batchedStaticCovarianceVariableChannel");
                    end
                    cases=cases+1;
                end
            end
        end
    end
end

% Trailing singleton dimensions and a single multi-RX RE must remain legal.
H=reshape([1 .3;-.2 1.4],1,2,2);
[symbols,reliability,info]=sixgr.phy.rx.equalizeMMSE([.4 1.1],H,.1);
assert(isequal(size(symbols),[1 2]) && isequal(size(reliability),[1 2]));
assert(info.EqualizerResult.NRE==1 && info.NumRxAnt==2 && info.NumTxPorts==2);
H=(1:4).'; rx=ones(4,1); covariance=[.1;.2;.3;.4];
[~,~,included]=sixgr.phy.rx.equalizeMMSE(rx,H,0,'Rint',covariance,'RIncludesNoise',true);
[~,~,added]=sixgr.phy.rx.equalizeMMSE(rx,H,.025,'Rint',covariance-.025,'RIncludesNoise',false);
near(included.EqualizerResult.PostEqSINRLinear,H.^2./covariance,2e-12, ...
    'SISO per-RE covariance must not be rejected or replaced.');
near(included.EqualizerResult.PostEqSINRLinear,added.EqualizerResult.PostEqSINRLinear, ...
    2e-12,'Noise-included and noise-added conventions must agree.');

% Singular physical covariance is legal; an indefinite one is not.
H=repmat(reshape(eye(2),1,2,2),2,1,1);
[symbols,reliability,info]=sixgr.phy.rx.equalizeMMSE(ones(2),H,0, ...
    'Rint',diag([0 .25]),'RIncludesNoise',true);
near(symbols,repmat([1 .8],2,1),2e-12,'Zero-noise dimension must not be loaded.');
assert(all(isinf(info.EqualizerResult.PostEqSINRLinear(:,1))) && all(reliability(:,1)==1));
near(info.EqualizerResult.PostEqSINRLinear(:,2),4*ones(2,1),2e-12,'Noisy dimension changed.');
[symbols,reliability,info]=sixgr.phy.rx.equalizeMMSE(zeros(2,2),zeros(2,2,2),0);
assert(all(symbols(:)==0) && all(reliability(:)==0) && all(info.EqualizerResult.PostEqSINRLinear(:)==0));
fprintf('EQUALIZER_SCALE_INVARIANCE_PASS cases=%d single_RE_multi_layer=1 singular_covariance=1\n',cases);
ok=true;
end

function [symbols,gamma]=directReference(rx,H,R,algorithm)
nRE=size(H,1); nRx=size(H,2); nLayers=size(H,3);
symbols=complex(zeros(nRE,nLayers)); gamma=zeros(nRE,nLayers);
for k=1:nRE
    h=reshape(H(k,:,:),nRx,nLayers);
    if algorithm=="ZF"
        W=pinv(h);
    else
        % Independent receive-covariance form, not DUT layer whitening.
        W=((h*h'+R)\h)';
    end
    symbols(k,:)=(W*rx(k,:).').';
    A=W*h; C=W*R*W';
    for layer=1:nLayers
        other=[1:layer-1 layer+1:nLayers];
        gamma(k,layer)=abs(A(layer,layer))^2/ ...
            (sum(abs(A(layer,other)).^2)+real(C(layer,layer)));
    end
end
end

function near(actual,expected,tolerance,message)
assert(isequal(size(actual),size(expected)),message);
assert(norm(actual(:)-expected(:))<=tolerance*max(norm(expected(:)),realmin),message);
end
