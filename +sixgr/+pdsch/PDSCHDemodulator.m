function demod = PDSCHDemodulator(rx)
%PDSCHDemodulator Package demodulation evidence from the truthful receiver.

llr = sixgr.util.structGet(rx, "CodewordLLR", []);
demod = struct();
demod.LLRCount = double(numel(llr));
demod.EqualizedSymbolCount = double(numel(sixgr.util.structGet(rx, "EqualizedSymbolsForEvidence", [])));
demod.Source = "nrPDSCHDecode_truth_path";
end

