function ok = test6GScenarioRunner()
%TEST6GSCENARIORUNNER Execute a lightweight single 6G scenario run.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(tmp, "pdcch_smoke.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "scenarios", "pdcch_blind_decode_sweep.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"pdcch_smoke","description":"smoke","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"monte_carlo_iterations":1,"random_seed":7},' ...
    '"run_control":{"auto_start_parallel_pool":false,"num_workers":1},' ...
    '"control":{"aggregation_levels":[1]},' ...
    '"output":{"save_figures":false,"save_mat":true}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
assert(out.Ok, "Single 6G scenario runner should complete.");

runFolder = char(string(out.RunFolder));
assert(exist(fullfile(runFolder, "meta", "scenario_manifest.json"), "file") == 2, "Missing scenario manifest.");
assert(exist(fullfile(runFolder, "meta", "scenario_config_resolved.yaml"), "file") == 2, "Missing resolved YAML snapshot.");
assert(exist(fullfile(runFolder, "meta", "scenario_config_resolved.json"), "file") == 2, "Missing resolved JSON snapshot.");
assert(exist(fullfile(runFolder, "reports", "csv", "scenario_summary.csv"), "file") == 2, "Missing scenario summary CSV.");
assert(exist(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_sweep.csv"), "file") == 2, "Missing PDCCH sweep CSV.");

T = readtable(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_sweep.csv"), ...
    'Delimiter', ',', 'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
assert(ismember("ScenarioID", T.Properties.VariableNames), "ScenarioID must be annotated on CSV outputs.");
assert(ismember("ConfigHash", T.Properties.VariableNames), "ConfigHash must be annotated on CSV outputs.");

manifest = jsondecode(fileread(fullfile(runFolder, "meta", "scenario_manifest.json")));
assert(isfield(manifest, "RandomSeed"), "Scenario manifest must include RandomSeed.");
assert(isfield(manifest, "DeterministicMode"), "Scenario manifest must include DeterministicMode.");
assert(isfield(manifest, "RunnerProfile"), "Scenario manifest must include RunnerProfile.");
assert(isfield(manifest, "RunScope"), "Scenario manifest must include RunScope.");
assert(isfield(manifest, "RunCompletion"), "Scenario manifest must include RunCompletion.");

ok = true;
end
