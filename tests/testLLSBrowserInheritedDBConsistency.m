function ok = testLLSBrowserInheritedDBConsistency()
%TESTLLSBROWSERINHERITEDDBCONSISTENCY Inherited browser-overlay values stay truth-consistent.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot.yaml");
scenarioPath = fullfile(tmp, "__web_runtime_inherited_snr_focus.yaml");
fid = fopen(scenarioPath, "w");
assert(fid >= 0, "Unable to create focused browser overlay scenario.");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_browser_inherited_db_consistency","description":"browser overlay inherits base SNR","version":"1","owner":"test","maturity_tag":"baseline"},' ...
    '"run_control":{"execution_mode":"LLS","num_workers":1},' ...
    '"deployment_topology":{"num_cells":3,"num_ues":4,"num_trps":3},' ...
    '"users":{"enabled":true,"n_users":4,"execution_model":"slot_coupled_truth","save_user_tables":true},' ...
    '"output":{"backend":"filesystem","profile":"lls_browser_inherited_db_consistency","save_figures":false,"save_png":false,"save_mat":false}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
artifacts = sixgr.truth.exportLLSConfigOwnershipArtifacts(fullfile(tmp, "run"), scfg, cfg);

roundtripT = localReadVerificationCSV(char(artifacts.ConfigRoundtripVerification));
browserDbT = localReadVerificationCSV(char(artifacts.BrowserRuntimeDBConsistency));

localAssertInheritedDBUnavailableIsConsistent(roundtripT, "simulation.snr_db");
localAssertInheritedDBUnavailableIsConsistent(browserDbT, "simulation.snr_db");
assert(~any(strcmp(string(browserDbT.ConsistencyStatus), "db_snapshot_unavailable")), ...
    "Browser/runtime/DB consistency must not fail base-inherited browser-overlay values when DB snapshot is absent.");

ok = true;
end

function localAssertInheritedDBUnavailableIsConsistent(T, parameterName)
mask = strcmp(string(T.ParameterName), string(parameterName));
assert(nnz(mask) == 1, "Expected parameter %s exactly once.", parameterName);
row = T(find(mask, 1, "first"), :);
status = lower(strtrim(string(row.ConsistencyStatus)));
notes = lower(strtrim(string(row.ConsistencyNotes)));
assert(startsWith(status, "consistent"), ...
    "Inherited parameter %s must remain truth-contract consistent, got %s.", parameterName, status);
if ismember("DBSnapshotValue", string(T.Properties.VariableNames))
    assert(strlength(strtrim(string(row.DBSnapshotValue))) == 0, ...
        "Regression setup for %s must exercise the DB-snapshot-absent path.", parameterName);
end
assert(contains(notes, "db_snapshot_unavailable") || contains(status, "db_unavailable") || ...
    contains(status, "db_inactive"), ...
    "Inherited parameter %s must disclose DB snapshot absence without failing consistency.", parameterName);
end

function T = localReadVerificationCSV(filePath)
opts = detectImportOptions(filePath, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
opts = setvartype(opts, opts.VariableNames, "string");
T = readtable(filePath, opts);
end
