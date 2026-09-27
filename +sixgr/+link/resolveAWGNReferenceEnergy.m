function [energy,policy]=resolveAWGNReferenceEnergy(cfg)
% Fixed configured Es reference, not actual RX power or instantaneous rank.
% A legacy direct-core caller inherits the catalog's unit-RE convention.
energy=sixgr.util.structGet(cfg,'channel.awgnReferenceREEnergy',[]);
source="resolved_config_channel_awgnReferenceREEnergy";
if isempty(energy) && ~isfield(sixgr.util.structGet(cfg,'channel',struct()), ...
        'awgnReferenceREEnergy')
    catalog=sixgr.config.loadCoreCatalog();
    energy=catalog.parameters.channel.awgnReferenceREEnergy.default;
    source="core_catalog_default_channel_awgnReferenceREEnergy";
end
assert(isnumeric(energy) && isreal(energy) && isscalar(energy) && ...
    isfinite(energy) && energy>0, ...
    'sixgr:link:InvalidAWGNReferenceEnergy', ...
    'channel.awgnReferenceREEnergy must be a finite positive scalar fixed for the run.');
energy=double(energy);
policy=struct('EnergySource',source, ...
    'CalibrationSource',"fixed_once_from_configured_occupied_re_energy_and_canonical_ofdm_noise_transform", ...
    'NoiseVarianceSource',"fixed_configured_occupied_re_esn0_canonical_ofdm_transform");
if energy==1
    % Preserve the original unit-reference provenance and physical samples.
    policy.CalibrationSource="fixed_once_from_unit_occupied_re_energy_and_canonical_ofdm_noise_transform";
    policy.NoiseVarianceSource="fixed_unit_occupied_re_esn0_canonical_ofdm_transform";
end
if sixgr.rf.isFixedSNRLinkAuthority(cfg) && ...
        ~sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)
    ctx=sixgr.util.structGet(cfg,'lls6g.runtimePowerContext',struct());
    if ~(isstruct(ctx) && isfield(ctx,'AmplitudeScale'))
        direction=upper(strtrim(string(sixgr.util.structGet(cfg, ...
            'lls6g.userContext.RuntimeCurrentDirection',''))));
        if any(direction==["DL","UL"])
            ctx=sixgr.rf.PowerContext(cfg,direction);
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            ofdm=nrOFDMInfo(carrier);
            nsc=12*double(carrier.NSizeGrid);
            energy=double(ctx.TotalTxPower_mW)*double(ofdm.Nfft)^2/nsc;
            policy.EnergySource="configured_"+lower(direction)+ ...
                "_total_power_full_bwp_reference_epre_grid_energy";
            policy.CalibrationSource="absolute_sqrt_mw_full_bwp_reference_epre_and_canonical_ofdm_transform";
            policy.NoiseVarianceSource="fixed_snr_physical_full_bwp_reference_epre";
            return;
        end
        policy.EnergySource=source+"_configuration_validation_without_direction";
        policy.CalibrationSource="absolute_fixed_snr_deferred_until_direction_binding";
        policy.NoiseVarianceSource="not_resolved_until_runtime_direction_binding";
        return;
    end
    assert(...
        isscalar(ctx.AmplitudeScale) && isfinite(double(ctx.AmplitudeScale)) && ...
        double(ctx.AmplitudeScale)>0 && ...
        string(sixgr.util.structGet(ctx,'WaveformAmplitudeUnit',''))=="sqrt_mW" && ...
        logical(sixgr.util.structGet(ctx,'PhysicalDevicePowerClaim',false)), ...
        'sixgr:link:MissingAbsoluteFixedSNRPowerContext', ...
        ['Absolute calibrated fixed-SNR noise requires the exact applied ' ...
         'sqrt(mW) transmitter PowerContext.']);
    energy=energy*double(ctx.AmplitudeScale)^2;
    policy.EnergySource=source+"_times_applied_power_context_amplitude_scale_squared";
    policy.CalibrationSource="fixed_configured_occupied_re_es_scaled_by_applied_sqrt_mw_power_context";
    policy.NoiseVarianceSource="fixed_snr_physical_grid_es_from_applied_power_context";
end
end
