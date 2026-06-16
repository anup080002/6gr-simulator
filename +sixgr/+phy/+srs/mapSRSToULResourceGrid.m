function grids = mapSRSToULResourceGrid(srsCfg)
%MAPSRSTOULRESOURCEGRID Map generated SRS onto UL resource grids.

mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
slots = mapping.SlotResources;
P = max(1, round(double(srsCfg.NumSRSPorts)));
grids = repmat(struct("Slot", NaN, "Grid", [], "Indices", [], "Symbols", []), numel(slots), 1);
for ii = 1:numel(slots)
    carrier = srsCfg.ToolboxCarrier;
    carrier.NSlot = double(slots(ii).Slot);
    try
        grid = nrResourceGrid(carrier, P);
    catch
        grid = complex(zeros(double(carrier.NSizeGrid) * 12, double(carrier.SymbolsPerSlot), P));
    end
    grid(slots(ii).Indices) = slots(ii).Symbols;
    grids(ii).Slot = double(slots(ii).Slot);
    grids(ii).Grid = grid;
    grids(ii).Indices = slots(ii).Indices;
    grids(ii).Symbols = slots(ii).Symbols;
end
end
