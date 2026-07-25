function alloc = FDRAAllocator(fdraCfg, nSizeGrid, varargin)
%FDRAAllocator Materialize truthful frequency-domain allocation decisions.

slotContext = struct( ...
    "ExecutionProfile", "study_calibration", ...
    "DecodedFDRAType", "");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        slotContext.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if ~isfield(fdraCfg, "FDRAType") || strlength(strtrim(string(fdraCfg.FDRAType))) == 0
    error("sixgr:pdsch:MissingFDRAType", ...
        "PDSCH frequency-domain allocation requires a decoded FDRA type.");
end
fdraType = lower(string(fdraCfg.FDRAType));
if fdraType == "dynamic"
    decodedType = lower(strtrim(string(sixgr.util.structGet( ...
        slotContext, "DecodedFDRAType", ""))));
    if ~any(decodedType == ["type0_bitmap","type1_riv"])
        error("sixgr:pdsch:MissingDecodedFDRAType", ...
            "Dynamic FDRA requires the allocation type decoded from DCI; transmission parity is not scheduling evidence.");
    end
    fdraType = decodedType;
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
        error("sixgr:pdsch:InvalidFDRAType", ...
            "Unsupported FDRAType '%s'.", fdraType);
end

if isempty(prbSet) || min(prbSet) < 0 || max(prbSet) >= nSizeGrid
    error("sixgr:pdsch:ResourceOutsideBWP", ...
        "Materialized PRB allocation exceeds the configured grid.");
end

alloc = struct();
alloc.FDRAType = char(fdraType);
alloc.PRBSet = double(prbSet(:).');
alloc.RBStart = double(rbStart);
alloc.NumRB = double(numRB);
alloc.BitmapOrRIV = char(encoded);
alloc.PhysicalCarrierID = double(sixgr.util.structGet(fdraCfg, "PhysicalCarrierID", 0));
alloc.SingleCarrierOnly = logical(sixgr.util.structGet(fdraCfg, "SingleCarrierOnly", true));
end

function prbSet = localBitmapToPRBSet(bitmap, granularityRB, nSizeGrid)
bitmap = double(bitmap(:).');
if isempty(bitmap)
    error("sixgr:pdsch:InvalidRBGField", ...
        "type0_bitmap allocation requires RBBitmap.");
end
if any(~isfinite(bitmap)) || any(bitmap ~= fix(bitmap)) || any(~ismember(bitmap, [0 1]))
    error("sixgr:pdsch:InvalidRBGField", ...
        "RBBitmap must contain only decoded binary values.");
end
granularityRB = double(granularityRB);
if ~isscalar(granularityRB) || ~isfinite(granularityRB) || ...
        granularityRB ~= fix(granularityRB) || granularityRB < 1
    error("sixgr:pdsch:InvalidRBGSize", ...
        "RBG granularity must be a positive integer.");
end
nSizeGrid = double(nSizeGrid);
if ~isscalar(nSizeGrid) || ~isfinite(nSizeGrid) || ...
        nSizeGrid ~= fix(nSizeGrid) || nSizeGrid < 1
    error("sixgr:pdsch:NPRBOutOfRange", ...
        "NSizeGrid must be a positive integer.");
end
if numel(bitmap) ~= ceil(nSizeGrid / granularityRB)
    error("sixgr:pdsch:InvalidRBGField", ...
        "RBBitmap length %d does not match the required %d RBGs.", ...
        numel(bitmap), ceil(nSizeGrid / granularityRB));
end
prbSet = [];
for i = 1:numel(bitmap)
    if bitmap(i) ~= 0
        rb0 = (i-1) * granularityRB;
        rb1 = min(i * granularityRB - 1, nSizeGrid - 1);
        prbSet = [prbSet, rb0:rb1]; %#ok<AGROW>
    end
end
if isempty(prbSet)
    error("sixgr:pdsch:ScheduledResourceUnavailable", ...
        "Decoded RBG bitmap schedules no PDSCH PRBs.");
end
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
error("sixgr:pdsch:InvalidRIV", ...
    "RIV %d could not be decoded for NSizeGrid=%d.", round(riv), round(nSizeGrid));
end

