function ok=testFlatAWGNMultiportChannel()
% Algebraic/statistical receiver test; not end-to-end PHY qualification.
setup6GRSimToolkit('Verbose',false);
stream=RandStream('mt19937ar','Seed',5192447);
n=144; ports=2; branches=4; trials=3000; variance=2.5;
base=exp(2i*pi*(0:n-1)'*(0:ports-1)/n);
% Unequal pilot energy and nonorthogonal columns must not break port ownership.
X=base*[1 .3+.2i;0 .7];
H=[.8+.1i 0 .6-.2i 0;0 .6+.2i 0 .8-.1i];
Y=X*H+sqrt(variance/2)*(randn(stream,n,branches)+1i*randn(stream,n,branches));
fit=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(Y,X);
independent=X\Y;
assert(max(abs(fit.GainPerPortReceiveBranch-independent),[],'all')<1e-12);
expected=sum(abs(Y-X*independent).^2,1)/(n-ports);
assert(max(abs(fit.NoiseVariancePerReceiveBranch-expected))<1e-12);
assert(fit.ResidualComplexDegreesOfFreedomPerBranch==n-ports);
covariance=(X'*X)\eye(ports);
assert(norm(fit.UnitNoiseCoefficientCovariance-covariance,'fro')<1e-12);
clean=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(X*H,X);
assert(norm(clean.GainPerPortReceiveBranch-H,'fro')<1e-12 && clean.NoiseVariance<1e-24);
scale=.031; phase=exp(1i*[.6 -.7 .2 -1.1]); order=[4 2 1 3];
changed=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(scale*Y(:,order).*phase,X);
assert(norm(changed.GainPerPortReceiveBranch-scale*fit.GainPerPortReceiveBranch(:,order).*phase,'fro')<1e-12);
assert(max(abs(changed.NoiseVariancePerReceiveBranch-scale^2*fit.NoiseVariancePerReceiveBranch(order)))<1e-12);
permuted=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(Y,X(:,[2 1]));
assert(norm(permuted.GainPerPortReceiveBranch-fit.GainPerPortReceiveBranch([2 1],:),'fro')<1e-12);
singleFit=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(single(Y),single(X));
assert(norm(double(singleFit.GainPerPortReceiveBranch)-independent,'fro')<1e-5);
errorEnergy=zeros(ports,branches); errorSum=complex(errorEnergy); noiseSum=zeros(1,branches);
for k=1:trials
    noise=sqrt(variance/2)*(randn(stream,n,branches)+1i*randn(stream,n,branches));
    observed=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(X*H+noise,X);
    err=observed.GainPerPortReceiveBranch-H;
    errorEnergy=errorEnergy+abs(err).^2; errorSum=errorSum+err;
    noiseSum=noiseSum+observed.NoiseVariancePerReceiveBranch;
end
theoretical=variance*real(diag(covariance));
ratio=(errorEnergy/trials)./theoretical;
assert(all(abs(ratio-1)<.08,'all') && all(abs(noiseSum/trials/variance-1)<.015));
assert(all(abs(errorSum/trials)<5*sqrt(theoretical/trials),'all'));
for bad={zeros(n,ports),[X(:,1) X(:,1)],X(1:ports,:),NaN(n,ports)}
    rejected=false;
    try
        sixgr.phy.rx.estimateFlatAWGNMultiportChannel(Y,bad{1});
    catch ME
        rejected=any(strcmp(ME.identifier,{'sixgr:phy:rx:InvalidFlatMultiportPilots', ...
            'sixgr:phy:rx:UnidentifiableFlatMultiportChannel'}));
    end
    assert(rejected,'test:FlatMultiportInvalidPilotsAccepted','Invalid pilot design must fail.');
end
fprintf('FLAT_AWGN_MULTIPORT_MATH_PASS trials=%d MSE_ratio=[%g,%g] noise=[%g,%g] no_oracle=1\n', ...
    trials,min(ratio,[],'all'),max(ratio,[],'all'),min(noiseSum/trials),max(noiseSum/trials));
ok=true;
end
