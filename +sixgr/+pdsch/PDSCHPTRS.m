function [ptrs, ptrsTable] = PDSCHPTRS(carrier, pdsch)
%PDSCHPTRS Generate truthful PDSCH PTRS mapping metadata.

[ptrsInd, ptrsSym, info] = sixgr.phy.refsig.ptrsPDSCH(carrier, pdsch, "IndexBase", "1based");
if isempty(ptrsInd)
    ptrsTable = table();
else
    ptrsInd = ptrsInd(:);
    ptrsSym = ptrsSym(:);
    numPorts = max([1, size(ptrsInd, 2), double(pdsch.NumLayers)]);
    [k, l, p] = ind2sub([carrier.NSizeGrid * 12, carrier.SymbolsPerSlot, numPorts], ptrsInd);
    ptrsTable = table(double(l - 1), double(k - 1), double(p - 1), real(ptrsSym), imag(ptrsSym), ...
        'VariableNames', {'Symbol','Subcarrier','Port','Real','Imag'});
end
ptrs = struct("Indices", ptrsInd, "Symbols", ptrsSym, "Info", info);
end
