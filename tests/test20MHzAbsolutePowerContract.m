function ok=test20MHzAbsolutePowerContract()
% Resolved scenario + executed small power/noise/loss operators, not a run.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~sixgr.rf.isFixedSNRLinkAuthority(cfg) && cfg.channel.pathlossEnabled);
assert(string(cfg.run.noiseOperatingMode)=="receiver_noise_figure_thermal_noise");
sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
assert(cfg.phy.pusch.powerControl.enabled && cfg.phy.pusch.powerControl.requireMeasuredReferenceRS);
assert(cfg.phy.pusch.powerControl.openLoopEnabled && cfg.phy.pusch.powerControl.closedLoopEnabled);
assert(cfg.phy.pusch.powerControl.pcmax_dBm==23 && cfg.phy.pusch.powerControl.alpha==.8);
for direction=["DL","UL"]
    context=sixgr.rf.PowerContext(cfg,direction);
    power=30; ports=64; nf=7;
    if direction=="UL", power=23; ports=4; nf=5; end
    assert(context.WaveformAmplitudeUnit=="sqrt_mW" && context.TotalTxPower_dBm==power && ...
        context.NoiseFigure_dB==nf);
    chain=sixgr.rf.applyRFImpairmentChain([],cfg,'Direction',direction, ...
        'Endpoint','tx','SampleRateHz',30.72e6,'ResolveOnly',true);
    assert(chain.Config.TxDAC.Enabled && chain.Config.TxPA.Enabled);
    assert(chain.Config.TxDAC.Reference.NumTransmitPorts==ports && ...
        abs(chain.Config.TxDAC.FullScale-sqrt(10^(power/10)/ports)*10^.6)<1e-10);
    [pa,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,direction);
    assert(canonical && pa.InputBackoff_dB==0 && ...
        abs(pa.SaturationAmplitude-sqrt(10^(power/10)/ports)*10^.4)<1e-10);
    % Execute the retained RF path, not just the profile's scalar resolver.
    epoch=cfg.rf.configurationEpoch;
    one=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,30.72e6,ports,0,epoch,false);
    split=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,30.72e6,ports,0,epoch,false);
    probe=sqrt(10^(power/10)/ports)*exp(1j*(0:1023)'*.127)*ones(1,ports);
    whole=one.apply(sixgr.phy.waveform.WaveformChunk(probe,0),epoch);
    first=split.apply(sixgr.phy.waveform.WaveformChunk(probe(1:317,:),0),epoch);
    second=split.apply(sixgr.phy.waveform.WaveformChunk(probe(318:end,:),317),epoch);
    assert(norm(whole.Waveform-[first.Waveform;second.Waveform],'fro')<1e-10*norm(whole.Waveform,'fro'));
    assert(whole.Replay.PAApplied && whole.Replay.DACQuantizationApplied && ...
        whole.Replay.DACReferenceDomain=="absolute_endpoint_rms");
    local=cfg; local.lls6g.userContext.RuntimeCurrentDirection=direction;
    [~,noise]=sixgr.link.applyWaveformImpairments(complex(zeros(8,ports)), ...
        local,30.72e6,'ApplyRFChain',false);
    expected=10^((-174+nf)/10)*30.72e6;
    assert(abs(noise.ThermalSampleNoiseVariance_mW-expected)<1e-10*expected);
end
% Large-scale UMa NLOS model must be applied, not just exported as metadata.
model=sixgr.channel.TR38901Plus(cfg,'Scenario','UMa','Seed',121);
bs=[0;0;25]; ue=[85;0;1.5];
[loss,los,meta]=model.pathloss(bs,ue,'LOS',false,'IndoorRx',false);
native=nrPathLoss(nrPathLossConfig('Scenario','UMa'),2.35e9,false,bs,ue);
assert(abs(loss-native)<1e-10 && ~los && meta.pathlossEnabled && ~meta.fallbackUsedForPathloss);
fprintf('ABSOLUTE_POWER_CONTRACT_PASS: DL=30dBm ULmax=23dBm NF_DL=7dB NF_UL=5dB UMa_85m_loss=%.6fdB\n',loss);
ok=true;
end
