function artifacts = exportMIMOEvidenceArtifacts(runFolder, cfg, rawTrials, varargin)
%EXPORTMIMOEVIDENCEARTIFACTS Write MIMO/rank/beam evidence artifacts.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || isnumeric(x));
ip.parse(varargin{:});

runRoot = localRunRoot(runFolder);
layout = sixgr.report.resultLayout(runRoot);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(fullfile(layout.ReportDir, "json"));

evidence = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, rawTrials, ...
    "RunId", ip.Results.RunId, ...
    "ScenarioName", ip.Results.ScenarioName, ...
    "StrictMode", ip.Results.StrictMode);

artifacts = struct("Evidence", evidence, "csv", {{}}, "json", {{}});
csvSpecs = {
    fullfile(layout.BeamformingCSVDir, "mimo_config_strict.csv"), evidence.MIMOConfigStrict;
    fullfile(layout.BeamformingCSVDir, "mimo_config_validation.csv"), evidence.ConfigValidation;
    fullfile(layout.BeamformingCSVDir, "antenna_array_config.csv"), evidence.AntennaArrayConfig;
    fullfile(layout.BeamformingCSVDir, "antenna_port_mapping.csv"), evidence.AntennaPortMapping;
    fullfile(layout.BeamformingCSVDir, "rank_layer_trials.csv"), evidence.RankLayerTrials;
    fullfile(layout.BeamformingCSVDir, "mimo_layer_metrics.csv"), evidence.LayerMetrics;
    fullfile(layout.BeamformingCSVDir, "mimo_configured_vs_effective.csv"), evidence.ConfiguredVsEffective;
    fullfile(layout.BeamformingCSVDir, "precoder_evidence.csv"), evidence.PrecoderEvidence;
    fullfile(layout.BeamformingCSVDir, "beam_codebook.csv"), evidence.BeamCodebook;
    fullfile(layout.BeamformingCSVDir, "beam_sweep_measurements.csv"), evidence.BeamSweepMeasurements;
    fullfile(layout.BeamformingCSVDir, "mimo_negative_trials.csv"), evidence.NegativeTrials;
    fullfile(layout.BeamformingCSVDir, "mimo_oracle_guard.csv"), evidence.OracleGuard;
    fullfile(layout.ReportCSVDir, "mimo_rank_utilization_table.csv"), evidence.RankUtilization
    };
for i = 1:size(csvSpecs, 1)
    sixgr.util.csvWriteTable(csvSpecs{i, 1}, csvSpecs{i, 2});
    artifacts.csv{end+1} = csvSpecs{i, 1}; %#ok<AGROW>
end
jsonPath = fullfile(layout.ReportDir, "json", "mimo_toolbox_capabilities.json");
sixgr.util.jsonWrite(jsonPath, evidence.ToolboxCapabilities);
artifacts.json{end+1} = jsonPath;
end

function root = localRunRoot(runFolder)
runFolder = char(string(runFolder));
[parent, leaf] = fileparts(runFolder);
if strcmpi(leaf, "air_interface") && strlength(string(parent)) > 0
    root = parent;
else
    root = runFolder;
end
end
