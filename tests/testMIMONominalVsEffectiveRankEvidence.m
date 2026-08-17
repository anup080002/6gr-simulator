function ok = testMIMONominalVsEffectiveRankEvidence()
%TESTMIMONOMINALVSEFFECTIVERANKEVIDENCE Effective rank must come from raw receiver rows.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg(2, 20, "256QAM");
raw = struct("DL", localRank2Rows("DL"), "UL", localRank2Rows("UL"));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_positive", "StrictMode", true);
assert(all(logical(out.ConfiguredVsEffective.ScenarioObjectivePass)), ...
    "Rank-2 raw receiver evidence must pass configured-vs-effective summary.");
dlRows = out.RankLayerTrials(strcmp(string(out.RankLayerTrials.Direction), "DL"), :);
assert(all(double(dlRows.EffectiveDecodedRank) == 2), ...
    "Effective decoded DL rank must be reconstructed from per-layer receiver evidence.");
assert(all(strlength(string(dlRows.LayerSINRdB)) > 0), ...
    "Rank-2 strict evidence must carry per-layer SINR lineage.");

fullCfg = cfg;
fullCfg.scenario.ue.nTxAnt = 4;
fullCfg.scenario.bs.nRxAnt = 64;
fullCfg.channel.nTxAntUL = 4;
fullCfg.channel.nRxAntUL = 64;
fullCfg.phy.beamManagement.hybridBeamformingEnabled = true;
fullRaw = struct("DL", localFullElementRows("DL"), ...
    "UL", localFullElementRows("UL"));
fullOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(fullCfg,fullRaw, ...
    "RunId","mimo_full_element_positive","StrictMode",true);
assert(logical(fullOut.StrictOk), ...
    "Physical 64x4/4x64 channel participation plus logical rank-2 execution must pass strict MIMO evidence.");
assert(all(logical(fullOut.AntennaArrayConfig.ExactRuntimeAntennaMatch)));
assert(all(logical(fullOut.AntennaArrayConfig.LogicalPortLayerMatch)));
assert(isequal(double(fullOut.AntennaArrayConfig.ObservedPhysicalTxAntennaCount(:)),[64;4]));
assert(isequal(double(fullOut.AntennaArrayConfig.ObservedPhysicalRxAntennaCount(:)),[4;64]));
assert(height(fullOut.NegativeTrials) == 0, ...
    "A successful runtime must not manufacture a placeholder negative trial.");

matrixOnlyRaw = fullRaw;
matrixOnlyRaw.DL.AppliedPrecoderPMI(:) = NaN;
matrixOnlyRaw.DL.AppliedPrecoderMatrixSHA256 = repmat( ...
    string(repmat('a', 1, 64)), height(matrixOnlyRaw.DL), 1);
matrixOnlyOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(fullCfg,matrixOnlyRaw, ...
    "RunId","mimo_applied_matrix_without_pmi","StrictMode",true);
dlPrecoder = matrixOnlyOut.PrecoderEvidence( ...
    string(matrixOnlyOut.PrecoderEvidence.Direction) == "DL", :);
assert(logical(matrixOnlyOut.StrictOk) && ...
    all(logical(dlPrecoder.PrecodingActive)) && ...
    all(string(dlPrecoder.EvidenceType) == "applied_matrix") && ...
    all(string(dlPrecoder.Status) == "pass"), ...
    "A valid physically applied precoder-matrix digest must prove DL precoding even when no scalar PMI exists.");

exportRoot = string(tempname);
mkdir(exportRoot);
exportCleanup = onCleanup(@()localRemoveTree(exportRoot)); %#ok<NASGU>
exported = sixgr.mimo.exportMIMOEvidenceArtifacts(exportRoot, fullCfg, fullRaw, ...
    "RunId", "mimo_export_status_positive", "StrictMode", true);
assert(isfield(exported, "StrictOk") && isfield(exported, "Ok") && ...
    logical(exported.StrictOk) && logical(exported.Ok), ...
    "The MIMO artifact adapter must expose its strict evidence status to runSingle.");
assert(strlength(string(exported.FailureReason)) == 0, ...
    "A passing MIMO artifact export must not carry a failure reason.");

