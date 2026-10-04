function tf = isPRACHWaveformPreparationSlot(cfg, slotIdx)
%ISPRACHWAVEFORMPREPARATIONSLOT True at the canonical PRACH buffer origin.
%
% A shared causal waveform stream must enqueue the complete PRACH buffer
% before its received-clock/common-UL-offset-adjusted transmit origin.  That
% physical origin can precede the nominal carrier-slot boundary slightly, so
% the deterministic scheduling horizon is the immediately preceding carrier
% slot.  This only prepares a future contribution; it does not move any IQ
% sample or change the reported PRACH occasion.  The predicate is distinct from
% isActivePRACHOccasion, which identifies the slot containing transmitted
% PRACH energy and remains the reporting/RA-RNTI authority.

validateattributes(slotIdx,{'numeric'}, ...
    {'real','scalar','finite','integer','positive'});
timing=sixgr.util.structGet(cfg,'phy.prach.timing',struct());
occasions=sixgr.util.structGet(timing,'Occasions',table());
required=["PRACHSlot","AbsoluteSlot"];
if ~istable(occasions) || isempty(occasions) || ...
        ~all(ismember(required,string(occasions.Properties.VariableNames)))
    error('sixgr:truth:MissingPRACHWaveformTimingAuthority', ...
        'Shared PRACH preparation requires the canonical resolved occasion table.');
end
period=double(sixgr.util.structGet(timing,'PeriodCarrierSlots',NaN));
subframesPerPRACHSlot=double(sixgr.util.structGet( ...
    timing,'SubframesPerPRACHSlot',NaN));
% The resolver has already mapped each PRACH-clock occasion, including
% fractional short-preamble origins, onto the carrier sample/slot clock.
% Recomputing PRACHSlot*duration can yield a fractional carrier-slot value
% even though the received waveform has an exact containing AbsoluteSlot.
prachSlots=double(occasions.PRACHSlot(:));
starts=double(occasions.AbsoluteSlot(:));
if ~(isscalar(period) && isfinite(period) && period>=1 && period==fix(period) && ...
        isscalar(subframesPerPRACHSlot) && isfinite(subframesPerPRACHSlot) && ...
        subframesPerPRACHSlot>0 && all(isfinite(prachSlots)) && ...
        all(prachSlots>=0) && all(prachSlots==fix(prachSlots)) && ...
        all(isfinite(starts)) && all(starts>=0) && ...
        all(starts<period) && all(starts==fix(starts)))
    error('sixgr:truth:InvalidPRACHWaveformTimingAuthority', ...
        'Canonical PRACH occasions must have valid resolved carrier slots.');
end
% One full carrier-slot planning horizon covers the bounded received-clock
% phase/common N_TA offset without rewriting an already committed interval.
% An origin at slot zero is therefore prepared in the final slot of the
% preceding repetition; RAConfig then selects the following occurrence.
starts=unique(mod(starts-1,period),'stable');
slotInPeriod=mod(double(slotIdx)-1,period);
tf=ismember(slotInPeriod,starts);
end
