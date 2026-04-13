function ok = testLLSSINRFieldTruth()
%TESTLLSSINRFIELDTRUTH Keep raw DL/UL SINR semantics honest.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml");
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
assert(all(strcmp(string(T.SINRValueRole(receiverMask)), "estimated")), ...
    sprintf("%s ReceiverHestSINR_dB rows must be classified as estimated.", direction));
assert(all(strcmp(string(T.SINRSource(receiverMask)), "receiver_hest_csi_feedback_wideband_effective_sinr")), ...
    sprintf("%s ReceiverHestSINR_dB rows must publish the Hest/CSI source.", direction));
assert(all(strcmp(string(T.ReceiverHestSINRSource(receiverMask)), "receiver_hest_csi_feedback_wideband_effective_sinr")), ...
    sprintf("%s ReceiverHestSINRSource must stay explicit.", direction));

legacyMask = receiverMask & isfinite(double(T.MeasuredTrialSINR_dB));
assert(all(abs(double(T.ReceiverHestSINR_dB(legacyMask)) - double(T.MeasuredTrialSINR_dB(legacyMask))) < 1e-9), ...
    sprintf("%s MeasuredTrialSINR_dB must remain only a compatibility mirror of ReceiverHestSINR_dB.", direction));

proxyMask = isfinite(double(T.EVM_rms)) & double(T.EVM_rms) > 0;
assert(any(proxyMask), sprintf("%s truth probe must produce finite EVM for decoder-truth proxy derivation.", direction));
assert(all(isfinite(double(T.DecoderTruthProxySINR_dB(proxyMask)))), ...
    sprintf("%s decoder-truth proxy SINR must be derived when EVM is available.", direction));
assert(all(strcmp(string(T.DecoderTruthProxySINRSource(proxyMask)), "post_equalization_evm_proxy")), ...
    sprintf("%s decoder-truth proxy SINR must publish the EVM proxy source.", direction));

highFailMask = double(T.CRCPass) == 0 & isfinite(double(T.ReceiverHestSINR_dB)) & double(T.ReceiverHestSINR_dB) > 20;
if any(highFailMask)
    assert(all(strcmp(string(T.SINRValueRole(highFailMask)), "estimated")), ...
        sprintf("%s high-SINR CRC-fail rows must remain labeled as estimated receiver SINR, not decoder truth.", direction));
    assert(all(strcmp(string(T.SINRSource(highFailMask)), "receiver_hest_csi_feedback_wideband_effective_sinr")), ...
        sprintf("%s high-SINR CRC-fail rows must keep the Hest/CSI source label.", direction));
end
end
