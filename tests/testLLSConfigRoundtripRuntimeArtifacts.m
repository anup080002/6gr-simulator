function ok = testLLSConfigRoundtripRuntimeArtifacts()
%TESTLLSCONFIGROUNDTRIPRUNTIMEARTIFACTS Verify roundtrip verifier artifacts on a focused LLS runtime path.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot.yaml");
scenarioPath = fullfile(tmp, "__web_runtime_roundtrip_focus.yaml");
fid = fopen(scenarioPath, "w");
assert(fid >= 0, "Unable to create focused roundtrip scenario file.");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_config_roundtrip_runtime_artifacts","scenario_name":"focused roundtrip verifier test","description":"focused roundtrip verifier test","version":"1","owner":"test","maturity_tag":"baseline","study_status":"baseline"},' ...
    '"simulation":{"n_frames":1,"n_slots":5,"n_subframes":3,"monte_carlo_iterations":1,"random_seed":73040,"snr_db":24,"snr_sweep_offsets_db":[0],"noise_operating_mode":"receiver_noise_figure_thermal_noise","harq_diagnostics_enabled":false},' ...
    '"run_control":{"execution_mode":"LLS","total_slots":5,"warmup_slots":0,"measurement_slots":5,"warmup_time_ms":0,"measurement_time_ms":2.5,"total_time_ms":2.5,"num_workers":1,"seed":73040},' ...
    '"deployment_topology":{"layout_type":"hex_grid","inter_site_distance":640,"num_cells":1,"num_ues":1,"num_trps":1},' ...
    '"mobility":{"ue_speed_kmh":42,"trajectory_model":"zigzag","update_period_s":0.001},' ...
    '"mimo":{"n_tx_ant":4,"n_rx_ant":2,"beam_sweep_enabled":false},' ...
    '"antenna_and_array":{"bs_num_txrus":4,"bs_num_rxrus":4,"bs_num_antenna_elements":4,"ue_num_txrus":2,"ue_num_rxrus":2,"ue_num_antenna_elements":2,"element_spacing_h":0.75,"element_spacing_v":0.5,"polarization":"single"},' ...
    '"channels":{"doppler_source_mode":"derive_from_ue_speed","mobility_kmph":42},' ...
    '"random_access":{"enabled":false,"detection_threshold":0.2,"min_detection_trials":1},' ...
    '"interference":{"inter_cell_execution_mode":"full_per_link_channel_waveform_sum"},' ...
    '"receiver":{"use_ideal_timing_sync":true},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":true,"srs_required":false,"srs_max_age_slots":5,"trs_required":false,"trs_max_age_slots":6},' ...
    '"csi_acquisition_and_reporting":{"channel_state_information_mode":"PMI+CQI","cqi_policy":"baseline","pmi_policy":"baseline","ri_policy":"disabled","cri_policy":"disabled","report_payload_mode":"compressed","crc_attached_mode":true,"crc_free_mode":false,"pmi_codebook_mode":"type1_su_mimo"},' ...
    '"control":{"pdcch_enabled":true,"pucch_enabled":true,"pucch_format":0},' ...
    '"pucch_resources":{"enabled":true,"profile":"nr_rel18_pucch_strict","configuration_epoch":1,' ...
    '"resource_sets":[{"id":0,"max_payload_bits":2,"resource_ids":[0]}],' ...
    '"resources":[{"id":0,"format":0,"starting_prb":0,"nrof_prbs":1,"starting_symbol":13,"nrof_symbols":1,' ...
    '"intra_slot_hopping":false,"second_hop_start_prb":null,"initial_cyclic_shift":0,"occ_length":1,"occ_index":0,' ...
    '"additional_dmrs":false,"pi2_bpsk":false,"nid":1,"hopping_id":1}],' ...
    '"dl_data_to_ul_ack":[1,2,3,4,5,6,7,8],"harq_ack":{"resource_id":0,"k1_slots":4},' ...
    '"overlap_policy":{"detect_pucch_pusch_overlap":true,"uci_on_pusch_enabled":true,"unsupported_overlap_policy":"reject_before_waveform"}},' ...
    '"harq":{"enabled":true},' ...
    '"reference_signals":{"ssb_enabled":false,"pbch_enabled":false,"srs_enabled":false,"trs_enabled":false,"tracking_rs_enabled":false,"channel_state_information_mode":"PMI+CQI","csi_feedback_mode":"PMI+CQI","cqi_reporting_enabled":true,"pmi_reporting_enabled":true,"ri_reporting_enabled":false,"cri_reporting_enabled":false,"csi_rs_precoder_codebook":{"enabled":true,"type":"dft_ura","physical_element_count":4,"beam_indices_port_0":[0],"beam_indices_port_1":[1]}},' ...
    '"initial_access":{"enabled":false,"sib1":{"enabled":false},"ssb":{"precoder_codebook":{"enabled":true,"type":"dft_ura","physical_element_count":4,"beam_grid_rows":2,"beam_grid_columns":4,"beam_indices":[0,1,2,3,4,5,6,7]}}},' ...
    '"link_adaptation":{"cqi_table":"table2"},' ...
    '"users":{"enabled":true,"n_users":1,"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"output":{"backend":"filesystem","profile":"lls_config_roundtrip_runtime_artifacts","save_figures":false,"save_png":false,"save_mat":false}}']);
