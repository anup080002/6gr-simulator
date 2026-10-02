function out=buildSLSCommonChannelCalendar(cfg,numSlots)
% Reuse exact PHY planners; configuration ownership is not RF observation.
arguments
    cfg struct
    numSlots (1,1) double {mustBeInteger,mustBePositive}
end
planning=cfg;
planning.run.totalSlots=numSlots;
planning.outputs.plannedAllocationEncoding='exact_periodic_templates';
[allocations,checks]=sixgr.truth.buildPlannedREAllocation(planning, ...
    'TargetChannels',["SSB_PBCH","TYPE0_PDCCH","SIB1_PDSCH","CSI_RS","TRS"]);
failed=checks.enabled & ~checks.resolved;
% No periodic occasion in a short window is not an invalid configuration.
noOccasion=ismember(string(checks.error_id), ...
    ["sixgr:truth:EmptyEnabledAllocation","sixgr:truth:NoActiveSSBOccasion", ...
     "sixgr:truth:NoType0Occasion"]);
assert(~any(failed & ~noOccasion),'sixgr:system:CommonReservationUnresolved', ...
    'Common-channel calendar is unresolved: %s', ...
    join(string(checks.feature(failed & ~noOccasion))+": "+string(checks.detail(failed & ~noOccasion)),"; "));
if ~isempty(allocations)
    allocations=allocations(ismember(string(allocations.channel), ...
        ["SSB_PBCH","TYPE0_PDCCH","SIB1_PDSCH","CSI_RS","TRS"]),:);
    assert(all(string(allocations.grid_domain)=="carrier_cp_ofdm"), ...
        'sixgr:system:CommonReservationGrid','Common resources must use the carrier CP-OFDM grid.');
end
checks.status(failed & noOccasion)="NO_OCCASION_IN_WINDOW";
out=struct('Allocations',allocations,'Checks',checks,'NumSlots',numSlots, ...
    'Source',"configured_PHY_calendar_not_RF_execution",'PhysicalTransmissionProven',false);
end
