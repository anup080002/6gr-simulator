function [state,completed]=advanceSharedSlotWithULGrants(state,cfg,futureGrants,dueGrants,onReceived)
% Keep received UE grants alive across the physical source-slot callbacks.
% The scheduling queue consumes a due grant before advanceSlot. That is not
% permission to discard the receiver's grant/encoded-UCI ownership. Retire
% the due calendar entries only after every decision in this slot has run.
% Pending observations and immutable encoded waveforms remain owner-held.
slot=double(state.CurrentSlot);
assert(isstruct(futureGrants) && isstruct(dueGrants), ...
    'sixgr:truth:InvalidSharedULCalendar','UL calendars must contain grants.');
futureSlots=arrayfun(@sixgr.truth.runtimeULGrantSlot,futureGrants(:));
dueSlots=arrayfun(@sixgr.truth.runtimeULGrantSlot,dueGrants(:));
assert(all(futureSlots>slot) && all(dueSlots==slot), ...
    'sixgr:truth:InvalidSharedULCalendarPartition', ...
    'Future and source-slot received grants must be disjoint calendar partitions.');
state.SharedPendingULGrants=localAppend(futureGrants,dueGrants);
[state,completed]=state.SharedWaveformStream.advanceSlot(state,cfg,onReceived);
% Read callback-updated state, never restore the pre-advance snapshot: a
% decoded UL DCI in this slot may have admitted another future grant.
pending=state.SharedPendingULGrants;
slots=arrayfun(@sixgr.truth.runtimeULGrantSlot,pending(:));
assert(all(slots>=slot),'sixgr:truth:StaleSharedULCalendar', ...
    'A physical callback must not introduce a past UL grant.');
state.SharedPendingULGrants=pending(slots>slot);
end

function combined=localAppend(lhs,rhs)
if isempty(lhs), combined=rhs(:); return; end
if isempty(rhs), combined=lhs(:); return; end
names=union(fieldnames(lhs),fieldnames(rhs),'stable');
for k=1:numel(names)
    name=names{k};
    if ~isfield(lhs,name), [lhs.(name)]=deal([]); end
    if ~isfield(rhs,name), [rhs.(name)]=deal([]); end
end
combined=[orderfields(lhs(:),names);orderfields(rhs(:),names)];
end