failedExportRoot = string(tempname);
mkdir(failedExportRoot);
failedExportCleanup = onCleanup(@()localRemoveTree(failedExportRoot)); %#ok<NASGU>
failedExport = sixgr.mimo.exportMIMOEvidenceArtifacts(failedExportRoot, fullCfg, ...
    struct("DL", table(), "UL", table()), ...
    "RunId", "mimo_export_status_missing", "StrictMode", true);
assert(isfield(failedExport, "StrictOk") && ~logical(failedExport.StrictOk) && ...
    ~logical(failedExport.Ok) && strlength(string(failedExport.FailureReason)) > 0, ...
    "The MIMO artifact adapter must preserve missing-evidence failure status at its top level.");

adaptiveCfg = fullCfg;
adaptiveCfg.link_adaptation.fixed_or_amc = "amc";
adaptiveRaw = fullRaw;
adaptiveRaw.DL.Modulation(:) = "QPSK";
adaptiveRaw.DL.MCS(:) = 1;
adaptiveRaw.UL.Modulation(:) = "16QAM";
adaptiveRaw.UL.MCS(:) = 10;
adaptiveRaw.DL = localAddAdaptivePolicyEvidence(adaptiveRaw.DL);
adaptiveRaw.UL = localAddAdaptivePolicyEvidence(adaptiveRaw.UL);
adaptiveOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,adaptiveRaw, ...
    "RunId","mimo_fixed_rank_amc","StrictMode",true);
assert(all(logical(adaptiveOut.MIMOConfigStrict.FixedAnchorMode)) && ...
    all(logical(adaptiveOut.MIMOConfigStrict.AdaptiveMode)), ...
    "Fixed-rank anchoring and AMC must remain independent runtime controls.");
assert(logical(adaptiveOut.StrictOk) && ...
    all(double(adaptiveOut.ConfiguredVsEffective.ExactMatchPercent) == 0) && ...
    all(double(adaptiveOut.ConfiguredVsEffective.ExecutionContractMatchPercent) >= 0.999), ...
    "AMC changes must remain exact operating-point mismatches while passing a separately proven adaptive policy contract.");
assert(all(logical(adaptiveOut.RankLayerTrials.ExactSpatialMatch)) && ...
    all(~logical(adaptiveOut.RankLayerTrials.ExactOperatingPointMatch)) && ...
    all(logical(adaptiveOut.RankLayerTrials.AdaptivePolicyMatch)), ...
    "Spatial exactness, configured operating-point equality, and adaptive-policy compliance must be separate evidence fields.");
assert(all(logical(adaptiveOut.ConfiguredVsEffective.SpatialContractMatch)) && ...
    all(~logical(adaptiveOut.ConfiguredVsEffective.FixedOperatingPointMatch)) && ...
    all(~logical(adaptiveOut.ConfiguredVsEffective.FixedOperatingPointRequired)) && ...
    all(logical(adaptiveOut.ConfiguredVsEffective.AdaptivePolicyConformance)) && ...
    all(logical(adaptiveOut.ConfiguredVsEffective.MUExecutionMatch)), ...
    "The four MIMO gates must remain explicit; disabled MU is a visible not-applicable pass.");
assert(all(string(adaptiveOut.MIMOConfigStrict.Status) == "pass") && ...
    all(strlength(string(adaptiveOut.MIMOConfigStrict.RuntimeValidationFailureReason)) == 0), ...
    "Direct adaptive runtime evidence must resolve the MIMO config status instead of leaving it not_validated.");

bootstrapOnlyRaw = adaptiveRaw;
bootstrapOnlyRaw.DL.MCSValueStatus(:) = ...
    "yaml_mu_mimo_first_data_bootstrap_pending_data_feedback";
bootstrapOnlyRaw.UL.MCSValueStatus(:) = ...
    "yaml_mu_mimo_first_data_bootstrap_pending_data_feedback";
bootstrapOnlyOut = sixgr.mimo.resolveNominalVsEffectiveMIMO( ...
    adaptiveCfg, bootstrapOnlyRaw, "RunId", "mimo_bootstrap_only", ...
    "StrictMode", true);
assert(~logical(bootstrapOnlyOut.StrictOk) && ...
    all(double(bootstrapOnlyOut.ConfiguredVsEffective.AdaptiveFeedbackDecisionRowCount) == 0) && ...
    all(~logical(bootstrapOnlyOut.ConfiguredVsEffective.AdaptivePolicyConformance)) && ...
    all(contains(string(bootstrapOnlyOut.ConfiguredVsEffective.FailureReason), ...
        "adaptive_policy_only_bootstrap_rows")), ...
    ["An adaptive run containing only configured bootstrap grants must " ...
    "not be certified as measured CQI feedback adaptation."]);

