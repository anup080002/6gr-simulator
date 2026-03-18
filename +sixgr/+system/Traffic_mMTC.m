function offeredBits = Traffic_mMTC(cfg, nUE, nTTI, tti_s)
%TRAFFIC_MMTC Sparse IoT traffic model.

lambdaPktPerSec = double(sixgr.util.structGet(cfg, "traffic.mmtc.lambdaPktPerSec", 0.5));
pktBits = double(sixgr.util.structGet(cfg, "traffic.mmtc.packetBits", 256));
lambda = max(0, lambdaPktPerSec * max(tti_s, eps));

arrivals = localPoisson(lambda, [nTTI, nUE]);
offeredBits = pktBits * arrivals;
end

function x = localPoisson(lambda, sz)
if exist("poissrnd", "file") == 2
    x = poissrnd(lambda, sz);
    return;
end

% Knuth algorithm fallback (works well for small lambda).
x = zeros(sz);
L = exp(-lambda);
for i = 1:prod(sz)
    k = 0;
    p = 1;
    while p > L
        k = k + 1;
        p = p * rand();
    end
    x(i) = k - 1;
end
x = reshape(x, sz);
end
