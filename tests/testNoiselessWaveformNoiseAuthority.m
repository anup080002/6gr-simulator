function ok=testNoiselessWaveformNoiseAuthority()
% Actual production waveform injector, not a decoded-link/PHY accuracy test.
% Explicit normalized occupied-RE AWGN reference; no thermal or absolute
% power claim. Quiet samples are input observations, not fabricated RX rows.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
n=(0:4096).';
original=[exp(1i*.13*n),.3*exp(-1i*.29*n)];
original(1:512,:)=0;
for direction=["DL","UL"]
    [cfg,fs]=configuration(direction);
    originalCfg=cfg;
    for precision=["double","single"]
        x=cast(original,precision);
        tx=struct('Waveform',x); info=struct('OFDM',struct('SampleRate',fs));
        initial=struct('Initialized',true,'SampleRate_Hz',fs,'UseFading',false, ...
            'Direction',direction,'Pathloss_dB',0,'ShadowFading_dB',0, ...
            'O2ILoss_dB',0,'WaveformImpairmentNextSample',913);
        states=cell(1,2);
        for modeIndex=1:2
            snrs=[Inf 12]; snr=snrs(modeIndex); active=cfg; active.channel.snr_dB=snr;
            [whole,replay,fullState]=sixgr.link.applyWaveformTruthImpairments( ...
                x,snr,initial,active,tx,info);
            assert(string(class(whole))==precision && isequal(replay.RawWaveform,x) && ...
                isequal(replay.ReceiverInputWaveform,whole) && ...
                replay.AppliedLargeScaleAmplitudeGain==1 && ...
                string(replay.PowerContextAmplitudeUnit)=="normalized_complex_baseband" && ...
                string(replay.WaveformLinkDirection)==direction && ...
                replay.AppliedAWGNSNR_dB==snr && ...
                replay.RequestedAWGNReferenceSNR_dB==snr && ...
                islogical(replay.ConfiguredAWGNNoiselessReference) && ...
                isscalar(replay.ConfiguredAWGNNoiselessReference) && ...
                replay.ConfiguredAWGNNoiselessReference==(snr==Inf));
            assert(replay.SignalEnergyPerOccupiedRE==cfg.channel.awgnReferenceREEnergy && ...
                isfinite(replay.SampleToGridNoiseVarianceGain) && ...
                replay.SampleToGridNoiseVarianceGain>0 && ...
                replay.GridNoiseVariance==cfg.channel.awgnReferenceREEnergy*10^(-snr/10) && ...
                replay.ReferenceAWGNGridNoiseVariance==replay.GridNoiseVariance && ...
                replay.InjectedNoiseVariance==replay.GridNoiseVariance/replay.SampleToGridNoiseVarianceGain && ...
                replay.ReferenceAWGNSampleNoiseVariance==replay.InjectedNoiseVariance);
            if snr==Inf
                assert(isequal(whole,x) && replay.InjectedNoiseVariance==0 && ...
                    replay.GridNoiseVariance==0 && all(whole(1:512,:)==0,'all'));
            else
                assert(replay.InjectedNoiseVariance>0 && ~isequal(whole,x) && ...
                    any(whole(1:512,:)~=0,'all'));
            end
            % One-sample and quiet boundaries must consume precisely the same
            % receiver RNG stream and original sample clock as a whole call.
            state=initial; divided=zeros(size(whole),'like',whole); first=0;
            for last=[1 37 511 512 2048 size(x,1)]
                [divided(first+1:last,:),part,state]=sixgr.link.applyWaveformTruthImpairments( ...
                    x(first+1:last,:),snr,state,active,tx,info);
                assert(part.ImpairmentStartSample==913+first && ...
                    part.ImpairmentEndSampleExclusive==913+last && ...
                    part.NoiseStreamSeed==replay.NoiseStreamSeed && ...
                    part.InjectedNoiseVariance==replay.InjectedNoiseVariance && ...
                    part.ConfiguredAWGNNoiselessReference==replay.ConfiguredAWGNNoiselessReference);
                first=last;
            end
            assert(isequal(whole,divided) && isequaln(state,fullState));
            tail=complex(zeros(19,2,precision));
            [a,ra,sa]=sixgr.link.applyWaveformTruthImpairments(tail,snr,state,active,tx,info);
            [b,rb,sb]=sixgr.link.applyWaveformTruthImpairments(tail,snr,fullState,active,tx,info);
            assert(isequal(a,b) && isequaln(ra,rb) && isequaln(sa,sb) && ...
                ra.ImpairmentStartSample==913+size(x,1) && ...
                sa.ReceiverNoiseState.NextSample==913+size(x,1)+size(tail,1));
            if snr==Inf, assert(isequal(a,tail)); else, assert(any(a~=0,'all')); end
            % Also start from an entirely quiet original capture: calibrated
            % variance must not be derived from the current sample energy.
            [quiet,qr]=sixgr.link.applyWaveformTruthImpairments(tail,snr,initial,active,tx,info);
            assert(qr.InjectedNoiseVariance==replay.InjectedNoiseVariance);
            if snr==Inf, assert(isequal(quiet,tail)); else, assert(any(quiet~=0,'all')); end
            states{modeIndex}=sa.ReceiverNoiseState;
            assert(isequaln(rng,saved),'Receiver noise must not consume global scenario RNG.');
        end
        % A zero variance call advances the same random draws as a finite
        % variance call. Variance cannot change within one retained stream.
        assert(isequal(states{1}.RandomState,states{2}.RandomState) && ...
            states{1}.Seed==states{2}.Seed && states{1}.NextSample==states{2}.NextSample);
        assert(isequaln(cfg,originalCfg) && isequal(x,cast(original,precision)));
    end
    % Full production injector must retain exact configured authority guards.
    x=original; tx=struct('Waveform',x);
    info=struct('OFDM',struct('SampleRate',fs));
    initial=struct('Initialized',true,'SampleRate_Hz',fs,'UseFading',false, ...
        'Direction',direction,'Pathloss_dB',0,'ShadowFading_dB',0,'O2ILoss_dB',0);
    thermal=cfg; thermal.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
    reject(@()sixgr.link.applyWaveformTruthImpairments(x,Inf,initial,thermal,tx,info), ...
        'sixgr:link:AbsoluteThermalNoiseAuthorityRequired');
    for badValue={NaN,-Inf,"Inf",true,[1 2],complex(1,1),[],struct()}
        bad=cfg; bad.channel.snr_dB=badValue{1};
        reject(@()sixgr.link.applyWaveformTruthImpairments(x,Inf,initial,bad,tx,info), ...
            'sixgr:link:InvalidConfiguredAWGNSNR');
    end
    underflow=cfg; underflow.channel.snr_dB=4000;
    reject(@()sixgr.link.applyWaveformTruthImpairments(x,4000,initial,underflow,tx,info), ...
        'sixgr:link:InvalidFixedReferenceNoiseVariance');
    assert(isequaln(rng,saved));
