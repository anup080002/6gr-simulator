function W = selectGrantReplayPDSCHPrecodingMatrix(grant)
%SELECTGRANTREPLAYPDSCHPRECODINGMATRIX Select only a non-frozen Tx override.
%
% A frozen PHYGrant is the complete authority: applying it to the runtime
% config restores its logical-port matrix and the PDSCH transmitter then
% expands that matrix through the frozen hybrid architecture. Passing the
% element-domain matrix again as an explicit PrecodingMatrix would treat
% physical antenna elements as logical NR ports and apply the hybrid stage
% twice.

W = [];
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    return;
end
logicalW = sixgr.util.structGet(grant, "PrecodingMatrixLogicalPorts", ...
    sixgr.util.structGet(grant, "LogicalPrecodingMatrix", []));
if isnumeric(logicalW) && ~isempty(logicalW)
    W = logicalW;
    return;
end
physicalW = sixgr.util.structGet(grant, "PrecodingMatrix", []);
if isnumeric(physicalW) && ~isempty(physicalW)
    W = physicalW;
end
end
