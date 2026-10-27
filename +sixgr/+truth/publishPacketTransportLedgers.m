function state=publishPacketTransportLedgers(state,T,initialCount)
assert(istable(T)&&isscalar(initialCount)&&initialCount>=0&&initialCount==fix(initialCount)&&initialCount<=height(T), ...
    'sixgr:protocol:InvalidTransportLedger','Preserve the original disjoint/recovery partition.');
state.PacketSDULedgerTable=T(1:initialCount,:);
if height(T)>initialCount||isfield(state,'RLCRecoveryTransportLedgerTable')
    state.RLCRecoveryTransportLedgerTable=T(initialCount+1:end,:);
end
end
