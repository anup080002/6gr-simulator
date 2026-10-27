function [state,connection]=createIssuedNRSRB1(state,item)
% Original cell Msg4 TX admits gNB endpoints only.
% Actual UE reception later aliases these SAME handles, preserving COUNT/RLC.
id='sixgr:truth:IssuedNRSRB1';owner=state.SharedWaveformStream;
proof=sixgr.truth.verifyCellMsg4TransmissionCompletion(owner,item);
p=item.Context.Prepared;
completed=owner.completedCellMsg4Transmission(p.ServingCell,p.AbsoluteSlot,p.TemporaryCRNTI);
assert(isequaln(completed.Prepared,p)&&isequaln(completed.ExecutionProof,proof),id, ...
    'Only this physical owner''s original completed cell Msg4 may issue Setup.');
original=p.Tx.Msg4.RRCCodecEvidence;
decoded=sixgr.rrc.asn1.NRAccessMessageCodec.decode("setup",original.Bytes);
assert(isequaln(decoded,original)&&decoded.Semantic.srb1_lcid==1 && ...
    decoded.Semantic.cell_group_id==0 && proof.RRCSetupSHA256==decoded.SHA256,id, ...
    'Bind the actual emitted supported Setup bytes, not a configured success flag.');
descriptor=sixgr.truth.resolveNRCellConnectionDescriptor(p,proof);
connectionID=descriptor.ConnectionID;execution=descriptor.ExecutionRunID;
identity=descriptor.OriginalIdentity;originalMsg3=p.OriginalMsg3ReceiveReceipt;
prior=sixgr.util.structGet(state,'NRCellConnections',{});
assert(~any(cellfun(@(c)c.ConnectionID==connectionID || ...
    (c.ServingCell==p.ServingCell&&c.RNTI==p.TemporaryCRNTI),prior)),id, ...
    'A repeated or reused live connection identity requires its existing owner, never COUNT reset.');
directions=["UL","DL"];configs=cell(1,2);runtimes=cell(1,2);issued=cell(1,2);
for k=1:2
    config=sixgr.truth.nrBaseSRB1ProtocolConfiguration(descriptor,directions(k));
    scope=config.EndpointAdmissionScope;
    runtime=sixgr.protocol.ProtocolRuntime(config);
    receipt=scope;
    receipt.ContractVersion="issued_NR_SRB1_setup/v1";
    receipt.RRCTransactionID=decoded.Semantic.transaction_id;
    receipt.RRCSetupSHA256=decoded.SHA256;
    receipt.TransmitComponentID=proof.ComponentID;
    receipt.TransmitEnqueueReceiptSHA256=proof.EnqueueReceiptSHA256;
    receipt.OriginalComponentSampleSHA256=proof.OriginalSampleSHA256;
    receipt.TransmitObservationSHA256=proof.TransmitObservationSHA256;
    receipt.PhysicalTransmissionReceiptSHA256=sixgr.l2.mac.MACHash.of(proof);
    receipt.TransmitStartSample=proof.TransmitStartSample;
    receipt.TransmitEndSampleExclusive=proof.TransmitEndSampleExclusive;
    receipt.IssuedAtSample=proof.CompletedAtSample;
    receipt.OriginalMsg3ReceiveReceiptSHA256=originalMsg3.SHA256;
    receipt.UEIndex=NaN; % No radio receiver routing input exists at this boundary.
    receipt.SHA256=sixgr.l2.mac.MACHash.of(receipt);
    runtime.validateIssuedSetup(receipt,owner.Events.NextSampleIndex);
    configs{k}=config;runtimes{k}=runtime;issued{k}=receipt;
end
% Both owners have passed complete private-state preflight before mutation.
for k=1:2,runtimes{k}.admitIssuedSetup(issued{k},owner.Events.NextSampleIndex);end
connection=struct('ContractVersion',"original_NR_cell_connection/v1", ...
    'Descriptor',descriptor,'ConnectionID',connectionID,'UEID',connectionID,'ServingCell',p.ServingCell, ...
    'RNTI',p.TemporaryCRNTI,'ExecutionRunID',execution,'UEIndex',NaN, ...
    'ConfigurationEpoch',owner.Physical.ConfigurationEpoch,'ClockEpoch',owner.Physical.ConfigurationEpoch, ...
    'SampleRateHz',owner.SampleRateHz,'OriginalIdentity',identity, ...
    'ProtocolConfigurations',{configs},'IssuedSetupReceipts',{issued}, ...
    'ULRuntime',runtimes{1},'DLRuntime',runtimes{2},'OriginalSetup',decoded, ...
    'OriginalMsg4Proof',proof,'OriginalMsg3ReceiveReceipt',originalMsg3, ...
    'UEReceivedSetup',false,'GNBSetupCompleteReceived',false, ...
    'Status',"issued_Setup_gNB_endpoints_admitted_waiting_independent_UE_receive", ...
    'DedicatedDRBInstalled',false,'NASValidated',false);
state.NRCellConnections=[prior;{connection}];
end
