function grant = finalizeHARQGrantSpatialSnapshot(grant, direction)
%FINALIZEHARQGRANTSPATIALSNAPSHOT Persist executed spatial aliases for HARQ.
% The waveform builder may reconstruct a compact grant after transmission.
% Before that snapshot enters HARQ state, synchronize every top-level layer
% alias from the executed/frozen PHY contract. This prevents a later
% scheduler template from backfilling a missing alias with rank one.

if nargin < 2
    direction = "";
end
if ~(isstruct(grant) && isscalar(grant))
    error("sixgr:link:InvalidHARQGrantSnapshot", ...
        "HARQ spatial finalization requires one grant structure.");
end

contract = sixgr.phy.grant.resolveGrantSpatialContract(grant, ...
    "Direction", direction);
nLayers = double(contract.NumLayers);
grant.NumLayers = nLayers;
grant.Layers = nLayers;
grant.TBSInputNumLayers = nLayers;

phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
    codingLayers = double(sixgr.util.structGet(phyGrant, ...
        "CodingLayout.NumLayers", NaN));
    antennaLayers = double(sixgr.util.structGet(phyGrant, ...
        "AntennaArchitecture.NumLayers", NaN));
    if ~(isfinite(codingLayers) && isfinite(antennaLayers) && ...
            codingLayers == nLayers && antennaLayers == nLayers)
        error("sixgr:link:HARQFrozenSpatialContractMismatch", ...
            "Executed %s HARQ snapshot has top-level layers=%d, but its " + ...
            "frozen coding/antenna contracts report %g/%g.", ...
            char(upper(string(direction))), round(nLayers), ...
            codingLayers, antennaLayers);
    end
end
end
