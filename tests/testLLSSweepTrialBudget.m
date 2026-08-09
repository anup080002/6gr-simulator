function ok = testLLSSweepTrialBudget()
%TESTLLSSWEEPTRIALBUDGET Truth sweep must honor configured frame/trial budgets without hidden floors.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "lls_sweep_budget_probe"));
cfg.run.numFrames = 4;
cfg = sixgr.util.structSet(cfg, "lls6g.users.enabled", false);
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 1);
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.interferenceExecutionMode = "none";
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 5e6;
cfg.channel.snr_dB = 0;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.channelBandwidth_MHz = 5;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", 24);
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", 24);
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg = sixgr.util.structSet(cfg, ...
    "phy.pdsch.executionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, ...
    "run.pdschExecutionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, ...
    "phy.pusch.executionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, ...
    "run.puschExecutionProfile", "phy_calibration");
cfg.phy.pbch.enable = false;
cfg.phy.mib.enable = false;
cfg.phy.sib1.enable = false;
cfg.phy.pdcch.enable = false;
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindSearch", false);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.dmrs.enable", false);
cfg.phy.pucch.enable = false;
cfg.phy.srs.enable = false;
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", false);
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enable", false);
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enableCPECorrection", false);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.enablePTRS", false);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.enableCPECorrection", false);
cfg = sixgr.util.structSet(cfg, "phy.pusch.enablePTRS", false);
cfg = sixgr.util.structSet(cfg, "phy.pusch.ptrs.enableCPECorrection", false);
cfg = sixgr.util.structSet(cfg, "pdsch6gr.EnablePTRS", false);
cfg = sixgr.util.structSet(cfg, "phy.trackingRS.enable", false);
cfg.phy.csirs.enable = false;
cfg.phy.prach.enable = false;
cfg = sixgr.util.structSet(cfg, "random_access.enabled", false);
cfg.phy.harq.enable = false;
cfg.mac.harq.enable = false;
cfg = sixgr.util.structSet(cfg, "run.harqDiagnosticsEnabled", false);

% This is a deliberately reduced unit-test scenario, not a post-load
% bypass of the resolved YAML. Reinstall a matching feature authority so
% the waveform runner still exercises the production fail-closed contract.
probeScenario = scfg.toStruct();
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.pbch_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "initial_access.mib.enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "initial_access.sib1.enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "control.pdcch_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "control.blind_search_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.pdcch_dmrs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "control.pucch_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.srs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.trs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.tracking_rs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.ptrs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.ptrs_cpe_correction_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "pdsch6gr.enable_ptrs", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "reference_signals.csi_rs_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "random_access.enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, "harq.enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "pdsch6gr.harq_enabled", false);
probeScenario = sixgr.util.structSet(probeScenario, ...
    "simulation.harq_diagnostics_enabled", false);
cfg = sixgr.config.installRuntimeOperatingAuthority(cfg, probeScenario);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

out = sixgr.truth.runWaveformLinkBundle(cfg, tmp, struct( ...
    "LinkDuration_s", 0.004, ...
    "LinkMaxSimFrames", 4, ...
    "LinkSNRGrid_dB", [0 10], ...
    "LinkSweepFrames", 3, ...
    "LinkSweepMaxPoints", 2, ...
    "LinkReferenceSweepFrames", 1, ...
    "LinkReferenceSweepMaxPoints", 1, ...
    "LinkReferenceSweepMargin_dB", 0, ...
    "LinkReferenceSweepStep_dB", 10, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "SaveFigures", false));

dl = out.RawTrials.DL;
ul = out.RawTrials.UL;
assert(istable(dl) && istable(ul), ...
    "Truth sweep budget probe must export DL and UL raw-trial tables.");

dlCounts = splitapply(@numel, dl.SNR_dB, findgroups(dl.SNR_dB));
ulCounts = splitapply(@numel, ul.SNR_dB, findgroups(ul.SNR_dB));
assert(all(dlCounts == 12) && all(ulCounts == 12), ...
    "Truth sweep must honor LinkSweepFrames as Monte Carlo repetitions without a hidden minimum frame floor.");

outSingle = sixgr.truth.runWaveformLinkBundle(cfg, tmp, struct( ...
    "LinkDuration_s", 0.001, ...
    "LinkMaxSimFrames", 1, ...
    "LinkSNRGrid_dB", 0, ...
    "LinkSweepMaxPoints", 1, ...
    "LinkReferenceSweepFrames", 1, ...
    "LinkReferenceSweepMaxPoints", 1, ...
    "LinkReferenceSweepMargin_dB", 0, ...
    "LinkReferenceSweepStep_dB", 10, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "SaveFigures", false));

dlSingle = outSingle.RawTrials.DL;
ulSingle = outSingle.RawTrials.UL;
assert(height(dlSingle) == 1 && height(ulSingle) == 1, ...
    "Default raw-trial export must honor a single configured frame instead of silently expanding to eight.");

ok = true;
end
