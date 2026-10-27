function [state,cfgSRS]=bindSharedSRSReceivedPowerOwner(state,cfgSRS,ue)
% Bind the live UE-owned PUSCH adjustment to same-as-PUSCH SRS preparation.
% This retains value-state history; it does not receive/apply a TPC command,
% reset an existing owner, or replace the later emission-time power binding.
if string(sixgr.util.structGet(cfgSRS, ...
        'rf.frontend.ul_power_control.srs.adjustment_state',''))~="same_as_pusch"
    return;
end
validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
states=sixgr.util.structGet(state,'SharedUEULPowerControlStates',{});
assert(iscell(states),'sixgr:srs:InvalidReceivedPowerOwners', ...
    'Retain the original per-UE received-command owners.');
if numel(states)<ue || isempty(states{ue})
    states{ue}=sixgr.link.ReceivedULPowerControlState(cfgSRS);
end
assert(isa(states{ue},'sixgr.link.ReceivedULPowerControlState'), ...
    'sixgr:srs:MissingReceivedPowerState', ...
    'Do not replace an existing invalid UE power owner with an initial state.');
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfgSRS,'0_1');
assert(states{ue}.RNTI==context.Data.RNTIValue, ...
    'sixgr:power:WrongEndpoint','SRS must retain its own UE received-command owner.');
state.SharedUEULPowerControlStates=states;
cfgSRS.phy.srs.receivedPowerControlState=states{ue};
end
