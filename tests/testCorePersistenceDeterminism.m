function ok = testCorePersistenceDeterminism()
%TESTCOREPERSISTENCEDETERMINISM Core results must not depend on artifact writes.

setup6GRSimToolkit("Verbose", false);

localCSVWriteGate();
localPMICacheDeterminism();
localPostEqSINRCacheDeterminism();
localFixedLinkCoreOnlyDeterminism();

ok = true;
end

function localCSVWriteGate()
tmp = tempname;
mkdir(tmp);
cleanupDir = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
csvPath = fullfile(tmp, "csv", "probe.csv");
T = table((1:3).', ["a";"b";"c"], 'VariableNames', {'Index','Label'});

cleanupPersistence = sixgr.util.persistenceScope(false); %#ok<NASGU>
sixgr.util.csvWriteTable(csvPath, T);
assert(exist(csvPath, "file") ~= 2, ...
    "csvWriteTable must be a no-op while persistence is disabled.");
clear cleanupPersistence;

sixgr.util.csvWriteTable(csvPath, T);
assert(exist(csvPath, "file") == 2, ...
    "csvWriteTable must resume writing after the persistence scope is restored.");
end

function localPMICacheDeterminism()
clear sixgr.phy.dl.pmiCodebookCandidates;
cfg = sixgr.config.defaultConfig();
cfg.phy.beamManagement.beamCount = 16;
cfg.phy.csi.codebookType = "type1";
cfg.phy.csi.dualPolarizedType1 = false;
cfg.phy.bsArray = [2 2 1];
cfg.antenna.bs.geometry = "ura";

[cand1, info1] = sixgr.phy.dl.pmiCodebookCandidates(cfg, 2, 4, ...
    "Mode", "type1_su_mimo", "MaxCandidates", 12);
[cand2, info2] = sixgr.phy.dl.pmiCodebookCandidates(cfg, 2, 4, ...
    "Mode", "type1_su_mimo", "MaxCandidates", 12);

assert(~logical(info1.CacheHit) && logical(info2.CacheHit), ...
    "PMI codebook cache must miss once and hit for identical immutable inputs.");
assert(strcmp(string(info1.CacheKey), string(info2.CacheKey)), ...
    "Identical PMI inputs must produce identical cache keys.");
assert(numel(cand1) == numel(cand2), "Cached PMI candidate count changed.");
for i = 1:numel(cand1)
    assert(isequaln(cand1(i).PMI, cand2(i).PMI) && ...
        max(abs(cand1(i).W(:) - cand2(i).W(:))) < 1e-15, ...
        "Cached PMI candidate %d must be numerically identical.", i);
end
end

function localPostEqSINRCacheDeterminism()
clear sixgr.phy.rx.computePostEqSINR;
H0 = [1 0.15; -0.05 0.9];
H = repmat(reshape(H0, 1, 2, 2), 32, 1, 1);
Rint = [0.25 0.03; 0.03 0.18];

[sinr1, per1, info1] = sixgr.phy.rx.computePostEqSINR(H, 0.05, ...
    "Method", "irc", "Rint", Rint, "RIncludesNoise", true, "Layers", 2);
[sinr2, per2, info2] = sixgr.phy.rx.computePostEqSINR(H, 0.05, ...
    "Method", "irc", "Rint", Rint, "RIncludesNoise", true, "Layers", 2);

assert(isfinite(double(sinr1)) && isequaln(double(sinr1), double(sinr2)), ...
    "Cached post-EQ SINR wideband value must be deterministic.");
assert(max(abs(double(per1(:)) - double(per2(:)))) < 1e-15, ...
    "Cached post-EQ SINR per-RE values must be deterministic.");
assert(~logical(info1.CacheHit) && logical(info2.CacheHit), ...
    "Post-EQ SINR equalizer cache must miss once and hit for identical immutable inputs.");
assert(strcmp(string(info1.CacheKey), string(info2.CacheKey)), ...
    "Identical post-EQ SINR inputs must produce identical cache keys.");
end

function localFixedLinkCoreOnlyDeterminism()
cfg = localFixtureConfig();
opt = localCampaignOptions(cfg, 12, 77729);

tmpPersist = tempname;
mkdir(tmpPersist);
cleanupPersist = onCleanup(@() rmdir(tmpPersist, "s")); %#ok<NASGU>
outPersist = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(tmpPersist, "air_interface"), opt);

tmpCore = tempname;
mkdir(tmpCore);
cleanupCore = onCleanup(@() rmdir(tmpCore, "s")); %#ok<NASGU>
optCore = opt;
optCore.CoreOnly = true;
optCore.PersistenceEnabled = false;
outCore = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(tmpCore, "air_interface"), optCore);

assert(logical(outPersist.PersistenceEnabled) && ~logical(outPersist.CoreOnly), ...
    "Default fixed-link bundle run must publish artifacts.");
assert(~logical(outCore.PersistenceEnabled) && logical(outCore.CoreOnly), ...
    "Core-only fixed-link bundle run must declare persistence disabled.");
persistCsv = fullfile(tmpPersist, "air_interface", "csv", "lls_fixed_link_campaign.csv");
coreCsv = fullfile(tmpCore, "air_interface", "csv", "lls_fixed_link_campaign.csv");
assert(exist(persistCsv, "file") == 2 && exist(coreCsv, "file") ~= 2, ...
    "Core-only fixed-link run must not write campaign CSV artifacts.");

T1 = outPersist.SNRSweep;
T2 = outCore.SNRSweep;
cols = ["SNR_dB","PointSeed","DL_TrialCount","DL_FailureCount","DL_BLER"];
for i = 1:numel(cols)
    assert(isequaln(double(T1.(cols(i))), double(T2.(cols(i)))), ...
        "Core-only and persisted fixed-link campaign column %s must match.", cols(i));
end
end

function cfg = localFixtureConfig()
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", "SCN00_BASELINE_CAPACITY.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "core_persistence_fixture"));
cfg.run.numFrames = 1;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.interferenceExecutionMode = "none";
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.run.seed = 4309;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 5e6;
cfg.channel.snr_dB = 12;
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
cfg.phy.pusch.enable = false;
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
cfg = sixgr.util.structSet(cfg, "lls6g.users.enabled", false);
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 1);
end

function opt = localCampaignOptions(cfg, snr, seed)
opt = struct( ...
    "LinkDuration_s", 0.001, ...
    "LinkMaxSimFrames", 1, ...
    "FixedLinkCampaignOnly", true, ...
    "LinkSNR_dB", double(cfg.channel.snr_dB), ...
    "LinkSNRGrid_dB", double(cfg.channel.snr_dB), ...
    "LinkSweepFrames", 1, ...
    "LinkSweepTrialsPerSNR", 1, ...
    "LinkSweepMaxPoints", 1, ...
    "LinkReferenceSweepFrames", 1, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkFixedLinkCampaignEnabled", true, ...
    "LinkFixedLinkSNRGrid_dB", double(snr), ...
    "LinkFixedLinkMinTrials", 1, ...
    "LinkFixedLinkMaxTrials", 1, ...
    "LinkFixedLinkTrialsPerDrop", 1, ...
    "LinkFixedLinkErrorTarget", inf, ...
    "LinkFixedLinkCIWidthTarget", inf, ...
    "LinkFixedLinkConfidenceLevel", 0.95, ...
    "LinkFixedLinkSeed", seed, ...
    "HARQDiagnosticsEnabled", false, ...
    "LinkAnchorCases", "DL_PDSCH_Throughput", ...
    "SaveFigures", false);
end
