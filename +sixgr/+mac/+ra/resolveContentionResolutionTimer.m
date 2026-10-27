function timer=resolveContentionResolutionTimer(node,scs,originalEnum)
% TS38.331 V18.8 RACH-ConfigCommon field description:
% sf8 is eight subframes (8ms), independent of PUSCH slot numerology.
% Slot-only legacy component configuration is explicit simulator timing;
% it may be encoded in SIB1 only when WireRepresentable is true.
id='sixgr:mac:ra:ContentionTimerAuthority';
assert(isstruct(node)&&isscalar(node),id,'One explicit timer configuration required.');
validateattributes(scs,{'numeric'},{'scalar','real','finite','positive'});
mu=log2(double(scs)/15);
assert(mu==fix(mu)&&mu>=0&&mu<=6,id,'Require an exact supported NR slot numerology.');
perSubframe=2^mu;hasSF=isfield(node,'ra_contention_resolution_timer_subframes');
hasSlots=isfield(node,'ra_contention_resolution_timer_slots');
if hasSF,validateattributes(node.ra_contention_resolution_timer_subframes,{'numeric'}, ...
        {'scalar','real','finite','integer','positive'});end
if hasSlots,validateattributes(node.ra_contention_resolution_timer_slots,{'numeric'}, ...
        {'scalar','real','finite','integer','positive'});end
enum="";source="";
if nargin>=3
    enum=string(originalEnum);
    assert(isscalar(enum)&&any(enum=="sf"+string(8:8:64)),id,'Original mandatory received timer enum required.');
    subframes=str2double(erase(enum,"sf"));source="original_received_RACH_ContentionResolutionTimer";
elseif hasSF
    subframes=double(node.ra_contention_resolution_timer_subframes);
    assert(ismember(subframes,8:8:64),id,'Configured subframes must be representable by the original NR timer enum.');
    enum="sf"+subframes;source="explicit_configured_contention_timer_subframes";
elseif hasSlots
    subframes=double(node.ra_contention_resolution_timer_slots)/perSubframe;
    if ismember(subframes,8:8:64),enum="sf"+subframes;end
    source="legacy_explicit_slot_timer_not_received_SIB1";
else
    error(id,'Require explicit subframe duration or a named legacy slot duration.');
end
slots=subframes*perSubframe;
assert(slots==fix(slots)&&slots>0&&slots<=flintmax,id,'Do not round a received timer to different slot timing.');
if hasSF,assert(double(node.ra_contention_resolution_timer_subframes)==subframes,id,'Subframe aliases disagree.');end
if hasSlots,assert(double(node.ra_contention_resolution_timer_slots)==slots,id,'Legacy slot alias disagrees with original subframe duration/numerology.');end
ticksPerSlot=idivide(sixgr.phy.frame.AbsoluteTime.TicksPerFrame,int64(10*perSubframe));
assert(slots<=floor(double(intmax('int64'))/double(ticksPerSlot)),id,'Timer exceeds the exact absolute clock range.');
duration=int64(slots)*ticksPerSlot;
timer=struct('ContractVersion',"NR_contention_timer_units/v1",'OriginalEnum',enum, ...
    'Subframes',subframes,'DurationSeconds',subframes/1000,'DurationTicks',duration, ...
    'Slots',slots,'SCSkHz',double(scs),'Mu',mu,'SlotsPerSubframe',perSubframe, ...
    'Source',source,'WireRepresentable',strlength(enum)>0, ...
    'Reference',"TS38.331_V18.8.0_RACH_ConfigCommon_ra_ContentionResolutionTimer");
end
