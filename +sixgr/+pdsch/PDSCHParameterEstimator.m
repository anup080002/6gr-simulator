function est = PDSCHParameterEstimator(rx, replay, carrier)
%PDSCHParameterEstimator Practical parameter-estimation study hook.

est = struct();
[estimatedSNR, estimatedSource, estimatedRole] = localBestEstimatedSNR(rx);
est.EstimatedSNR_dB = double(estimatedSNR);
est.EstimatedSNRSource = char(estimatedSource);
est.EstimatedSNRValueRole = char(estimatedRole);
est.PostEqSINR_dB = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
est.PostEqSINRSource = char(string(sixgr.util.structGet(rx, "PostEqSINRSource", "")));
est.ReceiverHestSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
est.ReceiverHestSINRSource = char(string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", "")));
est.EstimatedDelay_samples = double(sixgr.util.structGet(rx, "TimingOffset", NaN));
est.EstimatedDelaySpread_s = NaN;
est.EstimatedDoppler_Hz = NaN;
est.Source = "practical_estimation_from_receiver_observables";

hEst = sixgr.util.structGet(rx, "ChannelEstimate", []);
if ~isempty(hEst) && ndims(hEst) >= 2
    Havg = squeeze(mean(double(hEst), [2 3], "omitnan"));
    if isvector(Havg) && numel(Havg) >= 4
        pdp = abs(ifft(Havg)).^2;
        pdp = pdp(:);
        pdp = pdp / max(sum(pdp), eps);
        tau = (0:numel(pdp)-1).' / max(1, double(carrier.NSizeGrid) * 12);
        muTau = sum(tau .* pdp);
        est.EstimatedDelaySpread_s = sqrt(max(sum(((tau - muTau).^2) .* pdp), 0));
    end
end
if isstruct(replay)
    est.EstimatedDoppler_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
end
end

function [sinr, source, role] = localBestEstimatedSNR(rx)
sinr = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
source = string(sixgr.util.structGet(rx, "PostEqSINRSource", ""));
role = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", ""));
if isfinite(sinr)
    if strlength(strtrim(source)) == 0
        source = "post_equalization_sinr_from_equalizer_channel_estimate";
    end
    if strlength(strtrim(role)) == 0
        role = "measured_post_equalization_scheduling_input";
    end
    return;
end
sinr = NaN;
source = "post_equalization_sinr_unavailable";
role = "unavailable";
end
