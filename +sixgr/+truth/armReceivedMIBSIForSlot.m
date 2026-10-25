function ids=armReceivedMIBSIForSlot(state)
%ARMRECEIVEDMIBSIFORSLOT Arm future SI captures from original received clocks.
% A complete extra receive slot is needed beyond the current one: using
% only the next nominal slot boundary loses windows shifted by propagation
% or measured timing. This is planning lookahead, not added radio latency.
ids=strings(0,1);
owner=state.SharedWaveformStream;
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
validateattributes(state.CanonicalSlotsPerSweepPoint,{'double'}, ...
    {'real','scalar','finite','integer','positive'});
runEnd=sixgr.phy.frame.slotStartSample(carrier, ...
    state.CanonicalSlotsPerSweepPoint,owner.SampleRateHz);
now=owner.Events.NextSampleIndex;
if now>=runEnd, return; end
for ue=1:state.NumUsers
    [available,~,binding]=sixgr.truth.ReceivedMIBDelivery.current(state,ue);
    if ~available, continue; end
    installed=sixgr.util.structGet(state,'DecodedSIB1RecoveryByUE',{});
    if numel(installed)>=ue && isstruct(installed{ue}) && ...
            string(sixgr.util.structGet(installed{ue},'ReceivedMIBGenerationID',''))==binding.GenerationID
        % This original SI has already been accepted and installed. Pending
        % armed captures are not cancelled or relabelled as receptions.
        continue;
    end
    data=binding.Context.Data;
    spec=sixgr.phy.frame.NumerologyCatalog.resolve( ...
        data.ReceiverGeometry.SubcarrierSpacing,data.ReceiverGeometry.CyclicPrefix, ...
        'generic_waveform_test','');
    elapsed=now-data.ReceivedFrameOriginSample;
    ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/owner.SampleRateHz;
    assert(isfinite(elapsed) && elapsed>=0 && elapsed==fix(elapsed) && ...
        ticksPerSample>=1 && ticksPerSample==fix(ticksPerSample) && ...
        elapsed<=flintmax/ticksPerSample, ...
        'sixgr:truth:InvalidSIMonitoringClock','Keep exact received-frame sample and basic-time coordinates.');
    time=sixgr.phy.frame.AbsoluteTime(int64(elapsed*ticksPerSample));
    [~,frame,slot]=time.floorToSlot(spec);
    relative=double(frame)*spec.SlotsPerFrame+double(slot);
    horizon=data.ReceivedFrameOriginSample+sixgr.phy.frame.slotStartSample( ...
        data.ReceiverGeometry,relative+2,owner.SampleRateHz);
    horizon=min(horizon,runEnd);
    [queued,~]=owner.armSIB1ReceiveOnly(state,ue,horizon);
    ids=[ids;queued(:)]; %#ok<AGROW>
end
end
