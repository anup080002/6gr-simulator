function ok=testAbsoluteEndpointRFReference()
% Actual OFDM amplitudes, fixed converter/PA ranges and signed PH.
setup6GRSimToolkit('Verbose',false);
cfg=struct('integration',struct('run_mode','GEOMETRY_NETWORK', ...
    'configured_snr_is_link_authority',false,'power_reference_mode','absolute_calibrated_sqrt_mw'));
cfg.scenario.bs.nTxAnt=64; cfg.scenario.ue.nTxAnt=4;
cfg.powerAndRF.bsTxPower_dBm=30; cfg.powerAndRF.ueTxPower_dBm=23;
cfg.phy.carrier=struct('NSizeGrid',51,'SubcarrierSpacing',30);
raw=struct('reference_domain','absolute_endpoint_rms', ...
    'reference_total_power_dl_dbm',30,'reference_total_power_ul_dbm',23, ...
    'reference_headroom_db',12);
carrier=nrCarrierConfig('NSizeGrid',51,'SubcarrierSpacing',30);
stream=RandStream('mt19937ar','Seed',8421);
for direction=["DL","UL"]
    ports=64; power=30;
    if direction=="UL", ports=4; power=23; end
    ref=sixgr.rf.resolveDACAmplitudeReference(cfg,raw,30.72e6,direction);
    rms=sqrt(10^(power/10)/ports);
    assert(abs(ref.ReferenceRMS-rms)<1e-12 && ref.NumTransmitPorts==ports);
    assert(abs(ref.WaveformUnitsPerReferenceUnit-rms*10^.6)<1e-12);
    changed=cfg; changed.powerAndRF.ueTxPower_dBm=-30;
    changed.lls6g.runtimeScheduledPowerContext.GrantTargetTxPower_dBm=-20;
    assert(isequaln(ref,sixgr.rf.resolveDACAmplitudeReference(changed,raw,30.72e6,direction)), ...
        'The physical DAC range must not track per-grant power.');
    grid=(2*randi(stream,[0 1],612,14,ports)-1+ ...
        1j*(2*randi(stream,[0 1],612,14,ports)-1))/sqrt(2*ports);
    [wave,info]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
    [wave,context]=sixgr.rf.applyPowerContext(wave,cfg,direction, ...
        struct('OFDM',info,'PortGrid',grid),'ApplyPA',false);
    assert(context.WaveformAmplitudeUnit=="sqrt_mW" && ...
        abs(context.OutputTotalPower_dBm-power)<1e-9);
    pa=raw; pa.profile_id='absolute_reference_test'; pa.version='1';
    pa.model='rapp'; pa.input_backoff_db=0; pa.reference_headroom_db=8;
    pa.saturation_amplitude=1; pa.smoothness=2;
    cfg.rf.specification.profile_id='rf_impaired_research'; cfg.rf.frontend.pa=pa;
    [profile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,direction);
    assert(canonical && abs(profile.SaturationAmplitude-rms*10^.4)<1e-12);
    [received,evidence]=sixgr.rf.runtime.PAProfile.apply(wave,profile);
    expected=wave./(1+(abs(wave)/(rms*10^.4)).^4).^.25;
    assert(norm(received-expected,'fro')<1e-12*norm(expected,'fro'));
    assert(~evidence.PowerRestorationApplied && evidence.PowerChange_dB<0);
    cfg.rf.pa.enable=true;
    [standalone,standaloneContext]=sixgr.rf.applyPowerContext( ...
        wave,cfg,direction,struct('OFDM',info,'PortGrid',grid),'ApplyPA',true);
    assert(norm(standalone-received,'fro')<1e-10*norm(received,'fro') && ...
        standaloneContext.PAApplied && ~standaloneContext.PAPowerRestorationApplied, ...
        'Standalone power-context PA must match the physical sample-domain PA.');
    assert(max(abs(real(wave(:))))<ref.WaveformUnitsPerReferenceUnit && ...
        max(abs(imag(wave(:))))<ref.WaveformUnitsPerReferenceUnit);
end
bad=cfg; bad.integration.run_mode='FIXED_SNR_SWEEP';
bad.integration.configured_snr_is_link_authority=true;
bad.integration.power_reference_mode='normalized_unit_es';
localReject(@()sixgr.rf.resolveDACAmplitudeReference(bad,raw,30.72e6,'DL'), ...
    'RF:AbsoluteEndpointReferenceDomain');
state=sixgr.rf.runtime.UplinkPowerControlState(1);
request=struct('Channel','PUSCH','Mu',1,'MRB',51,'MeasuredPathloss_dB',110, ...
    'PathlossSource','measured_reference_rs','P0_dBm',-80,'Alpha',.8, ...
    'DeltaTF_dB',0,'PCMAX_dBm',23);
result=state.resolve(request);
expected=-80+10*log10(2*51)+.8*110;
assert(result.RequestedPower_dBm==expected && result.AppliedPower_dBm==23 && ...
    result.PowerHeadroom_dB==23-expected && result.PowerHeadroom_dB<0 && ...
    result.RemainingAppliedPowerMargin_dB==0);
request.MeasuredPathloss_dB=80;
result=state.resolve(request); assert(result.PowerHeadroom_dB>0 && ~result.Clipped);
ok=true; disp('ABSOLUTE_ENDPOINT_RF_REFERENCE_PASS: OFDM 64/4 ports, fixed range, Rapp, negative PH');
end
function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:MissingExpectedError','Expected %s.',id);
end
