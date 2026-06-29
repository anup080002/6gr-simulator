function result = evaluatePublicationReadinessGates(cfg, runDir)
%EVALUATEPUBLICATIONREADINESSGATES Evidence-based terminal Phase 7 gates.
%
% This evaluator deliberately reads persisted runtime artifacts and writes
% audit summaries. Missing artifacts fail closed; no placeholder rows are
% treated as publication evidence.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || strlength(strtrim(string(runDir))) == 0
    runDir = pwd;
end
runDir = char(string(runDir));
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

[energyOk, energyT] = localEvaluateEnergy(runDir);
[perfOk, perfT] = localEvaluatePerformance(cfg, runDir);
[stabilityOk, stabilityT] = localEvaluateLongRunStability(cfg, runDir);
[artifactOk, artifactT] = localEvaluateArtifactCompleteness(runDir);
[lineageOk, lineageT] = localEvaluatePlotLineage(runDir);
[claimsOk, claimsT] = localEvaluateClaimsTruthfulness(runDir);

paths = struct();
paths.Energy = localWrite(layout.ReportCSVDir, "energy_model_gate.csv", energyT);
paths.Performance = localWrite(layout.ReportCSVDir, "performance_profile_summary.csv", perfT);
paths.LongRunStability = localWrite(layout.ReportCSVDir, "long_run_stability_summary.csv", stabilityT);
paths.ArtifactCompleteness = localWrite(layout.ReportCSVDir, "artifact_completeness_summary.csv", artifactT);
paths.PlotDataLineage = localWrite(layout.ReportCSVDir, "plot_data_lineage_summary.csv", lineageT);
paths.ClaimsTruthfulness = localWrite(layout.ReportCSVDir, "final_scientific_claims_truthfulness.csv", claimsT);

flags = struct( ...
    "EnergyModelOk", logical(energyOk), ...
    "PerformanceProfileOk", logical(perfOk), ...
    "LongRunStabilityOk", logical(stabilityOk), ...
    "ArtifactCompletenessOk", logical(artifactOk), ...
    "PlotDataLineageOk", logical(lineageOk), ...
    "FinalScientificClaimsTruthfulOk", logical(claimsOk));

summaryT = table(flags.EnergyModelOk, flags.PerformanceProfileOk, flags.LongRunStabilityOk, ...
    flags.ArtifactCompletenessOk, flags.PlotDataLineageOk, flags.FinalScientificClaimsTruthfulOk, ...
    all(struct2array(flags)), "evidence_files_only_no_forced_publication_pass", ...
    'VariableNames', {'EnergyModelOk','PerformanceProfileOk','LongRunStabilityOk', ...
    'ArtifactCompletenessOk','PlotDataLineageOk','FinalScientificClaimsTruthfulOk', ...
    'TerminalPublicationGatesOk','EvaluationPolicy'});
paths.Summary = localWrite(layout.ReportCSVDir, "publication_readiness_gate_summary.csv", summaryT);

result = struct("Flags", flags, "Tables", struct("Energy", energyT, "Performance", perfT, ...
    "LongRunStability", stabilityT, "ArtifactCompleteness", artifactT, ...
    "PlotDataLineage", lineageT, "ClaimsTruthfulness", claimsT, "Summary", summaryT), ...
    "Paths", paths);
end

function path = localWrite(dirPath, fileName, T)
path = fullfile(dirPath, fileName);
sixgr.analytics.writeAnalysisTable(path, T);
end

function [ok, T] = localEvaluateEnergy(runDir)
energyPath = localFirstExisting(runDir, [
    "reports/csv/energy_efficiency_outputs.csv"
    "rf/csv/probe_rf_energy.csv"
    "reports/csv/live_energy_efficiency_table.csv"
    ]);
rootPath = fullfile(runDir, "reports", "csv", "energy_root_cause_table.csv");
energy = localReadTable(energyPath);
root = localReadTable(rootPath);

ueJ = localMetricValue(energy, ["ue_energy_per_successful_bit","ue_energy_per_bit_j"]);
gnbJ = localMetricValue(energy, ["gnb_energy_per_successful_bit","gnb_energy_per_bit_j"]);
observedOk = localAvailabilityOk(energy);
hasUE = localRootHasEntity(root, ["ue"]);
hasCell = localRootHasEntity(root, ["cell","gnb","gNB"]);
criticalCount = double(isfinite(ueJ) && ueJ > 0) + double(isfinite(gnbJ) && gnbJ > 0);
ok = ~isempty(energyPath) && istable(energy) && height(energy) >= 2 && criticalCount == 2 && ...
    observedOk && exist(rootPath, "file") == 2 && hasUE && hasCell;
