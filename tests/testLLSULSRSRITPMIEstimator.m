function ok = testLLSULSRSRITPMIEstimator()
%TESTLLSULSRSRITPMIESTIMATOR Verify SRS-based UL RI and TPMI estimation path.

setup6GRSimToolkit("Verbose", false);

if exist("nrPUSCHCodebook", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.phy.nRxAnt = 2;
cfg.phy.nTxAnt = 2;
cfg = sixgr.util.structSet(cfg, "phy.pusch.transmissionScheme", "codebook");
cfg = sixgr.util.structSet(cfg, "phy.pusch.transformPrecoding", false);
cfg = sixgr.util.structSet(cfg, "phy.pusch.maxRankDefault", 2);
cfg = sixgr.util.structSet(cfg, "phy.srs.rankEigenThreshold_dB", 10);

Hwb = cat(3, ...
    [1.10 + 0.10j, 0.18 - 0.02j; 0.12 + 0.01j, 0.92 - 0.08j], ...
    [1.02 + 0.06j, 0.15 + 0.01j; 0.08 - 0.03j, 0.88 - 0.04j]);
Hest = zeros(24, 14, 2, 2);
for k = 1:24
    for l = 1:14
        Hest(k, l, :, :) = Hwb(:, :, 1);
    end
end
Hest(13:24, :, :, :) = repmat(reshape(Hwb(:, :, 2), 1, 1, 2, 2), [12, 14, 1, 1]);

est = sixgr.phy.ul.estimateSRSRITPMI(Hest, 0.01, cfg);
assert(logical(est.Valid), ...
    "SRS estimator must report a valid RI/TPMI estimate for a codebook-capable UL channel.");
assert(isfinite(est.RI) && est.RI >= 1 && est.RI <= 2, ...
    "Estimated RI must stay within the supported UL rank range.");
assert(isfinite(est.TPMI), ...
    "Estimated TPMI must be finite when the UL codebook path is active.");
assert(est.TPMICandidateCount > 0 && isfinite(est.TPMIMutualInformation), ...
    "SRS TPMI estimation must score at least one candidate with a finite MI metric.");

ok = true;
end
