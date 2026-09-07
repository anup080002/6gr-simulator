function ok=testRFStreamMemoryAndPhase()
% Exact state retention and analytic memory checks, not PA calibration or
% RF device conformance. Input backoff precedes PA nonlinearity.
setup6GRSimToolkit('Verbose',false);
fs=7.68e6; epoch=9; origin=31;
r=RandStream('Threefry','Seed',613);
x=.2*complex(randn(r,1024,2),randn(r,1024,2));
saved=rng;
cfg=struct(); cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.configurationEpoch=epoch; cfg.phy.fc_Hz=2.35e9;
cfg.rf.frontend.phase_noise=struct('profile_id','unit_explicit_mask', ...
    'version','1','mask_offsets_hz',[1e3 1e4 1e5], ...
    'mask_levels_dbchz',[-85 -95 -110],'lo_correlation',.5,'seed',17);
cfg.rf.frontend.pa=struct('profile_id','unit_identified_coefficients', ...
    'version','1','input_backoff_db',2,'model','memory_polynomial', ...
    'coefficients',[1 .1;-.1 .02],'orders',[1 3],'memory_depth',2);
for direction=["DL","UL"]
  for endpoint=["tx","rx"]
    c=cfg; c.rf.(endpoint).phaseNoise.enable=true;
    c.rf.pa.enable=endpoint=="tx";
    whole=sixgr.rf.runtime.RFImpairmentStream(c,endpoint,direction,fs,2,origin,epoch,false);
    split=sixgr.rf.runtime.RFImpairmentStream(c,endpoint,direction,fs,2,origin,epoch,false);
    expected=whole.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch);
    actual=zeros(size(x),'like',x); first=0;
    for last=[1 2 3 39 128 1024]
        out=split.apply(sixgr.phy.waveform.WaveformChunk(x(first+1:last,:),origin+first),epoch);
        actual(first+1:last,:)=out.Waveform; first=last;
    end
    assert(isequal(actual,expected.Waveform),'RF memory/phase state changed with partition boundaries.');
    assert(expected.Replay.PhaseNoiseApplied);
    assert(norm(actual-x,'fro')>0);
  end
end
assert(isequal(saved,rng),'Canonical oscillators must not consume the global RNG.');
% A one-order, three-tap profile has three memory columns, not three orders.
c=cfg; c.rf.pa.enable=true;
c.rf.frontend.pa.coefficients=[1 .25 -.125];
c.rf.frontend.pa.orders=1; c.rf.frontend.pa.memory_depth=3;
owner=sixgr.rf.runtime.RFImpairmentStream(c,'tx','UL',fs,2,origin,epoch,false);
result=owner.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch);
expected=filter([1 .25 -.125],1,x)*10^(-2/20);
assert(norm(result.Waveform-expected,'fro')<1e-12*norm(expected,'fro'));
direct=sixgr.rf.runtime.oracle.MemoryPolynomialSpec.apply(x,[1 .25 -.125],1);
assert(norm(direct-filter([1 .25 -.125],1,x),'fro')<1e-12*norm(x,'fro'));
tail=owner.apply(sixgr.phy.waveform.WaveformChunk(zeros(2,2),origin+size(x,1)),epoch);
flushed=filter([1 .25 -.125],1,[x;zeros(2,2)])*10^(-2/20);
assert(norm(tail.Waveform-flushed(end-1:end,:),'fro')<1e-12);
% Nonlinear backoff is NOT equivalent to an attenuator after saturation.
[profile,~]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg);
[y,evidence]=sixgr.rf.runtime.PAProfile.apply(x,profile);
driven=x*10^(-profile.InputBackoff_dB/20);
oracle=sixgr.rf.runtime.oracle.MemoryPolynomialSpec.apply( ...
    driven,profile.Coefficients,profile.Orders);
assert(norm(y-oracle,'fro')<1e-12*norm(oracle,'fro'));
postAttenuated=sixgr.rf.runtime.oracle.MemoryPolynomialSpec.apply( ...
    x,profile.Coefficients,profile.Orders)*10^(-profile.InputBackoff_dB/20);
assert(norm(y-postAttenuated,'fro')>1e-6);
assert(evidence.BackoffReferencePlane=="before_pa_nonlinearity" && ~evidence.PowerRestorationApplied);
% Physical stream columns are already mapped. A configured logical-port
% beamforming matrix must not be applied again inside analog element RF.
c=struct(); c.rf.tx.element.enable=true; c.rf.tx.element.gain_dB=[0 6];
c.rf.tx.element.phase_deg=[0 90]; c.rf.bs.PortToElementMatrix=[1 1;1 -1]/sqrt(2);
owner=sixgr.rf.runtime.RFImpairmentStream(c,'tx','DL',fs,2,origin,epoch,false);
result=owner.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch);
assert(norm(result.Waveform-x.*[1 10^(6/20)*1j],'fro')<1e-12*norm(x,'fro'));
bad=c; bad.rf.tx.element.gain_dB=[0 NaN];
localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,2,0,epoch,false),'sixgr:rf:InvalidElementRFVector');
% Preflight oscillator epoch mismatches cannot silently reset an LO.
bad=cfg; bad.rf.tx.phaseNoise.enable=true;
localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,2,0,epoch+1,false),'RF:StateEpochMismatch');
% A stateful-stage exception permanently poisons that owner.
bad=cfg; bad.rf.tx.element.enable=true; bad.rf.tx.element.gain_dB=[0 1 2];
broken=sixgr.rf.runtime.RFImpairmentStream(bad,'tx','UL',fs,2,origin,epoch,false);
failed=false;
try, broken.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch); catch cause
    assert(string(cause.identifier)=="sixgr:rf:ElementRFVectorSizeMismatch"); failed=true;
end
assert(failed && broken.Faulted);
localError(@()broken.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch),'RF:FaultedStream');
% Retain the earlier rejected-mask case as a negative test. No relaxed
% tolerance or substituted phase-noise process is allowed on failure.
bad=cfg; bad.rf.tx.phaseNoise.enable=true;
bad.rf.frontend.phase_noise.mask_levels_dbchz=[-80 -100 -120];
broken=sixgr.rf.runtime.RFImpairmentStream(bad,'tx','UL',fs,2,origin,epoch,false);
localError(@()broken.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch),'RF:PhaseNoiseMaskFitFailed');
assert(broken.Faulted);
ok=true;
disp('RF_STREAM_MEMORY_PHASE_PASS: retained DL/UL oscillators, PA memory, exact analytic taps and fault handling.');
end

function localError(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:ExpectedError','Expected %s.',id);
end
