function ok=testADCConfigurationAuthority()
% Isolate the ADC, then compare both execution adapters with the actual
% quantizer. No channel/noise/AGC is fitted to obtain agreement.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'master_sinr_sweep.yaml'));
s=s.toStruct();
s.impairments.adc_quantization_enabled=true;
s.rf_frontend.receiver.adc.enabled=true;
s.rf_frontend.receiver.adc.bits=5;
s.rf_frontend.receiver.adc.full_scale=.7;
s.rf_frontend.receiver.adc.convention='signed_midrise';
s.rf_frontend.receiver.adc.dither_enabled=true;
s.rf_frontend.receiver.adc.dither_rms=.03;
s.rf_frontend.receiver.adc.aperture_jitter_seconds=3e-10;
s.rf_frontend.receiver.adc.inl_lsb=.11;
s.rf_frontend.receiver.adc.dnl_lsb=.07;
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
% Retain the installed ADC fields, but explicitly isolate its execution
% from every other RF stage. This is a component test, not a master run.
cfg=struct('run',struct('seed',391));
cfg.rf.adc=installed.rf.adc;
cfg.rf.adcBits=installed.rf.adcBits;
cfg.rf.frontend.receiver.adc=installed.rf.frontend.receiver.adc;
fs=122.88e6;
n=(0:1008).';
x=[.79*exp(1j*.13*n) .56*exp(-1j*.39*n)];
saved=rng;
for convention=["signed_midrise","signed_midtread"]
    cfg.rf.frontend.receiver.adc.convention=convention;
    expectedProfile=struct('Bits',5,'FullScale',.7,'Convention',convention, ...
        'DitherRMS',.03,'ApertureJitter_s',3e-10,'INL_LSB',.11, ...
        'DNL_LSB',.07,'Seed',391,'SampleRate_Hz',fs);
    expected=sixgr.rf.runtime.ADCModel.quantize(x,expectedProfile);
    actual=localApply(x,cfg,fs);
    assert(isequal(actual.Waveform,expected.Output), ...
        'sixgr:test:ADCProfileNotApplied','Block RF must execute the entire installed ADC profile.');
    assert(isequal(actual.Config.RxADC.Profile,expectedProfile));
    assert(actual.Replay.ADCClippingRatio==expected.ClippingRatio);
    assert(actual.Replay.ADCApertureJitterSecondsConfigured==3e-10 && ...
        actual.Replay.ADCDitherRMSConfigured==.03 && ...
        actual.Replay.ADCConventionConfigured==convention);
    whole=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',fs,2,113,2,false);
    split=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',fs,2,113,2,false);
    one=whole.apply(sixgr.phy.waveform.WaveformChunk(x,113),2);
    assert(isequal(one.Waveform,expected.Output));
    y=zeros(size(x),'like',x); first=0; clipped=0; population=0;
    for stop=[1 7 131 765 size(x,1)]
        part=split.apply(sixgr.phy.waveform.WaveformChunk(x(first+1:stop,:),113+first),2);
        y(first+1:stop,:)=part.Waveform;
        clipped=clipped+part.Replay.ADCClippedSampleCount;
        population=population+part.Replay.ADCClippingSampleCount;
        first=stop;
    end
    assert(isequal(y,expected.Output) && clipped==nnz(expected.Clipped) && population==numel(x));
end
assert(isequal(rng,saved),'ADC execution must not consume the global random stream.');
bad=cfg; bad.rf.frontend.receiver.adc.aperture_jitter_s=4e-10;
localError(@()localApply(x,bad,fs),'RF:ADCProfileConflict');
bad=cfg; bad.rf.frontend.receiver.adc.dither_enabled=false;
localError(@()localApply(x,bad,fs),'RF:ADCProfileMissing');
bad=cfg; bad.rf.frontend.receiver.adc.convention='unsupported';
localError(@()localApply(x,bad,fs),'RF:ADCProfileMissing');
bad=cfg; bad.rf.frontend.receiver.adc.aperture_jitter_seconds=-1;
localError(@()localApply(x,bad,fs),'RF:ADCProfileMissing');
% Supported legacy jitter alias must have the same semantics, never silent
% precedence over a contradictory canonical value.
alias=cfg; alias.rf.frontend.receiver.adc=rmfield(alias.rf.frontend.receiver.adc,'aperture_jitter_seconds');
alias.rf.frontend.receiver.adc.aperture_jitter_s=3e-10;
aliasOut=localApply(x,alias,fs);
assert(isequal(aliasOut.Waveform,actual.Waveform));
quiet=cfg; quiet.rf.frontend.receiver.adc.dither_enabled=false;
quiet.rf.frontend.receiver.adc.dither_rms=0;
quiet.rf.frontend.receiver.adc.aperture_jitter_seconds=0;
quietOut=localApply(x,quiet,fs);
expectedProfile.DitherRMS=0; expectedProfile.ApertureJitter_s=0;
quietExpected=sixgr.rf.runtime.ADCModel.quantize(x,expectedProfile);
assert(isequal(quietOut.Waveform,quietExpected.Output) && ~isequal(quietOut.Waveform,actual.Waveform));
off=cfg; off.rf.adc.enable=false;
offOut=localApply(10*x,off,fs);
assert(isequal(offOut.Waveform,10*x) && ~offOut.Replay.ADCQuantizationExecuted && isnan(offOut.Replay.ADCClippingRatio));
fprintf('ADC_CONFIGURATION_AUTHORITY_PASS block_stream_profile_parity=1 canonical_jitter=1\n');
ok=true;
end

function out=localApply(x,cfg,fs)
out=sixgr.rf.applyRFImpairmentChain(x,cfg,'SampleRateHz',fs, ...
    'Endpoint','rx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
end

function localError(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); return; end
error('sixgr:test:ExpectedADCGuard','Expected %s.',id);
end
