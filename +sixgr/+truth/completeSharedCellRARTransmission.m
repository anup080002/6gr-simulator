function [state,observed]=completeSharedCellRARTransmission(state,item)
% Publish the actual cell TX independently of every UE monitoring result.
proof=sixgr.truth.verifyCellRARTransmissionCompletion(state.SharedWaveformStream,item);
p=item.Context.Prepared; root=p.Config.run.rootRunFolder;
prior=sixgr.util.structGet(state,'CellRARTransmissionReceipts',{});
assert(~any(cellfun(@(r)r.ComponentID==proof.ComponentID,prior)), ...
    'sixgr:truth:DuplicateCellRARCompletion','Publish each original cell RAR once.');
prior{end+1,1}=proof;state.CellRARTransmissionReceipts=prior;
policy=sixgr.lls6g.config.resolveNRAccessPolicy(sixgr.util.structGet(p.Config,'initial_access.rrc',struct()));
if policy.Enabled
    % Arm from this actual emitted cell response; never wait for any UE to
    % decode RAR or prepare/transmit Msg3 before owning the gNB receiver.
    state.SharedWaveformStream.armCellMsg3Receivers(item);
end
folder=fullfile(root,'control','cell_rar');sixgr.util.ensureFolder(folder);
sixgr.util.jsonWrite(fullfile(folder,proof.ComponentID+'.json'),proof);
row=table(proof.ComponentID,p.ServingCell,p.RARNTI,p.AbsoluteSlot+1, ...
    proof.TransmitStartSample,proof.TransmitEndSampleExclusive,proof.SampleRateHz, ...
    proof.ReceiverReceiptSHA256,proof.RARPlanSHA256,proof.RARPayloadSHA256, ...
    proof.TransmitObservationSHA256,true,false,proof.ObservationScope, ...
    'VariableNames',{'ObservationID','ServingCell','RARNTI','Slot', ...
    'TransmitStartSample','TransmitEndSampleExclusive','SampleRateHz','ReceiverReceiptSHA256', ...
    'RARPlanSHA256','RARPayloadSHA256','TransmitObservationSHA256','PhysicalTransmissionVerified', ...
    'ReceiverExecutionClaimed','Scope'});
row=sixgr.truth.bindCoupledExecutionIdentity(row,p.Config,'cell_RAR_transmitter',true);
old=sixgr.util.structGet(state,'ControlTrials.RAEvidenceTables.cell_rar_transmissions',table());
if isempty(old),old=row;else,old=[old;row];end
state.ControlTrials.RAEvidenceTables.cell_rar_transmissions=old;
sixgr.util.csvWriteTable(fullfile(root,'control','csv','cell_rar_transmissions.csv'),old);
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
