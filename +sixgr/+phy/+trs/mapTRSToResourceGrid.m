function mapped = mapTRSToResourceGrid(cfg)
%MAPTRSTORESOURCEGRID Map generated TRS REs to per-slot resource grids.

sig = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg);
resources = sig.SlotResources;
gridSlots = repmat(localGridSlot(), 0, 1);
for ii = 1:numel(resources)
    res = resources(ii);
    grid = nrResourceGrid(res.Carrier, res.Ports);
    grid(res.Indices) = res.Symbols;
    row = localGridSlot();
    row.Slot = double(res.Slot);
    row.Carrier = res.Carrier;
    row.Grid = grid;
    row.Indices = res.Indices;
    row.Symbols = res.Symbols;
    row.NRE = double(res.NRE);
    gridSlots(end+1, 1) = row; %#ok<AGROW>
end
mapped = sig;
mapped.GridSlots = gridSlots;
end

function row = localGridSlot()
row = struct("Slot", NaN, "Carrier", [], "Grid", [], "Indices", [], ...
    "Symbols", [], "NRE", NaN);
end
