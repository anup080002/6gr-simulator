function row=bindPositionClock(row,state)
% Position validity is distinct from the historical receiver event's slot.
slot=double(sixgr.util.structGet(state,'MobilityStateSlot',NaN));
row.PositionValidAtTime_s=(slot-1)*double(state.SlotDuration_s);
row.MobilityStateVersion=double(sixgr.util.structGet(state,'MobilityStateVersion',NaN));
row.PositionSource="runtime_mobility_state";
row.VelocityReferenceFrame="scenario_global_cartesian_metre_second";
row.PositionValidAtSample=NaN; row.PositionSnapshotAtSample=NaN;
row.PositionSampleRateHz=NaN;
stream=sixgr.util.structGet(state,'SharedWaveformStream',[]);
if ~isempty(stream)
    row.PositionSampleRateHz=double(stream.SampleRateHz);
    row.PositionValidAtSample=round(row.PositionValidAtTime_s*stream.SampleRateHz);
    row.PositionSnapshotAtSample=double(stream.Events.NextSampleIndex);
end
end
