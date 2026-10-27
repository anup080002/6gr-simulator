function [state,observed]=completeSharedCellMsg4Transmission(state,item)
% Publish the actual cell TX independently of every UE monitoring result.
proof=sixgr.truth.verifyCellMsg4TransmissionCompletion(state.SharedWaveformStream,item);
p=item.Context.Prepared; root=p.Config.run.rootRunFolder;
prior=sixgr.util.structGet(state,'CellMsg4TransmissionReceipts',{});
assert(~any(cellfun(@(r)r.ComponentID==proof.ComponentID,prior)), ...
    'sixgr:truth:DuplicateCellMsg4Completion','Publish each original cell Msg4 once.');
prior{end+1,1}=proof;state.CellMsg4TransmissionReceipts=prior;
[state,~]=sixgr.truth.createIssuedNRSRB1(state,item);
folder=fullfile(root,'control','cell_msg4');sixgr.util.ensureFolder(folder);
sixgr.util.jsonWrite(fullfile(folder,proof.ComponentID+'.json'),proof);
row=table(proof.ComponentID,p.ServingCell,p.TemporaryCRNTI,p.AbsoluteSlot+1, ...
    proof.TransmitStartSample,proof.TransmitEndSampleExclusive,proof.SampleRateHz, ...
    proof.ReceiverReceiptSHA256,proof.ResponseProposalSHA256,proof.Msg4MACPayloadSHA256, ...
    proof.TransmitObservationSHA256,true,false,proof.ObservationScope, ...
    'VariableNames',{'ObservationID','ServingCell','TemporaryCRNTI','Slot', ...
    'TransmitStartSample','TransmitEndSampleExclusive','SampleRateHz','ReceiverReceiptSHA256', ...
    'Msg4ProposalSHA256','Msg4MACPayloadSHA256','TransmitObservationSHA256','PhysicalTransmissionVerified', ...
    'ReceiverExecutionClaimed','Scope'});
row=sixgr.truth.bindCoupledExecutionIdentity(row,p.Config,'cell_Msg4_transmitter',true);
old=sixgr.util.structGet(state,'ControlTrials.RAEvidenceTables.cell_msg4_transmissions',table());
if isempty(old),old=row;else,old=[old;row];end
state.ControlTrials.RAEvidenceTables.cell_msg4_transmissions=old;
sixgr.util.csvWriteTable(fullfile(root,'control','csv','cell_msg4_transmissions.csv'),old);
observed=table();
for channel=["PDCCH","PDSCH"]
    tx=p.Tx.(channel);
    if channel=="PDCCH",tx.PDCCHIndices=tx.PDCCHInd;tx.DMRSIndices=tx.DMRSInd;end
    part=sixgr.truth.buildObservedREAllocation(tx,'Channel',channel,'Direction','DL', ...
        'AbsoluteSlot',p.AbsoluteSlot,'CellID',p.ServingCell,'UEID',0, ...
        'AllocationID',proof.ComponentID+'_'+channel);
    part.port_domain=repmat("executed_tx_object_grid_before_shared_spatial_mapping",height(part),1);
    part.grid_port_count=repmat(size(tx.Grid,3),height(part),1);
    part.observation_start_sample=repmat(proof.TransmitStartSample,height(part),1);
    part.observation_end_sample_exclusive=repmat(proof.TransmitEndSampleExclusive,height(part),1);
    part.observation_sample_rate_hz=repmat(proof.SampleRateHz,height(part),1);
    if isempty(observed),observed=part;else,observed=[observed;part];end
end
end
