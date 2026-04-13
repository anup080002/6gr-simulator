function ok = testLLSSINRRuntimeArtifacts()
%TESTLLSSINRRUNTIMEARTIFACTS Verify truthful SINR exports through runtime CSV artifacts.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scenarioPath = fullfile(tmp, "lls_sinr_artifacts.json");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_sinr_artifacts","description":"sinr artifact truth","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":2,"n_slots":2,"monte_carlo_iterations":1,"snr_sweep_offsets_db":[0],"random_seed":23},' ...
    '"channels":{"doppler_hz":25},' ...
    '"reference_signals":{"trs_enabled":true},' ...
    '"impairments":{"cfo_hz":80,"timing_offset_samples":8},' ...
    '"output":{"profile":"lls_sinr_artifacts","save_figures":false,"save_mat":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, "results", "sinr_artifacts");
runFolder = char(string(out.RunFolder));
assert(isfolder(runFolder), "Focused SINR artifact probe must create a run folder.");
scenarioSummary = readtable(fullfile(runFolder, "reports", "csv", "scenario_summary.csv"), "VariableNamingRule", "preserve");
assert(height(scenarioSummary) >= 1, "Focused SINR artifact probe must emit scenario_summary.csv.");
completion = string(scenarioSummary.RunCompletion(1));
assert(any(strcmp(completion, ["completed","completed_with_failures"])), ...
    "Focused SINR artifact probe must complete and emit artifacts even if unrelated required cases fail.");
assert(logical(scenarioSummary.ArtifactsGenerated(1)), ...
    "Focused SINR artifact probe must emit runtime artifacts.");

dl = readtable(fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv"), "VariableNamingRule", "preserve");
ul = readtable(fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv"), "VariableNamingRule", "preserve");
coverage = readtable(fullfile(runFolder, "reports", "csv", "live_coverage_layer.csv"), "VariableNamingRule", "preserve");
valueAudit = readtable(fullfile(runFolder, "reports", "csv", "value_source_audit.csv"), "VariableNamingRule", "preserve");
valueDict = readtable(fullfile(runFolder, "reports", "csv", "runtime_value_source_dictionary.csv"), "VariableNamingRule", "preserve");

localAssertRuntimeSINR(dl, "DL");
localAssertRuntimeSINR(ul, "UL");

coverageVars = string(coverage.Properties.VariableNames);
assert(all(ismember(["ReceiverHestWidebandSINR_dB","DecoderTruthProxyWidebandSINR_dB","WidebandSINRSource","WidebandSINRValueRole"], coverageVars)), ...
    "Live coverage layer must expose receiver-estimate, decoder-proxy, and source-role SINR fields.");
receiverMask = isfinite(double(coverage.ReceiverHestWidebandSINR_dB));
if any(receiverMask)
    assert(all(strcmp(string(coverage.WidebandSINRValueRole(receiverMask)), "estimated")), ...
        "Coverage rows with receiver Hest SINR must stay labeled as estimated.");
end
localAssertValueSourceRows(valueAudit, "ReceiverHestSINR_dB", "estimated", "receiver_hest_csi_feedback_wideband_effective_sinr");
localAssertValueSourceRows(valueAudit, "DecoderTruthProxySINR_dB", "derived", "post_equalization_evm_proxy");
localAssertDictionaryRows(valueDict, "ReceiverHestSINR_dB", "estimated", "receiver_hest_csi_feedback_wideband_effective_sinr");
localAssertDictionaryRows(valueDict, "DecoderTruthProxySINR_dB", "derived", "post_equalization_evm_proxy");
localAssertDictionaryRows(valueDict, "LargeScaleSINR_dB", "preview", "large_scale_interference_preview");

ok = true;
end

function localAssertValueSourceRows(T, fieldName, expectedRole, expectedSource)
mask = strcmp(string(T.FieldName), string(fieldName));
assert(any(mask), sprintf("value_source_audit.csv must contain %s.", fieldName));
assert(all(strcmp(string(T.ValueRole(mask)), string(expectedRole))), ...
    sprintf("value_source_audit.csv must label %s with role %s.", fieldName, expectedRole));
assert(all(strcmp(string(T.ValueSource(mask)), string(expectedSource))), ...
    sprintf("value_source_audit.csv must label %s with source %s.", fieldName, expectedSource));
end

function localAssertDictionaryRows(T, fieldName, expectedRole, expectedSource)
mask = strcmp(string(T.FieldName), string(fieldName));
assert(any(mask), sprintf("runtime_value_source_dictionary.csv must contain %s.", fieldName));
assert(all(strcmp(string(T.ValueRole(mask)), string(expectedRole))), ...
    sprintf("runtime_value_source_dictionary.csv must label %s with role %s.", fieldName, expectedRole));
assert(all(strcmp(string(T.ValueSource(mask)), string(expectedSource))), ...
    sprintf("runtime_value_source_dictionary.csv must label %s with source %s.", fieldName, expectedSource));
end

function localAssertRuntimeSINR(T, direction)
vars = string(T.Properties.VariableNames);
required = ["ReceiverHestSINR_dB","ReceiverHestSINRSource","DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","SINRValueRole","SINRSource","MeasuredTrialSINR_dB"];
assert(all(ismember(required, vars)), sprintf("%s runtime CSV must expose truthful SINR fields.", direction));
mask = isfinite(double(T.ReceiverHestSINR_dB));
assert(any(mask), sprintf("%s runtime CSV must contain finite ReceiverHestSINR_dB samples.", direction));
assert(all(strcmp(string(T.SINRValueRole(mask)), "estimated")), sprintf("%s runtime CSV must label receiver SINR as estimated.", direction));
assert(all(strcmp(string(T.SINRSource(mask)), "receiver_hest_csi_feedback_wideband_effective_sinr")), ...
    sprintf("%s runtime CSV must label receiver SINR with the Hest/CSI source.", direction));
mirrorMask = mask & isfinite(double(T.MeasuredTrialSINR_dB));
assert(all(abs(double(T.ReceiverHestSINR_dB(mirrorMask)) - double(T.MeasuredTrialSINR_dB(mirrorMask))) < 1e-9), ...
    sprintf("%s runtime CSV must keep MeasuredTrialSINR_dB as the receiver-Hest mirror only.", direction));
end
