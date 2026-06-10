function ok = testLLSSINRFieldTruth()
%TESTLLSSINRFIELDTRUTH Keep raw DL/UL SINR semantics honest.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "lls_sinr_field_truth"));

dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 8);
ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 8);

assert(~logical(dl.Skipped) && ~logical(ul.Skipped), ...
    "Focused DL/UL truth probes must execute waveform trials, not skip into NaN metrics.");
assert(istable(dl.TrialTable) && height(dl.TrialTable) > 0 && istable(ul.TrialTable) && height(ul.TrialTable) > 0, ...
    "Focused DL/UL truth probes must emit trial tables even when a mid-SNR CRC fails.");

localAssertSINRTruth(dl.TrialTable, "DL");
localAssertSINRTruth(ul.TrialTable, "UL");

ok = true;
end

function localAssertSINRTruth(T, direction)
vars = string(T.Properties.VariableNames);
required = ["ConfiguredSNR_dB","AppliedAWGNSNR_dB","ReceiverHestSINR_dB","ReceiverHestSINRSource", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","EVMProxySINR_dB","EVMProxySINRValueRole", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","SINRValueRole","SINRSource", ...
    "MeasuredTrialSINR_dB","MeasuredTrialSINRSource","LargeScaleSINR_dB"];
assert(all(ismember(required, vars)), sprintf("%s trials must export the truthful SINR fields.", direction));

receiverMask = isfinite(double(T.ReceiverHestSINR_dB));
assert(any(receiverMask), sprintf("%s trials must export finite ReceiverHestSINR_dB samples.", direction));
cfgMask = receiverMask & isfinite(double(T.ConfiguredSNR_dB));
if any(cfgMask)
    copiedSweepMask = abs(double(T.ReceiverHestSINR_dB(cfgMask)) - double(T.ConfiguredSNR_dB(cfgMask))) < 1e-9;
    assert(~all(copiedSweepMask), ...
        sprintf("%s ReceiverHestSINR_dB must be receiver-estimated, not copied wholesale from ConfiguredSNR_dB.", direction));
end
assert(all(strcmp(string(T.ReceiverHestSINRSource(receiverMask)), "receiver_hest_reference_signal_measurement")), ...
    sprintf("%s ReceiverHestSINRSource must stay explicit.", direction));

measuredMask = isfinite(double(T.MeasuredTrialSINR_dB));
assert(any(measuredMask), sprintf("%s trials must export at least one finite MeasuredTrialSINR_dB sample.", direction));
postEqMask = isfinite(double(T.PostEqSINR_dB));
assert(any(postEqMask), sprintf("%s trials must export true post-equalization SINR samples.", direction));
assert(all(abs(double(T.MeasuredTrialSINR_dB(measuredMask)) - double(T.PostEqSINR_dB(measuredMask))) < 1e-9), ...
    sprintf("%s MeasuredTrialSINR_dB must mirror PostEqSINR_dB, not EVM proxy.", direction));
assert(all(strlength(strtrim(string(T.MeasuredTrialSINRSource(measuredMask)))) > 0), ...
    sprintf("%s MeasuredTrialSINR_dB rows must carry an explicit measurement source.", direction));
assert(all(~contains(lower(string(T.MeasuredTrialSINRSource(measuredMask))), "proxy_fallback")), ...
    sprintf("%s MeasuredTrialSINR_dB must not be relabeled from decoder-proxy fallback.", direction));
assert(all(strcmp(string(T.MeasuredTrialSINRSource(measuredMask)), "post_equalization_sinr_from_equalizer_channel_estimate")), ...
    sprintf("%s MeasuredTrialSINR_dB must come from true post-equalization receiver evidence.", direction));
assert(all(strcmp(string(T.SINRValueRole(measuredMask)), "measured_post_equalization_scheduling_input")), ...
    sprintf("%s rows with measured trial SINR must publish primary SINR as post-eq scheduling input.", direction));
assert(all(strcmp(string(T.SINRSource(measuredMask)), string(T.MeasuredTrialSINRSource(measuredMask)))), ...
    sprintf("%s rows with measured trial SINR must use the measured source for primary SINR.", direction));
proxyOnlyMask = ~isfinite(double(T.ReceiverHestSINR_dB)) & isfinite(double(T.DecoderTruthProxySINR_dB));
if any(proxyOnlyMask)
    assert(all(~isfinite(double(T.MeasuredTrialSINR_dB(proxyOnlyMask)))), ...
        sprintf("%s proxy-only rows must keep MeasuredTrialSINR_dB unavailable instead of fabricating a measured value.", direction));
end

proxyMask = isfinite(double(T.EVM_rms)) & double(T.EVM_rms) > 0;
assert(any(proxyMask), sprintf("%s truth probe must produce finite EVM for decoder-truth proxy derivation.", direction));
assert(all(isfinite(double(T.DecoderTruthProxySINR_dB(proxyMask)))), ...
    sprintf("%s decoder-truth proxy SINR must be derived when EVM is available.", direction));
assert(all(strcmp(string(T.DecoderTruthProxySINRSource(proxyMask)), "post_equalization_evm_proxy")), ...
    sprintf("%s decoder-truth proxy SINR must publish the EVM proxy source.", direction));
assert(all(strcmp(string(T.EVMProxySINRValueRole(proxyMask)), "diagnostic_evm_proxy_not_scheduling_input")), ...
    sprintf("%s EVM proxy SINR must be explicitly non-scheduling.", direction));

highFailMask = double(T.CRCPass) == 0 & isfinite(double(T.ReceiverHestSINR_dB)) & double(T.ReceiverHestSINR_dB) > 20;
if any(highFailMask)
    measuredHighFailMask = highFailMask & measuredMask;
    if any(measuredHighFailMask)
        assert(all(strcmp(string(T.SINRValueRole(measuredHighFailMask)), "measured_post_equalization_scheduling_input")), ...
            sprintf("%s high receiver-Hest CRC-fail rows with data SINR must remain labeled as post-eq scheduling input.", direction));
        assert(all(~strcmp(string(T.SINRSource(measuredHighFailMask)), "receiver_hest_reference_signal_measurement")), ...
            sprintf("%s high receiver-Hest CRC-fail rows must not promote diagnostic Hest SINR into primary SINR.", direction));
    end
    diagnosticOnlyMask = highFailMask & ~measuredMask;
    if any(diagnosticOnlyMask)
        assert(all(~strcmp(string(T.SINRSource(diagnosticOnlyMask)), "receiver_hest_reference_signal_measurement")), ...
            sprintf("%s receiver-Hest-only CRC-fail rows must not promote Hest/CSI source into primary SINR.", direction));
    end
end
end