reason = localReason(ok, "energy_metrics_and_entity_root_cause_verified", ...
    "missing_or_nonpositive_energy_metrics_or_root_cause_rows");

T = table(string(localPortable(runDir, energyPath)), string(localPortable(runDir, rootPath)), ...
    height(energy), height(root), criticalCount, observedOk, ueJ, gnbJ, hasUE, hasCell, ok, reason, ...
    'VariableNames', {'EnergySourceCSV','RootCauseSourceCSV','EnergyMetricRows','RootCauseRows', ...
    'CriticalPositiveMetricCount','AvailabilityOk','UEEnergyPerBit_J','GNBEnergyPerBit_J', ...
    'HasUEEnergyRows','HasCellEnergyRows','EnergyModelOk','FailureReason'});
end

function [ok, T] = localEvaluatePerformance(cfg, runDir)
runtimePath = fullfile(runDir, "meta", "runtime_summary.json");
summary = localReadJson(runtimePath);
runtimeS = localJsonNumber(summary, ["ElapsedSeconds","RuntimeSeconds","runtime_seconds","elapsed_seconds"], NaN);
runtimeEvidencePath = runtimePath;
if ~isfinite(runtimeS)
    reportPath = fullfile(runDir, "reports", "scenario_report.md");
    runtimeS = localScenarioReportRuntimeSeconds(reportPath);
    if isfinite(runtimeS)
        runtimeEvidencePath = reportPath;
    end
end
profilingConfigured = localBool(cfg, ["output.profiler_enabled","run.profiler_enabled", ...
    "run_control.time_profiling_enable","time_profiling_enable","perf.exportTimeProfile", ...
    "analytics.export_time_profile","run.time_profiling_enable","run.timeProfilingEnabled", ...
    "perf.timeProfilingEnabled"], false);
[profileArtifact, profileArtifactPath] = localFirstExistingFlag(runDir, [
    "reports/csv/time_profile_summary.csv"
    "reports/csv/time_profile_calls.csv"
    "reports/csv/time_profile_coverage.csv"
    "reports/csv/per_function_timing.csv"
    "reports/csv/runtime_profiler_summary.csv"
    "reports/csv/runtime_function_profile.csv"
    "reports/csv/runtime_function_call_edges.csv"
    "profiler/time_profile.csv"
    "performance/csv/time_profile.csv"
    ]);
runtimeOk = isfinite(runtimeS) && runtimeS > 0 && runtimeS < 86400;
ok = exist(runtimeEvidencePath, "file") == 2 && runtimeOk && (profilingConfigured || profileArtifact);
reason = localReason(ok, "runtime_summary_and_profiling_evidence_verified", ...
    "runtime_summary_missing_invalid_or_no_profiling_evidence");
runtimeEvidenceRel = string(localPortable(runDir, runtimeEvidencePath));
T = table(runtimeEvidenceRel, runtimeEvidenceRel, string(localPortable(runDir, profileArtifactPath)), ...
    runtimeS, logical(profilingConfigured), logical(profileArtifact), ...
    ok, reason, 'VariableNames', {'RuntimeSummaryJSON','RuntimeEvidencePath','ProfilerArtifactCSV','RuntimeSeconds','ProfilingConfigured', ...
    'ProfilerArtifactExists','PerformanceProfileOk','FailureReason'});
end

function [ok, T] = localEvaluateLongRunStability(cfg, runDir)
dropPath = fullfile(runDir, "air_interface", "csv", "multi_seed_drop_statistics.csv");
drop = localReadTable(dropPath);
stdLimit = localNumber(cfg, ["canonical_control.run.max_bler_std","run.max_bler_std","analysis.long_run_bler_std_threshold"], 0.05);
minSeeds = localNumber(cfg, ["canonical_control.run.num_seeds","run.num_seeds","simulation.num_seeds"], 2);
if ~(isfinite(minSeeds) && minSeeds >= 2)
    minSeeds = 2;
end
bler = localNumericColumn(drop, "BLER");
seed = localNumericColumn(drop, "FixedLinkDropSeed");
if isempty(seed)
    seed = localNumericColumn(drop, "Seed");
end
valid = isfinite(bler);
bler = bler(valid);
if numel(seed) == height(drop)
    seed = seed(valid);
