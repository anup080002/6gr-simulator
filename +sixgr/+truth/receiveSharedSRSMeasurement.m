function [state,output,capture]=receiveSharedSRSMeasurement(state,item,input)
% Receive once; preserve only completed receiver pilot history per UE.
c=item.Context;
% Bind the measurement to the actual completed owner plane. Buffers do not
% themselves carry an endpoint name, so geometry equality alone cannot
% distinguish pre-RF samples from a same-sized post-RF substitute.
planeIDs=string({item.Planes.ReceiverID});
preIndex=find(planeIDs==string(input.Replay.ReceiverID)+":pre_rf");
assert(isscalar(preIndex) && ...
    item.Planes(preIndex).Observation==input.PhysicalMeasurementObservation, ...
    'sixgr:truth:SRSAntennaPlaneIdentity','Measure the original completed pre-RF observation instance.');
input.PhysicalMeasurementEvidence=struct( ...
    'ReceiverID',planeIDs(preIndex),'ObservationID',string(item.ID), ...
    'Observation',item.Planes(preIndex).Observation);
% Read the immutable installation from the actual owner. Do not rebuild it
% from the current scheduler/SRS configuration at completion time.
input.PhysicalMeasurementEvidence.ReceiveBranchLayout= ...
    state.SharedWaveformStream.Physical.receiveBranchLayout(string(input.Replay.ReceiverID));
% Audit-only owner operands. runSRSChannelEstimation never forwards these
% to SRS_Rx; each reference proves its own actual FFT support AFTER reception.
input.SRSIsolationOwner=state.SharedWaveformStream;
input.SRSIsolationItem=item;
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
[reference,referenceEvidence]=sixgr.truth.scoreSharedSRSAntennaPower( ...
    output,item,input,state.SharedWaveformStream);
for field=string(fieldnames(reference)).', output.(field)=reference.(field); end
if nargout>2, capture.SRSAntennaPowerReferenceEvidence=referenceEvidence; end
% Installed producer context, retained before any later scheduler config is
% consulted. This is not the SRI occasion or a UE channel-estimate input.
strict=sixgr.phy.srs.buildSRSConfigFromScenario(c.Config);
output.SRSConfigurationEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
[output.SRSConfigurationContextID,configuration]=sixgr.truth.srsConfigurationContextID( ...
    c.Config,output.SRSConfigurationEpoch,item.UE,c.ServingCell);
output.SRSConfigurationContextVersion=configuration.Version;
output.SRSNumPorts=double(strict.ToolboxSRS.NumSRSPorts);
output.SRSResourceID=double(strict.ResourceId);
output.SRSResourceIDsJSON=string(jsonencode(double(strict.ResourceIds(:).')));
if ~isempty(fieldnames(output.PilotPhaseTrackingState))
    state.SRSPilotPhaseHistoryByUE{item.UE,1}=output.PilotPhaseTrackingState;
end
end
