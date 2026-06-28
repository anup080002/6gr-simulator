function ok = testCorePersistenceDeterminism()
%TESTCOREPERSISTENCEDETERMINISM Core results must not depend on artifact writes.

setup6GRSimToolkit("Verbose", false);

localCSVWriteGate();
localPMICacheDeterminism();
localPostEqSINRCacheDeterminism();
localDeterministicTaskPlan();
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

function localDeterministicTaskPlan()
snrGrid = [-2 0 4];
plan = sixgr.util.buildDeterministicTaskPlan(99123, snrGrid, ["DL", "UL"], ...
    "MaxTrials", 5, ...
    "TrialsPerDrop", 2, ...
    "IncludePointTasks", true);

pointRows = string(plan.TaskKind) == "point_metadata";
workRows = string(plan.TaskKind) == "point_drop_link";
assert(nnz(pointRows) == numel(snrGrid), ...
    "Task plan must include one deterministic point metadata row per SNR point.");
assert(all(double(plan.TrialCount(workRows)) > 0) && all(double(plan.TrialCount(workRows)) <= 2), ...
    "Drop tasks must carry bounded trial counts for coarse-grain execution.");
assert(numel(unique(double(plan.TaskSeed))) == height(plan), ...
    "Every coarse task must receive a unique immutable seed.");
assert(all(string(plan.SchedulingInvariant) == "worker_order_independent_seed_per_task"), ...
    "Task plan must declare worker-order-independent seed assignment.");
assert(all(string(plan.PersistencePhase) == "post_run_or_disabled"), ...
    "Task plan must keep persistence outside task execution rows.");

serialSig = localTaskSignature(plan);
reordered = plan([height(plan):-1:1], :);
parallelLike = sortrows(reordered, "TaskIndex");
parallelSig = localTaskSignature(parallelLike);
assert(isequaln(serialSig, parallelSig), ...
    "Task outputs derived only from immutable task seeds must be invariant to worker completion order.");

expectedDLSeed = sixgr.util.hierarchicalSeed(99123, 2, 1, 0, "DL");
mask = double(plan.PointIndex) == 2 & double(plan.DropIndex) == 1 & string(plan.LinkToken) == "DL";
assert(any(mask) && double(plan.TaskSeed(find(mask, 1, "first"))) == expectedDLSeed, ...
    "Task-plan DL seed must use the canonical hierarchical seed function.");
end

function sig = localTaskSignature(plan)
sig = zeros(height(plan), 1);
for i = 1:height(plan)
    rs = RandStream("mt19937ar", "Seed", double(plan.TaskSeed(i)));
    sig(i) = rand(rs) + double(plan.PointIndex(i)) * 1e-3 + double(plan.DropIndex(i)) * 1e-5;
end
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

P1 = outPersist.FixedLinkCampaign.TaskPlan;
P2 = outCore.FixedLinkCampaign.TaskPlan;
assert(istable(P1) && istable(P2) && height(P1) == height(P2) && height(P1) > 0, ...
    "Persisted and core-only fixed-link runs must both expose the deterministic task plan.");
for c = ["TaskIndex","PointIndex","DropIndex","TrialStartIndex","TrialCount","PointSeed","TaskSeed"]
    assert(isequaln(double(P1.(c)), double(P2.(c))), ...
        "Core-only and persisted task-plan column %s must match.", c);
end
assert(isequal(string(P1.TaskKey), string(P2.TaskKey)) && isequal(string(P1.LinkToken), string(P2.LinkToken)), ...
    "Core-only and persisted task-plan identities must match.");
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
