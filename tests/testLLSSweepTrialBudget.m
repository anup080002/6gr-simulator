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
cfg.phy.pbch.enable = false;
cfg.phy.mib.enable = false;
cfg.phy.sib1.enable = false;
cfg.phy.pdcch.enable = false;
cfg.phy.pucch.enable = false;
cfg.phy.srs.enable = false;
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", false);
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enable", false);
cfg.phy.csirs.enable = false;
cfg.phy.prach.enable = false;
cfg.phy.harq.enable = false;
cfg.mac.harq.enable = false;

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
