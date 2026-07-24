function xOverhead = resolvePDSCHXOverhead(cfg, symAlloc)
%RESOLVEPDSCHXOVERHEAD Resolve TS 38.214 PDSCH N_oh from active RS overlap.
%
% Explicit phy.pdsch.xOverhead remains authoritative. If it is absent, infer
% overhead from configured SSB and CSI-RS symbols that overlap the PDSCH time
% allocation: 0, 6, 12, or 18 RE/PRB.

if nargin < 2 || isempty(symAlloc)
    symAlloc = sixgr.util.structGet(cfg, "phy.pdsch.symbolAllocation", []);
end
if isempty(symAlloc)
    error("sixgr:phy:dl:MissingPDSCHSymbolAllocation", ...
        "PDSCH XOverhead resolution requires an explicit SymbolAllocation.");
end

[xOverhead, explicit] = localFirstFiniteScalarWithPresence( ...
    sixgr.util.structGet(cfg, "phy.pdsch.xOverhead", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.XOverhead", []));
if explicit
    xOverhead = max(0, round(double(xOverhead)));
    return;
end

pdschSymbols = localAllocationSymbols(symAlloc);
overlapSymbols = [];
if localBooleanPath(cfg, ["phy.ssb.enable","phy.ssb.Enabled","phy.ssb.Enable"])
    overlapSymbols = [overlapSymbols intersect(pdschSymbols, localResolveSSBSymbols(cfg))]; %#ok<AGROW>
end
if localBooleanPath(cfg, ["phy.csirs.enable","phy.csirs.enabled","phy.csirs.Enable"])
    overlapSymbols = [overlapSymbols intersect(pdschSymbols, localResolveCSIRSSymbols(cfg))]; %#ok<AGROW>
end

nOverlap = numel(unique(overlapSymbols));
if nOverlap <= 0
    xOverhead = 0;
elseif nOverlap == 1
    xOverhead = 6;
elseif nOverlap == 2
    xOverhead = 12;
else
    xOverhead = 18;
end
end

function symbols = localAllocationSymbols(symAlloc)
symAlloc = double(symAlloc(:).');
if numel(symAlloc) ~= 2 || any(~isfinite(symAlloc)) || ...
        any(symAlloc ~= fix(symAlloc)) || symAlloc(1) < 0 || ...
        symAlloc(2) < 1 || sum(symAlloc) > 14
    error("sixgr:phy:dl:InvalidPDSCHSymbolAllocation", ...
        "PDSCH SymbolAllocation must be integer [start,count] within a 14-symbol slot.");
end
startSym = round(symAlloc(1));
nSym = round(symAlloc(2));
symbols = startSym:(startSym + nSym - 1);
symbols = symbols(symbols >= 0 & symbols < 14);
end

function symbols = localResolveSSBSymbols(cfg)
symbols = double(sixgr.util.structGet(cfg, "phy.ssb.symbolLocations", []));
if isempty(symbols)
    symbols = double(sixgr.util.structGet(cfg, "phy.ssb.SymbolLocations", []));
end
if isempty(symbols)
    symbols = 0:3;
end
symbols = unique(round(double(symbols(:).')));
symbols = symbols(symbols >= 0 & symbols < 14);
end

function symbols = localResolveCSIRSSymbols(cfg)
symbols = double(sixgr.util.structGet(cfg, "phy.csirs.symbolLocations", []));
if isempty(symbols)
    symbols = double(sixgr.util.structGet(cfg, "phy.csirs.SymbolLocations", []));
end
if isempty(symbols)
    row = double(sixgr.util.structGet(cfg, "phy.csirs.rowNumber", 1));
    if any(round(row) == [13 14 16 17])
        symbols = [0 2];
    else
        symbols = 0;
    end
end
symbols = unique(round(double(symbols(:).')));
symbols = symbols(symbols >= 0 & symbols < 14);
end

function tf = localBooleanPath(cfg, paths)
tf = false;
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(raw)
        continue;
    end
    try
        tf = logical(raw);
    catch
        tf = false;
    end
    return;
end
end

function [value, found] = localFirstFiniteScalarWithPresence(varargin)
value = NaN;
found = false;
for i = 1:numel(varargin)
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    try
        v = double(raw);
    catch
        continue;
    end
    v = v(isfinite(v));
    if ~isempty(v)
        value = v(1);
        found = true;
        return;
    end
end
end
