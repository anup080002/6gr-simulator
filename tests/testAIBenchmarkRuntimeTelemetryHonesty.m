function ok = testAIBenchmarkRuntimeTelemetryHonesty()
%TESTAIBENCHMARKRUNTIMETELEMETRYHONESTY Keep AI outputs config_only until measured runtime telemetry exists.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(tmp, "ce_ai_reporting.yaml");
s = struct();
s.inherits = {fullfile(pwd, "simulator", "configs", "scenarios", "ce_ai_nn.yaml")};
s.meta = struct( ...
    "scenario_id", "ce_ai_reporting", ...
    "description", "ai reporting honesty check", ...
    "version", "1", ...
    "owner", "test", ...
    "maturity_tag", "smoke");
s.ai_ml = struct("benchmark_observations", 2);
s.output = struct("save_figures", false, "save_mat", false);
fid = fopen(scenarioPath, "w");
fwrite(fid, jsonencode(s), "char");
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
runFolder = char(string(out.RunFolder));

benchmarkCsv = fullfile(runFolder, "reports", "csv", "ai_channel_estimation_benchmark.csv");
coverageCsv = fullfile(runFolder, "reports", "csv", "lls_output_spec_coverage.csv");
assert(exist(benchmarkCsv, "file") == 2, "Missing AI benchmark CSV.");
assert(exist(coverageCsv, "file") == 2, "Missing AI coverage CSV.");

benchT = readtable(benchmarkCsv, 'Delimiter', ',', 'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(ismember("ConfidenceScore", string(benchT.Properties.VariableNames)), ...
    "AI benchmark CSV should export ConfidenceScore column.");
assert(all(isnan(double(benchT.ConfidenceScore))), ...
    "ConfidenceScore must stay NaN until measured runtime confidence telemetry exists.");

coverageT = readtable(coverageCsv, 'Delimiter', ',', 'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
metricKeys = ["model_parameters","ai_flops","memory_footprint","ai_inference_latency","ai_confidence_traces","fallback_rate"];
for i = 1:numel(metricKeys)
    row = coverageT(string(coverageT.MetricKey) == metricKeys(i), :);
    assert(height(row) == 1, "Expected a single coverage row for %s.", metricKeys(i));
    assert(string(row.Availability(1)) == "config_only", ...
        "%s should remain config_only without measured runtime AI telemetry.", metricKeys(i));
    assert(~logical(row.CountsTowardCoverage(1)), ...
        "%s must not count toward runtime coverage without measured telemetry.", metricKeys(i));
end

ok = true;
end
