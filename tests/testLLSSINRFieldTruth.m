function ok = testLLSSINRFieldTruth()
%TESTLLSSINRFIELDTRUTH Keep raw DL/UL SINR semantics honest.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "lls_sinr_field_truth"));
cfg = localConfigureIsolatedTruthProbe(cfg);
assert(logical(cfg.phy.pusch.measurements.dmrsResidualPostEqSINRBoundEnabled) && ...
    logical(cfg.phy.pusch.measurements.decisionDirectedPostEqSINRBoundEnabled) && ...
    string(cfg.phy.pusch.measurements.decoderNoiseVarianceMode) == "pre_equalization", ...
    "The truth scenario must explicitly preserve its PUSCH receiver-residual and standard pre-equalization-noise-plus-CSI decoder policy through YAML normalization.");

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

function cfg = localConfigureIsolatedTruthProbe(cfg)
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pusch.executionProfile = "phy_calibration";
cfg.phy.pdsch.symbolAllocation = [0 14];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pusch.mappingType = "A";
prbSet = 0:(double(cfg.phy.carrier.NSizeGrid) - 1);
cfg.phy.pdsch.prbSet = prbSet;
cfg.phy.pusch.prbSet = prbSet;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.ptrs.enable = false;
cfg.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "sinr_field_truth_calibration");
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
receiverSources = string(T.ReceiverHestSINRSource(receiverMask));
allowedReceiverSources = ["receiver_hest_reference_signal_measurement", ...
    "canonical_dmrs_estimate_and_equalizer"];
assert(all(ismember(receiverSources, allowedReceiverSources)), ...
    sprintf("%s ReceiverHestSINRSource must identify an actual receiver estimate/equalizer path.", direction));

measuredMask = isfinite(double(T.MeasuredTrialSINR_dB));
assert(any(measuredMask), sprintf("%s trials must export at least one finite MeasuredTrialSINR_dB sample.", direction));
postEqMask = isfinite(double(T.PostEqSINR_dB));
assert(any(postEqMask), sprintf("%s trials must export true post-equalization SINR samples.", direction));
assert(all(abs(double(T.MeasuredTrialSINR_dB(measuredMask)) - double(T.PostEqSINR_dB(measuredMask))) < 1e-9), ...
    sprintf("%s MeasuredTrialSINR_dB must mirror PostEqSINR_dB, not a proxy or cross-domain reference metric.", direction));
assert(all(strlength(strtrim(string(T.MeasuredTrialSINRSource(measuredMask)))) > 0), ...
    sprintf("%s MeasuredTrialSINR_dB rows must carry an explicit measurement source.", direction));
assert(all(~contains(lower(string(T.MeasuredTrialSINRSource(measuredMask))), "proxy_fallback")), ...
    sprintf("%s MeasuredTrialSINR_dB must not be relabeled from decoder-proxy fallback.", direction));
if strcmpi(direction, "UL")
    allowedULSources = ["post_equalization_sinr_from_equalizer_channel_estimate", ...
        "post_equalization_sinr_from_dmrs_residual_bounded_equalizer_channel_estimate", ...
        "post_equalization_sinr_from_decision_directed_symbol_residual_bounded_equalizer_channel_estimate"];
    assert(all(ismember(string(T.MeasuredTrialSINRSource(measuredMask)), allowedULSources)), ...
        "UL MeasuredTrialSINR_dB must come from true post-equalization receiver evidence.");
else
    allowedDLPostEqSources = ["post_equalization_sinr_from_equalizer_channel_estimate", ...
        "canonical_post_equalization_sinr"];
    assert(all(ismember(string(T.MeasuredTrialSINRSource(measuredMask)), allowedDLPostEqSources)), ...
        sprintf("%s MeasuredTrialSINR_dB must come from true post-equalization receiver evidence.", direction));
end
if strcmpi(direction, "UL")
    measuredSources = string(T.MeasuredTrialSINRSource(measuredMask));
    measuredRoles = string(T.SINRValueRole(measuredMask));
    assert(all(ismember(measuredSources, allowedULSources) & ...
        measuredRoles == "measured_post_equalization_scheduling_input"), ...
        "UL rows with measured trial SINR must publish post-equalization receiver evidence.");
else
    assert(all(strcmp(string(T.SINRValueRole(measuredMask)), "measured_post_equalization_scheduling_input")), ...
        sprintf("%s rows with measured trial SINR must publish primary SINR as post-eq scheduling input.", direction));
end
assert(all(strcmp(string(T.SINRSource(measuredMask)), string(T.MeasuredTrialSINRSource(measuredMask)))), ...
    sprintf("%s rows with measured trial SINR must use the measured source for primary SINR.", direction));
proxyOnlyMask = ~isfinite(double(T.ReceiverHestSINR_dB)) & isfinite(double(T.DecoderTruthProxySINR_dB));
if any(proxyOnlyMask)
    assert(all(~isfinite(double(T.MeasuredTrialSINR_dB(proxyOnlyMask)))), ...
        sprintf("%s proxy-only rows must keep MeasuredTrialSINR_dB unavailable instead of fabricating a measured value.", direction));
end

evmMask = isfinite(double(T.EVM_rms)) & double(T.EVM_rms) > 0;
assert(any(evmMask), sprintf("%s truth probe must produce finite EVM for diagnostic proxy export.", direction));
assert(all(~isfinite(double(T.DecoderTruthProxySINR_dB(evmMask)))), ...
    sprintf("%s decoder-truth proxy SINR must stay unavailable when only EVM is available.", direction));
assert(all(contains(lower(string(T.DecoderTruthProxySINRSource(evmMask))), "not_decoder_truth") | ...
    contains(lower(string(T.DecoderTruthProxySINRSource(evmMask))), "not_materialized")), ...
    sprintf("%s decoder-truth proxy source must disclose quarantine or unavailability.", direction));
assert(all(isfinite(double(T.EVMProxySINR_dB(evmMask)))), ...
    sprintf("%s EVM proxy SINR diagnostic must be available when EVM is available.", direction));
assert(all(strcmp(string(T.EVMProxySINRValueRole(evmMask)), "diagnostic_evm_proxy_not_scheduling_input")), ...
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
