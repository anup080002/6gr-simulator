function ok=testReceiverAbsoluteThermalNoise()
% Physical power-domain contract, independent of geometry/SNR/rank/ports.
setup6GRSimToolkit('Verbose',false);
base=struct('NoiseOperatingMode','receiver_noise_figure_thermal_noise', ...
    'PowerContextAmplitudeUnit','sqrt_mW','ThermalNoisePower_dBm',NaN, ...
    'NoiseBandwidth_Hz',NaN,'SampleRate_Hz',NaN);
for fs=[7.68e6 30.72e6]
 for bandwidth=[5e6 20e6]
  for nf=[5 9]
    r=base; r.SampleRate_Hz=fs; r.NoiseBandwidth_Hz=bandwidth;
    r.ThermalNoisePower_dBm=-174+10*log10(bandwidth)+nf;
    expected=10^((-174+nf)/10)*fs;
    variance=sixgr.link.resolveReceiverThermalNoiseVariance(r);
    assert(abs(variance-expected)<1e-12*expected);
    for serving=[-5.43 -54.18 -123.73 NaN]
        r.ServingRxPower_dBm=serving; r.ServingRSRP_dBm=serving;
        r.ConfiguredSNR_dB=25; r.AppliedAWGNSNR_dB=12;
        r.DesiredSignalPowerBeforeNoise=1e-3;
        assert(sixgr.link.resolveReceiverThermalNoiseVariance(r)==variance);
    end
  end
 end
end
% The same receiver noise realization is independent of desired waveform
% amplitude. A silent branch still has noise; adding RX branches does not
% divide the per-branch physical thermal variance.
n=100003; signal=complex(ones(n,3));
[noisy,~]=sixgr.link.addRuntimeComplexNoise(signal,variance,913,0,struct());
[quiet,~]=sixgr.link.addRuntimeComplexNoise(complex(zeros(n,3)),variance,913,0,struct());
assert(norm((noisy-signal)-quiet,'fro')<1e-9*norm(quiet,'fro'));
assert(all(abs(mean(abs(quiet).^2,1)/variance-1)<.025));
r=base; r.NoiseBandwidth_Hz=5e6; r.SampleRate_Hz=7.68e6;
r.ThermalNoisePower_dBm=-100;
bad=r; bad.PowerContextAmplitudeUnit='normalized';
localError(@()sixgr.link.resolveReceiverThermalNoiseVariance(bad), ...
    'sixgr:link:AbsoluteThermalNoiseAuthorityRequired');
bad=r; bad.NoiseOperatingMode='standalone_awgn_snr_argument';
localError(@()sixgr.link.resolveReceiverThermalNoiseVariance(bad), ...
    'sixgr:link:AbsoluteThermalNoiseAuthorityRequired');
% Exercise the common replay producer with real physical sample units.
cfg=sixgr.config.defaultConfig(); cfg.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
cfg.channel.bandwidth_Hz=5e6;
for direction=["DL","UL"]
    cfg.lls6g.userContext.RuntimeCurrentDirection=direction;
    [~,replay]=sixgr.link.applyWaveformImpairments(complex(zeros(3,2)),cfg,7.68e6,'ApplyRFChain',false);
    assert(replay.ThermalSampleNoiseBandwidth_Hz==7.68e6);
    assert(replay.ThermalSampleNoiseVariance_mW==sixgr.link.resolveReceiverThermalNoiseVariance(replay));
    assert(string(replay.AppliedAWGNSNRValueRole)=="link_budget_prediction_not_measured_SINR_or_noise_control");
    % Verify the actual shared receiver in explicitly thermal-noise mode.
    owner=sixgr.truth.SharedWaveformPhysicalRuntime(7.68e6,0,1);
    owner.addTransmitter('silent',cfg,direction,2,false);
    owner.addReceiver('receiver',cfg,direction,2,false);
    input=struct('ID',"silent",'Chunk',sixgr.phy.waveform.WaveformChunk( ...
        complex(zeros(n,2)),0));
    [physical,execution]=owner.process(input,0,n,[]);
    applied=execution.RX.Replay;
    assert(isnan(applied.AppliedAWGNSNR_dB) && ...
        applied.AppliedAWGNSNRSource=="not_applicable_thermal_noise", ...
        'Thermal noise must not acquire a fictitious fixed-AWGN SNR.');
    assert(applied.InjectedNoiseVariance==replay.ThermalSampleNoiseVariance_mW);
    samples=physical(string({physical.ID})=="receiver:pre_rf").Chunk.Samples;
    assert(all(abs(mean(abs(samples).^2,1)/applied.InjectedNoiseVariance-1)<.025));
end
ok=true;
disp('RECEIVER_ABSOLUTE_THERMAL_NOISE_PASS: PSD*Fs, no serving-RSRP/fading/port-count scaling.');
end
function localError(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id); return;
end
error('test:ExpectedError','Expected %s.',id);
end