fclose(fid);

expectedRunFolder = fullfile(pwd, "results", "lls", "lls_config_roundtrip_runtime_artifacts", "roundtrip");
runtimeCompleted = false;
try
    out = run_6g_phy_lls_single(scenarioPath, tmp, "roundtrip");
    runtimeCompleted = logical(out.Ok);
    runFolder = char(string(out.RunFolder));
catch ME
    assert(strcmp(string(ME.identifier), "sixgr:link:PrimarySummarySkipped"), ...
        "Focused LLS roundtrip verifier run failed unexpectedly: %s", string(ME.message));
    runFolder = expectedRunFolder;
end
assert(exist(runFolder, "dir") == 7, ...
    "Focused LLS roundtrip verifier must produce a run folder even when summary coverage recovery is triggered.");
assert(runtimeCompleted || exist(fullfile(runFolder, "reports", "csv", "config_roundtrip_verification.csv"), "file") == 2, ...
    "Focused LLS roundtrip verifier must emit recovered config-ownership artifacts when summary coverage is skipped.");
roundtripFile = fullfile(runFolder, "reports", "csv", "config_roundtrip_verification.csv");
browserDbFile = fullfile(runFolder, "reports", "csv", "browser_runtime_db_consistency.csv");
summaryRawFile = fullfile(runFolder, "reports", "csv", "summary_vs_raw_consistency.csv");
valueSourceAuditFile = fullfile(runFolder, "reports", "csv", "value_source_audit.csv");
browserSurfaceFile = fullfile(runFolder, "reports", "csv", "browser_config_surface_matrix.csv");

assert(exist(roundtripFile, "file") == 2, "Missing config roundtrip verification CSV.");
assert(exist(browserDbFile, "file") == 2, "Missing browser/runtime/DB consistency CSV.");
assert(exist(summaryRawFile, "file") == 2, "Missing summary-vs-raw consistency CSV.");
assert(exist(valueSourceAuditFile, "file") == 2, "Missing value-source audit CSV.");
assert(exist(browserSurfaceFile, "file") == 2, "Missing browser config surface matrix CSV.");

roundtripT = localReadVerificationCSV(roundtripFile);
dictT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "runtime_value_source_dictionary.csv"));
exposureT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "config_exposure_summary.csv"));
matrixT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "config_ownership_matrix.csv"));
valueSourceAuditT = localReadVerificationCSV(valueSourceAuditFile);
summaryRawT = localReadVerificationCSV(summaryRawFile);
browserSurfaceT = localReadVerificationCSV(browserSurfaceFile);

localAssertRoundtripValue(roundtripT, "deployment_topology.inter_site_distance", "640");
localAssertRoundtripOverlayValue(roundtripT, "deployment_topology.inter_site_distance", "640");
localAssertRoundtripEvidence(roundtripT, "deployment_topology.layout_type", "LayoutType", "hex_grid");
localAssertRoundtripValue(roundtripT, "mobility.ue_speed_kmh", "42");
localAssertRoundtripValue(roundtripT, "antenna_and_array.bs_num_antenna_elements", "4");
localAssertRoundtripValue(roundtripT, "run_control.num_workers", "1");
localAssertRoundtripOverlayValue(roundtripT, "run_control.num_workers", "1");
localAssertRoundtripValue(roundtripT, "control_gating.srs_max_age_slots", "5");
localAssertRoundtripValue(roundtripT, "control_gating.trs_max_age_slots", "6");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.cqi_policy", "1");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.pmi_policy", "1");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.ri_policy", "0");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.cri_policy", "0");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "deployment_topology.layout_type", "hex_grid");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "simulation.noise_operating_mode", "receiver_noise_figure_thermal_noise");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "receiver.use_ideal_timing_sync", "true");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.channel_state_information_mode", "PMI+CQI");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.cqi_policy", "baseline");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.pmi_policy", "baseline");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.ri_policy", "disabled");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.cri_policy", "disabled");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "csi_acquisition_and_reporting.report_payload_mode", "compressed");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "link_adaptation.cqi_table", "table2");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "users.execution_model", "slot_coupled_truth");
localAssertBrowserSurfaceResolvedValue(browserSurfaceT, "users.beam_selection_strategy", "fixed_first_beam");

