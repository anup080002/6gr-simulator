function slots=resolveRAEventAbsoluteSlots(events,slotDuration_s)
% RAEventLog.Frame is absolute; RAEventLog.Slot is within its 10-ms frame.
% Never substitute row ordinals for missing physical event coordinates.
assert(istable(events) && all(ismember({'Frame','Slot'},events.Properties.VariableNames)), ...
    'sixgr:truth:MissingRAEventClock','Retain the physical event frame and slot.');
validateattributes(slotDuration_s,{'numeric'},{'real','scalar','finite','positive'});
perFrame=0.01/double(slotDuration_s);
assert(perFrame==fix(perFrame) && perFrame>=1, ...
    'sixgr:truth:InvalidRAEventClock','The event clock must partition the 10-ms frame exactly.');
frame=double(events.Frame); within=double(events.Slot);
assert(all(isfinite(frame) & frame>=0 & frame==fix(frame)) && ...
    all(isfinite(within) & within>=0 & within<perFrame & within==fix(within)), ...
    'sixgr:truth:InvalidRAEventClock','RA events require exact absolute frames and in-frame slots.');
slots=frame*perFrame+within;
assert(all(slots<flintmax),'sixgr:truth:InvalidRAEventClock','RA event clock exceeds exact integer range.');
end
