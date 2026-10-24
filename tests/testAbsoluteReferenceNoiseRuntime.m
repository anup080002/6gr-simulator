function ok=testAbsoluteReferenceNoiseRuntime()
% Actual shared receiver noise/RF execution and native OFDM units. No fading,
% decoded signal, scheduler, measured target-SINR or campaign qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
before=rng;
groups={@absolute,@legacy,@guards}; names=["absolute_native_OFDM_DL_UL","legacy_thermal_normalized","receipt_and_unknown_mode_guards"];
failures=strings(0,1);
for k=1:numel(groups)
    try
        groups{k}(); fprintf('ABSOLUTE_REFERENCE_RUNTIME %s PASS\n',names(k));
    catch cause
        failures(end+1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'%s\n',getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(isequal(before,rng),'test:NoiseGlobalRNG','Physical noise must use its retained private stream.');
assert(isempty(failures),'test:AbsoluteReferenceNoiseRuntime','%s',strjoin(failures,newline));
ok=true;
fprintf('ABSOLUTE_REFERENCE_RUNTIME_PASS groups=3 channel_executions=0 decoded_target_SINR_claim=0\n');
end

function absolute()
for scs=[15 30]
    for direction=["DL","UL"]
        [cfg,carrier,fs]=configuration("absolute_reference_esn0",scs);
        sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
        [metadata,configured]=sixgr.truth.resolveCoupledReplaySNR(cfg,cfg.channel.snr_dB);
        assert(isnan(metadata)&&~configured,'A reference label is not receiver SINR.');
        [variance,reference]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,direction,fs);
        [samples,ledger,nfft]=execute(cfg,carrier,fs,direction);
        assert(isequaln(ledger.AbsoluteReferenceNoise,reference)&& ...
            ledger.AbsoluteReferenceNoiseInjectedSampleVariance_mW==variance&& ...
            isnan(ledger.AppliedAWGNSNR_dB)&&isnan(ledger.ThermalNoisePSD_mWPerHz)&& ...
            isequal(ledger.ThermalNoiseApplied,false)&&isequal(ledger.ControlledReferenceNoiseApplied,true));
        pub=sixgr.link.absoluteReferenceNoisePublication(ledger);
        assert(pub.AbsoluteReferenceNoiseEvidenceAvailable&& ...
            pub.ReferenceNoiseContractSHA256==reference.ReferenceContractSHA256&& ...
            pub.AbsoluteReferenceNoiseInjectedSampleVariance_mW==variance);
        raw=nrOFDMDemodulate(carrier,samples);
        physicalRE=raw/(double(nfft)*sqrt(1000));
        expectedW=reference.NoisePSD_mWPerHz*1000*scs/1000;
        actualW=mean(abs(physicalRE).^2,'all');
        nearStat(actualW,expectedW);
        fprintf('ABSOLUTE_NOISE_OBS direction=%s scs_kHz=%g Fs=%g N0_mWHz=%.17g sample_expected=%.17g sample_observed=%.17g RE_expected_W=%.17g RE_observed_W=%.17g\n', ...
            direction,scs,fs,reference.NoisePSD_mWPerHz,variance,mean(abs(samples).^2,'all'),expectedW,actualW);
        % Actual emitter amplitude and RF/device budget are not reference inputs.
        changed=cfg; changed.powerAndRF.bsTxPower_dBm=47; changed.powerAndRF.ueTxPower_dBm=12;
        changed.rf.noiseFigure_dB=41;
        changed=sixgr.util.structSet(changed,'lls6g.userContext.RuntimeCurrentDirection',direction);
        [~,a]=sixgr.link.applyWaveformImpairments(complex(zeros(7,2)),changed,fs,'ApplyRFChain',false);
        [~,b]=sixgr.link.applyWaveformImpairments(complex(17*ones(7,2)),changed,fs,'ApplyRFChain',false);
        assert(sixgr.link.resolveAbsoluteReferenceNoiseVariance(a)==variance&& ...
            sixgr.link.resolveAbsoluteReferenceNoiseVariance(b)==variance);
    end
