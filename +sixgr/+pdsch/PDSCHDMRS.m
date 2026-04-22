function [dmrs, dmrsTable] = PDSCHDMRS(carrier, pdsch)
%PDSCHDMRS Generate truthful PDSCH DMRS and export explicit RE locations.

[dmrsInd, dmrsSym, info] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch, "IndexBase", "1based");
dmrsInd = dmrsInd(:);
dmrsSym = dmrsSym(:);
numPorts = max(1, max(1, double(pdsch.NumLayers)));
[k, l, p] = ind2sub([carrier.NSizeGrid * 12, carrier.SymbolsPerSlot, numPorts], dmrsInd);
dmrsTable = table(double(l - 1), double(k - 1), double(p - 1), real(dmrsSym), imag(dmrsSym), ...
    'VariableNames', {'Symbol','Subcarrier','Port','Real','Imag'});
dmrs = struct("Indices", dmrsInd, "Symbols", dmrsSym, "Info", info);
end
