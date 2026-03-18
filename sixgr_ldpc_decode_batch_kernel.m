function [decCB, decLen, actNumIter, parityHead] = sixgr_ldpc_decode_batch_kernel(recLLR, bgn, maxNumIter, useNormMinSum)
%#codegen
% sixgr_ldpc_decode_batch_kernel
% Coder-friendly LDPC batch decode kernel for code-block matrices.

N = size(recLLR,1);
C = size(recLLR,2);

decCB = zeros(N, C, 'int8');
decLen = zeros(C, 1);
actNumIter = zeros(C, 1);
parityHead = zeros(C, 1);

for c = 1:C
    llr = recLLR(:,c);
    if useNormMinSum ~= 0
        [d, it, pc] = nrLDPCDecode(llr, bgn, maxNumIter, 'Algorithm', 'Normalized min-sum');
    else
        [d, it, pc] = nrLDPCDecode(llr, bgn, maxNumIter);
    end

    d = d(:);
    L = min(numel(d), N);
    if L > 0
        decCB(1:L, c) = int8(d(1:L));
    end
    decLen(c) = L;

    if isempty(it)
        actNumIter(c) = 0;
    else
        actNumIter(c) = it(1);
    end

    if isempty(pc)
        parityHead(c) = 0;
    else
        parityHead(c) = pc(1);
    end
end
end
