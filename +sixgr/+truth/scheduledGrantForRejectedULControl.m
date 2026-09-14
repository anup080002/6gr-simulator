function [grant,transmission]=scheduledGrantForRejectedULControl(state,control)
% UE rejection authorizes silence, not the gNB receive allocation. Recover
% that allocation from the owner's physically transmitted command ledger.
received=sixgr.truth.validateSharedRejectedULControl(state,control);
controls=state.SharedWaveformStream.readTransmittedULControls(received.UEIndex,double(received.Slot));
hit=find(cellfun(@(r)r.Binding.GrantContextID==string(received.PHYGrant.GrantContextId),controls));
assert(isscalar(hit),'sixgr:truth:MissingRejectedULScheduledGrant', ...
    'Rejected control must match one actually transmitted gNB UL command.');
transmission=controls{hit}; grant=transmission.Binding.Grant;
for name=["Direction","UEIndex","RNTI","Slot","Frame","TimingDecision","PHYGrant", ...
        "DCI","HARQ","SymbolAllocation","TBSBits","TBSBytes","ULTotalDAIAuthority"]
    assert(isfield(received,name) && isfield(grant,name) && isequaln(received.(name),grant.(name)), ...
        'sixgr:truth:RejectedULScheduledGrantMismatch', ...
        'Received control annotation cannot replace the transmitted gNB allocation field %s.',name);
end
assert(transmission.AvailableAtSample<=control.AvailableAtSample, ...
    'sixgr:truth:RejectedULScheduledGrantClock','The received rejection must not precede the actual command transmission.');
end
