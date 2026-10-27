function [state,deferred]=deferSharedDataPreparation(state,cfg,multiUser,plan,direction,snr)
% One original queued bearer head cannot be encoded into two future TBs.
deferred=false; direction=upper(string(direction));
if ~logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)) || ...
        sixgr.truth.GrantPreparation.grantIsRetransmission(plan.GrantSnapshot)
    return;
end
bridge=state.ProtocolBridge;
if ~bridge.hasUncommittedTransport(plan.UEIndex,direction),return;end
key=sixgr.truth.GrantPreparation.sharedGrantControlKey(plan.GrantSnapshot,direction);
pending=sixgr.util.structGet(state,'SharedDeferredDataPreparations',{});
assert(~any(cellfun(@(p)p.Key==key,pending)), ...
    'sixgr:truth:DuplicateDeferredDataPreparation','An original grant can wait only once.');
pending{end+1,1}=struct('Key',key,'UEIndex',plan.UEIndex,'Direction',direction, ...
    'Plan',plan,'Config',cfg,'MultiUser',multiUser,'SNR',snr);
state.SharedDeferredDataPreparations=pending;
deferred=true;
end
