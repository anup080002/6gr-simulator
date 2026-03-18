function offeredBits = Traffic_GenAI(cfg, nUE, nTTI, ~)
%TRAFFIC_GENAI Bursty GenAI-like uplink/downlink workload model.

burstProb = double(sixgr.util.structGet(cfg, "traffic.genai.burstProb", 0.12));
meanBits = double(sixgr.util.structGet(cfg, "traffic.genai.meanBurstBits", 6e5));
sigma = double(sixgr.util.structGet(cfg, "traffic.genai.logSigma", 0.65));

offeredBits = zeros(nTTI, nUE);
u = rand(nTTI, nUE);
isBurst = (u < burstProb);

if any(isBurst(:))
    z = sigma * randn(nTTI, nUE);
    bursts = meanBits * exp(z - 0.5*sigma^2);
    offeredBits(isBurst) = bursts(isBurst);
end
end
