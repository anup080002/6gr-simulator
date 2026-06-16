function verdict = evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, varargin)
%EVALUATELLSRUNTIMETRUTHCONTRACT Fail closed on missing honest-LLS evidence.

p = inputParser;
p.addParameter("Result", struct());
p.parse(varargin{:});

if nargin < 1 || strlength(string(runFolder)) == 0
    error("sixgr:truth:MissingRunFolder", "A run folder is required for runtime truth contract evaluation.");
end
if nargin < 2
    scfg = struct();
end
if nargin < 3
    cfg = struct();
end

layout = sixgr.report.resultLayout(runFolder);

verdict = struct();
verdict.Ok = true;
verdict.RuntimeTruthContractOk = true;
verdict.RoundtripMismatchCount = 0;
verdict.RequiredRuntimeEvidenceMissingCount = 0;
verdict.StrictTruthFailureCount = 0;
verdict.StrictProxyGuardFailureCount = 0;
verdict.CanonicalArtifactGapCount = 0;
verdict.RoundtripStatusDetails = strings(0, 1);
verdict.DLTrialCount = 0;
verdict.ULTrialCount = 0;
verdict.RequiredDL = false;
verdict.RequiredUL = false;
verdict.Failures = strings(0, 1);

[verdict.RequiredDL, verdict.RequiredUL] = localRequiredDirections(scfg, cfg);
strictTruthRequired = localRequiresStrictRuntimeTruthContract(scfg, cfg);
isPRACHOnly = localIsPRACHOnlyScenario(scfg, cfg);
isPRACHStrict = localIsPRACHStrictScenario(scfg, cfg);
isPDCCHOnly = localIsPDCCHOnlyScenario(scfg, cfg);
isPDCCHStrict = localIsPDCCHStrictScenario(scfg, cfg);
isTRSOnly = localIsTRSOnlyScenario(scfg, cfg);
isTRSStrict = localIsTRSStrictScenario(scfg, cfg);
isSRSOnly = localIsSRSOnlyScenario(scfg, cfg);
isSRSStrict = localIsSRSStrictScenario(scfg, cfg);
isChannelRFOnly = localIsChannelRFOnlyScenario(scfg, cfg);
isChannelRFStrict = localIsChannelRFStrictScenario(scfg, cfg);
isRAOnly = localIsRAOnlyScenario(scfg, cfg);
isPDSCHStudy = localIsPDSCH6GRStudyScenario(scfg, cfg);
isProxyOnlyStudy = localIsProxyOnlyStudyScenario(scfg, cfg);
isControlOnly = isPRACHOnly || isPDCCHOnly || isTRSOnly || isSRSOnly || isChannelRFOnly || isRAOnly;
verdict.ContractApplicability = "applicable";

if isProxyOnlyStudy
    verdict.RequiredDL = false;
    verdict.RequiredUL = false;
    verdict.ContractApplicability = "not_applicable_proxy_only_study";
    verdict.CheckDetails = localProxyOnlyTruthContractDetails(layout);
    verdict.Ok = true;
    verdict.RuntimeTruthContractOk = true;
    localWriteTruthContractArtifacts(layout, runFolder, scfg, cfg, verdict);
    return;
end

if isControlOnly
    verdict.RequiredDL = false;
    verdict.RequiredUL = false;
end

dlTrialsPath = fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv");
ulTrialsPath = fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv");
dlTrials = localReadTable(dlTrialsPath);
ulTrials = localReadTable(ulTrialsPath);
opSummary = struct();
if ~isControlOnly
    try
        opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials);
        verdict.DLTrialCount = localGetNestedDouble(opSummary, ["DL", "SampleCount"], height(dlTrials));
        verdict.ULTrialCount = localGetNestedDouble(opSummary, ["UL", "SampleCount"], height(ulTrials));
    catch ME
        verdict.DLTrialCount = height(dlTrials);
        verdict.ULTrialCount = height(ulTrials);
        verdict = localAddFailure(verdict, "effective_trial_count_summary_failed:" + string(ME.identifier), "evidence");
    end
else
    verdict.DLTrialCount = 0;
    verdict.ULTrialCount = 0;
end

requiredArtifacts = [
    fullfile(layout.ReportCSVDir, "scenario_summary.csv")
    fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv")
    fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv")
    ];
if ~isControlOnly
    requiredArtifacts = [
        requiredArtifacts
        fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv")
        fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv")
        fullfile(layout.ReportCSVDir, "value_source_audit.csv")
        ];
    if isPDSCHStudy
        requiredArtifacts = setdiff(requiredArtifacts, [ ...
            fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv")
            fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv")
            fullfile(layout.ReportCSVDir, "value_source_audit.csv")], 'stable');
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.ReportCSVDir, "pdsch6gr_trial_level_results.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_tb_level_results.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_codeword_level_results.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_layer_mapping_trace.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_fdra_allocations.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_tdra_allocations.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_dmrs_mapping.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_channel_estimation_metrics.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_harq_trace.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_snr.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_band.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_fdra_type.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_tdra_mode.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_dmrs_setting.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_rank.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_summary_by_repetition.csv")
            fullfile(layout.ReportCSVDir, "pdsch6gr_complexity_summary.csv")
            ];
    end
elseif isPRACHOnly
    if isPRACHStrict
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.ControlCSVDir, "prach_config_strict.csv")
            fullfile(layout.ControlCSVDir, "prach_trials.csv")
            fullfile(layout.ControlCSVDir, "prach_detection_candidates.csv")
            fullfile(layout.ControlCSVDir, "prach_restricted_set_mapping.csv")
            fullfile(layout.ControlCSVDir, "prach_root_sequence_budget.csv")
            fullfile(layout.ControlCSVDir, "prach_zcz_cyclic_shift_mapping.csv")
            fullfile(layout.ControlCSVDir, "prach_missed_detection_sweep.csv")
            fullfile(layout.ControlCSVDir, "prach_false_alarm_sweep.csv")
            fullfile(layout.ControlCSVDir, "prach_timing_offset_sweep.csv")
            fullfile(layout.ControlCSVDir, "prach_frequency_offset_sweep.csv")
            fullfile(layout.ControlCSVDir, "prach_collision_trials.csv")
            fullfile(layout.ControlCSVDir, "prach_multi_occasion_trials.csv")
            fullfile(layout.ControlCSVDir, "prach_negative_trials.csv")
            fullfile(layout.ControlCSVDir, "prach_oracle_guard.csv")
            fullfile(layout.ReportDir, "json", "prach_conformance_summary.json")
            fullfile(layout.ReportDir, "json", "prach_toolbox_capabilities.json")
            ];
    else
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.ControlCSVDir, "prach_detection_trials.csv")
            fullfile(layout.ControlCSVDir, "prach_trials.csv")
            fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv")
            fullfile(layout.ReportCSVDir, "initial_access_random_access_outputs.csv")
            fullfile(layout.ReportCSVDir, "prach_summary_by_snr.csv")
            fullfile(layout.ReportCSVDir, "prach_confusion_detection_types.csv")
            fullfile(layout.ReportCSVDir, "prach_timing_error_samples.csv")
            ];
    end
elseif isPDCCHOnly
    runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
    if isPDCCHStrict
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.ControlCSVDir, "pdcch_config_strict.csv")
            fullfile(layout.ControlCSVDir, "pdcch_trials.csv")
            fullfile(layout.ControlCSVDir, "pdcch_candidates.csv")
            fullfile(layout.ControlCSVDir, "pdcch_dci_fields.csv")
            fullfile(layout.ControlCSVDir, "pdcch_grant_validation.csv")
            fullfile(layout.ControlCSVDir, "pdcch_wrong_rnti_trials.csv")
            fullfile(layout.ControlCSVDir, "pdcch_no_signal_trials.csv")
            fullfile(layout.ControlCSVDir, "pdcch_corruption_trials.csv")
            fullfile(layout.ControlCSVDir, "pdcch_false_alarm_sweep.csv")
            fullfile(layout.ControlCSVDir, "pdcch_low_snr_sweep.csv")
            fullfile(layout.ControlCSVDir, "pdcch_oracle_guard.csv")
            fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv")
            fullfile(layout.ReportDir, "json", "pdcch_detection_summary.json")
            fullfile(layout.ReportDir, "json", "pdcch_toolbox_capabilities.json")
            ];
    else
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv")
            fullfile(layout.ReportCSVDir, "pdcch_control_outputs.csv")
            ];
    end
    if runnerProfile == "ctrl6gr_pdcch_study"
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.ReportCSVDir, "pdcch6gr_coreset_map.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_search_space_map.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_reg_index_map.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_cce_reg_map.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_candidate_hash_trace.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_dmrs_locations.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_per_candidate_results.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_per_slot_results.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_snr.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_al.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_mapping.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_repetition.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_coreset_duration.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_frequency_allocation.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_summary_by_mrss_mode.csv")
            fullfile(layout.ReportCSVDir, "pdcch6gr_complexity_summary.csv")
            ];
    end
elseif isTRSOnly
    refCsvDir = fullfile(layout.Root, "reference_signals", "csv");
    if isTRSStrict
        requiredArtifacts = [
            requiredArtifacts
            fullfile(refCsvDir, "trs_config_strict.csv")
            fullfile(refCsvDir, "trs_trials.csv")
            fullfile(refCsvDir, "trs_resource_mapping.csv")
            fullfile(refCsvDir, "trs_detection_metrics.csv")
            fullfile(refCsvDir, "trs_timing_tracking.csv")
            fullfile(refCsvDir, "trs_frequency_tracking.csv")
            fullfile(refCsvDir, "trs_channel_estimation.csv")
            fullfile(refCsvDir, "trs_coverage.csv")
            fullfile(refCsvDir, "trs_negative_trials.csv")
            fullfile(refCsvDir, "trs_low_snr_sweep.csv")
            fullfile(refCsvDir, "trs_timing_offset_sweep.csv")
            fullfile(refCsvDir, "trs_frequency_offset_sweep.csv")
            fullfile(refCsvDir, "trs_oracle_guard.csv")
            fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv")
            fullfile(layout.ReportDir, "json", "trs_detection_summary.json")
            fullfile(layout.ReportDir, "json", "trs_tracking_summary.json")
            fullfile(layout.ReportDir, "json", "trs_toolbox_capabilities.json")
            ];
    else
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv")
            ];
    end
elseif isSRSOnly
    refCsvDir = fullfile(layout.Root, "reference_signals", "csv");
    if isSRSStrict
        requiredArtifacts = [
            requiredArtifacts
            fullfile(refCsvDir, "srs_config_strict.csv")
            fullfile(refCsvDir, "srs_resource_sets.csv")
            fullfile(refCsvDir, "srs_resources.csv")
            fullfile(refCsvDir, "srs_resource_mapping.csv")
            fullfile(refCsvDir, "srs_tx_waveform.csv")
            fullfile(refCsvDir, "srs_rx_extraction.csv")
            fullfile(refCsvDir, "srs_detection_metrics.csv")
            fullfile(refCsvDir, "srs_channel_estimation.csv")
            fullfile(refCsvDir, "srs_coverage.csv")
            fullfile(refCsvDir, "srs_trigger_events.csv")
            fullfile(refCsvDir, "srs_negative_trials.csv")
            fullfile(refCsvDir, "srs_low_snr_sweep.csv")
            fullfile(refCsvDir, "srs_timing_offset_sweep.csv")
            fullfile(refCsvDir, "srs_multi_ue_trials.csv")
            fullfile(refCsvDir, "srs_oracle_guard.csv")
            fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv")
            fullfile(layout.ReportDir, "json", "srs_detection_summary.json")
            fullfile(layout.ReportDir, "json", "srs_coverage_summary.json")
            fullfile(layout.ReportDir, "json", "srs_toolbox_capabilities.json")
            ];
    else
        requiredArtifacts = [
            requiredArtifacts
            fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv")
            ];
    end
elseif isChannelRFOnly
    channelCsvDir = fullfile(layout.Root, "channel", "csv");
    if isChannelRFStrict
        requiredArtifacts = [
            requiredArtifacts
            fullfile(channelCsvDir, "channel_rf_config_strict.csv")
            fullfile(channelCsvDir, "link_geometry.csv")
            fullfile(channelCsvDir, "large_scale_parameters.csv")
            fullfile(channelCsvDir, "channel_realizations.csv")
            fullfile(channelCsvDir, "channel_snapshots.csv")
            fullfile(channelCsvDir, "path_gains.csv")
            fullfile(channelCsvDir, "channel_configured_vs_applied.csv")
            fullfile(layout.InterferenceCSVDir, "interference_topology.csv")
            fullfile(layout.RFCSVDir, "rf_impairment_chain.csv")
            fullfile(layout.RFCSVDir, "thermal_noise_validation.csv")
            fullfile(layout.RFCSVDir, "evm_impairment_measurements.csv")
            fullfile(layout.RFCSVDir, "channel_rf_negative_trials.csv")
            fullfile(layout.RFCSVDir, "channel_rf_oracle_guard.csv")
            fullfile(layout.AirInterfaceCSVDir, "downstream_channel_references.csv")
            fullfile(layout.ReportDir, "json", "channel_rf_toolbox_capabilities.json")
            fullfile(layout.ReportDir, "json", "channel_rf_conformance_summary.json")
            ];
    end
elseif isRAOnly
    requiredArtifacts = [
        requiredArtifacts
        fullfile(layout.ControlCSVDir, "ra_attempts.csv")
        fullfile(layout.ControlCSVDir, "ra_state_transitions.csv")
        fullfile(layout.ControlCSVDir, "msg1_prach_detection.csv")
        fullfile(layout.ControlCSVDir, "msg2_rar_trials.csv")
        fullfile(layout.ControlCSVDir, "msg2_pdcch_candidates.csv")
        fullfile(layout.ControlCSVDir, "msg3_pusch_trials.csv")
        fullfile(layout.ControlCSVDir, "msg4_contention_resolution.csv")
        fullfile(layout.ControlCSVDir, "ra_timer_events.csv")
        fullfile(layout.ControlCSVDir, "ra_oracle_guard.csv")
        ];
end
if verdict.RequiredDL
    requiredArtifacts(end + 1, 1) = dlTrialsPath;
    if strictTruthRequired
        requiredArtifacts(end + 1, 1) = fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv");
    end
end
if verdict.RequiredUL
    requiredArtifacts(end + 1, 1) = ulTrialsPath;
    if strictTruthRequired
        requiredArtifacts(end + 1, 1) = fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv");
    end
end

for ii = 1:numel(requiredArtifacts)
    artifactPath = string(requiredArtifacts(ii));
    if ~isfile(artifactPath)
        verdict.CanonicalArtifactGapCount = verdict.CanonicalArtifactGapCount + 1;
        verdict = localAddFailure(verdict, "missing_required_artifact:" + localRelativePath(runFolder, artifactPath), "artifact");
    elseif endsWith(lower(artifactPath), ".csv")
        artifactTable = localReadTable(artifactPath);
        if isempty(artifactTable) || height(artifactTable) == 0
            verdict.CanonicalArtifactGapCount = verdict.CanonicalArtifactGapCount + 1;
            verdict = localAddFailure(verdict, "empty_required_artifact:" + localRelativePath(runFolder, artifactPath), "artifact");
        end
    end
end

if verdict.RequiredDL && verdict.DLTrialCount <= 0
    verdict = localAddFailure(verdict, "effective_dl_trial_count=0", "evidence");
end
if verdict.RequiredUL && verdict.ULTrialCount <= 0
    verdict = localAddFailure(verdict, "effective_ul_trial_count=0", "evidence");
end

configuredUsers = localScenarioGetDouble(scfg, cfg, "users.n_users", NaN);
if isnan(configuredUsers)
    configuredUsers = localScenarioGetDouble(scfg, cfg, "topology.num_ues", NaN);
end
runtimeMode = localReadTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
if ~isControlOnly && ~isPDSCHStudy && configuredUsers > 0
    if isempty(runtimeMode) || height(runtimeMode) == 0
        verdict = localAddFailure(verdict, "configured_users_missing_runtime_operating_mode_proof", "evidence");
    elseif localHasColumn(runtimeMode, "ConfiguredUsers")
        observedUsers = localTableMaxNumeric(runtimeMode, "ConfiguredUsers", NaN);
        if isnan(observedUsers) || observedUsers <= 0
            verdict = localAddFailure(verdict, "configured_users_runtime_proof_unavailable", "evidence");
        end
    else
        verdict = localAddFailure(verdict, "configured_users_runtime_proof_column_missing", "evidence");
    end
