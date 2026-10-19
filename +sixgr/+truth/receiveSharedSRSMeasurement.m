function [state,output,capture]=receiveSharedSRSMeasurement(state,item,input)
% Receive once; preserve only completed receiver pilot history per UE.
c=item.Context;
input.PilotPhaseContextID=sixgr.truth.srsPilotPhaseContextID(c.Config, ...
    state.SharedWaveformStream.Physical.ConfigurationEpoch,item.UE,c.ServingCell);
input.PilotPhaseHistory=struct();
if isfield(state,'SRSPilotPhaseHistoryByUE') && ...
        numel(state.SRSPilotPhaseHistoryByUE)>=item.UE && ...
        ~isempty(state.SRSPilotPhaseHistoryByUE{item.UE})
    input.PilotPhaseHistory=state.SRSPilotPhaseHistoryByUE{item.UE};
end
if nargout>2
    [output,capture]=sixgr.link.runSRSChannelEstimation( ...
        c.Config,c.Arguments{:},'ReceivedContext',input);
else
    output=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
end
if ~isempty(fieldnames(output.PilotPhaseTrackingState))
    state.SRSPilotPhaseHistoryByUE{item.UE,1}=output.PilotPhaseTrackingState;
end
end
