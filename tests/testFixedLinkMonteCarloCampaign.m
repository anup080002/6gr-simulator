function ok = testFixedLinkMonteCarloCampaign()
%TESTFIXEDLINKMONTECARLOCAMPAIGN Controlled SNR curves must be real fixed-link campaigns.

setup6GRSimToolkit("Verbose", false);

cfg = localFixtureConfig();
snrGrid = [0 5 10 15 20];
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

opt = localCampaignOptions(cfg, snrGrid, 2, 99123);
out = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(tmp, "air_interface"), opt);

T = out.SNRSweep;
assert(istable(T) && height(T) == numel(snrGrid), ...
    "Fixed-link campaign must publish one controlled curve row per configured SNR point.");
assert(isequal(double(T.SNR_dB(:)).', snrGrid), ...
    "Fixed-link campaign must preserve the explicit SNR vector instead of replacing it with the operating point.");
assert(all(string(T.CampaignKind) == "fixed_link_monte_carlo") && ...
    all(string(T.SweepKind) == "fixed_reference_awgn_snr_campaign"), ...
    "Controlled curve rows must identify the fixed-link Monte Carlo source.");
assert(all(logical(T.FixedReferenceMode)) && all(string(T.NoiseOperatingMode) == "standalone_awgn_snr_argument"), ...
    "Fixed-link calibration must run in explicit AWGN SNR mode, separate from receiver-noise truth rows.");
assert(all(double(T.DL_TrialCount) >= 2) && all(double(T.UL_TrialCount) >= 2), ...
    "Each SNR point must accumulate the configured minimum DL and UL waveform trials.");
assert(all(string(T.DL_BLER_CI_Method) == "wilson_95pct") && ...
    all(string(T.UL_BLER_CI_Method) == "wilson_95pct"), ...
    "BLER confidence intervals must use the fixed-link Wilson method.");
assert(all(isfinite(double(T.PointSeed))) && numel(unique(double(T.PointSeed))) == height(T), ...
    "Each SNR point must receive a deterministic hierarchical point seed.");

fixedCsv = fullfile(tmp, "air_interface", "csv", "lls_fixed_link_campaign.csv");
assert(exist(fixedCsv, "file") == 2, ...
    "Fixed-link campaign summary CSV must be exported as a distinct artifact.");
csvT = readtable(fixedCsv, "VariableNamingRule", "preserve");
assert(isequal(double(csvT.SNR_dB(:)).', snrGrid), ...
    "Fixed-link campaign CSV must preserve the configured SNR vector.");

dlCurveCsv = fullfile(tmp, "reports", "csv", "dl_fixed_link_bler_curve.csv");
ulCurveCsv = fullfile(tmp, "reports", "csv", "ul_fixed_link_bler_curve.csv");
summaryCsv = fullfile(tmp, "reports", "csv", "fixed_link_campaign_summary.csv");
assert(exist(dlCurveCsv, "file") == 2 && exist(ulCurveCsv, "file") == 2 && exist(summaryCsv, "file") == 2, ...
    "Fixed-link campaign must export the report-level BLER curves and summary bundle.");
dlCurve = readtable(dlCurveCsv, "VariableNamingRule", "preserve");
assert(~isempty(dlCurve) && all(isfinite(double(dlCurve.CI_HalfWidth))), ...
    "DL report-level BLER curve must carry finite Wilson confidence intervals.");

tmp2 = tempname;
mkdir(tmp2);
c2 = onCleanup(@() rmdir(tmp2, "s")); %#ok<NASGU>
out2 = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(tmp2, "air_interface"), opt);
T2 = out2.SNRSweep;
cols = ["SNR_dB","PointSeed","DL_FailureCount","UL_FailureCount","DL_BLER","UL_BLER"];
for i = 1:numel(cols)
    a = double(T.(cols(i)));
    b = double(T2.(cols(i)));
    assert(isequaln(a, b), "Fixed-link campaign column %s must be deterministic for the same seed.", cols(i));
end

ok = true;
end

function cfg = localFixtureConfig()
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "fixed_link_campaign_fixture"));
cfg.run.numFrames = 1;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.interferenceExecutionMode = "none";
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.run.seed = 4207;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 5e6;
cfg.channel.snr_dB = 18;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.channelBandwidth_MHz = 5;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", 24);
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", 24);
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
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
cfg.phy.pusch.powerControl.enabled = false;
cfg.powerAndRF.puschPowerControlEnabled = false;
cfg = sixgr.util.structSet(cfg, "lls6g.users.enabled", false);
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 1);
end

function opt = localCampaignOptions(cfg, snrGrid, trialsPerPoint, seed)
opt = struct( ...
    "LinkDuration_s", 0.001, ...
    "LinkMaxSimFrames", 1, ...
    "FixedLinkCampaignOnly", true, ...
    "LinkSNR_dB", double(cfg.channel.snr_dB), ...
    "LinkSNRGrid_dB", double(cfg.channel.snr_dB), ...
    "LinkSweepFrames", 1, ...
    "LinkSweepTrialsPerSNR", 1, ...
    "LinkSweepMaxPoints", 1, ...
    "LinkReferenceSweepFrames", trialsPerPoint, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkFixedLinkCampaignEnabled", true, ...
    "LinkFixedLinkSNRGrid_dB", snrGrid, ...
    "LinkFixedLinkMinTrials", trialsPerPoint, ...
    "LinkFixedLinkMaxTrials", trialsPerPoint, ...
    "LinkFixedLinkTrialsPerDrop", 1, ...
    "LinkFixedLinkErrorTarget", inf, ...
    "LinkFixedLinkCIWidthTarget", inf, ...
    "LinkFixedLinkConfidenceLevel", 0.95, ...
    "LinkFixedLinkSeed", seed, ...
    "HARQDiagnosticsEnabled", false, ...
    "LinkAnchorCases", ["DL_PDSCH_Throughput","UL_PUSCH_Throughput"], ...
    "SaveFigures", false);
end