end
end

function legacy()
for mode=["receiver_noise_figure_thermal_noise","standalone_awgn_snr_argument"]
    [cfg,carrier,fs]=configuration(mode,30);
    sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
    for direction=["DL","UL"]
        [samples,r,nfft]=execute(cfg,carrier,fs,direction);
        raw=nrOFDMDemodulate(carrier,samples);
        if mode=="receiver_noise_figure_thermal_noise"
            expected=r.ThermalNoisePSD_mWPerHz*fs;
            assert(r.InjectedNoiseVariance==expected&&isnan(r.AppliedAWGNSNR_dB));
            nearStat(mean(abs(raw/(double(nfft)*sqrt(1000))).^2,'all'),expected/nfft/1000);
        else
            nearStat(mean(abs(raw).^2,'all'),r.ReferenceAWGNGridNoiseVariance);
            assert(abs(r.AppliedAWGNSNR_dB-cfg.channel.snr_dB)<1e-10&& ...
                r.WaveformAmplitudeUnit=="normalized_complex_baseband");
        end
        assert(~isfield(r,'AbsoluteReferenceNoise'));
        p=sixgr.link.absoluteReferenceNoisePublication(r);
        assert(~p.AbsoluteReferenceNoiseEvidenceAvailable&&isnan(p.ControlledReferenceNoiseApplied));
    end
end
end

function guards()
[cfg,~,fs]=configuration("absolute_reference_esn0",30);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',"UL");
[~,r]=sixgr.link.applyWaveformImpairments(complex(zeros(5,2)),cfg,fs,'ApplyRFChain',false);
assert(sixgr.link.resolveAbsoluteReferenceNoiseVariance(r)>0);
for field=["SampleRate_Hz","PowerContextDirection","PowerContextAmplitudeUnit","AbsoluteReferenceNoise"]
    bad=rmfield(r,field);
    reject(@()sixgr.link.resolveAbsoluteReferenceNoiseVariance(bad),'sixgr:link:AbsoluteReferenceNoiseReceipt');
end
bad=r; bad.AbsoluteReferenceNoise.Direction="DL";
reject(@()sixgr.link.resolveAbsoluteReferenceNoiseVariance(bad),'sixgr:link:AbsoluteReferenceNoiseReceipt');
bad=r; bad.AbsoluteReferenceNoise.NoisePSD_mWPerHz=2*bad.AbsoluteReferenceNoise.NoisePSD_mWPerHz;
reject(@()sixgr.link.resolveAbsoluteReferenceNoiseVariance(bad),'sixgr:link:AbsoluteReferenceNoiseReceipt');
% isequal(false,0) is true in MATLAB: require original logical scalar flags,
% not numeric substitutes or arrays, for every reference-authority field.
for field=["ReferenceIsMeasured","ThermalNoiseApplied","NoiseFigureApplied", ...
        "ReferencePathlossEvaluatedThisCall"]
    assert(islogical(r.AbsoluteReferenceNoise.(field))&& ...
        isscalar(r.AbsoluteReferenceNoise.(field))&&~r.AbsoluteReferenceNoise.(field));
    for invalid={0,false(1,2),false(0,1),true}
        bad=r; bad.AbsoluteReferenceNoise.(field)=invalid{1};
        reject(@()sixgr.link.resolveAbsoluteReferenceNoiseVariance(bad),'sixgr:link:AbsoluteReferenceNoiseReceipt');
    end
end
bad=cfg; bad.run.noiseOperatingMode='unknown';
reject(@()sixgr.link.applyWaveformImpairments(complex(zeros(5,2)),bad,fs,'ApplyRFChain',false), ...
    'sixgr:link:UnsupportedNoiseOperatingMode');
reject(@()sixgr.truth.resolveCoupledReplaySNR(bad,0),'sixgr:truth:UnsupportedSharedNoisePowerReference');
end