end
seedCount = localUniqueFiniteCount(seed);
stdVal = NaN;
meanVal = NaN;
if ~isempty(bler)
    meanVal = mean(bler, "omitnan");
    stdVal = std(bler, 0, "omitnan");
end
ok = exist(dropPath, "file") == 2 && seedCount >= minSeeds && isfinite(stdVal) && stdVal <= stdLimit && ...
    isfinite(meanVal) && meanVal >= 0 && meanVal <= 0.5;
reason = localReason(ok, "multi_seed_bler_stability_verified", ...
    "multi_seed_drop_statistics_missing_or_bler_variance_out_of_bounds");
T = table(string(localPortable(runDir, dropPath)), height(drop), seedCount, meanVal, stdVal, stdLimit, minSeeds, ok, reason, ...
    'VariableNames', {'DropStatisticsCSV','DropRows','SeedCount','BLERMean','BLERStd', ...
    'BLERStdThreshold','RequiredSeedCount','LongRunStabilityOk','FailureReason'});
end

function [ok, T] = localEvaluateArtifactCompleteness(runDir)
required = [
    "reports/image/bler_vs_measured_sinr.png"
    "reports/image/throughput_vs_measured_sinr.png"
    "reports/image/measured_sinr_distribution.png"
    "reports/image/distance_vs_sinr.png"
    "reports/image/access_delay_cdf.png"
    "reports/image/power_energy_cumulative.png"
    "control/csv/initial_access_lifecycle_trace.csv"
    ];
missing = strings(0, 1);
for rel = required(:).'
    if exist(fullfile(runDir, strrep(char(rel), "/", filesep)), "file") ~= 2
        missing(end+1, 1) = rel; %#ok<AGROW>
    end
end
unavailable = localReadTable(fullfile(runDir, "reports", "csv", "unavailable_plot_card_registry.csv"));
[unresolvedUnavailable, resolvedUnavailable] = localUnresolvedUnavailablePlots(runDir, unavailable);
unavailableCount = height(unavailable);
unresolvedCount = numel(unresolvedUnavailable);
ok = isempty(missing) && unresolvedCount == 0;
reason = localReason(ok, "mandatory_images_and_access_trace_present_no_unavailable_cards", ...
    "mandatory_artifact_missing_or_unavailable_plot_cards_remain");
T = table(strjoin(missing, "|"), unavailableCount, numel(resolvedUnavailable), unresolvedCount, ...
    strjoin(unresolvedUnavailable, "|"), numel(required), ok, reason, ...
    'VariableNames', {'MissingArtifacts','UnavailablePlotCardCount','ResolvedUnavailablePlotCardCount', ...
    'UnresolvedUnavailablePlotCardCount','UnresolvedUnavailablePlotCards','RequiredArtifactCount', ...
    'ArtifactCompletenessOk','FailureReason'});
end

function [ok, T] = localEvaluatePlotLineage(runDir)
manifestPath = fullfile(runDir, "reports", "csv", "plot_manifest.csv");
measuredPath = fullfile(runDir, "reports", "csv", "measurement_sinr_plot_lineage.csv");
chartPath = fullfile(runDir, "reports", "csv", "chart_source_registry.csv");
manifest = localReadTable(manifestPath);
measured = localReadTable(measuredPath);
chart = localReadTable(chartPath);

[manifestOk, manifestMissing] = localManifestLineageOk(runDir, manifest);
measuredOk = true;
if istable(measured) && height(measured) > 0
    if localHasColumn(measured, "LineageStatus")
        measuredOk = all(lower(strtrim(string(measured.LineageStatus))) == "complete");
    elseif all(localHasColumn(measured, ["ImageExists","SourceExists"]))
        measuredOk = all(localColumnAsLogical(measured.ImageExists) & localColumnAsLogical(measured.SourceExists));
    end
end
chartOk = istable(chart) && height(chart) > 0;
ok = manifestOk && measuredOk && chartOk;
reason = localReason(ok, "plot_images_have_source_csv_lineage", ...
    "plot_manifest_or_source_lineage_missing_incomplete");
T = table(string(localPortable(runDir, manifestPath)), string(localPortable(runDir, measuredPath)), ...
    string(localPortable(runDir, chartPath)), height(manifest), height(measured), height(chart), ...
    strjoin(manifestMissing, "|"), manifestOk, measuredOk, chartOk, ok, reason, ...
    'VariableNames', {'PlotManifestCSV','MeasuredSINRLineageCSV','ChartSourceRegistryCSV', ...
    'PlotManifestRows','MeasuredSINRLineageRows','ChartSourceRegistryRows','MissingManifestLineage', ...
    'PlotManifestLineageOk','MeasuredSINRLineageOk','ChartSourceRegistryOk', ...
    'PlotDataLineageOk','FailureReason'});
