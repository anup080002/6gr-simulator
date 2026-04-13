function ok = testLLSSweepTrialBudget()
%TESTLLSSWEEPTRIALBUDGET Truth sweep must honor configured Monte Carlo repetitions.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "lls_sweep_budget_probe"));
cfg.run.numFrames = 4;

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

out = sixgr.truth.runWaveformLinkBundle(cfg, tmp, struct( ...
    "LinkDuration_s", 0.004, ...
    "LinkMaxSimFrames", 4, ...
    "LinkSNRGrid_dB", [0 10], ...
    "LinkSweepFrames", 3, ...
    "SaveFigures", false));

dl = out.RawTrials.DL;
ul = out.RawTrials.UL;
assert(istable(dl) && istable(ul), ...
    "Truth sweep budget probe must export DL and UL raw-trial tables.");

dlCounts = splitapply(@numel, dl.SNR_dB, findgroups(dl.SNR_dB));
ulCounts = splitapply(@numel, ul.SNR_dB, findgroups(ul.SNR_dB));
assert(all(dlCounts == 24) && all(ulCounts == 24), ...
    "Truth sweep must honor LinkSweepFrames as Monte Carlo repetitions over the minimum frame budget floor.");

ok = true;
end
