function variance=resolveReceiverThermalNoiseVariance(replay)
% Absolute complex-sample thermal noise, per physical receive branch.
% Samples are sqrt(mW); never normalize noise by the current faded signal,
% RSRP, beam gain, serving link budget, active RE count or requested SNR.
% Flat complex-baseband sample noise spans Fs. The configured-channel noise
% power may have been integrated over a different B; recover its PSD first:
%   variance [mW/sample] = N_B [mW] * Fs/B.
% A later OFDM/measurement bandwidth selects its portion of this noise.
required={'NoiseOperatingMode','PowerContextAmplitudeUnit', ...
    'ThermalNoisePower_dBm','NoiseBandwidth_Hz','SampleRate_Hz'};
if ~isstruct(replay)||~isscalar(replay)||~all(isfield(replay,required)) || ...
        ~isequal(string(replay.NoiseOperatingMode),"receiver_noise_figure_thermal_noise") || ...
        ~isequal(string(replay.PowerContextAmplitudeUnit),"sqrt_mW")
    error('sixgr:link:AbsoluteThermalNoiseAuthorityRequired', ...
        'Thermal sample noise requires explicit absolute sqrt(mW) units and receiver noise/B/Fs authority.');
end
validateattributes(replay.ThermalNoisePower_dBm,{'numeric'},{'real','scalar','finite'});
validateattributes(replay.NoiseBandwidth_Hz,{'numeric'},{'real','scalar','finite','positive'});
validateattributes(replay.SampleRate_Hz,{'numeric'},{'real','scalar','finite','positive'});
variance=10^(double(replay.ThermalNoisePower_dBm)/10)* ...
    (double(replay.SampleRate_Hz)/double(replay.NoiseBandwidth_Hz));
validateattributes(variance,{'numeric'},{'real','scalar','finite','positive'});
end
