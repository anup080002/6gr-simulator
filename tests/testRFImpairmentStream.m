function ok=testRFImpairmentStream()
% Actual OFDM sample processing, not a complete RF conformance campaign.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
profile=cfg.rf.frontend.receiver.agc.stream_profile;
assert(string(profile.control_model)=="causal_windowed_joint_rms_attack_hold_release");
% Configuration-only parity; no FDD waveform run is launched here.
fdd=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring.yaml'));
fddCfg=sixgr.lls6g.buildInternalConfig(fdd,tempname);
assert(isequaln(fddCfg.rf.frontend.receiver.agc.stream_profile,profile));
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',15);
source=RandStream('Threefry','Seed',25);
bits=randi(source,[0 3],288,14,2);
grid=exp(1j*(pi/4+pi/2*bits));
[x,info]=nrOFDMModulate(carrier,grid,'Windowing',0);
x(1:floor(end/2),:)=x(1:floor(end/2),:)*.1;
fs=info.SampleRate; first=123; epoch=7;
cfg.rf.rx.agc.enable=true; cfg.rf.rx.agc.targetRms=.25;
cfg.rf.rx.agc.minGain_dB=-80; cfg.rf.rx.agc.maxGain_dB=80;
cfg.rf.adc.enable=true; cfg.rf.adcBits=12; cfg.rf.adc.fullScale=1;
cfg.rf.frontend.receiver.adc.dither_rms=1e-5;
cfg.rf.frontend.receiver.adc.aperture_jitter_s=1e-10;
cfg.rf.rx.cfo_Hz=1300; cfg.rf.tx.cfo_Hz=-700;
cfg.rf.rx.timingOffsetSamples=7; cfg.rf.tx.timingOffsetSamples=3;
cfg.rf.rx.phaseNoise.enable=false; cfg.rf.tx.phaseNoise.enable=false;
cfg.rf.pa.enable=false;
saved=rng;
for direction=["DL","UL"]
  for endpoint=["tx","rx"]
    whole=sixgr.rf.runtime.RFImpairmentStream(cfg,endpoint,direction,fs,2,first,epoch,false);
    split=sixgr.rf.runtime.RFImpairmentStream(cfg,endpoint,direction,fs,2,first,epoch,false);
    expected=whole.apply(sixgr.phy.waveform.WaveformChunk(x,first),epoch);
    y=zeros(size(x),'like',x); gains=zeros(0,1); start=0;
    for stop=unique([1 17 73 777 size(x,1)])
        chunk=sixgr.phy.waveform.WaveformChunk(x(start+1:stop,:),first+start);
        if endpoint=="rx"
            [part,replay]=sixgr.link.applyCompositeReceiverFrontEnd(chunk.Samples,cfg,fs,struct(), ...
                'Direction',direction,'UseLegacyGlobalConfig',false,'Stream',split, ...
                'StartSample',chunk.StartSample,'ConfigurationEpoch',epoch);
        else
            result=split.apply(chunk,epoch); part=result.Waveform; replay=result.Replay;
        end
        assert(replay.RFStreamStartSample==first+start && replay.RFStreamEndSampleExclusive==first+stop);
        assert(replay.RFProcessingMode=="retained_sample_stream" && replay.AGCDecisionCausal);
        y(start+1:stop,:)=part;
        if endpoint=="rx", gains=[gains;replay.AGCStreamTrace.AppliedGain_dB]; end %#ok<AGROW>
        start=stop;
    end
    assert(isequal(y,expected.Waveform),'%s %s samples changed at API chunk boundaries.',direction,endpoint);
    if endpoint=="rx"
        assert(isequal(gains,expected.Replay.AGCStreamTrace.AppliedGain_dB));
        assert(all(gains(1:profile.update_period_samples)==0), ...
            'The first detector window must not use gain computed from itself.');
        assert(expected.Replay.AGCGainIsTimeVarying && isnan(expected.Replay.AGCGain_dB));
        assert(expected.Replay.AGCStreamTrace.StartSample==first);
    end
    next=first+size(x,1);
    localError(@()split.apply(sixgr.phy.waveform.WaveformChunk(x(1:3,:),next+1),epoch),'RF:StreamClockDiscontinuity');
    localError(@()split.apply(sixgr.phy.waveform.WaveformChunk(x(1:3,:),next),epoch+1),'RF:StateEpochMismatch');
    assert(~split.Faulted && split.NextSampleIndex==next);
    a=split.apply(sixgr.phy.waveform.WaveformChunk(x(1:11,:),next),epoch);
    b=whole.apply(sixgr.phy.waveform.WaveformChunk(x(1:11,:),next),epoch);
    assert(isequal(a.Waveform,b.Waveform),'Rejected preflight mutated retained RF state.');
  end
end
assert(isequal(rng,saved),'Retained RF must not reset or consume the global random stream.');
legacy=sixgr.rf.applyRFImpairmentChain(x,cfg,'Endpoint','rx','SampleRateHz',fs, ...
    'UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
assert(legacy.Replay.AGCControlModel=="noncausal_same_block_rms" && ~legacy.Replay.AGCDecisionCausal);
% Export actual RF executions, preserving the block-vs-stream distinction.
% This temporary unit artifact is not a production-run result.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path=fullfile(folder,'actual_rf_execution_rows.csv');
writetable(struct2table([legacy.Row;expected.Row]),path);
rows=readtable(path,'TextType','string');
assert(rows.RFProcessingMode(1)=="independent_block" && ~rows.AGCDecisionCausal(1));
assert(rows.RFProcessingMode(2)=="retained_sample_stream" && rows.AGCDecisionCausal(2));
assert(rows.AGCControlModel(1)=="noncausal_same_block_rms" && ...
    rows.AGCControlModel(2)=="causal_windowed_joint_rms_attack_hold_release");
only=sixgr.rf.applyRFImpairmentChain([],cfg,'Endpoint','rx','SampleRateHz',fs,'ResolveOnly',true);
assert(only.ExecutionStage=="configured_not_executed" && ~isfield(only,'Waveform') && ~isfield(only,'Row'));
bad=cfg; bad.rf.frontend.receiver.agc=rmfield(bad.rf.frontend.receiver.agc,'stream_profile');
localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'rx','UL',fs,2,0,epoch,false),'RF:ImplicitAGCForbidden');
bad=cfg; bad.rf.rx.timingOffsetSamples=.5;
localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'rx','UL',fs,2,0,epoch,false),'RF:StreamingFractionalTimingRequiresClockBridge');
bad=cfg; bad.rf.rx.sampleClockOffset.ppm=20;
localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'rx','UL',fs,2,0,epoch,false),'RF:StreamingSampleClockRequiresClockBridge');
localError(@()sixgr.link.applyCompositeReceiverFrontEnd(x,cfg,NaN,struct()),'RF:CompositeSampleRateRequired');
localError(@()sixgr.link.applyCompositeReceiverFrontEnd(x,cfg,fs,struct(),'Direction','UX'),'RF:InvalidCompositeDirection');
for bits=[0 1 NaN 25 31 32 12.5]
    bad=struct(); bad.rf.adc.enable=true; bad.rf.adcBits=bits;
    localError(@()sixgr.rf.runtime.RFImpairmentStream(bad,'rx','UL',fs,2,0,epoch,false),'RF:ADCProfileMissing');
end
ok=true;
disp('RF_IMPAIRMENT_STREAM_PASS: exact split/whole TX/RX, causal AGC, retained ADC/delay/CFO state.');
end

function localError(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:ExpectedError','Expected %s.',id);
end
