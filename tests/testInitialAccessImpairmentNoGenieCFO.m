function ok=testInitialAccessImpairmentNoGenieCFO()
% The physical producer must not use exact TX samples as a receiver oracle.
setup6GRSimToolkit("Verbose",false);
cfg=sixgr.config.defaultConfig();
cfg.channel.model="AWGN";
cfg.channel.awgnOnly=true;
cfg.channel.pathlossEnabled=false;
cfg.channel.snr_dB=12;
cfg.run.noiseOperatingMode="standalone_awgn_snr_argument";
cfg.phy.impairments.cfoEnabled=true;
cfg.phy.impairments.cfoHz=1234;
cfg.phy.impairments.timingOffsetSamples=0;
cfg.phy.impairments.phaseNoiseEnabled=false;
cfg.rf.phaseNoise.enable=false;
cfg.phy.rx.cfoCompensation=true;
fs=7.68e6;
n=(0:4095).';
x=[exp(1j*.19*n),.4*exp(-1j*.31*n)];
tx=struct("Waveform",x);
info=struct("OFDM",struct("SampleRate",fs));
state=struct("Initialized",true,"SampleRate_Hz",fs,"UseFading",false, ...
    "Pathloss_dB",0,"ShadowFading_dB",0,"O2ILoss_dB",0);
initialRNG=rng;
cleanup=onCleanup(@()rng(initialRNG)); %#ok<NASGU>
rng(4831);
[withFlag,replay]=sixgr.link.applyWaveformTruthImpairments(x,12,state,cfg,tx,info);
cfg.phy.rx.cfoCompensation=false;
rng(4831);
[withoutFlag,replayOff]=sixgr.link.applyWaveformTruthImpairments(x,12,state,cfg,tx,info);
expected=x.*replay.AppliedLargeScaleAmplitudeGain.*exp(1j*2*pi*1234/fs*n);
assert(norm(replay.RawWaveform-expected,'fro')<1e-12*norm(expected,'fro'));
assert(isequal(withFlag,withoutFlag) && isequaln(replay,replayOff), ...
    "A receiver correction flag must not pre-correct the physical channel output.");
assert(~replay.CFOCorrectionApplied && isnan(replay.EstimatedCFO_PreCorrection_Hz) && ...
    isnan(replay.ResidualCFO_PostCorrection_Hz));
assert(replay.InjectedCFO_Hz==1234 && ...
    string(replay.CFOCorrectionAuthority)=="receiver_synchronization_after_noise");
assert(isequal(replay.RawWaveform,replay.CorrectedWaveform));
assert(replay.InjectedNoiseVariance>0 && norm(withFlag-expected,'fro')>0);
assert(isequal(withFlag,replay.ReceiverInputWaveform));
fprintf('INITIAL_ACCESS_IMPAIRMENT_NO_GENIE_CFO_PASS: injected CFO retained until noisy receiver input.\n');
ok=true;
end