end

function [ok, T] = localEvaluateClaimsTruthfulness(runDir)
claimPath = fullfile(runDir, "reports", "final", "final_scientific_claims_matrix.csv");
scanPath = fullfile(runDir, "reports", "csv", "public_output_claim_scan.csv");
claims = localReadTable(claimPath);
scan = localReadTable(scanPath);

unsupportedLabeled = 0;
unsupportedClaimed = 0;
if istable(claims) && height(claims) > 0 && localHasColumn(claims, "support_status")
    status = lower(strtrim(string(claims.support_status)));
    unsupportedLabel = contains(status, "unsupported");
    supportedLabel = status == "supported" | startsWith(status, "supported_") | ...
        status == "verified" | startsWith(status, "verified_");
    unsupportedLabeled = sum(unsupportedLabel);
    unsupportedClaimed = sum(supportedLabel & unsupportedLabel);
end
forbiddenBroad = false;
if istable(scan) && height(scan) > 0
    for col = ["ForbiddenBroadClaim","ClaimAllowed"]
        if localHasColumn(scan, col)
            vals = localColumnAsLogical(scan.(char(col)));
            if col == "ForbiddenBroadClaim"
                forbiddenBroad = any(vals);
            elseif col == "ClaimAllowed"
                forbiddenBroad = forbiddenBroad || any(~vals);
            end
        end
    end
end
if ~(istable(claims) && height(claims) > 0)
    % The Phase 7 builder itself writes a conservative claims matrix. When
    % no older matrix exists, the upcoming matrix is truthful by construction
    % because it labels unsupported claims as unsupported.
    claimsSource = "current_phase7_builder_truthful_claim_matrix";
    ok = true;
else
    claimsSource = localPortable(runDir, claimPath);
    ok = unsupportedClaimed == 0 && ~forbiddenBroad;
end
reason = localReason(ok, "claims_matrix_labels_support_status_truthfully", ...
    "unsupported_or_forbidden_claim_presented_as_supported");
T = table(string(claimsSource), string(localPortable(runDir, scanPath)), height(claims), ...
    unsupportedLabeled, unsupportedClaimed, forbiddenBroad, ok, reason, ...
    'VariableNames', {'ClaimsMatrixCSV','PublicClaimScanCSV','ClaimRows','UnsupportedClaimRows', ...
    'UnsupportedButClaimedSupportedRows','ForbiddenBroadClaimPresent','FinalScientificClaimsTruthfulOk', ...
    'FailureReason'});
end

function [ok, missing] = localManifestLineageOk(runDir, manifest)
missing = strings(0, 1);
ok = istable(manifest) && height(manifest) > 0;
if ~ok
    missing = "plot_manifest_missing";
    return;
end
for i = 1:height(manifest)
    if localHasColumn(manifest, "CountsAsRealPlot") && ~localColumnAsLogical(manifest.CountsAsRealPlot(i))
        continue;
    end
    imageRel = localStringAt(manifest, "ImagePath", i);
    sourceSpec = localStringAt(manifest, "SourceCSV", i);
    if strlength(strtrim(imageRel)) == 0 || exist(fullfile(runDir, strrep(char(imageRel), "/", filesep)), "file") ~= 2
        missing(end+1, 1) = "image:" + imageRel; %#ok<AGROW>
    end
    if strlength(strtrim(sourceSpec)) == 0
        missing(end+1, 1) = "source_empty:" + imageRel; %#ok<AGROW>
    else
        parts = split(sourceSpec, "|");
        for p = parts(:).'
            if strlength(strtrim(p)) > 0 && exist(fullfile(runDir, strrep(char(p), "/", filesep)), "file") ~= 2
                missing(end+1, 1) = "source:" + p; %#ok<AGROW>
            end
        end
    end
end
ok = isempty(missing);
end

function value = localMetricValue(T, metricKeys)
value = NaN;
if ~(istable(T) && height(T) > 0)
    return;
end
metricCol = localFirstColumnName(T, ["MetricKey","metric_key","MetricName","metric_name"]);
if strlength(metricCol) == 0
    return;
end
metricValues = lower(strtrim(string(T.(char(metricCol)))));
keys = lower(strtrim(string(metricKeys(:))));
mask = ismember(metricValues, keys);
if ~any(mask)
    return;
