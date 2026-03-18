function [servedDL, servedUL, droppedDL, droppedUL, activeUECount, schedDL, schedUL, meanQueueBits, meanSINR_dB] = ...
    sixgr_system_fast_core_kernel(offeredDL, offeredUL, sinrDL, sinrUL, tti_s, bw_Hz, qMaxBits, schedulerMode)
%#codegen
% sixgr_system_fast_core_kernel
% Coder-friendly system-level proxy kernel for MEX acceleration.
% This is an abstraction backend (Shannon/logistic queue service), not
% waveform-level PHY decoding.

nTTI = size(offeredDL, 1);
nUE = size(offeredDL, 2);

servedDL = zeros(nTTI,1);
servedUL = zeros(nTTI,1);
droppedDL = zeros(nTTI,1);
droppedUL = zeros(nTTI,1);
activeUECount = zeros(nTTI,1);
schedDL = zeros(nTTI,1);
schedUL = zeros(nTTI,1);
meanQueueBits = zeros(nTTI,1);
meanSINR_dB = zeros(nTTI,1);

queueDL = zeros(nUE,1);
queueUL = zeros(nUE,1);
avgRateDL = ones(nUE,1);
avgRateUL = ones(nUE,1);
rrPtrDL = 1;
rrPtrUL = 1;

for t = 1:nTTI
    queueDL = queueDL + max(0, offeredDL(t,:)).';
    queueUL = queueUL + max(0, offeredUL(t,:)).';

    activeUECount(t) = sum((queueDL + queueUL) > 0);
    meanSINR_dB(t) = 0.5 * (mean(sinrDL(t,:)) + mean(sinrUL(t,:)));

    activeDL = find(queueDL > 0);
    if ~isempty(activeDL)
        [sel, rrPtrDL] = localSelectUE(activeDL, schedulerMode, sinrDL(t,:).', avgRateDL, bw_Hz, tti_s, rrPtrDL);
        if sel > 0
            schedDL(t) = sel;
            allocBits = localCapacityBits(sinrDL(t,sel), bw_Hz, tti_s);
            pSucc = localSuccProb(sinrDL(t,sel));
            if rand < pSucc
                tx = min(queueDL(sel), allocBits);
                queueDL(sel) = queueDL(sel) - tx;
                servedDL(t) = tx;
                avgRateDL(sel) = 0.9*avgRateDL(sel) + 0.1*(tx / max(tti_s, eps));
            else
                avgRateDL(sel) = 0.9*avgRateDL(sel);
            end
        end
    end

    activeUL = find(queueUL > 0);
    if ~isempty(activeUL)
        [sel, rrPtrUL] = localSelectUE(activeUL, schedulerMode, sinrUL(t,:).', avgRateUL, bw_Hz, tti_s, rrPtrUL);
        if sel > 0
            schedUL(t) = sel;
            allocBits = localCapacityBits(sinrUL(t,sel), bw_Hz, tti_s);
            pSucc = localSuccProb(sinrUL(t,sel));
            if rand < pSucc
                tx = min(queueUL(sel), allocBits);
                queueUL(sel) = queueUL(sel) - tx;
                servedUL(t) = tx;
                avgRateUL(sel) = 0.9*avgRateUL(sel) + 0.1*(tx / max(tti_s, eps));
            else
                avgRateUL(sel) = 0.9*avgRateUL(sel);
            end
        end
    end

    ovDL = max(queueDL - qMaxBits, 0);
    ovUL = max(queueUL - qMaxBits, 0);
    if any(ovDL > 0)
        droppedDL(t) = sum(ovDL);
        queueDL = min(queueDL, qMaxBits);
    end
    if any(ovUL > 0)
        droppedUL(t) = sum(ovUL);
        queueUL = min(queueUL, qMaxBits);
    end

    meanQueueBits(t) = mean(queueDL + queueUL);
end
end

function [sel, rrPtr] = localSelectUE(activeUE, schedulerMode, sinrVec, avgRateVec, bw_Hz, tti_s, rrPtr)
sel = 0;
if isempty(activeUE)
    return;
end

if schedulerMode == 1
    inst = zeros(numel(activeUE),1);
    for i = 1:numel(activeUE)
        u = activeUE(i);
        inst(i) = localCapacityBits(sinrVec(u), bw_Hz, tti_s);
    end
    metric = inst ./ max(avgRateVec(activeUE) * tti_s, 1);
    [~, j] = max(metric);
    sel = activeUE(j);
else
    if rrPtr > numel(activeUE)
        rrPtr = 1;
    end
    sel = activeUE(rrPtr);
    rrPtr = rrPtr + 1;
end
end

function bits = localCapacityBits(sinr_dB, bw_Hz, tti_s)
sinrLin = 10.^(sinr_dB/10);
eff = log2(1 + max(sinrLin, 0));
bits = floor(bw_Hz * tti_s * max(eff, 0) * 0.18);
if ~isfinite(bits) || bits < 0
    bits = 0;
end
end

function p = localSuccProb(sinr_dB)
p = 1 / (1 + exp(-(sinr_dB - 3) * 0.35));
p = min(max(p, 0.05), 0.995);
end
