function extracted = extractSRSResources(rx, srsCfg)
%EXTRACTSRSRESOURCES Extract configured SRS REs from received UL grids.

mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
rows = repmat(localExtractRow(), 0, 1);
obsAll = [];
refAll = [];
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
    try
        obs = grid(ind);
    catch
        idx = double(ind(:));
        idx = idx(idx >= 1 & idx <= numel(grid));
        obs(1:numel(idx)) = grid(idx);
    end
    obsAll = [obsAll; obs(:)]; %#ok<AGROW>
    refAll = [refAll; ref(:)]; %#ok<AGROW>
    for k = 1:numel(ind)
        row = localExtractRow();
        row.RunId = string(srsCfg.RunId);
        row.Slot = double(slot);
        row.ResourceId = double(srsCfg.ResourceId);
        row.LinearIndex = double(ind(k));
        row.ReferenceSymbolI = double(real(ref(k)));
        row.ReferenceSymbolQ = double(imag(ref(k)));
        row.ObservedSymbolI = double(real(obs(k)));
        row.ObservedSymbolQ = double(imag(obs(k)));
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
    "Table", T, "ExtractionAttempted", true, ...
    "ExtractionAvailable", ~isempty(obsAll) && all(finiteMask), ...
    "ObservedFiniteRECount", double(sum(finiteMask)), ...
    "ExpectedRECount", double(numel(obsAll)));
end

function row = localExtractRow()
row = struct("RunId", "", "Slot", NaN, "ResourceId", NaN, "LinearIndex", NaN, ...
    "ReferenceSymbolI", NaN, "ReferenceSymbolQ", NaN, ...
    "ObservedSymbolI", NaN, "ObservedSymbolQ", NaN, ...
    "ExtractionAttempted", false, "ExtractionAvailable", false, ...
    "ConfigHash", "", "TruthStatus", "");
end
