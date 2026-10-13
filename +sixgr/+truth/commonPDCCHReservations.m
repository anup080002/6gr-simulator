function coordinates=commonPDCCHReservations(state,cfg,slot0,cellID,carrier)
% Cell-common configured DL resources plus already committed RA plans.
% No UE payload, decoded outcome or energy hypothesis enters admission.
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
assert(plan.Carrier.SubcarrierSpacing==carrier.SubcarrierSpacing && ...
    strcmp(plan.Carrier.CyclicPrefix,carrier.CyclicPrefix), ...
    'sixgr:truth:CommonControlNumerologyMismatch', ...
    'Common and connected control must share an explicit time/frequency plane.');
coordinates=plan.controlReservations(slot0);
if isfield(state,'SharedWaveformStream')
    coordinates=unique([coordinates;state.SharedWaveformStream.commonRAResources( ...
        cellID,slot0,"DL",carrier)],'rows');
end
end
