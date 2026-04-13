function ok = testLLSConfigRoundtripRuntimeArtifacts()
%TESTLLSCONFIGROUNDTRIPRUNTIMEARTIFACTS Verify roundtrip verifier artifacts on a focused LLS runtime path.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scenarioPath = fullfile(tmp, "__web_runtime_roundtrip_focus.yaml");
fid = fopen(scenarioPath, "w");
assert(fid >= 0, "Unable to create focused roundtrip scenario file.");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_config_roundtrip_runtime_artifacts","description":"focused roundtrip verifier test","version":"1","owner":"test","maturity_tag":"experimental"},' ...
    '"simulation":{"n_frames":1,"n_slots":1,"n_subframes":1,"monte_carlo_iterations":1,"random_seed":73040,"snr_db":8,"snr_sweep_offsets_db":[0],"noise_operating_mode":"configured_snr_anchor_after_large_scale_gain"},' ...
    '"run_control":{"execution_mode":"LLS","num_workers":1},' ...
    '"deployment_topology":{"layout_type":"hex_grid","inter_site_distance":640,"num_cells":3,"num_ues":4,"num_trps":3},' ...
    '"mobility":{"ue_speed_kmh":42,"trajectory_model":"zigzag","update_period_s":0.001},' ...
    '"mimo":{"n_tx_ant":4,"n_rx_ant":2},' ...
    '"antenna_and_array":{"bs_num_antenna_elements":4,"ue_num_antenna_elements":2,"element_spacing_h":0.75,"element_spacing_v":0.5,"polarization":"single"},' ...
    '"channels":{"doppler_source_mode":"derive_from_ue_speed","mobility_kmph":42},' ...
    '"interference":{"inter_cell_execution_mode":"full_per_link_channel_waveform_sum"},' ...
    '"receiver":{"use_ideal_timing_sync":true},' ...
    '"control_gating":{"pbch_required":true,"prach_required":true,"pdcch_required":true,"srs_required":true,"srs_max_age_slots":5,"trs_required":true,"trs_max_age_slots":6},' ...
    '"csi_acquisition_and_reporting":{"channel_state_information_mode":"PMI+CQI","cqi_policy":"baseline","pmi_policy":"baseline","ri_policy":"disabled","cri_policy":"disabled","report_payload_mode":"compressed","crc_attached_mode":true,"crc_free_mode":false,"pmi_codebook_mode":"type1_su_mimo"},' ...
    '"reference_signals":{"channel_state_information_mode":"PMI+CQI","csi_feedback_mode":"PMI+CQI","cqi_reporting_enabled":true,"pmi_reporting_enabled":true,"ri_reporting_enabled":false,"cri_reporting_enabled":false},' ...
    '"link_adaptation":{"cqi_table":"table2"},' ...
    '"users":{"enabled":true,"n_users":4,"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"output":{"backend":"filesystem","profile":"lls_config_roundtrip_runtime_artifacts","save_figures":false,"save_png":false,"save_mat":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "roundtrip");
assert(out.Ok, "Focused LLS roundtrip verifier run should complete.");

runFolder = char(string(out.RunFolder));
roundtripFile = fullfile(runFolder, "reports", "csv", "config_roundtrip_verification.csv");
browserDbFile = fullfile(runFolder, "reports", "csv", "browser_runtime_db_consistency.csv");
summaryRawFile = fullfile(runFolder, "reports", "csv", "summary_vs_raw_consistency.csv");
valueSourceAuditFile = fullfile(runFolder, "reports", "csv", "value_source_audit.csv");

assert(exist(roundtripFile, "file") == 2, "Missing config roundtrip verification CSV.");
assert(exist(browserDbFile, "file") == 2, "Missing browser/runtime/DB consistency CSV.");
assert(exist(summaryRawFile, "file") == 2, "Missing summary-vs-raw consistency CSV.");
assert(exist(valueSourceAuditFile, "file") == 2, "Missing value-source audit CSV.");

roundtripT = localReadVerificationCSV(roundtripFile);
dictT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "runtime_value_source_dictionary.csv"));
exposureT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "config_exposure_summary.csv"));
matrixT = localReadVerificationCSV(fullfile(runFolder, "reports", "csv", "config_ownership_matrix.csv"));
valueSourceAuditT = localReadVerificationCSV(valueSourceAuditFile);
summaryRawT = localReadVerificationCSV(summaryRawFile);

