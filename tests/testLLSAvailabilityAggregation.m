function ok = testLLSAvailabilityAggregation()
%TESTLLSAVAILABILITYAGGREGATION Guard semantic availability rollups in the LLS report bundle.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanup = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_4x4_rank2_bidirectional_focused_validation.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
manifest = struct("CodeVersion", "test", "CodeDetail", "clean", ...
    "RandomSeed", 23, "GeneratedUTC", "test", "RunnerProfile", "test", ...
    "RunCompletion", "failed", "DeterministicMode", "test");
sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, ...
    struct("Ok", false), manifest, ...
    struct("StartedUTC", "test", "ElapsedSeconds", 0), ...
    struct("RunCompletion", "failed", "ResultOk", false));
coveragePath = fullfile(runFolder, "reports", "csv", "lls_output_spec_coverage.csv");

coverage = readtable(coveragePath, "VariableNamingRule", "preserve");
detail = readtable(fullfile(runFolder, "reports", "csv", "lls_output_metric_rows.csv"), "VariableNamingRule", "preserve");
inventory = readtable(fullfile(runFolder, "reports", "csv", "artifact_inventory.csv"), "VariableNamingRule", "preserve");
summaryT = readtable(fullfile(runFolder, "reports", "csv", "per_scenario_summary_tables.csv"), "VariableNamingRule", "preserve");
autoMd = string(fileread(fullfile(runFolder, "reports", "automatic_markdown_summary.md")));
execMd = string(fileread(fullfile(runFolder, "reports", "executive_summary.md")));
techMd = string(fileread(fullfile(runFolder, "reports", "technical_report.md")));

assert(all(ismember(["CountsTowardCoverage","CoveredRowCount","ObservedRowCount","DerivedRowCount","ConfigOnlyRowCount","DisabledRowCount","PlaceholderRowCount"], ...
    string(coverage.Properties.VariableNames))), ...
    "Coverage summary must expose semantic state counts and coverage-credit flags.");
assert(all(ismember(["SemanticState","CountsTowardCoverage"], string(inventory.Properties.VariableNames))), ...
    "Artifact inventory must expose semantic state and coverage-credit flags.");

assert(localCoverageState(coverage, "scenario_identifiers") == "config_only", ...
    "Scenario identifiers must roll up as config_only.");
assert(localCoverageState(coverage, "ai_confidence_traces") == "not_supported", ...
    "Suppressed disabled-AI traces must roll up as not_supported.");
assert(localCoverageState(coverage, "curves_access_delay_cdf") == "not_available", ...
    "Missing access-delay evidence must roll up as not_available without a placeholder.");
assert(~localCoverageCredit(coverage, "scenario_identifiers"), ...
    "Config-only metrics must not receive coverage credit.");
assert(~localCoverageCredit(coverage, "ai_confidence_traces"), ...
    "Suppressed disabled metrics must not receive coverage credit.");
assert(~localCoverageCredit(coverage, "curves_access_delay_cdf"), ...
    "Unavailable metrics must not receive coverage credit.");

assert(~any(string(inventory.RelativePath) == "reports/image/ai_confidence_trace.png") && ...
    ~any(string(inventory.RelativePath) == "reports/csv/ai_confidence_trace.csv"), ...
    "Artifact inventory must not claim suppressed disabled-AI artifacts exist.");
assert(~any(string(inventory.RelativePath) == "reports/image/access_delay_cdf.png"), ...
    "Artifact inventory must not claim an unavailable access-delay plot exists.");
assert(localInventoryState(inventory, "reports/csv/lls_output_spec_coverage.csv") == "derived", ...
    "Artifact inventory must mark the coverage CSV as a derived report artifact.");

assert(height(summaryT) == 1, "Per-scenario summary table must contain one row for the smoke run.");
assert(double(summaryT.CoveredMetricCount(1)) == sum(logical(coverage.CountsTowardCoverage)), ...
    "Per-scenario covered-metric count must match the coverage-credit flags.");
assert(double(summaryT.ConfigOnlyMetricCount(1)) == sum(string(coverage.Availability) == "config_only"), ...
    "Per-scenario config-only count must match the coverage summary.");
assert(double(summaryT.DisabledMetricCount(1)) == sum(string(coverage.Availability) == "disabled"), ...
    "Per-scenario disabled count must match the coverage summary.");
assert(double(summaryT.PlaceholderMetricCount(1)) == sum(string(coverage.Availability) == "placeholder"), ...
    "Per-scenario placeholder count must match the coverage summary.");

assert(contains(autoMd, "Observed metrics"), ...
    "Automatic markdown summary must report observed metric counts explicitly.");
assert(contains(execMd, "Config-only metrics"), ...
    "Executive summary must distinguish config-only metrics.");
assert(contains(execMd, "Placeholder artifacts/metrics"), ...
    "Executive summary must distinguish placeholder artifacts.");
assert(contains(techMd, "covered,") && contains(techMd, "config-only"), ...
    "Technical report must summarize category coverage using the semantic states.");

assert(any(string(detail.MetricKey) == "ai_confidence_traces" & string(detail.Availability) == "not_supported"), ...
    "Detail rows must preserve not_supported for suppressed AI confidence traces.");
assert(any(string(detail.MetricKey) == "curves_access_delay_cdf" & string(detail.Availability) == "not_available"), ...
    "Detail rows must preserve not_available for an omitted access-delay plot.");

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

function state = localInventoryState(T, relPath)
mask = string(T.RelativePath) == string(relPath);
assert(any(mask), "Artifact inventory is missing %s.", relPath);
state = string(T.SemanticState(find(mask, 1, "first")));
end
