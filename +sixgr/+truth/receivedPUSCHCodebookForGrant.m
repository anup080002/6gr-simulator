function book=receivedPUSCHCodebookForGrant(state,grant)
% Planning may precede control reception; actual TX callers must require a
% typed result. Never substitute the scheduled DCI or pending ACK bit values.
book=[];
if ~isfield(state,'SharedWaveformStream') || ~isfield( ...
        sixgr.util.structGet(state.CfgMobility,'phy.pdcch.operatorControl',struct()),'connected_dci')
    return;
end
controlSlot=sixgr.truth.resolvePDCCHControlSlot(grant);
key="UL_ue_"+grant.UEIndex+"_rnti_"+grant.RNTI+"_control_"+controlSlot+"_data_"+grant.Slot;
controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
hit=find(cellfun(@(r)r.Key==key,controls));
if isempty(hit), return; end
assert(isscalar(hit),'sixgr:truth:AmbiguousReceivedULControl', ...
    'One exact received UL control result must own this PUSCH preparation.');
control=controls{hit};
assert(control.Allowed && ~isempty(control.ReceivedAssignment) && ...
    control.AvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex && ...
    string(control.Grant.PHYGrant.GrantContextId)==string(grant.PHYGrant.GrantContextId), ...
    'sixgr:truth:UnavailableReceivedULControl','A missed/future/different UL DCI cannot authorize UCI encoding.');
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(state.CfgMobility,state,grant.UEIndex,'UL');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,controlSlot);
book=sixgr.truth.buildReceivedHARQACKCodebook( ...
    state,cfg,grant.UEIndex,grant.Slot,control.ReceivedAssignment);
end
