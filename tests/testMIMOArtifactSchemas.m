function ok = testMIMOArtifactSchemas()
%TESTMIMOARTIFACTSCHEMAS MIMO export must write source-backed artifact schemas.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfg = localCfg();
raw = struct("DL", localRows("DL"), "UL", localRows("UL"));
kpiTable = table(["DL_PDSCH_Throughput"; "UL_PUSCH_Throughput"], [true; true], [false; false], ...
    'VariableNames', {'Case','Ok','Skipped'});
details = struct("RawTrials", raw, "Config", cfg, "RunId", "mimo_artifacts", "ScenarioName", "unit");
sixgr.link.exportLinkKPIs(tmp, kpiTable, details, "SaveCSV", true, "SaveMAT", false, "SaveFigures", false);

required = [
    "beamforming/csv/mimo_config_strict.csv"
    "beamforming/csv/mimo_config_validation.csv"
    "beamforming/csv/antenna_array_config.csv"
    "beamforming/csv/antenna_port_mapping.csv"
    "beamforming/csv/rank_layer_trials.csv"
    "beamforming/csv/mimo_layer_metrics.csv"
    "beamforming/csv/mimo_configured_vs_effective.csv"
    "beamforming/csv/precoder_evidence.csv"
    "beamforming/csv/beam_codebook.csv"
    "beamforming/csv/beam_sweep_measurements.csv"
    "beamforming/csv/mimo_negative_trials.csv"
    "beamforming/csv/mimo_oracle_guard.csv"
    "reports/csv/mimo_rank_utilization_table.csv"
    "reports/json/mimo_toolbox_capabilities.json"
    ];
for i = 1:numel(required)
    assert(exist(fullfile(tmp, required(i)), "file") == 2, "Missing MIMO artifact: %s", required(i));
end
rankT = readtable(fullfile(tmp, "beamforming", "csv", "rank_layer_trials.csv"), "VariableNamingRule", "preserve");
assert(all(ismember(["ConfiguredRank","TransmittedRank","EffectiveDecodedRank","SourceRowsHash","StrictOk"], string(rankT.Properties.VariableNames))), ...
    "rank_layer_trials.csv must expose configured/transmitted/effective rank lineage and source hash.");
summaryT = readtable(fullfile(tmp, "beamforming", "csv", "mimo_configured_vs_effective.csv"), "VariableNamingRule", "preserve");
assert(all(logical(summaryT.ScenarioObjectivePass)), ...
    "Positive rank-2 MIMO artifact fixture must pass configured-vs-effective objective.");

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
cfg.mimo.rank_adaptation_policy = "fixed";
end

function T = localRows(direction)
T = table(repmat(string(direction), 2, 1), [1; 2], [2; 2], [2; 2], repmat("256QAM", 2, 1), ...
    [20; 20], [true; true], [true; true], [true; true], repmat("18|17", 2, 1), ...
    [3; 3], [1; 1], [0; 0], [1000; 1000], [1000; 1000], [1000; 1000], [1; 1], ...
    'VariableNames', {'Direction','TrialId','Layers','RankEstimate','Modulation','MCS', ...
    'CRCPass','DecodeUsable','ReceiverUsable','PostEqSINRPerLayer_dB', ...
    'AppliedPrecoderPMI','SelectedBeamIndex','BitErrors','BitsCompared', ...
    'Goodput_Mbps','TBSize_bits','AirInterfaceObservation_ms'});
end
