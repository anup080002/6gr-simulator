function ok = testMIMOPrecoderEvidence()
%TESTMIMOPRECODEREVIDENCE Multi-layer rows require explicit precoder lineage.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg();
raw = struct("DL", localRows("DL", true), "UL", localRows("UL", true));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_precoder", "StrictMode", true);
assert(all(strcmp(string(out.PrecoderEvidence.Status), "pass")), ...
    "Rank-2 rows with PMI/precoder lineage must pass precoder evidence.");
assert(all(strlength(string(out.PrecoderEvidence.SourceRowsHash)) > 0), ...
    "Precoder evidence must carry source-row hashes.");

rawMissing = struct("DL", localRows("DL", false), "UL", localRows("UL", false));
bad = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, rawMissing, "RunId", "mimo_precoder_missing", "StrictMode", true);
assert(any(strcmp(string(bad.PrecoderEvidence.Status), "fail")), ...
    "Multi-layer rows without PMI/precoder lineage must fail precoder evidence.");

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

function T = localRows(direction, withPMI)
pmi = NaN(2, 1);
if withPMI
    pmi(:) = 3;
end
T = table(repmat(string(direction), 2, 1), [1; 2], [2; 2], [2; 2], repmat("256QAM", 2, 1), ...
    [20; 20], [true; true], [true; true], [true; true], repmat("18|17", 2, 1), ...
    pmi, [1; 1], [0; 0], [1000; 1000], ...
    'VariableNames', {'Direction','TrialId','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB', ...
    'AppliedPrecoderPMI','SelectedBeamIndex','BitErrors','BitsCompared'});
end
