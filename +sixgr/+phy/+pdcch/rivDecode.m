function [prbStart, numPRB, valid] = rivDecode(riv, nSizeGrid)
%RIVDECODE Decode NR resource-indication value to contiguous PRB allocation.

riv = double(riv);
nSizeGrid = double(nSizeGrid);
if ~(isscalar(nSizeGrid) && isfinite(nSizeGrid) && nSizeGrid >= 1)
    error("sixgr:phy:pdcch:InvalidNSizeGrid", "NSizeGrid must be a positive scalar.");
end
prbStart = NaN;
numPRB = NaN;
valid = false;
if ~(isscalar(riv) && isfinite(riv) && riv >= 0)
    return;
end
for L = 1:round(nSizeGrid)
    for S = 0:(round(nSizeGrid) - L)
        cand = sixgr.phy.pdcch.rivEncode(S, L, nSizeGrid);
        if cand == round(riv)
            prbStart = double(S);
            numPRB = double(L);
            valid = true;
            return;
        end
    end
end
end
