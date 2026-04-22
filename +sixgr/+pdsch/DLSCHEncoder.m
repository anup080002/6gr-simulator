function encode = DLSCHEncoder(tx, txInfo)
%DLSCHEncoder Summarize truthful DL-SCH encoder evidence.

encode = struct();
encode.TransportBlockSize = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
encode.BaseGraph = double(sixgr.util.structGet(tx, "BaseGraph", NaN));
encode.RateMatchedBits = double(sixgr.util.structGet(tx, "G", NaN));
encode.NumCodeBlocks = double(sixgr.util.structGet(txInfo, "Segmentation.nCB", NaN));
encode.Source = "pdsch_tx_dlsch_encode_truth_path";
end

