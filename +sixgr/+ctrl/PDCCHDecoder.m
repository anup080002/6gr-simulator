function dec = PDCCHDecoder(eqSymbols, noiseVar, payloadMeta, ctrlCfg, context)
%PDCCHDecoder Demap, descramble, decode, and CRC-check one candidate.

if nargin < 5
    context = struct();
end

[llr, demodInfo] = sixgr.phy.mod.demodulateLLR(eqSymbols(:), ctrlCfg.Modulation, max(noiseVar, eps));
scr = sixgr.ctrl.PayloadScrambler(int8(zeros(numel(llr),1)), ctrlCfg, context);
if scr.Enabled
    llr = llr .* (1 - 2 * double(scr.Sequence(:)));
end

[rateRecovered, rrInfo] = sixgr.phy.phycode.rateRecoverPolar(llr, payloadMeta.KWithCRC, payloadMeta.PolarEncodedLength, false, "NMax", 9);
[decodedBitsCRC, polarInfo] = sixgr.phy.phycode.polarDecode(rateRecovered, payloadMeta.KWithCRC, numel(llr), "DL", "ListLength", payloadMeta.ListLength);
mask = [];
if ctrlCfg.CRCScramblingEnabled
    mask = double(ctrlCfg.RNTI);
end
[decodedBits, crcOk, crcErr] = sixgr.phy.tb.checkCRC(decodedBitsCRC, ctrlCfg.CRCPolynomial, mask);

dec = struct();
dec.DecodedBits = int8(decodedBits(:));
dec.CRCPass = logical(crcOk);
dec.CRCError = double(crcErr);
dec.LLR = llr(:);
dec.DecodingMetric = mean(abs(llr));
dec.DemodInfo = demodInfo;
dec.RateRecoverInfo = rrInfo;
dec.PolarInfo = polarInfo;
end
