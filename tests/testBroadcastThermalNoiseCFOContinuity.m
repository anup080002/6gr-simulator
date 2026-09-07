function ok = testBroadcastThermalNoiseCFOContinuity()
% Production thermal-noise/CFO path, including quiet and one-sample chunks.
% Phase noise, timing interpolation and fixed-SNR chunk semantics are NOT
% qualified by this check; those remaining streaming boundaries stay explicit.
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.channel.model = 'AWGN';
cfg.channel.awgnOnly = true;
cfg.channel.pathlossEnabled = false;
cfg.run.noiseOperatingMode = 'receiver_noise_figure_thermal_noise';
cfg.phy.impairments.cfoEnabled = true;
cfg.phy.impairments.cfoHz = 7500;
cfg.phy.impairments.timingOffsetSamples = 0;
cfg.phy.impairments.phaseNoiseEnabled = false;
cfg.rf.phaseNoise.enable = false;
fs = 7.68e6;
n = (0:8192).';
x = [exp(1i*.13*n), .3*exp(-1i*.29*n)];
x(1:512,:) = 0;
tx = struct('Waveform',x);
info = struct('OFDM',struct('SampleRate',fs));
initialRNG = rng;
cleanup = onCleanup(@()rng(initialRNG)); %#ok<NASGU>
for origin = [0 913]
    initial = struct('Initialized',true,'SampleRate_Hz',fs,'UseFading',false, ...
        'Pathloss_dB',0,'ShadowFading_dB',0,'O2ILoss_dB',0, ...
        'WaveformImpairmentNextSample',origin);
    [whole,replay,fullState] = sixgr.link.applyWaveformTruthImpairments(x,12,initial,cfg,tx,info);
    expected = x.*replay.AppliedLargeScaleAmplitudeGain .* ...
        exp(1i*2*pi*(7500/fs)*(origin+n));
    assert(isequal(replay.RawWaveform,expected), 'CFO must use the actual absolute sample phase.');
    assert(replay.InjectedNoiseVariance == sixgr.link.resolveReceiverThermalNoiseVariance(replay));
    assert(replay.InjectedNoiseVariance == ...
        10^(replay.ThermalNoisePower_dBm/10)*fs/replay.NoiseBandwidth_Hz);
    assert(any(abs(whole(1:512,:))>0,'all'), 'Quiet samples must retain receiver thermal noise.');
    state = initial;
    divided = zeros(size(whole),'like',whole);
    first = 0;
    for last = [1 37 511 512 2048 4097 size(x,1)]
        [divided(first+1:last,:),chunkReplay,state] = ...
            sixgr.link.applyWaveformTruthImpairments(x(first+1:last,:),12,state,cfg,tx,info);
        assert(chunkReplay.ImpairmentStartSample == origin+first && ...
            chunkReplay.ImpairmentEndSampleExclusive == origin+last);
        assert(chunkReplay.InjectedNoiseVariance == replay.InjectedNoiseVariance && ...
            chunkReplay.NoiseStreamSeed == replay.NoiseStreamSeed);
        first = last;
    end
    assert(isequal(whole,divided) && isequaln(state.ReceiverNoiseState,fullState.ReceiverNoiseState));
    assert(isequaln(rng,initialRNG), 'Thermal receiver draws must not consume the scenario global RNG.');
    otherUE = sixgr.util.structSet(cfg,'lls6g.userContext.UEIndex',2);
    [other,otherReplay] = sixgr.link.applyWaveformTruthImpairments(x,12,initial,otherUE,tx,info);
    assert(otherReplay.NoiseStreamSeed~=replay.NoiseStreamSeed && ~isequal(other,whole), ...
        'Independent AWGN receivers must not share a noise realization when no fading link key exists.');
    assert(isequal(otherReplay.RawWaveform,replay.RawWaveform));
end
ok = true;
disp('BROADCAST_THERMAL_NOISE_CFO_CONTINUITY_PASS');
end
