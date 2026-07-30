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

requiredAirCsv = [
    "air_interface/csv/lls_fixed_link_campaign.csv"
    "air_interface/csv/lls_snr_sweep.csv"
    "air_interface/csv/fixed_link_campaign_task_plan.csv"
    "air_interface/csv/dl_fixed_link_campaign_trials.csv"
    "air_interface/csv/ul_fixed_link_campaign_trials.csv"
    ];
for relPath = requiredAirCsv.'
    absPath = fullfile(tmp, strrep(relPath, "/", filesep));
    assert(exist(absPath, "file") == 2, "Missing fixed-link air-interface CSV: %s", relPath);
    Ta = readtable(absPath, "VariableNamingRule", "preserve");
    assert(height(Ta) >= 1, "Fixed-link air-interface CSV is empty: %s", relPath);
end
assert(exist(fullfile(tmp, "air_interface", "csv", ...
    "lls_reference_snr_sweep.csv"), "file") ~= 2, ...
    ["A DUT fixed-link sweep must not be duplicated and mislabeled as an " ...
    "independent reference sweep when no independent oracle was supplied."]);

requiredReportCsv = [
    "reports/csv/fixed_snr_sweep_curve_summary.csv"
    "reports/csv/dl_fixed_snr_bler_curve.csv"
    "reports/csv/ul_fixed_snr_bler_curve.csv"
    "reports/csv/dl_fixed_snr_ber_curve.csv"
    "reports/csv/ul_fixed_snr_ber_curve.csv"
    "reports/csv/fixed_snr_sweep_point_completeness.csv"
    "reports/csv/fixed_snr_sweep_curve_crossing.csv"
    ];
for relPath = requiredReportCsv.'
    absPath = fullfile(tmp, strrep(relPath, "/", filesep));
    assert(exist(absPath, "file") == 2, "Missing fixed-link report CSV: %s", relPath);
    Tr = readtable(absPath, "VariableNamingRule", "preserve");
    assert(height(Tr) >= 1, "Fixed-link report CSV is empty: %s", relPath);
end

normalizedSummary = readtable(fullfile(tmp, "reports", "csv", "fixed_snr_sweep_curve_summary.csv"), "VariableNamingRule", "preserve");
assert(height(normalizedSummary) == 2 * numel(snrGrid), ...
    "Normalized fixed-SNR curve summary must have one row per SNR point per enabled direction.");
requiredCurveCols = ["Direction","ChannelModel","SweepKind","NoiseVariable","SNR_dB","ConfiguredSNR_dB", ...
    "AppliedSNR_dB","MeanMeasuredSINR_dB","MedianMeasuredSINR_dB","SINRMinusSNRMean_dB", ...
    "MCS","Modulation","Rank","Layers","TrialCount","TBPassCount","TBFailCount", ...
    "BLER","BLER_CI_Low","BLER_CI_High","BLER_CI_Width","BitErrors","BitsCompared", ...
    "BER","BER_CI_Low","BER_CI_High","BER_CI_Width","Throughput_Mbps","Goodput_Mbps", ...
    "TargetBLER","TargetCrossingSNR_dB","TargetCrossingStatus","StopReason","Incomplete","Status","FailureCode"];
assert(all(ismember(requiredCurveCols, string(normalizedSummary.Properties.VariableNames))), ...
    "Normalized fixed-SNR curve summary is missing required audit columns.");
assert(all(double(normalizedSummary.TrialCount) >= 2), ...
    "Normalized fixed-SNR curve summary must preserve the configured minimum trials per point.");
assert(all(double(normalizedSummary.BLER) >= 0 & double(normalizedSummary.BLER) <= 1), ...
    "Normalized fixed-SNR BLER values must stay within [0,1].");
assert(all(double(normalizedSummary.BER) >= 0 & double(normalizedSummary.BER) <= 1), ...
    "Normalized fixed-SNR BER values must stay within [0,1].");

dlTrialsCsv = readtable(fullfile(tmp, "air_interface", "csv", "dl_fixed_link_campaign_trials.csv"), "VariableNamingRule", "preserve");
requiredTrialCols = ["Direction","SNR_dB","ConfiguredSNR_dB","AppliedSNR_dB","AppliedAWGNSNR_dB", ...
    "MeasuredPostEqSINR_dB","Status","CRCPass","BitErrors","BitsCompared","MCS","Modulation", ...
    "Rank","NumLayers","TBSizeBits","RateMatchedBits","EffectiveCodeRate","FixedLinkCampaign", ...
    "FixedReferenceMode","FixedLinkPointIndex","FixedLinkDropIndex","FixedLinkTrialIndex","FixedLinkSeedHierarchy"];
assert(all(ismember(requiredTrialCols, string(dlTrialsCsv.Properties.VariableNames))), ...
    "Normalized fixed-link DL trial CSV is missing required audit columns.");
