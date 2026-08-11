function value = executedMCSTable(cfg)
%EXECUTEDMCSTABLE Resolve the MCS-table authority for an executed LLS trial.
%
% Fixed-MCS studies are owned by the selected physical-channel block.
% Link-adaptation studies are owned by linkAdaptation.mcsTable because that
% table selects every per-trial modulation/code-rate operating point.

link = lower(string(cfg.simulation.link));
if logical(sixgr.util.structGet(cfg,"linkAdaptation.enabled",false))
    value = string(cfg.linkAdaptation.mcsTable);
else
    value = string(sixgr.util.structGet(cfg,link + ".mcsTable",""));
end

if ~isscalar(value) || strlength(strtrim(value)) == 0
    error("sixgr:lls:MissingExecutedMCSTable", ...
        "The executed MCS-table authority is unavailable for link '%s'. " + ...
        "Configure %s.mcsTable for fixed-MCS studies or " + ...
        "linkAdaptation.mcsTable for adaptive studies.", ...
        upper(link),link);
end
end
