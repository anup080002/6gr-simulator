function ok = testMIMOConfiguredVsEffectiveSummary()
%TESTMIMOCONFIGUREDVSEFFECTIVESUMMARY Summary must reconstruct from trials.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg();
raw = struct("DL", [localRows("DL", true); localRows("DL", false)], ...
    "UL", [localRows("UL", true); localRows("UL", false)]);
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_summary", "StrictMode", true);
summary = out.ConfiguredVsEffective;
assert(all(double(summary.StrictEligibleRowCount) == 4), ...
    "Configured-vs-effective summary must count strict-eligible raw trial rows.");
assert(all(double(summary.ExactMatchRowCount) == 2), ...
    "Exact-match count must be reconstructed from per-trial rank/layer/modulation/MCS evidence.");
assert(all(abs(double(summary.ExactMatchPercent) - 0.5) < 1e-12), ...
    "Exact-match percentage must be reconstructed from raw trial rows.");
assert(all(~logical(summary.ScenarioObjectivePass)), ...
    "Fixed-anchor objective must fail when exact-match percentage is below threshold.");

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

function T = localRows(direction, match)
if match
    layers = [2; 2]; mod = repmat("256QAM", 2, 1); mcs = [20; 20]; sinr = repmat("18|17", 2, 1);
else
    layers = [1; 1]; mod = repmat("QPSK", 2, 1); mcs = [1; 1]; sinr = repmat("12", 2, 1);
end
T = table(repmat(string(direction), 2, 1), [1; 2], layers, layers, mod, mcs, ...
    [true; true], [true; true], [true; true], sinr, [3; 3], [1; 1], [0; 0], [1000; 1000], ...
    'VariableNames', {'Direction','TrialId','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB', ...
    'AppliedPrecoderPMI','SelectedBeamIndex','BitErrors','BitsCompared'});
end
