function est = PDSCHChannelEstimator(rx)
%PDSCHChannelEstimator Summarize the active PDSCH channel-estimation result.

hEst = sixgr.util.structGet(rx, "ChannelEstimate", []);
nmseProxy = NaN;
if ~isempty(hEst)
    mag = abs(double(hEst(:)));
    nmseProxy = mean(abs(mag - 1).^2, "omitnan") / max(mean(mag.^2, "omitnan"), eps);
end
est = struct();
est.Mode = char(string(sixgr.util.structGet(rx, "TimingEstimateSource", "")));
est.Engine = char(string(sixgr.util.structGet(rx, "ChannelEstimationEngine", "")));
est.NMSEProxy = double(nmseProxy);
est.NoiseVar = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
est.Source = "dmrs_based_channel_estimate_from_pdsch_rx";
end
