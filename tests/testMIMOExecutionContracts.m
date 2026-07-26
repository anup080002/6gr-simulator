function ok = testMIMOExecutionContracts()
%TESTMIMOEXECUTIONCONTRACTS Rank-2, MU-MIMO and multi-TRP execution contracts.

setup6GRSimToolkit("Verbose", false);

localRank2ULSchedulerAnchor();
localUnsupportedFixedRankThrows();
localMUMIMOCompositeAndBeamLoss();
localMultiTRPCoherentCombining();
localRuntimeWrapper();

ok = true;
end

function localRank2ULSchedulerAnchor()
cfg = localRankCfg(2, 2);
scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "UL");
ue = struct("RNTI", 101, "CQI", 12, "RI", 2);
[~, nLayers, ~, amc] = scheduler.selectAMC(ue);

assert(double(nLayers) == 2, ...
    "Waveform fading UL fixed rank-2 must not collapse to one layer when ports/codebook support rank-2.");
assert(~logical(amc.RankDowngradeApplied), ...
    "Rank-2 anchor must execute without a downgrade flag.");
assert(strcmp(string(amc.RankDecisionReason), "waveform_fading_ul_rank_supported_by_ports_and_codebook"), ...
    "Scheduler must disclose why the legacy UL single-layer guard was not applied.");
end

function localUnsupportedFixedRankThrows()
cfg = localRankCfg(2, 1);
scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "UL");
ue = struct("RNTI", 102, "CQI", 12, "RI", 2);
threw = false;
try
    scheduler.selectAMC(ue);
catch ME
    threw = strcmp(ME.identifier, "sixgr:mimo:RankExecutionPolicy:UnsupportedFixedRank");
end
assert(threw, ...
    "Unsupported fixed rank-2 on one UL port must throw before grant/waveform generation.");
end

function localMUMIMOCompositeAndBeamLoss()
cfg = struct();
cfg.phy.noiseVariance = 1e-3;
tx = localTwoUserTx(false);
rx = localTwoUserRx();
out = sixgr.mimo.executeSpatialComposite(tx, rx, cfg, "NoiseVariance", 1e-3, "Mode", "mu_mimo");

assert(logical(out.SimultaneousSharedPRB), ...
    "Two MU users must be represented as simultaneous shared-PRB contributors.");
assert(norm(out.Rx(1).DesiredWaveform - tx(1).Symbols, "fro") < 1e-12 && ...
    norm(out.Rx(2).DesiredWaveform - tx(2).Symbols, "fro") < 1e-12, ...
    "Zero-forcing beams must deliver each user's intended layer symbols through the matching channel.");
assert(out.Rx(1).InterferencePower < 1e-12 && out.Rx(2).InterferencePower < 1e-12, ...
    "Orthogonal beams/channels must produce negligible MU leakage in the deterministic anchor.");

orthogonalBaseline = 0.5 .* sum([out.Rx.Rate_bpsHz]);
assert(double(out.SumRate_bpsHz) > double(orthogonalBaseline) + 1, ...
    "Simultaneous MU-MIMO sum rate must exceed a half-resource orthogonal baseline for the same SINR.");

badTx = localTwoUserTx(true);
bad = sixgr.mimo.executeSpatialComposite(badTx, rx, cfg, "NoiseVariance", 1e-3, "Mode", "mu_mimo");
loss_dB = out.Rx(1).SINR_dB - bad.Rx(1).SINR_dB;
assert(isfinite(loss_dB) && loss_dB > 25, ...
    "Bad-beam A/B test must produce a large predicted SINR loss in the actual composite.");
end

function localMultiTRPCoherentCombining()
cfg = struct();
cfg.phy.noiseVariance = 1e-6;
n = 8;
tx(1) = struct("SourceId", "trp1", "TRPId", "trp1", "UserId", "ue1", ...
    "Symbols", ones(n, 1), "Precoder", 1, "PowerScale", 1, ...
    "PhaseRad", 0, "Muted", false, "PRBSet", 0:3);
