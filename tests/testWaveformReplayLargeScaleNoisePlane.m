function ok = testWaveformReplayLargeScaleNoisePlane()
% A supplied receive SINR must not incur large-scale attenuation twice.
% This tests coordinate scaling of the same SINR, not pathloss invariance
% at fixed transmitter power and a fixed absolute thermal-noise level.
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.useMex = false;
cfg.channel.model = 'AWGN';
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.phy.ssb.enable = false;
cfg.phy.csirs.enable = false;
cfg.phy.ptrs.enable = false;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.pdsch.dmrs.portSet = 0;
cfg.phy.pusch.dmrs.portSet = 0;
cfg.phy.pusch.transformPrecoding = false;
cfg.phy.pdsch.xOverhead = 0;
cfg.phy.pusch.xOverhead = 0;
grant = struct('RNTI',73,'PRBSet',0:5,'SymbolAllocation',[2 10], ...
    'MappingType','A','Modulation','QPSK','NumLayers',1,'TargetCodeRate',0.3,'RV',0);

for direction = ["DL","UL"]
    % The seed and coded payload are identical for all amplitude planes.
    loss = [0 60 110];
    replay = cell(1,numel(loss));
    for index = 1:numel(loss)
        cfg.lls6g.userContext = struct('RuntimeCurrentDirection',char(direction), ...
            'RuntimeServingPathloss_dB',loss(index), ...
            'RuntimeServingBasePathloss_dB',loss(index), ...
            'RuntimeServingShadowFading_dB',0,'RuntimeServingO2I_dB',0);
        replay{index} = sixgr.system.waveform.replayGrant(cfg,direction,grant,[],30, ...
            'StrictMode',true,'FastAWGNPath',false,'NoiseSeed',73001,'ChannelSeed',73002);
    end
    low = replay{1};
    for index = 2:numel(loss)
        attenuated = replay{index};
        assert(low.Ok && attenuated.Ok && ...
            low.TransmittedTransportBlockSHA256 == attenuated.TransmittedTransportBlockSHA256, ...
            'An equivalent receive SINR must recover the same coded payload at both amplitude planes.');
        gainRatio = 10^((attenuated.AppliedLargeScaleGain_dB-low.AppliedLargeScaleGain_dB)/10);
        assert(abs(10*log10(gainRatio)+loss(index))<1e-10, ...
            'The diagnostic must actually execute the requested additional sample attenuation.');
        assert(abs(attenuated.AWGNGridNoiseVariance/low.AWGNGridNoiseVariance/gainRatio-1)<1e-10 && ...
            abs(attenuated.AWGNSampleNoiseVariance/low.AWGNSampleNoiseVariance/gainRatio-1)<1e-10, ...
            'Noise must use the same applied large-scale power plane as the receive SINR.');
        assert(abs(attenuated.EVM_rms-low.EVM_rms)<1e-4, ...
            'Matched-noise realizations must give equivalent receiver EVM after common amplitude scaling.');
    end
end
fprintf('WAVEFORM_REPLAY_LARGE_SCALE_NOISE_PASS: DL/UL, 60/110 dB gain closure, matched noise and CRC\n');
ok = true;
end