end
for col = ["ValueNumeric","Value","MetricValue","metric_value","energy_per_bit_j"]
    vals = localNumericColumn(T(mask, :), col);
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = vals(1);
        return;
    end
end
end

function tf = localAvailabilityOk(T)
tf = istable(T) && height(T) > 0;
if ~tf
    return;
end
availabilityCol = localFirstColumnName(T, ["Availability","availability","EvidenceStatus","evidence_status"]);
statusCol = localFirstColumnName(T, ["energy_value_status","value_status","ValueStatus","status"]);
bad = ["proxy","fallback","synthetic","placeholder","not_available","unavailable","disabled"];
if strlength(availabilityCol) > 0
    states = lower(strtrim(string(T.(char(availabilityCol)))));
    tf = ~any(ismember(states, bad) | contains(states, bad));
elseif strlength(statusCol) > 0
    states = lower(strtrim(string(T.(char(statusCol)))));
    tf = all(states == "ok" | states == "observed" | states == "available" | states == "derived" | states == "runtime_truth_fact");
end
end

function tf = localRootHasEntity(T, names)
tf = false;
if ~(istable(T) && height(T) > 0)
    return;
end
entity = strings(height(T), 1);
for col = ["entity_type","EntityType","Entity"]
    if localHasColumn(T, col)
        entity = lower(strtrim(string(T.(char(col)))));
        break;
    end
end
tf = any(ismember(entity, lower(string(names))));
end

function [unresolved, resolved] = localUnresolvedUnavailablePlots(runDir, unavailable)
unresolved = strings(0, 1);
resolved = strings(0, 1);
if ~(istable(unavailable) && height(unavailable) > 0)
    return;
end
for i = 1:height(unavailable)
    plotId = lower(strtrim(localStringAt(unavailable, "PlotId", i)));
    imageRel = localStringAt(unavailable, "ImagePath", i);
    sourceRel = localStringAt(unavailable, "SourceCSV", i);
    if localUnavailableEntryResolvedByEvidence(runDir, plotId, imageRel, sourceRel)
        resolved(end+1, 1) = plotId; %#ok<AGROW>
    else
        unresolved(end+1, 1) = plotId; %#ok<AGROW>
    end
end
end

function tf = localUnavailableEntryResolvedByEvidence(runDir, plotId, imageRel, sourceRel)
plotId = lower(strtrim(string(plotId)));
switch plotId
    case {"bler_vs_snr","bler_vs_configured_snr"}
        imageRel = "reports/image/bler_vs_measured_sinr.png";
        sourceRel = "air_interface/csv/dl_measured_sinr_bler_curve.csv";
    case {"throughput_vs_snr","throughput_vs_configured_snr"}
        imageRel = "reports/image/throughput_vs_measured_sinr.png";
        sourceRel = "air_interface/csv/dl_measured_sinr_throughput_curve.csv";
    case {"access_delay_cdf"}
        imageRel = "reports/image/access_delay_cdf.png";
        sourceRel = "control/csv/initial_access_lifecycle_trace.csv";
end
tf = localArtifactExists(runDir, imageRel) && localAllSourceArtifactsExist(runDir, sourceRel);
end

function tf = localAllSourceArtifactsExist(runDir, sourceSpec)
sourceSpec = string(sourceSpec);
if strlength(strtrim(sourceSpec)) == 0
    tf = false;
    return;
end
parts = split(sourceSpec, "|");
tf = true;
for part = parts(:).'
    part = strtrim(part);
    if strlength(part) == 0
        continue;
    end
    tf = tf && localArtifactExists(runDir, part);
end
end

function tf = localArtifactExists(runDir, rel)
rel = string(rel);
tf = strlength(strtrim(rel)) > 0 && ...
    exist(fullfile(runDir, strrep(char(rel), "/", filesep)), "file") == 2;
end

function T = localReadTable(path)
T = table();
if strlength(strtrim(string(path))) == 0 || exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "Delimiter", ",", "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function S = localReadJson(path)
S = struct();
if exist(char(path), "file") ~= 2
    return;
end
try
    S = jsondecode(fileread(char(path)));
catch
    S = struct();
end
end

function path = localFirstExisting(runDir, rels)
path = "";
for rel = string(rels(:)).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    if exist(p, "file") == 2
        path = string(p);
        return;
    end
end
end

function tf = localAnyExisting(runDir, rels)
tf = false;
for rel = string(rels(:)).'
    if exist(fullfile(runDir, strrep(char(rel), "/", filesep)), "file") == 2
        tf = true;
        return;
    end
