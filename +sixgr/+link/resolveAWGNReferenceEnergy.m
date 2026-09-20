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
end