end
ok=true;
fprintf('NOISELESS_WAVEFORM_NOISE_AUTHORITY_PASS directions=2 precisions=2 reference_modes=2 physical_link_claim=0\n');
end

function [cfg,fs]=configuration(direction)
cfg=sixgr.config.defaultConfig();
cfg.run.seed=913;
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.pathlossEnabled=false; cfg.channel.snr_dB=Inf;
cfg.channel.awgnReferenceREEnergy=1;
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30, ...
    'CyclicPrefix','normal','NCellID',1,'NSlot',0,'NFrame',0);
cfg.phy.impairments.cfoEnabled=false; cfg.phy.impairments.cfoHz=0;
cfg.phy.impairments.timingOffsetEnabled=false; cfg.phy.impairments.timingOffsetSamples=0;
cfg.phy.impairments.phaseNoiseEnabled=false; cfg.rf.phaseNoise.enable=false;
cfg.rf.pa.enable=false;
cfg.powerAndRF.bsTxGain_dB=0; cfg.powerAndRF.ueTxGain_dB=0;
cfg.powerAndRF.bsRxGain_dB=0; cfg.powerAndRF.ueRxGain_dB=0;
cfg.powerAndRF.dlImplementationLoss_dB=0; cfg.powerAndRF.ulImplementationLoss_dB=0;
cfg.scenario.bs.txGain_dBi=0; cfg.scenario.bs.rxGain_dBi=0;
cfg.scenario.ue.txGain_dBi=0; cfg.scenario.ue.rxGain_dBi=0;
cfg.lls6g.userContext=struct('RuntimeCurrentDirection',direction,'Direction',direction, ...
    'UEIndex',1,'RuntimeServingCellIndex',1);
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier); fs=double(ofdm.SampleRate);
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingNoiseAuthorityRejection','Expected %s.',id);
end
