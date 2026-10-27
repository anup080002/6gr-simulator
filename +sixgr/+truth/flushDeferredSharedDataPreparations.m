function state=flushDeferredSharedDataPreparations(state,ue,direction)
% Resume retained original plans after earlier actual TX commits its queue.
direction=upper(string(direction));
if ~logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)),return;end
pending=sixgr.util.structGet(state,'SharedDeferredDataPreparations',{});
while ~state.ProtocolBridge.hasUncommittedTransport(ue,direction)
    hit=find(cellfun(@(p)p.UEIndex==ue && p.Direction==direction,pending),1);
    if isempty(hit),return;end
    entry=pending{hit}; pending(hit)=[];
    state.SharedDeferredDataPreparations=pending;
    % Keep the original received grant, rank, coding allocation and times.
    % queueData itself rejects any elapsed physical preparation deadline.
    state=sixgr.truth.queuePreparedSharedDataPlan(state,entry.Config, ...
        entry.MultiUser,entry.Plan,entry.Direction,entry.SNR);
    pending=sixgr.util.structGet(state,'SharedDeferredDataPreparations',{});
end
end
