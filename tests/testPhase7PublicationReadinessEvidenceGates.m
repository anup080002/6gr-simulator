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
assert(double(pub.Tables.ArtifactCompleteness.ResolvedUnavailablePlotCardCount(1)) == 0, ...
    "The canonical contract fixture must not depend on stale unavailable-card aliases.");

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
terms = table(repmat("term",12,1) + string((1:12).'), repmat("AVAILABLE",12,1), ...
    'VariableNames', {'Term','Availability'});
sixgr.util.csvWriteTable(fullfile(layout.RFCSVDir, "energy_model_terms.csv"), terms);
root = table(["ue";"cell"], [1;1], [1.0;10.0], [1000;1000], [1e6;1e7], ...
    ["active_tx";"active_tx"], ["active_runtime_energy";"active_runtime_energy"], ...
    repmat("rf/csv/power_energy_table.csv", 2, 1), ...
    'VariableNames', {'entity_type','entity_id','total_energy_j','useful_bits', ...
    'energy_per_bit_nj','dominant_state','root_cause_reason','source_artifact_ref'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "energy_root_cause_table.csv"), root);

prof = table("sixgr.link.runDLPDSCHThroughput", 1, 0.25, 0.20, ...
    'VariableNames', {'FunctionName','NumCalls','TotalTime_s','SelfTimeApprox_s'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"), prof);

drops = table(repmat("DL", 6, 1), [1;1;1;2;2;2], ...
    [-4;-4;-4;8;8;8], [1;2;3;1;2;3], ...
    [101;102;103;201;202;203], [0.90;0.91;0.89;0.10;0.11;0.09], ...
    repmat("executed_trial_rows", 6, 1), ...
    'VariableNames', {'Direction','FixedLinkPointIndex','SNR_dB', ...
    'FixedLinkDropIndex','FixedLinkDropSeed','BLER','EvidenceStatus'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "multi_seed_drop_statistics.csv"), drops);

contractImages = [
    "reports/image/contract__fixed-snr-sinr-sweep-validation__measured-sinr-vs-configured-snr.png"
    "reports/image/contract__error-reliability-analytics__bler-vs-sinr.png"
    "reports/image/contract__prach-random-access__prach-peak-search-timeline.png"
    ];
sourceCsvs = [
    "reports/csv/contract__fixed-snr-sinr-sweep-validation__measured-sinr-vs-configured-snr.csv"
    "reports/csv/contract__error-reliability-analytics__bler-vs-sinr.csv"
    "reports/csv/contract__prach-random-access__prach-peak-search-timeline.csv"
    ];
for index = 1:numel(contractImages)
    localWriteTinyPNG(fullfile(runDir, strrep(char(contractImages(index)), "/", filesep)));
end
for rel = sourceCsvs(:).'
    p = fullfile(runDir, strrep(char(rel), "/", filesep));
    sixgr.util.ensureDir(p);
    writetable(table((1:3).', (4:6).', 'VariableNames', {'X','Y'}), p);
end

plotIds = [
    "contract__fixed-snr-sinr-sweep-validation__measured-sinr-vs-configured-snr"
    "contract__error-reliability-analytics__bler-vs-sinr"
    ];
manifest = table(plotIds, contractImages(1:2), sourceCsvs(1:2), sourceCsvs(1:2), ...
    true(2, 1), false(2, 1), repmat("rendered_real_plot", 2, 1), ...
    repmat("real_lls_evidence", 2, 1), ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','SourceTable','CountsAsRealPlot', ...
    'IsUnavailableCard','PlotRenderStatus','VisualValidity'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "plot_manifest.csv"), manifest);

lineage = table(plotIds, contractImages(1:2), sourceCsvs(1:2), ...
    repmat("fixture_source_hash", 2, 1), repmat("fixture_image_hash", 2, 1), ...
    repmat(1100, 2, 1), repmat(620, 2, 1), repmat("image/png", 2, 1), ...
    true(2, 1), true(2, 1), repmat("test_fixture", 2, 1), ...
    repmat("pass", 2, 1), strings(2, 1), ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','SourceCSV_SHA256','ImageSHA256', ...
    'Width','Height','MimeType','ImageExists','SourceExists','ProducerModule','Status','FailureReason'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "contract_plot_lineage.csv"), lineage);

coverage = table(2, 2, 0, 0, 2, 2, 0, 0, ...
    'VariableNames', {'tables_total','tables_available','tables_policy_disabled','tables_missing', ...
    'charts_total','charts_available','charts_policy_disabled','charts_missing'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "contract_materialization_coverage.csv"), coverage);

imageAudit = table(contractImages, repmat("pass", 3, 1), true(3, 1), ...
    false(3, 1), sourceCsvs, true(3, 1), ...
    'VariableNames', {'relative_path','status','readable','blank_or_low_information', ...
    'source_csv','source_csv_exists'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "all_image_artifact_audit.csv"), imageAudit);

generationDir = fullfile(runDir, "artifact_generation");
sixgr.util.ensureFolder(generationDir);
generation = table(true, "PASS", contractImages(3), ...
    'VariableNames', {'Required','Status','OutputRelativePath'});
sixgr.util.csvWriteTable(fullfile(generationDir, "artifact_generation_results.csv"), generation);

emptyUnavailable = table(strings(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), ...
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
