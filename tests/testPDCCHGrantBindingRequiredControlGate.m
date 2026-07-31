function ok = testPDCCHGrantBindingRequiredControlGate()
%TESTPDCCHGRANTBINDINGREQUIREDCONTROLGATE Control gating must require decoded DCI binding.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.control_gating.pdcch_required = true;
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;

assert(sixgr.control.isPDCCHGrantBindingRequired(cfg, "DL"), ...
    "DL grant binding must become required when control gating requires PDCCH.");
cfgSchedulerTruth = cfg;
cfgSchedulerTruth.control_gating.pdcch_required = false;
cfgSchedulerTruth.phy.pdsch.executionProfile = "scheduler_truth";
cfgSchedulerTruth.run.pdschExecutionProfile = "scheduler_truth";
assert(sixgr.control.isPDCCHGrantBindingRequired(cfgSchedulerTruth, "DL"), ...
    "scheduler_truth PDSCH must require decoded DCI binding even when access gating is disabled.");

T = localMinimalBoundlessDLTrialTable();
res = sixgr.truth.evaluatePDSCHObjectiveStrict(T, cfg, ...
    "RunId", "pdcch_control_gate_required", ...
    "ScenarioName", "pdcch_grant_binding_required_control_gate", ...
    "StrictMode", true);

codes = string(res.Failures.FailureCode);
assert(logical(res.Summary.GrantBindingRequired(1)), ...
    "Strict DL objective summary must expose GrantBindingRequired=true when control gating requires it.");
assert(~logical(res.ObjectivePass), ...
    "A DL trial without grant binding evidence must fail once control gating requires decoded DCI binding.");
assert(any(codes == "dl_pdsch_grant_binding_missing"), ...
    "Missing decoded DCI binding must be reported explicitly.");

ok = true;
end

function T = localMinimalBoundlessDLTrialTable()
T = table();
T.Direction = "DL";
T.SNR_dB = 15;
T.Frame = 0;
T.Slot = 0;
T.MCS = 4;
T.Layers = 1;
T.Modulation = "QPSK";
T.EffectiveMCSIndex = 4;
T.EffectiveLayers = 1;
T.ConfiguredMCSIndex = 4;
T.ConfiguredModulation = "QPSK";
T.ConfiguredLayers = 1;
T.ConfiguredRank = 1;
T.TBSize_bits = 1024;
T.CRCPass = true;
T.BitErrors = 0;
T.BitsCompared = 1024;
T.StrictReceiverEvidenceOk = true;
T.ChannelEstimateAttempted = true;
T.ChannelEstimateAvailable = true;
T.ResourceExtractionAttempted = true;
T.ResourceExtractionAvailable = true;
T.EqualizationAttempted = true;
T.EqualizationAvailable = true;
T.DLSCHDecodeAttempted = true;
T.DLSCHDecodeAvailable = true;
T.LLRAvailable = true;
T.LLRFinite = true;
T.PostEqSINRWidebanddB = 18;
T.PostEqSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
T.PostEqSINRValueRole = "measured_post_equalization_scheduling_input";
T.PostEqSINRValueStatus = "OK";
T.SINRComputationMethod = "mmse";
T.Crash = false;
T.Skipped = false;
T.TruthStatus = "real_lls_evidence";
T.PDCCHGrantBindingOk = false;
T.PDCCHGrantBindingStatus = "failed";
T.PDCCHGrantBindingFailureCode = "decoded_dci_missing";
end
