function ok = testRecoveryImmutableConfigAuthority()
%TESTRECOVERYIMMUTABLECONFIGAUTHORITY Recovery rejects mutable YAML drift.

setup6GRSimToolkit("Verbose", false);
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
metaDir = fullfile(root, "meta");
airDir = fullfile(root, "air_interface", "csv");
mkdir(metaDir);
mkdir(airDir);

executed = sixgr.lls6g.config.loadScenarioConfig( ...
    "simulator/configs/scenarios/webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
drifted = sixgr.lls6g.config.loadScenarioConfig( ...
    "simulator/configs/scenarios/master_geometry_based.yaml");
assert(executed.ConfigHash ~= drifted.ConfigHash);
sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_resolved.json"), executed.toStruct());
snapshotPath = fullfile(metaDir, "scenario_config_resolved.json");
fid = fopen(snapshotPath, "r");
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
snapshotDigest = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
clear cleanupFile;
sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_identity.json"), struct( ...
    "SchemaVersion", "sixgr_resolved_config_identity/v1", ...
    "ScenarioID", executed.ScenarioID, ...
    "ConfigHash", executed.ConfigHash, ...
    "ResolvedJSONSHA256", snapshotDigest));
sourceT = table(executed.SourceFiles(:), 'VariableNames', {'SourceConfigFile'});
sixgr.util.csvWriteTable(fullfile(metaDir, "scenario_source_chain.csv"), sourceT);
trialT = table(repmat(executed.ConfigHash, 2, 1), ...
    'VariableNames', {'ConfigHash'});
sixgr.util.csvWriteTable(fullfile(airDir, "prach_trials.csv"), trialT);

[resolved, authority] = sixgr.truth.resolveRecoveryScenarioConfig(root, drifted);
assert(resolved.ConfigHash == executed.ConfigHash && authority.ExactMatch && ...
    authority.Authority == "persisted_resolved_config_snapshot", ...
    ["Recovery must use the persisted exact config instead of a later supplied YAML revision. " + ...
    "resolved=%s executed=%s expected=%s persisted=%s supplied=%s authority=%s exact=%d"], ...
    char(resolved.ConfigHash), char(executed.ConfigHash), ...
    char(authority.ExpectedConfigHash), char(authority.PersistedSnapshotHash), ...
    char(authority.SuppliedConfigHash), char(authority.Authority), authority.ExactMatch);

% Legacy runners stored report-only fields in the resolved snapshot.  The
% file remains digest-checked but cannot be executable config authority;
% recovery must select an exact supplied configuration with the same
% runtime-bound ConfigHash.
legacyView = executed.toStruct();
legacyView.reporting_semantics = struct("configured_parameters_are_nominal", true);
legacyView.resolved_runtime_view = struct("active_grid_num_rbs", 273);
sixgr.util.jsonWrite(snapshotPath, legacyView);
fid = fopen(snapshotPath, "r");
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
legacyDigest = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
clear cleanupFile;
sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_identity.json"), struct( ...
    "SchemaVersion", "sixgr_resolved_config_identity/v1", ...
    "ScenarioID", executed.ScenarioID, ...
    "ConfigHash", executed.ConfigHash, ...
    "ResolvedJSONSHA256", legacyDigest));
[resolvedLegacy, legacyAuthority] = ...
    sixgr.truth.resolveRecoveryScenarioConfig(root, executed);
assert(resolvedLegacy.ConfigHash == executed.ConfigHash && ...
    legacyAuthority.ExactMatch && ...
    legacyAuthority.Authority == "supplied_exact_resolved_config", ...
    "Legacy derived snapshots must fall back only to exact executable configuration authority.");

sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_resolved.json"), drifted.toStruct());
caught = false;
try
    sixgr.truth.resolveRecoveryScenarioConfig(root, drifted);
catch ME
    caught = ismember(string(ME.identifier), [ ...
        "sixgr:truth:recover:ImmutableConfigUnavailable", ...
        "sixgr:truth:recover:ResolvedConfigSnapshotDigestMismatch"]);
end
assert(caught, ...
    "Recovery must fail closed when neither available resolved config matches runtime evidence.");
ok = true;
end
