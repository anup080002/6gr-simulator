function mask=matchPacketTransportBlock(T,grant,direction,ueIndex)
% Match received data to its original logical UE/TB, not current radio state.
direction=upper(string(direction));
assert(isscalar(direction) && any(direction==["DL","UL"]) && ...
    isscalar(ueIndex) && isfinite(ueIndex) && ueIndex>=1 && ueIndex==fix(ueIndex), ...
    'sixgr:truth:InvalidPacketTransportOwner','Require a direction and stable logical UE owner.');
assert(isequal(double(sixgr.util.structGet(grant,'UEIndex',NaN)),double(ueIndex)), ...
    'sixgr:truth:PacketTransportOwnerMismatch','The received grant must retain its logical UE owner.');
tbId=sixgr.truth.resolveGrantTransportBlockIdentity(grant);
assert(istable(T) && all(ismember({'Direction','UEIndex','TransportBlockId'},T.Properties.VariableNames)), ...
    'sixgr:truth:MissingPacketTransportOwner','The SDU ledger must retain its typed UE/TB binding.');
mask=upper(string(T.Direction))==direction & double(T.UEIndex)==ueIndex & ...
    string(T.TransportBlockId)==tbId;
if ~any(mask), return; end
% Historical radio identity belongs to this TB. A later RRC binding must
% neither rename it nor authorize stale feedback for a newer NDI epoch.
columns=["RNTI","ServingCell","HARQProcessId","NDI","NDIEpoch"];
paths=["RNTI","ServingCell","HARQ.HarqID","HARQ.NDI","HARQ.NDIEpoch"];
for k=1:numel(columns)
    if ~ismember(columns(k),string(T.Properties.VariableNames)), continue; end
    retained=double(T.(columns(k))(mask));
    known=isfinite(retained);
    if ~any(known), continue; end
    received=double(sixgr.util.structGet(grant,paths(k),NaN));
    assert(isscalar(received) && isfinite(received) && all(retained(known)==received), ...
        'sixgr:truth:PacketTransportIdentityMismatch', ...
        'Received %s disagrees with the original packet/TB binding.',columns(k));
end
end
