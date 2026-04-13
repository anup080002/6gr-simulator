function ok = test6GAIBenchmarkReporting()
%TEST6GAIBENCHMARKREPORTING Ensure AI benchmark outputs carry prompt metadata.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(tmp, "ce_ai_reporting.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "scenarios", "ce_ai_nn.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"ce_ai_reporting","description":"ai reporting","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"ai_ml":{"benchmark_observations":2},' ...
    '"output":{"save_figures":false,"save_mat":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
assert(out.Ok, "AI benchmark scenario should complete.");

runFolder = char(string(out.RunFolder));
benchmarkCsv = fullfile(runFolder, "reports", "csv", "ai_channel_estimation_benchmark.csv");
metadataCsv = fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv");
assert(exist(benchmarkCsv, "file") == 2, "Missing AI benchmark CSV.");
assert(exist(metadataCsv, "file") == 2, "Missing AI benchmark metadata CSV.");

T = readtable(benchmarkCsv, 'Delimiter', ',', 'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
requiredVars = ["ModelVersion","ParameterCount","ConfidenceLoggingEnabled","FLOPsBudget", ...
    "RuntimeBudget_us","QuantizationMode","AIEnabled"];
for i = 1:numel(requiredVars)
    assert(ismember(requiredVars(i), T.Properties.VariableNames), ...
        "AI benchmark CSV missing %s.", requiredVars(i));
end

M = readtable(metadataCsv, 'Delimiter', ',', 'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(height(M) == 1, "AI benchmark metadata CSV should contain one row.");
assert(M.AIEnabled(1), "AI benchmark metadata must record AIEnabled=true.");
assert(M.ParameterCount(1) > 0, "AI benchmark metadata must report descriptor parameter count.");

ok = true;
end
