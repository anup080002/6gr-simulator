function ok = testMIMOBeamCodebookAndSweep()
%TESTMIMOBEAMCODEBOOKANDSWEEP Beam evidence must be source-backed.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg();
raw = struct("DL", localRows("DL", true), "UL", localRows("UL", true));
out = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, raw, "RunId", "mimo_beam", "StrictMode", true);
assert(height(out.BeamCodebook) > 0 && all(strlength(string(out.BeamCodebook.WeightVectorHash)) > 0), ...
    "Beam codebook evidence must include source-backed beam IDs and hashes.");
assert(all(strcmp(string(out.BeamSweepMeasurements.Status), "pass")), ...
    "Rows with selected beam IDs must pass beam sweep provenance.");

rawMissing = struct("DL", localRows("DL", false), "UL", localRows("UL", false));
bad = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, rawMissing, "RunId", "mimo_beam_missing", "StrictMode", true);
assert(any(strcmp(string(bad.BeamSweepMeasurements.Status), "fail")), ...
    "Multi-layer rows without selected beam/source evidence must fail beam sweep provenance.");

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

function T = localRows(direction, withBeam)
beam = NaN(2, 1);
if withBeam
    beam(:) = 1;
end
T = table(repmat(string(direction), 2, 1), [1; 2], [2; 2], [2; 2], repmat("256QAM", 2, 1), ...
    [20; 20], [true; true], [true; true], [true; true], repmat("18|17", 2, 1), ...
    [3; 3], beam, [0; 0], [1000; 1000], ...
    'VariableNames', {'Direction','TrialId','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB', ...
    'AppliedPrecoderPMI','SelectedBeamIndex','BitErrors','BitsCompared'});
end
