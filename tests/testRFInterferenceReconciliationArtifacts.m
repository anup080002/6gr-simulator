function ok = testRFInterferenceReconciliationArtifacts()
%TESTRFINTERFERENCERECONCILIATIONARTIFACTS Guard Phase 7 RF evidence wiring.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
sixgr.util.ensureFolder(fullfile(tmp, "reports", "json"));
sixgr.util.jsonWrite(fullfile(tmp, "reports", "json", "scenario_manifest.json"), ...
    struct("Fixture", "rf_interference_reconciliation"));

cfg = localScenarioConfig();
cfg.run = rmfield(cfg.run, "noise_operating_mode");
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
rawTrials = struct("DL", localTrialTable("DL"), "UL", localTrialTable("UL"));
mobilityArtifacts = struct("Resolution", localMobilityResolution());

artifacts = sixgr.analytics.writeRFInterferenceReconciliation(cfg, tmp, rawTrials, mobilityArtifacts, struct());
assert(isstruct(artifacts) && isfield(artifacts, "Tables"), "Writer must return artifact tables.");

required = [
    "noise_reconciliation.csv", "NoiseReconciliationOk"
    "interference_accounting.csv", "InterferenceAccountingOk"
    "rf_chain_definition.csv", "RfChainDefinitionOk"
    "cfo_reconciliation.csv", "CfoConfiguredAppliedOk"
    "phase_noise_reconciliation.csv", "PhaseNoiseConfiguredAppliedOk"
    "timing_offset_reconciliation.csv", "TimingOffsetConfiguredAppliedOk"
    "iq_imbalance_reconciliation.csv", "IqImbalanceConfiguredAppliedOk"
    "pa_reconciliation.csv", "PaConfiguredAppliedOk"
    "evm_reconciliation.csv", "EvmReconciliationOk"
    "papr_reconciliation.csv", "PaprReconciliationOk"
    "channel_rf_reconciliation.csv", "ChannelRfConfiguredVsAppliedOk"
    "mimo_kpi_reconciliation.csv", "MimoKpiReconciliationOk"
    "mobility_kpi_reconciliation.csv", "MobilityKpiReconciliationOk"
    "scheduler_kpi_reconciliation.csv", "SchedulerKpiReconciliationOk"
    ];
for i = 1:size(required, 1)
    path = fullfile(tmp, "reports", "csv", required(i, 1));
    assert(exist(path, "file") == 2, "Missing reconciliation CSV: %s", required(i, 1));
    T = readtable(path, "VariableNamingRule", "preserve", "TextType", "string");
    assert(height(T) >= 1, "Reconciliation CSV must contain an audit row: %s", required(i, 1));
    flag = required(i, 2);
    assert(ismember(flag, string(T.Properties.VariableNames)), ...
        "Reconciliation CSV %s missing flag %s.", required(i, 1), flag);
    assert(all(localAsLogical(T.(char(flag)))), ...
        "Reconciliation flag did not pass for fixture: %s", flag);
    if required(i, 1) == "noise_reconciliation.csv"
        assert(all(string(T.NoiseOperatingMode) == "standalone_awgn_snr_argument"), ...
            "Noise reconciliation must honor the canonical camel-case runtime noise mode.");
        assert(all(contains(string(T.EvidenceSource), "standalone_awgn_snr_argument")), ...
            "Noise evidence source must identify the configured operating mode.");
    elseif required(i, 1) == "cfo_reconciliation.csv"
        assert(all(~localAsLogical(T.CFOEstimationRequired)) && ...
            all(string(T.CFOEstimationStatus) == "not_applicable_disabled_zero_cfo_identity"), ...
            "Disabled zero-CFO identity paths must not require fabricated estimator outputs.");
    elseif required(i, 1) == "evm_reconciliation.csv"
        assert(all(string(T.EVMThresholdEvaluationStatus) == "not_applicable_no_yaml_campaign_limit"), ...
            "EVM must not use a hidden universal threshold when YAML provides no campaign limit.");
    elseif required(i, 1) == "papr_reconciliation.csv"
        assert(all(string(T.PAPRThresholdEvaluationStatus) == "not_applicable_no_yaml_campaign_limit"), ...
            "PAPR must not use a hidden universal threshold when YAML provides no campaign limit.");
    elseif required(i, 1) == "mimo_kpi_reconciliation.csv"
        assert(all(double(T.AchievedDL_RI_mean) == 2) && all(double(T.AchievedUL_RI_mean) == 2), ...
            "MIMO reconciliation must use executed Rank/Layers, not the recommended RankIndicator.");
        assert(all(localAsLogical(T.DL_MCSProfileExactOk)) && all(localAsLogical(T.UL_MCSProfileExactOk)), ...
            "MIMO reconciliation must verify applied modulation/code rate against the configured TS 38.214 MCS table.");
        assert(all(double(T.DL_PhysicalAntennaExactFraction) == 1) && ...
            all(double(T.UL_PhysicalAntennaExactFraction) == 1), ...
            "MIMO reconciliation must verify the physical DL/UL antenna dimensions on every raw waveform row.");
    end