localAssertRoundtripValue(roundtripT, "deployment_topology.inter_site_distance", "640");
localAssertRoundtripOverlayValue(roundtripT, "deployment_topology.inter_site_distance", "640");
localAssertRoundtripValue(roundtripT, "deployment_topology.layout_type", "hex_grid");
localAssertRoundtripOverlayValue(roundtripT, "deployment_topology.layout_type", "hex_grid");
localAssertRoundtripEvidence(roundtripT, "deployment_topology.layout_type", "LayoutType", "hex_grid");
localAssertRoundtripValue(roundtripT, "mobility.ue_speed_kmh", "42");
localAssertRoundtripValue(roundtripT, "antenna_and_array.bs_num_antenna_elements", "4");
localAssertRoundtripValue(roundtripT, "simulation.noise_operating_mode", "configured_snr_anchor_after_large_scale_gain");
localAssertRoundtripValue(roundtripT, "receiver.use_ideal_timing_sync", "1");
localAssertRoundtripOverlayValue(roundtripT, "receiver.use_ideal_timing_sync", "1");
localAssertRoundtripValue(roundtripT, "run_control.num_workers", "1");
localAssertRoundtripOverlayValue(roundtripT, "run_control.num_workers", "1");
localAssertRoundtripValue(roundtripT, "control_gating.srs_max_age_slots", "5");
localAssertRoundtripValue(roundtripT, "control_gating.trs_max_age_slots", "6");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.channel_state_information_mode", "PMI+CQI");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.cqi_policy", "baseline");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.pmi_policy", "baseline");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.ri_policy", "disabled");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.cri_policy", "disabled");
localAssertRoundtripOverlayValue(roundtripT, "csi_acquisition_and_reporting.cqi_policy", "baseline");
localAssertRoundtripOverlayValue(roundtripT, "csi_acquisition_and_reporting.pmi_policy", "baseline");
localAssertRoundtripOverlayValue(roundtripT, "csi_acquisition_and_reporting.ri_policy", "disabled");
localAssertRoundtripOverlayValue(roundtripT, "csi_acquisition_and_reporting.cri_policy", "disabled");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.cqi_policy", "1");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.pmi_policy", "1");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.ri_policy", "0");
localAssertRoundtripDerivedValue(roundtripT, "csi_acquisition_and_reporting.cri_policy", "0");
localAssertRoundtripValue(roundtripT, "csi_acquisition_and_reporting.report_payload_mode", "compressed");
localAssertRoundtripValue(roundtripT, "link_adaptation.cqi_table", "table2");
localAssertRoundtripValue(roundtripT, "users.execution_model", "slot_coupled_truth");
localAssertRoundtripValue(roundtripT, "users.beam_selection_strategy", "fixed_first_beam");

assert(height(matrixT) >= 100, "Runtime ownership matrix should stay expanded on the active LLS path.");
assert(height(dictT) >= 50, "Runtime value-source dictionary should stay expanded on the active LLS path.");
assert(height(exposureT) == height(matrixT), "Exposure summary should cover the full ownership matrix surface on the active LLS path.");
localAssertObservedValue(valueSourceAuditT, "MobilitySpeed_kmh", "42");
localAssertObservedNumericNotEqual(valueSourceAuditT, "ResolvedDopplerHz", 42);
localAssertObservedValue(valueSourceAuditT, "ConfiguredLinkAdaptationMode", "amc");
localAssertObservedValue(valueSourceAuditT, "UseIdealTimingSync", "1");
localAssertObservedValue(valueSourceAuditT, "PDCCHGatingActive", "1");
localAssertObservedValue(valueSourceAuditT, "SRSGatingActive", "1");
localAssertObservedValue(valueSourceAuditT, "TRSGatingActive", "1");
localAssertRoundtripNote(roundtripT, "link_adaptation.cqi_table", "runtime_evidence_diverges_from_resolved_runtime_value");
localAssertDictionaryRole(dictT, "MobilitySpeed_kmh", "configured");
localAssertDictionaryRole(dictT, "ResolvedDopplerHz", "derived");
localAssertDictionaryRole(dictT, "ConfiguredWorkers", "configured");
localAssertDictionaryRole(dictT, "TRSMode", "runtime_state_derived");
localAssertDictionaryRole(dictT, "UseIdealTimingSync", "resolved");
localAssertDictionaryRole(dictT, "PDCCHGatingActive", "resolved");
localAssertDictionaryRole(dictT, "TRSGatingActive", "resolved");

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

function T = localReadVerificationCSV(filePath)
opts = detectImportOptions(filePath, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
opts = setvartype(opts, opts.VariableNames, "string");
T = readtable(filePath, opts);
end
