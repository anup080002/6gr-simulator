function ok = testLLSSINRRuntimeArtifacts()
%TESTLLSSINRRUNTIMEARTIFACTS Verify truthful SINR exports through runtime CSV artifacts.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg.run.numFrames = 1;
cfg.scenario.nUE = 1;
cfg.scenario.ue.nUE = 1;
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 1);
cfg = sixgr.util.structSet(cfg, "lls6g.users.enabled", true);
cfg = sixgr.util.structSet(cfg, "users.n_users", 1);
cfg = sixgr.util.structSet(cfg, "deployment_topology.num_ues", 1);
cfg.channel.snr_dB = 8;
cfg.outputs.saveFigures = false;
cfg.outputs.savePNG = false;

airInterfaceFolder = fullfile(tmp, "bundle", "air_interface");
rootRunFolder = fileparts(airInterfaceFolder);
opt = struct( ...
    "LinkDuration_s", 0.001, ...
    "LinkMaxSimFrames", 1, ...
    "LinkSNR_dB", cfg.channel.snr_dB, ...
    "LinkSNRGrid_dB", cfg.channel.snr_dB, ...
    "LinkSweepFrames", 1, ...
    "LinkSweepTrialsPerSNR", 1, ...
    "LinkReferenceSweepFrames", 1, ...
    "LinkSweepMaxPoints", 1, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkAdaptiveSweepMaxPoints", 1, ...
    "LinkAnchorCases", ["dl","ul"], ...
    "SaveFigures", false);
out = sixgr.truth.runWaveformLinkBundle(cfg, airInterfaceFolder, opt);
assert(isempty(string(sixgr.util.structGet(out, "Errors", strings(0, 1)))), ...
    "Focused SINR artifact probe must not report waveform-bundle execution errors.");
sixgr.truth.exportLLSConfigOwnershipArtifacts(rootRunFolder, scfg, cfg);

dl = readtable(fullfile(airInterfaceFolder, "csv", "dl_pdsch_trials.csv"), "VariableNamingRule", "preserve");
ul = readtable(fullfile(airInterfaceFolder, "csv", "ul_pusch_trials.csv"), "VariableNamingRule", "preserve");
coverage = readtable(fullfile(rootRunFolder, "reports", "csv", "live_coverage_layer.csv"), "VariableNamingRule", "preserve");
valueAudit = readtable(fullfile(rootRunFolder, "reports", "csv", "value_source_audit.csv"), "VariableNamingRule", "preserve");
valueDict = readtable(fullfile(rootRunFolder, "reports", "csv", "runtime_value_source_dictionary.csv"), "VariableNamingRule", "preserve");

localAssertRuntimeSINR(dl, "DL");
localAssertRuntimeSINR(ul, "UL");

coverageVars = string(coverage.Properties.VariableNames);
assert(all(ismember(["ReceiverHestWidebandSINR_dB","DecoderTruthProxyWidebandSINR_dB","MeasuredWidebandSINR_dB","WidebandSINRSource","WidebandSINRValueRole"], coverageVars)), ...
    "Live coverage layer must expose receiver-estimate, decoder-proxy, and source-role SINR fields.");
localAssertCoverageSINR(coverage);
localAssertValueSourceRows(valueAudit, "ReceiverHestSINR_dB", "estimated", "receiver_hest_reference_signal_measurement");
localAssertValueSourceRows(valueAudit, "MeasuredTrialSINR_dB", "measured", "post_equalization_error_vector_measurement");
localAssertValueSourceRows(valueAudit, "DecoderTruthProxySINR_dB", "derived", "post_equalization_evm_proxy");
localAssertDictionaryRows(valueDict, "ReceiverHestSINR_dB", "estimated", "receiver_hest_reference_signal_measurement");
localAssertDictionaryRows(valueDict, "MeasuredTrialSINR_dB", "measured", "waveform_trial_measurement");
localAssertDictionaryRows(valueDict, "DecoderTruthProxySINR_dB", "derived", "post_equalization_evm_proxy");
localAssertDictionaryRows(valueDict, "LargeScaleSINR_dB", "preview", "large_scale_interference_preview");

ok = true;
end

