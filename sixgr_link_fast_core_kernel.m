function [dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, paprCP, paprDFTs, paprGain] = ...
    sixgr_link_fast_core_kernel(snrGrid_dB, numFrames, slotDur_s, bw_Hz)
%#codegen
% sixgr_link_fast_core_kernel
% Coder-friendly fast link abstraction for campaign-time BLER/BER/throughput.

n = numel(snrGrid_dB);
dlBer = zeros(n,1);
dlBler = zeros(n,1);
dlThr = zeros(n,1);
ulBer = zeros(n,1);
ulBler = zeros(n,1);
ulThr = zeros(n,1);
srsNmse = zeros(n,1);
paprCP = zeros(n,1);
paprDFTs = zeros(n,1);
paprGain = zeros(n,1);

if ~(isfinite(numFrames) && numFrames > 0)
    numFrames = 1;
end
if ~(isfinite(slotDur_s) && slotDur_s > 0)
    slotDur_s = 1e-3;
end
if ~(isfinite(bw_Hz) && bw_Hz > 0)
    bw_Hz = 20e6;
end

sampleAdj = 0.35 / sqrt(max(double(numFrames), 1.0));
simDur_s = double(numFrames) * slotDur_s;

for i = 1:n
    snr = double(snrGrid_dB(i));
    sinrLin = 10.^(snr/10);

    blerDL = localBlerModel(snr, 2.8, 0.58, sampleAdj);
    blerUL = localBlerModel(snr, 2.4, 0.56, sampleAdj * 1.05);

    seDL = min(7.4, log2(1 + 0.92 * max(sinrLin, 0)));
    seUL = min(6.9, log2(1 + 0.86 * max(sinrLin, 0)));

    bitsPerSlotDL = floor(bw_Hz * slotDur_s * max(seDL, 0) * 0.18);
    bitsPerSlotUL = floor(bw_Hz * slotDur_s * max(seUL, 0) * 0.17);
    bitsPerSlotDL = max(bitsPerSlotDL, 0);
    bitsPerSlotUL = max(bitsPerSlotUL, 0);

    goodBitsDL = (1 - blerDL) * bitsPerSlotDL * double(numFrames);
    goodBitsUL = (1 - blerUL) * bitsPerSlotUL * double(numFrames);

    berDL = blerDL * min(0.35, 0.020 + 0.18 / (1 + sinrLin));
    berUL = blerUL * min(0.38, 0.024 + 0.22 / (1 + sinrLin));

    nmseLin = 1.0 / max(1 + 0.8 * sinrLin, 1e-6);
    nmse_dB = 10 * log10(max(nmseLin, 1e-9));

    paprCp_i = 8.5 + 0.35 * exp(-max(snr, -15) / 18);
    paprDfts_i = 6.6 + 0.25 * exp(-max(snr, -15) / 20);

    dlBer(i) = min(max(berDL, 1e-6), 0.5);
    dlBler(i) = min(max(blerDL, 1e-4), 0.9999);
    dlThr(i) = (goodBitsDL / max(simDur_s, eps)) / 1e6;

    ulBer(i) = min(max(berUL, 1e-6), 0.5);
    ulBler(i) = min(max(blerUL, 1e-4), 0.9999);
    ulThr(i) = (goodBitsUL / max(simDur_s, eps)) / 1e6;

    srsNmse(i) = nmse_dB;
    paprCP(i) = paprCp_i;
    paprDFTs(i) = paprDfts_i;
    paprGain(i) = paprCp_i - paprDfts_i;
end
end

function bler = localBlerModel(snr_dB, thr_dB, slope, sampleAdj)
margin = double(snr_dB) - double(thr_dB);
bler = 1.0 / (1.0 + exp(double(slope) * margin));
bler = min(max(bler + double(sampleAdj), 1e-4), 0.9999);
end
