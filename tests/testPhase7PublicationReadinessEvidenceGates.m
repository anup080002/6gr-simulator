function ok = testPhase7PublicationReadinessEvidenceGates()
%TESTPHASE7PUBLICATIONREADINESSEVIDENCEGATES Guard terminal gate closure.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = localCfg();
localWriteTerminalEvidence(tmp);

pub = sixgr.analytics.evaluatePublicationReadinessGates(cfg, tmp);
for name = ["EnergyModelOk","PerformanceProfileOk","LongRunStabilityOk", ...
        "ArtifactCompletenessOk","PlotDataLineageOk","FinalScientificClaimsTruthfulOk"]
    assert(logical(pub.Flags.(char(name))), "Expected terminal gate to pass: %s", name);
end
assert(double(pub.Tables.ArtifactCompleteness.ResolvedUnavailablePlotCardCount(1)) == 3, ...
    "Stale unavailable rows for replaced plots/access CDF must be resolved only by verified artifacts.");

artifactProfilerCfg = cfg;
artifactProfilerCfg.output.profiler_enabled = false;
artifactProfilerCfg.run_control.time_profiling_enable = false;
artifactOnly = sixgr.analytics.evaluatePublicationReadinessGates(artifactProfilerCfg, tmp);
assert(logical(artifactOnly.Flags.PerformanceProfileOk), ...
    "PerformanceProfileOk must accept runner profiler artifacts even when only persisted evidence is available.");
assert(endsWith(string(artifactOnly.Tables.Performance.ProfilerArtifactCSV(1)), ...
    "reports/csv/runtime_function_profile.csv"), ...
    "Performance gate must recognize the runner's runtime_function_profile.csv artifact.");

report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);
assert(isfield(report, "Gates"), "Phase 7 report must include gate status.");
gates = readtable(fullfile(tmp, "reports", "csv", "phase7_truth_gates.csv"), ...
    "VariableNamingRule", "preserve", "TextType", "string");
for name = ["EnergyModelOk","PerformanceProfileOk","LongRunStabilityOk", ...
        "ArtifactCompletenessOk","PlotDataLineageOk","FinalScientificClaimsTruthfulOk"]
    assert(localAsLogical(gates.(char(name))(1)), "Phase 7 did not consume terminal gate: %s", name);
end
assert(~localAsLogical(gates.Phase7Ok(1)), ...
    "Terminal evidence alone must not force Phase7Ok when lower-phase evidence is missing.");
assert(~localAsLogical(gates.PublicationReadinessOk(1)), ...
    "PublicationReadinessOk must remain fail-closed without every Phase 7 gate.");

tmpMissing = tempname;
mkdir(tmpMissing);
cleanupMissing = onCleanup(@() rmdir(tmpMissing, "s")); %#ok<NASGU>
missing = sixgr.analytics.evaluatePublicationReadinessGates(cfg, tmpMissing);
assert(~logical(missing.Flags.EnergyModelOk), "Missing energy evidence must fail closed.");
assert(~logical(missing.Flags.PerformanceProfileOk), "Missing runtime profile evidence must fail closed.");
assert(~logical(missing.Flags.LongRunStabilityOk), "Missing long-run evidence must fail closed.");
assert(~logical(missing.Flags.ArtifactCompletenessOk), "Missing artifact evidence must fail closed.");
assert(~logical(missing.Flags.PlotDataLineageOk), "Missing plot lineage evidence must fail closed.");

ok = true;
end

function cfg = localCfg()
cfg = struct();
cfg.output.profiler_enabled = true;
cfg.canonical_control.run.num_seeds = 3;
cfg.canonical_control.run.max_bler_std = 0.05;
cfg.run_control.total_slots = 10;
cfg.frame_timing.slot_duration_ms = 0.5;
cfg.mobility.user_paths = struct([]);
end

