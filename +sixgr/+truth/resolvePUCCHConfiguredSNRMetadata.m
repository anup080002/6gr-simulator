function snr_dB = resolvePUCCHConfiguredSNRMetadata(state, cfg)
%RESOLVEPUCCHCONFIGUREDSNRMETADATA Resolve metadata without feedback leakage.
% The PUCCH SNR argument is configured operating-point metadata. It must
% never be replaced by prior receiver feedback: doing so would feed a
% receiver output back into the next waveform's noise injection. In
% thermal-noise mode the actual sample variance is resolved independently
% from absolute received power, bandwidth and receiver noise figure inside
% runPUCCHWaveformTrial.

snr_dB = double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN));
if ~isfinite(snr_dB)
    cfgEval = cfg;
    if ~(isstruct(cfgEval) && ~isempty(fieldnames(cfgEval)))
        cfgEval = sixgr.util.structGet(state, "CfgMobility", struct());
    end
    snr_dB = double(sixgr.util.structGet(cfgEval, "channel.snr_dB", NaN));
end
if ~isfinite(snr_dB)
    error("sixgr:truth:MissingPUCCHConfiguredOperatingPoint", ...
        ["PUCCH waveform execution requires a finite configured " + ...
         "operating-point label. Receiver SINR/CSI feedback cannot " + ...
         "be substituted as noise-injection authority."]);
end
end
