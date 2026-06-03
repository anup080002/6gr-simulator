function cqi = mapSINRToCQI(sinr_dB)
%MAPSINRTOCQI Authoritative SINR-to-CQI mapping used by LLS truth paths.

thresholds_dB = [-inf -5 -2 0 2 4 6 8 10 12 14 16 18 20 22 24];
idx = find(double(sinr_dB) >= thresholds_dB, 1, "last");
if isempty(idx)
    cqi = 0;
else
    cqi = max(0, min(15, idx - 1));
end
end
