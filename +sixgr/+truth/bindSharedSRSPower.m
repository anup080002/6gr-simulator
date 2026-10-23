function state=bindSharedSRSPower(state,item)
% Apply the received UE adjustment at the live SRS emission boundary.
% The shared owner validates the clock and forbids changing emitted energy.
assert(string(item.Kind)=="BindSRSPower",'sixgr:srs:WrongPowerBindingEvent', ...
    'Only the queued SRS resource-boundary event can bind sounding power.');
states=sixgr.util.structGet(state,'SharedUEULPowerControlStates',{});
assert(numel(states)>=item.UE && ...
    isa(states{item.UE},'sixgr.link.ReceivedULPowerControlState'), ...
    'sixgr:srs:MissingReceivedPowerState','Retain the UE power owner until SRS emission.');
state.SharedWaveformStream.bindSRSPower(item.UE,item.Context.ObservationID,states{item.UE});
end
