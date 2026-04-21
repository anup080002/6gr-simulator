function ok = testSystemLevelSourceLabelSeparation()
%TESTSYSTEMLEVELSOURCELABELSEPARATION Guard system-level SINR/beam/channel source labels.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "cfg"));

grantT = table( ...
    ["DL"; "UL"], [1; 1], [0; 0], [1; 1], [1; 1], ["D"; "U"], ...
    [0; 12], [24; 16], [2; 2], [10; 10], [1024; 768], [11; 9], [10; 8], ...
    [0.55; 0.49], [true; false], [0; 1], [0; 0], [1; 1], [false; false], ...
    ["unit_test_dl"; "unit_test_ul"], [0; 0], [4096; 2048], [3072; 2048], ...
    'VariableNames', {'Direction','TTI','Time_s','UE','CellID','SlotDirection','PRBStart','PRBCount', ...
    'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','TargetCodeRate','Ack','HarqID','RV','NDI', ...
    'IsRetransmission','GrantReason','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter'});

details = struct();
details.SchedulerGrants = grantT;
details.TTI_s = 0.5e-3;
details.WaveformBacked = true;
details.ExecutionBackend = "WAVEFORM_SYSTEM_PHY";
details.PHYMode = "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL";
details.WaveformPHYActive = true;
details.ProxyPHYActive = false;
details.FallbackUsed = false;
details.SINR_dB = 17.25;
details.SINR_UL_dB = 9.75;
details.RSRP_dBm = -82.5;
details.Pathloss_dB = 119.5;
details.ServingDistance_m = 180;
details.ServingBeamIndex = 5;
details.ServingBeamGain_dB = 6.5;
details.InterferencePowerDL_dBm = -96;
details.InterferencePowerUL_dBm = -99;
details.NoiseDL_dBm = -101;
details.NoiseUL_dBm = -100;
details.ActiveInterfererCountDL = 3;
details.ActiveInterfererCountUL = 2;
details.ServingCell = 1;
details.Layout = struct("bs", struct("pos_m", zeros(57, 3)));
details.UEFinal = struct("pos_m", zeros(100, 3));

systemOut = struct("Details", details);
sixgr.truth.exportSystemLevelCanonicalArtifacts(tmp, scfg, cfg, systemOut);

dlT = localReadTable(fullfile(tmp, "air_interface", "csv", "dl_pdsch_trials.csv"));
ulT = localReadTable(fullfile(tmp, "air_interface", "csv", "ul_pusch_trials.csv"));
runtimeT = localReadTable(fullfile(tmp, "reports", "csv", "runtime_operating_mode.csv"));
channelStateT = localReadTable(fullfile(tmp, "reports", "csv", "live_channel_state_tti.csv"));

for T = {dlT, ulT, channelStateT}
    current = T{1};
    assert(all(isfinite(double(current.SystemLevelSINR_dB))), "System-level SINR must be exported as its own estimate.");
    assert(all(strcmpi(string(current.SystemLevelSINRValueRole), "runtime_state_derived")), "System-level SINR role must be runtime-state-derived.");
    assert(all(strcmpi(string(current.SystemLevelSINRValueStatus), "available_system_level_estimate")), "System-level SINR status must be explicit.");
    assert(all(~isfinite(double(current.ReceiverHestSINR_dB))), "System-level adapter must not fabricate receiver Hest SINR.");
    assert(all(strcmpi(string(current.ReceiverHestSINRValueStatus), "unavailable")), "Receiver Hest SINR must remain unavailable when no Hest grid exists.");
    assert(all(~isfinite(double(current.DecoderTruthProxySINR_dB))), "System SINR budget must not be relabeled as decoder-truth proxy SINR.");
    assert(all(strcmpi(string(current.DecoderTruthProxySINRValueStatus), "unavailable")), "Decoder-truth proxy SINR must remain unavailable without proxy evidence.");
    assert(all(strcmpi(string(current.ExplicitPrecoderReplayStatus), "not_materialized")), "Explicit precoder replay must be labeled as not materialized.");
    assert(all(strcmpi(string(current.ChannelArrayValueStatus), "approximate_system_context")), "Channel-array handling status must disclose system-level approximation.");
end

assert(all(strcmpi(string(runtimeT.SystemLevelSINRValueStatus), "available_system_level_estimate")), ...
    "Runtime operating mode must expose system-level SINR status.");
assert(all(strcmpi(string(runtimeT.ReceiverHestSINRValueStatus), "unavailable")), ...
    "Runtime operating mode must expose receiver-Hest SINR unavailability.");
assert(all(strcmpi(string(runtimeT.DecoderTruthProxySINRValueStatus), "unavailable")), ...
    "Runtime operating mode must expose decoder-truth proxy SINR unavailability.");

evidenceTmp = fullfile(tmp, "with_replay_evidence");
mkdir(evidenceTmp);
detailsEvidence = details;
detailsEvidence.SchedulerGrants = localAttachReplayEvidence(grantT);
sixgr.truth.exportSystemLevelCanonicalArtifacts(evidenceTmp, scfg, cfg, struct("Details", detailsEvidence));

dlEvidenceT = localReadTable(fullfile(evidenceTmp, "air_interface", "csv", "dl_pdsch_trials.csv"));
ulEvidenceT = localReadTable(fullfile(evidenceTmp, "air_interface", "csv", "ul_pusch_trials.csv"));
runtimeEvidenceT = localReadTable(fullfile(evidenceTmp, "reports", "csv", "runtime_operating_mode.csv"));
channelEvidenceT = localReadTable(fullfile(evidenceTmp, "reports", "csv", "live_channel_state_tti.csv"));

