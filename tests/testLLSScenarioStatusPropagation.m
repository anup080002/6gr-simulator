function ok = testLLSScenarioStatusPropagation()
%TESTLLSSCENARIOSTATUSPROPAGATION Scenario-level status must match authoritative link status.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scenarioPath = fullfile(tmp, "status_failure.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_status_propagation_failure","description":"status propagation regression","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":4,"n_slots":4,"monte_carlo_iterations":2,"random_seed":11,"snr_db":-10},' ...
    '"modulation":{"mcs_table":"qam256_table2","dl_modulation_order":8,"ul_modulation_order":8,"dl_mcs_index":27,"ul_mcs_index":27},' ...
    '"link_adaptation":{"fixed_or_amc":"fixed","pdsch_link_adaptation_policy":"fixed","pusch_link_adaptation_policy":"fixed"},' ...
    '"output":{"save_figures":false,"save_png":false,"save_mat":true,"phy_signal_diagnostic_enabled":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "status");
assert(~logical(out.Ok), "Regression scenario must fail so status propagation can be checked.");

runFolder = char(string(out.RunFolder));
scenarioMat = fullfile(runFolder, "reports", "mat", "scenario_result.mat");
linkMat = fullfile(runFolder, "air_interface", "mat", "link_results.mat");
summaryCsv = fullfile(runFolder, "reports", "csv", "scenario_summary.csv");
manifestJson = fullfile(runFolder, "meta", "scenario_manifest.json");
scenarioMd = fullfile(runFolder, "reports", "scenario_report.md");
executiveMd = fullfile(runFolder, "reports", "executive_summary.md");
technicalMd = fullfile(runFolder, "reports", "technical_report.md");
runLog = fullfile(runFolder, "air_interface", "logs", "run.log");

assert(exist(scenarioMat, "file") == 2, "Scenario MAT export is missing.");
assert(exist(linkMat, "file") == 2, "Link MAT export is missing.");
assert(exist(summaryCsv, "file") == 2, "Scenario summary CSV is missing.");
assert(exist(manifestJson, "file") == 2, "Scenario manifest JSON is missing.");
assert(exist(runLog, "file") == 2, "Link run log is missing.");

S = load(scenarioMat);
L = load(linkMat);
summaryT = readtable(summaryCsv, "VariableNamingRule", "preserve");
manifest = jsondecode(fileread(manifestJson));
scenarioReport = string(fileread(scenarioMd));
executiveReport = string(fileread(executiveMd));
technicalReport = string(fileread(technicalMd));
logText = string(fileread(runLog));

assert(isfield(S, "ScenarioStatus"), "Scenario MAT must include ScenarioStatus.");
assert(isfield(S, "Result") && isfield(S.Result, "Link"), "Scenario MAT must include nested link result.");
assert(isfield(L, "details"), "Link MAT must expose the detailed link result payload.");

scenarioOk = logical(S.Result.Ok);
linkNestedOk = logical(S.Result.Link.Result.Ok);
linkMatOk = logical(L.details.Ok);
summaryOk = logical(summaryT.Ok(1));
summaryResultOk = logical(summaryT.ResultOk(1));
manifestOk = logical(manifest.ResultOk);

assert(strcmp(string(summaryT.RunCompletion(1)), "completed_with_failures"), ...
    "Scenario summary RunCompletion must record execution completion with failures explicitly.");
assert(isfield(manifest, "RunCompletion") && string(manifest.RunCompletion) == "completed_with_failures", ...
    "Manifest RunCompletion must record execution completion with failures explicitly.");
assert(isfield(manifest, "RequiredFailureCount") && double(manifest.RequiredFailureCount) > 0, ...
    "Manifest must expose the required failure count for failing scenarios.");

assert(~scenarioOk, "Scenario MAT top-level Result.Ok must fail when the authoritative link result fails.");
assert(~linkNestedOk, "Nested link result must fail in the regression scenario.");
assert(~linkMatOk, "Link MAT details.Ok must fail in the regression scenario.");
assert(~summaryOk && ~summaryResultOk, "Scenario summary CSV must propagate the failing result status.");
assert(~manifestOk, "Scenario manifest must propagate the failing result status.");
requiredSummaryVars = {'FailingCaseCount','WarningCount','ErrorSource','ErrorIdentifier','ErrorMessage','AuthoritativeStatusSource', ...
    'StatusAuthority','RuntimeTruthContractOk','RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount','StrictTruthFailureCount'};
assert(all(ismember(requiredSummaryVars, summaryT.Properties.VariableNames)), ...
    "Scenario summary CSV must expose the richer status-hierarchy provenance fields.");
assert(double(summaryT.FailingCaseCount(1)) >= 1, ...
    "Scenario summary CSV must count at least one failing case for the failing regression scenario.");
assert(strcmpi(char(string(summaryT.StatusAuthority(1))), "scenario_status_aggregation_v2_runtime_truth_contract"), ...
    "Scenario summary CSV must disclose the final runtime-truth-contract status authority.");
assert(~logical(summaryT.RuntimeTruthContractOk(1)), ...
    "Failing regression scenarios with roundtrip/status mismatches must not pass the runtime truth contract.");
assert(double(summaryT.StrictTruthFailureCount(1)) > 0, ...
    "Runtime truth contract failures must contribute to the strict truth failure count.");
assert(strlength(string(summaryT.ErrorSource(1))) > 0 && strlength(string(summaryT.ErrorIdentifier(1))) > 0 && strlength(string(summaryT.ErrorMessage(1))) > 0, ...
    "Scenario summary CSV must preserve the failure source, identifier, and message.");

assert(scenarioOk == linkNestedOk && scenarioOk == linkMatOk && scenarioOk == summaryOk && scenarioOk == summaryResultOk && scenarioOk == manifestOk, ...
    "Scenario CSV/MAT/manifest status must agree with the authoritative link result.");

assert(contains(scenarioReport, "- Run completion: `completed_with_failures`"), ...
    "Scenario markdown report must print the completion flag.");
assert(contains(scenarioReport, "- Result OK: `false`"), ...
    "Scenario markdown report must print the failing result status.");
assert(contains(executiveReport, "- Result OK: `false`"), ...
    "Executive summary must print the failing result status.");
assert(contains(technicalReport, "- Result OK: `false`"), ...
    "Technical report must print the failing result status.");
assert(contains(logText, "failing case(s)"), ...
    "Link log must record the failing case status.");

ok = true;
end
