function tf = isActivePRACHOccasion(cfg, slotIdx)
%ISACTIVEPRACHOCCASION Test an absolute carrier slot against canonical PRACH timing.
%
% FrameStructureEngine/PRACHOccasionResolver already materializes every
% candidate through nrPRACHIndices and rejects resources that do not fit
% the resolved UL symbol map.  Runtime gating must therefore consume its
% absolute carrier-slot aliases directly.  NPRACHSlot is a PRACH-timeline
% index and must not be populated with an absolute carrier slot merely to
% repeat that validation.

tf = false;
prachRequired = logical(sixgr.util.structGet( ...
    cfg, "run.controlGating.prachRequired", false));
validateattributes(slotIdx,{'numeric'},{'real','scalar','finite','integer','positive'});

validSlots1 = double(sixgr.util.structGet( ...
    cfg, "phy.prach.validSlots1Based", []));
if ~isempty(validSlots1)
    % These aliases cover the joint PRACH-table/TDD repetition period,
    % which is not necessarily one 10 ms radio frame. Frame modulo can
    % erase every valid occasion (e.g. slot 15 in a 20-slot period).
    period=double(sixgr.util.structGet(cfg,'phy.prach.timing.PeriodCarrierSlots', ...
        sixgr.util.structGet(cfg,'phy.prach.period_slots',NaN)));
    if ~isscalar(period)||~isfinite(period)||period<1||period~=fix(period) || ...
            any(~isfinite(validSlots1))||any(validSlots1<1|validSlots1>period|validSlots1~=fix(validSlots1))
        error('sixgr:truth:InvalidPRACHOccasionAuthority', ...
            'Resolved PRACH carrier-slot aliases need their exact integer repetition period and in-period slot coordinates.');
    end
    aliasPeriod=sixgr.util.structGet(cfg,'phy.prach.period_slots',period);
    if ~isequal(double(aliasPeriod),period)
        error('sixgr:truth:PRACHPeriodAuthorityConflict','PRACH period alias contradicts canonical timing.');
    end
    canonicalSlotInPeriod=mod(double(slotIdx)-1,period)+1;
    tf=ismember(canonicalSlotInPeriod,validSlots1(:).');
    return;
end

try
    frameStructure = sixgr.phy.FrameStructureEngine(cfg);
    tf = logical(frameStructure.IsPRACHSlot(double(slotIdx)-1));
catch ME
    if prachRequired || logical(sixgr.util.structGet(cfg, "phy.prach.enable", false))
        rethrow(ME);
    end
    tf = false;
end
end