muCfg = adaptiveCfg;
muCfg.mimo.mu_mimo_enable = true;
muCfg.mimo.ul_mu_mimo_enable = true;
muCfg.mimo.mu_mimo_max_users_per_prb = 2;
muCfg.mac.scheduler.muMimoEnabled = true;
muCfg.mac.scheduler.ulMuMimoEnabled = true;
muCfg.mac.scheduler.muMimoMaxUsersPerPRB = 2;
muCfg.mac.scheduler.muMimoPrecoderLeakageThreshold_dB = -15;
muCfg.run.intraCellInterferenceExecutionMode = "shared_slot_waveform_superposition";
muRaw = adaptiveRaw;
muRaw.DL = localAddMUExecutionEvidence(muRaw.DL, 1001);
muRaw.UL = localAddMUExecutionEvidence(muRaw.UL, 2001);
muOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(muCfg, muRaw, ...
    "RunId","mimo_physical_mu_positive","StrictMode",true);
assert(logical(muOut.StrictOk) && ...
    all(logical(muOut.ConfiguredVsEffective.MUExecutionRequired)) && ...
    all(logical(muOut.ConfiguredVsEffective.MUExecutionMatch)) && ...
    all(double(muOut.ConfiguredVsEffective.MUExecutedDistinctGroupCount) == 1) && ...
    all(double(muOut.ConfiguredVsEffective.MUExecutedTrialRowCount) == 2), ...
    "A complete causally paired shared-waveform MU opportunity must pass its independent execution gate.");
muMissingWaveform = muRaw;
muMissingWaveform.DL.InterferenceContributorCount(:) = 0;
muMissingWaveformOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(muCfg, muMissingWaveform, ...
    "RunId","mimo_mu_missing_waveform","StrictMode",true);
dlMUSummary = muMissingWaveformOut.ConfiguredVsEffective( ...
    string(muMissingWaveformOut.ConfiguredVsEffective.Direction) == "DL", :);
assert(~logical(muMissingWaveformOut.StrictOk) && ...
    ~logical(dlMUSummary.MUExecutionMatch) && ...
    contains(string(dlMUSummary.FailureReason), "mu_execution_contract_failed"), ...
    "Scheduler MU labels without peer waveform superposition must fail closed.");
muWeakCovariance = muRaw;
muWeakCovariance.UL.InterferenceCovarianceSource(:) = ...
    "runtime_covariance_without_shared_contribution_grid_binding";
muWeakCovarianceOut = sixgr.mimo.resolveNominalVsEffectiveMIMO( ...
    muCfg, muWeakCovariance, "RunId", "mimo_mu_unbound_ul_covariance", ...
    "StrictMode", true);
ulWeakCovarianceSummary = muWeakCovarianceOut.ConfiguredVsEffective( ...
    string(muWeakCovarianceOut.ConfiguredVsEffective.Direction) == "UL", :);
assert(~logical(muWeakCovarianceOut.StrictOk) && ...
    ~logical(ulWeakCovarianceSummary.MUExecutionMatch), ...
    "UL MU execution must fail unless IRC is bound to the exact shared-slot contribution-grid covariance.");
muUnappliedCombiner = muRaw;
muUnappliedCombiner.UL.MUMIMOReceiveCombinerApplied(:) = false;
muUnappliedCombinerOut = sixgr.mimo.resolveNominalVsEffectiveMIMO( ...
    muCfg, muUnappliedCombiner, "RunId", "mimo_mu_unapplied_ul_combiner", ...
    "StrictMode", true);
ulUnappliedSummary = muUnappliedCombinerOut.ConfiguredVsEffective( ...
    string(muUnappliedCombinerOut.ConfiguredVsEffective.Direction) == "UL", :);
assert(~logical(muUnappliedCombinerOut.StrictOk) && ...
    ~logical(ulUnappliedSummary.MUExecutionMatch), ...
    "A scheduled UL combiner digest without receiver-side application must fail closed.");
muDLMatrixMismatch = muRaw;
muDLMatrixMismatch.DL.AppliedPrecoderMatrixSHA256(:) = ...
    string(repmat('b', 1, 64));
