function ok = testMIMOOracleGuard()
%TESTMIMOORACLEGUARD Effective rank cannot equal config without receiver evidence.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg();
raw = struct("DL", localOracleLookingRows("DL"), "UL", localOracleLookingRows("UL"));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_oracle", "StrictMode", true);

assert(any(strcmp(string(out.RankLayerTrials.Status), "fail")), ...
    "Rows that only look like nominal rank without per-layer receiver evidence must fail strict trial evidence.");
assert(all(strcmp(string(out.OracleGuard.Status), "pass")), ...
    "Oracle guard must pass because the implementation refuses to produce effective rank from config alone.");
assert(all(~isfinite(double(out.RankLayerTrials.EffectiveDecodedRank))), ...
    "EffectiveDecodedRank must remain unavailable when per-layer receiver evidence is missing.");

ok = true;
end

function cfg = localCfg()
cfg = struct();
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.mcsIndex = 20;
cfg.phy.pdsch.modulation = "256QAM";
cfg.phy.pdsch.NumAntennaPorts = 4;
cfg.phy.pusch.numLayers = 2;
cfg.phy.pusch.nLayers = 2;
cfg.phy.pusch.mcsIndex = 20;
cfg.phy.pusch.modulation = "256QAM";
cfg.phy.pusch.NumAntennaPorts = 2;
cfg.link_adaptation.fixed_or_amc = "fixed";
end

function T = localOracleLookingRows(direction)
T = table(repmat(string(direction), 1, 1), 1, 2, 2, "256QAM", 20, true, true, true, "", ...
    3, 1, 0, 1000, ...
    'VariableNames', {'Direction','TrialId','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB', ...
    'AppliedPrecoderPMI','SelectedBeamIndex','BitErrors','BitsCompared'});
end
