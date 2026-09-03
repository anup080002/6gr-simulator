function ok = testPUCCHConfiguredSNRMetadataAuthority()
%TESTPUCCHCONFIGUREDSNRMETADATAAUTHORITY Keep receiver feedback out of noise injection.

state = struct();
state.CurrentSNR_dB = 17;
state.LatestULFeedback = struct("Valid", true, "SINR_dB", -8.5);
state.PendingCSITable = table(1, "UL", 3.25, ...
    "VariableNames", {"UEIndex", "Direction", "SINR_dB"});
cfg = struct("run", struct("noiseOperatingMode", ...
    "receiver_noise_figure_thermal_noise"), ...
    "channel", struct("snr_dB", 12));

value = sixgr.truth.resolvePUCCHConfiguredSNRMetadata(state, cfg);
assert(value == 17, ...
    ["PUCCH configured-SNR metadata must retain the current configured " + ...
     "operating point and must not consume receiver SINR feedback."]);

state.CurrentSNR_dB = NaN;
value = sixgr.truth.resolvePUCCHConfiguredSNRMetadata(state, cfg);
assert(value == 12, ...
    "The resolved YAML channel operating point must be the only fallback metadata authority.");

cfg.channel.snr_dB = NaN;
threw = false;
try
    sixgr.truth.resolvePUCCHConfiguredSNRMetadata(state, cfg);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:truth:MissingPUCCHConfiguredOperatingPoint");
end
assert(threw, ...
    "Missing configured PUCCH operating-point metadata must fail closed with a typed error.");

ok = true;
end
