function mode = resolveTruthMode(cfg)
%RESOLVETRUTHMODE Resolve the explicit LLS truth-mode token.

mode = lower(string(sixgr.util.structGet(cfg, "run.truthMode", ...
    sixgr.util.structGet(cfg, "phy.truthMode", "full_waveform"))));
if strlength(mode) == 0
    mode = "full_waveform";
end

switch mode
    case {"full_waveform","ideal_channel_debug","abstract_fast"}
        % accepted
    otherwise
        error("sixgr:link:UnknownTruthMode", ...
            "Unsupported truth mode '%s'. Expected full_waveform, ideal_channel_debug, or abstract_fast.", ...
            mode);
end
end
