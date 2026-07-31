function cfgPoint = bindStandaloneSNRPoint(cfg, snr_dB)
%BINDSTANDALONESNRPOINT Bind one configured SNR point to a waveform trial.
%
% Standalone control-signal diagnostics receive their sweep value outside
% the normalized scenario structure.  Bind that value to the same
% channel.snr_dB field consumed by the waveform generators so the applied
% waveform condition cannot diverge from the exported configured label.

arguments
    cfg (1,1) struct
    snr_dB (1,1) double {mustBeReal,mustBeFinite}
end

cfgPoint = cfg;
if ~isfield(cfgPoint, "channel") || ~isstruct(cfgPoint.channel)
    cfgPoint.channel = struct();
end
cfgPoint.channel.snr_dB = double(snr_dB);
end
