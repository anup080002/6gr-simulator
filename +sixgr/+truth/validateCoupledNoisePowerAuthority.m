function validateCoupledNoisePowerAuthority(cfg)
% The coupled producer applies PowerContext before the receiver adds noise.
% A fixed unit-RE noise reference is meaningful only if that same producer
% keeps normalized samples. Do not silently combine device-power scaling
% with a unit-Es noise variance, or normalize noise from faded RX samples.
mode=lower(strtrim(string(sixgr.util.structGet(cfg, ...
    'run.noiseOperatingMode','receiver_noise_figure_thermal_noise'))));
if strlength(mode)==0, mode="receiver_noise_figure_thermal_noise"; end
normalized=sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
switch mode
    case "standalone_awgn_snr_argument"
        assert(normalized,'sixgr:truth:MixedSharedNoisePowerReference', ...
            ['Shared configured-SNR execution requires integration.run_mode=FIXED_SNR_SWEEP, ' ...
             'configured_snr_is_link_authority=true and power_reference_mode=normalized_unit_es. ' ...
             'Absolute-power TX samples cannot use unit-RE AWGN noise. For a physical power ' ...
             'budget select receiver_noise_figure_thermal_noise without fixed-SNR authority.']);
    case "receiver_noise_figure_thermal_noise"
        assert(~normalized,'sixgr:truth:MixedSharedNoisePowerReference', ...
            'Physical thermal noise requires absolute-power samples, not normalized fixed-SNR transmit samples.');
    otherwise
        error('sixgr:truth:UnsupportedSharedNoisePowerReference', ...
            'Unsupported coupled noise operating mode: %s.',mode);
end
end