end

if ~isControlOnly && ~isPDSCHStudy
    [proxyFailureCount, proxyFailures] = localRuntimeModeFailures(runtimeMode, scfg, cfg);
    verdict.StrictProxyGuardFailureCount = verdict.StrictProxyGuardFailureCount + proxyFailureCount;
    for ii = 1:numel(proxyFailures)
        verdict = localAddFailure(verdict, proxyFailures(ii), "proxy");
    end
else
    proxyFailureCount = 0;
    proxyFailures = strings(0, 1); %#ok<NASGU>
end

roundtripFiles = [
    fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"), "ConsistencyStatus", "consistent"
    fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv"), "ConsistencyStatus", "consistent"
    ];
if ~isControlOnly && ~isPDSCHStudy
    roundtripFiles = [roundtripFiles; fullfile(layout.ReportCSVDir, "summary_vs_raw_consistency.csv"), "ConsistencyStatus", "consistent"];
    if strictTruthRequired
        roundtripFiles = [roundtripFiles; fullfile(layout.ReportCSVDir, "value_source_audit.csv"), "ConsistencyStatus", "observed"];
    end
end
for ii = 1:size(roundtripFiles, 1)
    artifactPath = roundtripFiles(ii, 1);
    T = localReadTable(artifactPath);
    [badCount, detailText] = localCountBadStatuses(T, roundtripFiles(ii, 2), roundtripFiles(ii, 3));
    verdict.RoundtripMismatchCount = verdict.RoundtripMismatchCount + badCount;
    if badCount > 0
        verdict.RoundtripStatusDetails(end + 1, 1) = localRelativePath(runFolder, artifactPath) + ":" + detailText;
    end
end
if verdict.RoundtripMismatchCount > 0
    verdict = localAddFailure(verdict, "roundtrip_mismatch_count=" + string(verdict.RoundtripMismatchCount), "roundtrip");
end

if ~isControlOnly && ~isPDSCHStudy
    [rawLifecycleStats, rawLifecycleFailures] = localRawLifecycleStats(dlTrials, ulTrials, ...
        verdict.RequiredDL && strictTruthRequired, verdict.RequiredUL && strictTruthRequired);
    for ii = 1:numel(rawLifecycleFailures)
        verdict = localAddFailure(verdict, rawLifecycleFailures(ii), "evidence");
    end

    [ferStats, ferFailures] = localFERScopeStats(layout);
    for ii = 1:numel(ferFailures)
        verdict = localAddFailure(verdict, ferFailures(ii), "evidence");
    end

    [amcStats, amcFailures] = localAMCNamingStats(runtimeMode, dlTrials, ulTrials);
    for ii = 1:numel(amcFailures)
        verdict = localAddFailure(verdict, amcFailures(ii), "evidence");
    end
else
    rawLifecycleStats = struct( ...
        "DLRows", 0, "ULRows", 0, "DLFinalizedRows", NaN, "ULFinalizedRows", NaN, ...
        "DLPartialRows", NaN, "ULPartialRows", NaN, "DLPrimaryOKRows", NaN, ...
        "ULPrimaryOKRows", NaN, "DLPrimaryOKNotFinalizedRows", NaN, ...
        "ULPrimaryOKNotFinalizedRows", NaN, "RawLifecycleOk", true, ...
        "Applicability", localStudyApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly, isPDSCHStudy));
    ferStats = struct( ...
        "FERSummaryRows", NaN, "FERRunScopeRows", NaN, "FERRunScopeIdentityLeakCount", NaN, ...
        "FERRunScopeIdentityOk", true, "FERScopeStatus", localStudyApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly, isPDSCHStudy));
    amcStats = struct( ...
        "AMCNamingOk", true, "RuntimeModeRows", NaN, "DLTrialRows", 0, "ULTrialRows", 0, ...
        "PolicyBooleanCollapseCount", NaN, "AppliedAuthorityMissingCount", NaN, ...
        "RawAuthorityMissingCount", NaN, "Applicability", localStudyApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly, isPDSCHStudy));
end

hiddenDefaultStats = localHiddenDefaultStats(layout);
if double(hiddenDefaultStats.DangerousHiddenFallbackCount) > 0
    verdict = localAddFailure(verdict, "dangerous_hidden_default_count=" + string(hiddenDefaultStats.DangerousHiddenFallbackCount), "evidence");
end

proxyStats = localProxySummaryStats(runtimeMode);
issueRegistryStats = localIssueRegistryStats(layout);
if strictTruthRequired && double(issueRegistryStats.BlockingIssueCount) > 0
    verdict = localAddFailure(verdict, ...
        "active_result_issue_registry_blockers=" + string(issueRegistryStats.BlockingIssueCount) + ...
        ";critical=" + string(issueRegistryStats.ActiveCriticalCount) + ...
        ";high=" + string(issueRegistryStats.ActiveHighCount) + ...
        ";medium=" + string(issueRegistryStats.ActiveMediumCount), ...
        "evidence");
end

sib1Stats = localSIB1EvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(sib1Stats.SIB1Required) && ~logical(sib1Stats.SIB1StrictOk)
    verdict = localAddFailure(verdict, ...
        "sib1_strict_waveform_evidence_missing_or_failing:" + string(sib1Stats.SIB1Status), ...
        "evidence");
end

raStats = localRAEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(raStats.RARequired) && ~logical(raStats.RAStrictOk)
    verdict = localAddFailure(verdict, ...
        "ra_strict_four_step_evidence_missing_or_failing:" + string(raStats.RAStatus), ...
        "evidence");
end

prachStats = localPRACHStrictEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(prachStats.PRACHRequired) && ~logical(prachStats.PRACHStrictOk)
    verdict = localAddFailure(verdict, ...
        "prach_strict_waveform_evidence_missing_or_failing:" + string(prachStats.PRACHStatus), ...
        "evidence");
end

pdcchStats = localPDCCHStrictEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(pdcchStats.PDCCHRequired) && ~logical(pdcchStats.PDCCHStrictOk)
    verdict = localAddFailure(verdict, ...
        "pdcch_strict_waveform_evidence_missing_or_failing:" + string(pdcchStats.PDCCHStatus), ...
        "evidence");
end

trsStats = localTRSStrictEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(trsStats.TRSRequired) && ~logical(trsStats.TRSStrictOk)
    verdict = localAddFailure(verdict, ...
        "trs_strict_waveform_evidence_missing_or_failing:" + string(trsStats.TRSStatus), ...
        "evidence");
end

srsStats = localSRSStrictEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(srsStats.SRSRequired) && ~logical(srsStats.SRSStrictOk)
    verdict = localAddFailure(verdict, ...
        "srs_strict_waveform_evidence_missing_or_failing:" + string(srsStats.SRSStatus), ...
        "evidence");
end

channelRFStats = localChannelRFStrictEvidenceStats(layout, scfg, cfg);
if strictTruthRequired && logical(channelRFStats.ChannelRFRequired) && ~logical(channelRFStats.ChannelRFStrictOk)
    verdict = localAddFailure(verdict, ...
        "channel_rf_configured_applied_evidence_missing_or_failing:" + string(channelRFStats.ChannelRFStatus), ...
        "evidence");
end

[scenarioObjectiveStats, scenarioObjectiveFailures] = localScenarioObjectiveStats(opSummary, scfg, cfg, strictTruthRequired, isControlOnly, isPDSCHStudy);
for ii = 1:numel(scenarioObjectiveFailures)
    verdict = localAddFailure(verdict, scenarioObjectiveFailures(ii), "evidence");
end

verdict.CheckDetails = struct( ...
    "RawLifecycle", rawLifecycleStats, ...
    "FER", ferStats, ...
    "AMC", amcStats, ...
    "HiddenDefaults", hiddenDefaultStats, ...
    "Proxy", proxyStats, ...
    "IssueRegistry", issueRegistryStats, ...
    "SIB1", sib1Stats, ...
    "RandomAccess", raStats, ...
    "PRACH", prachStats, ...
    "PDCCH", pdcchStats, ...
    "TRS", trsStats, ...
    "SRS", srsStats, ...
    "ChannelRF", channelRFStats, ...
    "ScenarioObjective", scenarioObjectiveStats);
verdict.StrictTruthFailureCount = numel(verdict.Failures);
verdict.Ok = verdict.StrictTruthFailureCount == 0;
verdict.RuntimeTruthContractOk = verdict.Ok;
localWriteTruthContractArtifacts(layout, runFolder, scfg, cfg, verdict);
end

function [requiredDL, requiredUL] = localRequiredDirections(scfg, cfg)
direction = lower(strtrim(string(localScenarioGet(scfg, cfg, "simulation.link_direction", "both"))));
if strlength(direction) == 0 || direction == "all"
    direction = "both";
end
requiredDL = any(direction == ["both", "dl", "downlink"]);
requiredUL = any(direction == ["both", "ul", "uplink"]);
end

function tf = localIsPRACHOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = any(runnerProfile == ["prach_detection", "prach_strict_validation"]) || (~isempty(targetCases) && all(targetCases == "prach"));
end

function tf = localIsPRACHStrictScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "prach_strict_validation" || localScenarioHasObjective(scfg, cfg, "prach_strict_validation");
end

function tf = localIsPDCCHOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = any(runnerProfile == ["ctrl6gr_pdcch_study", "pdcch_blind_decode_sweep", "pdcch_strict_validation"]) || ...
    (~isempty(targetCases) && all(targetCases == "pdcch"));
end

function tf = localIsPDCCHStrictScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "pdcch_strict_validation" || localScenarioHasObjective(scfg, cfg, "pdcch_strict_validation");
end

function tf = localIsTRSOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = any(runnerProfile == ["trs_strict_validation", "trs_tracking_validation"]) || ...
    (~isempty(targetCases) && all(targetCases == "trs"));
end

function tf = localIsTRSStrictScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "trs_strict_validation" || localScenarioHasObjective(scfg, cfg, "trs_strict_validation");
end

function tf = localIsSRSOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = runnerProfile == "srs_strict_validation" || (~isempty(targetCases) && all(targetCases == "srs"));
end

function tf = localIsSRSStrictScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "srs_strict_validation" || localScenarioHasObjective(scfg, cfg, "srs_strict_validation");
end

function tf = localIsChannelRFOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = runnerProfile == "channel_rf_strict_validation" || (~isempty(targetCases) && all(targetCases == "channel_rf"));
end

function tf = localIsChannelRFStrictScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "channel_rf_strict_validation" || localScenarioHasObjective(scfg, cfg, "channel_rf_strict_validation");
end

function tf = localIsRAOnlyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
targetCases = string(localScenarioGet(scfg, cfg, "scenario.target_cases", strings(0, 1)));
if iscell(targetCases)
    targetCases = string(targetCases(:));
end
targetCases = lower(strtrim(targetCases(:)));
targetCases = targetCases(strlength(targetCases) > 0);
tf = runnerProfile == "random_access_four_step" || ...
    (~isempty(targetCases) && all(ismember(targetCases, ["ra", "rach", "random_access", "four_step_ra"])));
end

function tf = localIsPDSCH6GRStudyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
tf = runnerProfile == "pdsch6gr_truth_study";
end

function tf = localIsProxyOnlyStudyScenario(scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
sweepBase = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.sweep.base_profile", ""))));
tf = runnerProfile == "ai_benchmark" || (runnerProfile == "generic_sweep" && sweepBase == "ai_benchmark");
end

function details = localProxyOnlyTruthContractDetails(layout)
applicability = "not_applicable_for_proxy_only_ai_benchmark";
details = struct( ...
    "RawLifecycle", struct( ...
        "DLRows", 0, "ULRows", 0, "DLFinalizedRows", NaN, "ULFinalizedRows", NaN, ...
        "DLPartialRows", NaN, "ULPartialRows", NaN, "DLPrimaryOKRows", NaN, ...
        "ULPrimaryOKRows", NaN, "DLPrimaryOKNotFinalizedRows", NaN, ...
        "ULPrimaryOKNotFinalizedRows", NaN, "RawLifecycleOk", true, ...
        "Applicability", applicability), ...
    "FER", struct( ...
        "FERSummaryRows", NaN, "FERRunScopeRows", NaN, "FERRunScopeIdentityLeakCount", NaN, ...
        "FERRunScopeIdentityOk", true, "FERScopeStatus", applicability), ...
    "AMC", struct( ...
        "AMCNamingOk", true, "RuntimeModeRows", NaN, "DLTrialRows", 0, "ULTrialRows", 0, ...
        "PolicyBooleanCollapseCount", NaN, "AppliedAuthorityMissingCount", NaN, ...
        "RawAuthorityMissingCount", NaN, "Applicability", applicability), ...
    "HiddenDefaults", localHiddenDefaultStats(layout), ...
    "Proxy", struct( ...
        "NoProxyPHYOk", false, ...
        "SyntheticBLERFallbackOk", false, ...
        "Applicability", applicability));
end

function label = localControlApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly)
if isPRACHOnly
    label = "not_applicable_for_prach_control_only";
elseif isPDCCHOnly
    label = "not_applicable_for_pdcch_control_only";
elseif isRAOnly
    label = "not_applicable_for_random_access_control_only";
else
    label = "applicable";
end
end

function label = localStudyApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly, isPDSCHStudy)
if isPDSCHStudy
    label = "not_applicable_for_standalone_pdsch_truth_study";
else
    label = localControlApplicabilityLabel(isPRACHOnly, isPDCCHOnly, isRAOnly);
end
end

function tf = localRequiresStrictRuntimeTruthContract(scfg, cfg)
execModel = lower(strtrim(string(localScenarioGet(scfg, cfg, "users.execution_model", ""))));
honestyMode = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.honesty_mode", ""))));
scenarioGroup = lower(strtrim(string(localScenarioGet(scfg, cfg, "meta.scenario_group", ""))));
tags = lower(string(localScenarioGet(scfg, cfg, "meta.tags", strings(0, 1))));
if iscell(tags)
    tags = lower(string(tags(:)));
end
tags = tags(:);
tf = execModel == "slot_coupled_truth" || honestyMode == "strict" || ...
    any(ismember(tags, ["no-proxy", "truth", "strict_truth", "coupled_truth"])) || ...
    any(contains(scenarioGroup, "truth"));
end

function [failureCount, failures] = localRuntimeModeFailures(runtimeMode, scfg, cfg)
failureCount = 0;
failures = strings(0, 1);
if isempty(runtimeMode) || height(runtimeMode) == 0
    failures(end + 1, 1) = "runtime_operating_mode_missing";
    failureCount = failureCount + 1;
    return;
end

if localHasColumn(runtimeMode, "ProxyPHYActive") && any(localColumnBool(runtimeMode, "ProxyPHYActive"))
    failures(end + 1, 1) = "proxy_phy_active_in_runtime_operating_mode";
end
if localHasColumn(runtimeMode, "FallbackUsed") && any(localColumnBool(runtimeMode, "FallbackUsed"))
    failures(end + 1, 1) = "fallback_used_in_runtime_operating_mode";
end
if localHasColumn(runtimeMode, "WaveformPHYActive") && ~all(localColumnBool(runtimeMode, "WaveformPHYActive"))
    failures(end + 1, 1) = "waveform_phy_not_active_for_all_runtime_rows";
end

proxyTokens = ["abstract", "proxy", "lut", "bler", "sinr_to_bler", "fallback"];
for col = ["ExecutionBackend", "PHYMode", "InterferenceMode", "ApproximationMode", "E2EAirModel"]
    if localHasColumn(runtimeMode, col)
        values = lower(string(runtimeMode.(col)));
        values(ismissing(values)) = "";
        for token = proxyTokens
            if any(contains(values, token))
                failures(end + 1, 1) = lower(col) + "_contains_proxy_token:" + token;
                break;
            end
        end
    end
end

interCellEnabled = localScenarioGetBool(scfg, cfg, "interference.inter_cell_interference_enable", false) || ...
    localScenarioGetBool(scfg, cfg, "interference.inter_cell_interference_flag", false);