end

% Explicitly disabled interference is not missing evidence.  It is a
% runtime-observed identity only when every trial says none, has zero
% contributors, no finite aggregate power/source and no interferer truth.
disabledCfg = cfg;
disabledCfg.interference.inter_cell_execution_mode = "none";
disabledCfg.interference.inter_cell_interference_flag = false;
disabledCfg.interference.intra_cell_interference_flag = false;
disabledCfg.interference.mu_mimo_interference_flag = false;
disabledTrials = struct("DL", localDisabledTrialTable("DL"), ...
    "UL", localDisabledTrialTable("UL"));
% A populated reference-plane status must not turn missing aggregate power
% into an active interference source during live-table canonicalization.
% This mirrors the persisted no-interference TDD/FDD waveform rows.
for direction = ["DL", "UL"]
    scope = lower(direction) + "_pdsch_trials";
    if direction == "UL"
        scope = "ul_pusch_trials";
    end
    candidate = disabledTrials.(char(direction));
    candidate.InterferencePowerReferencePlane = repmat( ...
        "not_recorded_for_configured_off_interference", height(candidate), 1);
    candidate = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, candidate);
    expectedSource = "not_emitted_by_active_" + scope + "_runtime";
    assert(all(string(candidate.InterferencePowerSource) == expectedSource), ...
        "Configured-off interference was mislabeled as an active source for %s.", ...
        direction);
    candidate.InterferencePowerSource(:) = ...
        "active_" + scope + "_runtime_table";
    candidate = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, candidate);
    assert(all(string(candidate.InterferencePowerSource) == expectedSource), ...
        "A stale auto-generated active source was not repaired for %s.", ...
        direction);
    candidate.InterferencePowerSource(1) = "unrecognized_nonempty_source";
    candidate = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, candidate);
    assert(string(candidate.InterferencePowerSource(1)) == ...
        "unrecognized_nonempty_source", ...
        "Canonicalization concealed an unrecognized interference source for %s.", ...
        direction);
    candidate.InterferencePowerSource(1) = expectedSource;
    cellCandidate = candidate;
    cellCandidate.InterferenceContributorCount = ...
        num2cell(double(cellCandidate.InterferenceContributorCount));
    cellCandidate.InterferenceAggregatedRxPower_dBm = ...
        num2cell(double(cellCandidate.InterferenceAggregatedRxPower_dBm));
    cellCandidate.InterferencePowerSource(:) = ...
        "active_" + scope + "_runtime_table";
    cellCandidate = sixgr.truth.canonicalizeLLSLiveSignalChainTable( ...
        scope, cellCandidate);
    assert(all(string(cellCandidate.InterferencePowerSource) == expectedSource), ...
        "Cell-valued CSV numerics prevented disabled identity repair for %s.", ...
        direction);
    disabledTrials.(char(direction)) = candidate;
