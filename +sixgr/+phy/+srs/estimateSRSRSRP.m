function out = estimateSRSRSRP(det, srsCfg)
%ESTIMATESRSRSRP Estimate SRS received power from extracted receiver REs.

obs = det.Extracted.ObservedSymbols(:);
mask = isfinite(real(obs)) & isfinite(imag(obs));
if any(mask)
    rsrpLinear = mean(abs(obs(mask)).^2, "omitnan");
    rsrpDb = 10 * log10(max(rsrpLinear, eps));
else
    rsrpLinear = NaN;
    rsrpDb = NaN;
end
out = struct();
out.RSRPLinear = double(rsrpLinear);
out.RSRP_dB = double(rsrpDb);
out.NumSamples = double(sum(mask));
out.ConfigHash = string(srsCfg.ConfigHash);
out.TruthStatus = "real_lls_evidence";
end
