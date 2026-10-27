function state=completeSharedCellMsg3Reception(state,item)
% Original independently registered gNB capture -> PHY/MAC receive result.
owner=state.SharedWaveformStream;owner.validateCellMsg3Completion(item);
prior=sixgr.util.structGet(state,'CellMsg3ReceiveResults',{});
assert(~any(cellfun(@(r)r.ObservationID==item.ID,prior)), ...
    'sixgr:truth:DuplicateCellMsg3Reception','Decode each original cell Msg3 interval once.');
c=item.Context;p=c.Plan;root=c.Config.run.rootRunFolder;
folder=fullfile(root,'control','cell_msg3');sixgr.util.ensureFolder(folder);
% Preserve original inputs before decoder/tool errors can interrupt a run.
save(fullfile(folder,item.ID+'_original.mat'),'item','-v7.3');
post=item.Planes(endsWith(string({item.Planes.ReceiverID}),':post_rf')).Observation;
pre=item.Planes(endsWith(string({item.Planes.ReceiverID}),':pre_rf')).Observation;
result=owner.completeCellMsg3Receiver(item);
save(fullfile(folder,item.ID+'_received.mat'),'result','-v7.3');
% Compact receiver metadata excludes large native arrays, which remain in
% the original MAT evidence. No failed CRC or unsupported PDU becomes Setup.
receipt=owner.originalCellMsg3ReceiveReceipt(item.ID);
sixgr.util.jsonWrite(fullfile(folder,item.ID+'.json'),receipt);
prior{end+1,1}=receipt;state.CellMsg3ReceiveResults=prior;
row=table(string(item.ID),p.ServingCell,p.TemporaryCRNTI,p.RAPID,p.AbsoluteSlot0+1, ...
    p.ReceiveStartSample,p.ReceiveEndSampleExclusive,p.SampleRateHz,p.TransportBlockSize, ...
    p.Grant.MCS,p.Grant.NLayers,result.CRCPass,result.SemanticAccepted,result.SemanticStatus, ...
    result.SemanticErrorIdentifier,result.SemanticErrorMessage,p.RARComponentID,p.RARPayloadSHA256, ...
    p.SHA256,post.sampleHash(),pre.sampleHash(),result.ReceivedMACSHA256,receipt.SHA256, ...
    true,false,"original_independent_cell_Msg3_receiver", ...
    'VariableNames',{'ObservationID','ServingCell','RNTI','RAPID','Slot','ObservationStartSample', ...
    'ObservationEndSampleExclusive','SampleRateHz','TBSBits','MCS','Layers','CRCPass', ...
    'MACRRCSemanticAccepted','MACRRCSemanticStatus','SemanticErrorIdentifier','SemanticErrorMessage', ...
    'OriginalRARComponentID','OriginalRARPayloadSHA256','OriginalReceivePlanSHA256', ...
    'OriginalPostRXSampleSHA256','OriginalPreRXSampleSHA256','ReceivedMACSHA256', ...
    'ReceiveReceiptSHA256','ReceiverExecuted','MACRRCStandardsQualified','Source'});
row=sixgr.truth.bindCoupledExecutionIdentity(row,c.Config,'cell_Msg3_receiver',true);
old=sixgr.util.structGet(state,'ControlTrials.RAEvidenceTables.cell_msg3_receiver_observations',table());
if isempty(old),old=row;else,old=[old;row];end
state.ControlTrials.RAEvidenceTables.cell_msg3_receiver_observations=old;
sixgr.util.csvWriteTable(fullfile(root,'control','csv','cell_msg3_receiver_observations.csv'),old);
if result.SemanticAccepted
    [state,response]=sixgr.truth.prepareReceivedCellMsg4Response(state,item,receipt);
    pending=sixgr.util.structGet(state,'CellMsg4ResponseDispositions',{});
    pending{end+1,1}=response;state.CellMsg4ResponseDispositions=pending;
    sixgr.util.jsonWrite(fullfile(folder,item.ID+'_response.json'),response);
end
end
