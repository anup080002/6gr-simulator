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
assert(est.PRBCount == 2 && est.SRSSymbolCount == 14, ...
    "SRS RI/TPMI estimation must preserve both PRB and SRS-symbol observation dimensions.");

HsymCancel = zeros(24, 2, 2, 2);
HsymCancel(:, 1, :, :) = repmat(reshape(eye(2), 1, 1, 2, 2), [24, 1, 1, 1]);
HsymCancel(:, 2, :, :) = -HsymCancel(:, 1, :, :);
estSym = sixgr.phy.ul.estimateSRSRITPMI(HsymCancel, 0.01, cfg);
assert(estSym.SRSSymbolCount == 2 && estSym.PRBCount == 2, ...
    "SRS estimator must expose the observed symbol and PRB counts.");
assert(isfinite(estSym.RI) && estSym.RI == 2, ...
    "SRS RI estimation must use per-symbol covariance; averaging symbols first would erase this rank-2 channel.");
assert(isfinite(estSym.TPMIMutualInformation) && estSym.TPMIMutualInformation > 1, ...
    "SRS TPMI scoring must accumulate post-equalization MI over nonzero per-symbol channel observations.");

cfgMismatch = sixgr.util.structSet(cfg, "phy.pusch.NumAntennaPorts", 2);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "phy.pusch.numAntennaPorts", 2);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "phy.pusch.nLayers", 2);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "phy.pusch.numLayers", 2);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.pbchRequired", false);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.prachRequired", false);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.pdcchRequired", false);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.srsRequired", true);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.trsRequired", false);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.srsMaxAgeSlots", 8);
cfgMismatch = sixgr.util.structSet(cfgMismatch, "run.controlGating.trsMaxAgeSlots", 8);
Hest4 = zeros(24, 14, 2, 4);
Hest4(:, :, :, 1:2) = Hest;
Hest4(:, :, :, 3) = 0.3 .* Hest(:, :, :, 1);
Hest4(:, :, :, 4) = 0.2 .* Hest(:, :, :, 2);
estMismatch = sixgr.phy.ul.estimateSRSRITPMI(Hest4, 0.01, cfgMismatch);
assert(logical(estMismatch.Valid) && isfinite(estMismatch.TPMI), ...
    "SRS TPMI estimation must remain available when SRS ports exceed active PUSCH codebook ports.");
assert(estMismatch.SRSNumTxPorts == 4 && estMismatch.PUSCHCodebookNumPorts == 2 && estMismatch.NumTxPorts == 2, ...
    "SRS estimator must disclose and use the active PUSCH codebook port count for TPMI scoring.");
assert(strcmp(string(estMismatch.PortSelectionSource), "srs_ports_restricted_to_active_pusch_codebook_ports"), ...
    "SRS estimator must explain when wider SRS ports are restricted to the executable PUSCH codebook.");
try
    nrPUSCHCodebook(round(double(estMismatch.RI)), 2, round(double(estMismatch.TPMI)), false);
catch ME
    error("testLLSULSRSRITPMIEstimator:InvalidRuntimeTPMI", ...
        "Estimated TPMI %g must be executable for rank %g on the active 2-port PUSCH codebook: %s", ...
        double(estMismatch.TPMI), double(estMismatch.RI), ME.message);
end

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
multiUser = struct( ...
    "Enabled", true, ...
    "NumUsers", 1, ...
    "RNTIStart", 701, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfgMismatch, fullfile(tmp, "run"), multiUser, struct(), 1);
srsPass = table("PASS", 1, 1, true, 2, 12, ...
    'VariableNames', {'Status','Slot','Frame','CRCPass','RIEstimate','TPMIEstimate'});
state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, 1, srsPass);
sanitized = double(state.LatestULFeedback(1).PMI);
assert(isfinite(sanitized) && sanitized ~= 12, ...
    "Coupled runtime must not pass a wider-port invalid UL TPMI from SRS feedback through to a 2-port PUSCH grant.");
try
    nrPUSCHCodebook(2, 2, round(double(sanitized)), false);
catch ME
    error("testLLSULSRSRITPMIEstimator:InvalidSanitizedTPMI", ...
        "Sanitized UL TPMI %g must be executable for rank-2 2-port PUSCH: %s", ...
        double(sanitized), ME.message);
end

ok = true;
end
