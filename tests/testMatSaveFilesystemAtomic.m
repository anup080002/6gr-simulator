function ok = testMatSaveFilesystemAtomic()
%TESTMATSAVEFILESYSTEMATOMIC MAT publication is reloadable and leaves no partial file.

root = tempname();
mkdir(root);
cleanupRoot = onCleanup(@() localRemove(root)); %#ok<NASGU>
target = fullfile(root, "nested", "runtime_result.mat");
payload = struct( ...
    "Scalar", 17, ...
    "Matrix", reshape(1:24, 6, 4), ...
    "Text", "same_chain_truth");

sixgr.util.matSave(target, payload);
assert(isfile(target), "MAT artifact was not atomically published.");
loaded = load(target);
assert(isequal(loaded.Scalar, payload.Scalar));
assert(isequal(loaded.Matrix, payload.Matrix));
assert(string(loaded.Text) == payload.Text);

leftovers = dir(fullfile(fileparts(target), "*.mat"));
assert(numel(leftovers) == 1 && string(leftovers(1).name) == "runtime_result.mat", ...
    "MAT publication left a temporary or duplicate artifact.");

localTarget = fullfile(root, "checkpoint", "local_execution_state.mat");
sixgr.util.matSave(localTarget, payload, "UseArtifactStore", false);
assert(isfile(localTarget), ...
    "Filesystem-authoritative execution state was not published locally.");
localLoaded = load(localTarget);
assert(isequal(localLoaded.Matrix, payload.Matrix));
ok = true;
end

function localRemove(root)
if isfolder(root)
    rmdir(root, "s");
end
end
