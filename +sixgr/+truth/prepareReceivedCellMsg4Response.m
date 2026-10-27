function [state,response]=prepareReceivedCellMsg4Response(state,item,receipt)
% Actual independently completed gNB Msg3 authorizes common Msg4 only.
% No UE RAR/contention success or intended identity enters this producer.
owner=state.SharedWaveformStream;owner.validateCellMsg3Completion(item);
assert(isequaln(receipt,owner.originalCellMsg3ReceiveReceipt(item.ID)), ...
    'sixgr:truth:CellMsg4ReceiveAuthority','Use the private original cell receive result.');
c=item.Context;p=c.Plan;cfg=c.Config;
response=struct('OriginalReceiveReceiptSHA256',receipt.SHA256, ...
    'Status',"no_supported_received_CCCH",'ComponentID',"",'Proposal',struct());
if ~receipt.SemanticAccepted,return;end
carrier=sixgr.phy.grid.makeCarrier(cfg);
available=@(slot)isempty(owner.commonRAResources(p.ServingCell,slot,"DL",carrier));
[cfg,ra,msg4,proposal]=sixgr.truth.buildCellMsg4TransmissionContext(cfg,p,receipt,available);
response.Proposal=proposal;
if ~proposal.ResponseSchedulable
    response.Status="no_causal_disjoint_common_Msg4_opportunity";return;
end
prepared=sixgr.truth.prepareCellMsg4Transmission(cfg,ra,msg4,proposal,receipt);
[id,~]=owner.queueCellMsg4Transmission(prepared);
response.Status="original_cell_Msg4_enqueued_not_yet_transmitted";
response.ComponentID=id;
end
