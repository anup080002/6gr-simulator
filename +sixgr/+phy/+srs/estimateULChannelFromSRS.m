function ch = estimateULChannelFromSRS(det, srsCfg)
%ESTIMATEULCHANNELFROMSRS Estimate UL channel from extracted SRS REs.

obs = det.Extracted.ObservedSymbols(:);
ref = det.Extracted.ReferenceSymbols(:);
N = min(numel(obs), numel(ref));
h = [];
nmseDb = NaN;
sinrDb = NaN;
if N > 0
    obs = obs(1:N);
    ref = ref(1:N);
    mask = isfinite(real(obs)) & isfinite(imag(obs)) & isfinite(real(ref)) & isfinite(imag(ref)) & abs(ref) > eps;
    if any(mask)
        h = obs(mask) ./ ref(mask);
        hRef = ones(size(h));
        gain = mean(h, "omitnan");
        err = h - gain .* hRef;
        nmse = mean(abs(err).^2, "omitnan") / max(mean(abs(gain .* hRef).^2, "omitnan"), eps);
        nmseDb = 10 * log10(max(nmse, eps));
        sinrDb = 10 * log10(max(mean(abs(gain .* hRef).^2, "omitnan") / max(mean(abs(err).^2, "omitnan"), eps), eps));
    end
end
available = logical(det.DetectionSuccess) && isfinite(nmseDb) && nmseDb <= double(srsCfg.ChannelNMSEThresholddB);
row = struct("RunId", string(srsCfg.RunId), "TrialId", NaN, "UEId", double(srsCfg.UEId), ...
    "ResourceId", double(srsCfg.ResourceId), "Port", 0, "PRBStart", double(det.Coverage.PRBStart), ...
    "NumRB", double(det.Coverage.OccupiedPRBCount), "ChannelEstimateAttempted", true, ...
    "SRSChannelEstimateAvailable", logical(available), "PerPRBEstimateAvailable", logical(available), ...
    "PerPortEstimateAvailable", logical(available), "NMSE_dB", double(nmseDb), ...
    "WidebandSRSSINR_dB", double(sinrDb), "NumChannelSamples", double(numel(h)), ...
    "Estimator", "srs_ls_receiver_grid_estimator", ...
    "FailureReason", string(sixgr.phy.srs.localTernary(available, "", "srs_channel_estimate_unavailable_or_nmse_above_threshold")), ...
    "ConfigHash", string(srsCfg.ConfigHash), "TruthStatus", "real_lls_evidence");
ch = struct("ChannelEstimateAttempted", true, "SRSChannelEstimateAvailable", logical(available), ...
    "Hest", h, "NMSE_dB", double(nmseDb), "WidebandSRSSINR_dB", double(sinrDb), ...
    "Table", struct2table(row, "AsArray", true));
end