if interCellEnabled
    if ~localHasColumn(runtimeMode, "InterferenceMode")
        failures(end + 1, 1) = "inter_cell_interference_enabled_but_interference_mode_missing";
    else
        modes = lower(strtrim(string(runtimeMode.InterferenceMode)));
        modes(ismissing(modes)) = "";
        acceptable = modes == "full_per_link_channel_waveform_sum";
        if any(~acceptable)
            failures(end + 1, 1) = "inter_cell_interference_not_waveform_backed";
        end
    end
end

failures = unique(failures, "stable");
failureCount = numel(failures);
end

function T = localReadTable(pathValue)
pathValue = string(pathValue);
if ~isfile(pathValue)
    T = table();
    return;
end
try
    T = readtable(pathValue, ...
        "FileType", "text", ...
        "Delimiter", ",", ...
        "ReadVariableNames", true, ...
        "TextType", "string", ...
        "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function verdict = localAddFailure(verdict, failureText, failureClass)
failureText = string(failureText);
if strlength(failureText) == 0
    return;
end
if ~any(verdict.Failures == failureText)
    verdict.Failures(end + 1, 1) = failureText;
end
if failureClass == "evidence"
    verdict.RequiredRuntimeEvidenceMissingCount = verdict.RequiredRuntimeEvidenceMissingCount + 1;
elseif failureClass == "proxy"
    verdict.StrictProxyGuardFailureCount = verdict.StrictProxyGuardFailureCount + 1;
end
end

function [count, detailText] = localCountBadStatuses(T, statusColumn, expectedPrefix)
count = 0;
detailText = "rows=0";
if isempty(T) || height(T) == 0
    return;
end
statusColumn = string(statusColumn);
if ~localHasColumn(T, statusColumn)
    statusColumn = localResolveStatusColumnAlias(T, statusColumn);
    if strlength(statusColumn) == 0
        count = height(T);
        detailText = "missing_status_column rows=" + string(height(T));
        return;
    end
end
statuses = lower(strtrim(string(T.(statusColumn))));
statuses(ismissing(statuses)) = "";
expectedPrefix = lower(string(expectedPrefix));
if expectedPrefix == "consistent"
    ok = startsWith(statuses, "consistent");
elseif expectedPrefix == "observed"
    ok = statuses == "observed";
else
    ok = statuses == expectedPrefix;
end
count = sum(~ok);
detailText = "status_column=" + statusColumn + " bad=" + string(count) + "/" + string(height(T)) + ...
    " statuses=" + localStatusCountsText(statuses);
end

function text = localStatusCountsText(statuses)
statuses = string(statuses(:));
if isempty(statuses)
    text = "";
    return;
end
values = unique(statuses, "stable");
parts = strings(numel(values), 1);
for ii = 1:numel(values)
    label = values(ii);
    if strlength(label) == 0
        label = "<empty>";
    end
    parts(ii) = label + "=" + string(sum(statuses == values(ii)));
end
text = strjoin(parts, ",");
end

function statusColumn = localResolveStatusColumnAlias(T, requestedColumn)
requestedColumn = lower(string(requestedColumn));
candidates = strings(0, 1);
if requestedColumn == "consistencystatus"
    candidates = ["Status"; "status"; "Consistency"; "consistency_status"];
elseif requestedColumn == "status"
    candidates = ["ConsistencyStatus"; "consistency_status"];
end
statusColumn = "";
if isempty(T) || isempty(candidates)
    return;
end
names = string(T.Properties.VariableNames);
lowerNames = lower(names);
for ii = 1:numel(candidates)
    idx = find(lowerNames == lower(candidates(ii)), 1, "first");
    if ~isempty(idx)
        statusColumn = names(idx);
        return;
    end
end
end

function tf = localHasColumn(T, columnName)
tf = ~isempty(T) && any(string(T.Properties.VariableNames) == string(columnName));
end

function values = localColumnBool(T, columnName)
raw = T.(string(columnName));
if islogical(raw)
    values = raw;
elseif isnumeric(raw)
    values = raw ~= 0 & ~isnan(raw);
else
    values = lower(strtrim(string(raw)));
    values = values == "1" | values == "true" | values == "yes";
end
values = values(:);
end

function values = localColumnNumeric(T, columnName)
raw = T.(string(columnName));
if isnumeric(raw) || islogical(raw)
    values = double(raw);
else
    values = str2double(strtrim(string(raw)));
end
values = values(:);
end

function [stats, failures] = localRawLifecycleStats(dlTrials, ulTrials, requiredDL, requiredUL)
stats = struct( ...
    "DLRows", height(dlTrials), ...
    "ULRows", height(ulTrials), ...
    "DLFinalizedRows", 0, ...
    "ULFinalizedRows", 0, ...
    "DLPartialRows", 0, ...
    "ULPartialRows", 0, ...
    "DLPrimaryOKRows", 0, ...
    "ULPrimaryOKRows", 0, ...
    "DLPrimaryOKNotFinalizedRows", 0, ...
    "ULPrimaryOKNotFinalizedRows", 0, ...
    "RawLifecycleOk", true);
failures = strings(0, 1);
[stats.DLFinalizedRows, stats.DLPartialRows, stats.DLPrimaryOKRows, stats.DLPrimaryOKNotFinalizedRows, dlFailures] = ...
    localDirectionLifecycleStats(dlTrials, "DL", requiredDL);
[stats.ULFinalizedRows, stats.ULPartialRows, stats.ULPrimaryOKRows, stats.ULPrimaryOKNotFinalizedRows, ulFailures] = ...
    localDirectionLifecycleStats(ulTrials, "UL", requiredUL);
failures = [dlFailures(:); ulFailures(:)];
stats.RawLifecycleOk = isempty(failures);
end

function [finalizedRows, partialRows, primaryOKRows, primaryOKNotFinalizedRows, failures] = localDirectionLifecycleStats(T, direction, requiredFlag)
finalizedRows = 0;
partialRows = 0;
primaryOKRows = 0;
primaryOKNotFinalizedRows = 0;
failures = strings(0, 1);
direction = string(direction);
if isempty(T) || height(T) == 0
    if requiredFlag
        failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_no_rows";
    end
    return;
end
requiredColumns = ["RowLifecycleState", "FinalizedFlag", "PartialRowFlag", "PrimaryTruthValueStatus"];
missing = requiredColumns(~arrayfun(@(name) localHasColumn(T, name), requiredColumns));
if ~isempty(missing)
    failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_columns_missing:" + strjoin(missing, "|");
    return;
end
finalized = localColumnBool(T, "FinalizedFlag");
partial = localColumnBool(T, "PartialRowFlag");
primaryOK = strcmpi(strtrim(string(T.PrimaryTruthValueStatus)), "OK");
state = lower(strtrim(string(T.RowLifecycleState)));
finalizedRows = sum(finalized | state == "finalized");
partialRows = sum(partial | state == "partial");
primaryOKRows = sum(primaryOK);
primaryOKNotFinalizedRows = sum(primaryOK & ~(finalized | state == "finalized"));
if requiredFlag && finalizedRows <= 0
    failures(end + 1, 1) = lower(direction) + "_raw_lifecycle_no_finalized_rows";
end
if primaryOKNotFinalizedRows > 0
    failures(end + 1, 1) = lower(direction) + "_primary_truth_rows_not_finalized=" + string(primaryOKNotFinalizedRows);
end
end

function [stats, failures] = localFERScopeStats(layout)
stats = struct( ...
    "FERSummaryRows", 0, ...
    "FERRunScopeRows", 0, ...
    "FERRunScopeIdentityLeakCount", 0, ...
    "FERRunScopeIdentityOk", false, ...
    "FERScopeStatus", "missing");
failures = strings(0, 1);
pathValue = fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv");
T = localReadTable(pathValue);
if isempty(T) || height(T) == 0
    failures(end + 1, 1) = "fer_summary_missing_or_empty";
    return;
end
stats.FERSummaryRows = height(T);
if ~localHasColumn(T, "Scope")
    failures(end + 1, 1) = "fer_summary_scope_column_missing";
    stats.FERScopeStatus = "scope_column_missing";
    return;
end
runMask = strcmpi(strtrim(string(T.Scope)), "run");
stats.FERRunScopeRows = sum(runMask);
if stats.FERRunScopeRows == 0
    failures(end + 1, 1) = "fer_run_scope_rows_missing";
    stats.FERScopeStatus = "run_scope_rows_missing";
    return;
end
identityLeak = false(height(T), 1);
for col = ["UEID", "UEIndex", "RNTI"]
    if localHasColumn(T, col)
        identityLeak = identityLeak | (runMask & localColumnHasFiniteIdentity(T, col));
    end
end
stats.FERRunScopeIdentityLeakCount = sum(identityLeak);
stats.FERRunScopeIdentityOk = stats.FERRunScopeIdentityLeakCount == 0;
stats.FERScopeStatus = string(ternary(stats.FERRunScopeIdentityOk, "ok", "identity_leak"));
if stats.FERRunScopeIdentityLeakCount > 0
    failures(end + 1, 1) = "fer_run_scope_identity_leak_count=" + string(stats.FERRunScopeIdentityLeakCount);
end
end

function values = localColumnHasFiniteIdentity(T, columnName)
raw = T.(string(columnName));
if isnumeric(raw)
    values = isfinite(double(raw));
else
    text = strtrim(string(raw));
    nums = str2double(text);
    values = strlength(text) > 0 & ~strcmpi(text, "nan") & isfinite(nums);
end
values = values(:);
end

function [stats, failures] = localAMCNamingStats(runtimeMode, dlTrials, ulTrials)
stats = struct( ...
    "AMCNamingOk", true, ...
    "RuntimeModeRows", height(runtimeMode), ...
    "DLTrialRows", height(dlTrials), ...
    "ULTrialRows", height(ulTrials), ...
    "PolicyBooleanCollapseCount", 0, ...
    "AppliedAuthorityMissingCount", 0, ...
    "RawAuthorityMissingCount", 0);
failures = strings(0, 1);
if isempty(runtimeMode) || height(runtimeMode) == 0
    failures(end + 1, 1) = "amc_runtime_mode_missing";
    stats.AMCNamingOk = false;
    return;
end
for col = ["ConfiguredMCSSelectionPolicy", "ActualMCSSelectionMode", "RequestedOperatingPointSource", "AppliedOperatingPointSource"]
    if ~localHasColumn(runtimeMode, col)
        failures(end + 1, 1) = "amc_runtime_mode_column_missing:" + col;
    end
end
if localHasColumn(runtimeMode, "ConfiguredMCSSelectionPolicy")
    policy = lower(strtrim(string(runtimeMode.ConfiguredMCSSelectionPolicy)));
    badPolicy = ismember(policy, ["0", "1", "true", "false", "yes", "no"]);
    stats.PolicyBooleanCollapseCount = sum(badPolicy);
    if any(badPolicy)
        failures(end + 1, 1) = "amc_policy_collapsed_to_boolean";
    end
end
if localHasColumn(runtimeMode, "AppliedOperatingPointSource")
    applied = strtrim(string(runtimeMode.AppliedOperatingPointSource));
    stats.AppliedAuthorityMissingCount = sum(strlength(applied) == 0);
    if stats.AppliedAuthorityMissingCount > 0
        failures(end + 1, 1) = "amc_applied_operating_point_source_missing";
    end
end
stats.RawAuthorityMissingCount = localRawAMCMissingCount(dlTrials) + localRawAMCMissingCount(ulTrials);
if stats.RawAuthorityMissingCount > 0
    failures(end + 1, 1) = "raw_trial_amc_authority_missing_count=" + string(stats.RawAuthorityMissingCount);
end
failures = unique(failures, "stable");
stats.AMCNamingOk = isempty(failures);
end

function count = localRawAMCMissingCount(T)
count = 0;
if isempty(T) || height(T) == 0
    return;
end
for col = ["MCSAuthority", "ModulationAuthority", "AppliedOperatingPointSource", "ConfiguredMCSSelectionPolicy"]
    if ~localHasColumn(T, col)
        count = count + height(T);
    else
        count = count + sum(strlength(strtrim(string(T.(col)))) == 0);
    end
end
end

function stats = localHiddenDefaultStats(layout)
stats = struct( ...
    "HardcodedAuditRows", 0, ...
    "HistoricalDangerousHiddenFallbackRows", 0, ...
    "DangerousHiddenFallbackCount", 0, ...
    "HiddenDefaultAuditStatus", "missing");
T = localReadTable(fullfile(layout.ReportCSVDir, "hardcoded_parameter_audit.csv"));
if isempty(T) || height(T) == 0
    return;
end
stats.HardcodedAuditRows = height(T);
classification = lower(strtrim(string(localOptionalColumn(T, "Classification", ""))));
statusAfter = lower(strtrim(string(localOptionalColumn(T, "StatusAfterPatch", ""))));
actionTaken = lower(strtrim(string(localOptionalColumn(T, "ActionTaken", ""))));
dangerous = contains(classification, "dangerous") | contains(classification, "hidden_fallback") | ...
    contains(statusAfter, "dangerous") | contains(statusAfter, "hidden_fallback_unresolved") | ...
    contains(actionTaken, "dangerous_hidden_fallback");
stats.HistoricalDangerousHiddenFallbackRows = sum(dangerous);

resolvedTokens = ["removed", "config_owned", "derived", "explicit", "justified", ...
    "kept_legitimate", "standard_constant", "internal", "resolved", "owned"];
resolved = false(size(statusAfter));
for token = resolvedTokens
    resolved = resolved | contains(statusAfter, token);
end
actionResolvedTokens = ["removed", "moved", "explicit", "derived", "config", "resolved", "yaml"];
for token = actionResolvedTokens
    resolved = resolved | contains(actionTaken, token);
end
unresolvedStatusTokens = ["unresolved", "pending", "todo", "missing", "not_removed", "still_hidden"];
unresolved = false(size(statusAfter));
for token = unresolvedStatusTokens
    unresolved = unresolved | contains(statusAfter, token);
end
unresolvedActionTokens = ["unresolved", "pending", "todo", "not removed", "not_removed", "still hidden", "still_hidden"];
for token = unresolvedActionTokens
    unresolved = unresolved | contains(actionTaken, token);
end

unresolvedDangerous = dangerous & (~resolved | unresolved);
stats.DangerousHiddenFallbackCount = sum(unresolvedDangerous);
if stats.DangerousHiddenFallbackCount == 0
    stats.HiddenDefaultAuditStatus = string(ternary(stats.HistoricalDangerousHiddenFallbackRows == 0, ...
        "no_dangerous_hidden_fallback_rows", "historical_dangerous_hidden_fallbacks_resolved"));
else
    stats.HiddenDefaultAuditStatus = "unresolved_dangerous_hidden_fallback_rows_present";
end
end

function stats = localProxySummaryStats(runtimeMode)
stats = struct( ...
    "RuntimeModeRows", height(runtimeMode), ...
    "ProxyPHYActiveRows", 0, ...
    "FallbackUsedRows", 0, ...
    "NonWaveformPHYRows", 0, ...
    "SyntheticBLERFallbackTokenRows", 0, ...
    "NoProxyPHYOk", false, ...
    "SyntheticBLERFallbackOk", false);
if isempty(runtimeMode) || height(runtimeMode) == 0
    return;
end
if localHasColumn(runtimeMode, "ProxyPHYActive")
    stats.ProxyPHYActiveRows = sum(localColumnBool(runtimeMode, "ProxyPHYActive"));
end
if localHasColumn(runtimeMode, "FallbackUsed")
    stats.FallbackUsedRows = sum(localColumnBool(runtimeMode, "FallbackUsed"));
end
if localHasColumn(runtimeMode, "WaveformPHYActive")
    stats.NonWaveformPHYRows = sum(~localColumnBool(runtimeMode, "WaveformPHYActive"));
end
stats.SyntheticBLERFallbackTokenRows = localTokenRowCount(runtimeMode, ...
    ["ExecutionBackend", "PHYMode", "ApproximationMode", "E2EAirModel"], ...
    ["bler_lut", "bler_db", "sinr_to_bler", "synthetic_bler"]);
stats.NoProxyPHYOk = stats.ProxyPHYActiveRows == 0 && stats.FallbackUsedRows == 0 && stats.NonWaveformPHYRows == 0;
stats.SyntheticBLERFallbackOk = stats.SyntheticBLERFallbackTokenRows == 0;
end

function stats = localIssueRegistryStats(layout)
stats = struct( ...
    "RegistryRows", 0, ...
    "BlockingIssueCount", 0, ...
    "ActiveCriticalCount", 0, ...
    "ActiveHighCount", 0, ...
    "ActiveMediumCount", 0, ...
    "ActiveLowCount", 0, ...
    "BlockingIssueIds", strings(0, 1), ...
    "IssueRegistryStatus", "missing");
T = localReadTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"));
if isempty(T) || height(T) == 0
    return;
end
stats.RegistryRows = height(T);
severity = lower(strtrim(string(localOptionalColumn(T, "severity", ""))));
if all(strlength(severity) == 0)
    severity = lower(strtrim(string(localOptionalColumn(T, "Severity", ""))));
end
status = lower(strtrim(string(localOptionalColumn(T, "issue_status", ""))));
if all(strlength(status) == 0)
    status = lower(strtrim(string(localOptionalColumn(T, "fix_status", ""))));
end
if all(strlength(status) == 0)
    status = lower(strtrim(string(localOptionalColumn(T, "status", ""))));
end
issueIDs = string(localOptionalColumn(T, "issue_id", ""));
if all(strlength(strtrim(issueIDs)) == 0)
    issueIDs = string(localOptionalColumn(T, "IssueID", ""));
end

active = localActiveIssueStatusMask(status);
critical = severity == "critical";
high = severity == "high";
medium = severity == "medium";
low = severity == "low";
blocking = active & (critical | high | medium);
stats.ActiveCriticalCount = sum(active & critical);
stats.ActiveHighCount = sum(active & high);
stats.ActiveMediumCount = sum(active & medium);
stats.ActiveLowCount = sum(active & low);
stats.BlockingIssueCount = sum(blocking);
stats.BlockingIssueIds = unique(strtrim(issueIDs(blocking)), "stable");
stats.BlockingIssueIds = stats.BlockingIssueIds(strlength(stats.BlockingIssueIds) > 0);
if stats.BlockingIssueCount > 0
    stats.IssueRegistryStatus = "active_mandatory_blockers_present";
else
    stats.IssueRegistryStatus = "no_active_mandatory_blockers";
end
end

function mask = localActiveIssueStatusMask(status)
status = lower(strtrim(string(status(:))));
status(ismissing(status)) = "";
resolved = ["", "ok", "fixed", "verified", "closed", "resolved", "not_applicable", ...
    "waived_non_blocking", "non_blocking", "informational", "info"];
mask = ~ismember(status, resolved);
end

function stats = localSIB1EvidenceStats(layout, scfg, cfg)
required = localScenarioGetBool(scfg, cfg, "phy.sib1.enable", false) || ...
    localScenarioHasObjective(scfg, cfg, "cell_search_mib_sib1");
summaryPath = fullfile(layout.ReportCSVDir, "sib1_conformance_summary.csv");
recoveryPath = fullfile(layout.ControlCSVDir, "sib1_recovery_trials.csv");
candidatePath = fullfile(layout.ControlCSVDir, "sib1_pdcch_candidates.csv");
roundtripPath = fullfile(layout.ControlCSVDir, "sib1_asn1_roundtrip.csv");
airPath = fullfile(layout.AirInterfaceCSVDir, "pbch_mib_sib1_trials.csv");
stats = struct( ...
    "SIB1Required", logical(required), ...
    "SIB1StrictOk", false, ...
    "SIB1Status", "not_required", ...
    "SIB1RecoveryRows", 0, ...
    "SIB1CandidateRows", 0, ...
    "SIB1ASN1RoundtripRows", 0, ...
    "SIB1AirInterfaceRows", 0);
if ~required
    return;
end
summaryT = localReadTable(summaryPath);
recoveryT = localReadTable(recoveryPath);
candidateT = localReadTable(candidatePath);
roundtripT = localReadTable(roundtripPath);
airT = localReadTable(airPath);
stats.SIB1RecoveryRows = height(recoveryT);
stats.SIB1CandidateRows = height(candidateT);
stats.SIB1ASN1RoundtripRows = height(roundtripT);
stats.SIB1AirInterfaceRows = height(airT);
if isempty(summaryT) || height(summaryT) == 0
    stats.SIB1Status = "missing_sib1_conformance_summary";
    return;
end
strictOk = localHasColumn(summaryT, "StrictOk") && any(localColumnBool(summaryT, "StrictOk"));
hashOk = localHasColumn(summaryT, "TxPayloadHash") && localHasColumn(summaryT, "RxPayloadHash") && ...
    any(strlength(strtrim(string(summaryT.TxPayloadHash))) > 0 & ...
    string(summaryT.TxPayloadHash) == string(summaryT.RxPayloadHash));
treeOk = localHasColumn(summaryT, "TreeEqual") && any(localColumnBool(summaryT, "TreeEqual"));
artifactsOk = stats.SIB1RecoveryRows > 0 && stats.SIB1CandidateRows > 0 && ...
    stats.SIB1ASN1RoundtripRows > 0 && stats.SIB1AirInterfaceRows > 0;
stats.SIB1StrictOk = strictOk && hashOk && treeOk && artifactsOk;
if stats.SIB1StrictOk
    stats.SIB1Status = "strict_sib1_waveform_evidence_present";
else
    stats.SIB1Status = "strict_sib1_waveform_evidence_incomplete";
end
end

function stats = localRAEvidenceStats(layout, scfg, cfg)
runnerProfile = lower(strtrim(string(localScenarioGet(scfg, cfg, "scenario.runner_profile", ""))));
required = runnerProfile == "random_access_four_step" || ...
    localScenarioHasObjective(scfg, cfg, "random_access_four_step") || ...
    localScenarioHasObjective(scfg, cfg, "four_step_ra") || ...
    localScenarioHasObjective(scfg, cfg, "initial_access_ra");
attemptPath = fullfile(layout.ControlCSVDir, "ra_attempts.csv");
statePath = fullfile(layout.ControlCSVDir, "ra_state_transitions.csv");
msg1Path = fullfile(layout.ControlCSVDir, "msg1_prach_detection.csv");
msg2Path = fullfile(layout.ControlCSVDir, "msg2_rar_trials.csv");
pdcchPath = fullfile(layout.ControlCSVDir, "msg2_pdcch_candidates.csv");
msg3Path = fullfile(layout.ControlCSVDir, "msg3_pusch_trials.csv");
msg4Path = fullfile(layout.ControlCSVDir, "msg4_contention_resolution.csv");
timerPath = fullfile(layout.ControlCSVDir, "ra_timer_events.csv");
oraclePath = fullfile(layout.ControlCSVDir, "ra_oracle_guard.csv");
stats = struct( ...
    "RARequired", logical(required), ...
    "RAStrictOk", false, ...
    "RAStatus", "not_required", ...
    "RAAttemptRows", 0, ...
    "RAStateRows", 0, ...
    "Msg1Rows", 0, ...
    "Msg2Rows", 0, ...
    "Msg2PDCCHCandidateRows", 0, ...
    "Msg3Rows", 0, ...
    "Msg4Rows", 0, ...
    "RATimerRows", 0, ...
    "OracleGuardRows", 0, ...
    "OracleGuardViolationCount", NaN);
if ~required
    return;
end
attemptT = localReadTable(attemptPath);
stateT = localReadTable(statePath);
msg1T = localReadTable(msg1Path);
msg2T = localReadTable(msg2Path);
pdcchT = localReadTable(pdcchPath);
msg3T = localReadTable(msg3Path);
msg4T = localReadTable(msg4Path);
timerT = localReadTable(timerPath);
oracleT = localReadTable(oraclePath);
stats.RAAttemptRows = height(attemptT);
stats.RAStateRows = height(stateT);
stats.Msg1Rows = height(msg1T);
stats.Msg2Rows = height(msg2T);
stats.Msg2PDCCHCandidateRows = height(pdcchT);
stats.Msg3Rows = height(msg3T);
stats.Msg4Rows = height(msg4T);
stats.RATimerRows = height(timerT);
stats.OracleGuardRows = height(oracleT);
if isempty(attemptT) || height(attemptT) == 0
    stats.RAStatus = "missing_ra_attempts";
    return;
end
requiredColumns = ["StrictOk","RACompleted","PreambleDetected","Msg2RARNTIDetected", ...
    "Msg2DCICrcPass","Msg2PDSCHCrcPass","RAPIDMatches","RARULGrantValid", ...
    "Msg3PUSCHCrcPass","Msg4PDCCHCrcPass","Msg4PDSCHCrcPass", ...
    "ContentionIdentityMatches","ProxyUsed","Skipped","ToolboxMissing","UsedOracleFields"];
missing = requiredColumns(~arrayfun(@(c) localHasColumn(attemptT, c), requiredColumns));
if ~isempty(missing)
    stats.RAStatus = "ra_attempts_missing_columns:" + strjoin(missing, "|");
    return;
end
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.OracleGuardViolationCount = double(oracleViolations);
artifactRowsOk = stats.RAStateRows > 0 && stats.Msg1Rows > 0 && stats.Msg2Rows > 0 && ...
    stats.Msg2PDCCHCandidateRows > 0 && stats.Msg3Rows > 0 && stats.Msg4Rows > 0 && ...
    stats.RATimerRows > 0 && stats.OracleGuardRows > 0;
noOracleFieldsUsed = localBlankOrMissingMask(attemptT.UsedOracleFields);
strictRows = localColumnBool(attemptT, "StrictOk") & localColumnBool(attemptT, "RACompleted") & ...
    localColumnBool(attemptT, "PreambleDetected") & localColumnBool(attemptT, "Msg2RARNTIDetected") & ...
    localColumnBool(attemptT, "Msg2DCICrcPass") & localColumnBool(attemptT, "Msg2PDSCHCrcPass") & ...
    localColumnBool(attemptT, "RAPIDMatches") & localColumnBool(attemptT, "RARULGrantValid") & ...
    localColumnBool(attemptT, "Msg3PUSCHCrcPass") & localColumnBool(attemptT, "Msg4PDCCHCrcPass") & ...
    localColumnBool(attemptT, "Msg4PDSCHCrcPass") & localColumnBool(attemptT, "ContentionIdentityMatches") & ...
    ~localColumnBool(attemptT, "ProxyUsed") & ~localColumnBool(attemptT, "Skipped") & ...
    ~localColumnBool(attemptT, "ToolboxMissing") & noOracleFieldsUsed;
stats.RAStrictOk = artifactRowsOk && oracleViolations == 0 && any(strictRows);
if stats.RAStrictOk
    stats.RAStatus = "strict_four_step_ra_waveform_evidence_present";
else
    stats.RAStatus = "strict_four_step_ra_evidence_incomplete";
end
end

function stats = localPRACHStrictEvidenceStats(layout, scfg, cfg)
required = localIsPRACHStrictScenario(scfg, cfg);
configPath = fullfile(layout.ControlCSVDir, "prach_config_strict.csv");
trialPath = fullfile(layout.ControlCSVDir, "prach_trials.csv");
candidatePath = fullfile(layout.ControlCSVDir, "prach_detection_candidates.csv");
mappingPath = fullfile(layout.ControlCSVDir, "prach_restricted_set_mapping.csv");
rootPath = fullfile(layout.ControlCSVDir, "prach_root_sequence_budget.csv");
zczPath = fullfile(layout.ControlCSVDir, "prach_zcz_cyclic_shift_mapping.csv");
missPath = fullfile(layout.ControlCSVDir, "prach_missed_detection_sweep.csv");
falsePath = fullfile(layout.ControlCSVDir, "prach_false_alarm_sweep.csv");
timingPath = fullfile(layout.ControlCSVDir, "prach_timing_offset_sweep.csv");
freqPath = fullfile(layout.ControlCSVDir, "prach_frequency_offset_sweep.csv");
collisionPath = fullfile(layout.ControlCSVDir, "prach_collision_trials.csv");
multiPath = fullfile(layout.ControlCSVDir, "prach_multi_occasion_trials.csv");
negativePath = fullfile(layout.ControlCSVDir, "prach_negative_trials.csv");
oraclePath = fullfile(layout.ControlCSVDir, "prach_oracle_guard.csv");
stats = struct( ...
    "PRACHRequired", logical(required), ...
    "PRACHStrictOk", false, ...
    "PRACHStatus", "not_required", ...
    "PRACHConfigRows", 0, ...
    "PRACHTrialRows", 0, ...
    "PRACHCandidateRows", 0, ...
    "PRACHRestrictedSetRows", 0, ...
    "PRACHRootBudgetRows", 0, ...
    "PRACHZCZRows", 0, ...
    "PRACHMissedDetectionRows", 0, ...
    "PRACHFalseAlarmRows", 0, ...
    "PRACHTimingRows", 0, ...
    "PRACHFrequencyRows", 0, ...
    "PRACHCollisionRows", 0, ...
    "PRACHMultiOccasionRows", 0, ...
    "PRACHNegativeRows", 0, ...
    "PRACHOracleGuardRows", 0, ...
    "PRACHOracleGuardViolationCount", NaN);
if ~required
    return;
end
configT = localReadTable(configPath);
trialT = localReadTable(trialPath);
candidateT = localReadTable(candidatePath);
mappingT = localReadTable(mappingPath);
rootT = localReadTable(rootPath);
zczT = localReadTable(zczPath);
missT = localReadTable(missPath);
falseT = localReadTable(falsePath);
timingT = localReadTable(timingPath);
freqT = localReadTable(freqPath);
collisionT = localReadTable(collisionPath);
multiT = localReadTable(multiPath);
negativeT = localReadTable(negativePath);
oracleT = localReadTable(oraclePath);

stats.PRACHConfigRows = height(configT);
stats.PRACHTrialRows = height(trialT);
stats.PRACHCandidateRows = height(candidateT);
stats.PRACHRestrictedSetRows = height(mappingT);
stats.PRACHRootBudgetRows = height(rootT);
stats.PRACHZCZRows = height(zczT);
stats.PRACHMissedDetectionRows = height(missT);
stats.PRACHFalseAlarmRows = height(falseT);
stats.PRACHTimingRows = height(timingT);
stats.PRACHFrequencyRows = height(freqT);
stats.PRACHCollisionRows = height(collisionT);
stats.PRACHMultiOccasionRows = height(multiT);
stats.PRACHNegativeRows = height(negativeT);
stats.PRACHOracleGuardRows = height(oracleT);

if isempty(configT) || isempty(trialT)
    stats.PRACHStatus = "missing_strict_prach_config_or_trials";
    return;
end
requiredTrialCols = ["StrictOk","ProxyUsed","Skipped","ToolboxMissing","UsedOracleFields", ...
    "TrialType","PreambleIndexMatch","FalseAlarm","MissedDetection","ConfigHash","WaveformHash"];
missingTrialCols = requiredTrialCols(~arrayfun(@(c) localHasColumn(trialT, c), requiredTrialCols));
if ~isempty(missingTrialCols)
    stats.PRACHStatus = "prach_trials_missing_columns:" + strjoin(missingTrialCols, "|");
    return;
end
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.PRACHOracleGuardViolationCount = double(oracleViolations);
artifactRowsOk = stats.PRACHCandidateRows > 0 && stats.PRACHRestrictedSetRows > 0 && ...
    stats.PRACHRootBudgetRows > 0 && stats.PRACHZCZRows > 0 && ...
    stats.PRACHMissedDetectionRows > 0 && stats.PRACHFalseAlarmRows > 0 && ...
    stats.PRACHTimingRows > 0 && stats.PRACHFrequencyRows > 0 && ...
    stats.PRACHCollisionRows > 0 && stats.PRACHMultiOccasionRows > 0 && ...
    stats.PRACHNegativeRows > 0 && stats.PRACHOracleGuardRows > 0;
configOk = localHasColumn(configT, "StrictValid") && any(localColumnBool(configT, "StrictValid"));
rootOk = localHasColumn(rootT, "BudgetOk") && all(localColumnBool(rootT, "BudgetOk"));
mappingOk = localHasColumn(mappingT, "Valid") && any(localColumnBool(mappingT, "Valid"));
zczOk = localHasColumn(zczT, "Valid") && all(localColumnBool(zczT, "Valid"));
missedOk = localHasColumn(missT, "NumMissed") && localHasColumn(missT, "NumDetected") && ...
    localHasColumn(missT, "DetectionProbability") && ...
    any(localColumnNumeric(missT, "NumMissed") > 0) && any(localColumnNumeric(missT, "NumDetected") > 0) && ...
    all(localColumnNumeric(missT, "DetectionProbability") >= 0 & localColumnNumeric(missT, "DetectionProbability") <= 1);
falseAlarmOk = localHasColumn(falseT, "NumFalseAlarms") && localHasColumn(falseT, "FalseAlarmProbability") && ...
    all(localColumnNumeric(falseT, "FalseAlarmProbability") >= 0 & localColumnNumeric(falseT, "FalseAlarmProbability") <= 1);
timingOk = localHasColumn(timingT, "WithinToleranceProbability") && localHasColumn(timingT, "MaxAbsTimingErrorSamples") && ...
    all(localColumnNumeric(timingT, "WithinToleranceProbability") == 1) && ...
    all(isfinite(localColumnNumeric(timingT, "MaxAbsTimingErrorSamples")));
freqOk = localHasColumn(freqT, "Status") && any(strcmpi(strtrim(string(freqT.Status)), "measured")) && ...
    localHasColumn(freqT, "DetectionProbability") && any(localColumnNumeric(freqT, "DetectionProbability") > 0);
collisionOk = localHasColumn(collisionT, "CollisionInjected") && localHasColumn(collisionT, "CollisionDetected") && ...
    any(localColumnBool(collisionT, "CollisionInjected") & localColumnBool(collisionT, "CollisionDetected")) && ...
    localHasColumn(collisionT, "MultiplePreamblesDetected") && any(localColumnBool(collisionT, "MultiplePreamblesDetected"));
multiOk = localHasColumn(multiT, "DetectedOnCorrectOccasion") && all(localColumnBool(multiT, "DetectedOnCorrectOccasion"));
negativeOk = localHasColumn(negativeT, "StrictOk") && localHasColumn(negativeT, "NegativeExpectedOk") && ...
    all(~localColumnBool(negativeT, "StrictOk")) && all(localColumnBool(negativeT, "NegativeExpectedOk"));
positiveMask = string(trialT.TrialType) == "positive_high_snr";
strictPositive = localColumnBool(trialT, "StrictOk") & positiveMask & ...
    localColumnBool(trialT, "PreambleIndexMatch") & ...
    ~localColumnBool(trialT, "FalseAlarm") & ~localColumnBool(trialT, "MissedDetection") & ...
    ~localColumnBool(trialT, "ProxyUsed") & ~localColumnBool(trialT, "Skipped") & ...
    ~localColumnBool(trialT, "ToolboxMissing") & localBlankOrMissingMask(trialT.UsedOracleFields) & ...
    strlength(strtrim(string(trialT.ConfigHash))) > 0 & strlength(strtrim(string(trialT.WaveformHash))) > 0;
oldSimplifiedSuccess = localTokenRowCount(trialT, ["Status","FailureReason"], ...
    "active_but_simplified_waveform_prach_detection_gate") > 0 & any(localColumnBool(trialT, "StrictOk"));
stats.PRACHStrictOk = artifactRowsOk && configOk && rootOk && mappingOk && zczOk && ...
    missedOk && falseAlarmOk && timingOk && freqOk && collisionOk && multiOk && negativeOk && ...
    oracleViolations == 0 && any(strictPositive) && ~oldSimplifiedSuccess;
if stats.PRACHStrictOk
    stats.PRACHStatus = "strict_prach_waveform_evidence_present";
else
    stats.PRACHStatus = "strict_prach_waveform_evidence_incomplete";
end
end

function stats = localPDCCHStrictEvidenceStats(layout, scfg, cfg)
required = localIsPDCCHStrictScenario(scfg, cfg);
configPath = fullfile(layout.ControlCSVDir, "pdcch_config_strict.csv");
trialPath = fullfile(layout.ControlCSVDir, "pdcch_trials.csv");
candidatePath = fullfile(layout.ControlCSVDir, "pdcch_candidates.csv");
dciFieldPath = fullfile(layout.ControlCSVDir, "pdcch_dci_fields.csv");
grantPath = fullfile(layout.ControlCSVDir, "pdcch_grant_validation.csv");
wrongRntiPath = fullfile(layout.ControlCSVDir, "pdcch_wrong_rnti_trials.csv");
noSignalPath = fullfile(layout.ControlCSVDir, "pdcch_no_signal_trials.csv");
corruptionPath = fullfile(layout.ControlCSVDir, "pdcch_corruption_trials.csv");
falsePath = fullfile(layout.ControlCSVDir, "pdcch_false_alarm_sweep.csv");
lowSNRPath = fullfile(layout.ControlCSVDir, "pdcch_low_snr_sweep.csv");
oraclePath = fullfile(layout.ControlCSVDir, "pdcch_oracle_guard.csv");
stats = struct( ...
    "PDCCHRequired", logical(required), ...
    "PDCCHStrictOk", false, ...
    "PDCCHStatus", "not_required", ...
    "PDCCHConfigRows", 0, ...
    "PDCCHTrialRows", 0, ...
    "PDCCHCandidateRows", 0, ...
    "PDCCHDCIFieldRows", 0, ...
    "PDCCHGrantRows", 0, ...
    "PDCCHWrongRNTIRows", 0, ...
    "PDCCHNoSignalRows", 0, ...
    "PDCCHCorruptionRows", 0, ...
    "PDCCHFalseAlarmRows", 0, ...
    "PDCCHLowSNRRows", 0, ...
    "PDCCHOracleGuardRows", 0, ...
    "PDCCHOracleGuardViolationCount", NaN);
if ~required
    return;
end
configT = localReadTable(configPath);
trialT = localReadTable(trialPath);
candidateT = localReadTable(candidatePath);
dciFieldT = localReadTable(dciFieldPath);
grantT = localReadTable(grantPath);
wrongT = localReadTable(wrongRntiPath);
noSignalT = localReadTable(noSignalPath);
corruptionT = localReadTable(corruptionPath);
falseT = localReadTable(falsePath);
lowT = localReadTable(lowSNRPath);
oracleT = localReadTable(oraclePath);

stats.PDCCHConfigRows = height(configT);
stats.PDCCHTrialRows = height(trialT);
stats.PDCCHCandidateRows = height(candidateT);
stats.PDCCHDCIFieldRows = height(dciFieldT);
stats.PDCCHGrantRows = height(grantT);
stats.PDCCHWrongRNTIRows = height(wrongT);
stats.PDCCHNoSignalRows = height(noSignalT);
stats.PDCCHCorruptionRows = height(corruptionT);
stats.PDCCHFalseAlarmRows = height(falseT);
stats.PDCCHLowSNRRows = height(lowT);
stats.PDCCHOracleGuardRows = height(oracleT);

if isempty(configT) || isempty(trialT)
    stats.PDCCHStatus = "missing_strict_pdcch_config_or_trials";
    return;
end
requiredTrialCols = ["StrictOk","NegativeExpectedOk","ProxyUsed","Skipped","ToolboxMissing", ...
    "UsedOracleFields","TrialType","CandidatesAttempted","DCICrcPass","DCIPayloadHashTx", ...
    "DCIPayloadHashRx","DCIPayloadMatch","GrantValid","ConfigHash","DetectionMetric"];
missingTrialCols = requiredTrialCols(~arrayfun(@(c) localHasColumn(trialT, c), requiredTrialCols));
if ~isempty(missingTrialCols)
    stats.PDCCHStatus = "pdcch_trials_missing_columns:" + strjoin(missingTrialCols, "|");
    return;
end
requiredCandidateCols = ["TrialId","CandidateIndex","AggregationLevel","CCEIndex","RNTIAttempted", ...
    "ExpectedRNTI","CrcPass","Metric","SelectedCandidate","RejectedReason"];
missingCandidateCols = requiredCandidateCols(~arrayfun(@(c) localHasColumn(candidateT, c), requiredCandidateCols));
if ~isempty(missingCandidateCols)
    stats.PDCCHStatus = "pdcch_candidates_missing_columns:" + strjoin(missingCandidateCols, "|");
    return;
end
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.PDCCHOracleGuardViolationCount = double(oracleViolations);

artifactRowsOk = stats.PDCCHCandidateRows > 0 && stats.PDCCHDCIFieldRows > 0 && ...
    stats.PDCCHGrantRows > 0 && stats.PDCCHWrongRNTIRows > 0 && stats.PDCCHNoSignalRows > 0 && ...
    stats.PDCCHCorruptionRows > 0 && stats.PDCCHFalseAlarmRows > 0 && stats.PDCCHLowSNRRows > 0 && ...
    stats.PDCCHOracleGuardRows > 0;
configOk = localHasColumn(configT, "StrictValid") && any(localColumnBool(configT, "StrictValid")) && ...
    localHasColumn(configT, "ConfigHash") && any(strlength(strtrim(string(configT.ConfigHash))) > 0);
positiveMask = ismember(string(trialT.TrialType), ["positive_dci_1_0","positive_dci_0_0"]);
positiveOkRows = localColumnBool(trialT, "StrictOk") & positiveMask & ...
    localColumnBool(trialT, "DCICrcPass") & localColumnBool(trialT, "DCIPayloadMatch") & ...
    localColumnBool(trialT, "GrantValid") & localColumnNumeric(trialT, "CandidatesAttempted") > 0 & ...
    string(trialT.DCIPayloadHashTx) == string(trialT.DCIPayloadHashRx) & ...
    strlength(strtrim(string(trialT.ConfigHash))) > 0 & ...
    ~localColumnBool(trialT, "ProxyUsed") & ~localColumnBool(trialT, "Skipped") & ...
    ~localColumnBool(trialT, "ToolboxMissing") & localBlankOrMissingMask(trialT.UsedOracleFields);
positiveOk = sum(positiveOkRows) >= 2 && ...
    any(positiveOkRows & string(trialT.DCIFormatTx) == "1_0") && ...
    any(positiveOkRows & string(trialT.DCIFormatTx) == "0_0");
negativeMask = ismember(string(trialT.TrialType), ["wrong_rnti","no_signal_coreset", ...
    "corrupted_pdcch_symbols","corrupted_pdcch_dmrs","wrong_dci_format","invalid_grant_fields"]);
negativeOk = any(negativeMask) && all(~localColumnBool(trialT(negativeMask, :), "StrictOk")) && ...
    all(localColumnBool(trialT(negativeMask, :), "NegativeExpectedOk"));
wrongOk = localHasColumn(wrongT, "NegativeExpectedOk") && all(localColumnBool(wrongT, "NegativeExpectedOk")) && ...
    localHasColumn(wrongT, "WrongRNTIRejectCount") && any(localColumnNumeric(wrongT, "WrongRNTIRejectCount") > 0);
noSignalOk = localHasColumn(noSignalT, "FalseCandidateCount") && localHasColumn(noSignalT, "NegativeExpectedOk") && ...
    all(localColumnNumeric(noSignalT, "FalseCandidateCount") >= 0) && any(localColumnBool(noSignalT, "NegativeExpectedOk"));
corruptionOk = localHasColumn(corruptionT, "NegativeExpectedOk") && all(localColumnBool(corruptionT, "NegativeExpectedOk"));
falseAlarmOk = localHasColumn(falseT, "FalseAlarmProbability") && localHasColumn(falseT, "NumFalseCandidates") && ...
    all(localColumnNumeric(falseT, "FalseAlarmProbability") >= 0 & localColumnNumeric(falseT, "FalseAlarmProbability") <= 1);
lowSNROk = localHasColumn(lowT, "DetectionProbability") && localHasColumn(lowT, "CrcPassProbability") && ...
    all(localColumnNumeric(lowT, "DetectionProbability") >= 0 & localColumnNumeric(lowT, "DetectionProbability") <= 1) && ...
    all(localColumnNumeric(lowT, "CrcPassProbability") >= 0 & localColumnNumeric(lowT, "CrcPassProbability") <= 1);
dciFieldsOk = localHasColumn(dciFieldT, "Equal") && any(localColumnBool(dciFieldT, "Equal"));
grantOk = localHasColumn(grantT, "Valid") && any(localColumnBool(grantT, "Valid")) && ...
    localHasColumn(grantT, "GrantReferenceId") && any(strlength(strtrim(string(grantT.GrantReferenceId))) > 0);
successMetrics = localColumnNumeric(trialT(positiveOkRows, :), "DetectionMetric");
candidateMetrics = localColumnNumeric(candidateT, "Metric");
oldAllOneMetricOnly = ~isempty(successMetrics) && all(abs(successMetrics - 1) < 1e-12) && ...
    numel(unique(candidateMetrics(isfinite(candidateMetrics)))) <= 1;

stats.PDCCHStrictOk = artifactRowsOk && configOk && positiveOk && negativeOk && wrongOk && ...
    noSignalOk && corruptionOk && falseAlarmOk && lowSNROk && dciFieldsOk && grantOk && ...
    oracleViolations == 0 && ~oldAllOneMetricOnly;
if stats.PDCCHStrictOk
    stats.PDCCHStatus = "strict_pdcch_waveform_blind_decode_evidence_present";
else
    stats.PDCCHStatus = "strict_pdcch_waveform_blind_decode_evidence_incomplete";
end
end

function stats = localTRSStrictEvidenceStats(layout, scfg, cfg)
required = localIsTRSStrictScenario(scfg, cfg);
refCsvDir = fullfile(layout.Root, "reference_signals", "csv");
configPath = fullfile(refCsvDir, "trs_config_strict.csv");
trialPath = fullfile(refCsvDir, "trs_trials.csv");
mappingPath = fullfile(refCsvDir, "trs_resource_mapping.csv");
detectionPath = fullfile(refCsvDir, "trs_detection_metrics.csv");
timingPath = fullfile(refCsvDir, "trs_timing_tracking.csv");
freqPath = fullfile(refCsvDir, "trs_frequency_tracking.csv");
channelPath = fullfile(refCsvDir, "trs_channel_estimation.csv");
coveragePath = fullfile(refCsvDir, "trs_coverage.csv");
negativePath = fullfile(refCsvDir, "trs_negative_trials.csv");
lowPath = fullfile(refCsvDir, "trs_low_snr_sweep.csv");
timingSweepPath = fullfile(refCsvDir, "trs_timing_offset_sweep.csv");
freqSweepPath = fullfile(refCsvDir, "trs_frequency_offset_sweep.csv");
oraclePath = fullfile(refCsvDir, "trs_oracle_guard.csv");
stats = struct( ...
    "TRSRequired", logical(required), ...
    "TRSStrictOk", false, ...
    "TRSStatus", "not_required", ...
    "TRSConfigRows", 0, ...
    "TRSTrialRows", 0, ...
    "TRSResourceMappingRows", 0, ...
    "TRSDetectionRows", 0, ...
    "TRSTimingRows", 0, ...
    "TRSFrequencyRows", 0, ...
    "TRSChannelRows", 0, ...
    "TRSCoverageRows", 0, ...
    "TRSNegativeRows", 0, ...
    "TRSLowSNRRows", 0, ...
    "TRSTimingSweepRows", 0, ...
    "TRSFrequencySweepRows", 0, ...
    "TRSOracleGuardRows", 0, ...
    "TRSOracleGuardViolationCount", NaN);
if ~required
    return;
end
configT = localReadTable(configPath);
trialT = localReadTable(trialPath);
mappingT = localReadTable(mappingPath);
detectionT = localReadTable(detectionPath);
timingT = localReadTable(timingPath);
freqT = localReadTable(freqPath);
channelT = localReadTable(channelPath);
coverageT = localReadTable(coveragePath);
negativeT = localReadTable(negativePath);
lowT = localReadTable(lowPath);
timingSweepT = localReadTable(timingSweepPath);
freqSweepT = localReadTable(freqSweepPath);
oracleT = localReadTable(oraclePath);

stats.TRSConfigRows = height(configT);
stats.TRSTrialRows = height(trialT);
stats.TRSResourceMappingRows = height(mappingT);
stats.TRSDetectionRows = height(detectionT);
stats.TRSTimingRows = height(timingT);
stats.TRSFrequencyRows = height(freqT);
stats.TRSChannelRows = height(channelT);
stats.TRSCoverageRows = height(coverageT);
stats.TRSNegativeRows = height(negativeT);
stats.TRSLowSNRRows = height(lowT);
stats.TRSTimingSweepRows = height(timingSweepT);
stats.TRSFrequencySweepRows = height(freqSweepT);
stats.TRSOracleGuardRows = height(oracleT);

if isempty(configT) || isempty(trialT)
    stats.TRSStatus = "missing_strict_trs_config_or_trials";
    return;
end
requiredTrialCols = ["StrictOk","NegativeExpectedOk","ProxyUsed","Skipped","ToolboxMissing", ...
    "UsedOracleFields","TrialType","ConfigHash","DetectionAttempted","DetectionSuccess", ...
    "TimingTrackingAttempted","TRSTimingEstimateAvailable","EstimatedTimingOffset_samples", ...
    "FrequencyTrackingAttempted","TRSCFOEstimateAvailable","EstimatedCFO_Hz", ...
    "ChannelEstimationAttempted","TRSChannelEstimateAvailable","NMSE_dB","TruthStatus"];
missingTrialCols = requiredTrialCols(~arrayfun(@(c) localHasColumn(trialT, c), requiredTrialCols));
if ~isempty(missingTrialCols)
    stats.TRSStatus = "trs_trials_missing_columns:" + strjoin(missingTrialCols, "|");
    return;
end
artifactRowsOk = stats.TRSResourceMappingRows > 0 && stats.TRSDetectionRows > 0 && ...
    stats.TRSTimingRows > 0 && stats.TRSFrequencyRows > 0 && stats.TRSChannelRows > 0 && ...
    stats.TRSCoverageRows > 0 && stats.TRSNegativeRows > 0 && stats.TRSLowSNRRows > 0 && ...
    stats.TRSTimingSweepRows > 0 && stats.TRSFrequencySweepRows > 0 && stats.TRSOracleGuardRows > 0;
configOk = localHasColumn(configT, "StrictValid") && any(localColumnBool(configT, "StrictValid")) && ...
    localHasColumn(configT, "ImplementationStatus") && any(contains(string(configT.ImplementationStatus), "strict_trs"));
positiveMask = string(trialT.TrialType) == "positive_awgn";
positiveOkRows = localColumnBool(trialT, "StrictOk") & positiveMask & ...
    localColumnBool(trialT, "DetectionAttempted") & localColumnBool(trialT, "DetectionSuccess") & ...
    localColumnBool(trialT, "TimingTrackingAttempted") & localColumnBool(trialT, "TRSTimingEstimateAvailable") & ...
    localColumnBool(trialT, "FrequencyTrackingAttempted") & localColumnBool(trialT, "TRSCFOEstimateAvailable") & ...
    localColumnBool(trialT, "ChannelEstimationAttempted") & localColumnBool(trialT, "TRSChannelEstimateAvailable") & ...
    isfinite(localColumnNumeric(trialT, "EstimatedTimingOffset_samples")) & ...
    isfinite(localColumnNumeric(trialT, "EstimatedCFO_Hz")) & isfinite(localColumnNumeric(trialT, "NMSE_dB")) & ...
    ~localColumnBool(trialT, "ProxyUsed") & ~localColumnBool(trialT, "Skipped") & ...
    ~localColumnBool(trialT, "ToolboxMissing") & localBlankOrMissingMask(trialT.UsedOracleFields) & ...
    strlength(strtrim(string(trialT.ConfigHash))) > 0;
positiveOk = any(positiveOkRows);
negativeOk = localHasColumn(negativeT, "StrictOk") && localHasColumn(negativeT, "NegativeExpectedOk") && ...
    height(negativeT) >= 5 && all(~localColumnBool(negativeT, "StrictOk")) && all(localColumnBool(negativeT, "NegativeExpectedOk"));
attemptCoverageOk = localHasColumn(detectionT, "DetectionAttempted") && all(localColumnBool(detectionT, "DetectionAttempted")) && ...
    localHasColumn(timingT, "TimingTrackingAttempted") && all(localColumnBool(timingT, "TimingTrackingAttempted")) && ...
    localHasColumn(freqT, "FrequencyTrackingAttempted") && all(localColumnBool(freqT, "FrequencyTrackingAttempted")) && ...
    localHasColumn(channelT, "ChannelEstimationAttempted") && all(localColumnBool(channelT, "ChannelEstimationAttempted"));
sweepOk = localHasColumn(lowT, "DetectionProbability") && all(localColumnNumeric(lowT, "DetectionProbability") >= 0 & localColumnNumeric(lowT, "DetectionProbability") <= 1) && ...
    localHasColumn(timingSweepT, "TimingError_samples") && any(isfinite(localColumnNumeric(timingSweepT, "TimingError_samples"))) && ...
    localHasColumn(freqSweepT, "FrequencyError_Hz") && any(isfinite(localColumnNumeric(freqSweepT, "FrequencyError_Hz")));
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.TRSOracleGuardViolationCount = double(oracleViolations);
truthStatusOk = localHasColumn(trialT, "TruthStatus") && all(string(trialT.TruthStatus) == "real_lls_evidence");
stats.TRSStrictOk = artifactRowsOk && configOk && positiveOk && negativeOk && ...
    attemptCoverageOk && sweepOk && oracleViolations == 0 && truthStatusOk;
if stats.TRSStrictOk
    stats.TRSStatus = "strict_trs_waveform_tracking_evidence_present";
else
    stats.TRSStatus = "strict_trs_waveform_tracking_evidence_incomplete";
end
end

function stats = localSRSStrictEvidenceStats(layout, scfg, cfg)
required = localIsSRSStrictScenario(scfg, cfg);
refCsvDir = fullfile(layout.Root, "reference_signals", "csv");
configPath = fullfile(refCsvDir, "srs_config_strict.csv");
resourceSetPath = fullfile(refCsvDir, "srs_resource_sets.csv");
resourcePath = fullfile(refCsvDir, "srs_resources.csv");
mappingPath = fullfile(refCsvDir, "srs_resource_mapping.csv");
txPath = fullfile(refCsvDir, "srs_tx_waveform.csv");
extractionPath = fullfile(refCsvDir, "srs_rx_extraction.csv");
detectionPath = fullfile(refCsvDir, "srs_detection_metrics.csv");
channelPath = fullfile(refCsvDir, "srs_channel_estimation.csv");
coveragePath = fullfile(refCsvDir, "srs_coverage.csv");
triggerPath = fullfile(refCsvDir, "srs_trigger_events.csv");
negativePath = fullfile(refCsvDir, "srs_negative_trials.csv");
lowPath = fullfile(refCsvDir, "srs_low_snr_sweep.csv");
timingSweepPath = fullfile(refCsvDir, "srs_timing_offset_sweep.csv");
multiUEPath = fullfile(refCsvDir, "srs_multi_ue_trials.csv");
oraclePath = fullfile(refCsvDir, "srs_oracle_guard.csv");
trialPath = fullfile(refCsvDir, "srs_trials.csv");
stats = struct( ...
    "SRSRequired", logical(required), ...
    "SRSStrictOk", false, ...
    "SRSStatus", "not_required", ...
    "SRSConfigRows", 0, ...
    "SRSTrialRows", 0, ...
    "SRSResourceSetRows", 0, ...
    "SRSResourceRows", 0, ...
    "SRSResourceMappingRows", 0, ...
    "SRSTxWaveformRows", 0, ...
    "SRSExtractionRows", 0, ...
    "SRSDetectionRows", 0, ...
    "SRSChannelRows", 0, ...
    "SRSCoverageRows", 0, ...
    "SRSTriggerRows", 0, ...
    "SRSNegativeRows", 0, ...
    "SRSLowSNRRows", 0, ...
    "SRSTimingSweepRows", 0, ...
    "SRSMultiUERows", 0, ...
    "SRSOracleGuardRows", 0, ...
    "SRSOracleGuardViolationCount", NaN);
if ~required
    return;
end
configT = localReadTable(configPath);
trialT = localReadTable(trialPath);
resourceSetT = localReadTable(resourceSetPath);
resourceT = localReadTable(resourcePath);
mappingT = localReadTable(mappingPath);
txT = localReadTable(txPath);
extractionT = localReadTable(extractionPath);
detectionT = localReadTable(detectionPath);
channelT = localReadTable(channelPath);
coverageT = localReadTable(coveragePath);
triggerT = localReadTable(triggerPath);
negativeT = localReadTable(negativePath);
lowT = localReadTable(lowPath);
timingSweepT = localReadTable(timingSweepPath);
multiUET = localReadTable(multiUEPath);
oracleT = localReadTable(oraclePath);

stats.SRSConfigRows = height(configT);
stats.SRSTrialRows = height(trialT);
stats.SRSResourceSetRows = height(resourceSetT);
stats.SRSResourceRows = height(resourceT);
stats.SRSResourceMappingRows = height(mappingT);
stats.SRSTxWaveformRows = height(txT);
stats.SRSExtractionRows = height(extractionT);
stats.SRSDetectionRows = height(detectionT);
stats.SRSChannelRows = height(channelT);
stats.SRSCoverageRows = height(coverageT);
stats.SRSTriggerRows = height(triggerT);
stats.SRSNegativeRows = height(negativeT);
stats.SRSLowSNRRows = height(lowT);
stats.SRSTimingSweepRows = height(timingSweepT);
stats.SRSMultiUERows = height(multiUET);
stats.SRSOracleGuardRows = height(oracleT);

if isempty(configT) || isempty(trialT)
    stats.SRSStatus = "missing_strict_srs_config_or_trials";
    return;
end
requiredTrialCols = ["StrictOk","NegativeExpectedOk","ProxyUsed","Skipped","ToolboxMissing", ...
    "UsedOracleFields","TrialType","ConfigHash","DetectionAttempted","DetectionSuccess", ...
    "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
    "ChannelEstimateAttempted","SRSChannelEstimateAvailable","NMSE_dB", ...
    "TimingEstimateAttempted","SRSTimingEstimateAvailable","EstimatedTimingOffsetSamples", ...
    "CoverageRequirement","BandwidthCoverageStatus","FullCarrierClaimValid", ...
    "ConfiguredBandClaimValid","TruthStatus"];
missingTrialCols = requiredTrialCols(~arrayfun(@(c) localHasColumn(trialT, c), requiredTrialCols));
if ~isempty(missingTrialCols)
    stats.SRSStatus = "srs_trials_missing_columns:" + strjoin(missingTrialCols, "|");
    return;
end
artifactRowsOk = stats.SRSResourceSetRows > 0 && stats.SRSResourceRows > 0 && ...
    stats.SRSResourceMappingRows > 0 && stats.SRSTxWaveformRows > 0 && ...
    stats.SRSExtractionRows > 0 && stats.SRSDetectionRows > 0 && ...
    stats.SRSChannelRows > 0 && stats.SRSCoverageRows > 0 && stats.SRSTriggerRows > 0 && ...
    stats.SRSNegativeRows > 0 && stats.SRSLowSNRRows > 0 && stats.SRSTimingSweepRows > 0 && ...
    stats.SRSMultiUERows > 0 && stats.SRSOracleGuardRows > 0;
configOk = localHasColumn(configT, "StrictValid") && any(localColumnBool(configT, "StrictValid")) && ...
    localHasColumn(configT, "ImplementationStatus") && any(contains(string(configT.ImplementationStatus), "strict_srs"));
positiveMask = string(trialT.TrialType) == "positive_awgn";
positiveOkRows = localColumnBool(trialT, "StrictOk") & positiveMask & ...
    localColumnBool(trialT, "DetectionAttempted") & localColumnBool(trialT, "DetectionSuccess") & ...
    localColumnBool(trialT, "ResourceExtractionAttempted") & localColumnBool(trialT, "ResourceExtractionAvailable") & ...
    localColumnBool(trialT, "ChannelEstimateAttempted") & localColumnBool(trialT, "SRSChannelEstimateAvailable") & ...
    localColumnBool(trialT, "TimingEstimateAttempted") & localColumnBool(trialT, "SRSTimingEstimateAvailable") & ...
    localColumnBool(trialT, "ConfiguredBandClaimValid") & localColumnBool(trialT, "FullCarrierClaimValid") & ...
    string(trialT.BandwidthCoverageStatus) == "full_carrier" & ...
    isfinite(localColumnNumeric(trialT, "EstimatedTimingOffsetSamples")) & ...
    isfinite(localColumnNumeric(trialT, "NMSE_dB")) & ...
    ~localColumnBool(trialT, "ProxyUsed") & ~localColumnBool(trialT, "Skipped") & ...
    ~localColumnBool(trialT, "ToolboxMissing") & localBlankOrMissingMask(trialT.UsedOracleFields) & ...
    strlength(strtrim(string(trialT.ConfigHash))) > 0;
positiveOk = any(positiveOkRows);
negativeOk = localHasColumn(negativeT, "StrictOk") && localHasColumn(negativeT, "NegativeExpectedOk") && ...
    height(negativeT) >= 8 && all(~localColumnBool(negativeT, "StrictOk")) && all(localColumnBool(negativeT, "NegativeExpectedOk"));
partialFullGateOk = any(string(negativeT.TrialType) == "partial_band_claimed_full" & ...
    ~localColumnBool(negativeT, "StrictOk") & contains(string(negativeT.FailureReason), "srs_partial_band_claimed_full"));
attemptCoverageOk = localHasColumn(detectionT, "DetectionAttempted") && all(localColumnBool(detectionT, "DetectionAttempted")) && ...
    localHasColumn(channelT, "ChannelEstimateAttempted") && all(localColumnBool(channelT, "ChannelEstimateAttempted")) && ...
    localHasColumn(extractionT, "ExtractionAttempted") && all(localColumnBool(extractionT, "ExtractionAttempted"));
coverageOk = localHasColumn(coverageT, "FullCarrierClaimValid") && any(localColumnBool(coverageT, "FullCarrierClaimValid")) && ...
    localHasColumn(coverageT, "BandwidthCoverageStatus") && any(string(coverageT.BandwidthCoverageStatus) == "full_carrier");
triggerOk = localHasColumn(triggerT, "TriggerValid") && all(localColumnBool(triggerT, "TriggerValid"));
sweepOk = localHasColumn(lowT, "DetectionProbability") && all(localColumnNumeric(lowT, "DetectionProbability") >= 0 & localColumnNumeric(lowT, "DetectionProbability") <= 1) && ...
    localHasColumn(timingSweepT, "WithinToleranceProbability") && all(localColumnNumeric(timingSweepT, "WithinToleranceProbability") >= 0 & localColumnNumeric(timingSweepT, "WithinToleranceProbability") <= 1);
multiUEOk = localHasColumn(multiUET, "CollisionDetected") && any(localColumnBool(multiUET, "CollisionDetected")) && ...
    localHasColumn(multiUET, "OrthogonalityPass") && any(localColumnBool(multiUET, "OrthogonalityPass"));
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.SRSOracleGuardViolationCount = double(oracleViolations);
truthStatusOk = localHasColumn(trialT, "TruthStatus") && all(string(trialT.TruthStatus) == "real_lls_evidence");
stats.SRSStrictOk = artifactRowsOk && configOk && positiveOk && negativeOk && partialFullGateOk && ...
    attemptCoverageOk && coverageOk && triggerOk && sweepOk && multiUEOk && ...
    oracleViolations == 0 && truthStatusOk;
if stats.SRSStrictOk
    stats.SRSStatus = "strict_srs_waveform_channel_sounding_evidence_present";
else
    stats.SRSStatus = "strict_srs_waveform_channel_sounding_evidence_incomplete";
end
end

function stats = localChannelRFStrictEvidenceStats(layout, scfg, cfg)
required = localIsChannelRFStrictScenario(scfg, cfg);
channelCsvDir = fullfile(layout.Root, "channel", "csv");
configPath = fullfile(channelCsvDir, "channel_rf_config_strict.csv");
geometryPath = fullfile(channelCsvDir, "link_geometry.csv");
largeScalePath = fullfile(channelCsvDir, "large_scale_parameters.csv");
realizationPath = fullfile(channelCsvDir, "channel_realizations.csv");
snapshotPath = fullfile(channelCsvDir, "channel_snapshots.csv");
pathGainPath = fullfile(channelCsvDir, "path_gains.csv");
configuredAppliedPath = fullfile(channelCsvDir, "channel_configured_vs_applied.csv");
interferencePath = fullfile(layout.InterferenceCSVDir, "interference_topology.csv");
rfPath = fullfile(layout.RFCSVDir, "rf_impairment_chain.csv");
noisePath = fullfile(layout.RFCSVDir, "thermal_noise_validation.csv");
evmPath = fullfile(layout.RFCSVDir, "evm_impairment_measurements.csv");
negativePath = fullfile(layout.RFCSVDir, "channel_rf_negative_trials.csv");
oraclePath = fullfile(layout.RFCSVDir, "channel_rf_oracle_guard.csv");
downstreamPath = fullfile(layout.AirInterfaceCSVDir, "downstream_channel_references.csv");
stats = struct( ...
    "ChannelRFRequired", logical(required), ...
    "ChannelRFStrictOk", false, ...
    "ChannelRFStatus", "not_required", ...
    "ChannelRFConfigRows", 0, ...
    "ChannelRFGeometryRows", 0, ...
    "ChannelRFLargeScaleRows", 0, ...
    "ChannelRFRealizationRows", 0, ...
    "ChannelRFSnapshotRows", 0, ...
    "ChannelRFPathGainRows", 0, ...
    "ChannelRFConfiguredAppliedRows", 0, ...
    "ChannelRFInterferenceRows", 0, ...
    "ChannelRFRFRows", 0, ...
    "ChannelRFThermalNoiseRows", 0, ...
    "ChannelRFEVMRows", 0, ...
    "ChannelRFNegativeRows", 0, ...
    "ChannelRFDownstreamReferenceRows", 0, ...
    "ChannelRFOracleGuardRows", 0, ...
    "ChannelRFOracleGuardViolationCount", NaN);
if ~required
    return;
end
configT = localReadTable(configPath);
geometryT = localReadTable(geometryPath);
largeScaleT = localReadTable(largeScalePath);
realizationT = localReadTable(realizationPath);
snapshotT = localReadTable(snapshotPath);
pathGainT = localReadTable(pathGainPath);
configuredAppliedT = localReadTable(configuredAppliedPath);
interferenceT = localReadTable(interferencePath);
rfT = localReadTable(rfPath);
noiseT = localReadTable(noisePath);
evmT = localReadTable(evmPath);
negativeT = localReadTable(negativePath);
oracleT = localReadTable(oraclePath);
downstreamT = localReadTable(downstreamPath);

stats.ChannelRFConfigRows = height(configT);
stats.ChannelRFGeometryRows = height(geometryT);
stats.ChannelRFLargeScaleRows = height(largeScaleT);
stats.ChannelRFRealizationRows = height(realizationT);
stats.ChannelRFSnapshotRows = height(snapshotT);
stats.ChannelRFPathGainRows = height(pathGainT);
stats.ChannelRFConfiguredAppliedRows = height(configuredAppliedT);
stats.ChannelRFInterferenceRows = height(interferenceT);
stats.ChannelRFRFRows = height(rfT);
stats.ChannelRFThermalNoiseRows = height(noiseT);
stats.ChannelRFEVMRows = height(evmT);
stats.ChannelRFNegativeRows = height(negativeT);
stats.ChannelRFDownstreamReferenceRows = height(downstreamT);
stats.ChannelRFOracleGuardRows = height(oracleT);

if isempty(configT) || isempty(configuredAppliedT) || isempty(realizationT)
    stats.ChannelRFStatus = "missing_channel_rf_configured_applied_or_realization_tables";
    return;
end

requiredConfiguredCols = ["TrialId","ConfiguredChannelModelType","AppliedChannelModelType", ...
    "ConfiguredAppliedMatch","FeatureConfigured","FeatureApplied","ExpectedOk","StrictOk","TruthStatus","FailureReason"];
missingCols = requiredConfiguredCols(~arrayfun(@(c) localHasColumn(configuredAppliedT, c), requiredConfiguredCols));
if ~isempty(missingCols)
    stats.ChannelRFStatus = "channel_rf_configured_applied_missing_columns:" + strjoin(missingCols, "|");
    return;
end

artifactRowsOk = stats.ChannelRFConfigRows > 0 && stats.ChannelRFGeometryRows > 0 && ...
    stats.ChannelRFLargeScaleRows > 0 && stats.ChannelRFRealizationRows > 0 && ...
    stats.ChannelRFSnapshotRows > 0 && stats.ChannelRFPathGainRows > 0 && ...
    stats.ChannelRFConfiguredAppliedRows > 0 && stats.ChannelRFInterferenceRows > 0 && ...
    stats.ChannelRFRFRows > 0 && stats.ChannelRFThermalNoiseRows > 0 && ...
    stats.ChannelRFEVMRows > 0 && stats.ChannelRFNegativeRows > 0 && ...
    stats.ChannelRFDownstreamReferenceRows > 0 && stats.ChannelRFOracleGuardRows > 0;
configOk = localHasColumn(configT, "ConfigValidationOk") && all(localColumnBool(configT, "ConfigValidationOk")) && ...
    localHasColumn(configT, "ProxyAllowed") && all(~localColumnBool(configT, "ProxyAllowed"));
positiveMask = localColumnBool(configuredAppliedT, "ExpectedOk");
negativeMask = ~positiveMask;
positiveOk = any(positiveMask) && all(localColumnBool(configuredAppliedT(positiveMask, :), "StrictOk")) && ...
    all(localColumnBool(configuredAppliedT(positiveMask, :), "ConfiguredAppliedMatch")) && ...
    all(localColumnBool(configuredAppliedT(positiveMask, :), "FeatureApplied"));
negativeOk = any(negativeMask) && all(~localColumnBool(configuredAppliedT(negativeMask, :), "StrictOk")) && ...
    all(~localColumnBool(configuredAppliedT(negativeMask, :), "ConfiguredAppliedMatch")) && ...
    localHasColumn(negativeT, "NegativeExpectedOk") && all(localColumnBool(negativeT, "NegativeExpectedOk"));
realizationOk = localHasColumn(realizationT, "ChannelRealizationId") && ...
    all(strlength(strtrim(string(realizationT.ChannelRealizationId))) > 0) && ...
    localHasColumn(realizationT, "TruthStatus") && all(string(realizationT.TruthStatus) == "real_lls_evidence") && ...
    any(string(realizationT.ChannelModelType) == "TDL" & localColumnBool(realizationT, "WaveformChanged") & localColumnBool(realizationT, "PathGainsExported")) && ...
    any(string(realizationT.ChannelModelType) == "CDL" & localColumnBool(realizationT, "WaveformChanged") & localColumnBool(realizationT, "PathGainsExported"));
largeScaleOk = localHasColumn(largeScaleT, "AppliedOk") && all(localColumnBool(largeScaleT, "AppliedOk")) && ...
    localHasColumn(largeScaleT, "O2IPenetrationLossDbApplied") && any(localColumnNumeric(largeScaleT, "O2IPenetrationLossDbApplied") > 0);
interferenceOk = localHasColumn(interferenceT, "InterferenceApplied") && all(localColumnBool(interferenceT, "InterferenceApplied")) && ...
    localHasColumn(interferenceT, "ReceivedInterferencePower") && all(localColumnNumeric(interferenceT, "ReceivedInterferencePower") > 0);
rfOk = localHasColumn(rfT, "WaveformChanged") && all(localColumnBool(rfT, "WaveformChanged")) && ...
    localHasColumn(rfT, "RFImpairmentChainId") && all(strlength(strtrim(string(rfT.RFImpairmentChainId))) > 0);
noiseOk = localHasColumn(noiseT, "ThermalNoiseApplied") && all(localColumnBool(noiseT, "ThermalNoiseApplied")) && ...
    localHasColumn(noiseT, "StrictOk") && all(localColumnBool(noiseT, "StrictOk"));
downstreamOk = localHasColumn(downstreamT, "ChannelRealizationId") && localHasColumn(downstreamT, "RFImpairmentChainId") && ...
    localHasColumn(downstreamT, "ReferenceValid") && all(localColumnBool(downstreamT, "ReferenceValid")) && ...
    all(strlength(strtrim(string(downstreamT.ChannelRealizationId))) > 0) && ...
    all(strlength(strtrim(string(downstreamT.RFImpairmentChainId))) > 0);
oracleViolations = 0;
if ~isempty(oracleT) && localHasColumn(oracleT, "Violation")
    oracleViolations = sum(localColumnBool(oracleT, "Violation"));
end
stats.ChannelRFOracleGuardViolationCount = double(oracleViolations);
truthStatusOk = all(string(configuredAppliedT.TruthStatus) == "real_lls_evidence");
stats.ChannelRFStrictOk = artifactRowsOk && configOk && positiveOk && negativeOk && ...
    realizationOk && largeScaleOk && interferenceOk && rfOk && noiseOk && downstreamOk && ...
    oracleViolations == 0 && truthStatusOk;
if stats.ChannelRFStrictOk
    stats.ChannelRFStatus = "strict_channel_rf_configured_applied_evidence_present";
else
    stats.ChannelRFStatus = "strict_channel_rf_configured_applied_evidence_incomplete";
end
end

function tf = localScenarioHasObjective(scfg, cfg, objectiveToken)
objectiveToken = lower(strtrim(string(objectiveToken)));
values = strings(0, 1);
for pathValue = ["scenario.bundle_anchor_cases", "scenario.objectives", "scenario_objectives", ...
        "objectives", "meta.objectives", "validation.objectives"]
    raw = localScenarioGet(scfg, cfg, pathValue, strings(0, 1));
    values = [values; localStringList(raw)]; %#ok<AGROW>
end
if isempty(values)
    tf = false;
    return;
end
values = lower(strtrim(values(:)));
tf = any(values == objectiveToken);
end

function values = localStringList(raw)
if isempty(raw)
    values = strings(0, 1);
elseif isstring(raw)
    values = raw(:);
elseif ischar(raw)
    values = string(raw);
elseif iscell(raw)
    values = strings(numel(raw), 1);
    for ii = 1:numel(raw)
        values(ii) = string(raw{ii});
    end
else
    try
        values = string(raw(:));
    catch
        values = strings(0, 1);
    end
end
end

function [stats, failures] = localScenarioObjectiveStats(opSummary, scfg, cfg, strictTruthRequired, isControlOnly, isPDSCHStudy)
stats = struct( ...
    "Applicability", "not_applicable", ...
    "FixedOperatingPoint", false, ...
    "RequiredConfiguredMatchRate", NaN, ...
    "DLConfiguredMatchRate", NaN, ...
    "ULConfiguredMatchRate", NaN, ...
    "ScenarioObjectiveOk", true);
failures = strings(0, 1);
if ~strictTruthRequired || isControlOnly || isPDSCHStudy || isempty(opSummary)
    return;
end
[isFixed, fixedReason] = localIsFixedOperatingPointScenario(scfg, cfg);
stats.FixedOperatingPoint = isFixed;
stats.Applicability = string(ternary(isFixed, "fixed_operating_point", "adaptive_or_not_fixed"));
if ~isFixed
    return;
end
threshold = localScenarioGetDouble(scfg, cfg, "scenario.required_configured_match_rate", NaN);
if isnan(threshold)
    threshold = localScenarioGetDouble(scfg, cfg, "validation.required_configured_match_rate", NaN);
end
if isnan(threshold)
    threshold = 0.999;
end
stats.RequiredConfiguredMatchRate = threshold;
stats.DLConfiguredMatchRate = localGetNestedDouble(opSummary, ["DL", "ConfiguredMatchRate"], NaN);
stats.ULConfiguredMatchRate = localGetNestedDouble(opSummary, ["UL", "ConfiguredMatchRate"], NaN);

for direction = ["DL", "UL"]
    rate = double(stats.(direction + "ConfiguredMatchRate"));
    sampleCount = localGetNestedDouble(opSummary, [direction, "SampleCount"], 0);
    if sampleCount > 0 && isfinite(rate) && rate + eps < threshold
        failures(end + 1, 1) = lower(direction) + "_configured_effective_match_rate_below_required:" + ...
            "rate=" + string(sprintf("%.6g", rate)) + ...
            ";required=" + string(sprintf("%.6g", threshold)) + ...
            ";policy=" + fixedReason;
    end
end
failures = failures(strlength(failures) > 0);
stats.ScenarioObjectiveOk = isempty(failures);
end

function [tf, reason] = localIsFixedOperatingPointScenario(scfg, cfg)
tokens = lower(strtrim(string([ ...
    localScenarioGet(scfg, cfg, "link_adaptation.fixed_or_amc", ""), ...
    localScenarioGet(scfg, cfg, "phy.linkAdaptation.mode", ""), ...
    localScenarioGet(scfg, cfg, "link_adaptation.pdsch_link_adaptation_policy", ""), ...
    localScenarioGet(scfg, cfg, "link_adaptation.pusch_link_adaptation_policy", ""), ...
    localScenarioGet(scfg, cfg, "phy.linkAdaptation.dlPolicy", ""), ...
    localScenarioGet(scfg, cfg, "phy.linkAdaptation.ulPolicy", ""), ...
    localScenarioGet(scfg, cfg, "mimo.rank_adaptation_policy", ""), ...
    localScenarioGet(scfg, cfg, "phy.linkAdaptation.rankPolicy", "") ...
    ])));
tokens = tokens(strlength(tokens) > 0);
fixedTokens = ["fixed", "fixed_mcs", "configured_fixed", "disabled", "off", "none", "false"];
adaptiveTokens = ["amc", "adaptive", "cqi", "cqi_driven", "baseline", "actual_bler_based"];
tf = any(ismember(tokens, fixedTokens)) && ~any(ismember(tokens, adaptiveTokens));
if tf
    reason = strjoin(tokens, "|");
else
    reason = strjoin(tokens, "|");
end
end

function count = localTokenRowCount(T, columns, tokens)
count = 0;
if isempty(T) || height(T) == 0
    return;
end
mask = false(height(T), 1);
for col = columns
    if ~localHasColumn(T, col)
        continue;
    end
    values = lower(string(T.(col)));
    values(ismissing(values)) = "";
    for token = tokens
        mask = mask | contains(values, lower(string(token)));
    end
end
count = sum(mask);
end

function localWriteTruthContractArtifacts(layout, runFolder, scfg, cfg, verdict)
summaryPath = fullfile(layout.ReportCSVDir, "truth_contract_summary.csv");
failuresPath = fullfile(layout.ReportCSVDir, "truth_contract_failures.csv");
details = sixgr.util.structGet(verdict, "CheckDetails", struct());
raw = sixgr.util.structGet(details, "RawLifecycle", struct());
fer = sixgr.util.structGet(details, "FER", struct());
amc = sixgr.util.structGet(details, "AMC", struct());
hidden = sixgr.util.structGet(details, "HiddenDefaults", struct());
proxy = sixgr.util.structGet(details, "Proxy", struct());
issueRegistry = sixgr.util.structGet(details, "IssueRegistry", struct());
sib1 = sixgr.util.structGet(details, "SIB1", struct());
ra = sixgr.util.structGet(details, "RandomAccess", struct());
prach = sixgr.util.structGet(details, "PRACH", struct());
pdcch = sixgr.util.structGet(details, "PDCCH", struct());
trs = sixgr.util.structGet(details, "TRS", struct());
srs = sixgr.util.structGet(details, "SRS", struct());
channelRF = sixgr.util.structGet(details, "ChannelRF", struct());
scenarioObjective = sixgr.util.structGet(details, "ScenarioObjective", struct());
failures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
failures = failures(:);
[scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg);

summaryT = table( ...
    scenarioID, ...
    runTag, ...
    configHash, ...
    "truth_contract_v1", ...
    "sixgr.truth.evaluateLLSRuntimeTruthContract", ...
    string(sixgr.util.structGet(verdict, "ContractApplicability", "applicable")), ...
    logical(verdict.RuntimeTruthContractOk), ...
    logical(verdict.Ok), ...
    double(verdict.StrictTruthFailureCount), ...
    double(verdict.StrictProxyGuardFailureCount), ...
    double(verdict.CanonicalArtifactGapCount), ...
    double(verdict.RoundtripMismatchCount), ...
    double(verdict.RequiredRuntimeEvidenceMissingCount), ...
    logical(sixgr.util.structGet(proxy, "NoProxyPHYOk", false)), ...
    logical(sixgr.util.structGet(proxy, "SyntheticBLERFallbackOk", false)), ...
    logical(sixgr.util.structGet(raw, "RawLifecycleOk", false)), ...
    double(sixgr.util.structGet(raw, "DLFinalizedRows", NaN)), ...
    double(sixgr.util.structGet(raw, "ULFinalizedRows", NaN)), ...
    double(sixgr.util.structGet(raw, "DLPartialRows", NaN)), ...
    double(sixgr.util.structGet(raw, "ULPartialRows", NaN)), ...
    logical(sixgr.util.structGet(fer, "FERRunScopeIdentityOk", false)), ...
    double(sixgr.util.structGet(fer, "FERRunScopeIdentityLeakCount", NaN)), ...
    logical(sixgr.util.structGet(amc, "AMCNamingOk", false)), ...
    double(sixgr.util.structGet(amc, "PolicyBooleanCollapseCount", NaN)), ...
    string(sixgr.util.structGet(hidden, "HiddenDefaultAuditStatus", "")), ...
    double(sixgr.util.structGet(hidden, "HistoricalDangerousHiddenFallbackRows", NaN)), ...
    double(sixgr.util.structGet(hidden, "DangerousHiddenFallbackCount", NaN)), ...
    string(sixgr.util.structGet(issueRegistry, "IssueRegistryStatus", "")), ...
    double(sixgr.util.structGet(issueRegistry, "RegistryRows", NaN)), ...
    double(sixgr.util.structGet(issueRegistry, "BlockingIssueCount", NaN)), ...
    double(sixgr.util.structGet(issueRegistry, "ActiveCriticalCount", NaN)), ...
    double(sixgr.util.structGet(issueRegistry, "ActiveHighCount", NaN)), ...
    double(sixgr.util.structGet(issueRegistry, "ActiveMediumCount", NaN)), ...
    logical(sixgr.util.structGet(sib1, "SIB1Required", false)), ...
    logical(sixgr.util.structGet(sib1, "SIB1StrictOk", false)), ...
    string(sixgr.util.structGet(sib1, "SIB1Status", "")), ...
    double(sixgr.util.structGet(sib1, "SIB1RecoveryRows", NaN)), ...
    logical(sixgr.util.structGet(ra, "RARequired", false)), ...
    logical(sixgr.util.structGet(ra, "RAStrictOk", false)), ...
    string(sixgr.util.structGet(ra, "RAStatus", "")), ...
    double(sixgr.util.structGet(ra, "RAAttemptRows", NaN)), ...
    double(sixgr.util.structGet(ra, "Msg3Rows", NaN)), ...
    double(sixgr.util.structGet(ra, "Msg4Rows", NaN)), ...
    double(sixgr.util.structGet(ra, "OracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(prach, "PRACHRequired", false)), ...
    logical(sixgr.util.structGet(prach, "PRACHStrictOk", false)), ...
    string(sixgr.util.structGet(prach, "PRACHStatus", "")), ...
    double(sixgr.util.structGet(prach, "PRACHTrialRows", NaN)), ...
    double(sixgr.util.structGet(prach, "PRACHMissedDetectionRows", NaN)), ...
    double(sixgr.util.structGet(prach, "PRACHFalseAlarmRows", NaN)), ...
    double(sixgr.util.structGet(prach, "PRACHOracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(pdcch, "PDCCHRequired", false)), ...
    logical(sixgr.util.structGet(pdcch, "PDCCHStrictOk", false)), ...
    string(sixgr.util.structGet(pdcch, "PDCCHStatus", "")), ...
    double(sixgr.util.structGet(pdcch, "PDCCHTrialRows", NaN)), ...
    double(sixgr.util.structGet(pdcch, "PDCCHOracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(trs, "TRSRequired", false)), ...
    logical(sixgr.util.structGet(trs, "TRSStrictOk", false)), ...
    string(sixgr.util.structGet(trs, "TRSStatus", "")), ...
    double(sixgr.util.structGet(trs, "TRSTrialRows", NaN)), ...
    double(sixgr.util.structGet(trs, "TRSDetectionRows", NaN)), ...
    double(sixgr.util.structGet(trs, "TRSTimingRows", NaN)), ...
    double(sixgr.util.structGet(trs, "TRSFrequencyRows", NaN)), ...
    double(sixgr.util.structGet(trs, "TRSChannelRows", NaN)), ...
    double(sixgr.util.structGet(trs, "TRSOracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(srs, "SRSRequired", false)), ...
    logical(sixgr.util.structGet(srs, "SRSStrictOk", false)), ...
    string(sixgr.util.structGet(srs, "SRSStatus", "")), ...
    double(sixgr.util.structGet(srs, "SRSTrialRows", NaN)), ...
    double(sixgr.util.structGet(srs, "SRSResourceMappingRows", NaN)), ...
    double(sixgr.util.structGet(srs, "SRSDetectionRows", NaN)), ...
    double(sixgr.util.structGet(srs, "SRSChannelRows", NaN)), ...
    double(sixgr.util.structGet(srs, "SRSCoverageRows", NaN)), ...
    double(sixgr.util.structGet(srs, "SRSOracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(channelRF, "ChannelRFRequired", false)), ...
    logical(sixgr.util.structGet(channelRF, "ChannelRFStrictOk", false)), ...
    string(sixgr.util.structGet(channelRF, "ChannelRFStatus", "")), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFRealizationRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFConfiguredAppliedRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFLargeScaleRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFInterferenceRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFRFRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFNegativeRows", NaN)), ...
    double(sixgr.util.structGet(channelRF, "ChannelRFOracleGuardViolationCount", NaN)), ...
    logical(sixgr.util.structGet(scenarioObjective, "ScenarioObjectiveOk", true)), ...
    string(sixgr.util.structGet(scenarioObjective, "Applicability", "")), ...
    double(sixgr.util.structGet(scenarioObjective, "RequiredConfiguredMatchRate", NaN)), ...
    double(sixgr.util.structGet(scenarioObjective, "DLConfiguredMatchRate", NaN)), ...
    double(sixgr.util.structGet(scenarioObjective, "ULConfiguredMatchRate", NaN)), ...
    string(strjoin(failures, "; ")), ...
    string(localRelativePath(runFolder, summaryPath)), ...
    string(localRelativePath(runFolder, failuresPath)), ...
    'VariableNames', {'ScenarioID','RunTag','ConfigHash','TruthContractVersion','StatusAuthority', ...
    'ContractApplicability','RuntimeTruthContractOk','ResultOk','StrictTruthFailureCount','StrictProxyGuardFailureCount', ...
    'CanonicalArtifactGapCount','RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'NoProxyPHYOk','SyntheticBLERFallbackOk','RawLifecycleOk','DLFinalizedRows','ULFinalizedRows', ...
    'DLPartialRows','ULPartialRows','FERRunScopeIdentityOk','FERRunScopeIdentityLeakCount', ...
    'AMCNamingOk','AMCPolicyBooleanCollapseCount','HiddenDefaultAuditStatus','HistoricalDangerousHiddenFallbackRows','DangerousHiddenFallbackCount', ...
    'IssueRegistryStatus','IssueRegistryRows','ActiveMandatoryIssueCount','ActiveCriticalIssueCount','ActiveHighIssueCount','ActiveMediumIssueCount', ...
    'SIB1Required','SIB1StrictOk','SIB1EvidenceStatus','SIB1RecoveryRows', ...
    'RARequired','RAStrictOk','RAEvidenceStatus','RAAttemptRows','RAMsg3Rows','RAMsg4Rows','RAOracleGuardViolationCount', ...
    'PRACHRequired','PRACHStrictOk','PRACHEvidenceStatus','PRACHTrialRows','PRACHMissedDetectionRows','PRACHFalseAlarmRows','PRACHOracleGuardViolationCount', ...
    'PDCCHRequired','PDCCHStrictOk','PDCCHStatus','PDCCHTrialRows','PDCCHOracleGuardViolationCount', ...
    'TRSRequired','TRSStrictOk','TRSStatus','TRSTrialRows','TRSDetectionRows','TRSTimingRows','TRSFrequencyRows','TRSChannelRows','TRSOracleGuardViolationCount', ...
    'SRSRequired','SRSStrictOk','SRSStatus','SRSTrialRows','SRSResourceMappingRows','SRSDetectionRows','SRSChannelRows','SRSCoverageRows','SRSOracleGuardViolationCount', ...
    'ChannelRFRequired','ChannelRFStrictOk','ChannelRFStatus','ChannelRFRealizationRows','ChannelRFConfiguredAppliedRows','ChannelRFLargeScaleRows','ChannelRFInterferenceRows','ChannelRFRFRows','ChannelRFNegativeRows','ChannelRFOracleGuardViolationCount', ...
    'ScenarioObjectiveOk','ScenarioObjectiveApplicability','RequiredConfiguredMatchRate','DLConfiguredMatchRate','ULConfiguredMatchRate', ...
    'FailureSummary','TruthContractSummaryArtifact','TruthContractFailuresArtifact'});
sixgr.util.csvWriteTable(summaryPath, summaryT);

failureT = localBuildTruthContractFailureTable(failures, verdict, scfg, cfg, layout);
sixgr.util.csvWriteTable(failuresPath, failureT);
end

function T = localBuildTruthContractFailureTable(failures, verdict, scfg, cfg, layout)
varNames = {'ScenarioID','RunTag','ConfigHash','FailureIndex','FailureCode','FailureCategory','FailureSeverity','StatusAuthority','RequiredFailureCountContribution','FailureDefinition'};
varTypes = {'string','string','string','double','string','string','string','string','double','string'};
[scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg);
statusAuthority = "sixgr.truth.evaluateLLSRuntimeTruthContract";
failures = string(failures(:));
failures = failures(strlength(failures) > 0);
if isempty(failures)
    T = table('Size', [0 numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
    return;
end
n = numel(failures);
categories = strings(n, 1);
for ii = 1:n
    categories(ii) = localClassifyFailure(failures(ii));
end
T = table( ...
    repmat(scenarioID, n, 1), ...
    repmat(runTag, n, 1), ...
    repmat(configHash, n, 1), ...
    (1:n).', ...
    failures, ...
    categories, ...
    repmat("required_truth_contract_gate", n, 1), ...
    repmat(statusAuthority, n, 1), ...
    ones(n, 1), ...
    repmat("Run-level success is blocked until this required truth-contract failure is resolved.", n, 1), ...
    'VariableNames', varNames);
end

function category = localClassifyFailure(failure)
failure = lower(string(failure));
if contains(failure, "proxy") || contains(failure, "fallback") || contains(failure, "abstract") || contains(failure, "bler")
    category = "proxy_or_fallback";
elseif contains(failure, "prach_strict") || contains(failure, "prach_")
    category = "prach_waveform";
elseif contains(failure, "trs_strict") || contains(failure, "trs_")
    category = "trs_reference_signal";
elseif contains(failure, "srs_strict") || contains(failure, "srs_")
    category = "srs_reference_signal";
elseif contains(failure, "ra_strict") || contains(failure, "random_access")
    category = "random_access";
elseif contains(failure, "result_issue_registry")
    category = "active_issue_registry";
elseif contains(failure, "configured_effective_match")
    category = "scenario_objective";
elseif contains(failure, "roundtrip") || contains(failure, "consistent")
    category = "roundtrip";
elseif contains(failure, "artifact")
    category = "canonical_artifact";
elseif contains(failure, "fer")
    category = "fer_scope";
elseif contains(failure, "amc")
    category = "amc_labeling";
elseif contains(failure, "lifecycle") || contains(failure, "finalized")
    category = "raw_lifecycle";
else
    category = "runtime_evidence";
end
end

function [scenarioID, runTag, configHash] = localTruthMetadata(layout, scfg, cfg)
scenarioID = string(localScenarioGet(scfg, cfg, "scenario_id", localScenarioGet(scfg, cfg, "scenario.id", "")));
runTag = string(localScenarioGet(scfg, cfg, "run.runTag", sixgr.util.structGet(cfg, "run.runTag", "")));
configHash = string(localScenarioGet(scfg, cfg, "meta.configHash", sixgr.util.structGet(cfg, "meta.configHash", "")));

runtimeMode = localReadTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"));
roundtrip = localReadTable(fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"));
summary = localReadTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
scenarioID = localFirstNonBlank(scenarioID, runtimeMode, roundtrip, summary, ["ScenarioID", "ScenarioId", "scenario_id"]);
runTag = localFirstNonBlank(runTag, runtimeMode, roundtrip, summary, ["RunTag", "run_tag"]);
configHash = localFirstNonBlank(configHash, runtimeMode, roundtrip, summary, ["ConfigHash", "config_hash"]);
end

function value = localFirstNonBlank(value, varargin)
value = string(value);
if ~ismissing(value) && strlength(strtrim(value)) > 0
    return;
end
if numel(varargin) < 2
    return;
end
columnNames = string(varargin{end});
tables = varargin(1:end-1);
for tt = 1:numel(tables)
    T = tables{tt};
    if isempty(T) || height(T) == 0
        continue;
    end
    for cc = 1:numel(columnNames)
        col = columnNames(cc);
        if localHasColumn(T, col)
            raw = string(T.(col));
            raw = raw(~ismissing(raw) & strlength(strtrim(raw)) > 0);
            if ~isempty(raw)
                value = raw(1);
                return;
            end
        end
    end
end
end

function value = localOptionalColumn(T, name, defaultValue)
n = height(T);
if localHasColumn(T, name)
    value = T.(string(name));
    return;
end
if isstring(defaultValue) || ischar(defaultValue)
    value = repmat(string(defaultValue), n, 1);
elseif islogical(defaultValue)
    value = repmat(logical(defaultValue), n, 1);
else
    value = repmat(defaultValue, n, 1);
end
end

function mask = localBlankOrMissingMask(raw)
if isnumeric(raw)
    mask = isnan(raw);
    return;
end
values = lower(strtrim(string(raw)));
mask = ismissing(values) | values == "" | values == "nan" | values == "<missing>";
end

function out = ternary(condition, a, b)
if condition
    out = a;
else
    out = b;
end
end

function value = localTableMaxNumeric(T, columnName, defaultValue)
value = defaultValue;
if ~localHasColumn(T, columnName)
    return;
end
raw = T.(string(columnName));
if isnumeric(raw)
    nums = raw;
else
    nums = str2double(string(raw));
end
nums = nums(~isnan(nums));
if ~isempty(nums)
    value = max(nums);
end
end

function value = localGetNestedDouble(S, pathParts, defaultValue)
value = defaultValue;
try
    tmp = S;
    for ii = 1:numel(pathParts)
        key = char(pathParts(ii));
        tmp = tmp.(key);
    end
    value = double(tmp);
catch
    value = defaultValue;
end
end

function value = localScenarioGetDouble(scfg, cfg, pathValue, defaultValue)
raw = localScenarioGet(scfg, cfg, pathValue, defaultValue);
if isnumeric(raw) && isscalar(raw)
    value = double(raw);
else
    value = str2double(string(raw));
    if isnan(value)
        value = defaultValue;
    end
end
end

function value = localScenarioGetBool(scfg, cfg, pathValue, defaultValue)
raw = localScenarioGet(scfg, cfg, pathValue, defaultValue);
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = raw ~= 0;
else
    text = lower(strtrim(string(raw)));
    value = text == "true" || text == "1" || text == "yes" || text == "on";
end
if isempty(value)
    value = defaultValue;
end
end

function value = localScenarioGet(scfg, cfg, pathValue, defaultValue)
value = defaultValue;
try
    if isobject(scfg) && ismethod(scfg, "get")
        value = scfg.get(pathValue, defaultValue);
        return;
    end
catch
end
try
    value = sixgr.util.structGet(scfg, pathValue, defaultValue);
    if ~isequal(value, defaultValue)
        return;
    end
catch
end
try
    value = sixgr.util.structGet(cfg, pathValue, defaultValue);
catch
    value = defaultValue;
end
end

function rel = localRelativePath(rootFolder, artifactPath)
rootFolder = string(rootFolder);
artifactPath = string(artifactPath);
rootWithSep = rootFolder;
if ~endsWith(rootWithSep, filesep)
    rootWithSep = rootWithSep + filesep;
end
if startsWith(artifactPath, rootWithSep)
    rel = extractAfter(artifactPath, strlength(rootWithSep));
else
    rel = artifactPath;
end
rel = replace(rel, "\", "/");
end
