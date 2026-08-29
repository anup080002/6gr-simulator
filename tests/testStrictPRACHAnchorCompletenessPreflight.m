function ok = testStrictPRACHAnchorCompletenessPreflight()
%TESTSTRICTPRACHANCHORCOMPLETENESSPREFLIGHT Partial anchors are not restored.

setup6GRSimToolkit("Verbose", false);
root = tempname;
mkdir(root);
cleanup = onCleanup(@()localRemove(root)); %#ok<NASGU>
sixgr.util.jsonWrite(fullfile(root, "component_anchor_identity.json"), ...
    struct("SchemaName", "sixgr.component_anchor_identity"));
[complete, missing] = sixgr.truth.isStrictPRACHComponentAnchorComplete(root);
assert(~complete && numel(missing) == 4, ...
    "An identity-only PRACH anchor must not be treated as resumable.");

required = [ ...
    fullfile(root, "reports", "json", "prach_conformance_summary.json"); ...
    fullfile(root, "control", "csv", "prach_strict_artifact_manifest.csv"); ...
    fullfile(root, "control", "csv", "prach_config_strict.csv"); ...
    fullfile(root, "control", "csv", "prach_strict_trials.csv")];
for pathValue = string(required).'
    sixgr.util.ensureDir(pathValue);
    fid = fopen(pathValue, "w");
    assert(fid >= 0);
    fclose(fid);
end
[complete, missing] = sixgr.truth.isStrictPRACHComponentAnchorComplete(root);
assert(complete && isempty(missing), ...
    "The preflight must recognize the complete required file set.");
ok = true;
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
