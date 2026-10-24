function [snr_dB, configuredReplay] = resolveCoupledReplaySNR(cfg, configuredSNR_dB)
%RESOLVECOUPLEDREPLAYSNR Preserve the physical operating-point authority.
%   A configured AWGN replay applies its requested SNR to every waveform
%   producer, including coupled control channels. Geometry/receiver-noise
%   campaigns instead derive link quality from measured runtime state.

mode = string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
    sixgr.util.structGet(cfg, "run.noise_operating_mode", ...
    sixgr.util.structGet(cfg, "simulation.noise_operating_mode", ...
    "receiver_noise_figure_thermal_noise"))));
mode = lower(strtrim(mode));
if strlength(mode) == 0
    mode = "receiver_noise_figure_thermal_noise";
end

switch mode
    case "standalone_awgn_snr_argument"
        configuredReplay=true;
    case {"receiver_noise_figure_thermal_noise","absolute_reference_esn0"}
        % A nominal reference selects N0, never the measured link quality.
        configuredReplay=false;
    otherwise
        error('sixgr:truth:UnsupportedSharedNoisePowerReference', ...
            'Unsupported coupled replay noise mode %s.',mode);
end
snr_dB = NaN;
if configuredReplay
    requested = double(configuredSNR_dB);
    if ~(isscalar(requested) && isfinite(requested))
        error("sixgr:truth:InvalidConfiguredReplaySNR", ...
            "Configured replay mode '%s' requires one finite operating-point SNR.", ...
            mode);
    end
    snr_dB = requested;
end
end
