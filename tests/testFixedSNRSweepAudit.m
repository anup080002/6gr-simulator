function ok = testFixedSNRSweepAudit()
%TESTFIXEDSNRSWEEPAUDIT Fixed-SNR sweep audit must pass good evidence and fail bad evidence.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanupObj = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

snrGrid = [0 8 16];
trialsPerPoint = 20;
cfg = localFixtureConfig();
opt = localCampaignOptions(cfg, snrGrid, trialsPerPoint, 271828);

sixgr.truth.runWaveformLinkBundle(cfg, fullfile(tmp, "air_interface"), opt); %#ok<NASGU>
if usejava("jvm")
    sixgr.visual.plotFixedSNRSweepCurves(tmp);
end
localWriteAuditPrereqs(tmp, snrGrid, trialsPerPoint);

audit = sixgr.validation.auditFixedSNRSweepRun(tmp, "Strict", false, "WriteOutputs", true);
if ~logical(audit.Ok)
    disp(audit.Table(string(audit.Table.Status)=="FAIL",:));
    disp(audit.FailureCodes);
end
assert(logical(audit.Ok), "A correct fixed SNR sweep fixture must pass the fixed-sweep audit.");
assert(exist(fullfile(tmp, "reports", "csv", "fixed_snr_sweep_audit.csv"), "file") == 2, ...
    "The fixed-sweep audit CSV must be written.");
assert(exist(fullfile(tmp, "reports", "csv", "fixed_snr_sweep_monotonicity_audit.csv"), "file") == 2, ...
    "The monotonicity audit CSV must be written.");
assert(exist(fullfile(tmp, "reports", "csv", "fixed_snr_sweep_required_outputs.csv"), "file") == 2, ...
    "The required-outputs audit CSV must be written.");
assert(exist(fullfile(tmp, "reports", "json", "fixed_snr_sweep_audit.json"), "file") == 2, ...
    "The fixed-sweep audit JSON must be written.");

ulCurvePath = fullfile(tmp, "reports", "csv", "ul_fixed_snr_bler_curve.csv");
ulCurve = readtable(ulCurvePath, "VariableNamingRule", "preserve", "TextType", "string");
sixgr.util.csvWriteTable(ulCurvePath, ulCurve([],:));
auditMissingUL = sixgr.validation.auditFixedSNRSweepRun(tmp, "Strict", false, "WriteOutputs", false);
assert(~logical(auditMissingUL.Ok), "An empty UL BLER curve must fail the fixed-sweep audit.");
assert(any(contains(string(auditMissingUL.FailureCodes), "ul_curve_missing_or_empty")) || ...
    any(contains(string(auditMissingUL.FailureCodes), "required_output_missing_or_empty")), ...
    "The fixed-sweep audit must explain that the UL curve is missing or empty.");

sixgr.util.csvWriteTable(ulCurvePath, ulCurve);
dlCurvePath = fullfile(tmp, "reports", "csv", "dl_fixed_snr_bler_curve.csv");
dlCurve = readtable(dlCurvePath, "VariableNamingRule", "preserve", "TextType", "string");
dlCurve.BLER(1) = 1.2;
dlCurve.BLER_CI_Low(1) = 1.1;
dlCurve.BLER_CI_High(1) = 1.3;
dlCurve.BLER_CI_Width(1) = 0.2;
sixgr.util.csvWriteTable(dlCurvePath, dlCurve);
auditInvalidBLER = sixgr.validation.auditFixedSNRSweepRun(tmp, "Strict", false, "WriteOutputs", false);
assert(~logical(auditInvalidBLER.Ok), "BLER values above 1 must fail the fixed-sweep audit.");
assert(any(contains(string(auditInvalidBLER.FailureCodes), "bler_out_of_range")) || ...
    any(contains(string(auditInvalidBLER.FailureCodes), "bler_ci_invalid")), ...
    "The fixed-sweep audit must flag invalid BLER evidence.");

ok = true;
end

function cfg = localFixtureConfig()
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
scfg = scfg.toStruct();
scfg.harq.k2 = 2;
scfg.random_access.enabled = false;
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "fixed_snr_sweep_audit_fixture"));
cfg.run.numFrames = 1;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.interferenceExecutionMode = "none";
cfg.run.fixedReferenceMode = true;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.pdsch.PRBSet = 0:23;
cfg.phy.pdsch.prbSet = 0:23;
cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
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
cfg.phy.pusch.mcsIndex = 4;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.bwp.dl = struct("NStartBWP",0,"NSizeBWP",24);
cfg.phy.bwp.ul = struct("NStartBWP",0,"NSizeBWP",24);
cfg.run.seed = 4207;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 10e6;
cfg.channel.snr_dB = 18;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.channelBandwidth_MHz = 10;
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

function localWriteAuditPrereqs(runFolder, snrGrid, trialsPerPoint)
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.MetaDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

resolved = struct();
resolved.validation = struct( ...
    "run_class", "fixed_snr_sweep_lls", ...
    "fixed_snr_sweep_required", true);
resolved.sweeps_and_matrix = struct( ...
    "fixed_link_calibration", struct( ...
        "enabled", true, ...
        "only", true, ...
        "direction", "both", ...
        "snr_db", double(snrGrid(:)).', ...
        "min_trials", double(trialsPerPoint), ...
        "max_trials", double(trialsPerPoint), ...
        "ci_width_target", 10.0, ...
        "confidence_level", 0.95, ...
        "max_sinr_snr_delta_db", 10.0, ...
        "target_bler", 0.1));
resolved.simulation = struct("noise_operating_mode", "standalone_awgn_snr_argument");
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_config_resolved.json"), resolved);

runClassT = table( ...
    "fixed_snr_sweep_lls", true, true, true, false, ...
    "4", "QPSK", 1, 1, 1.0, false, ...
    "fixed_snr_sweep_lls uses dedicated fixed-sweep audit gating.", ...
    'VariableNames', {'RunClass','FixedMCSActive','RankFixed','ModulationFixed','AdaptiveMode', ...
    'ConfiguredMCS','ConfiguredModulation','ConfiguredRank','ConfiguredLayers', ...
    'ExactConfiguredEffectiveMatchRate','PublicationLLSEligible','Reason'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "run_classification.csv"), runClassT);
end
