function description = describeNoiseOperatingPoint(executedMode)
%DESCRIBENOISEOPERATINGPOINT Display the executed noise model, never SINR.
mode = lower(strtrim(string(executedMode)));
if ~isscalar(mode) || ismissing(mode) || strlength(mode)==0
    error('sixgr:truth:UnknownOperatingModeAuthority','An executed noise mode is required.');
end
switch mode
    case "standalone_awgn_snr_argument"
        description = "controlled occupied-RE reference-SNR point";
    case "receiver_noise_figure_thermal_noise"
        description = "thermal receiver-noise operating-point label";
    case "absolute_reference_esn0"
        description = "absolute nominal-reference Es/N0 noise point (not measured receiver SINR)";
    otherwise
        error('sixgr:truth:UnknownOperatingModeAuthority', ...
            'Unrecognized executed noise mode: %s.',mode);
end
end
