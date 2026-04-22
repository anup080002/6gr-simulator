function out = PDCCHGridMapper(ctrlCfg, candidateResources, txSymbols, dmrs, varargin)
%PDCCHGridMapper Map payload, DMRS, and optional repetitions onto slot grids.

opts = struct("NumSlots", ctrlCfg.NSlotGrid);
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

numSlots = max(1, round(double(opts.NumSlots)));
nSC = ctrlCfg.NSizeGrid * 12;
grid = complex(zeros(nSC, 14, ctrlCfg.NTx, numSlots));

payloadT = candidateResources.RETable(dmrs.PayloadREMask, :);
if numel(txSymbols) ~= height(payloadT)
    error("sixgr:ctrl:PDCCHGridMapper:PayloadLengthMismatch", ...
        "Payload symbol count %d does not match payload RE count %d.", numel(txSymbols), height(payloadT));
end

for i = 1:height(payloadT)
    slotIdx = max(1, min(numSlots, round(double(payloadT.SlotIndex(i)))));
    grid(payloadT.Subcarrier(i)+1, payloadT.Symbol(i)+1, 1, slotIdx) = txSymbols(i);
end
for i = 1:height(dmrs.Locations)
    slotIdx = max(1, min(numSlots, round(double(dmrs.Locations.SlotIndex(i)))));
    grid(dmrs.Locations.Subcarrier(i)+1, dmrs.Locations.Symbol(i)+1, 1, slotIdx) = dmrs.Symbols(i);
end

out = struct();
out.Grid = grid;
out.PayloadLocations = payloadT;
out.DMRSLocations = dmrs.Locations;
out.NumSlots = numSlots;
end
