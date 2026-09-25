function level = resolveScheduledAggregationLevel(cfg, grant)
%RESOLVESCHEDULEDAGGREGATIONLEVEL Preserve the MAC's actual CCE admission cost.
% Configured sweep SNR is noise metadata, not permission to change a grant's
% control allocation after admission. Never round/clamp an invalid grant.
level = sixgr.util.structGet(grant,"PDCCHAggregationLevel",NaN);
if ~(isnumeric(level) && isreal(level) && isscalar(level) && ...
        isfinite(level) && ismember(level,[1 2 4 8 16]))
    error('sixgr:phy:pdcch:InvalidScheduledAggregationLevel', ...
        'A scheduled PDCCH needs an explicit legal PDCCHAggregationLevel.');
end
levels = sixgr.phy.pdcch.resolveExecutableAggregationLevels(cfg, ...
    sixgr.util.structGet(cfg,"phy.pdcch.aggregationLevels", ...
    sixgr.util.structGet(cfg,"phy.pdcch.aggregationLevel",[])));
if ~ismember(level,levels)
    error('sixgr:phy:pdcch:UnmonitoredScheduledAggregationLevel', ...
        'Scheduled AL%d has no executable installed search-space candidate.',level);
end
level = double(level);
end
