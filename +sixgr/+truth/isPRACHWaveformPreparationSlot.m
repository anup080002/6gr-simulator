function tf = isPRACHWaveformPreparationSlot(cfg, slotIdx)
%ISPRACHWAVEFORMPREPARATIONSLOT One planning slot BEFORE the PRACH buffer.
%
% A shared causal waveform stream must enqueue the complete PRACH buffer
% before its received-clock/common-UL-offset-adjusted transmit origin.  That
% physical origin can precede the nominal carrier-slot boundary slightly, so
% the deterministic scheduling horizon is the immediately preceding carrier
% slot.  This only prepares a future contribution; it does not move any IQ
% sample or change the reported PRACH occasion.  The predicate is distinct from
% isActivePRACHOccasion, which identifies the slot containing transmitted
% PRACH energy. Native PRACH/reference RA-RNTI coordinates are unchanged.
% This one-slot lead is bounded simulator planning policy, not an NR delay.
% Per-UE timing and the committed-transmission guard still apply at enqueue.

validateattributes(slotIdx,{'numeric'}, ...
    {'real','scalar','finite','integer','positive'});
timing=sixgr.util.structGet(cfg,'phy.prach.timing',struct());
occasions=sixgr.util.structGet(timing,'Occasions',table());
required=["PRACHSlot","AbsoluteSlot","PRACHWaveformStartTicks","PRACHActiveStartTicks"];
if ~istable(occasions) || isempty(occasions) || ...
        ~all(ismember(required,string(occasions.Properties.VariableNames)))
    error('sixgr:truth:MissingPRACHWaveformTimingAuthority', ...
        'Shared PRACH preparation requires the canonical resolved occasion table.');
end
period=double(sixgr.util.structGet(timing,'PeriodCarrierSlots',NaN));
scs=sixgr.util.structGet(timing,'CarrierSubcarrierSpacingKHz',NaN);
cp=sixgr.util.structGet(cfg,'phy.carrier.CyclicPrefix',"normal");
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',scs,'CyclicPrefix',cp));
% AbsoluteSlot locates actual CP/useful energy, NOT the beginning of the
% complete native waveform buffer. A long preamble can have initial zeros;
% planning from occupied AbsoluteSlot-1 can already be too late after TA.
prachSlots=double(occasions.PRACHSlot(:));
activeSlots=double(occasions.AbsoluteSlot(:));
origins=occasions.PRACHWaveformStartTicks;
active=occasions.PRACHActiveStartTicks;
if ~(isscalar(period) && isfinite(period) && period>=1 && period==fix(period) && ...
        mod(period,spec.SlotsPerFrame)==0 && period<=flintmax && ...
        all(isfinite(prachSlots)) && ...
        all(prachSlots>=0) && all(prachSlots==fix(prachSlots)) && ...
        all(isfinite(activeSlots)) && all(activeSlots>=0) && all(activeSlots==fix(activeSlots)) && ...
        isa(origins,'int64') && iscolumn(origins) && isa(active,'int64') && iscolumn(active) && ...
        all(origins>=0 & active>=origins) && all(double(active)<=flintmax))
    error('sixgr:truth:InvalidPRACHWaveformTimingAuthority', ...
        'Canonical PRACH occasions require exact original waveform/active Tc clocks and a complete carrier-frame period.');
end
frames=period/spec.SlotsPerFrame;
if frames>floor(flintmax/double(sixgr.phy.frame.AbsoluteTime.TicksPerFrame))
    error('sixgr:truth:InvalidPRACHWaveformTimingAuthority','PRACH period exceeds exact Tc arithmetic.');
end
periodTicks=int64(frames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
if any(origins>=periodTicks)
    error('sixgr:truth:InvalidPRACHWaveformTimingAuthority','Original waveform origins must belong to the retained native period.');
end
starts=zeros(height(occasions),1);
for k=1:height(occasions)
    t=sixgr.phy.frame.AbsoluteTime(origins(k));
    [~,frame,slot]=t.floorToSlot(spec);
    starts(k)=double(frame)*spec.SlotsPerFrame+double(slot);
    % Reject contradictory native metadata without substituting occupied
    % coordinates for the original waveform-container clock.
    a=sixgr.phy.frame.AbsoluteTime(active(k));
    [~,activeFrame,activeSlot]=a.floorToSlot(spec);
    if activeSlots(k)~=double(activeFrame)*spec.SlotsPerFrame+double(activeSlot)
        error('sixgr:truth:InvalidPRACHWaveformTimingAuthority', ...
            'Native active support and occupied carrier slot disagree.');
    end
end
% One full carrier-slot planning horizon covers the bounded received-clock
% phase/common N_TA offset without rewriting an already committed interval.
% An origin at slot zero is therefore prepared in the final slot of the
% preceding repetition; RAConfig then selects the following occurrence.
starts=unique(mod(starts-1,period),'stable');
slotInPeriod=mod(double(slotIdx)-1,period);
tf=ismember(slotInPeriod,starts);
end
