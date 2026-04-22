function meta = PDSCHScrambler(cfg, carrier, pdsch)
%PDSCHScrambler Report the active PDSCH scrambling metadata.
%
% The actual scrambling is performed inside nrPDSCH in the truth path.

meta = struct();
meta.ScramblingMaterialization = "nr_pdsch_internal_truth_path";
meta.RNTI = double(pdsch.RNTI);
meta.NID = double(sixgr.util.structGet(pdsch, "NID", carrier.NCellID));
meta.SequenceInitMode = "nr_pdsch_gold_sequence_internal";
meta.CellID = double(carrier.NCellID);
meta.PayloadScramblingStatus = "materialized_inside_nrPDSCH";
end