assert(height(matrixT) >= 100, "Runtime ownership matrix should stay expanded on the active LLS path.");
assert(height(dictT) >= 50, "Runtime value-source dictionary should stay expanded on the active LLS path.");
assert(height(exposureT) == height(matrixT), "Exposure summary should cover the full ownership matrix surface on the active LLS path.");
localAssertObservedValue(valueSourceAuditT, "MobilitySpeed_kmh", "42");
localAssertObservedNumericNotEqual(valueSourceAuditT, "ResolvedDopplerHz", 42);
localAssertObservedValue(valueSourceAuditT, "UseIdealTimingSync", "1");
localAssertObservedValue(valueSourceAuditT, "PDCCHGatingActive", "1");
localAssertRoundtripEvidence(roundtripT, "link_adaptation.cqi_table", "CQITable", "table2");
localAssertRoundtripNoteAbsent(roundtripT, "link_adaptation.cqi_table", "runtime_evidence_diverges_from_resolved_runtime_value");
localAssertDictionaryRole(dictT, "MobilitySpeed_kmh", "configured");
localAssertDictionaryRole(dictT, "ResolvedDopplerHz", "derived");
localAssertDictionaryRole(dictT, "ConfiguredWorkers", "configured");
localAssertDictionaryRole(dictT, "UseIdealTimingSync", "resolved");
localAssertDictionaryRole(dictT, "PDCCHGatingActive", "resolved");

assert(any(strcmp(string(summaryRawT.SummaryField), "EffectiveDLTrialCount") & strcmp(string(summaryRawT.ConsistencyStatus), "consistent")), ...
    "Summary-vs-raw consistency must prove the DL effective-trial count from raw runtime tables.");
assert(any(strcmp(string(summaryRawT.SummaryField), "EffectiveULTrialCount") & strcmp(string(summaryRawT.ConsistencyStatus), "consistent")), ...
    "Summary-vs-raw consistency must prove the UL effective-trial count from raw runtime tables.");

ok = true;
end

function localAssertRoundtripValue(T, parameterName, expectedValue)
localAssertRoundtripPair(T, parameterName, expectedValue, expectedValue);
end

function localAssertRoundtripPair(T, parameterName, expectedBrowserValue, expectedResolvedValue)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.BrowserSubmittedValue), string(expectedBrowserValue)), ...
    "Browser-submitted value mismatch for %s.", parameterName);
assert(strcmp(string(row.ResolvedMATLABValue), string(expectedResolvedValue)), ...
    "Resolved MATLAB value mismatch for %s.", parameterName);
assert(any(strcmp(string(row.ConsistencyStatus), ["consistent","consistent_db_unavailable"])), ...
    "Roundtrip status for %s must stay consistent on the focused runtime path.", parameterName);
end

function localAssertRoundtripEvidence(T, parameterName, expectedEvidenceField, expectedEvidenceValue)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.RuntimeEvidenceField), string(expectedEvidenceField)), ...
    "Runtime evidence field mismatch for %s.", parameterName);
assert(strcmp(string(row.RuntimeEvidenceValue), string(expectedEvidenceValue)), ...
    "Runtime evidence value mismatch for %s.", parameterName);
assert(strcmp(string(row.RuntimeEvidenceValueRole), "runtime_state_derived") || strcmp(string(row.RuntimeEvidenceValueRole), "resolved"), ...
    "Runtime evidence role for %s must be semantic, not a cross-concept surrogate.", parameterName);
end

function localAssertRoundtripOverlayValue(T, parameterName, expectedOverlayValue)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.RuntimeOverlayValue), string(expectedOverlayValue)), ...
    "Runtime overlay value mismatch for %s.", parameterName);
assert(strcmp(string(row.RuntimeOverlayValueSource), "browser_runtime_overlay"), ...
    "Runtime overlay value source for %s must prove the active overlay, not inheritance or an unrelated artifact.", parameterName);
assert(strcmp(string(row.RuntimeOverlayValueRole), "submitted"), ...
    "Runtime overlay value role for %s must be labeled submitted.", parameterName);
end

function localAssertRoundtripDerivedValue(T, parameterName, expectedDerivedValue)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.ResolvedMATLABValueRole), "resolved"), ...
    "Resolved value role for %s must remain the policy token, not the derived flag.", parameterName);
