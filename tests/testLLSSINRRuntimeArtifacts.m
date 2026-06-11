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
assert(all(ismember(["PostEqWidebandSINR_dB","ReceiverHestWidebandSINR_dB","DecoderTruthProxyWidebandSINR_dB","MeasuredWidebandSINR_dB","WidebandSINRSource","WidebandSINRValueRole"], coverageVars)), ...
    "Live coverage layer must expose post-eq, receiver diagnostic, decoder-proxy, and source-role SINR fields.");
localAssertCoverageSINR(coverage);
localAssertValueSourceRows(valueAudit, "ReceiverHestSINR_dB", "estimated", "receiver_hest_reference_signal_measurement");
localAssertValueSourceRows(valueAudit, "MeasuredTrialSINR_dB", "measured_post_equalization_scheduling_input", ...
    ["post_equalization_sinr_from_equalizer_channel_estimate","ul_receiver_evidence_limited_post_equalization_sinr"]);
localAssertValueSourceRows(valueAudit, "DecoderTruthProxySINR_dB", "unavailable", "evm_proxy_quarantined_not_decoder_truth");
localAssertDictionaryRows(valueDict, "ReceiverHestSINR_dB", "estimated", "receiver_hest_reference_signal_measurement");
localAssertDictionaryRows(valueDict, "MeasuredTrialSINR_dB", "measured_post_equalization_scheduling_input", "post_equalization_sinr_from_equalizer_channel_estimate");
localAssertDictionaryRows(valueDict, "DecoderTruthProxySINR_dB", "unavailable", "evm_proxy_quarantined_not_decoder_truth");
localAssertDictionaryRows(valueDict, "LargeScaleSINR_dB", "preview", "large_scale_interference_preview");

ok = true;
end

function localAssertCoverageSINR(T)
measuredMask = isfinite(double(T.PostEqWidebandSINR_dB)) | isfinite(double(T.MeasuredWidebandSINR_dB));
if any(measuredMask)
    assert(all(strcmp(string(T.WidebandSINRValueRole(measuredMask)), "measured_post_equalization_scheduling_input")), ...
        "Coverage rows with post-eq SINR must be labeled as scheduler-quality post-eq measurements.");
    assert(all(strcmp(string(T.WidebandSINRSource(measuredMask)), "post_equalization_sinr_from_equalizer_channel_estimate")), ...
        "Coverage rows with measured data-domain SINR must use the post-equalization receiver source.");
end
assert(all(~isfinite(double(T.DecoderTruthProxyWidebandSINR_dB))), ...
    "Coverage rows must not promote EVM-derived decoder proxy into wideband SINR.");
receiverOnlyMask = ~measuredMask & isfinite(double(T.ReceiverHestWidebandSINR_dB));
if any(receiverOnlyMask)
    assert(all(~strcmp(string(T.WidebandSINRSource(receiverOnlyMask)), "receiver_hest_reference_signal_measurement")), ...
        "Coverage rows with only receiver Hest SINR must not promote the Hest/CSI source as wideband scheduling SINR.");
end
end

function localAssertValueSourceRows(T, fieldName, expectedRole, expectedSource)
mask = strcmp(string(T.FieldName), string(fieldName));
assert(any(mask), sprintf("value_source_audit.csv must contain %s.", fieldName));
assert(all(strcmp(string(T.ValueRole(mask)), string(expectedRole))), ...
    sprintf("value_source_audit.csv must label %s with role %s.", fieldName, expectedRole));
assert(all(ismember(string(T.ValueSource(mask)), string(expectedSource))), ...
    sprintf("value_source_audit.csv must label %s with source %s.", fieldName, strjoin(string(expectedSource), "|")));
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
required = ["ReceiverHestSINR_dB","ReceiverHestSINRSource","PostEqSINR_dB","PostEqSINRSource","DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","SINRValueRole","SINRSource","MeasuredTrialSINR_dB","MeasuredTrialSINRSource"];
assert(all(ismember(required, vars)), sprintf("%s runtime CSV must expose truthful SINR fields.", direction));
mask = isfinite(double(T.ReceiverHestSINR_dB));
assert(any(mask), sprintf("%s runtime CSV must contain finite ReceiverHestSINR_dB samples.", direction));
assert(all(strcmp(string(T.ReceiverHestSINRSource(mask)), "receiver_hest_reference_signal_measurement")), ...
    sprintf("%s runtime CSV must label receiver Hest diagnostics with the Hest/CSI source.", direction));
