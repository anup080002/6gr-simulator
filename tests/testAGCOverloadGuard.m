function ok=testAGCOverloadGuard()
% Implementation test, not a physical oscillator or RF conformance claim.
setup6GRSimToolkit('Verbose',false);
p=struct('TargetRMS',.5,'MinGain_dB',-80,'MaxGain_dB',120, ...
    'Attack',1,'Release',.5,'HoldSamples',128,'UpdatePeriodSamples',64);
guard=struct('model','pre_adc_rail_flag_next_sample_gain_step', ...
    'enabled',true,'gain_step_db',6,'hold_samples',128);
x=[.001*ones(1024,1);.2*ones(512,1);.001*ones(256,1)];
x=x.*[1+.1i,.5-.3i];
old=sixgr.rf.runtime.AGCState(p,1); [before,bt]=old.apply(x,1,1);
p.OverloadGuard=guard;
whole=sixgr.rf.runtime.AGCState(p,1); [expected,t]=whole.apply(x,1,1);
assert(t.OverloadGuardEnabled && t.OverloadGuardTriggerCount>0 && ...
    t.OverloadGuardFeedbackLatencySamples==1);
first=find(t.OverloadGuardTriggered,1);
assert(first==1025 && isequal(expected(1:first,:),before(1:first,:)), ...
    'A clip flag must never repair its own sample or alter past samples.');
assert(t.AppliedGain_dB(first+1)<=t.AppliedGain_dB(first)-guard.gain_step_db);
assert(sum(abs(real(expected(:)))>=1 | abs(imag(expected(:)))>=1)< ...
    sum(abs(real(before(:)))>=1 | abs(imag(before(:)))>=1));
assert(all(t.AppliedGain_dB>=p.MinGain_dB & t.AppliedGain_dB<=p.MaxGain_dB));
split=sixgr.rf.runtime.AGCState(p,1); actual=zeros(size(x)); flags=false(size(x,1),1);
gains=zeros(size(x,1),1); start=1;
for stop=[1 63 64 1024 1025 1026 1030 1088 1401 size(x,1)]
    [actual(start:stop,:),part]=split.apply(x(start:stop,:),1,1);
    flags(start:stop)=part.OverloadGuardTriggered;
    gains(start:stop)=part.AppliedGain_dB;
    start=stop+1;
end
assert(isequal(actual,expected) && isequal(flags,t.OverloadGuardTriggered) && ...
    isequal(gains,t.AppliedGain_dB),'Overload response must be API-chunk invariant.');
changed=x; changed(first+2:end,:)=.01*changed(first+2:end,:);
future=sixgr.rf.runtime.AGCState(p,1); other=future.apply(changed,1,1);
assert(isequal(other(1:first+1,:),expected(1:first+1,:)));
p.OverloadGuard.enabled=false;
disabled=sixgr.rf.runtime.AGCState(p,1); [unchanged,dt]=disabled.apply(x,1,1);
assert(isequal(unchanged,before) && isequal(dt.AppliedGain_dB,bt.AppliedGain_dB));
bad=guard; bad.gain_step_db=NaN; localReject(bad);
bad=guard; bad.enabled=2; localReject(bad);
bad=guard; bad.hold_samples=.5; localReject(bad);
bad=rmfield(guard,'model'); localReject(bad);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.rf.rx.agc.targetRms==.25 && ...
    cfg.rf.frontend.receiver.agc.stream_profile.overload_guard.enabled);
rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',122.88e6,4,0,1,false);
r=rx.apply(sixgr.phy.waveform.WaveformChunk(repmat(x(:,1),1,4),0),1);
assert(r.Row.AGCOverloadGuardEnabled==1 && r.Row.AGCTargetRMS==.25 && ...
    r.Replay.AGCOverloadGuardTriggerCount== ...
    nnz(r.Replay.AGCStreamTrace.OverloadGuardTriggered));
% The metadata must reconcile on a real cropped receiver observation.
a=1001; b=1100;
obs=sixgr.phy.waveform.WaveformObservationBuffer(a-1,b,122.88e6,4);
obs.append(sixgr.phy.waveform.WaveformChunk(r.Waveform(a:b,:),a-1),122.88e6);
segment=struct('Execution',struct('StartSample',0,'EndSampleExclusive',size(x,1), ...
    'RX',struct('ID',"receiver",'Replay',r.Replay)));
plane=struct('ReceiverID',"receiver:post_rf",'Observation',obs,'Segments',{{segment}});
summary=sixgr.truth.summarizeSharedRFEndpoint(plane,"RX");
assert(summary.AGCOverloadGuardTriggerCount==nnz(r.Replay.AGCStreamTrace.OverloadGuardTriggered(a:b)));
fprintf('AGC_OVERLOAD_GUARD_PASS causal=1 split_whole_exact=1 disabled_unchanged=1 cropped_events=1\n');
ok=true;
end
function localReject(guard)
try
    sixgr.rf.runtime.AGCState.validateOverloadGuard(guard);
catch cause
    assert(string(cause.identifier)=="RF:InvalidAGCOverloadGuard"); return;
end
error('test:ExpectedGuardRejection','Malformed guard must not silently disable overload protection.');
end
