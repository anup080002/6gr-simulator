function ok=testFlatAWGNPilotChannel()
% Algebraic/statistical estimator test, not a physical waveform campaign.
setup6GRSimToolkit('Verbose',false);
stream=RandStream('mt19937ar','Seed',5192431);
n=150; branches=2; trials=6000; variance=2.5;
s=exp(1i*pi/2*randi(stream,[0 3],n,1));
h=[.7+.2i -.3+.6i];
y=s*h+.3*(randn(stream,n,branches)+1i*randn(stream,n,branches));
out=sixgr.phy.rx.estimateFlatAWGNPilotChannel(y,s);
independent=s\y;
assert(max(abs(out.GainPerReceiveBranch-independent))<1e-12);
expected=sum(abs(y-s*independent).^2,1)/(n-1);
assert(max(abs(out.NoiseVariancePerReceiveBranch-expected))<1e-12);
assert(out.PilotCount==n && out.ResidualComplexDegreesOfFreedomPerBranch==n-1);
% Branch ordering/phase and absolute receive amplitude must remain physical.
phase=exp(1i*[.6 -1.1]); scale=.031;
changed=sixgr.phy.rx.estimateFlatAWGNPilotChannel(scale*y(:,[2 1]).*phase,s);
assert(max(abs(changed.GainPerReceiveBranch-scale*out.GainPerReceiveBranch([2 1]).*phase))<1e-12);
assert(max(abs(changed.NoiseVariancePerReceiveBranch-scale^2*out.NoiseVariancePerReceiveBranch([2 1])))<1e-12);
% A zero-signal branch stays measured zero; do not average gains over RX.
clean=sixgr.phy.rx.estimateFlatAWGNPilotChannel(s*[0 1i],s);
assert(max(abs(clean.GainPerReceiveBranch-[0 1i]))<1e-12 && clean.NoiseVariance<1e-24);
% Validate E|hhat-h|^2=sigma^2/sum|s|^2, not a tuned scenario threshold.
errorEnergy=0; noiseSum=0; errorSum=complex(zeros(1,branches));
for k=1:trials
    noise=sqrt(variance/2)*(randn(stream,n,branches)+1i*randn(stream,n,branches));
    fit=sixgr.phy.rx.estimateFlatAWGNPilotChannel(s*h+noise,s);
    err=fit.GainPerReceiveBranch-h;
    errorEnergy=errorEnergy+sum(abs(err).^2);
    errorSum=errorSum+err;
    noiseSum=noiseSum+fit.NoiseVariance;
end
mse=errorEnergy/(trials*branches); theoretical=variance/sum(abs(s).^2);
assert(abs(mse/theoretical-1)<.04 && abs(noiseSum/trials/variance-1)<.01);
assert(all(abs(errorSum/trials)<5*sqrt(theoretical/trials)));
for bad={NaN(n,branches),zeros(n-1,branches),zeros(1,branches)}
    rejected=false;
    try
        sixgr.phy.rx.estimateFlatAWGNPilotChannel(bad{1},s);
    catch ME
        rejected=strcmp(ME.identifier,'sixgr:phy:rx:InvalidFlatAWGNPilots');
    end
    assert(rejected);
end
rejected=false;
try
    sixgr.phy.rx.estimateFlatAWGNPilotChannel(y,zeros(n,1));
catch ME
    rejected=strcmp(ME.identifier,'sixgr:phy:rx:InvalidFlatAWGNReferenceEnergy');
end
assert(rejected);
fprintf('FLAT_AWGN_PILOT_CHANNEL_MATH_PASS MSE=%g theoretical=%g noise=%g expected=%g\n', ...
    mse,theoretical,noiseSum/trials,variance);
ok=true;
end