function [samples,receipt,nfft]=execute(cfg,carrier,fs,direction)
% Sixteen actual slots provide a fixed sufficient population, not an
% acceptance condition on receiver signal quality. Only noise is emitted.
grid=complex(zeros(12*carrier.NSizeGrid,14*16,2));
[zero,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
assert(ofdm.SampleRate==fs); nfft=ofdm.Nfft; n=size(zero,1);
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
owner.addTransmitter('silent',cfg,direction,2,false);
owner.addReceiver('receiver',cfg,direction,2,false);
event=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(event,'double'); event.commitTransmissionsThrough('silent',n);
event.observe('receiver:pre_rf','receiver:pre_rf',0,n);
event.observe('receiver:post_rf','receiver:post_rf',0,n);
before=rng; event.advanceUntilEvent(997); out=event.advanceUntilEvent(n);
assert(isequal(before,rng)&&owner.NextSampleIndex==n);
plane=out.Completed(string({out.Completed.ReceiverID})=="receiver:pre_rf");
samples=plane.Observation.readComplete();
receipt=plane.Segments{1}.Execution.RX.Replay;
last=plane.Segments{end}.Execution.RX.Replay;
assert(receipt.InjectedNoiseVariance==last.InjectedNoiseVariance&&receipt.NoiseStreamSeed==last.NoiseStreamSeed);
[expected,~]=sixgr.link.addRuntimeComplexNoise(zero,receipt.InjectedNoiseVariance,receipt.NoiseStreamSeed,0,struct());
assert(isequal(samples,expected),'Use exactly the original retained stream across partitions.');
nearStat(mean(abs(samples).^2,'all'),receipt.InjectedNoiseVariance);
T=table(cfg.channel.snr_dB,123.5,'VariableNames',{'ConfiguredSNR_dB','MeasuredSentinel'});
post=out.Completed(string({out.Completed.ReceiverID})=="receiver:post_rf");
published=sixgr.truth.bindSharedNoiseReferenceEvidence(T,post);
assert(published.MeasuredSentinel==T.MeasuredSentinel&&isequal(before,rng));
end

function [cfg,carrier,fs]=configuration(mode,scs)
cfg=sixgr.config.defaultConfig();
cfg.run.noiseOperatingMode=char(mode); cfg.run.seed=913;
cfg.channel.snr_dB=10; cfg.channel.bandwidth_Hz=10e6;
cfg.phy.fc_Hz=2350e6; cfg.channel.fc_Hz=2350e6;
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',scs, ...
    'CyclicPrefix','normal','NCellID',1,'NSlot',0,'NFrame',0);
cfg.integration=struct('run_mode','GEOMETRY_NETWORK','configured_snr_is_link_authority',false, ...
    'power_reference_mode','absolute_calibrated_sqrt_mw');
if mode=="standalone_awgn_snr_argument"
    cfg.integration.run_mode='FIXED_SNR_SWEEP';
    cfg.integration.configured_snr_is_link_authority=true;
    cfg.integration.power_reference_mode='normalized_unit_es';
end
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier); fs=double(ofdm.SampleRate);
if mode=="absolute_reference_esn0"
    bwp=struct('NSizeBWP',24,'NStartBWP',0,'SubcarrierSpacing_kHz',scs,'BWPID',0);
    cfg.phy.bwp=struct('dl',bwp,'ul',bwp);
    cfg.run.absoluteReferenceNoisePolicy=struct('reference_policy','nominal_full_bwp_unity_array', ...
        'reference_pathloss_scenario','UMa','reference_bs_position_m',[0 0 25], ...
        'reference_ue_position_m',[85 0 1.5],'reference_los',false, ...
        'nominal_dl_tx_power_dbm',30,'nominal_ul_tx_power_dbm',23, ...
        'classification','optional_research_experiment');
    [~,~,cfg.run.absoluteReferenceNoise]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,"DL",fs,'Freeze',true);
end
end
function nearStat(actual,expected)
assert(isfinite(actual)&&isfinite(expected)&&expected>0&&abs(actual/expected-1)<.03, ...
    'test:NoisePopulation','Observed %.17g expected %.17g (fixed-seed 3%% population tolerance).',actual,expected);
end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingNoiseRejection','Expected %s.',id);
end
