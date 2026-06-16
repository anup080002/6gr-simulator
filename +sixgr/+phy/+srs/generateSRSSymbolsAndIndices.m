function out = generateSRSSymbolsAndIndices(srsCfg)
%GENERATESRSSYMBOLSANDINDICES Generate real SRS symbols/indices per slot.

carrier0 = srsCfg.ToolboxCarrier;
srs = srsCfg.ToolboxSRS;
slotNumbers = double(srsCfg.ExpectedSlotSet(:).');
slotResources = repmat(struct("Slot", NaN, "Indices", [], "Symbols", [], "Info", struct()), numel(slotNumbers), 1);
rows = repmat(localResourceRow(), 0, 1);
for ii = 1:numel(slotNumbers)
    carrier = carrier0;
    carrier.NSlot = double(slotNumbers(ii));
    [ind, info] = nrSRSIndices(carrier, srs);
    sym = nrSRS(carrier, srs);
    slotResources(ii).Slot = double(slotNumbers(ii));
    slotResources(ii).Indices = ind;
    slotResources(ii).Symbols = sym;
    slotResources(ii).Info = info;
    rows = [rows; localRowsForSlot(srsCfg, carrier, srs, ind, sym)]; %#ok<AGROW>
end
if isempty(rows)
    resourceT = struct2table(repmat(localResourceRow(), 0, 1));
else
    resourceT = struct2table(rows, "AsArray", true);
end
coverage = sixgr.phy.srs.computeSRSCoverage(carrier0, srs, vertcat(slotResources.Indices), srsCfg);
out = struct();
out.SlotResources = slotResources;
out.ResourceMappingTable = resourceT;
out.Coverage = coverage;
out.ConfigHash = string(srsCfg.ConfigHash);
end

function rows = localRowsForSlot(srsCfg, carrier, srs, ind, sym)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
P = max(1, round(double(srs.NumSRSPorts)));
idx = double(ind(:));
[subcarrier, symbol, port] = ind2sub([K L P], idx);
N = numel(idx);
rows = repmat(localResourceRow(), N, 1);
for i = 1:N
    rows(i) = localResourceRow();
    rows(i).RunId = string(srsCfg.RunId);
    rows(i).CellId = double(srsCfg.CellId);
    rows(i).UEId = double(srsCfg.UEId);
    rows(i).Slot = double(carrier.NSlot);
    rows(i).Symbol = double(symbol(i) - 1);
    rows(i).Subcarrier = double(subcarrier(i) - 1);
    rows(i).PRB = double(floor((subcarrier(i) - 1) / 12));
    rows(i).Port = double(port(i) - 1);
    rows(i).ResourceId = double(srsCfg.ResourceId);
    rows(i).CombNumber = double(srs.KTC);
    rows(i).CombOffset = double(srs.KBarTC);
    rows(i).CyclicShift = double(srs.CyclicShift);
    rows(i).SequenceId = double(srs.NSRSID);
    rows(i).LinearIndex = double(idx(i));
    if i <= numel(sym)
        rows(i).SymbolHashInputReal = double(real(sym(i)));
        rows(i).SymbolHashInputImag = double(imag(sym(i)));
    end
    rows(i).ConfigHash = string(srsCfg.ConfigHash);
    rows(i).TruthStatus = "real_lls_evidence";
end
end

function row = localResourceRow()
row = struct("RunId", "", "CellId", NaN, "UEId", NaN, "Slot", NaN, ...
    "Symbol", NaN, "Subcarrier", NaN, "PRB", NaN, "Port", NaN, ...
    "ResourceId", NaN, "CombNumber", NaN, "CombOffset", NaN, ...
    "CyclicShift", NaN, "SequenceId", NaN, "LinearIndex", NaN, ...
    "SymbolHashInputReal", NaN, "SymbolHashInputImag", NaN, ...
    "ConfigHash", "", "TruthStatus", "");
end
