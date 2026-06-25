function extracted = extractSRSResources(rx, srsCfg)
%EXTRACTSRSRESOURCES Extract configured SRS REs from received UL grids.

mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
rows = repmat(localExtractRow(), 0, 1);
obsAll = [];
refAll = [];
truthAll = [];
appliedGain = sixgr.util.structGet(rx, "AppliedChannelGain", complex(1, 0));
for ii = 1:numel(mapping.SlotResources)
    slot = mapping.SlotResources(ii).Slot;
    rxIdx = find([rx.RxSlots.Slot] == slot, 1, "first");
    if isempty(rxIdx)
        continue;
    end
    ind = mapping.SlotResources(ii).Indices;
    ref = mapping.SlotResources(ii).Symbols;
    grid = rx.RxSlots(rxIdx).RxGrid;
    obs = complex(NaN(size(ref)));
    [subcarrier, symbol, port] = localIndexCoordinates(ind, srsCfg, grid);
    try
        obs = grid(ind);
    catch
        idx = double(ind(:));
        idx = idx(idx >= 1 & idx <= numel(grid));
        obs(1:numel(idx)) = grid(idx);
    end
    obsAll = [obsAll; obs(:)]; %#ok<AGROW>
    refAll = [refAll; ref(:)]; %#ok<AGROW>
    truthAll = [truthAll; repmat(appliedGain, numel(ref), 1)]; %#ok<AGROW>
    for k = 1:numel(ind)
        row = localExtractRow();
        row.RunId = string(srsCfg.RunId);
        row.Slot = double(slot);
        row.ResourceId = double(srsCfg.ResourceId);
        row.LinearIndex = double(ind(k));
        if k <= numel(symbol)
            row.Symbol = double(symbol(k));
        end
        if k <= numel(subcarrier)
            row.Subcarrier = double(subcarrier(k));
            row.PRB = double(floor(subcarrier(k) / 12));
        end
        if k <= numel(port)
            row.Port = double(port(k));
        end
        row.CombNumber = double(srsCfg.CombNumber);
        row.CombOffset = double(srsCfg.CombOffset);
        row.CyclicShift = double(srsCfg.CyclicShift);
        row.SequenceId = double(srsCfg.SequenceId);
        row.ReferenceSymbolI = double(real(ref(k)));
        row.ReferenceSymbolQ = double(imag(ref(k)));
        row.ObservedSymbolI = double(real(obs(k)));
        row.ObservedSymbolQ = double(imag(obs(k)));
        row.AppliedChannelGainI = double(real(appliedGain));
        row.AppliedChannelGainQ = double(imag(appliedGain));
        row.ExtractionAttempted = true;
        row.ExtractionAvailable = isfinite(real(obs(k))) && isfinite(imag(obs(k)));
        row.ConfigHash = string(srsCfg.ConfigHash);
        row.TruthStatus = "real_lls_evidence";
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
if isempty(rows)
    T = struct2table(repmat(localExtractRow(), 0, 1));
else
    T = struct2table(rows, "AsArray", true);
end
finiteMask = isfinite(real(obsAll)) & isfinite(imag(obsAll));
extracted = struct("ObservedSymbols", obsAll, "ReferenceSymbols", refAll, ...
    "AppliedChannelGains", truthAll, ...
    "Table", T, "ExtractionAttempted", true, ...
    "ExtractionAvailable", ~isempty(obsAll) && all(finiteMask), ...
    "ObservedFiniteRECount", double(sum(finiteMask)), ...
    "ExpectedRECount", double(numel(obsAll)));
end

function row = localExtractRow()
row = struct("RunId", "", "Slot", NaN, "ResourceId", NaN, "LinearIndex", NaN, ...
    "Symbol", NaN, "Subcarrier", NaN, "PRB", NaN, "Port", NaN, ...
    "CombNumber", NaN, "CombOffset", NaN, "CyclicShift", NaN, "SequenceId", NaN, ...
    "ReferenceSymbolI", NaN, "ReferenceSymbolQ", NaN, ...
    "ObservedSymbolI", NaN, "ObservedSymbolQ", NaN, ...
    "AppliedChannelGainI", NaN, "AppliedChannelGainQ", NaN, ...
    "ExtractionAttempted", false, "ExtractionAvailable", false, ...
    "ConfigHash", "", "TruthStatus", "");
end

function [subcarrier, symbol, port] = localIndexCoordinates(ind, srsCfg, grid)
idx = double(ind(:));
K = double(srsCfg.ToolboxCarrier.NSizeGrid) * 12;
L = double(srsCfg.ToolboxCarrier.SymbolsPerSlot);
P = max(1, round(double(srsCfg.NumSRSPorts)));
if ~isempty(grid) && ndims(grid) >= 3
    P = max(P, size(grid, 3));
end
subcarrier = NaN(size(idx));
symbol = NaN(size(idx));
port = NaN(size(idx));
if isempty(idx) || ~(isfinite(K) && K > 0 && isfinite(L) && L > 0)
    return;
end
try
    [k, l, p] = ind2sub([K L P], idx);
    subcarrier = double(k(:) - 1);
    symbol = double(l(:) - 1);
    port = double(p(:) - 1);
catch
end
end