assert(all(localAsLogicalVector(dlTrialsCsv.FixedLinkCampaign)) && all(localAsLogicalVector(dlTrialsCsv.FixedReferenceMode)), ...
    "Normalized fixed-link DL trial CSV must preserve fixed-link reference mode evidence.");
newTBMask = ~localAsLogicalVector(dlTrialsCsv.IsRetransmission);
assert(all(double(dlTrialsCsv.EffectiveCodeRate(newTBMask)) <= 1.0 + 1e-9), ...
    "Normalized fixed-link DL trial CSV must reject effective code rates above 1 for new transport blocks.");

if usejava("jvm")
    plotInfo = sixgr.visual.plotFixedSNRSweepCurves(tmp);
    expectedPlots = [
        "reports/image/dl_bler_vs_snr.png"
        "reports/image/dl_bler_vs_snr.svg"
        "reports/image/ul_bler_vs_snr.png"
        "reports/image/ul_bler_vs_snr.svg"
        "reports/image/dl_ber_vs_snr.png"
        "reports/image/dl_ber_vs_snr.svg"
        "reports/image/ul_ber_vs_snr.png"
        "reports/image/ul_ber_vs_snr.svg"
        "reports/image/dl_throughput_vs_snr.png"
        "reports/image/dl_throughput_vs_snr.svg"
        "reports/image/ul_throughput_vs_snr.png"
        "reports/image/ul_throughput_vs_snr.svg"
        "reports/image/measured_sinr_vs_configured_snr.png"
        "reports/image/measured_sinr_vs_configured_snr.svg"
        "reports/image/fixed_snr_trials_per_point.png"
        "reports/image/fixed_snr_trials_per_point.svg"
        "reports/image/fixed_snr_ci_width_vs_snr.png"
        "reports/image/fixed_snr_ci_width_vs_snr.svg"
        "reports/image/fixed_snr_curve_dashboard.png"
        "reports/image/fixed_snr_curve_dashboard.svg"
        ];
    for relPath = expectedPlots.'
        absPath = fullfile(tmp, strrep(relPath, "/", filesep));
        assert(exist(absPath, "file") == 2, "Missing fixed-SNR plot: %s", relPath);
    end
    lineage = readtable(fullfile(tmp, "reports", "csv", "fixed_snr_plot_lineage.csv"), "VariableNamingRule", "preserve");
    assert(height(lineage) == numel(expectedPlots), ...
        "Fixed-SNR plot lineage must contain one row per emitted PNG/SVG plot file.");
    assert(all(string(lineage.Status) == "rendered"), ...
        "Fixed-SNR plot lineage must report rendered status for every required plot.");
    assert(all(strlength(string(lineage.SourceCSV_SHA256)) == 64), ...
        "Fixed-SNR plot lineage must hash each source CSV.");
    assert(numel(plotInfo.Plots) == numel(expectedPlots), ...
        "Fixed-SNR plot helper must return every rendered PNG/SVG path.");
end

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

function values = localAsLogicalVector(raw)
if islogical(raw)
    values = logical(raw);
elseif isnumeric(raw)
    values = double(raw) ~= 0;
else
    token = lower(strtrim(string(raw)));
    values = token == "1" | token == "true" | token == "yes" | token == "pass";
end
values = values(:);
end

function cfg = localFixtureConfig()
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
scfg = scfg.toStruct();
scfg.harq.k2 = 2;
scfg.random_access.enabled = false;
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "fixed_link_campaign_fixture"));
cfg.run.numFrames = 1;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.interferenceExecutionMode = "none";
cfg.run.fixedReferenceMode = true;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.pdsch.PRBSet = 0:23;
cfg.phy.pdsch.prbSet = 0:23;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.UECapability1024QAM = false;
cfg.phy.pdsch.RRCEnabled1024QAM = false;
cfg.phy.pdsch.DCIEnabled1024QAM = false;
cfg.phy.pdsch.DeploymentAllows1024QAM = false;
cfg.phy.pdsch.FrequencyRangeAllows1024QAM = false;
cfg.phy.pdsch.BandAllows1024QAM = false;
cfg.phy.pdsch.FrequencyRange = "FR1";
cfg.phy.pdsch.OperatingBand = "n77";
cfg.phy.pdsch.DeploymentClass = "macro";
cfg.phy.pdsch.DCIFormat = "1_1";
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pusch.prbSet = 0:23;
cfg.phy.pusch.PRBSet = 0:23;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.bwp.dl = struct("NStartBWP",0,"NSizeBWP",273);
cfg.phy.bwp.ul = struct("NStartBWP",0,"NSizeBWP",273);
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
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals.ptrs_enabled", false);
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
    "LinkFixedLinkErrorTarget", 1, ...
    "LinkFixedLinkCIWidthTarget", 1, ...
    "LinkFixedLinkConfidenceLevel", 0.95, ...
    "LinkFixedLinkSeed", seed, ...
    "HARQDiagnosticsEnabled", false, ...
    "LinkAnchorCases", ["DL_PDSCH_Throughput","UL_PUSCH_Throughput"], ...
    "SaveFigures", false);
end