muDLMatrixMismatchOut = sixgr.mimo.resolveNominalVsEffectiveMIMO( ...
    muCfg, muDLMatrixMismatch, "RunId", "mimo_mu_dl_precoder_digest_mismatch", ...
    "StrictMode", true);
dlMismatchSummary = muDLMatrixMismatchOut.ConfiguredVsEffective( ...
    string(muDLMatrixMismatchOut.ConfiguredVsEffective.Direction) == "DL", :);
assert(~logical(muDLMatrixMismatchOut.StrictOk) && ...
    ~logical(dlMismatchSummary.MUExecutionMatch), ...
    "A DL scheduler matrix that differs from the physically applied precoder must fail closed.");

overMaximumRaw = adaptiveRaw;
overMaximumRaw.DL.MCS(:) = 21;
overMaximumRaw.DL.ScheduledMCS(:) = 21;
overMaximumRaw.DL.CQIDerivedMCS(:) = 21;
overMaximum = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,overMaximumRaw, ...
    "RunId","mimo_adaptive_maximum_violation","StrictMode",true);
overMaximumDL = overMaximum.RankLayerTrials( ...
    string(overMaximum.RankLayerTrials.Direction) == "DL", :);
assert(~logical(overMaximum.StrictOk) && ...
    all(~logical(overMaximumDL.AdaptivePolicyMatch)) && ...
    all(contains(string(overMaximumDL.AdaptivePolicyFailureReason), ...
    "adaptive_maximum_mcs_exceeded")), ...
    "Adaptive MIMO evidence must fail when a scheduled/transmitted MCS exceeds the YAML maximum.");

unprovenAdaptiveRaw = adaptiveRaw;
for direction = ["DL","UL"]
    unprovenAdaptiveRaw.(direction).MCSSelectionSource(:) = "";
    unprovenAdaptiveRaw.(direction).MCSAuthority(:) = "";
    unprovenAdaptiveRaw.(direction).ModulationAuthority(:) = "";
    unprovenAdaptiveRaw.(direction).AppliedOperatingPointSource(:) = "";
    unprovenAdaptiveRaw.(direction).GrantContextId(:) = "";
    unprovenAdaptiveRaw.(direction).CSIPayloadHex(:) = "";
end
unprovenAdaptiveOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,unprovenAdaptiveRaw, ...
    "RunId","mimo_unproven_amc","StrictMode",true);
assert(~logical(unprovenAdaptiveOut.StrictOk) && ...
    all(~logical(unprovenAdaptiveOut.RankLayerTrials.AdaptivePolicyMatch)) && ...
    all(contains(string(unprovenAdaptiveOut.RankLayerTrials.AdaptivePolicyFailureReason), ...
    "adaptive_decision_lineage_missing")), ...
    "A modulation/MCS change without measured adaptive-decision lineage must fail closed.");

lowSNRRaw = adaptiveRaw;
lowSNRRaw.DL.CRCPass(1) = false;
lowSNRRaw.DL.DecodeUsable(1) = false;
lowSNRRaw.DL.ReceiverUsable(1) = false;
lowSNRRaw.UL.CRCPass(1) = false;
lowSNRRaw.UL.DecodeUsable(1) = false;
lowSNRRaw.UL.ReceiverUsable(1) = false;
lowSNROut = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,lowSNRRaw, ...
    "RunId","mimo_fixed_rank_amc_low_snr","StrictMode",true);
assert(all(double(lowSNROut.ConfiguredVsEffective.ExecutionContractMatchPercent) >= 0.999) && ...
    all(logical(lowSNROut.ConfiguredVsEffective.ScenarioObjectivePass)), ...
    "Low-SNR CRC failures must remain reliability failures, not false rank/layer execution mismatches.");
failedRows = lowSNROut.RankLayerTrials(~logical(lowSNROut.RankLayerTrials.DecodeCrcPass), :);
assert(all(double(failedRows.TransmittedRank) == 2) && ...
    all(double(failedRows.EffectiveDecodedRank) == 0) && ...
    all(logical(failedRows.ExecutionContractMatch)), ...
    "MIMO evidence must preserve transmitted rank two while keeping failed decoded rank explicitly zero.");

