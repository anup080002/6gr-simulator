function encode = DLSCHEncoder(tx, txInfo)
%DLSCHEncoder Summarize truthful DL-SCH encoder evidence.

encode = struct();
transportBlockSize = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
encode.TransportBlockSize = double(sum(transportBlockSize(:), "omitnan"));
encode.TransportBlockSizePerCodeword = double(transportBlockSize(:).');
encode.BaseGraph = double(sixgr.util.structGet(tx, "BaseGraph", NaN));
encode.RateMatchedBits = double(sixgr.util.structGet(tx, "G", NaN));
encode.RateMatchedBitsPerCodeword = double(sixgr.util.structGet(tx, "GPerCodeword", encode.RateMatchedBits));
encode.NumCodeBlocks = double(sixgr.util.structGet(txInfo, "Segmentation.nCB", NaN));
encode.NumCodewords = double(sixgr.util.structGet(tx, "NumCodewords", numel(encode.TransportBlockSizePerCodeword)));
encode.Source = "pdsch_tx_dlsch_encode_truth_path";
end
