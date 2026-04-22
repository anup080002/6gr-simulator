function meta = PDSCHModulator(tx)
%PDSCHModulator Report actual constellation materialization metadata.

meta = struct();
meta.Modulation = char(string(sixgr.util.structGet(tx, "PDSCH.Modulation", "")));
meta.NumLayers = double(sixgr.util.structGet(tx, "PDSCH.NumLayers", NaN));
meta.SymbolCount = double(numel(sixgr.util.structGet(tx, "PDSCHSymbolsForEvidence", [])));
meta.ModulationStatus = "materialized_in_nrPDSCH";
end

