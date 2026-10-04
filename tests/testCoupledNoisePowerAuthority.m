function ok=testCoupledNoisePowerAuthority()
% Configuration and actual OFDM scaling checks; not an access acceptance run.
cfg=sixgr.config.defaultConfig();
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.integration=struct();
reject(@()sixgr.truth.validateCoupledNoisePowerAuthority(cfg), ...
    'sixgr:truth:MixedSharedNoisePowerReference');
% A fully installed DCI context keeps this a power-contract test, not a
% missing-control-schema test. Reject before any RF/channel construction.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_fdd_staged_data_connected_dci.yaml');
invalid=sixgr.lls6g.buildInternalConfig(scenario,tempname);
invalid.integration=struct();
invalid.run.noiseOperatingMode='standalone_awgn_snr_argument';
reject(@()sixgr.truth.CoupledWaveformStream.initialize( ...
    struct('CurrentSlot',1),invalid,{invalid}), ...
    'sixgr:truth:MixedSharedNoisePowerReference');
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
wrong=cfg; wrong.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
reject(@()sixgr.truth.validateCoupledNoisePowerAuthority(wrong), ...
    'sixgr:truth:MixedSharedNoisePowerReference');
wrong=cfg; wrong.integration.configured_snr_is_link_authority=false;
reject(@()sixgr.truth.validateCoupledNoisePowerAuthority(wrong), ...
    'sixgr:truth:MixedSharedNoisePowerReference');
wrong=cfg; wrong.integration.power_reference_mode='absolute_calibrated_sqrt_mw';
reject(@()sixgr.truth.validateCoupledNoisePowerAuthority(wrong), ...
    'sixgr:rf:MixedFixedSNRAndAbsolutePower');
physical=cfg; physical.integration.run_mode='GEOMETRY_NETWORK';
physical.integration.configured_snr_is_link_authority=false;
physical.integration.power_reference_mode='absolute_calibrated_sqrt_mw';
physical.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
sixgr.truth.validateCoupledNoisePowerAuthority(physical);
cfg.rf.pa.enable=false; cfg.phy.impairments.paNonlinearityEnabled=false;
for profile=[25 15;264 120].'
    carrier=nrCarrierConfig('NSizeGrid',profile(1),'SubcarrierSpacing',profile(2));
    grid=complex(ones(12*carrier.NSizeGrid,14,2)/sqrt(2));
    [wave,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
    txInfo=struct('OFDM',ofdm);
    for direction=["DL","UL"]
        for dbm=[0 26 46]
            cfg.powerAndRF.bsTxPower_dBm=dbm;
            cfg.powerAndRF.ueTxPower_dBm=dbm;
            [scaled,power]=sixgr.rf.applyPowerContext(wave,cfg,direction,txInfo);
            assert(isequal(scaled,wave) && power.AmplitudeScale==1 && ...
                power.FixedSNRNormalizedReference && ~power.PhysicalDevicePowerClaim, ...
                'Changing a device power budget must not alter normalized fixed-Es samples.');
        end
    end
end
ok=true;
disp('COUPLED_NOISE_POWER_AUTHORITY_PASS mixed_planes_rejected=1 actual_OFDM_bands=5MHz,400MHz DL_UL_power_invariant=1');
end
function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'%s: %s',cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
