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

fullCfg = cfg;
fullCfg.scenario.ue.nTxAnt = 4;
fullCfg.scenario.bs.nRxAnt = 64;
fullCfg.channel.nTxAntUL = 4;
fullCfg.channel.nRxAntUL = 64;
fullCfg.phy.beamManagement.hybridBeamformingEnabled = true;
fullRaw = struct("DL", localFullElementRows("DL"), ...
    "UL", localFullElementRows("UL"));
fullOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(fullCfg,fullRaw, ...
    "RunId","mimo_full_element_positive","StrictMode",true);
assert(logical(fullOut.StrictOk), ...
    "Physical 64x4/4x64 channel participation plus logical rank-2 execution must pass strict MIMO evidence.");
assert(all(logical(fullOut.AntennaArrayConfig.ExactRuntimeAntennaMatch)));
assert(all(logical(fullOut.AntennaArrayConfig.LogicalPortLayerMatch)));
assert(isequal(double(fullOut.AntennaArrayConfig.ObservedPhysicalTxAntennaCount(:)),[64;4]));
assert(isequal(double(fullOut.AntennaArrayConfig.ObservedPhysicalRxAntennaCount(:)),[4;64]));

adaptiveCfg = fullCfg;
adaptiveCfg.link_adaptation.fixed_or_amc = "amc";
adaptiveRaw = fullRaw;
adaptiveRaw.DL.Modulation(:) = "QPSK";
adaptiveRaw.DL.MCS(:) = 1;
adaptiveRaw.UL.Modulation(:) = "16QAM";
adaptiveRaw.UL.MCS(:) = 10;
adaptiveOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,adaptiveRaw, ...
    "RunId","mimo_fixed_rank_amc","StrictMode",true);
assert(all(logical(adaptiveOut.MIMOConfigStrict.FixedAnchorMode)) && ...
    all(logical(adaptiveOut.MIMOConfigStrict.AdaptiveMode)), ...
    "Fixed-rank anchoring and AMC must remain independent runtime controls.");
assert(logical(adaptiveOut.StrictOk) && ...
    all(double(adaptiveOut.ConfiguredVsEffective.ExactMatchPercent) >= 0.999), ...
    "AMC-selected modulation/MCS changes must not be mislabeled as MIMO rank/antenna mismatches.");

lowSNRRaw = adaptiveRaw;
lowSNRRaw.DL.CRCPass(1) = false;
lowSNRRaw.DL.DecodeUsable(1) = false;
lowSNRRaw.DL.ReceiverUsable(1) = false;
lowSNRRaw.UL.CRCPass(1) = false;
lowSNRRaw.UL.DecodeUsable(1) = false;
lowSNRRaw.UL.ReceiverUsable(1) = false;
lowSNROut = sixgr.mimo.resolveNominalVsEffectiveMIMO(adaptiveCfg,lowSNRRaw, ...
    "RunId","mimo_fixed_rank_amc_low_snr","StrictMode",true);
assert(all(double(lowSNROut.ConfiguredVsEffective.ExactMatchPercent) >= 0.999) && ...
    all(logical(lowSNROut.ConfiguredVsEffective.ScenarioObjectivePass)), ...
    "Low-SNR CRC failures must remain reliability failures, not false rank/layer execution mismatches.");
failedRows = lowSNROut.RankLayerTrials(~logical(lowSNROut.RankLayerTrials.DecodeCrcPass), :);
assert(all(double(failedRows.TransmittedRank) == 2) && ...
    all(double(failedRows.EffectiveDecodedRank) == 0) && ...
    all(logical(failedRows.ExactConfiguredMatch)), ...
    "MIMO evidence must preserve transmitted rank two while keeping failed decoded rank explicitly zero.");

badRaw = fullRaw;
badRaw.DL.BSAntennaNumPorts(:) = 2;
badOut = sixgr.mimo.resolveNominalVsEffectiveMIMO(fullCfg,badRaw, ...
    "RunId","mimo_full_element_bad","StrictMode",true);
assert(~logical(badOut.StrictOk), ...
    "Logical rank-2 ports must not be mislabeled as a 64-element physical transmit path.");

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

function T = localFullElementRows(direction)
T = localRank2Rows(direction);
if upper(string(direction)) == "UL"
    T.NumTxPorts = repmat(4,height(T),1);
    T.NumRxAntennas = repmat(64,height(T),1);
else
    T.NumTxPorts = repmat(64,height(T),1);
    T.NumRxAntennas = repmat(4,height(T),1);
end
T.PrecodingNumLayers = repmat(2,height(T),1);
T.BSAntennaNumPorts = repmat(64,height(T),1);
T.UEAntennaNumPorts = repmat(4,height(T),1);
T.AntennaRuntimeObjectCreated = true(height(T),1);
T.ChannelUsesSameRuntimeAntennaAssumptions = true(height(T),1);
end
