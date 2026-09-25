function ok=testEqualizerNoiseAuthority()
% Solver stabilization cannot become physical covariance or invented noise.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cases=0;
for dimensions=[1 1;2 1;4 2].'
    nr=dimensions(1); nl=dimensions(2); n=4;
    h0=reshape(sin(1:nr*nl)+1i*cos(2*(1:nr*nl)),nr,nl);
    h0(1:nl,:)=h0(1:nl,:)+2*eye(nl);
    for variable=[false true]
        H=repmat(reshape(h0,1,nr,nl),n,1,1);
        if variable
            for k=1:n, H(k,:,:)=H(k,:,:).*(1+.1*k)*exp(.1i*k); end
        end
        rx=reshape(cos(1:n*nr)+1i*sin(1:n*nr),n,nr);
        for variance=[0 1e-20 .05]
            for mode=["white","static","per_re"]
                covariance=variance*eye(nr); args={};
                if mode~="white"
                    supplied=covariance;
                    if mode=="per_re", supplied=repmat(reshape(covariance,1,nr,nr),n,1,1); end
                    args={'Rint',supplied,'RIncludesNoise',true};
                end
                [~,~,info]=sixgr.phy.rx.equalizeMMSE(rx,H,variance,args{:});
                result=info.EqualizerResult;
                assert(result.PreEqualizationNoiseVariance==variance, ...
                    'test:EqualizerInventedNoise','Zero noise must stay zero; no received-power-derived substitute.');
                for k=1:n
                    W=reshape(result.W(k,:,:),nl,nr);
                    expected=W*covariance*W';
                    actual=reshape(result.OutputNoiseInterferenceCovariance(k,:,:),nl,nl);
                    tolerance=128*eps(max(abs(expected(:))));
                    assert(all(abs(actual(:)-expected(:))<=tolerance), ...
                        'test:EqualizerNumericalLoadCountedAsNoise', ...
                        'Output covariance must be W*Rphysical*W^H, excluding solve-only diagonal loading.');
                    wh=reshape(result.EffectiveResponseWH(k,:,:),nl,nl);
                    for layer=1:nl
                        other=setdiff(1:nl,layer);
                        signal=abs(wh(layer,layer))^2;
                        interference=sum(abs(wh(layer,other)).^2);
                        denominator=interference+max(real(expected(layer,layer)),0);
                        expectedSINR=signal/denominator;
                        measured=result.PostEqSINRLinear(k,layer);
                        if isinf(expectedSINR)
                            assert(isinf(measured) && result.DemapperReliability(k,layer)==1);
                        else
                            assert(abs(measured-expectedSINR)<=1e-11*max(expectedSINR,realmin), ...
                                'test:EqualizerNoiseFloorChangedSINR','Do not floor physical SINR denominators to eps.');
                        end
                    end
                end
                cases=cases+1;
            end
        end
    end
end
for invalid={NaN,Inf,-1,1+1i}
    reject(@()sixgr.phy.rx.equalizeMMSE(ones(2,1),ones(2,1),invalid{1}));
end
for invalid={NaN,-1,[1 2;2 1]}
    R=invalid{1}; nr=size(R,1);
    reject(@()sixgr.phy.rx.equalizeMMSE(ones(2,nr),ones(2,nr),.1, ...
        'Rint',R,'RIncludesNoise',true));
end
fprintf('EQUALIZER_NOISE_AUTHORITY_PASS cases=%d invalid_inputs=7 synthesized_noise=0 solve_load_in_output_covariance=0\n',cases);
ok=true;
end
function reject(fn)
try, fn(); catch cause
    assert(startsWith(string(cause.identifier),'sixgr:phy:equalizeMMSE:')); return;
end
error('test:InvalidEqualizerNoiseAccepted','Invalid noise/covariance must not become a substituted noise model.');
end