end
disabledRoot = fullfile(tmp, "disabled_identity");
sixgr.analytics.writeRFInterferenceReconciliation(disabledCfg, disabledRoot, ...
    disabledTrials, mobilityArtifacts, struct());
disabledInterference = readtable(fullfile(disabledRoot, "reports", "csv", ...
    "interference_accounting.csv"), "VariableNamingRule", "preserve", "TextType", "string");
assert(all(localAsLogical(disabledInterference.InterferenceAccountingOk)) && ...
    all(localAsLogical(disabledInterference.ObservedDisabledIdentity)) && ...
    all(~localAsLogical(disabledInterference.ConfiguredInterferenceEnabled)) && ...
    all(string(disabledInterference.InterferenceEvaluationStatus) == "disabled_runtime_identity"), ...
    "Configured-off and runtime-off interference must pass as an audited disabled identity.");

% Production trial exporters preserve an explicit source token rather than
% a blank cell when the disabled path emits no waveform contribution.  That
% token is part of the same zero-contributor/NaN-power/false-truth identity.
sentinelDisabledTrials = disabledTrials;
sentinelDisabledTrials.DL.InterferencePowerSource(:) = ...
    "not_emitted_by_active_dl_pdsch_trials_runtime";
sentinelDisabledTrials.UL.InterferencePowerSource(:) = ...
    "not_emitted_by_active_ul_pusch_trials_runtime";
sentinelRoot = fullfile(tmp, "disabled_identity_explicit_source");
sixgr.analytics.writeRFInterferenceReconciliation(disabledCfg, sentinelRoot, ...
    sentinelDisabledTrials, mobilityArtifacts, struct());
sentinelInterference = readtable(fullfile(sentinelRoot, "reports", "csv", ...
    "interference_accounting.csv"), "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(all(localAsLogical(sentinelInterference.InterferenceAccountingOk)) && ...
    all(localAsLogical(sentinelInterference.ObservedDisabledIdentity)), ...
    "Canonical disabled-runtime source sentinels must preserve the audited identity.");

badSourceTrials = sentinelDisabledTrials;
badSourceTrials.DL.InterferencePowerSource(1) = ...
    "unrecognized_nonempty_interference_source";
badSourceRoot = fullfile(tmp, "bad_disabled_source_identity");
sixgr.analytics.writeRFInterferenceReconciliation(disabledCfg, badSourceRoot, ...
    badSourceTrials, mobilityArtifacts, struct());
badSourceInterference = readtable(fullfile(badSourceRoot, "reports", "csv", ...
    "interference_accounting.csv"), "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");
dlBadSource = upper(string(badSourceInterference.Direction)) == "DL";
assert(~localAsLogical(badSourceInterference.InterferenceAccountingOk(dlBadSource)) && ...
    localAsLogical(badSourceInterference.InterferenceAccountingOk(~dlBadSource)), ...
    "An unrecognized nonempty source must fail a disabled interference identity.");

badDisabledTrials = disabledTrials;
badDisabledTrials.DL.InterferenceContributorCount(1) = 1;
badDisabledRoot = fullfile(tmp, "bad_disabled_identity");
sixgr.analytics.writeRFInterferenceReconciliation(disabledCfg, badDisabledRoot, ...
    badDisabledTrials, mobilityArtifacts, struct());
badInterference = readtable(fullfile(badDisabledRoot, "reports", "csv", ...
    "interference_accounting.csv"), "VariableNamingRule", "preserve", "TextType", "string");
dlBad = upper(string(badInterference.Direction)) == "DL";
assert(~localAsLogical(badInterference.InterferenceAccountingOk(dlBad)) && ...
    localAsLogical(badInterference.InterferenceAccountingOk(~dlBad)), ...
    "A nonzero contributor must fail an otherwise disabled interference identity.");