measuredMask = isfinite(double(T.MeasuredTrialSINR_dB));
if any(measuredMask)
    if strcmpi(direction, "UL")
        limitedMask = measuredMask & strcmp(string(T.MeasuredTrialSINRSource), "ul_receiver_evidence_limited_post_equalization_sinr");
        postEqSelectedMask = measuredMask & ~limitedMask;
        if any(limitedMask)
            expectedLimited = min(double(T.PostEqSINR_dB(limitedMask)), double(T.ReceiverHestSINR_dB(limitedMask)));
            assert(all(abs(double(T.MeasuredTrialSINR_dB(limitedMask)) - expectedLimited) < 1e-9), ...
                "UL runtime CSV receiver-limited measured SINR must equal min(PostEqSINR, ReceiverHestSINR).");
        end
        if any(postEqSelectedMask)
            assert(all(abs(double(T.MeasuredTrialSINR_dB(postEqSelectedMask)) - double(T.PostEqSINR_dB(postEqSelectedMask))) < 1e-9), ...
                "UL runtime CSV post-eq-selected measured SINR must mirror PostEqSINR_dB.");
        end
    else
        assert(all(abs(double(T.MeasuredTrialSINR_dB(measuredMask)) - double(T.PostEqSINR_dB(measuredMask))) < 1e-9), ...
            sprintf("%s runtime CSV measured trial SINR must mirror PostEqSINR_dB.", direction));
    end
    assert(all(strlength(strtrim(string(T.MeasuredTrialSINRSource(measuredMask)))) > 0), ...
        sprintf("%s runtime CSV must keep MeasuredTrialSINRSource explicit when a measured trial SINR exists.", direction));
    assert(all(~contains(lower(string(T.MeasuredTrialSINRSource(measuredMask))), "proxy_fallback")), ...
        sprintf("%s runtime CSV must not relabel MeasuredTrialSINR_dB from decoder-proxy fallback.", direction));
    if strcmpi(direction, "UL")
        allowedULSources = ["post_equalization_sinr_from_equalizer_channel_estimate", ...
            "ul_receiver_evidence_limited_post_equalization_sinr", "measured_ul_rs_sinr"];
        assert(all(ismember(string(T.MeasuredTrialSINRSource(measuredMask)), allowedULSources)), ...
            "UL runtime CSV measured trial SINR must come from post-eq or explicitly receiver-limited UL evidence.");
    else
        assert(all(strcmp(string(T.MeasuredTrialSINRSource(measuredMask)), "post_equalization_sinr_from_equalizer_channel_estimate")), ...
            sprintf("%s runtime CSV measured trial SINR must come from post-equalization receiver evidence.", direction));
    end
    assert(all(strcmp(string(T.SINRValueRole(measuredMask)), "measured_post_equalization_scheduling_input")), ...
        sprintf("%s runtime CSV must publish measured trial SINR as post-eq scheduling input when available.", direction));
    assert(all(strcmp(string(T.SINRSource(measuredMask)), string(T.MeasuredTrialSINRSource(measuredMask)))), ...
        sprintf("%s runtime CSV primary SINR source must match the measured trial source.", direction));
end
proxyOnlyMask = ~isfinite(double(T.ReceiverHestSINR_dB)) & isfinite(double(T.DecoderTruthProxySINR_dB));
if any(proxyOnlyMask)
    assert(all(~isfinite(double(T.MeasuredTrialSINR_dB(proxyOnlyMask)))), ...
        sprintf("%s runtime CSV proxy-only rows must keep MeasuredTrialSINR_dB unavailable.", direction));
end
end
