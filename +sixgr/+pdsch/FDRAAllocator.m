function alloc = FDRAAllocator(fdraCfg, nSizeGrid, varargin)
%FDRAAllocator Materialize truthful frequency-domain allocation decisions.

slotContext = struct("TransmissionIndex", 1);
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        slotContext.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

fdraType = lower(string(fdraCfg.FDRAType));
if fdraType == "dynamic"
    if mod(double(sixgr.util.structGet(slotContext, "TransmissionIndex", 1)), 2) == 1
        fdraType = "type0_bitmap";
    else
        fdraType = "type1_riv";
    end
end

switch fdraType
    case "type0_bitmap"
        prbSet = localBitmapToPRBSet(fdraCfg.RBBitmap, fdraCfg.GranularityRB, nSizeGrid);
        rbStart = min(prbSet);
        numRB = numel(prbSet);
        encoded = string(join(string(fdraCfg.RBBitmap(:).'), ""));
    case "type1_riv"
        [rbStart, numRB] = localDecodeRIV(double(fdraCfg.RIV), double(nSizeGrid));
        prbSet = rbStart + (0:numRB-1);
        encoded = string(fdraCfg.RIV);
    otherwise
        error("sixgr:pdsch:FDRAAllocator:BadType", ...
            "Unsupported FDRAType '%s'.", fdraType);
end

if isempty(prbSet) || min(prbSet) < 0 || max(prbSet) >= nSizeGrid
    error("sixgr:pdsch:FDRAAllocator:OutOfBounds", ...
        "Materialized PRB allocation exceeds the configured grid.");
end

alloc = struct();
alloc.FDRAType = char(fdraType);
alloc.PRBSet = double(prbSet(:).');
alloc.RBStart = double(rbStart);
alloc.NumRB = double(numRB);
alloc.BitmapOrRIV = char(encoded);
alloc.PhysicalCarrierID = double(fdraCfg.PhysicalCarrierID);
alloc.SingleCarrierOnly = logical(fdraCfg.SingleCarrierOnly);
end

function prbSet = localBitmapToPRBSet(bitmap, granularityRB, nSizeGrid)
bitmap = double(bitmap(:).');
if isempty(bitmap)
    error("sixgr:pdsch:FDRAAllocator:MissingBitmap", ...
        "type0_bitmap allocation requires RBBitmap.");
end
granularityRB = max(1, round(double(granularityRB)));
prbSet = [];
for i = 1:numel(bitmap)
    if bitmap(i) ~= 0
        rb0 = (i-1) * granularityRB;
        rb1 = min(i * granularityRB - 1, nSizeGrid - 1);
        prbSet = [prbSet, rb0:rb1]; %#ok<AGROW>
    end
end
prbSet = unique(prbSet, "stable");
end

function [rbStart, numRB] = localDecodeRIV(riv, nSizeGrid)
rbStart = NaN;
numRB = NaN;
for L = 1:nSizeGrid
    for S = 0:(nSizeGrid - L)
        if L - 1 <= floor(nSizeGrid / 2)
            cand = nSizeGrid * (L - 1) + S;
        else
            cand = nSizeGrid * (nSizeGrid - L + 1) + (nSizeGrid - 1 - S);
        end
        if cand == riv
            rbStart = S;
            numRB = L;
            return;
        end
    end
end
error("sixgr:pdsch:FDRAAllocator:BadRIV", ...
    "RIV %d could not be decoded for NSizeGrid=%d.", round(riv), round(nSizeGrid));
end

