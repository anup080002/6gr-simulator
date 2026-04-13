function upperBoundBits = grantTBSUpperBoundBits(grant)
%GRANTTBSUPPERBOUNDBITS Loose physical upper bound for a grant TBS.
%
% This bound intentionally ignores DM-RS and coding overhead so exporters
% can reject impossible grant-level TBS values without rejecting valid ones.

arguments
    grant (1,1) struct
end

nPRB = localPRBCount(grant);
nSym = localNumSymbols(grant);
nLayers = max(1, round(double(sixgr.util.structGet(grant, "NumLayers", 1))));
qm = localModOrder(grant);

if ~(isfinite(nPRB) && nPRB > 0 && isfinite(nSym) && nSym > 0 && ...
        isfinite(nLayers) && nLayers > 0 && isfinite(qm) && qm > 0)
    upperBoundBits = NaN;
    return;
end

upperBoundBits = 8 * ceil((double(nPRB) * 12 * double(nSym) * double(qm) * double(nLayers)) / 8);
end

function nPRB = localPRBCount(grant)
prbSet = sixgr.util.structGet(grant, "PRBSet", []);
if ~isempty(prbSet)
    prbSet = unique(round(double(prbSet(:))));
    nPRB = numel(prbSet);
    return;
end

for name = ["PRBCount", "NumPRB", "NPRB"]
    v = double(sixgr.util.structGet(grant, name, NaN));
    if isfinite(v) && v > 0
        nPRB = round(v);
        return;
    end
end

nPRB = NaN;
end

function nSym = localNumSymbols(grant)
symAlloc = sixgr.util.structGet(grant, "SymbolAllocation", []);
if ~isempty(symAlloc)
    symAlloc = round(double(symAlloc(:).'));
    if numel(symAlloc) >= 2 && isfinite(symAlloc(2)) && symAlloc(2) > 0
        nSym = symAlloc(2);
        return;
    end
end

nSym = double(sixgr.util.structGet(grant, "NumSymbols", 14));
if ~(isfinite(nSym) && nSym > 0)
    nSym = NaN;
else
    nSym = round(nSym);
end
end

function qm = localModOrder(grant)
modStr = upper(string(sixgr.util.structGet(grant, "Modulation", "")));
switch char(modStr)
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    otherwise
        mcs = double(sixgr.util.structGet(grant, "MCSIndex", NaN));
        cqi = double(sixgr.util.structGet(grant, "CQIUsed", NaN));
        if isfinite(mcs)
            if mcs >= 20
                qm = 8;
            elseif mcs >= 10
                qm = 6;
            elseif mcs >= 5
                qm = 4;
            else
                qm = 2;
            end
        elseif isfinite(cqi)
            if cqi >= 11
                qm = 8;
            elseif cqi >= 7
                qm = 6;
            elseif cqi >= 4
                qm = 4;
            else
                qm = 2;
            end
        else
            qm = 8;
        end
end
end