badNoiseTrials = disabledTrials;
badNoiseTrials.DL.NoiseOperatingMode(1) = "receiver_noise_figure_thermal_noise";
badNoiseRoot = fullfile(tmp, "bad_noise_mode");
sixgr.analytics.writeRFInterferenceReconciliation(disabledCfg, badNoiseRoot, ...
    badNoiseTrials, mobilityArtifacts, struct());
badNoise = readtable(fullfile(badNoiseRoot, "reports", "csv", ...
    "noise_reconciliation.csv"), "VariableNamingRule", "preserve", "TextType", "string");
dlBad = upper(string(badNoise.Direction)) == "DL";
assert(~localAsLogical(badNoise.NoiseReconciliationOk(dlBad)) && ...
    localAsLogical(badNoise.NoiseReconciliationOk(~dlBad)), ...
    "Runtime/configured noise-mode mismatch must fail reconciliation for that direction.");

% The only permitted scalar channel/array identity is an exact rank-1,
% 1x1, explicit-AWGN link.  This keeps fixed-reference AWGN honest without
% weakening the per-antenna/per-resource evidence required by fading MIMO.
sisoCfg = cfg;
sisoCfg.scenario.bs.nTxAnt = 1;
sisoCfg.scenario.bs.nRxAnt = 1;
sisoCfg.scenario.ue.nTxAnt = 1;
sisoCfg.scenario.ue.nRxAnt = 1;
sisoCfg.mimo.max_dl_layers = 1;
sisoCfg.mimo.max_ul_layers = 1;
sisoTrials = struct("DL", localScalarAWGNTrialTable("DL"), ...
    "UL", localScalarAWGNTrialTable("UL"));
sisoRoot = fullfile(tmp, "scalar_awgn_siso");
sixgr.analytics.writeRFInterferenceReconciliation(sisoCfg, sisoRoot, ...
    sisoTrials, mobilityArtifacts, struct());
sisoMIMO = readtable(fullfile(sisoRoot, "reports", "csv", ...
    "mimo_kpi_reconciliation.csv"), "VariableNamingRule", "preserve", "TextType", "string");
assert(localAsLogical(sisoMIMO.MimoKpiReconciliationOk(1)) && ...
    string(sisoMIMO.DL_RuntimeArrayEvaluationStatus(1)) == "explicit_awgn_siso_scalar_identity" && ...
    string(sisoMIMO.UL_RuntimeArrayEvaluationStatus(1)) == "explicit_awgn_siso_scalar_identity", ...
    "Exact explicit-AWGN SISO scalar identities must be accepted and labeled narrowly.");

badFadingTrials = sisoTrials;
badFadingTrials.DL.ChannelModel(:) = "CDL-D";
badFadingRoot = fullfile(tmp, "scalar_fading_rejected");
sixgr.analytics.writeRFInterferenceReconciliation(sisoCfg, badFadingRoot, ...
    badFadingTrials, mobilityArtifacts, struct());
badFadingMIMO = readtable(fullfile(badFadingRoot, "reports", "csv", ...
    "mimo_kpi_reconciliation.csv"), "VariableNamingRule", "preserve", "TextType", "string");
assert(~localAsLogical(badFadingMIMO.MimoKpiReconciliationOk(1)) && ...
    ~localAsLogical(badFadingMIMO.DL_RuntimeArrayModelOk(1)), ...
    "A scalar count-only fading channel must never qualify as a runtime MIMO array model.");

proxyInterferenceCfg = cfg;
proxyInterferenceCfg.interference.inter_cell_execution_mode = "explicit_activity_power_sum";
proxyInterferenceTrials = struct("DL", localTrialTable("DL"), "UL", localTrialTable("UL"));
proxyInterferenceTrials.DL.InterferenceMode(:) = "explicit_activity_power_sum";
proxyInterferenceTrials.UL.InterferenceMode(:) = "explicit_activity_power_sum";
proxyInterferenceRoot = fullfile(tmp, "proxy_interference_rejected");
sixgr.analytics.writeRFInterferenceReconciliation(proxyInterferenceCfg, proxyInterferenceRoot, ...
    proxyInterferenceTrials, mobilityArtifacts, struct());
