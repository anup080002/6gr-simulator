function [paprCP_dB, paprDFTs_dB] = sixgr_fft_papr_kernel(symGrid, cpLen)
%#codegen
% sixgr_fft_papr_kernel
% Coder-friendly FFT/IFFT kernel for UL CP-OFDM vs DFT-s-OFDM PAPR.

[nSC, nSym] = size(symGrid);
cpLen = max(0, min(round(double(cpLen)), nSC-1));

blkLen = nSC + cpLen;
wfCP = complex(zeros(blkLen*nSym,1));
wfDFTs = complex(zeros(blkLen*nSym,1));
ptr = 1;

for s = 1:nSym
    d = symGrid(:,s);

    tCP0 = ifft(d, nSC);
    tCP = complex(zeros(blkLen,1));
    if cpLen > 0
        tCP(1:cpLen) = tCP0(end-cpLen+1:end);
    end
    tCP(cpLen+1:end) = tCP0;

    dSpread = fft(d, nSC) / sqrt(nSC);
    tDFT0 = ifft(dSpread, nSC);
    tDFT = complex(zeros(blkLen,1));
    if cpLen > 0
        tDFT(1:cpLen) = tDFT0(end-cpLen+1:end);
    end
    tDFT(cpLen+1:end) = tDFT0;

    wfCP(ptr:ptr+blkLen-1) = tCP;
    wfDFTs(ptr:ptr+blkLen-1) = tDFT;
    ptr = ptr + blkLen;
end

paprCP_dB = localPAPRdB(wfCP);
paprDFTs_dB = localPAPRdB(wfDFTs);
end

function v = localPAPRdB(x)
p = abs(x(:)).^2;
v = 10*log10(max(p)/max(mean(p), eps));
end
