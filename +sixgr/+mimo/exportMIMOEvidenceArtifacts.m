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

tpResolve = sixgr.perf.TimeProfiler.scope("sixgr.mimo.resolveNominalVsEffectiveMIMO", ...
    "Stage", "mimo_nominal_effective_resolution");
resolvedTrials = sixgr.kpi.loadDirectionRawTables( ...
    struct("RawTrials", rawTrials, "Config", cfg), ...
    "RunFolder", runRoot, "PreferPersistedPrimary", true);
evidence = sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg, resolvedTrials, ...
    "RunId", ip.Results.RunId, ...
    "ScenarioName", ip.Results.ScenarioName, ...
    "StrictMode", ip.Results.StrictMode);
clear tpResolve;

% The runner consumes supplemental validators through a small common
% contract (StrictOk/Ok/FailureReason).  Keep the complete evidence object,
% but do not make callers infer its status from the generated files.
% Missing status is deliberately fail-closed because runSingle defaults an
% absent supplemental status to false.
strictOk = logical(sixgr.util.structGet(evidence, "StrictOk", false));
failureReason = string(sixgr.util.structGet(evidence, "FailureReason", ""));
if strictOk
    failureReason = "";
elseif strlength(strtrim(failureReason)) == 0
    failureReason = "mimo_strict_evidence_failed";
end
artifacts = struct( ...
    "Evidence", evidence, ...
    "StrictOk", strictOk, ...
    "Ok", strictOk, ...
    "FailureReason", char(failureReason), ...
    "csv", {{}}, ...
    "json", {{}});
artifacts.PrimarySourceReconciliation = resolvedTrials.PrimarySourceReconciliation;
csvSpecs = {
    fullfile(layout.BeamformingCSVDir, "mimo_primary_trial_source_reconciliation.csv"), resolvedTrials.PrimarySourceReconciliation;
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
    fullfile(layout.BeamformingCSVDir, "mimo_strict_gate_summary.csv"), evidence.StrictGateSummary;
    fullfile(layout.ReportCSVDir, "mimo_rank_utilization_table.csv"), evidence.RankUtilization
    };
for i = 1:size(csvSpecs, 1)
    % MIMO evidence tables are versioned interfaces.  Columns that are
    % deliberately not applicable in the current operating mode (for
    % example RequiredExactMatchPercent during AMC, or an empty adaptive
    % failure reason on a passing row) still describe the contract.  The
    % generic CSV writer otherwise prunes those all-missing/all-empty
    % columns before the later sanitizer has a chance to preserve them.
    sixgr.util.csvWriteTable(csvSpecs{i, 1}, csvSpecs{i, 2}, ...
        "PreserveSchema", true);
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