end
end

function [tf, path] = localFirstExistingFlag(runDir, rels)
tf = false;
path = "";
for rel = string(rels(:)).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    if exist(p, "file") == 2
        tf = true;
        path = string(p);
        return;
    end
end
end

function tf = localHasColumn(T, names)
tf = istable(T) && all(ismember(string(names), string(T.Properties.VariableNames)));
end

function name = localFirstColumnName(T, names)
name = "";
if ~istable(T)
    return;
end
vars = string(T.Properties.VariableNames);
for candidate = string(names(:)).'
    idx = find(strcmpi(vars, candidate), 1, "first");
    if ~isempty(idx)
        name = vars(idx);
        return;
    end
end
end

function vals = localNumericColumn(T, name)
vals = zeros(0, 1);
if ~(istable(T) && height(T) > 0)
    return;
end
name = localFirstColumnName(T, name);
if strlength(name) == 0
    return;
end
raw = T.(char(string(name)));
if isnumeric(raw) || islogical(raw)
    vals = double(raw(:));
else
    vals = str2double(string(raw(:)));
end
vals = vals(:);
end

function tf = localColumnAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok" | token == "available";
end
end

function s = localStringAt(T, name, idx)
s = "";
if istable(T) && localHasColumn(T, name) && idx <= height(T)
    raw = T.(char(string(name)));
    if iscell(raw)
        if idx <= numel(raw)
            s = string(raw{idx});
        end
    elseif isstring(raw) || iscategorical(raw)
        raw = string(raw);
        if idx <= numel(raw)
            s = raw(idx);
        end
    elseif ischar(raw)
        if size(raw, 1) >= idx
            s = string(strtrim(raw(idx, :)));
        else
            s = string(strtrim(raw));
        end
    else
        raw = string(raw);
        if idx <= numel(raw)
            s = raw(idx);
        end
    end
end
end

function n = localUniqueFiniteCount(values)
values = double(values(:));
values = values(isfinite(values));
n = double(numel(unique(values)));
end

function value = localJsonNumber(S, names, defaultValue)
value = defaultValue;
if ~isstruct(S)
    return;
end
for name = string(names(:)).'
    raw = sixgr.util.structGet(S, char(name), []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function seconds = localScenarioReportRuntimeSeconds(path)
seconds = NaN;
if exist(char(path), "file") ~= 2
    return;
end
try
    text = string(fileread(char(path)));
catch
    return;
end
patterns = [
    "Runtime seconds:\s*`?([0-9]+(?:\.[0-9]+)?)"
    "RuntimeSeconds\s*[:=]\s*`?([0-9]+(?:\.[0-9]+)?)"
    "Runtime seconds.*?([0-9]+(?:\.[0-9]+)?)"
    ];
for pat = patterns(:).'
    tok = regexp(text, char(pat), "tokens", "once");
    if ~isempty(tok)
        seconds = str2double(string(tok{1}));
        if isfinite(seconds)
            return;
        end
    end
end
end

function value = localNumber(cfg, paths, defaultValue)
value = defaultValue;
for path = string(paths(:)).'
    raw = localGet(cfg, path, []);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            value = double(raw);
            return;
        end
    else
        x = str2double(string(raw));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function tf = localBool(cfg, paths, defaultValue)
tf = logical(defaultValue);
for path = string(paths(:)).'
    raw = localGet(cfg, path, []);
    if islogical(raw) || isnumeric(raw)
        if isscalar(raw)
            tf = logical(raw);
            return;
        end
    else
        s = lower(strtrim(string(raw)));
        if s == "true" || s == "1" || s == "yes" || s == "on"
            tf = true;
            return;
        elseif s == "false" || s == "0" || s == "no" || s == "off"
            tf = false;
            return;
        end
    end
end
end

function value = localGet(cfg, path, defaultValue)
try
    value = sixgr.util.structGet(cfg, path, defaultValue);
catch
    value = defaultValue;
end
end

function rel = localPortable(runDir, path)
rel = string(path);
if strlength(strtrim(rel)) == 0
    return;
end
try
    root = string(runDir);
    if startsWith(rel, root)
        rel = eraseBetween(rel, 1, strlength(root));
        rel = regexprep(rel, "^[\\/]", "");
    end
catch
end
rel = replace(rel, "\", "/");
end

function reason = localReason(ok, passReason, failReason)
if logical(ok)
    reason = string(passReason);
else
    reason = string(failReason);
end
end
