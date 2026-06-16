function ok = testDLPDSCHRawBLERBERObjectiveGate()
%TESTDLPDSCHRAWBLERBEROBJECTIVEGATE Degraded DL cannot pass strict objective.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.pdsch.mcsIndex = 20;
cfg.phy.pdsch.modulation = "256QAM";
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numLayers = 2;
cfg.validation.dl_pdsch.max_bler = 0.10;
cfg.validation.dl_pdsch.max_ber = 1e-3;
cfg.validation.dl_pdsch.required_configured_match_rate = 0.999;

T = localDegradedTrialTable();
res = sixgr.truth.evaluatePDSCHObjectiveStrict(T, cfg, ...
    "RunId", "audited_degraded_case", ...
    "ScenarioName", "aud_pdsch_001_regression", ...
    "StrictMode", true);

summary = res.Summary;
assert(~logical(res.ObjectivePass), "Degraded raw DL PDSCH objective must fail.");
assert(~logical(summary.ResultOk(1)) && ~logical(summary.ScenarioObjectiveOk(1)), ...
    "ResultOk/ScenarioObjectiveOk must be false for degraded raw DL PDSCH.");
assert(abs(double(summary.RawBLER(1)) - 141/325) < 1e-12, ...
    "Raw BLER must be computed from TB CRC rows.");
assert(abs(double(summary.RawBERWeighted(1)) - 0.309128) < 1e-6, ...
    "Raw BER must be weighted sum(BitErrors)/sum(BitsCompared).");

codes = string(res.Failures.FailureCode);
assert(any(codes == "dl_pdsch_bler_objective_failed"), ...
    "BLER objective failure must be explicit.");
assert(any(codes == "dl_pdsch_ber_objective_failed"), ...
    "BER objective failure must be explicit.");
assert(any(codes == "dl_pdsch_configured_effective_mismatch"), ...
    "Fixed configured/effective mismatch must be explicit.");
assert(any(codes == "dl_pdsch_rank_layer_collapse"), ...
    "Rank/layer collapse must be explicit.");
assert(any(codes == "dl_pdsch_mcs_modulation_collapse"), ...
    "MCS/modulation collapse must be explicit.");

ok = true;
end

function T = localDegradedTrialTable()
n = 325;
crcPass = false(n, 1);
crcPass(1:184) = true;
bitsCompared = repmat(1000000, n, 1);
bitErrors = round(bitsCompared * 0.309128);
T = table();
T.Direction = repmat("DL", n, 1);
T.SNR_dB = repmat(15, n, 1);
T.Frame = (0:n-1)';
T.MCS = repmat(1, n, 1);
T.Layers = repmat(1, n, 1);
T.Modulation = repmat("QPSK", n, 1);
T.EffectiveMCSIndex = repmat(1, n, 1);
T.EffectiveLayers = repmat(1, n, 1);
T.ConfiguredMCSIndex = repmat(20, n, 1);
T.ConfiguredModulation = repmat("256QAM", n, 1);
T.ConfiguredLayers = repmat(2, n, 1);
T.ConfiguredRank = repmat(2, n, 1);
T.TBSize_bits = repmat(1000, n, 1);
T.CRCPass = crcPass;
T.BitErrors = bitErrors;
T.BitsCompared = bitsCompared;
T.StrictReceiverEvidenceOk = true(n, 1);
T.ChannelEstimateAttempted = true(n, 1);
T.ChannelEstimateAvailable = true(n, 1);
T.ResourceExtractionAttempted = true(n, 1);
T.ResourceExtractionAvailable = true(n, 1);
T.EqualizationAttempted = true(n, 1);
T.EqualizationAvailable = true(n, 1);
T.DLSCHDecodeAttempted = true(n, 1);
T.DLSCHDecodeAvailable = true(n, 1);
T.LLRAvailable = true(n, 1);
T.LLRFinite = true(n, 1);
T.PostEqSINRWidebanddB = repmat(12, n, 1);
T.PostEqSINRSource = repmat("post_equalization_sinr_from_equalizer_channel_estimate", n, 1);
T.PostEqSINRValueRole = repmat("measured_post_equalization_scheduling_input", n, 1);
T.PostEqSINRValueStatus = repmat("OK", n, 1);
T.SINRComputationMethod = repmat("mmse", n, 1);
T.Crash = false(n, 1);
T.Skipped = false(n, 1);
T.TruthStatus = repmat("real_lls_evidence", n, 1);
end