assert(strcmp(string(row.DerivedValue), string(expectedDerivedValue)), ...
    "Derived value mismatch for %s.", parameterName);
assert(strcmp(string(row.DerivedValueRole), "derived"), ...
    "Derived value role for %s must be labeled derived.", parameterName);
assert(contains(string(row.DerivedValueSource), "localPolicyFlag"), ...
    "Derived value source for %s must point at the policy-to-flag derivation.", parameterName);
end

function localAssertObservedValue(T, fieldName, expectedValue)
mask = strcmp(string(T.FieldName), string(fieldName)) & strcmp(string(T.ConsistencyStatus), "observed");
assert(any(mask), "Value-source audit must observe field %s on the active runtime path.", fieldName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.ObservedValue), string(expectedValue)), ...
    "Observed value mismatch for %s.", fieldName);
end

function localAssertObservedNumericNotEqual(T, fieldName, excludedValue)
mask = strcmp(string(T.FieldName), string(fieldName)) & strcmp(string(T.ConsistencyStatus), "observed");
assert(any(mask), "Value-source audit must observe field %s on the active runtime path.", fieldName);
row = T(find(mask, 1, "first"), :);
observed = str2double(string(row.ObservedValue));
assert(isfinite(observed), "Observed value for %s must be numeric.", fieldName);
assert(abs(observed - excludedValue) > 1e-9, ...
    "Observed value for %s must stay distinct from excluded concept value %g.", fieldName, excludedValue);
end

function localAssertDictionaryRole(T, fieldName, expectedRole)
mask = strcmp(string(T.FieldName), string(fieldName));
assert(nnz(mask) == 1, "Runtime value-source dictionary must contain %s exactly once.", fieldName);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.ValueRole), string(expectedRole)), ...
    "Value-role mismatch for %s.", fieldName);
end

function localAssertRoundtripNote(T, parameterName, expectedNoteFragment)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(contains(string(row.ConsistencyNotes), string(expectedNoteFragment)), ...
    "Roundtrip verifier must record note '%s' for %s.", string(expectedNoteFragment), parameterName);
end

function localAssertRoundtripNoteAbsent(T, parameterName, forbiddenNoteFragment)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Roundtrip verifier must contain parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
assert(~contains(string(row.ConsistencyNotes), string(forbiddenNoteFragment)), ...
    "Roundtrip verifier must not retain stale note '%s' for %s when runtime evidence matches.", ...
    string(forbiddenNoteFragment), parameterName);
end

function localAssertBrowserSurfaceResolvedValue(T, parameterId, expectedValue)
mask = strcmp(string(T.ParameterId), string(parameterId));
assert(nnz(mask) == 1, "Browser config surface must contain parameter %s exactly once.", parameterId);
row = T(find(mask, 1, "first"), :);
assert(strcmp(string(row.ResolvedMATLABValue), string(expectedValue)), ...
    "Browser surface resolved MATLAB value mismatch for %s.", parameterId);
assert(strcmp(string(row.ConfigStatus), "submitted_in_browser_overlay"), ...
    "Browser surface config status for %s must prove the browser overlay path.", parameterId);
displayStatus = string(row.DisplayStatus);
displayReason = string(row.DisplayReason);
if strcmp(displayStatus, "display_config_resolved")
    assert(strcmp(displayReason, "resolved_in_matlab_from_browser_overlay"), ...
        "Browser surface display reason for %s must stay tied to browser-overlay resolution.", parameterId);
    return;
end
if strcmp(displayStatus, "display_runtime_measured")
    assert(strcmp(string(row.RuntimeMeasuredValue), string(expectedValue)), ...
        "Browser surface runtime-measured value mismatch for %s.", parameterId);
    assert(strcmp(string(row.MeasurementStatus), "measured_runtime_evidence_published"), ...
        "Browser surface measurement status for %s must prove published runtime evidence.", parameterId);
    return;
end
if strcmp(displayStatus, "display_runtime_applied")
    assert(strcmp(string(row.RuntimeAppliedValue), string(expectedValue)), ...
        "Browser surface runtime-applied value mismatch for %s.", parameterId);
    assert(strcmp(string(row.ApplicationStatus), "applied_to_runtime_object"), ...
        "Browser surface application status for %s must prove runtime application evidence.", parameterId);
    return;
end
assert(false, "Browser surface display status for %s must be resolved, runtime-applied, or runtime-measured.", parameterId);
end

function T = localReadVerificationCSV(filePath)
opts = detectImportOptions(filePath, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
opts = setvartype(opts, opts.VariableNames, "string");
T = readtable(filePath, opts);
end