proxyInterference = readtable(fullfile(proxyInterferenceRoot, "reports", "csv", ...
    "interference_accounting.csv"), "VariableNamingRule", "preserve", "TextType", "string");
assert(all(~localAsLogical(proxyInterference.InterferenceAccountingOk)), ...
    "Aggregate/proxy interference modes must never pass waveform-truth reconciliation.");

% Regression: adaptive QPSK/MCS 1 is not an exact match for a nominal
% 256QAM/MCS 20 operating point.  It can satisfy the execution policy only
% when every trial carries the scheduled/applied decision and causal CSI
% lineage.  The two claims must never be collapsed into one boolean.
adaptiveCfg = cfg;
adaptiveCfg.link_adaptation.fixed_or_amc = "amc";
adaptiveCfg.link_adaptation.initial_mcs = 1;
adaptiveCfg.link_adaptation.maximum_mcs = 20;
adaptiveCfg.pdsch.mcs_index = 20;
adaptiveCfg.pdsch.modulation = "256QAM";
adaptiveCfg.pusch.mcs_index = 20;
adaptiveCfg.pusch.modulation = "256QAM";
adaptiveTrials = struct("DL", localAdaptiveTrialTable("DL"), ...
    "UL", localAdaptiveTrialTable("UL"));
sixgr.analytics.writeRFInterferenceReconciliation(adaptiveCfg, tmp, ...
    adaptiveTrials, mobilityArtifacts, struct());
