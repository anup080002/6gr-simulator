function [next,receipt]=installReceivedNewDRB(state,srbRuntime,delivery,expected,coreContext,evidenceBoundary,actor,capsule,currentSample)
% Install UE routing aliases for an EXISTING original issued connection capsule.
% No new Runtime/COUNT/RLC is created at reception. Bridge binding is separate.
id='sixgr:rrc:NewDRBInstallation';
assert(nargin>=9&&isa(capsule,'sixgr.rrc.PendingDRBEndpoints'), ...
    'sixgr:rrc:OriginalIssuedDRBRequired','Original issued capsule, actual transport owner and current native sample are required.');
assert(string(evidenceBoundary)=="original_shared_receiver",id,'Declared fixtures cannot activate production DRB admission.');
assert(isstruct(state)&&isscalar(state)&&isfield(state,'InstalledDRBBearers')&&iscell(state.InstalledDRBBearers),id,'Require the complete original issued bearer registry.');
for name=["ExecutionRunID","UEID","ServingCell","RNTI","ConfigurationEpoch","SampleRateHz","ClockEpoch"]
    assert(isequaln(expected.(name),capsule.Connection.(name)),id,'Original connection scope differs.');
end
assert(expected.RRCTransactionID==capsule.OriginalMessage.Semantic.transaction_id,id,'Original procedure differs.');
configs=sixgr.rrc.buildNewDRBProtocolConfigurations(capsule.OriginalMessage,capsule.Connection,coreContext);
assert(string(sixgr.l2.mac.MACHash.of(configs))==capsule.ConfigurationSHA256,id,'Original protocol configuration changed.');
matched=[];
for k=1:numel(state.InstalledDRBBearers)
    r=state.InstalledDRBBearers{k};
    assert(isstruct(r)&&isscalar(r)&&isfield(r,'PreparedEndpoints'),id,'Malformed original issued registry.');
    if isequal(r.PreparedEndpoints,capsule),matched(end+1)=k;end %#ok<AGROW>
end
assert(isscalar(matched),id,'Exactly one original issued owner must already exist in the registry.');
record=state.InstalledDRBBearers{matched};
assert(isequaln(record.OriginalMessage,capsule.OriginalMessage),id,'Registry original UPER changed.');
message=sixgr.rrc.validateDRBOriginalSRBTransport(actor,srbRuntime,delivery,capsule.Connection,"received");
assert(isequal(message.Bytes,capsule.OriginalMessage.Bytes),id,'Actual received configuration differs.');
receipt=struct('ContractVersion',"received_new_DRB_installation/v2", ...
    'Connection',capsule.Connection,'RRCTransactionID',message.Semantic.transaction_id, ...
    'RRCPayloadSHA256',message.SHA256,'OriginalObservationSHA256',delivery.ReceiverObservationSHA256, ...
    'ReceivedAvailableAtSample',delivery.AvailableAtSample,'InstalledAtSample',currentSample,'ConfigurationSHA256',capsule.ConfigurationSHA256, ...
    'DRBIntegrityEnabled',false,'SRBIntegrityAlgorithm',"128-NIA2", ...
    'Source',"decoded_RRCReconfiguration_same_issued_runtime_alias", ...
    'EvidenceBoundary',"original_shared_receiver",'NASValidated',false);
% All registry/config validation completes before paired endpoint mutation.
receipts=sixgr.rrc.projectDRBAdmissionPair(capsule,delivery,"received");
capsule.admitReceived(receipts,currentSample);
record.Receipt=receipt;record.EndpointBindingStatus="original_UE_received_same_runtime_alias";
next=state;next.InstalledDRBBearers{matched}=record;
end
