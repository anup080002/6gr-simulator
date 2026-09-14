function [state,id]=queueSharedPUSCHAfterRejectedControl(state,cfg,control)
% The UE stays silent; the gNB retains its scheduled receive opportunity.
% This registers observations only, without UE timing advance or preparation.
[grant,transmission]=sixgr.truth.scheduledGrantForRejectedULControl(state,control);
owner=state.SharedWaveformStream; fs=owner.SampleRateHz;
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,grant.UEIndex,'UL');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,grant.Slot,grant.Frame);
cfg=sixgr.truth.bindSharedDataOccasion(cfg,grant.Slot,grant.Frame,fs);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[guard,source]=sixgr.phy.sync.resolveTimingSearchGuard(cfg,fs);
assert(startsWith(source,"configured_receiver_timing_uncertainty"), ...
    'sixgr:truth:RejectedULTimingSearchAuthorityRequired','Use the configured receive uncertainty, not a silent exact-clock default.');
slot0=double(grant.TimingDecision.DataAbsoluteSlot);
first=sixgr.phy.frame.slotStartSample(carrier,slot0,fs)-guard;
stop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,fs)+guard;
assert(first>=owner.Events.NextSampleIndex, ...
    'sixgr:truth:LateRejectedULReceiveWindow', ...
    'Scheduled gNB capture must be registered before its first sample; never backfill or pad.');
rows=sixgr.util.structGet(state,'SharedRejectedULReceiveWindows',{});
assert(~any(cellfun(@(x)x.ControlKey==string(control.Key),rows)), ...
    'sixgr:truth:DuplicateRejectedULReceiveWindow','One rejected command may arm only one scheduled receive window.');
id=owner.queuePUSCHReceiveOnly(grant.UEIndex,cfg,grant,first,stop);
rows{end+1}=struct('ControlKey',string(control.Key),'ObservationID',id, ...
    'GrantContextID',string(grant.PHYGrant.GrantContextId), ...
    'ControlAvailableAtSample',control.AvailableAtSample, ...
    'GNBControlObservationID',transmission.ObservationID,'GNBControlAvailableAtSample',transmission.AvailableAtSample, ...
    'StartSample',first,'EndSampleExclusive',stop, ...
    'TimingGuardSamples',guard,'TimingGuardSource',source);
state.SharedRejectedULReceiveWindows=rows;
end