badRaw = fullRaw;
badRaw.DL.TxWaveformColumns(:) = 2;
badRaw.DL.PhysicalTxAntennas(:) = 2;
badOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(fullCfg,badRaw, ...
    "RunId","mimo_full_element_bad","StrictMode",true);
assert(~logical(badOut.StrictOk), ...
    "Logical rank-2 ports must not be mislabeled as a 64-element physical transmit path.");

noRaw = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, struct("DL", table(), "UL", table()), ...
    "RunId", "mimo_missing", "StrictMode", true);
assert(~logical(noRaw.StrictOk), "Nominal configuration alone must not pass as effective MIMO evidence.");
assert(all(double(noRaw.ConfiguredVsEffective.StrictEligibleRowCount) == 0), ...
    "Missing raw trial rows must remain visible in configured-vs-effective evidence.");

ok = true;
end

function localRemoveTree(folder)
folder = char(string(folder));
if isfolder(folder)
    rmdir(folder, "s");
end
end

function cfg = localCfg(layers, mcs, modulation)
cfg = struct();
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfg.channel.nTxAnt = 64;
cfg.channel.nRxAnt = 4;
cfg.phy.pdsch.numLayers = layers;
cfg.phy.pdsch.nLayers = layers;
cfg.phy.pdsch.mcsIndex = mcs;
cfg.phy.pdsch.modulation = modulation;
cfg.phy.pdsch.NumAntennaPorts = 4;
cfg.phy.pusch.numLayers = layers;
cfg.phy.pusch.nLayers = layers;
cfg.phy.pusch.mcsIndex = mcs;
cfg.phy.pusch.modulation = modulation;
cfg.phy.pusch.NumAntennaPorts = layers;
cfg.link_adaptation.fixed_or_amc = "fixed";
cfg.link_adaptation.initial_mcs = 1;
cfg.link_adaptation.maximum_mcs = 20;
cfg.mimo.rank_adaptation_policy = "fixed";
end

function T = localRank2Rows(direction)
T = table(repmat(string(direction), 2, 1), [1; 2], [10; 11], [1; 1], [2; 2], [2; 2], ...
    repmat("256QAM", 2, 1), [20; 20], [true; true], [true; true], [true; true], ...
    repmat("18|17", 2, 1), [0.02; 0.02], [-30; -31], [5; 5], [0; 0], [1000; 1000], ...
    [3; 3], [1; 1], repmat("csi01", 2, 1), ...
    'VariableNames', {'Direction','TrialId','Slot','Frame','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB','EVM_rms','NMSE_dB', ...
    'LLRMeanAbs','BitErrors','BitsCompared','AppliedPrecoderPMI','SelectedBeamIndex','CSIPayloadHex'});
end

