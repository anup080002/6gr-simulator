function offeredBits = Traffic_XR(cfg, nUE, nTTI, tti_s)
%TRAFFIC_XR XR-like periodic burst traffic.

pktBits = double(sixgr.util.structGet(cfg, "traffic.xr.packetBits", 2e5));
fps = double(sixgr.util.structGet(cfg, "traffic.xr.frameRate_fps", 50));
jitter = double(sixgr.util.structGet(cfg, "traffic.xr.jitterPct", 0.15));

periodTTI = max(1, round((1/max(fps,1)) / max(tti_s,eps)));
offeredBits = zeros(nTTI, nUE);

for t = 1:nTTI
    if mod(t-1, periodTTI) == 0
        sc = 1 + jitter * (2*rand(1,nUE)-1);
        offeredBits(t,:) = pktBits .* sc;
    end
end

offeredBits = max(0, offeredBits);
end