function localAssertCoverageSINR(T)
measuredMask = isfinite(double(T.MeasuredWidebandSINR_dB));
if any(measuredMask)
    assert(all(strcmp(string(T.WidebandSINRValueRole(measuredMask)), "measured")), ...
        "Coverage rows with measured data-domain SINR must be labeled measured.");
    assert(all(strcmp(string(T.WidebandSINRSource(measuredMask)), "post_equalization_error_vector_measurement")), ...
        "Coverage rows with measured data-domain SINR must use the post-equalization measurement source.");
end
proxyMask = ~measuredMask & isfinite(double(T.DecoderTruthProxyWidebandSINR_dB));
if any(proxyMask)
    assert(all(strcmp(string(T.WidebandSINRValueRole(proxyMask)), "derived_proxy")), ...
        "Coverage rows with only decoder-proxy SINR must be labeled derived_proxy.");
    assert(all(strcmp(string(T.WidebandSINRSource(proxyMask)), "post_equalization_evm_proxy")), ...
        "Coverage rows with only decoder-proxy SINR must keep the EVM proxy source.");
end
receiverOnlyMask = ~measuredMask & ~proxyMask & isfinite(double(T.ReceiverHestWidebandSINR_dB));
if any(receiverOnlyMask)
    assert(all(strcmp(string(T.WidebandSINRValueRole(receiverOnlyMask)), "estimated_diagnostic")), ...
        "Coverage rows with only receiver Hest SINR must be labeled estimated_diagnostic.");
    assert(all(strcmp(string(T.WidebandSINRSource(receiverOnlyMask)), "receiver_hest_reference_signal_measurement")), ...
        "Coverage rows with only receiver Hest SINR must keep the Hest/CSI source.");
end
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
required = ["ReceiverHestSINR_dB","ReceiverHestSINRSource","DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","SINRValueRole","SINRSource","MeasuredTrialSINR_dB","MeasuredTrialSINRSource"];
assert(all(ismember(required, vars)), sprintf("%s runtime CSV must expose truthful SINR fields.", direction));
mask = isfinite(double(T.ReceiverHestSINR_dB));
assert(any(mask), sprintf("%s runtime CSV must contain finite ReceiverHestSINR_dB samples.", direction));
assert(all(strcmp(string(T.ReceiverHestSINRSource(mask)), "receiver_hest_reference_signal_measurement")), ...
    sprintf("%s runtime CSV must label receiver Hest diagnostics with the Hest/CSI source.", direction));
measuredMask = isfinite(double(T.MeasuredTrialSINR_dB));
if any(measuredMask)
    assert(all(strlength(strtrim(string(T.MeasuredTrialSINRSource(measuredMask)))) > 0), ...
        sprintf("%s runtime CSV must keep MeasuredTrialSINRSource explicit when a measured trial SINR exists.", direction));
    assert(all(~contains(lower(string(T.MeasuredTrialSINRSource(measuredMask))), "proxy_fallback")), ...
        sprintf("%s runtime CSV must not relabel MeasuredTrialSINR_dB from decoder-proxy fallback.", direction));
    assert(all(strcmp(string(T.MeasuredTrialSINRSource(measuredMask)), "post_equalization_error_vector_measurement")), ...
        sprintf("%s runtime CSV measured trial SINR must come from post-equalization data-symbol error vectors.", direction));
    assert(all(strcmp(string(T.SINRValueRole(measuredMask)), "measured")), ...
        sprintf("%s runtime CSV must publish measured trial SINR as the primary SINR when available.", direction));
    assert(all(strcmp(string(T.SINRSource(measuredMask)), string(T.MeasuredTrialSINRSource(measuredMask)))), ...
        sprintf("%s runtime CSV primary SINR source must match the measured trial source.", direction));
end
proxyOnlyMask = ~isfinite(double(T.ReceiverHestSINR_dB)) & isfinite(double(T.DecoderTruthProxySINR_dB));
if any(proxyOnlyMask)
    assert(all(~isfinite(double(T.MeasuredTrialSINR_dB(proxyOnlyMask)))), ...
        sprintf("%s runtime CSV proxy-only rows must keep MeasuredTrialSINR_dB unavailable.", direction));
end
end
