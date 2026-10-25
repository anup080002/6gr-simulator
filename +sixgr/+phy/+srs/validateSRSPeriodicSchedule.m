function T = validateSRSPeriodicSchedule(srsCfg)
%VALIDATESRSPERIODICSCHEDULE Configured/native mapping check, not reception.

slots = double(srsCfg.ExpectedSlotSet(:));
[period,offset]=sixgr.phy.srs.validateSRSPeriodOffset(srsCfg.Periodicity,srsCfg.Offset);
sixgr.phy.srs.validateSRSOccasionCoordinates(period,offset,slots,[]);
expected = mod(slots - offset, period) == 0;
native=false(numel(slots),1);
for k=1:numel(slots)
    carrier=srsCfg.ToolboxCarrier; carrier.NSlot=slots(k);
    native(k)=~isempty(nrSRSIndices(carrier,srsCfg.ToolboxSRS));
end
T = table(repmat(string(srsCfg.RunId), numel(slots), 1), slots, ...
    repmat(double(period), numel(slots), 1), repmat(double(offset), numel(slots), 1), ...
    expected, nan(numel(slots),1), native, repmat(string(srsCfg.ConfigHash), numel(slots), 1), ...
    repmat("configured_native_resource_mapping_not_received_evidence", numel(slots), 1), ...
    'VariableNames', {'RunId','Slot','Periodicity','Offset','ExpectedOccasion','ObservedOccasion', ...
    'NativeMappingOccasion','ConfigHash','TruthStatus'});
end
