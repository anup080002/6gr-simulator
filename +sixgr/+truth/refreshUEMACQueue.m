function refreshUEMACQueue(state,ue,policy,slot)
% UE-local procedure input only; never a gNB scheduling backlog oracle.
owner=state.SharedUEBSRStates{ue}; volume=state.ProtocolBridge.pendingTransmitBytes(ue,'UL');
old=owner.Buffers(policy.LCGID+1); current=volume.TotalBSRBytes;
if current>old
    owner.arrival(policy.LCGID,current-old);
elseif current<old
    owner.dequeue(policy.LCGID,old-current);
end
owner.advanceTo(slot);
state.SharedUEPHRStates{ue}.advanceTo(slot);
end
