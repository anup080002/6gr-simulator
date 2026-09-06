function ok=testAGCContinuousState()
% Fixed detector windows and hold durations must not depend on call sizes.
p=struct("TargetRMS",0.5,"MinGain_dB",-40,"MaxGain_dB",40, ...
    "Attack",1,"Release",1,"HoldSamples",3,"UpdatePeriodSamples",2);
a=sixgr.rf.runtime.AGCState(p,1);
x=[ones(2,1);0.1*ones(6,1)];
[y,t]=a.apply(x,2,1);
g=[0;0;repmat(20*log10(.5),4,1);repmat(20*log10(5),2,1)];
assert(max(abs(t.AppliedGain_dB-g))<1e-12);
assert(max(abs(y-x.*10.^(g/20)))<1e-12);
assert(a.SamplesProcessed==8 && a.Step==4 && a.DetectorSamples==0);
assert(t.GainValueRole=="next_sample_gain");
p.Attack=.6; p.Release=.2; p.UpdatePeriodSamples=7; p.HoldSamples=11;
n=(0:256).';
envelope=[.01*ones(63,1);.4*ones(91,1);.02*ones(103,1)];
x=[envelope.*exp(1j*.03*n),.7*envelope.*exp(-1j*.05*n)];
whole=sixgr.rf.runtime.AGCState(p,2);
chunks=sixgr.rf.runtime.AGCState(p,2);
[expected,expectedTrace]=whole.apply(x,2,2);
actual=zeros(size(x),'like',x); gains=zeros(size(x,1),1);
first=1;
for last=[1 6 7 8 27 66 91 257]
    [actual(first:last,:),trace]=chunks.apply(x(first:last,:),2,2);
    gains(first:last)=trace.AppliedGain_dB;
    assert(trace.StartSample==first-1 && trace.EndSampleExclusive==last);
    first=last+1;
end
assert(isequal(actual,expected) && isequal(gains,expectedTrace.AppliedGain_dB));
for name=["Gain_dB","Step","State","SamplesProcessed","DetectorSamples", ...
        "DetectorEnergy","DetectorClipped","DetectorAtMinimumGain","HoldRemainingSamples"]
    assert(isequal(chunks.(name),whole.(name)),"Chunk-dependent AGC state: %s",name);
end
% A future amplitude change cannot alter any already-emitted sample, even
% when it lies within the same detector window as the shared prefix.
a=sixgr.rf.runtime.AGCState(p,2); b=sixgr.rf.runtime.AGCState(p,2);
ya=a.apply([x(1:20,:);2*x(21:end,:)],4,2);
yb=b.apply([x(1:20,:);.2*x(21:end,:)],4,2);
assert(isequal(ya(1:20,:),yb(1:20,:)));
before=chunks.SamplesProcessed;
localError(@()chunks.apply(x(:,1),2,2),"RF:AGCStateMismatch");
localError(@()chunks.apply(x,2,3),"RF:StateEpochMismatch");
assert(chunks.SamplesProcessed==before);
localError(@()sixgr.rf.runtime.AGCState(rmfield(p,"UpdatePeriodSamples"),1), ...
    "RF:ImplicitAGCForbidden");
p.HoldSamples=1.5;
localError(@()sixgr.rf.runtime.AGCState(p,1),"RF:ImplicitAGCForbidden");
fprintf('AGC_CONTINUOUS_STATE_PASS: fixed sample windows, exact hold and no future-sample dependence.\n');
ok=true;
end

function localError(action,identifier)
try
    action();
catch ME
    assert(string(ME.identifier)==identifier,"Expected %s; got %s",identifier,ME.identifier);
    return;
end
error("TEST:MissingExpectedError","Expected %s.",identifier);
end
