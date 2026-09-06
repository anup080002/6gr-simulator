function window = resolveTRSObservationWindow(cfg, slotIdx)
%RESOLVETRSOBSERVATIONWINDOW Bind the authored TRS resources to an epoch.
% Explicit slotNumbers describe resources within one carrier frame. The
% multi-slot receiver observes that set once, starting at its first resource;
% resource activity (e.g. PDSCH RE reservation) still includes every member.
validateattributes(slotIdx, {'numeric'}, ...
    {'real','scalar','finite','integer','positive','<=',flintmax});
absoluteSlot = double(slotIdx)-1;
slots = sixgr.util.structGet(cfg,'phy.trs.slotNumbers', ...
    sixgr.util.structGet(cfg,'lls6g.reference_signals.trs.slot_numbers',[]));
if isempty(slots)
    period = sixgr.util.structGet(cfg,'phy.trs.period_slots',NaN);
    offset = sixgr.util.structGet(cfg,'phy.trs.period_offset',0);
    if ~isnumeric(period)||~isreal(period)||~isscalar(period)|| ...
            ~isfinite(period)||period<1||period~=fix(period)|| ...
            ~isnumeric(offset)||~isreal(offset)||~isscalar(offset)|| ...
            ~isfinite(offset)||offset<0||offset>=period||offset~=fix(offset)
        error('sixgr:truth:MissingTRSSlotAuthority', ...
            'TRS needs explicit within-frame slotNumbers or integer period_slots/period_offset.');
    end
    % A single periodic resource is not silently expanded into a multi-slot
    % frequency-tracking observation. Strict receiver validation still applies.
    first = double(offset)+max(0,floor((absoluteSlot-double(offset))/double(period)))*double(period);
    window = struct('Authority',"periodic_offset",'FrameNumber',NaN,'SlotsPerFrame',NaN, ...
        'ConfiguredSlotNumbers',double(offset),'AbsoluteSlotNumbers',first, ...
        'ResourceActive',absoluteSlot==first,'ObservationStarts',absoluteSlot==first);
    return;
end
spf = sixgr.util.structGet(cfg,'phy.numerology.slotsPerFrame', ...
    sixgr.util.structGet(cfg,'frame_timing.slots_per_frame',NaN));
if ~isnumeric(spf)||~isreal(spf)||~isscalar(spf)||~isfinite(spf)||spf<1||spf~=fix(spf)
    error('sixgr:truth:MissingTRSFrameTiming', ...
        'Explicit TRS resources require integer carrier slots per frame.');
end
if ~isnumeric(slots)||~isreal(slots)||~isvector(slots)|| ...
        any(~isfinite(slots))||any(slots<0|slots>=spf|slots~=fix(slots))|| ...
        numel(unique(slots))~=numel(slots)
    error('sixgr:truth:InvalidTRSResourceSlots', ...
        'TRS slotNumbers must be unique integer resources in [0, slotsPerFrame-1].');
end
slots = sort(double(slots(:).'));
frame = floor(absoluteSlot/double(spf));
resolved = frame*double(spf)+slots;
if any(resolved>flintmax)
    error('sixgr:truth:InvalidTRSSlot','TRS absolute resource slots exceed exact integer coordinates.');
end
window = struct('Authority',"explicit_slot_numbers",'FrameNumber',frame,'SlotsPerFrame',double(spf), ...
    'ConfiguredSlotNumbers',slots,'AbsoluteSlotNumbers',resolved, ...
    'ResourceActive',any(absoluteSlot==resolved),'ObservationStarts',absoluteSlot==resolved(1));
end
