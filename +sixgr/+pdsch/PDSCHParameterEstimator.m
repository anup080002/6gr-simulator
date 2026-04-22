function est = PDSCHParameterEstimator(rx, replay, carrier)
%PDSCHParameterEstimator Practical parameter-estimation study hook.

est = struct();
est.EstimatedSNR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
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

