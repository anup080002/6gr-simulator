function state=advanceMobilityClock(state,slot)
% One physical trajectory clock, independent of mutable scheduling cursors.
validateattributes(slot,{'numeric'},{'scalar','integer','positive','finite'});
last=double(sixgr.util.structGet(state,'MobilityStateSlot',1));
assert(slot>=last,'sixgr:truth:MobilityClockRewind', ...
    'A past-slot consumer cannot evolve the current mobility state.');
version=double(sixgr.util.structGet(state,'MobilityStateVersion',0));
enabled=logical(sixgr.util.structGet(state,'MobilityEnabled',false));
% Preserve the stochastic model's original per-slot cadence even when a
% caller skips reporting slots. A long step is not equivalent for RWP.
for step=last+1:slot
    if enabled
        [state.UE,state.MobilityModel]=sixgr.scenario.mobility.updatePositions( ...
            state.UE,state.CfgMobility,state.SlotDuration_s,state.MobilityModel);
    end
    version=version+1;
end
state.MobilityStateSlot=double(slot);
state.MobilityStateVersion=version;
end
