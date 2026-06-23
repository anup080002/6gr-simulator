function riv = rivEncode(prbStart, numPRB, nSizeGrid)
%RIVENCODE Encode contiguous PRB allocation to NR resource-indication value.

prbStart = double(prbStart);
numPRB = double(numPRB);
nSizeGrid = double(nSizeGrid);
if ~(isscalar(nSizeGrid) && isfinite(nSizeGrid) && nSizeGrid >= 1)
    error("sixgr:phy:pdcch:InvalidNSizeGrid", "NSizeGrid must be a positive scalar.");
end
if ~(isscalar(prbStart) && isfinite(prbStart) && prbStart >= 0 && prbStart < nSizeGrid)
    error("sixgr:phy:pdcch:InvalidPRBStart", "PRB start is outside the carrier BWP.");
end
if ~(isscalar(numPRB) && isfinite(numPRB) && numPRB >= 1 && prbStart + numPRB <= nSizeGrid)
    error("sixgr:phy:pdcch:InvalidPRBLength", "PRB allocation length is outside the carrier BWP.");
end
L = round(numPRB);
S = round(prbStart);
if (L - 1) <= floor(nSizeGrid / 2)
    riv = nSizeGrid * (L - 1) + S;
else
    riv = nSizeGrid * (nSizeGrid - L + 1) + (nSizeGrid - 1 - S);
end
riv = double(riv);
end
