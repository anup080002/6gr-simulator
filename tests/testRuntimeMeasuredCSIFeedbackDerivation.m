function ok = testRuntimeMeasuredCSIFeedbackDerivation()
%TESTRUNTIMEMEASUREDCSIFEEDBACKDERIVATION Measured PHY SINR must drive runtime CSI.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_mobile_2ue_100kmh_1sector_full_capture.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tempname);

assert(strcmpi(char(sixgr.link.resolveConfiguredMCSTable(cfg, "DL")), "qam256_table2"), ...
    "modulation_and_mapping.dl_mcs_table must feed the internal DL MCS table.");
assert(strcmpi(char(sixgr.link.resolveConfiguredMCSTable(cfg, "UL")), "qam256_table2"), ...
    "modulation_and_mapping.ul_mcs_table must feed the internal UL MCS table.");
assert(double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN)) == 2 && ...
    double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN)) == 2, ...
    "Scenario rank/layer caps must remain visible to the scheduler and PHY.");

row = table();
row.Direction = "DL";
row.WidebandCQI = 1;
row.CQIDerivedMCS = 0;
row.CQIDerivedTargetCodeRate = 120 / 1024;
row.CQIDerivedModulation = "QPSK";
row.MeasuredTrialSINR_dB = 18.5;
row.MeasuredTrialSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
row.MeasuredTrialSINRValueRole = "measured_post_equalization_scheduling_input";
row.MeasuredTrialSINRValueStatus = "OK";
row.RankIndicator = 2;

csi = sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(row, cfg, "DL");

assert(isfinite(double(csi.SINR_dB)) && abs(double(csi.SINR_dB) - 18.5) < 1e-9, ...
    "Runtime CSI must carry the measured trial SINR, not a missing MeasuredSINR_dB alias.");
assert(double(csi.CQI) > 1, ...
    "Stale trial WidebandCQI=1 must be replaced when measured post-equalization SINR is available.");
assert(double(csi.MCSIndex) > 0 && ~strcmpi(char(string(csi.Modulation)), "QPSK"), ...
    "Measured high-SINR CSI should produce a higher AMC point than bootstrap QPSK.");
assert(double(csi.RI) == 2, ...
    "Measured RI must be preserved for downstream rank/layer grant realignment.");

row.ReceiverHestSINR_dB = 6.0;
row.ReceiverHestSINRSource = "receiver_hest_reference_signal_measurement";
row.ReceiverHestSINRValueRole = "estimated";
row.ReceiverHestSINRValueStatus = "OK";
conservativeCSI = sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(row, cfg, "DL");

assert(abs(double(conservativeCSI.SINR_dB) - 6.0) < 1e-9, ...
    "Runtime CSI must use the conservative measured receiver-Hest/post-eq SINR minimum.");
assert(double(conservativeCSI.MCSIndex) < double(csi.MCSIndex), ...
    "Lower receiver channel-estimate SINR must reduce the derived AMC point.");
assert(contains(string(conservativeCSI.SINRValueRole), "conservative_min_channel_estimate_posteq"), ...
    "Conservative scheduler CSI must carry explicit measured-source provenance.");

ok = true;
end
