function ok = testMIMOFixedRank2AnchorNoCollapse()
%TESTMIMOFIXEDRANK2ANCHORNOCOLLAPSE Fixed rank-2 anchor must fail collapse.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg(2, 20, "256QAM");
raw = struct("DL", localCollapsedRows("DL"), "UL", localCollapsedRows("UL"));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_collapse", "StrictMode", true);

assert(~logical(out.StrictOk), "Strict MIMO evidence must fail when rank/layer/MCS collapse is observed.");
assert(all(~logical(out.ConfiguredVsEffective.ScenarioObjectivePass)), ...
    "Configured-vs-effective summary must fail fixed rank-2 collapse.");
assert(all(contains(string(out.RankLayerTrials.MismatchCause), "effective_rank_mismatch")), ...
    "Rank collapse must be visible in per-trial mismatch cause.");
assert(any(strcmp(string(out.NegativeTrials.NegativeTrialType), "configured_effective_collapse")), ...
    "A negative/falsification row must be exported for fixed-anchor collapse.");

ok = true;
end

function cfg = localCfg(layers, mcs, modulation)
cfg = struct();
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfg.channel.nTxAnt = 64;
cfg.channel.nRxAnt = 4;
cfg.phy.pdsch.numLayers = layers;
cfg.phy.pdsch.nLayers = layers;
cfg.phy.pdsch.mcsIndex = mcs;
cfg.phy.pdsch.modulation = modulation;
cfg.phy.pdsch.NumAntennaPorts = 4;
cfg.phy.pusch.numLayers = layers;
cfg.phy.pusch.nLayers = layers;
cfg.phy.pusch.mcsIndex = mcs;
cfg.phy.pusch.modulation = modulation;
cfg.phy.pusch.NumAntennaPorts = layers;
cfg.link_adaptation.fixed_or_amc = "fixed";
cfg.mimo.rank_adaptation_policy = "fixed";
end

function T = localCollapsedRows(direction)
T = table(repmat(string(direction), 2, 1), [1; 2], [10; 11], [1; 1], [1; 1], [1; 1], ...
    repmat("QPSK", 2, 1), [1; 1], [true; true], [true; true], [true; true], ...
    repmat("12", 2, 1), [0.04; 0.04], [-20; -20], [3; 3], [0; 0], [1000; 1000], ...
    [0; 0], [0; 0], repmat("", 2, 1), ...
    'VariableNames', {'Direction','TrialId','Slot','Frame','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB','EVM_rms','NMSE_dB', ...
    'LLRMeanAbs','BitErrors','BitsCompared','AppliedPrecoderPMI','SelectedBeamIndex','CSIPayloadHex'});
end
