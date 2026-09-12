function grant=bindExecutedHARQClock(grant,carrier,absoluteSlot1)
% Snapshot the executed NR clock; a missing planning alias is not a clock.
validateattributes(absoluteSlot1,{'numeric'},{'scalar','integer','positive','finite'});
assert(isa(carrier,'nrCarrierConfig'),'sixgr:link:HARQExecutedCarrierRequired', ...
    'HARQ execution clock requires the actual waveform carrier.');
slot0=double(absoluteSlot1)-1; perFrame=double(carrier.SlotsPerFrame);
assert(double(carrier.NSlot)==mod(slot0,perFrame) && ...
    double(carrier.NFrame)==mod(floor(slot0/perFrame),1024), ...
    'sixgr:link:HARQExecutedClockMismatch','The waveform carrier must match the absolute data slot.');
frame1=floor(slot0/perFrame)+1;
names={'Slot','Frame','ScheduledAbsoluteSlot'}; values=[double(absoluteSlot1) frame1 slot0];
for k=1:numel(names)
    if isfield(grant,names{k}) && ~isempty(grant.(names{k}))
        value=double(grant.(names{k}));
        assert(isscalar(value) && (isnan(value) || value==values(k)), ...
            'sixgr:link:HARQExecutedClockMismatch', ...
            'A supplied grant clock must match execution, not be silently overwritten.');
    end
end
grant.Slot=double(absoluteSlot1);
grant.Frame=frame1;
grant.ScheduledAbsoluteSlot=slot0;
grant.HARQClockSource='executed_nr_carrier_and_absolute_slot';
end