function T = localAddAdaptivePolicyEvidence(T)
n = height(T);
T.ScheduledLayers = T.Layers;
T.ScheduledRank = T.RankEstimate;
T.ScheduledModulation = T.Modulation;
T.ScheduledMCS = T.MCS;
T.ActualMCSSelectionMode = repmat("scheduler_grant", n, 1);
T.MCSSelectionSource = repmat("runtime_cqi_table_raw", n, 1);
T.MCSAuthority = repmat("cqi_link_adaptation", n, 1);
T.ModulationAuthority = repmat("cqi_link_adaptation", n, 1);
T.AppliedOperatingPointSource = repmat("cqi_link_adaptation", n, 1);
T.LinkAdaptationScheduled = true(n, 1);
T.LinkAdaptationApplied = true(n, 1);
T.WidebandCQI = repmat(8, n, 1);
T.CQIDerivedMCS = T.MCS;
T.MCSValueStatus = repmat("measured_feedback_adapted", n, 1);
T.GrantContextId = "grant_" + string((1:n).');
end

function T = localAddMUExecutionEvidence(T, groupId)
n = height(T);
assert(n == 2, "MU evidence fixture requires exactly two group members.");
T.UEIndex = (1:n).';
T.MUMIMOEnabled = true(n, 1);
T.MUMIMOGroupSize = repmat(n, n, 1);
T.MUMIMOGroupId = repmat(double(groupId), n, 1);
T.MUMIMOPairingStatus = repmat("paired_shared_prb_spatial_multiplexing", n, 1);
T.MUMIMOPairingMetricValue_dB = repmat(-100, n, 1);
T.MUMIMOSpatialFilterMatrixSHA256 = repmat(string(repmat('a', 1, 64)), n, 1);
if upper(string(T.Direction(1))) == "DL"
    T.MUMIMOPairingMetricSource = repmat( ...
        "measured_tdd_srs_reciprocal_complete_peer_subspace_hybrid_block_diagonalized_precoder_leakage", n, 1);
    T.MUMIMOPairingEvidenceSource = repmat( ...
        "causal_measured_srs_complete_peer_subspace_reciprocity_phase_only_hybrid_and_frozen_baseband", n, 1);
    T.AppliedPrecoderMatrixSHA256 = T.MUMIMOSpatialFilterMatrixSHA256;
    T.InterferenceCovarianceAvailable = true(n, 1);
    T.InterferenceCovarianceSource = repmat( ...
        "shared_slot_contribution_grid_covariance", n, 1);
else
    T.MUMIMOPairingMetricSource = repmat( ...
        "measured_srs_peer_subspace_admission_projection_leakage_full_dimensional_per_re_irc", n, 1);
    T.MUMIMOPairingEvidenceSource = repmat( ...
        "causal_measured_srs_pairing_with_full_receiver_observation_and_runtime_per_re_irc_covariance", n, 1);
    T.MUMIMOAdmissionReceiveCombiningMatrixSHA256 = T.MUMIMOSpatialFilterMatrixSHA256;
    T.MUMIMOReceiveProcessingMode = repmat("full_dimensional_per_re_irc", n, 1);
    T.MUMIMOReceiverAlgorithmApplied = repmat("full_dimensional_per_re_irc", n, 1);
    T.EqualizerType = repmat("MMSE_IRC", n, 1);
    T.InterferenceCovarianceSource = repmat( ...
        "shared_slot_contribution_grid_covariance", n, 1);
    T.InterferenceCovarianceAvailable = true(n, 1);
    T.MUMIMOReceiveCombinerApplied = true(n, 1);
    T.MUMIMOReceiveCombinerStatus = repmat( ...
        "applied_full_dimensional_identity_preprocessor_for_per_re_irc", n, 1);
    T.MUMIMOReceiveCombinerMatrixSHA256 = T.MUMIMOSpatialFilterMatrixSHA256;
    T.MUMIMOReceiveCombinerInputBranches = T.PhysicalRxAntennas;
    T.MUMIMOReceiveCombinerOutputBranches = T.PhysicalRxAntennas;
    T.MUMIMOReceiveCombinerInterferenceProjected = true(n, 1);
    T.MUMIMOReceiveCombinerFullObservationPreserved = true(n, 1);
    T.MUMIMOReceiveCombinerIdentityResidual = zeros(n, 1);
end
T.InterferenceMode = repmat("shared_slot_waveform_superposition", n, 1);
T.InterferenceContributorCount = ones(n, 1);
T.PRBStart = zeros(n, 1);
T.PRBCount = repmat(12, n, 1);
T.SymbolStart = repmat(2, n, 1);
T.NumSymbols = repmat(10, n, 1);
end

function T = localFullElementRows(direction)
T = localRank2Rows(direction);
if upper(string(direction)) == "UL"
    T.NumTxPorts = repmat(2,height(T),1);
    T.NumRxAntennas = repmat(64,height(T),1);
    T.TxWaveformColumns = repmat(4,height(T),1);
    T.PhysicalTxAntennas = repmat(4,height(T),1);
    T.RxWaveformBranches = repmat(64,height(T),1);
    T.PhysicalRxAntennas = repmat(64,height(T),1);
else
    T.NumTxPorts = repmat(4,height(T),1);
    T.NumRxAntennas = repmat(4,height(T),1);
    T.TxWaveformColumns = repmat(64,height(T),1);
    T.PhysicalTxAntennas = repmat(64,height(T),1);
    T.RxWaveformBranches = repmat(4,height(T),1);
    T.PhysicalRxAntennas = repmat(4,height(T),1);
end
T.PrecodingNumLayers = repmat(2,height(T),1);
T.BSAntennaElements = repmat(64,height(T),1);
T.BSAntennaNumPorts = repmat(4,height(T),1);
T.UEAntennaElements = repmat(4,height(T),1);
T.UEAntennaNumPorts = repmat(4,height(T),1);
T.AntennaRuntimeObjectCreated = true(height(T),1);
T.ChannelUsesSameRuntimeAntennaAssumptions = true(height(T),1);
end
