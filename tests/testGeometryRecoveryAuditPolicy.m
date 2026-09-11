function ok = testGeometryRecoveryAuditPolicy()
% Policy and failed-evidence publication, without rewriting historical runs.
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
cfg = struct();
cfg.validation.run_class = 'adaptive_system_diagnostic';
cfg.canonical_control.launch.geometry_enabled = true;
assert(sixgr.validation.geometryEvidenceRequired(cfg, struct()));
assert(sixgr.validation.geometryEvidenceRequired(struct(), cfg));
disabled = cfg;
disabled.canonical_control.launch.geometry_enabled = false;
assert(~sixgr.validation.geometryEvidenceRequired(disabled, cfg), ...
    'An explicit resolved false must not be replaced by an internal true.');
audit = sixgr.validation.runGeometryScenarioAuditIfNeeded(root, disabled, cfg);
assert(~audit.Required && ~audit.Executed && audit.Status == "not_required");
path = fullfile(root, 'reports', 'csv', 'geometry_runtime_audit.csv');
assert(~isfile(path), 'Disabled geometry must not generate placeholder rows.');
sixgr.util.ensureFolder(fullfile(root, 'meta'));
sixgr.util.jsonWrite(fullfile(root, 'meta', 'scenario_config_resolved.json'), cfg);
audit = sixgr.validation.runGeometryScenarioAuditIfNeeded(root, cfg, struct());
assert(audit.Required && audit.Executed && ~audit.Ok && audit.FailureCount > 0);
assert(isfile(path), 'Incomplete execution must publish its actual failed geometry audit.');
rows = sixgr.util.csvReadTable(path);
assert(any(string(rows.Status) == "FAIL"));
assert(~isfile(fullfile(root, 'geometry', 'csv', 'trajectory_geometry.csv')), ...
    'The audit must not manufacture a missing measured trajectory.');
assert(string(audit.RunClass) == "adaptive_system_diagnostic");
bad = cfg;
bad.canonical_control.launch.geometry_enabled = NaN;
try
    sixgr.validation.geometryEvidenceRequired(bad, struct());
    error('test:ExpectedError', 'Invalid boolean policy was accepted.');
catch ME
    assert(string(ME.identifier) == "sixgr:validation:InvalidGeometryEvidencePolicy");
end
ok = true;
end
