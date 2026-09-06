function out = generateTRSSymbolsAndIndices(cfg)
%GENERATETRSSYMBOLSANDINDICES Generate NZP-CSI-RS/TRS symbols and indices.

resourceSet = sixgr.phy.trs.buildNZPCSIRSResourceSetForTRS(cfg);
slots = double(resourceSet.SlotNumbers(:).');
slotResources = repmat(localSlotResource(), 0, 1);
mappingRows = repmat(localMappingRow(), 0, 1);
for ii = 1:numel(slots)
    carrier = resourceSet.Carrier;
    carrier.NSlot = mod(slots(ii),double(carrier.SlotsPerFrame));
    carrier.NFrame = mod(floor(slots(ii)/double(carrier.SlotsPerFrame)),1024);
    ind = nrCSIRSIndices(carrier, resourceSet.CSIRS);
    sym = nrCSIRS(carrier, resourceSet.CSIRS);
    K = double(carrier.NSizeGrid) * 12;
    L = double(carrier.SymbolsPerSlot);
    P = double(resourceSet.CSIRS.NumCSIRSPorts);
    [sc, symIdx, portIdx] = ind2sub([K L P], double(ind(:)));
    res = localSlotResource();
    res.Slot = double(slots(ii));
    res.Carrier = carrier;
    res.Indices = ind(:);
    res.Symbols = sym(:);
    res.K = K;
    res.L = L;
    res.Ports = P;
    res.NRE = numel(ind);
    slotResources(end+1, 1) = res; %#ok<AGROW>
    for jj = 1:numel(ind)
        row = localMappingRow();
        row.RunId = string(cfg.RunId);
        row.ConfigHash = string(cfg.ConfigHash);
        row.Slot = double(slots(ii));
        row.ResourceIndex = double(jj);
        row.LinearIndex1Based = double(ind(jj));
        row.Subcarrier0Based = double(sc(jj) - 1);
        row.Symbol0Based = double(symIdx(jj) - 1);
        row.Port0Based = double(portIdx(jj) - 1);
        row.ReferenceSignal = "TRS_NZP_CSI_RS";
        row.CSIRSRowNumber = double(resourceSet.CSIRS.RowNumber);
        row.NumCSIRSPorts = double(resourceSet.CSIRS.NumCSIRSPorts);
        row.CDMType = string(resourceSet.CSIRS.CDMType);
        row.Density = string(resourceSet.CSIRS.Density);
        row.TruthStatus = "real_lls_evidence";
        mappingRows(end+1, 1) = row; %#ok<AGROW>
    end
end

out = struct();
out.ResourceSet = resourceSet;
out.SlotResources = slotResources;
out.ResourceMappingTable = struct2table(mappingRows, "AsArray", true);
end

function row = localSlotResource()
row = struct("Slot", NaN, "Carrier", [], "Indices", [], "Symbols", [], ...
    "K", NaN, "L", NaN, "Ports", NaN, "NRE", NaN);
end

function row = localMappingRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, "ResourceIndex", NaN, ...
    "LinearIndex1Based", NaN, "Subcarrier0Based", NaN, "Symbol0Based", NaN, ...
    "Port0Based", NaN, "ReferenceSignal", "", "CSIRSRowNumber", NaN, ...
    "NumCSIRSPorts", NaN, "CDMType", "", "Density", "", "TruthStatus", "");
end