function localWriteTerminalEvidence(runDir)
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.MetaDir);
sixgr.util.ensureFolder(layout.RFCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
reportJSONDir = fullfile(layout.ReportDir, "json");
finalReportDir = fullfile(layout.ReportDir, "final");
sixgr.util.ensureFolder(reportJSONDir);
sixgr.util.ensureFolder(finalReportDir);

sixgr.util.jsonWrite(fullfile(layout.MetaDir, "runtime_summary.json"), ...
    struct("ElapsedSeconds", 12.5, "StartedUTC", "2026-06-29T00:00:00Z", ...
    "CompletedUTC", "2026-06-29T00:00:12Z"));
sixgr.util.jsonWrite(fullfile(reportJSONDir, "scenario_manifest.json"), struct("Fixture", "publication_gate"));

energy = table( ...
    ["ue_energy_per_successful_bit";"gnb_energy_per_successful_bit";"first_delivered_bits"], ...
    ["UE";"gNB";"system"], ["mean";"mean";"total"], [4e-7;2e-4;1000], ...
    ["observed";"observed";"observed"], ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','Availability'});
sixgr.util.csvWriteTable(fullfile(layout.RFCSVDir, "probe_rf_energy.csv"), energy);
root = table(["ue";"cell"], [1;1], [1.0;10.0], [1000;1000], [1e6;1e7], ...
    ["active_tx";"active_tx"], ["active_runtime_energy";"active_runtime_energy"], ...
    repmat("rf/csv/power_energy_table.csv", 2, 1), ...
    'VariableNames', {'entity_type','entity_id','total_energy_j','useful_bits', ...
    'energy_per_bit_nj','dominant_state','root_cause_reason','source_artifact_ref'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "energy_root_cause_table.csv"), root);

prof = table("sixgr.link.runDLPDSCHThroughput", 1, 0.25, 0.20, ...
    'VariableNames', {'FunctionName','NumCalls','TotalTime_s','SelfTimeApprox_s'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"), prof);

drops = table(["DL";"DL";"DL"], [1;2;3], [101;102;103], [0.10;0.11;0.09], ...
    repmat("executed_trial_rows", 3, 1), ...
    'VariableNames', {'Direction','FixedLinkDropIndex','FixedLinkDropSeed','BLER','EvidenceStatus'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "multi_seed_drop_statistics.csv"), drops);

requiredImages = [
    "bler_vs_measured_sinr.png"
    "throughput_vs_measured_sinr.png"
    "measured_sinr_distribution.png"
    "distance_vs_sinr.png"
    "access_delay_cdf.png"
    "power_energy_cumulative.png"
    ];
for img = requiredImages(:).'
    localWriteTinyPNG(fullfile(layout.ReportImageDir, img));
end
ia = table(1, 1, 1, 0, 0, 0.0, "RA_COMPLETE", "access_complete", ...
    "complete", true, false, false, 5.5, 5.5, ...
    'VariableNames', {'Step','UEIndex','RNTI','Frame','Slot','Time_s','StageName', ...
    'EventName','StageStatus','CompleteFlag','PlaceholderFlag','FallbackFlag', ...
    'ProcedureDelay_ms','AccessDelay_ms'});
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"), ia);

sourceCsvs = [
    "air_interface/csv/dl_measured_sinr_bler_curve.csv"
    "air_interface/csv/dl_measured_sinr_throughput_curve.csv"
    "air_interface/csv/measured_sinr_distribution.csv"
    "air_interface/csv/distance_vs_sinr.csv"
    "control/csv/initial_access_lifecycle_trace.csv"
    "rf/csv/power_energy_table.csv"
    ];
for rel = sourceCsvs(:).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    sixgr.util.ensureDir(p);
    writetable(table((1:3).', (4:6).', 'VariableNames', {'X','Y'}), p);
end

plotIds = erase(requiredImages, ".png");
manifest = table(plotIds, "reports/image/" + requiredImages, sourceCsvs, sourceCsvs, ...
    true(numel(requiredImages), 1), false(numel(requiredImages), 1), ...
    repmat("rendered_real_plot", numel(requiredImages), 1), ...
    repmat("real_lls_evidence", numel(requiredImages), 1), ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','SourceTable','CountsAsRealPlot', ...
    'IsUnavailableCard','PlotRenderStatus','VisualValidity'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "plot_manifest.csv"), manifest);
chart = manifest(:, {'PlotId','SourceCSV','SourceTable','PlotRenderStatus','VisualValidity'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "chart_source_registry.csv"), chart);
lineage = table(plotIds(1:4), "reports/image/" + requiredImages(1:4), sourceCsvs(1:4), ...
    true(4, 1), true(4, 1), repmat("complete", 4, 1), ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','ImageExists','SourceExists','LineageStatus'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "measurement_sinr_plot_lineage.csv"), lineage);
emptyUnavailable = table(["bler_vs_snr";"throughput_vs_snr";"access_delay_cdf"], ...
    ["reports/image/bler_vs_snr_unavailable.svg";"reports/image/throughput_vs_snr_unavailable.svg";"reports/image/access_delay_cdf_unavailable.svg"], ...
    ["reports/csv/bler_vs_snr.csv";"reports/csv/throughput_vs_snr.csv";"control/csv/initial_access_lifecycle_trace.csv"], ...
    repmat("stale_unavailable_card_replaced_by_verified_artifact", 3, 1), ...
    repmat("unavailable", 3, 1), ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','PlotSuppressionReason','VisualValidity'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "unavailable_plot_card_registry.csv"), emptyUnavailable);

claims = table(["publication_ready";"full_route_mobility_study"], ...
    ["unsupported_until_all_phase7_gates_pass";"unsupported_until_full_route_run"], ...
    ["reports/csv/phase7_truth_gates.csv";"mobility/csv/trajectory_resolution.csv"], ...
    'VariableNames', {'claim','support_status','evidence_artifact'});
sixgr.util.csvWriteTable(fullfile(finalReportDir, "final_scientific_claims_matrix.csv"), claims);
end

function localWriteTinyPNG(path)
sixgr.util.ensureDir(path);
fid = fopen(path, "w");
assert(fid > 0, "Could not write fixture image %s", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8([137 80 78 71 13 10 26 10]));
end

function tf = localAsLogical(values)
if islogical(values)
    tf = logical(values(:));
elseif isnumeric(values)
    v = double(values(:));
    tf = isfinite(v) & v ~= 0;
else
    token = lower(strtrim(string(values(:))));
    tf = token == "1" | token == "true" | token == "yes" | token == "pass" | token == "passed" | token == "ok";
end
end
