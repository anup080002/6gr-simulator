function validatePRACHPeriodAliases(cfg,timing)
%VALIDATEPRACHPERIODALIASES Preserve native PRACH occasion authority.
% The optional period declarations describe the resolved joint PRACH/TDD
% repetition in carrier slots. They cannot replace the TS 38.211 V18.8.0
% 6.3.3.2 table-derived occasions with an independent user timer.
% Check every declaration, including aliases shadowed by builder precedence.
slots=localPositive(timing.PeriodCarrierSlots,'resolved PeriodCarrierSlots');
scs=localPositive(timing.CarrierSubcarrierSpacingKHz,'resolved carrier SCS');
assert(slots==fix(slots) && log2(scs/15)==fix(log2(scs/15)) && scs>=15, ...
    'sixgr:phy:frame:InvalidPRACHPeriodAuthority','Invalid resolved carrier clock.');
slotPaths=["phy.prach.period_slots","random_access.prach_periodicity_slots", ...
    "random_access.periodicity_slots"];
msPaths=["random_access.prach_periodicity_ms","random_access.periodicity_ms"];
for path=[slotPaths msPaths]
    raw=sixgr.util.structGet(cfg,path,[]);
    if isempty(raw),continue;end
    value=localPositive(raw,path);
    if any(path==msPaths),value=value*(scs/15);end
    assert(isfinite(value) && value<=flintmax && value==fix(value), ...
        'sixgr:phy:frame:InvalidPRACHPeriodAlias', ...
        '%s must resolve exactly to positive integer carrier slots.',path);
    assert(value==slots,'sixgr:phy:frame:PRACHPeriodAliasConflict', ...
        ['%s declares %g carrier slots, but configuration-index-derived PRACH ' ...
         'and the resolved duplex calendar repeat in %g slots. Change the legal ' ...
         'PRACH/duplex configuration or remove the contradictory assertion.'],path,value,slots);
end
end

function value=localPositive(raw,path)
assert(isnumeric(raw) && ~islogical(raw) && isreal(raw) && isscalar(raw) && ...
    isfinite(raw) && raw>0,'sixgr:phy:frame:InvalidPRACHPeriodAlias', ...
    '%s must be a finite positive numeric scalar.',path);
if isinteger(raw)
    assert(raw<=cast(flintmax,'like',raw),'sixgr:phy:frame:InvalidPRACHPeriodAlias', ...
        '%s exceeds the exact integer coordinate range.',path);
end
value=double(raw);
assert(value<=flintmax,'sixgr:phy:frame:InvalidPRACHPeriodAlias', ...
    '%s exceeds the exact numeric coordinate range.',path);
end