tx(2) = tx(1);
tx(2).SourceId = "trp2";
tx(2).TRPId = "trp2";
rx = struct("UserId", "ue1", "Channel", {{1, 1}});

both = sixgr.mimo.executeSpatialComposite(tx, rx, cfg, ...
    "NoiseVariance", 1e-6, "Mode", "multi_trp", "CombiningMode", "coherent");
txMuted = tx;
txMuted(2).Muted = true;
muted = sixgr.mimo.executeSpatialComposite(txMuted, rx, cfg, ...
    "NoiseVariance", 1e-6, "Mode", "multi_trp", "CombiningMode", "coherent");

assert(max(abs(both.Rx(1).DesiredWaveform(:) - 2)) < 1e-12, ...
    "Two coherent equal-phase TRPs must add in sample amplitude.");
gain_dB = 10 .* log10(both.Rx(1).DesiredPower ./ muted.Rx(1).DesiredPower);
assert(abs(gain_dB - 6.020599913279624) < 1e-9, ...
    "Muting one equal coherent TRP must remove exactly the 6.02 dB combining gain.");
end

function localRuntimeWrapper()
cfg = struct();
cfg.phy.noiseVariance = 1e-3;
out = sixgr.truth.CoupledTruthRuntime.executeMIMOCompositeRuntime( ...
    localTwoUserTx(false), localTwoUserRx(), cfg, "NoiseVariance", 1e-3);
assert(strcmp(string(out.RuntimeConsumer), "sixgr.truth.CoupledTruthRuntime.executeMIMOCompositeRuntime"), ...
    "Coupled runtime must expose the causal MIMO composite execution hook.");
assert(size(out.Rx(1).ContributionTensor, 3) == 2, ...
    "Runtime composite must retain per-source contribution tensors.");
end

function cfg = localRankCfg(requestedLayers, ports)
cfg = sixgr.config.defaultConfig();
cfg.system.phyBackend = "waveform";
cfg.channel.awgnOnly = false;
cfg.channel.model = "TDL-C";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.fading.enable = true;
cfg.scenario.ue.nTxAnt = ports;
cfg.scenario.bs.nRxAnt = 4;
cfg.phy.nTxAnt = ports;
cfg.phy.nRxAnt = 4;
cfg.phy.pusch.nLayers = requestedLayers;
cfg.phy.pusch.numLayers = requestedLayers;
cfg.phy.pusch.maxLayers = requestedLayers;
cfg.phy.pusch.NumAntennaPorts = ports;
cfg.phy.pusch.transmissionScheme = "codebook";
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.5;
cfg.phy.pusch.mcsIndex = 4;
cfg.phy.mimo.maxRank = requestedLayers;
cfg.phy.linkAdaptation.rankPolicy = "fixed_rank_anchor";
cfg.mimo.rank_adaptation_policy = "fixed_rank_anchor";
cfg.mac.scheduler.direction = "UL";
end

function tx = localTwoUserTx(badBeam)
n = 8;
tx(1) = struct("SourceId", "gnb_ue1", "TRPId", "trp0", "UserId", "ue1", ...
    "Symbols", ones(n, 1), "Precoder", [1; 0], "PowerScale", 1, ...
    "PhaseRad", 0, "Muted", false, "PRBSet", 0:7);
tx(2) = struct("SourceId", "gnb_ue2", "TRPId", "trp0", "UserId", "ue2", ...
    "Symbols", 1i .* ones(n, 1), "Precoder", [0; 1], "PowerScale", 1, ...
    "PhaseRad", 0, "Muted", false, "PRBSet", 0:7);
if badBeam
    tx(1).Precoder = [0; 1];
end
end

function rx = localTwoUserRx()
rx(1) = struct("UserId", "ue1", "Channel", {{[1 0], [1 0]}});
rx(2) = struct("UserId", "ue2", "Channel", {{[0 1], [0 1]}});
end
