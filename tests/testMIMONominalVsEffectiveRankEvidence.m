function ok = testMIMONominalVsEffectiveRankEvidence()
%TESTMIMONOMINALVSEFFECTIVERANKEVIDENCE Effective rank must come from raw receiver rows.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg(2, 20, "256QAM");
raw = struct("DL", localRank2Rows("DL"), "UL", localRank2Rows("UL"));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_positive", "StrictMode", true);
assert(all(logical(out.ConfiguredVsEffective.ScenarioObjectivePass)), ...
    "Rank-2 raw receiver evidence must pass configured-vs-effective summary.");
dlRows = out.RankLayerTrials(strcmp(string(out.RankLayerTrials.Direction), "DL"), :);
assert(all(double(dlRows.EffectiveDecodedRank) == 2), ...
    "Effective decoded DL rank must be reconstructed from per-layer receiver evidence.");
assert(all(strlength(string(dlRows.LayerSINRdB)) > 0), ...
    "Rank-2 strict evidence must carry per-layer SINR lineage.");

noRaw = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, struct("DL", table(), "UL", table()), ...
    "RunId", "mimo_missing", "StrictMode", true);
assert(~logical(noRaw.StrictOk), "Nominal configuration alone must not pass as effective MIMO evidence.");
assert(all(double(noRaw.ConfiguredVsEffective.StrictEligibleRowCount) == 0), ...
    "Missing raw trial rows must remain visible in configured-vs-effective evidence.");

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

function T = localRank2Rows(direction)
T = table(repmat(string(direction), 2, 1), [1; 2], [10; 11], [1; 1], [2; 2], [2; 2], ...
    repmat("256QAM", 2, 1), [20; 20], [true; true], [true; true], [true; true], ...
    repmat("18|17", 2, 1), [0.02; 0.02], [-30; -31], [5; 5], [0; 0], [1000; 1000], ...
    [3; 3], [1; 1], repmat("csi01", 2, 1), ...
    'VariableNames', {'Direction','TrialId','Slot','Frame','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB','EVM_rms','NMSE_dB', ...
    'LLRMeanAbs','BitErrors','BitsCompared','AppliedPrecoderPMI','SelectedBeamIndex','CSIPayloadHex'});
end
