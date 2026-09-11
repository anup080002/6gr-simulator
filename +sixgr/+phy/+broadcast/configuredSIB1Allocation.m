function [pdsch, dci] = configuredSIB1Allocation(carrier, cfg)
%CONFIGUREDSIB1ALLOCATION Shared configured allocation for TX and scheduling.
% This is not a measured transmission or a decoded UE grant.
allocation = sixgr.util.structGet(cfg, ...
    "initial_access.sib1.pdsch", sixgr.util.structGet(cfg, ...
    "phy.sib1.pdsch", struct()));
required = ["prb_start","num_prb","symbol_start","num_symbols","mcs","rv"];
if ~(isstruct(allocation) && isscalar(allocation))
    error("sixgr:phy:broadcast:MissingSIB1Allocation", ...
        "Strict SIB1 generation requires initial_access.sib1.pdsch.");
end
for ii = 1:numel(required)
    if ~isfield(allocation, required(ii)) || isempty(allocation.(required(ii)))
        error("sixgr:phy:broadcast:MissingSIB1Allocation", ...
            "Strict SIB1 allocation is missing %s.", required(ii));
    end
end
prbStart = localNonnegativeInteger(allocation.prb_start, "prb_start");
nRB = localPositiveInteger(allocation.num_prb, "num_prb");
symbolStart = localNonnegativeInteger( ...
    allocation.symbol_start, "symbol_start");
numSymbols = localPositiveInteger( ...
    allocation.num_symbols, "num_symbols");
mcs = localNonnegativeInteger(allocation.mcs, "mcs");
rv = localNonnegativeInteger(allocation.rv, "rv");
if prbStart + nRB > double(carrier.NSizeGrid)
    error("sixgr:phy:broadcast:SIB1AllocationOutsideBWP", ...
        "Configured SIB1 PRB interval [%d,%d) exceeds NSizeGrid=%d.", ...
        prbStart, prbStart + nRB, double(carrier.NSizeGrid));
end
[dci, pdsch] = sixgr.phy.broadcast.buildSIB1DCI10(carrier, cfg, ...
    "PRBStart", prbStart, "PRBCount", nRB, ...
    "SymbolStart", symbolStart, "NumSymbols", numSymbols, ...
    "MCSIndex", mcs, "RV", rv);
end

function value = localNonnegativeInteger(raw, fieldName)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= 0)
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a nonnegative integer.", fieldName);
end
end

function value = localPositiveInteger(raw, fieldName)
value = localNonnegativeInteger(raw, fieldName);
if value < 1
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a positive integer.", fieldName);
end
end
