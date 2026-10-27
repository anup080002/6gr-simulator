function [state,result,checkpoint]=installReceivedNRSRB1(state,ue,result,checkpoint)
% Install the actual SRB protocol owner only after original NR Setup decode.
id='sixgr:truth:NRReceivedSRB1';
assert(isfield(state,'NRRRCSetupAttemptsByUE')&&numel(state.NRRRCSetupAttemptsByUE)>=ue&& ...
    isa(state.NRRRCSetupAttemptsByUE{ue},'sixgr.mac.ra.NRRRCSetupAttemptState')&& ...
    checkpoint.NextStage==5,id,'Require the original RRC-attempt and received Setup boundary.');
[attempt,setup]=state.NRRRCSetupAttemptsByUE{ue}.receiveSetup( ...
    checkpoint.RARReceiver,checkpoint.ContentionReceiver,state.SharedWaveformStream);
if ~isfield(state,'NRSRB1RuntimeByUE'),state.NRSRB1RuntimeByUE=cell(state.NumUsers,1);end
assert(isempty(state.NRSRB1RuntimeByUE{ue}),id,'Initial Setup cannot overwrite an existing bearer.');
policy=attempt.Policy;
complete=sixgr.rrc.asn1.NRAccessMessageCodec.encode("setup_complete",struct( ...
    'transaction_id',setup.TransactionID,'selected_plmn_identity',policy.SelectedPLMNIdentity, ...
    'dedicated_nas_hex',policy.DedicatedNASHex));
connections=sixgr.util.structGet(state,'NRCellConnections',{});
hit=find(cellfun(@(c)c.ConnectionID==setup.ConnectionID,connections));
assert(isscalar(hit),id,'The gNB must already own this original issued Setup pair.');
connection=connections{hit};
assert(~connection.UEReceivedSetup&&isnan(connection.UEIndex) && ...
    isequaln(connection.Descriptor,setup.ConnectionDescriptor) && ...
    isequaln(connection.OriginalMsg4Proof,setup.OriginalMsg4Proof) && ...
    isequaln(connection.ProtocolConfigurations{1},setup.ProtocolConfiguration),id, ...
    'UE Setup activates the same issued owners without replacing COUNT, RLC or scope.');
owners={connection.ULRuntime,connection.DLRuntime};received=cell(1,2);
for k=1:2
    r=connection.ProtocolConfigurations{k}.EndpointAdmissionScope;
    r.ContractVersion="received_NR_SRB1_setup/v1";
    r.RRCTransactionID=setup.TransactionID;r.RRCSetupSHA256=setup.ReceivedRRCSetupSHA256;
    r.IssuedSetupReceiptSHA256=connection.IssuedSetupReceipts{k}.SHA256;
    r.ReceiverObservationID=setup.ReceiverObservationID;
    r.ReceiverObservationSHA256=setup.ReceiverObservationSHA256;
    r.ReceivedMACPayloadSHA256=setup.ReceivedMACPayloadSHA256;
    r.ObservationStartSample=setup.ContentionObservation.ObservationStartSample;
    r.ObservationEndSampleExclusive=setup.ContentionObservation.ObservationEndSampleExclusive;
    r.AvailableAtSample=setup.AvailableAtSample;
    r.OriginalRARObservationSHA256=setup.OriginalRARObservationSHA256;
    r.OriginalContentionObservationSHA256=setup.OriginalContentionObservationSHA256;
    r.UEIndex=ue;r.MACAttemptRunID=setup.RunId;r.AttemptID=setup.AttemptId;
    r.SHA256=sixgr.l2.mac.MACHash.of(r);
    owners{k}.validateReceivedSetup(r,state.SharedWaveformStream.Events.NextSampleIndex);
    received{k}=r;
end
% Both private owners were preflighted before either changes. No event or
% callback runs between these paired endpoint admissions.
for k=1:2,owners{k}.admitReceivedSetup(received{k},state.SharedWaveformStream.Events.NextSampleIndex);end
runtime=connection.ULRuntime;
% The configured runtime converts these seconds back to its exact original
% sample clock; its API does not accept a separate authored timestamp struct.
time=setup.AvailableAtSample/setup.SampleRateHz;
packet=runtime.enqueuePacket("RRCSetupComplete/"+complete.SHA256,reshape(complete.Bytes,1,[]),time);
state.NRRRCSetupAttemptsByUE{ue}=attempt;
state.NRSRB1RuntimeByUE{ue}=runtime;
if ~isfield(state,'NRSRB1DLRuntimeByUE'),state.NRSRB1DLRuntimeByUE=cell(state.NumUsers,1);end
state.NRSRB1DLRuntimeByUE{ue}=connection.DLRuntime;
connection.UEIndex=ue;connection.UEReceivedSetup=true;connection.ReceivedSetupReceipts=received;
connection.Status="same_issued_pair_admitted_by_original_UE_received_Setup";
state.NRCellConnections{hit}=connection;
if ~isfield(state,'NRSetupCompleteByUE'),state.NRSetupCompleteByUE=cell(state.NumUsers,1);end
state.NRSetupCompleteByUE{ue}=struct('Setup',setup,'OriginalULDCCH',complete,'Packet',packet, ...
    'UEConnected',true,'GNBSetupCompleteReceived',false,'DedicatedDRBInstalled',false, ...
    'Status',"waiting_original_received_common_CRNTI_uplink_grant", ...
    'NASSource',policy.NASSource);
result.ReceivedNRSRB1Installation=setup;
result.SRB1Installed=true;
result.UERRCConnected=true;
result.RRCConnected=false; % Existing aggregate means both endpoint milestones.
checkpoint.Result=result;
end
