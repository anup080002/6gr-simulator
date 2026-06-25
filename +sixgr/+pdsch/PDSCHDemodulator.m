function demod = PDSCHDemodulator(rx)
%PDSCHDemodulator Package demodulation evidence from the truthful receiver.

llr = sixgr.util.structGet(rx, "CodewordLLRCell", []);
if isempty(llr)
    llr = sixgr.util.structGet(rx, "CodewordLLR", []);
end
demod = struct();
if iscell(llr)
    demod.LLRCount = double(sum(cellfun(@numel, llr)));
    demod.LLRCountPerCodeword = double(cellfun(@numel, llr));
else
    demod.LLRCount = double(numel(llr));
    demod.LLRCountPerCodeword = double(numel(llr));
end
demod.EqualizedSymbolCount = double(numel(sixgr.util.structGet(rx, "EqualizedSymbolsForEvidence", [])));
demod.Source = "nrPDSCHDecode_truth_path";
end