for T = {dlEvidenceT, ulEvidenceT, channelEvidenceT}
    current = T{1};
    assert(all(isfinite(double(current.SystemLevelSINR_dB))), "System-level SINR must stay separately exported.");
    assert(all(strcmpi(string(current.SystemLevelSINRSource), "system_level_desired_interference_noise_budget")), ...
        "System-level SINR source must not be overwritten by waveform replay receiver evidence.");
    assert(all(isfinite(double(current.ReceiverHestSINR_dB))), ...
        "Receiver-Hest SINR must be exported when per-grant waveform replay evidence exists.");
    assert(all(strcmpi(string(current.ReceiverHestSINRSource), "receiver_hest_reference_signal_measurement")), ...
        "Receiver-Hest SINR must keep receiver Hest/CSI source lineage.");
    assert(all(strcmpi(string(current.ReceiverHestSINRValueStatus), "OK")), ...
        "Receiver-Hest SINR status must be OK for replay evidence rows.");
    assert(all(isfinite(double(current.DecoderTruthProxySINR_dB))), ...
        "Decoder-side SINR proxy must be exported only from explicit equalizer/EVM evidence.");
    assert(all(strcmpi(string(current.DecoderTruthProxySINRSource), "post_equalization_evm_proxy")), ...
        "Decoder-side SINR proxy must not be relabeled from the system SINR budget.");
    assert(all(strcmpi(string(current.DecoderTruthProxySINRValueStatus), "OK")), ...
        "Decoder-side SINR proxy status must be OK when EVM evidence exists.");
    assert(all(strcmpi(string(current.ExplicitPrecoderReplayStatus), "materialized")), ...
        "Explicit precoder replay must be materialized when per-grant replay metadata exists.");
    assert(all(strcmpi(string(current.ChannelArrayValueStatus), "approximate_system_context")), ...
        "Channel-array handling status must still disclose system-level approximation.");
end

assert(all(strcmpi(string(runtimeEvidenceT.ReceiverHestSINRValueStatus), "OK")), ...
    "Runtime operating mode must summarize replay-backed receiver-Hest SINR availability.");
assert(all(strcmpi(string(runtimeEvidenceT.DecoderTruthProxySINRValueStatus), "OK")), ...
    "Runtime operating mode must summarize replay-backed equalizer SINR proxy availability.");
assert(all(strcmpi(string(runtimeEvidenceT.ExplicitPrecoderReplayStatus), "materialized")), ...
    "Runtime operating mode must summarize per-grant precoder replay availability.");

ok = true;
end

function T = localReadTable(pathStr)
opts = detectImportOptions(pathStr, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
T = readtable(pathStr, opts);
end

function T = localAttachReplayEvidence(T)
n = height(T);
T.ReceiverHestSINR_dB = [15.25; 8.5];
T.ReceiverHestSINRSource = repmat("receiver_hest_reference_signal_measurement", n, 1);
T.ReceiverHestSINRValueRole = repmat("estimated", n, 1);
T.ReceiverHestSINRValueStatus = repmat("OK", n, 1);
T.ReceiverHestSINRNAReason = repmat("", n, 1);
T.DecoderTruthProxySINR_dB = [14.75; 7.9];
T.DecoderTruthProxySINRSource = repmat("post_equalization_evm_proxy", n, 1);
T.DecoderTruthProxySINRValueRole = repmat("derived", n, 1);
T.DecoderTruthProxySINRValueStatus = repmat("OK", n, 1);
T.DecoderTruthProxySINRNAReason = repmat("", n, 1);
T.PrecoderSource = ["dl_type1_codebook"; "ul_direct_mapping_no_explicit_beam_weights"];
T.RequestedPrecoderSource = T.PrecoderSource;
T.AppliedPrecoderSource = T.PrecoderSource;
T.RequestedPrecoderPMI = [2; NaN];
T.PrecodingMode = ["explicit-wideband"; "direct_mapping_no_explicit_beam_weights"];
T.PrecodingApplicationStage = ["nrPDSCHPrecode_before_RE_mapping"; "re_mapping_without_explicit_beam_weights"];
T.PrecodingActive = [true; false];
T.ExplicitBeamWeightsApplied = [true; false];
T.TransformPrecodingApplied = [false; false];
T.BeamformingApplied = [true; false];
T.AppliedBeamIndexSet = ["2"; ""];
T.AppliedPrecoderPMI = [2; NaN];
T.AppliedPrecoderValueRole = repmat("applied", n, 1);
T.AppliedPrecoderValueStatus = repmat("OK", n, 1);
T.AppliedPrecoderNAReason = repmat("", n, 1);
T.ExplicitPrecoderReplayStatus = repmat("materialized", n, 1);
T.ExplicitPrecoderReplayBlocker = repmat("", n, 1);
T.AppliedPrecoderPMIType = ["type1"; ""];
T.AppliedPrecoderCodebookMode = ["type1_su_mimo"; ""];
T.PrecodingNumPorts = [2; 1];
T.PrecodingNumLayers = [2; 1];
T.PrecodingMatrixRows = [2; NaN];
T.PrecodingMatrixCols = [2; NaN];
end
