function [deliveredDL, deliveredUL, ackDL, ackUL, nackDL, nackUL, grantDL, grantUL, ...
    retxDL, retxUL, queueDLBits, queueULBits, meanCQI] = ...
    sixgr_e2e_fast_core_kernel(offeredDL, offeredUL, slotDL, slotUL, serviceDLBits, serviceULBits, snrDL_dB, snrUL_dB)
%#codegen
% sixgr_e2e_fast_core_kernel
% Coder-friendly E2E proxy kernel for MEX acceleration.
% This is an abstraction backend (queue + CQI + logistic success), not
% per-grant waveform PHY replay.

nSlots = size(offeredDL, 1);
nUE = size(offeredDL, 2);

deliveredDL = zeros(nSlots,1);
deliveredUL = zeros(nSlots,1);
ackDL = zeros(nSlots,1);
ackUL = zeros(nSlots,1);
nackDL = zeros(nSlots,1);
nackUL = zeros(nSlots,1);
grantDL = zeros(nSlots,1);
grantUL = zeros(nSlots,1);
retxDL = zeros(nSlots,1);
retxUL = zeros(nSlots,1);
queueDLBits = zeros(nSlots,1);
queueULBits = zeros(nSlots,1);
meanCQI = zeros(nSlots,1);

qDL = zeros(nUE,1);
qUL = zeros(nUE,1);

for t = 1:nSlots
    qDL = qDL + max(0, offeredDL(t,:)).';
    qUL = qUL + max(0, offeredUL(t,:)).';

    cqiSum = 0;
    cqiCnt = 0;
    if slotDL(t)
        for u = 1:nUE
            if qDL(u) <= 0
                continue;
            end
            grantDL(t) = grantDL(t) + 1;
            txBits = min(qDL(u), serviceDLBits);
            cqi = max(1, min(15, round((snrDL_dB + 10 + 2*randn()) / 2)));
            cqiSum = cqiSum + cqi;
            cqiCnt = cqiCnt + 1;
            pSucc = localSuccProb(snrDL_dB, cqi);
            if rand < pSucc
                ackDL(t) = ackDL(t) + 1;
                deliveredDL(t) = deliveredDL(t) + txBits;
                qDL(u) = qDL(u) - txBits;
            else
                nackDL(t) = nackDL(t) + 1;
                retxDL(t) = retxDL(t) + 1;
            end
        end
    end

    if slotUL(t)
        for u = 1:nUE
            if qUL(u) <= 0
                continue;
            end
            grantUL(t) = grantUL(t) + 1;
            txBits = min(qUL(u), serviceULBits);
            cqi = max(1, min(15, round((snrUL_dB + 10 + 2*randn()) / 2)));
            cqiSum = cqiSum + cqi;
            cqiCnt = cqiCnt + 1;
            pSucc = localSuccProb(snrUL_dB, cqi);
            if rand < pSucc
                ackUL(t) = ackUL(t) + 1;
                deliveredUL(t) = deliveredUL(t) + txBits;
                qUL(u) = qUL(u) - txBits;
            else
                nackUL(t) = nackUL(t) + 1;
                retxUL(t) = retxUL(t) + 1;
            end
        end
    end

    queueDLBits(t) = sum(qDL);
    queueULBits(t) = sum(qUL);
    if cqiCnt > 0
        meanCQI(t) = cqiSum / cqiCnt;
    else
        meanCQI(t) = 0;
    end
end
end

function p = localSuccProb(snr_dB, cqi)
effSnr = snr_dB + 0.25*(double(cqi) - 10);
p = 1 / (1 + exp(-(effSnr - 2.5) * 0.38));
p = min(max(p, 0.03), 0.997);
end
