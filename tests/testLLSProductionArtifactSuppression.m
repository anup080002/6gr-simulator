function ok = testLLSProductionArtifactSuppression()
%TESTLLSPRODUCTIONARTIFACTSUPPRESSION Suppress placeholder/disabled audit artifacts in production truth bundles.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scenarioPath = fullfile(tmp, "lls_report_production.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_report_production","description":"production truth artifact suppression","version":"1","owner":"test","maturity_tag":"baseline"},' ...
    '"simulation":{"n_frames":4,"n_slots":4,"monte_carlo_iterations":2,"snr_sweep_offsets_db":[-12,0],"random_seed":23},' ...
    '"channels":{"doppler_hz":30},' ...
    '"reference_signals":{"trs_enabled":true},' ...
    '"impairments":{"cfo_hz":40,"timing_offset_samples":16},' ...
    '"output":{"profile":"lls_report_production","save_figures":true,"save_mat":false,"emit_placeholder_artifacts":false,"emit_disabled_audit_artifacts":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "prod");
assert(out.Ok, "Production-style waveform bundle should complete.");

runFolder = char(string(out.RunFolder));
coverage = readtable(fullfile(runFolder, "reports", "csv", "lls_output_spec_coverage.csv"), ...
    "VariableNamingRule", "preserve");
detail = readtable(fullfile(runFolder, "reports", "csv", "lls_output_metric_rows.csv"), ...
    "VariableNamingRule", "preserve");
inventory = readtable(fullfile(runFolder, "reports", "csv", "artifact_inventory.csv"), ...
    "VariableNamingRule", "preserve");

assert(exist(fullfile(runFolder, "reports", "csv", "ai_ml_outputs.csv"), "file") ~= 2, ...
    "Production truth bundles must not emit disabled-only AI category CSVs.");
assert(exist(fullfile(runFolder, "reports", "csv", "ai_confidence_trace.csv"), "file") ~= 2, ...
    "Production truth bundles must not emit disabled AI confidence CSVs.");
assert(exist(fullfile(runFolder, "reports", "image", "ai_confidence_trace.png"), "file") ~= 2, ...
    "Production truth bundles must not emit disabled AI confidence images.");
assert(exist(fullfile(runFolder, "reports", "image", "access_delay_cdf.png"), "file") ~= 2, ...
    "Production truth bundles must not emit placeholder access-delay figures.");

assert(localCoverageState(coverage, "ai_confidence_traces") == "not_supported", ...
    "Suppressed disabled-AI traces must roll up as not_supported.");
assert(localCoverageState(coverage, "curves_access_delay_cdf") == "not_available", ...
    "Suppressed placeholder access-delay curves must roll up as not_available.");
assert(~localCoverageCredit(coverage, "ai_confidence_traces"), ...
    "Suppressed disabled-AI traces must not receive coverage credit.");
assert(~localCoverageCredit(coverage, "curves_access_delay_cdf"), ...
    "Suppressed placeholder access-delay curves must not receive coverage credit.");

assert(any(string(detail.MetricKey) == "ai_confidence_traces" & string(detail.Availability) == "not_supported"), ...
    "Detail rows must preserve not_supported for suppressed AI traces.");
assert(any(string(detail.MetricKey) == "curves_access_delay_cdf" & string(detail.Availability) == "not_available"), ...
    "Detail rows must preserve not_available for suppressed placeholder plots.");

assert(~any(string(inventory.RelativePath) == "reports/csv/ai_confidence_trace.csv"), ...
    "Artifact inventory must not claim a suppressed AI confidence CSV exists.");
assert(~any(string(inventory.RelativePath) == "reports/image/ai_confidence_trace.png"), ...
    "Artifact inventory must not claim a suppressed AI confidence plot exists.");
assert(~any(string(inventory.RelativePath) == "reports/image/access_delay_cdf.png"), ...
    "Artifact inventory must not claim a suppressed placeholder access-delay figure exists.");

ok = true;
end

function state = localCoverageState(T, metricKey)
mask = string(T.MetricKey) == string(metricKey);
assert(any(mask), "Coverage table is missing metric %s.", metricKey);
state = string(T.Availability(find(mask, 1, "first")));
end

function tf = localCoverageCredit(T, metricKey)
mask = string(T.MetricKey) == string(metricKey);
assert(any(mask), "Coverage table is missing metric %s.", metricKey);
tf = logical(T.CountsTowardCoverage(find(mask, 1, "first")));
end
