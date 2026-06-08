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

localValidatePDCCHPolarInputs(llr, payloadMeta, ctrlCfg);

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

function localValidatePDCCHPolarInputs(llr, payloadMeta, ctrlCfg)
expectedK = double(sixgr.util.structGet(ctrlCfg, "PayloadLengthBits", NaN)) + localCRCLength(ctrlCfg.CRCPolynomial);
if isfinite(expectedK) && double(payloadMeta.KWithCRC) ~= expectedK
    error("sixgr:ctrl:PDCCHDecoder:KWithCRCMismatch", ...
        "KWithCRC=%d but expected DCI payload plus CRC length=%d.", ...
        double(payloadMeta.KWithCRC), expectedK);
end
rateMatchedLength = double(sixgr.util.structGet(payloadMeta, "RateMatchedLength", numel(llr)));
if isfinite(rateMatchedLength) && rateMatchedLength ~= numel(llr)
    warning("sixgr:ctrl:PDCCHDecoder:RateMatchedLengthMismatch", ...
        "RateMatchedLength=%d but demapped LLR length is %d.", rateMatchedLength, numel(llr));
end
payloadRECount = double(sixgr.util.structGet(payloadMeta, "PayloadRECount", NaN));
if isfinite(payloadRECount)
    expectedE = payloadRECount * localBitsPerSymbol(ctrlCfg.Modulation);
    if expectedE ~= numel(llr)
        warning("sixgr:ctrl:PDCCHDecoder:EncodedLengthMismatch", ...
            "PDCCH mapped capacity E=%d but demapped LLR length is %d.", expectedE, numel(llr));
    end
end
end

function q = localBitsPerSymbol(modulation)
token = upper(regexprep(char(string(modulation)), "[^A-Z0-9/]", ""));
switch token
    case {"BPSK","PI/2BPSK","PI2BPSK"}
        q = 1;
    case "QPSK"
        q = 2;
    case "16QAM"
        q = 4;
    case "64QAM"
        q = 6;
    case "256QAM"
        q = 8;
    case "1024QAM"
        q = 10;
    case "4096QAM"
        q = 12;
    otherwise
        error("sixgr:ctrl:PDCCHDecoder:UnsupportedModulation", ...
            "Unsupported PDCCH modulation '%s'.", string(modulation));
end
end

function n = localCRCLength(poly)
token = upper(string(poly));
if contains(token, "24")
    n = 24;
elseif contains(token, "16")
    n = 16;
elseif contains(token, "11")
    n = 11;
elseif contains(token, "6")
    n = 6;
else
    n = NaN;
end
end