mimo = readtable(fullfile(tmp, "reports", "csv", "mimo_kpi_reconciliation.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(~localAsLogical(mimo.DLConfiguredEffectiveExactOk(1)) && ...
    ~localAsLogical(mimo.ULConfiguredEffectiveExactOk(1)), ...
    "Adaptive operating points must not be mislabeled as exact configured matches.");
assert(localAsLogical(mimo.DLExecutionPolicyOk(1)) && ...
    localAsLogical(mimo.ULExecutionPolicyOk(1)) && ...
    localAsLogical(mimo.MimoKpiReconciliationOk(1)), ...
    "Causally evidenced adaptive decisions must pass the separate execution-policy contract.");

report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);
assert(isfield(report, "Gates"), "Phase 7 report must expose gates.");
gates = readtable(fullfile(tmp, "reports", "csv", "phase7_truth_gates.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
for flag = required(:, 2).'
    assert(ismember(flag, string(gates.Properties.VariableNames)), "Phase 7 gate missing: %s", flag);
    assert(localAsLogical(gates.(char(flag))(1)), "Phase 7 gate did not consume reconciliation CSV: %s", flag);
end

ok = true;
end

function T = localAdaptiveTrialTable(direction)
T = localTrialTable(direction);
n = height(T);
profile = sixgr.link.resolveMCSProfile("qam64_table1", 1);
T.MCS(:) = 1;
T.Modulation(:) = "QPSK";
T.MCSTable(:) = "qam64_table1";
T.TargetCodeRate(:) = double(profile.TargetCodeRate);
T.ScheduledMCS = ones(n, 1);
T.ScheduledModulation = repmat("QPSK", n, 1);
T.LinkAdaptationScheduled = true(n, 1);
T.LinkAdaptationApplied = true(n, 1);
T.MCSSelectionSource = repmat("measured_csi_cqi_scheduler", n, 1);
T.MCSAuthority = repmat("scheduler_decoded_csi_feedback", n, 1);
T.ModulationAuthority = repmat("ts38214_mcs_profile_from_scheduled_mcs", n, 1);
T.AppliedOperatingPointSource = repmat("frozen_scheduler_grant", n, 1);
T.CSIReportId = "csi-report-" + string((1:n).');
T.WidebandCQI = repmat(8, n, 1);
T.CQIDerivedMCS = ones(n, 1);
T.MCSValueStatus = repmat("measured_feedback_adapted", n, 1);
end

function cfg = localScenarioConfig()
cfg = struct();
cfg.global_radio_scope = struct("channel_bandwidth_hz", 100e6, "carrier_frequency_hz", 4e9);
cfg.scenario = struct();
  cfg.scenario.ue = struct("noiseFigure_dB", 7, "nTxAnt", 4, "nRxAnt", 4);
  cfg.scenario.bs = struct("noiseFigure_dB", 5, "nTxAnt", 64, "nRxAnt", 64);
cfg.frame_timing = struct("slot_duration_ms", 0.5);
cfg.run = struct("total_slots", 240, "noise_operating_mode", "receiver_noise_figure_thermal_noise");
cfg.run_control = struct("total_slots", 240);
cfg.simulation = struct("n_slots", 240);
cfg.interference = struct("inter_cell_execution_mode", "full_per_link_channel_waveform_sum");
cfg.mimo = struct("max_dl_layers", 2, "max_ul_layers", 2);
cfg.pdsch = struct("mcs_index", 13, "modulation", "64QAM");
cfg.pusch = struct("mcs_index", 13, "modulation", "64QAM");
cfg.link_adaptation = struct("fixed_or_amc", "fixed", "initial_mcs", 13, "maximum_mcs", 20);
cfg.impairments = struct();
cfg.impairments.oscillator_profile = "lab_clean";
cfg.impairments.dac_quantization_bits = 12;
cfg.impairments.adc_quantization_bits = 12;
cfg.impairments.cfo = struct("enabled", false, "value_hz", 0, "model", "zero_ppm");
cfg.impairments.phase_noise = struct("enabled", false, "model", "none", "psd_floor_dbc_hz", -150);
cfg.impairments.iq_imbalance = struct("enabled", false, "model", "none", ...
    "amplitude_imbalance_db", 0, "phase_imbalance_deg", 0);
cfg.impairments.to = struct("enabled", false, "value_samples", 0, "model", "perfect_timing");
cfg.impairments.pa_nonlinearity = struct("enabled", false, "model", "ideal_linear", ...
    "iip3_dbm", 60, "p1db_dbm", 50);
cfg.mobility = struct("ue_speed_kmh", 100, "user_paths", localUserPaths());
cfg.meta = struct("scenario_id", "rf_interference_reconciliation_fixture");
end

function paths = localUserPaths()
paths = repmat(struct("ue_id", 0, "initial_position_m", [0 0 1.5], ...
    "speed_kmh", 100, "waypoints_m", struct("position_m", [0 3.333333333333 1.5])), 2, 1);
paths(1).ue_id = 1;
paths(2).ue_id = 2;
paths(2).initial_position_m = [10 0 1.5];
paths(2).waypoints_m = struct("position_m", [10 3.333333333333 1.5]);
end

function T = localTrialTable(direction)
n = 6;
slot = (1:n).';
T = table( ...
    repmat(string(direction), n, 1), ...
    slot, floor(slot ./ 20), repmat([1; 2], n / 2, 1), ...
    true(n, 1), false(n, 1), repmat("PASS", n, 1), true(n, 1), ...
    repmat(12000, n, 1), repmat(0.5, n, 1), repmat(13, n, 1), ...
    repmat("64QAM", n, 1), repmat(2, n, 1), repmat([1; 2], n / 2, 1), ...
    repmat(0.045, n, 1), repmat(10.2, n, 1), repmat(12, n, 1), ...
    zeros(n, 1), zeros(n, 1), zeros(n, 1), ...
    zeros(n, 1), zeros(n, 1), zeros(n, 1), ...
    false(n, 1), false(n, 1), repmat("none", n, 1), zeros(n, 1), zeros(n, 1), ...
    false(n, 1), false(n, 1), false(n, 1), false(n, 1), ...
    repmat("full_per_link_channel_waveform_sum", n, 1), repmat(1, n, 1), ...
    repmat(-100, n, 1), repmat("sample_domain_interference_sum", n, 1), true(n, 1), ...
    'VariableNames', {'Direction','Slot','Frame','UEIndex','FinalizedFlag','IsWarmupFrame','Status','CRCPass', ...
    'GoodBits','AirInterfaceTTI_ms','MCS','Modulation','Rank','RankIndicator', ...
    'EVM_rms','PAPR_dB','PostEqSINR_dB', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
    'IQImbalanceConfigured','IQImbalanceApplied','IQImbalanceModel','ConfiguredIQGainImbalance_dB','ConfiguredIQPhaseImbalance_deg', ...
    'PhaseNoiseConfigured','PhaseNoiseApplied','PAEnabled','PAApplied', ...
    'InterferenceMode','InterferenceContributorCount','InterferenceAggregatedRxPower_dBm', ...
    'InterferencePowerSource','FullInterfererChannelTruthUsed'});
T.MCSTable = repmat("qam256_table2", n, 1);
T.TargetCodeRate = repmat(567 / 1024, n, 1);
if upper(string(direction)) == "DL"
    T.PhysicalTxAntennas = repmat(64, n, 1);
    T.PhysicalRxAntennas = repmat(4, n, 1);
else
    T.PhysicalTxAntennas = repmat(4, n, 1);
    T.PhysicalRxAntennas = repmat(64, n, 1);
end
T.ChannelUsesSameRuntimeAntennaAssumptions = true(n, 1);
T.ChannelUsesCountOnlyAntennaModel = false(n, 1);
T.MUMIMOGroupSize = ones(n, 1);
T.MUMIMOEnabled = false(n, 1);
T.NoiseOperatingMode = repmat("standalone_awgn_snr_argument", n, 1);
T.ReceiverInputSampleNoiseVariance = repmat(1e-3, n, 1);
T.PostEqualizationNoiseVariance = repmat(1.1e-3, n, 1);
T.LLRNoiseVariance = repmat(1.1e-3, n, 1);
T.NoiseVarStatus = repmat("OK", n, 1);
T.NoiseVarStrictFailure = false(n, 1);
T.NoiseVarianceSource = repmat("fixture_waveform_awgn_replay", n, 1);
T.AppliedNoiseSNRSource = repmat("occupied_re_signal_energy_over_effective_grid_noise_variance", n, 1);
T.PostEqualizationNoiseVarianceSource = repmat("fixture_post_equalization_variance", n, 1);
T.LLRNoiseVarianceSource = repmat("fixture_soft_demapper_variance", n, 1);
T.ChannelModel = repmat("AWGN", n, 1);
end

function T = localDisabledTrialTable(direction)
T = localTrialTable(direction);
n = height(T);
T.InterferenceMode(:) = "none";
T.InterferenceContributorCount(:) = 0;
T.InterferenceAggregatedRxPower_dBm(:) = NaN;
T.InterferencePowerSource(:) = "";
T.FullInterfererChannelTruthUsed(:) = false;
end

function T = localScalarAWGNTrialTable(direction)
T = localTrialTable(direction);
n = height(T);
T.Rank(:) = 1;
T.RankIndicator(:) = 1;
T.PhysicalTxAntennas(:) = 1;
T.PhysicalRxAntennas(:) = 1;
T.ChannelUsesSameRuntimeAntennaAssumptions(:) = false;
T.ChannelUsesCountOnlyAntennaModel(:) = true;
T.ChannelModel(:) = "AWGN";
T.MUMIMOGroupSize(:) = 1;
T.MUMIMOEnabled(:) = false;
end

function T = localMobilityResolution()
slotMs = 0.5;
slots = 240;
speed = 100 / 3.6;
dist = speed * slots * slotMs / 1e3;
T = table(true, slots, slots * slotMs / 1e3, slots, dist, "full_route_duration_configured", ...
    'VariableNames', {'FullTrajectoryExecutedOk','ConfiguredSlots','ConfiguredDuration_s', ...
    'RequiredTraversalSlots','ActualDistanceTravelled_m','Status'});
end

function tf = localAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok";
end
end
