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
    burstLength=sixgr.util.structGet(cfg,'phy.trs.burstLengthSlots',1);
    validateattributes(burstLength,{'numeric'},{'scalar','integer','positive','<=',double(period)});
    % The configured resource-set length, not an inferred extra pilot,
    % determines all resources belonging to this periodic observation.
    first = double(offset)+max(0,floor((absoluteSlot-double(offset))/double(period)))*double(period);
    resolved=first+(0:burstLength-1);
    window = struct('Authority',"periodic_offset",'FrameNumber',NaN,'SlotsPerFrame',NaN, ...
        'ConfiguredSlotNumbers',double(offset)+(0:burstLength-1),'AbsoluteSlotNumbers',resolved, ...
        'ResourceSetIndex0Based',0,'BurstLengthSlots',burstLength, ...
        'ResourceActive',any(absoluteSlot==resolved),'ObservationStarts',absoluteSlot==first);
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
burstLength=sixgr.util.structGet(cfg,'phy.trs.burstLengthSlots',numel(slots));
validateattributes(burstLength,{'numeric'},{'scalar','integer','positive'});
assert(mod(numel(slots),burstLength)==0,'sixgr:truth:InvalidTRSBurstPartition', ...
    'Every authored TRS resource set must have its complete configured burst_length_slots.');
bursts=reshape(resolved,burstLength,[]);
assert(all(diff(bursts,1,1)==1,'all'),'sixgr:truth:NonconsecutiveTRSBurst', ...
    'A multi-slot trs-Info resource set requires consecutive slots, not a disjoint pilot pair.');
activeBurst=find(any(bursts==absoluteSlot,1),1);
if isempty(activeBurst)
    activeBurst=find(bursts(1,:)>=absoluteSlot,1);
    if isempty(activeBurst), activeBurst=size(bursts,2); end
end
observationSlots=bursts(:,activeBurst).';
if any(resolved>flintmax)
    error('sixgr:truth:InvalidTRSSlot','TRS absolute resource slots exceed exact integer coordinates.');
end
window = struct('Authority',"explicit_slot_numbers",'FrameNumber',frame,'SlotsPerFrame',double(spf), ...
    'ConfiguredSlotNumbers',slots,'AbsoluteSlotNumbers',observationSlots, ...
    'ResourceSetIndex0Based',activeBurst-1,'BurstLengthSlots',burstLength, ...
    'ResourceActive',any(absoluteSlot==resolved),'ObservationStarts',any(absoluteSlot==bursts(1,:)));
end
